-- The pure model of Bastian's Campfire (campfire.md): the value of a benefit at a level, the fire
-- card's state, the beacon's message and its expiry, the chat pickup, the planner's rows. Plain
-- tables in, plain tables out; no WoW API.
local _, ns = ...
local Camp = ns.Camp

local Model = {}
ns.Model = Model

Model.CARD_LINGER = 60 -- the card fades a minute after the fire's aura is gone
Model.FIRE_SECONDS = 3600 -- a shared fire's pin expires after an hour
Model.MESSAGE_VERSION = 1
Model.KIND = "camp" -- the Comm kind (docs/architecture/addon-messages.md)

-- The value of literal brackets { { up to level, value }, ... } at `level`; nil when the level
-- is unknown or beyond every bracket (never a guess, CLAUDE.md §4.2).
function Model.Value(brackets, level)
  level = tonumber(level)
  if type(brackets) ~= "table" or not level then
    return nil
  end
  for _, b in ipairs(brackets) do
    if level <= b[1] then
      return b[2]
    end
  end
  return nil
end

-- The values of a benefit at `level`: { main } or for the lute { armor, attributes, resistances };
-- an empty table when the level is unknown.
function Model.Values(benefit, level)
  if benefit.armor then
    return {
      armor = Model.Value(benefit.armor, level),
      attributes = Model.Value(benefit.attributes, level),
      resistances = Model.Value(benefit.resistances, level),
    }
  end
  return { main = Model.Value(benefit.levels, level) }
end

