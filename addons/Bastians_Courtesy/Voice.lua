-- Courtesy's voice (courtesy.md, ADR 0063): which line fits a moment, and its words.
-- Pure: plain tables in, plain tables out; the caller gathers the facts. A condition or a slot that
-- asks for a fact nobody knows rules the line out (CLAUDE.md 4.2).
local _, ns = ...
local L = ns.L

local Voice = {}
ns.Voice = Voice

Voice.MOODS = { "polite", "roleplay", "snarky", "philosophic", "cheerful", "weary" }
Voice.SPECIFIC = 3 -- how much likelier a line is for each condition it meets
Voice.RECENT = 40 -- lines not repeated while another candidate exists
Voice.MAX_BYTES = 255 -- one chat message
Voice.NAME_ROOM = 40 -- what a written line leaves free for the names its slots bring

-- a line's `when` key -> the fact it reads
Voice.CONDITIONS = {
  race = "raceKey",
  class = "classKey",
  sex = "sex",
  mine = "myRaceKey",
  mysex = "mySex",
  time = "time",
  weather = "weather",
  kin = "kin",
}

-- a slot of a line -> the fact it writes
Voice.SLOTS = {
  t = "target",
  r = "race",
  c = "class",
  h = "daytime",
  w = "weatherWord",
  z = "zone",
  n = "myName",
  m = "myRace",
  p = "myPossessive",
  o = "address",
  y = "folk",
}

local WEATHER_WORD = { rain = "rain", snow = "snow", sandstorm = "sand" }
local POSSESSIVE = { m = "his", f = "her" }
local ADDRESS = { m = "sir", f = "my lady" }
local FOLK = { m = "lad", f = "lass" }

local function word(map, key)
  local text = key ~= nil and map[key] or nil
  return text and L[text] or nil
end

-- The facts a slot or a condition reads that follow from the others. -> the same table.
function Voice.Complete(facts)
  if facts.raceKey and facts.myRaceKey then
    facts.kin = facts.raceKey == facts.myRaceKey
  end
  facts.myPossessive = word(POSSESSIVE, facts.mySex)
  facts.address = word(ADDRESS, facts.sex)
  facts.folk = word(FOLK, facts.sex)
  facts.weatherWord = word(WEATHER_WORD, facts.weather)
  facts.daytime = facts.time and L[facts.time] or nil
  return facts
end

-- The situations the lines name, as a set; a child also names its parent ("buff.mind", "buff").
function Voice.Situations(lines)
  local out = {}
  for _, line in ipairs(lines) do
    out[line[1]] = true
  end
  return out
end

local function meets(want, have)
  if have == nil then
    return false
  end
  if type(want) ~= "table" then
    return want == have
  end
  for _, value in ipairs(want) do
    if value == have then
      return true
    end
  end
  return false
end

local function slotsKnown(text, facts)
  if not text then
    return true
  end
  for key in string.gmatch(text, "%%(%a+)") do
    local field = Voice.SLOTS[key]
    if not field or facts[field] == nil then
      return false
    end
  end
  return true
end

-- How well a line fits, nil when it does not: 1, the conditions and the exact situation add to it.
local function score(line, facts)
  local parent = string.match(facts.situation or "", "^([^.]+)%.")
  if line[1] ~= facts.situation and line[1] ~= parent then
    return nil
  end
  if not (slotsKnown(line[3] or nil, facts) and slotsKnown(line.act, facts)) then
    return nil
  end
  local weight = line[1] == facts.situation and Voice.SPECIFIC or 1
  for key, want in pairs(line.when or {}) do
    local field = Voice.CONDITIONS[key]
    if not field or not meets(want, facts[field]) then
      return nil
    end
    weight = weight * Voice.SPECIFIC
  end
  return weight
end

