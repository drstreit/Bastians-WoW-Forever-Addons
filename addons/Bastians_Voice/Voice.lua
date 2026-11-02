-- Bastian's Voice, the namespace and the pure model (voice.md): the orbit's arrangement, the bearing
-- of a thing from the player, what a quest is to the player now, where the panel sits on the screen.
-- Plain tables in, plain tables out; no WoW API in this file.
local _, ns = ...

local Voice = { Model = {} }
ns.Voice = Voice
local Model = Voice.Model

-- The wide orbit in design units: the frame's scale maps them to the screen (voice.md §5).
Voice.BASE = 300 -- the wide diameter
Voice.COMPACT = 0.55 -- the compact size as a share of the wide one
Voice.LIMITS = { places = 6, outer = 7, moons = 4 }
Voice.RADII = {
  inner = 64, -- the places' orbit
  outer = 109, -- the givers', bosses' and readables' orbit
  hub = 31, -- the controls in the middle
  moon = 19, -- a quest moon's distance from its giver
  place = 20, -- the dungeon and the zone
  here = 16, -- the area the player stands in
  area = 12, -- the zone's other areas
  giver = 12,
  moonBubble = 7,
  boss = 9,
  read = 9,
  plus = 9,
}
Voice.MIN_GAP = 30 -- degrees between two outer bubbles

-- The order of a quest's status on the orbit: what the player can act on now first.
local RANK = { ready = 0, log = 1, available = 2 }

-- Spoken Places' key of an area name (its NormaliseAreaKey, read 01.11.2026): lowercase, no
-- apostrophe, no leading "the", only letters, digits and single spaces.
function Model.AreaKey(name)
  if type(name) ~= "string" then
    return nil
  end
  local key = string.lower(name)
  key = string.gsub(key, "'", "")
  key = string.gsub(key, "^the%s+", "")
  key = string.gsub(key, "[^a-z0-9]+", " ")
  key = string.gsub(key, "^%s+", "")
  key = string.gsub(key, "%s+$", "")
  if key == "" then
    return nil
  end
  return key
end

-- The direction of a target from the player as the orbit draws it: degrees clockwise from the
-- top, the top being where the player faces. World yards: x north, y west; `facing` the client's
-- radians counter-clockwise from north (nil: north is up).
function Model.Bearing(px, py, facing, tx, ty)
  if not (px and py and tx and ty) then
    return nil
  end
  local dx, dy = tx - px, ty - py
  if dx == 0 and dy == 0 then
    return 0
  end
  local angle = math.atan2(dy, dx) - (facing or 0)
  return (-math.deg(angle)) % 360
end

-- The status of a quest to this character: "ready" (hand in), "log", "available", or nil (done, too
-- high, unknown). `entry` is the quest log's entry, `completed` the client's flag, `level` the
-- player's, `record` our data (minLevel).
function Model.QuestStatus(record, entry, completed, level)
  if completed then
    return nil
  end
  if entry then
    return (entry.readyForTurnIn or entry.isComplete) and "ready" or "log"
  end
  if not record then
    return nil
  end
  local min = record.minLevel or record.level
  if min and level and level < min then
    return nil
  end
  return "available"
end

local function rank(item)
  return RANK[item.status] or 3
end

-- Sorts in place: what the player can act on first, unheard before heard, nearer first, then by
-- name so the order is stable.
function Model.Order(list)
  table.sort(list, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then
      return ra < rb
    end
    if (a.heard and true or false) ~= (b.heard and true or false) then
      return not a.heard
    end
    local da, db = a.distance or math.huge, b.distance or math.huge
    if da ~= db then
      return da < db
    end
    return tostring(a.title or "") < tostring(b.title or "")
  end)
  return list
end