-- The camp's state for the card. `input`:
--   now      the clock in seconds
--   nearby   true while the "Campfire Nearby" aura is on the player
--   resting  the "Welcoming Campfire" aura's end (seconds on the clock), or true without one
--   buffs    { [benefit key] = end on the clock | true (an end the client did not give) }
--   seen     the clock when the fire last showed itself (nearby, resting or a buff landing)
--   carried  { feature, ... } the camp items in the bags
--   features { benefit key, ... } the camp's benefits seen on the group (optional)
-- -> { show, state = "away" | "near" | "warming" | "warm" | "fading", warmIn, left, have, could }
function Model.Card(input)
  local now = input.now or 0
  local have, left = {}, nil
  for _, key in ipairs(Camp.BENEFIT_ORDER) do
    local ends = input.buffs and input.buffs[key]
    if ends then
      have[#have + 1] = key
      if type(ends) == "number" then
        local l = math.max(0, ends - now)
        left = left and math.min(left, l) or l
      end
    end
  end
  -- `features`: the benefits the camp gives anyone of the group (their auras, probe C5); the
  -- player's own buffs without a group
  local out = {
    have = have,
    left = left,
    could = Model.Could(input.carried, input.features or have, {
      professions = input.professions,
      cooling = input.cooling,
      placedHere = input.placedHere,
    }),
  }
  if input.resting then
    out.state = "warming"
    if type(input.resting) == "number" then
      out.warmIn = math.max(0, input.resting - now)
    end
  elseif #have > 0 then
    out.state = (left and left <= Camp.FADING_SECONDS) and "fading" or "warm"
  elseif input.nearby then
    out.state = "near"
  else
    out.state = "away"
  end
  local recent = input.seen and now - input.seen < Model.CARD_LINGER
  out.show = (input.nearby or input.resting or recent) and true or false
  return out
end

-- Whether the character can use `feature` (`professions`: { [skill line] = rank }). No answer from the
-- client, an empty table included, is unknown: then it is offered, the game has the last word.
local function canUse(feature, professions)
  if type(professions) ~= "table" or next(professions) == nil then
    return true
  end
  return (professions[feature.skill] or 0) >= feature.rank
end

-- The carried features whose benefit the camp does not give yet, the highest rank of each (one feature
-- per player at a camp: the suggestions are the player's own). A service feature (no benefit) is always
-- offered. `ctx`: `professions`, `cooling` ({ [item] = true }), `placedHere` (none after the player's
-- own: one per player and camp).
function Model.Could(carried, have, ctx)
  ctx = ctx or {}
  if ctx.placedHere then
    return {}
  end
  local got = {}
  for _, key in ipairs(have or {}) do
    got[key] = true
  end
  local out, at = {}, {}
  for _, feature in ipairs(carried or {}) do
    local key = feature.benefit or feature.name
    local open = not feature.kit and not got[feature.benefit or ""]
    if open and canUse(feature, ctx.professions) and not (ctx.cooling and ctx.cooling[feature.item]) then
      if not at[key] then
        out[#out + 1] = feature
        at[key] = #out
      elseif feature.rank > out[at[key]].rank then
        out[at[key]] = feature
      end
    end
  end
  return out
end

-- The carried kits the character can use, the biggest fire first.
function Model.Kits(carried, professions)
  local out = {}
  for _, item in ipairs(carried or {}) do
    if item.kit and canUse(item, professions) then
      out[#out + 1] = item
    end
  end
  table.sort(out, function(a, b)
    return a.rank > b.rank
  end)
  return out
end

-- The flame of each state (campfire.md "The flame"): its size and brightness, the heart's brightness, how
-- fast and how far it flickers.
Model.FLAME = {
  near = { size = 0.62, outer = 0.6, heart = 0.4, speed = 2.5, depth = 0.05 },
  warming = { size = 0.85, outer = 0.9, heart = 1, speed = 5, depth = 0.06 },
  warm = { size = 1, outer = 1, heart = 1, speed = 3, depth = 0.04 },
  fading = { size = 0.72, outer = 0.9, heart = 0.8, speed = 9, depth = 0.14 },
  away = { size = 0.55, outer = 0.45, heart = 0.25, speed = 1, depth = 0.02 },
}

-- The flame at the time `t`: -> size (of the full flame), the outer brightness, the heart's. Two waves
-- that never line up, so that it does not look like a pulsing icon.
function Model.Flame(state, t)
  local f = Model.FLAME[state] or Model.FLAME.near
  local wave = (math.sin(t * f.speed) + 0.5 * math.sin(t * f.speed * 2.3 + 1)) / 1.5
  local other = math.cos(t * f.speed * 1.4)
  return f.size * (1 + f.depth * wave),
    math.min(1, f.outer * (1 - f.depth * (wave + 1) / 2)),
    math.min(1, f.heart * (1 - f.depth * (other + 1)))
end

-- How much of the heart burns: while warming the part of the minute gone by, else all of it; a time
-- nobody knows does not fill it (it flickers whole).
function Model.Fill(state, warmIn)
  if state ~= "warming" or type(warmIn) ~= "number" then
    return 1
  end
  return math.max(0.1, math.min(1, 1 - warmIn / Camp.REST_SECONDS))
end

-- The benefits the camp still lacks (the group's suggestion line: names of benefits, never of
-- people; nobody is whispered).
function Model.Missing(have)
  local got = {}
  for _, key in ipairs(have or {}) do
    got[key] = true
  end
  local out = {}
  for _, key in ipairs(Camp.BENEFIT_ORDER) do
    if not got[key] and key ~= "tent" then
      out[#out + 1] = key
    end
  end
  return out
end

-- "m:ss" for seconds; nil for nil.
function Model.Clock(seconds)
  if type(seconds) ~= "number" then
    return nil
  end
  seconds = math.max(0, math.floor(seconds + 0.5))
  if seconds >= 3600 then
    return string.format(
      "%d:%02d:%02d",
      math.floor(seconds / 3600),
      math.floor(seconds / 60) % 60,
      seconds % 60
    )
  end
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- ---------------------------------------------------------------------------------------------
-- The beacon (addon-messages.md, kind "camp")
-- ---------------------------------------------------------------------------------------------

local function fraction(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

-- The message of a fire: { v, map, x, y, size, features, age } (uiMapID and map fractions; `age`
-- in seconds since the sender first saw the fire, because two players' clocks differ; no names).
function Model.Payload(fire, now)
  local features = {}
  for _, key in ipairs(fire.features or {}) do
    if Camp.BENEFITS[key] then
      features[#features + 1] = key
    end
  end
  return {
    v = Model.MESSAGE_VERSION,
    map = fire.map,
    x = fire.x,
    y = fire.y,
    size = fire.size,
    features = features,
    age = fire.since and math.max(0, math.floor((now or 0) - fire.since)) or nil,
  }
end

-- A received value made safe: the fields above checked, unknown fields dropped; nil and why for
-- anything else.
function Model.CleanCamp(value, now)
  if type(value) ~= "table" then
    return nil, "not a table"
  end
  if type(value.v) ~= "number" or value.v < 1 then
    return nil, "version"
  end
  local map = tonumber(value.map)
  if not map or map <= 0 or map ~= math.floor(map) or not fraction(value.x) or not fraction(value.y) then
    return nil, "position"
  end
  local size = value.size
  if size ~= nil and size ~= 3 and size ~= 5 and size ~= 10 then
    size = nil
  end
  local features = {}
  if type(value.features) == "table" then
    for _, key in ipairs(value.features) do
      if type(key) == "string" and Camp.BENEFITS[key] and #features < 10 then
        features[#features + 1] = key
      end
    end
  end
  local age = tonumber(value.age)
  if age and (age < 0 or age > Model.FIRE_SECONDS) then
    return nil, "too old"
  end
  return {
    map = map,
    x = value.x,
    y = value.y,
    size = size,
    features = features,
    at = (now or 0) - (age or 0),
  }
end

-- Whether a kept fire is past its hour.
function Model.Expired(fire, now)
  return (now or 0) - (fire.at or 0) > Model.FIRE_SECONDS
end

-- Keeps the fires that are not expired, one per place (a fire within `near` map units of a newer
-- one is the same fire), the newest first.
function Model.Prune(fires, now, near)
  near = near or 0.01
  table.sort(fires, function(a, b)
    return (a.at or 0) > (b.at or 0)
  end)
  local out = {}
  for _, fire in ipairs(fires) do
    local same = false
    for _, kept in ipairs(out) do
      if kept.map == fire.map and math.abs(kept.x - fire.x) < near and math.abs(kept.y - fire.y) < near then
        same = true
        break
      end
    end
    if not same and not Model.Expired(fire, now) then
      out[#out + 1] = fire
    end
  end
  return out
end

-- A chat line that posts a camp: a map pin link (|Hworldmap:<uiMapID>:<x>:<y>|h, x and y in
-- 1/10000) and one of `words` ("camp", "fire" and the locale's words) as a whole word, any case.
-- -> map, x, y (fractions) or nil.
function Model.ChatCamp(text, words)
  if type(text) ~= "string" then
    return nil
  end
  local map, x, y = text:match("|Hworldmap:(%d+):(%d+):(%d+)")
  map, x, y = tonumber(map), tonumber(x), tonumber(y)
  if not (map and x and y) or x > 10000 or y > 10000 then
    return nil
  end
  local plain = text:gsub("|H.-|h.-|h", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  plain = (" " .. plain .. " "):lower()
  for _, word in ipairs(words or {}) do
    local w = word:lower():gsub("(%W)", "%%%1")
    if plain:find("[^%w]" .. w .. "[^%w]") then
      return map, x / 10000, y / 10000
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The planner
-- ---------------------------------------------------------------------------------------------

-- The planner's features with what the player can do with them. `ctx`:
--   level        the character's level (nil: unknown)
--   professions  { [skill line id] = rank } of this character (nil: the client did not say)
--   carried      { [itemID] = count } in the bags
--   faction      "Alliance" | "Horde" | nil
-- -> { { feature, benefit, amounts, canPlace = true | false | nil, carried = n } } in the order of
-- the benefits, the service features last.
function Model.Plan(ctx)
  local out = {}
  local function add(feature)
    if feature.faction and ctx.faction and feature.faction ~= ctx.faction then
      return
    end
    local benefit = feature.benefit and Camp.BENEFITS[feature.benefit] or nil
    local canPlace -- nil while the client did not say which professions the character has
    if ctx.professions then
      canPlace = (ctx.professions[feature.skill] or 0) >= feature.rank
    end
    out[#out + 1] = {
      feature = feature,
      benefit = benefit,
      amounts = benefit and Model.Values(benefit, ctx.level) or {},
      canPlace = canPlace,
      carried = ctx.carried and ctx.carried[feature.item] or 0,
    }
  end
  for _, key in ipairs(Camp.BENEFIT_ORDER) do
    for _, feature in ipairs(Camp.FEATURES) do
      if feature.benefit == key then
        add(feature)
      end
    end
  end
  for _, feature in ipairs(Camp.FEATURES) do
    if not feature.benefit then
      add(feature)
    end
  end
  return out
end

-- The skill line ids of the client's profession names ({ [name] = rank }, as Compat.GetProfessions
-- gives them) through `nameOf(skillID) -> the client's word`. nil stays nil.
function Model.Professions(byName, nameOf)
  if type(byName) ~= "table" then
    return nil
  end
  local out = {}
  for skill in pairs(Camp.SKILLS) do
    local rank = byName[nameOf(skill)]
    if rank then
      out[skill] = rank
    end
  end
  return out
end
