-- Bastian's Helpers, the rare finder (helpers.md "The rare finder", "I
-- did not get an alarm like a rare finder - can we have that? marking them on all maps and as alarm
-- with arrow where it is"): a rare the client names (its nameplate, the target, the mouse, its own
-- words) sounds the raid warning and shows a banner with Arrow and Map, once in ten minutes; it
-- stays on the big map and the minimap for five minutes (layer helpers.rares); every known rare
-- spawn is a second layer, off by default. Names stay in RAM.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Helpers = ns.Helpers
local Model = Helpers.Model

local Rares = {}
ns.Rares = Rares
Helpers.Rares = Rares

Rares.AGAIN = 600 -- seconds before the same rare sounds again
Rares.LIVE = 300 -- seconds a spotted rare stays on the maps
Rares.NEAR = 300 -- yards: a known spawn of the rare this close to the player is where it stands
Rares.BANNER = 12 -- seconds the banner stays
Rares.KIT = 8959 -- the raid warning's sound (as the Map's timers)
Rares.LAYER, Rares.SPAWNS = "helpers.rares", "helpers.rarespawns"

local spotted = {} -- npc id -> { ref, id, name, level, at, continent, wx, wy, known }
local spawns -- the known rare spawns once read: { [continent] = { { ref, wx, wy, label } } }
local reading -- the job reading them
local banner
local hideTimer
local mod

local function now()
  return GetTime()
end

-- The rare behind a unit, or nil: the data's flag, or the client's own word for it.
function Rares.Of(unit)
  local ref = B.Compat.UnitEntity(unit)
  local typ, id = B.Entity.Parse(ref or "")
  if typ ~= "npc" or not id then
    return nil
  end
  local d = B:GetService("data")
  local r = d and d:Get("npc", id) or nil
  local rank = B.Compat.UnitClassification(unit)
  if (r and Model.IsRare(r.flags)) or rank == "rare" or rank == "rareelite" then
    return ref, id, r
  end
  return nil
end

-- The nearest known spawn of a rare to the player on the player's continent, within NEAR.
local function nearestSpawn(r, c, px, py)
  local best, bestD
  for _, sp in ipairs(r and r.spawns or {}) do
    local sc, wx, wy = B.Coords.ToWorld(tonumber(sp[1]), tonumber(sp[2]), tonumber(sp[3]))
    if sc and sc == c and wx then
      local dd = (wx - px) ^ 2 + (wy - py) ^ 2
      if not bestD or dd < bestD then
        best, bestD = { wx, wy }, dd
      end
    end
  end
  if best and bestD <= Rares.NEAR ^ 2 then
    return best
  end
  return nil
end

local function actionButton(id, label, ref)
  if not B:GetAction(id) then
    return nil
  end
  return {
    label = label,
    run = function()
      B:RunAction(id, ref, { source = "helpers.rares" })
    end,
  }
end

local function hideBanner()
  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end
  if banner then
    banner:Hide()
  end
end