local function candidates(lines, facts, opts, useRecent)
  local byMood = {}
  for _, line in ipairs(lines) do
    local mood = line[2]
    local moodOn = opts.moods == nil or (opts.moods[mood] or 0) > 0
    local spoken = opts.via ~= "say" or line[3]
    local fresh = not (useRecent and opts.recent and opts.recent[line])
    if moodOn and spoken and fresh then
      local weight = score(line, facts)
      if weight then
        local bucket = byMood[mood]
        if not bucket then
          bucket = { total = 0 }
          byMood[mood] = bucket
        end
        bucket[#bucket + 1] = { line, weight }
        bucket.total = bucket.total + weight
      end
    end
  end
  return byMood
end

local function pickMood(byMood, moods, rand)
  local total = 0
  local function weightOf(mood)
    return byMood[mood] and (moods and moods[mood] or (not moods and 1)) or 0
  end
  for _, mood in ipairs(Voice.MOODS) do
    total = total + weightOf(mood)
  end
  local at = rand() * total
  local last
  for _, mood in ipairs(Voice.MOODS) do
    local weight = weightOf(mood)
    if weight > 0 then
      last = mood
      at = at - weight
      if at < 0 then
        return mood
      end
    end
  end
  return last
end

-- The line for `facts`, or nil. `opts`: `moods` { mood = weight } (nil: all alike; a mood left out
-- is off), `via` "say" (silent lines are out), `recent` (Voice.Remember's table), `fresh` (nil rather
-- than a line from `recent`), `rand` () -> 0..1.
function Voice.Choose(lines, facts, opts)
  opts = opts or {}
  local rand = opts.rand or math.random
  local byMood = candidates(lines, facts, opts, true)
  if next(byMood) == nil and not opts.fresh then
    byMood = candidates(lines, facts, opts, false) -- all were said lately: better again than silence
  end
  local mood = pickMood(byMood, opts.moods, rand)
  local bucket = mood and byMood[mood]
  if not bucket then
    return nil
  end
  local at = rand() * bucket.total
  for _, entry in ipairs(bucket) do
    at = at - entry[2]
    if at < 0 then
      return entry[1]
    end
  end
  return bucket[#bucket][1]
end

-- Notes a line as said; the oldest is forgotten after RECENT.
function Voice.Remember(recent, line)
  recent.order = recent.order or {}
  recent[line] = true
  table.insert(recent.order, line)
  if #recent.order > Voice.RECENT then
    recent[table.remove(recent.order, 1)] = nil
  end
end

local function fill(text, facts)
  return (string.gsub(L[text], "%%(%a+)", function(key)
    return tostring(facts[Voice.SLOTS[key]])
  end))
end

local function unknownSlot(text)
  for key in string.gmatch(text or "", "%%(%a+)") do
    if not Voice.SLOTS[key] then
      return "%" .. key
    end
  end
  return nil
end

local function isMood(mood)
  for _, known in ipairs(Voice.MOODS) do
    if known == mood then
      return true
    end
  end
  return false
end

-- Why a line a player wrote cannot be used, nil when it can. `situations`: the set of known ones.
function Voice.Problem(line, situations)
  if type(line) ~= "table" then
    return L["not a line"]
  end
  local text, act = line[3] or nil, line.act
  if not situations[line[1]] then
    return string.format(L["unknown situation: %s"], tostring(line[1]))
  elseif not isMood(line[2]) then
    return string.format(L["unknown mood: %s"], tostring(line[2]))
  elseif (text ~= nil and type(text) ~= "string") or (act ~= nil and type(act) ~= "string") then
    return L["needs a text or an act"]
  elseif (text or "") == "" and (act or "") == "" then
    return L["needs a text or an act"]
  elseif line.emote ~= nil and type(line.emote) ~= "string" then
    return L["emote must be a word such as BOW"]
  end
  local slot = unknownSlot(text) or unknownSlot(act)
  if slot then
    return string.format(L["unknown slot: %s"], slot)
  end
  if line.when ~= nil and type(line.when) ~= "table" then
    return string.format(L["unknown condition: %s"], tostring(line.when))
  end
  for key in pairs(line.when or {}) do
    if not Voice.CONDITIONS[key] then
      return string.format(L["unknown condition: %s"], tostring(key))
    end
  end
  if #(text or "") + #(act or "") + 3 > Voice.MAX_BYTES - Voice.NAME_ROOM then
    return L["too long"]
  end
  return nil
end

-- The chat a line goes out in: `/e` when it acts, `/say` when it only speaks.
function Voice.Channel(line)
  return line.act and "EMOTE" or "SAY"
end

-- A line's words: `via` "say" the text, nil for a silent line; "emote" the action and the speech,
-- as `/e` wants them (the game writes the name in front).
function Voice.Words(line, facts, via)
  local text = line[3] and fill(line[3], facts) or nil
  if via == "say" then
    return text
  end
  local act = line.act and fill(line.act, facts) or nil
  if act and text then
    return act .. ' "' .. text .. '"'
  elseif act then
    return act
  end
  return 'says, "' .. text .. '"'
end
