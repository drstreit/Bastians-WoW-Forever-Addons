-- Bastian's Map: the player button's menu (map.md "The player button", R26.16): the last place of
-- every character of the account, as menu entries and as the layer "My characters", and sharing
-- where I stand with the group, the guild or a friend through the `notes` service (never a direct
-- call into Notes). Only the account's own characters are stored.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Map = ns.Map

local Chars = {}
ns.Characters = Chars

Chars.LAYER = "map.characters"
Chars.MAX_FRIENDS = 8 -- online friends offered in the menu at most
Chars.FLY_LEVEL = 3

local mod

local function store()
  return mod.db.global.characters
end

local function key()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Remembers where this character stands: continent, world position, map, zone, level and the
-- server time; nil without a map position (an instance).
function Chars.Remember()
  if not mod then
    return nil
  end
  local c, wx, wy, map = B.Coords.Player()
  if not c then
    return nil
  end
  local facts = B.Compat.GetPlayerFacts()
  local rec = store()[key()] or {}
  rec.name, rec.realm = UnitName("player"), GetRealmName()
  rec.continent, rec.wx, rec.wy, rec.map = c, wx, wy, map
  rec.zone = map and B:Entity("zone:" .. map):Name() or rec.zone
  rec.level, rec.classID = facts.level, facts.classID
  rec.at = B.Compat.ServerTime()
  store()[key()] = rec
  return rec
end

-- The characters of the account with a place, the most recent first; `others` leaves this one out.
function Chars.List(others)
  local me = key()
  local out = {}
  for k, rec in pairs(store()) do
    if rec.continent and not (others and k == me) then
      out[#out + 1] = rec
    end
  end
  table.sort(out, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then
      return (a.at or 0) > (b.at or 0)
    end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

-- "just now", "12 min ago", "3 h ago", "2 d ago"
function Chars.Ago(at)
  local d = B.Compat.ServerTime() - (at or 0)
  if d < 90 then
    return L["just now"]
  elseif d < 5400 then
    return string.format(L["%d min ago"], math.floor(d / 60 + 0.5))
  elseif d < 172800 then
    return string.format(L["%d h ago"], math.floor(d / 3600 + 0.5))
  end
  return string.format(L["%d d ago"], math.floor(d / 86400 + 0.5))
end

-- The name, with the realm when it is another one.
function Chars.Label(rec)
  local name = rec.name or "?"
  if rec.realm and rec.realm ~= GetRealmName() then
    name = name .. " (" .. rec.realm .. ")"
  end
  return name
end

local function pins(view)
  local out = {}
  for _, rec in ipairs(Chars.List(true)) do
    if rec.continent == view.continent then
      local r = rec
      out[#out + 1] = {
        ref = r.map and ("zone:" .. r.map) or nil,
        wx = r.wx,
        wy = r.wy,
        icon = B.UI.GLYPH_PATHS.waypoint,
        color = S.C.good,
        label = Chars.Label(r),
        priority = 85,
        cluster = false,
        size = 20,
        card = function()
          return {
            title = Chars.Label(r),
            lines = { { text = (r.zone or "?") .. ", " .. Chars.Ago(r.at), color = "dim" } },
          }
        end,
      }
    end
  end
  return out
end

-- Who my location can go to: the group, the guild, the online friends; each { label, channel,
-- target }; a single disabled line when there is nobody, or no Notes to carry it.
function Chars.ShareTargets()
  local out = {}
  local notes = B:GetService("notes")
  if not (notes and notes.SendHere) then
    out[1] = { label = L["Bastian's Notes is needed to share."], disabled = true }
    return out
  end
  local group = B.Compat.GroupChannel()
  if group then
    out[#out + 1] = { label = L["With my group"], channel = group }
  end
  if B.Compat.InGuild() then
    out[#out + 1] = { label = L["With my guild"], channel = "GUILD" }
  end
  local n = 0
  for _, f in ipairs(B.Compat.Friends()) do
    if f.online and n < Chars.MAX_FRIENDS then
      n = n + 1
      out[#out + 1] = { label = string.format(L["With %s"], f.name), channel = "WHISPER", target = f.name }
    end
  end
  if #out == 0 then
    out[1] = { label = L["No group, guild or friend online."], disabled = true }
  end
  return out
end

-- Sends where I stand; -> true, or nil and why.
function Chars.Share(channel, target)
  local notes = B:GetService("notes")
  if not (notes and notes.SendHere) then
    return nil, "notes"
  end
  return notes:SendHere(channel, target)
end

-- The menu: my characters, then the share entries.
function Chars.MenuItems()
  local items = { { label = L["My characters"], header = true } }
  local list = Chars.List(false)
  if #list == 0 then
    items[#items + 1] = { label = L["No position known yet."], disabled = true }
  end
  for _, rec in ipairs(list) do
    local r = rec
    items[#items + 1] = {
      label = string.format("%s: %s, %s", Chars.Label(r), r.zone or L["unknown"], Chars.Ago(r.at)),
      icon = B.UI.IconTexture("waypoint"),
      onClick = function()
        Map.Fly(r.continent, r.wx, r.wy, Chars.FLY_LEVEL)
      end,
    }
  end
  items[#items + 1] = { label = L["Share my location"], header = true }
  for _, t in ipairs(Chars.ShareTargets()) do
    local tt = t
    items[#items + 1] = {
      label = tt.label,
      icon = B.UI.IconTexture("spot"),
      disabled = tt.disabled,
      onClick = tt.channel and function()
        Chars.Share(tt.channel, tt.target)
      end or nil,
    }
  end
  return items
end

function Chars.OpenMenu(anchor)
  Chars.Remember()
  return B.UI.Menu(anchor, L["Player"], Chars.MenuItems(), mod)
end

table.insert(Map.onEnable, function(self)
  mod = self
  self.db.global.characters = self.db.global.characters or {}
  B:RegisterMapLayer(self, {
    id = Chars.LAYER,
    icon = "spot", -- the layer bar shows its icon (R27.8)
    label = L["My characters"],
    tip = L["Where the other characters of your account were last seen."],
    defaultOn = true,
    minLevel = 0,
    query = pins,
  })
end)
table.insert(Map.onZone, Chars.Remember)
table.insert(Map.onWorld, Chars.Remember)
table.insert(Map.onLogout, Chars.Remember)
table.insert(Map.onBuild, function()
  Chars.Remember()
end)
ns.mod.Characters = Chars
