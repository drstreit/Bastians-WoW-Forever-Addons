-- What the game's tracking finds (Find Herbs, Find Minerals, tracked creatures) on Bastian's own
-- minimap styles. Our tiles cover the game's minimap there and no API tells where its dots are;
-- the client only answers what the minimap's tooltip would say at a point
-- (Minimap:UpdateMouseoverAtPoint, C_TooltipInfo.GetMinimapMouseover). A sweep asks that over a
-- grid of the covered minimap, groups the points that answered the same name, and turns each
-- group's centre into world yards by the game minimap's own geometry: its size in our view and its
-- own zoom, never the camera's (our view is scaled, round or square, and zoomed
-- on its own). The pins then go through the overlay like every other layer's. Polling where no
-- event exists (CLAUDE.md rule 7): only while our frame shows one of our styles, a few frames per
-- sweep, nothing in the game's style, where the dots show by themselves.
local _, ns = ...
local B = Bastians
local Map = ns.Map -- the hook lists (Map.lua); `mod` below is the module once enabled
local L = ns.L
local mod

local Tracked = {}

Tracked.LAYER = "map.tracked"
Tracked.STEP = 8 -- minimap pixels between two probe points (a dot answers 10 to 20 around it)
Tracked.PER_FRAME = 48 -- probe points per frame
Tracked.WAIT = 1.2 -- seconds between two sweeps
Tracked.KEEP = 2 -- sweeps a known dot survives unseen before its pin goes
Tracked.SAME = 12 -- yards: a dot found this close to a known one of the same name is that one
Tracked.MOVED = 1 -- yards: a known dot moved less than this keeps the overlay as it is
Tracked.stats = { sweeps = 0, probes = 0, known = 0 }
-- a node kind of the data (Data's node records) -> the glyph of its pin
Tracked.GLYPH = { herb = "herb", ore = "mine", fish = "fish", treasure = "treasure" }

local driver -- the frame whose OnUpdate runs a sweep
local sweep -- the sweep in progress: { points, i, hits, cx, cy, scale }
local known = {} -- the dots found so far: { ref, name, continent, wx, wy, missed }
local counter = 0
local nextAt = 0 -- GetTime() of the next sweep
local broken -- the game raised an error during a sweep: no more sweeps this session
local byName -- lower-cased node name -> node record of the data, built on first use

local function db()
  return mod and mod.db and mod.db.profile or {}
end

local function cvarBool(name)
  local get = C_CVar and C_CVar.GetCVar or rawget(_G, "GetCVar")
  local v = get and get(name)
  return v == "1" or v == 1 or v == true
end

-- Whether this client answers the minimap's tooltip at a point; else the reason, for the settings.
function Tracked.Available()
  if broken then
    return nil, L["the game refused the minimap sweep; it rests until the next login"]
  end
  if
    not (
      Minimap
      and type(Minimap.UpdateMouseoverAtPoint) == "function"
      and type(Minimap.SetUsingSoftCursor) == "function"
      and C_TooltipInfo
      and type(C_TooltipInfo.GetMinimapMouseover) == "function"
    )
  then
    return nil, L["this client does not let an addon read the minimap's dots"]
  end
  return true
end

-- Whether a sweep is wanted now: the setting, our frame showing one of our styles.
function Tracked.Active()
  if db().miniTracked == false then
    return false
  end
  return ns.Mini.Taken() and ns.Mini.Style() ~= "game"
end

function Tracked.Running()
  return driver ~= nil and driver:GetScript("OnUpdate") ~= nil
end

-- --- pure -------------------------------------------------------------------------------------

-- Groups of grid points that touch (8-neighbourhood at the grid's step): { u, v, n } each, the
-- centre of every group and how many points it holds.
function Tracked.Cluster(points, step)
  local reach = step * 1.5
  local group = {}
  local groups = {}
  for i, p in ipairs(points) do
    local g
    for j = 1, i - 1 do
      local q = points[j]
      if math.abs(p[1] - q[1]) <= reach and math.abs(p[2] - q[2]) <= reach then
        local other = group[j]
        if g == nil then
          g = other
        elseif other ~= g then
          -- two groups touch through this point: the second joins the first
          for k = 1, i - 1 do
            if group[k] == other then
              group[k] = g
            end
          end
        end
      end
    end
    if g == nil then
      g = #groups + 1
      groups[g] = true
    end
    group[i] = g
  end
  local sums = {}
  for i, p in ipairs(points) do
    local g = group[i]
    local s = sums[g]
    if not s then
      s = { u = 0, v = 0, n = 0 }
      sums[g] = s
    end
    s.u, s.v, s.n = s.u + p[1], s.v + p[2], s.n + 1
  end
  local out = {}
  for _, s in pairs(sums) do
    out[#out + 1] = { u = s.u / s.n, v = s.v / s.n, n = s.n }
  end
  table.sort(out, function(a, b)
    if a.u ~= b.u then
      return a.u < b.u
    end
    return a.v < b.v
  end)
  return out
end

-- A point du right, dv up (pixels from the game minimap's centre) as world yards: the inverse of
-- the overlay's Project (world wx grows north and wy west; a rotating minimap turns by the facing).
function Tracked.ToWorld(du, dv, pxPerYard, facing, px, py)
  local east, north = du / pxPerYard, dv / pxPerYard
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    east, north = east * c - north * s, east * s + north * c
  end
  return px + north, py - east
end

-- --- the data's node of a dot's name ----------------------------------------------------------

local function nodeOf(name)
  if not byName then
    byName = {}
    local d = B:GetService("data")
    if d and d.Each and d.Get then
      for _, id in ipairs(d:Each("node") or {}) do
        local r = d:Get("node", id)
        local n = r and r.name and string.lower(r.name)
        if n and byName[n] == nil then
          byName[n] = r
        end
      end
    end
  end
  return byName[string.lower(name)]
end

local function iconOf(name)
  local r = nodeOf(name)
  return B.UI.IconTexture(r and Tracked.GLYPH[r.kind] or "other")
end

-- --- the sweep --------------------------------------------------------------------------------

local function gridPoints(half, shape)
  local points = {}
  local step = Tracked.STEP
  local limit = half - 2
  local v = -half + step / 2
  while v < half do
    local u = -half + step / 2
    while u < half do
      if shape == "SQUARE" or u * u + v * v <= limit * limit then
        points[#points + 1] = { u, v }
      end
      u = u + step
    end
    v = v + step
  end
  return points
end

local function begin()
  local w = Minimap:GetWidth()
  local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
  local scale = Minimap:GetEffectiveScale()
  if not (w and w > 0 and left and bottom and scale and scale > 0) then
    nextAt = GetTime() + Tracked.WAIT
    return false
  end
  sweep = {
    points = gridPoints(w / 2, ns.Mini.Shape()),
    i = 1,
    hits = {},
    cx = left + w / 2,
    cy = bottom + (Minimap:GetHeight() or w) / 2,
    scale = scale,
  }
  Minimap:SetUsingSoftCursor(true)
  return true
end

local function probe(p)
  Minimap:UpdateMouseoverAtPoint((sweep.cx + p[1]) * sweep.scale, (sweep.cy + p[2]) * sweep.scale)
  local data = C_TooltipInfo.GetMinimapMouseover()
  for _, line in ipairs(data and data.lines or {}) do
    local name = B.Compat.Plain(line.leftText)
    if type(name) == "string" and name ~= "" then
      local hits = sweep.hits[name]
      if not hits then
        hits = {}
        sweep.hits[name] = hits
      end
      hits[#hits + 1] = p
    end
  end
end

-- The dots of a sweep against the known ones: a known dot found again keeps its pin (and takes
-- the better place), an unseen one survives KEEP sweeps, a new one gets a pin.
local function finish()
  local hits = sweep.hits
  Minimap:SetUsingSoftCursor(false)
  sweep = nil
  nextAt = GetTime() + Tracked.WAIT
  Tracked.stats.sweeps = Tracked.stats.sweeps + 1
  local continent, px, py = B.Coords.Player()
  if not continent then
    if #known > 0 then
      known = {}
      ns.Minimap.Schedule()
    end
    return
  end
  local pxPerYard = ns.Minimap.Scale()
  local facing = cvarBool("rotateMinimap") and (B.Compat.GetPlayerFacing() or 0) or nil
  local found = {}
  for name, points in pairs(hits) do
    for _, g in ipairs(Tracked.Cluster(points, Tracked.STEP)) do
      local wx, wy = Tracked.ToWorld(g.u, g.v, pxPerYard, facing, px, py)
      found[#found + 1] = { name = name, wx = wx, wy = wy }
    end
  end
  local changed = false
  local same2 = Tracked.SAME * Tracked.SAME
  local kept = {}
  for _, k in ipairs(known) do
    local best, bestD
    for _, f in ipairs(found) do
      if not f.used and f.name == k.name and k.continent == continent then
        local dx, dy = f.wx - k.wx, f.wy - k.wy
        local d = dx * dx + dy * dy
        if d <= same2 and (not bestD or d < bestD) then
          best, bestD = f, d
        end
      end
    end
    if best then
      best.used = true
      if bestD > Tracked.MOVED * Tracked.MOVED then
        k.wx, k.wy = best.wx, best.wy
        changed = true
      end
      k.missed = 0
      kept[#kept + 1] = k
    else
      k.missed = k.missed + 1
      if k.missed <= Tracked.KEEP then
        kept[#kept + 1] = k
      else
        changed = true
      end
    end
  end
  for _, f in ipairs(found) do
    if not f.used then
      counter = counter + 1
      kept[#kept + 1] = {
        ref = "tracked:" .. counter,
        name = f.name,
        continent = continent,
        wx = f.wx,
        wy = f.wy,
        missed = 0,
      }
      changed = true
    end
  end
  known = kept
  Tracked.stats.known = #known
  if changed then
    ns.Minimap.Schedule()
  end
end

local function onUpdate()
  if not Tracked.Active() then
    Tracked.Stop()
    return
  end
  if not sweep then
    if GetTime() < nextAt or not begin() then
      return
    end
  end
  local points = sweep.points
  for _ = 1, Tracked.PER_FRAME do
    local p = points[sweep.i]
    if not p then
      break
    end
    local ok, err = pcall(probe, p)
    Tracked.stats.probes = Tracked.stats.probes + 1
    if not ok then
      -- the game refused (a secret or forbidden value): this session sweeps no more
      broken = tostring(err)
      B:Log(mod, "warn", "minimap sweep stopped: %s", broken)
      Tracked.Stop()
      return
    end
    sweep.i = sweep.i + 1
  end
  if sweep.i > #points then
    finish()
  end
end

-- Starts or stops the sweeps as the style and the setting want (Mini.Render calls this).
function Tracked.Sync()
  if Tracked.Active() and Tracked.Available() then
    if not driver then
      driver = CreateFrame("Frame")
    end
    if not Tracked.Running() then
      nextAt = 0
      driver:SetScript("OnUpdate", onUpdate)
    end
  else
    Tracked.Stop()
  end
end

-- No more sweeps; the pins of the dots go (the game's own minimap shows them again).
function Tracked.Stop()
  if driver then
    driver:SetScript("OnUpdate", nil)
  end
  if sweep then
    pcall(Minimap.SetUsingSoftCursor, Minimap, false)
    sweep = nil
  end
  if #known > 0 then
    known = {}
    Tracked.stats.known = 0
    ns.Minimap.Schedule()
  end
end

-- The layer's pins: the dots as pins on the minimap only (the big map has the nodes layer).
function Tracked.Query(view)
  if not view.minimap or not Tracked.Active() then
    return {}
  end
  local pins = {}
  for _, k in ipairs(known) do
    if k.continent == view.continent then
      pins[#pins + 1] = {
        kind = "tracked",
        ref = k.ref,
        wx = k.wx,
        wy = k.wy,
        icon = iconOf(k.name),
        label = k.name,
        priority = 60,
        card = function(pin)
          return { title = pin.label, lines = { { text = L["Found by the game's tracking"] } }, hint = "" }
        end,
      }
    end
  end
  return pins
end

-- The settings' note under the switch.
function Tracked.Note()
  local ok, why = Tracked.Available()
  if ok then
    return nil
  end
  return why
end

function Tracked.Known()
  return known
end

-- New data (the packs loaded): the names are looked up again.
function Tracked.Reset()
  byName = nil
end

ns.Tracked = Tracked
ns.mod.Tracked = Tracked

table.insert(Map.onEnable, function(self)
  mod = self
  B:RegisterMapLayer(self, {
    id = Tracked.LAYER,
    icon = "herb",
    label = L["Tracked by the game's minimap"],
    defaultOn = true,
    minLevel = 0,
    query = Tracked.Query,
  })
end)
table.insert(Map.onSetting, function(key)
  if key == "miniTracked" then
    Tracked.Sync()
  end
end)