-- Caps the lists for the orbit: `limits.places` inner bubbles, `limits.outer` outer ones, each
-- giver's quests to `limits.moons` (its `more` counts the rest). Returns the capped lists and the
-- items left out (for the "+n" bubble).
function Model.Pick(places, outer, limits)
  limits = limits or Voice.LIMITS
  local keptPlaces, keptOuter, rest = {}, {}, {}
  for i, p in ipairs(places) do
    if i <= limits.places then
      keptPlaces[#keptPlaces + 1] = p
    else
      rest[#rest + 1] = p
    end
  end
  for i, o in ipairs(outer) do
    if o.quests then
      Model.Order(o.quests)
      if #o.quests > limits.moons then
        o.more = #o.quests - limits.moons
        for j = #o.quests, limits.moons + 1, -1 do
          rest[#rest + 1] = o.quests[j]
          table.remove(o.quests, j)
        end
      end
    end
    if i <= limits.outer then
      keptOuter[#keptOuter + 1] = o
    else
      rest[#rest + 1] = o
    end
  end
  return keptPlaces, keptOuter, rest
end

-- x right, y up from the orbit's centre; `deg` clockwise from the top.
local function polar(deg, r)
  local a = math.rad(deg)
  return r * math.sin(a), r * math.cos(a)
end
Model.Polar = polar

-- Outer bubbles keep Voice.MIN_GAP degrees apart: sorted by bearing, each one later is pushed on,
-- and the last one may push the first (a wrap).
local function spread(list, gap)
  if #list < 2 then
    return
  end
  table.sort(list, function(a, b)
    return a.deg < b.deg
  end)
  for i = 2, #list do
    if list[i].deg - list[i - 1].deg < gap then
      list[i].deg = list[i - 1].deg + gap
    end
  end
  local wrap = list[1].deg + 360 - list[#list].deg
  if wrap < gap then
    local shift = (gap - wrap) / 2
    for _, slot in ipairs(list) do
      slot.deg = slot.deg + shift
    end
  end
end

-- The arrangement (voice.md §3.2, arrangement A): places evenly on the inner orbit, the first at the
-- top; outer items at their bearing (evenly where none has one), their quests as moons fanned
-- outward. Returns { { item, x, y, r, kind, parent }, ... } in design units of the wide orbit.
function Model.Layout(places, outer, radii)
  local R = radii or Voice.RADII
  local out = {}
  local n = #places
  for i, p in ipairs(places) do
    local x, y = polar((i - 1) * 360 / n, R.inner)
    out[#out + 1] = { item = p, x = x, y = y, r = R[p.size or "area"] or R.area, kind = p.kind }
  end
  local slots = {}
  local anyBearing = false
  for _, o in ipairs(outer) do
    if o.bearing then
      anyBearing = true
    end
  end
  for i, o in ipairs(outer) do
    local even = (i - 1) * 360 / #outer
    slots[#slots + 1] = { item = o, deg = anyBearing and (o.bearing or even) or even }
  end
  spread(slots, Voice.MIN_GAP)
  for _, slot in ipairs(slots) do
    local o = slot.item
    local x, y = polar(slot.deg, R.outer)
    local r = R[o.size or o.kind] or R.boss
    local me = { item = o, x = x, y = y, r = r, kind = o.kind, deg = slot.deg }
    out[#out + 1] = me
    if o.quests then
      local m = #o.quests
      for j, q in ipairs(o.quests) do
        local off = (j - (m + 1) / 2) * 26
        local mx, my = polar(slot.deg + off, R.moon)
        out[#out + 1] = { item = q, x = x + mx, y = y + my, r = R.moonBubble, kind = "quest", parent = o }
      end
    end
  end
  return out
end

-- The screen corner nearest a centre (x right, y up from the screen's bottom left) and the centre's
-- offset from it: a position that keeps its corner when the resolution or the UI scale changes.
function Model.Corner(cx, cy, width, height)
  local left, bottom = cx < width / 2, cy < height / 2
  local corner = (bottom and "BOTTOM" or "TOP") .. (left and "LEFT" or "RIGHT")
  return corner, cx - (left and 0 or width), cy - (bottom and 0 or height)
end

-- The centre a saved corner and offset mean on a screen of this size.
function Model.Place(corner, dx, dy, width, height)
  local x = string.find(corner, "LEFT") and 0 or width
  local y = string.find(corner, "BOTTOM") and 0 or height
  return x + (dx or 0), y + (dy or 0)
end

-- The wide orbit's diameter in UI units: 36 % of the screen's height, times the scale setting
-- (voice.md §5; 50..200 %).
function Model.Size(screenHeight, scalePercent)
  local percent = tonumber(scalePercent) or 100
  percent = math.max(50, math.min(200, percent))
  return (screenHeight or 768) * 0.36 * percent / 100
end

-- The creature id of a unit GUID ("Creature-0-1234-0-1-240-0000ABCD"), nil for players and nil.
function Model.CreatureID(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local id = string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return id and tonumber(id) or nil
end

-- A clip's length from the words it shows when nothing recorded it (Spoken NPCs reads 2.5 words a
-- second, at least 6 s).
function Model.ReadingTime(text)
  local _, words = string.gsub(text or "", "%S+", "")
  return math.max(6, words / 2.5)
end

-- The clip key of a line: what the player dedups on and what the heard list is keyed by.
function Model.Key(kind, a, b)
  if kind == "quest" then
    return "q:" .. tostring(a) .. ":" .. tostring(b or "accept")
  elseif kind == "zone" then
    return "z:" .. tostring(a)
  elseif kind == "area" then
    return "s:" .. tostring(a) .. ":" .. tostring(b)
  elseif kind == "boss" then
    return "b:" .. tostring(a) .. ":" .. tostring(b)
  elseif kind == "read" then
    return "r:" .. tostring(a)
  end
  return tostring(kind) .. ":" .. tostring(a)
end