local function buildBanner()
  local f = CreateFrame("Frame", "BastiansRareBanner", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetSize(380, 74)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  S.panel(f, S.C.panel)
  f.edges:Hide()
  f.rim = S.roundEdges(f, S.C.rare, "radius")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(30, 30)
  f.icon:SetPoint("LEFT", 12, 8)
  f.title = S.text(f, 16, S.C.rare)
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 4)
  f.title:SetPoint("RIGHT", -34, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.sub = S.text(f, 12, S.C.dim)
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetPoint("RIGHT", -34, 0)
  f.sub:SetJustifyH("LEFT")
  f.sub:SetWordWrap(false)
  f.close = S.action(f, { icon = "close", only = true })
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", hideBanner)
  f.buttons = {}
  f:Hide()
  return f
end

-- The banner: the rare, where it is, Arrow and Map where their apps are there.
function Rares.Banner(seen)
  banner = banner or buildBanner()
  B.UI.PaintIcon(banner.icon, B.UI.IconTexture("rare"))
  S.tint(banner.icon, S.C.rare)
  banner.title:SetText(string.format(L["Rare nearby: %s"], seen.name))
  local where = seen.known and L["at its known place"] or L["somewhere near you"]
  banner.sub:SetText(seen.level and (string.format(L["Level %d"], seen.level) .. " - " .. where) or where)
  for _, b in ipairs(banner.buttons) do
    b:Hide()
  end
  local specs = {
    actionButton("route.to", L["Arrow"], seen.ref),
    actionButton("map.show", L["Map"], seen.ref),
  }
  local x = 52
  local n = 0
  for _, spec in pairs(specs) do
    n = n + 1
    local b = banner.buttons[n]
    if not b then
      b = S.action(banner, { label = spec.label })
      banner.buttons[n] = b
    end
    b:SetLabel(spec.label)
    if b.Fit then
      b:Fit()
    end
    b:SetScript("OnClick", function()
      spec.run()
      hideBanner()
    end)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", x, 8)
    b:Show()
    x = x + (b:GetWidth() or 80) + 6
  end
  banner:Show()
  if hideTimer then
    hideTimer:Cancel()
  end
  hideTimer = C_Timer.NewTimer(Rares.BANNER, hideBanner)
  return banner
end

-- A rare spotted: the alarm once in AGAIN, its place on the maps for LIVE. `ref`, `id`, `r` as
-- Rares.Of gives them. -> true when it sounded.
function Rares.Spot(ref, id, r)
  if not Helpers.On("warnRares") then
    return false
  end
  local t = now()
  local seen = spotted[id]
  if seen and t - seen.at < Rares.AGAIN then
    return false
  end
  local c, px, py = B.Coords.Player()
  local at = c and nearestSpawn(r, c, px, py) or nil
  seen = {
    ref = ref,
    id = id,
    name = B:Entity(ref):Name() or (r and r.name) or ref,
    level = r and tonumber(r.level) or nil,
    at = t,
    continent = c,
    wx = at and at[1] or px,
    wy = at and at[2] or py,
    known = at ~= nil,
  }
  spotted[id] = seen
  if Helpers.On("rareSound") then
    B.Compat.PlayKit(Rares.KIT)
  end
  Rares.Banner(seen)
  -- the line in the strip and the addon chat, as every helper's (with the Map where it is there)
  Helpers.Notice(string.format(L["Rare: %s"], seen.name), actionButton("map.show", L["Map"], ref))
  B:Fire("BASTIANS_LAYER_CHANGED", Rares.LAYER)
  C_Timer.After(Rares.LIVE + 1, function()
    B:Fire("BASTIANS_LAYER_CHANGED", Rares.LAYER) -- it leaves the maps
  end)
  return true
end

-- A unit the client names now (a nameplate, the target, the mouse). -> the rare's ref, or nil.
function Rares.Check(unit)
  if not Helpers.On("warnRares") then
    return nil
  end
  local ref, id, r = Rares.Of(unit)
  if ref and Rares.Spot(ref, id, r) then
    return ref
  end
  return nil
end

-- A creature spoke (CHAT_MSG_MONSTER_SAY, _YELL, _EMOTE): its GUID says who.
function Rares.OnWords(guid)
  if not Helpers.On("warnRares") then
    return nil
  end
  local ref = B.Compat.EntityFromGUID(B.Compat.Plain(guid))
  local typ, id = B.Entity.Parse(ref or "")
  local d = B:GetService("data")
  local r = typ == "npc" and d and d:Get("npc", id) or nil
  if r and Model.IsRare(r.flags) and Rares.Spot(ref, id, r) then
    return ref
  end
  return nil
end

function Rares.Spotted()
  return spotted
end

-- The layer of spotted rares: each for LIVE at its place.
local function liveQuery(view)
  local out = {}
  local t = now()
  for _, seen in pairs(spotted) do
    if
      t - seen.at < Rares.LIVE
      and seen.continent == view.continent
      and seen.wx
      and seen.wx >= view.x1
      and seen.wx <= view.x2
      and seen.wy >= view.y1
      and seen.wy <= view.y2
    then
      out[#out + 1] = {
        ref = seen.ref,
        wx = seen.wx,
        wy = seen.wy,
        icon = B.UI.IconTexture("rare"),
        color = S.C.rare,
        label = seen.name,
        priority = 90,
        radius = seen.known and 30 or 60,
      }
    end
  end
  return out
end

-- Reads every known rare spawn once, in a job (the first time the layer of known spawns is asked).
local function readSpawns()
  local d = B:GetService("data")
  if reading or not d then
    return
  end
  reading = B.Jobs:Run(mod, "rarespawns", function(yield)
    local out = {}
    local ids = d:Each("npc")
    for i, id in ipairs(ids) do
      local r = d:Get("npc", id)
      if r and Model.IsRare(r.flags) then
        local label = r.level and string.format("%s (%d)", r.name or "?", r.level) or r.name
        for _, sp in ipairs(r.spawns or {}) do
          local c, wx, wy = B.Coords.ToWorld(tonumber(sp[1]), tonumber(sp[2]), tonumber(sp[3]))
          if c and wx then
            out[c] = out[c] or {}
            table.insert(out[c], { ref = "npc:" .. id, wx = wx, wy = wy, label = label })
          end
        end
      end
      if i % 400 == 0 then
        yield()
      end
    end
    spawns = out
    B:Fire("BASTIANS_LAYER_CHANGED", Rares.SPAWNS)
  end)
end

local function spawnQuery(view)
  if not spawns then
    readSpawns()
    return {}
  end
  local out = {}
  for _, sp in ipairs(spawns[view.continent] or {}) do
    if sp.wx >= view.x1 and sp.wx <= view.x2 and sp.wy >= view.y1 and sp.wy <= view.y2 then
      out[#out + 1] = {
        ref = sp.ref,
        wx = sp.wx,
        wy = sp.wy,
        icon = B.UI.IconTexture("rare"),
        color = S.C.rare,
        label = sp.label,
        priority = 40,
        cluster = true,
      }
    end
  end
  return out
end

function Rares.Attach(m)
  mod = m
  B:RegisterMapLayer(m, {
    id = Rares.LAYER,
    label = L["Rares spotted"],
    icon = "rare",
    defaultOn = true,
    minLevel = 0,
    maxLevel = 8,
    query = liveQuery,
  })
  B:RegisterMapLayer(m, {
    id = Rares.SPAWNS,
    label = L["Known rare spawns"],
    icon = "rare",
    defaultOn = false, -- the layer starts off
    minLevel = 2,
    maxLevel = 8,
    query = spawnQuery,
  })
  m:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit)
    Rares.Check(unit)
  end)
  for _, event in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE" }) do
    m:RegisterEvent(event, function(_, _, ...)
      Rares.OnWords((select(12, ...))) -- text, speaker, ..., the speaker's GUID twelfth
    end)
  end
end
