-- Courtesy's voice (courtesy.md, ADR 0063): which line fits a moment, and its words.
-- Pure: plain tables in, plain tables out; the caller gathers the facts. A condition or a slot that
-- asks for a fact nobody knows rules the line out (CLAUDE.md 4.2).
local _, ns = ...
local L = ns.L

local Voice = {}
ns.Voice = Voice

Voice.MOODS = { "polite", "roleplay", "snarky", "philosophic", "cheerful", "weary" }
-- how much likelier a line is for each condition it meets, for each level its situation lies deeper,
-- and once when it names something of the moment (Voice.SCENE)
Voice.SPECIFIC = 3
Voice.RECENT = 40 -- lines not repeated while another candidate exists
Voice.SHOWN = 6 -- lines offered (two rings), kept out of the next offers while others exist
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
  land = "land",
  heavy = "heavy",
  fight = "fight",
  level = "level",
  hurt = "hurt",
  many = "many",
  foe = "foe", -- the other faction (ADR 0063, 21.11.2026)
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
  s = "spell",
  a = "near",
  k = "company", -- the other players at a fire (courtesy.md "Greeting the fire")
}

-- the slots that name something of the moment: the spell, the place, the zone, the weather, the hour,
-- the company at a fire
Voice.SCENE = { s = true, a = true, z = true, w = true, h = true, k = true }

Voice.COMPANY_MAX = 4 -- names a line says at most; more are "everyone"

-- The languages of the lines (ADR 0088): a pack each, `ns.CourtesyPacks[language]` = { words,
-- lines (patterns, ADR 0089) }. The packs' files fill the table; `Voice.language` is the one the
-- ring speaks (Main.lua, the profile).
ns.CourtesyPacks = ns.CourtesyPacks or {}
Voice.PACKS = ns.CourtesyPacks
Voice.LANGUAGES = { "enUS", "deDE" }
Voice.language = "enUS"

-- The pack of a language (nil: the ring's), else the English one.
function Voice.Pack(language)
  return Voice.PACKS[language or Voice.language] or Voice.PACKS.enUS
end

-- The side of each race (the other faction's greetings may tease, ADR 0063 of 21.11.2026).
Voice.SIDE = {
  Human = "Alliance",
  Dwarf = "Alliance",
  NightElf = "Alliance",
  Gnome = "Alliance",
  Orc = "Horde",
  Troll = "Horde",
  Scourge = "Horde",
  Tauren = "Horde",
}

-- The words of the pack of `facts.lang` (else the ring's language), never the client's locale:
-- a German line on an English client says "der Herr".
local function wordsOf(facts)
  local pack = Voice.Pack(facts and facts.lang)
  return pack and pack.words or {}
end

-- The company at a fire in words: "Alda", "Alda and Brann", "Alda, Brann and Cedric"; more than
-- COMPANY_MAX "everyone"; nil for nobody (unknown, golden rule 2). `language` the pack's.
function Voice.Company(names, language)
  local words = (Voice.Pack(language) or {}).words or {}
  if type(names) ~= "table" or #names == 0 then
    return nil
  elseif #names > Voice.COMPANY_MAX then
    return words.everyone or "everyone"
  elseif #names == 1 then
    return names[1]
  end
  local pair = words.pair or "%s and %s"
  return string.format(pair, table.concat(names, ", ", 1, #names - 1), names[#names])
end

local function word(map, key)
  return type(map) == "table" and key ~= nil and map[key] or nil
end

-- A race's or a class's name in the pack's words, by sex (Magier, Magierin); unknown sex takes the
-- first. Nil when the pack does not know the key: the client's own name stays then.
local function nameIn(map, key, sex)
  local names = type(map) == "table" and key ~= nil and map[key] or nil
  if type(names) ~= "table" then
    return nil
  end
  return sex == "f" and names[2] or names[1]
end

-- The facts a slot or a condition reads that follow from the others, in the words of the pack of
-- `facts.lang`. -> the same table.
function Voice.Complete(facts)
  local words = wordsOf(facts)
  if facts.raceKey and facts.myRaceKey then
    facts.kin = facts.raceKey == facts.myRaceKey
    local theirs, mine = Voice.SIDE[facts.raceKey], Voice.SIDE[facts.myRaceKey]
    if theirs and mine then
      facts.foe = theirs ~= mine
    end
  end
  facts.race = nameIn(words.races, facts.raceKey, facts.sex) or facts.race
  facts.class = nameIn(words.classes, facts.classKey, facts.sex) or facts.class
  facts.myRace = nameIn(words.races, facts.myRaceKey, facts.mySex) or facts.myRace
  facts.myPossessive = word(words.possessive, facts.mySex)
  facts.address = word(words.address, facts.sex)
  facts.folk = word(words.folk, facts.sex)
  facts.weatherWord = word(words.weather, facts.weather)
  local daytime = facts.dayWord or facts.time -- an invented moment (try) names only the time
  facts.daytime = word(words.daytime, daytime)
  facts.near = facts.subzone or facts.zone -- the nearest place with a name
  return facts
end

-- The situations the lines name, as a set; a child also names its parent ("buff.mind", "buff").
function Voice.Situations(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if type(line[1]) == "table" then
      for _, one in ipairs(line[1]) do
        out[one] = true
      end
    else
      out[line[1]] = true
    end
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

-- ---------------------------------------------------------------------------------------------
-- Patterns with variants (ADR 0089): a line's text or act may hold choice groups `{a|b|}`, one
-- choice each, alike; an empty choice says nothing; groups do not nest. The variant is chosen when
-- the line is offered (Voice.Realise), so the petal shows the words a click sends.
-- ---------------------------------------------------------------------------------------------

Voice.PATTERN_MAX = 140 -- bytes the longest variant of a pattern's text and act say at most

local function splitChoices(inner)
  local out, at = {}, 1
  while true do
    local bar = string.find(inner, "|", at, true)
    if not bar then
      out[#out + 1] = string.sub(inner, at)
      return out
    end
    out[#out + 1] = string.sub(inner, at, bar - 1)
    at = bar + 1
  end
end

-- A text in pieces: a string is said as it stands, a table is a group's choices. Nil when a brace
-- does not close, a group holds another, or a `|` or `}` stands outside a group.
local function parse(text)
  local out, at = {}, 1
  local function literal(piece)
    if string.find(piece, "[|}]") then
      return false
    end
    out[#out + 1] = piece
    return true
  end
  while true do
    local open = string.find(text, "{", at, true)
    if not open then
      return literal(string.sub(text, at)) and out or nil
    end
    local close = string.find(text, "}", open + 1, true)
    if not close or not literal(string.sub(text, at, open - 1)) then
      return nil
    end
    local inner = string.sub(text, open + 1, close - 1)
    if string.find(inner, "{", 1, true) then
      return nil
    end
    out[#out + 1] = splitChoices(inner)
    at = close + 1
  end
end

local parsed = {} -- text -> its pieces, or false when it is no pattern (the lines are few and fixed)

local function piecesOf(text)
  local pieces = parsed[text]
  if pieces == nil then
    pieces = parse(text) or false
    parsed[text] = pieces
  end
  return pieces or nil
end

-- Whether every slot of `text` has its fact; `scene` is set when one names the moment.
local function factsKnown(text, facts, scene)
  for key in string.gmatch(text, "%%(%a+)") do
    local field = Voice.SLOTS[key]
    if not field or facts[field] == nil then
      return false
    end
    if scene and Voice.SCENE[key] then
      scene.named = true
    end
  end
  return true
end

-- Whether `text` can be said with `facts`: every slot outside a group known, and in every group a
-- choice whose slots are known; and whether a slot outside the groups names the moment.
local function slotsKnown(text, facts)
  if not text then
    return true, false
  end
  local pieces = piecesOf(text)
  if not pieces then
    return false, false
  end
  local scene = {}
  for _, piece in ipairs(pieces) do
    if type(piece) == "string" then
      if not factsKnown(piece, facts, scene) then
        return false, false
      end
    else
      local any = false
      for _, choice in ipairs(piece) do
        any = any or factsKnown(choice, facts)
      end
      if not any then
        return false, false
      end
    end
  end
  return true, scene.named == true
end

-- The capitals of the lower-case letters a German sentence may start with (two bytes in UTF-8).
local UPPER = { ["\195\164"] = "\195\132", ["\195\182"] = "\195\150", ["\195\188"] = "\195\156" }

local function upper(letter)
  return UPPER[letter] or string.upper(letter)
end

-- A realised text tidied: one space where an empty choice left two, none before , . ! ?, and with
-- `capitals` each sentence starting with one (not after "...": "Ah... danke." is meant so).
local function tidy(text, capitals)
  text = string.gsub(text, "%s+", " ")
  text = string.gsub(text, "^ ", "")
  text = string.gsub(text, " $", "")
  text = string.gsub(text, " ([,.!?])", "%1")
  if capitals then
    text = string.gsub(text, "%.%.%.", "\1")
    text = string.gsub(text, "^(%l)", upper)
    text = string.gsub(text, "^(\195[\164\182\188])", upper)
    text = string.gsub(text, "([.!?] )(%l)", function(gap, letter)
      return gap .. upper(letter)
    end)
    text = string.gsub(text, "([.!?] )(\195[\164\182\188])", function(gap, letter)
      return gap .. upper(letter)
    end)
    text = string.gsub(text, "\1", "...")
  end
  return text
end

local function realised(text, facts, rand, capitals)
  local pieces = piecesOf(text)
  if not pieces then
    return nil
  end
  local out = {}
  for _, piece in ipairs(pieces) do
    if type(piece) == "string" then
      out[#out + 1] = piece
    else
      local fitting = {}
      for _, choice in ipairs(piece) do
        if factsKnown(choice, facts) then
          fitting[#fitting + 1] = choice
        end
      end
      if #fitting == 0 then
        return nil
      end
      out[#out + 1] = fitting[math.min(#fitting, math.floor(rand() * #fitting) + 1)]
    end
  end
  return tidy(table.concat(out), capitals)
end

-- A line as it is offered: a copy with one choice per group, `pattern` the line itself; nil when a
-- group has no choice whose facts are known. A line without a group comes back as it is.
function Voice.Realise(line, facts, rand)
  local text, act = line[3], line.act
  local textGroups = type(text) == "string" and string.find(text, "{", 1, true)
  local actGroups = type(act) == "string" and string.find(act, "{", 1, true)
  if not textGroups and not actGroups then
    return line
  end
  rand = rand or math.random
  local copy = {}
  for key, value in pairs(line) do
    copy[key] = value
  end
  copy.pattern = line
  if textGroups then
    copy[3] = realised(text, facts or {}, rand, true)
    if not copy[3] then
      return nil
    end
  end
  if actGroups then
    copy.act = realised(act, facts or {}, rand, false)
    if not copy.act then
      return nil
    end
  end
  return copy
end

-- The line a realised one was drawn from (itself when it had no group): what memory and Never keep.
function Voice.Source(line)
  return type(line) == "table" and line.pattern or line
end

-- The bytes the longest variant of `text` says (its slots counted as written); nil when it is no
-- pattern.
function Voice.Longest(text)
  local pieces = text and piecesOf(text)
  if not pieces then
    return text == nil and 0 or nil
  end
  local n = 0
  for _, piece in ipairs(pieces) do
    if type(piece) == "string" then
      n = n + #piece
    else
      local most = 0
      for _, choice in ipairs(piece) do
        most = math.max(most, #choice)
      end
      n = n + most
    end
  end
  return n
end

-- Whether a line of `situation` serves the moment `of`: the same, or one above it in the tree
-- ("buff" and "buff.blessing" serve "buff.blessing.might"; a sibling never does).
local function serves(situation, of)
  if type(situation) == "table" then -- a part may serve several rows ({ "buff", "rez" })
    for _, one in ipairs(situation) do
      if serves(one, of) then
        return true
      end
    end
    return false
  end
  if type(situation) ~= "string" or type(of) ~= "string" then
    return false
  end
  return situation == of or string.sub(of, 1, #situation + 1) == situation .. "."
end

-- How deep the deepest of a part's rows that serves `of` lies (0 for "buff", 2 for
-- "buff.blessing.might").
local function depth(situation, of)
  if type(situation) == "table" then
    local best = 0
    for _, one in ipairs(situation) do
      if serves(one, of) then
        best = math.max(best, depth(one, of))
      end
    end
    return best
  end
  local _, levels = string.gsub(situation, "%.", "")
  return levels
end

-- How well a line fits, nil when it does not: 1, and more for each level its situation lies deeper,
-- for each condition it meets, and once when it names something of the moment.
local function score(line, facts)
  if not serves(line[1], facts.situation) then
    return nil
  end
  local textKnown, textNames = slotsKnown(line[3] or nil, facts)
  local actKnown, actNames = slotsKnown(line.act, facts)
  if not (textKnown and actKnown) then
    return nil
  end
  local naming = (textNames or actNames) and 1 or 0
  local weight = Voice.SPECIFIC ^ (depth(line[1], facts.situation) + naming)
  for key, want in pairs(line.when or {}) do
    local field = Voice.CONDITIONS[key]
    if not field or not meets(want, facts[field]) then
      return nil
    end
    weight = weight * Voice.SPECIFIC
  end
  return weight
end

-- A line's key for the never-offered list: its words, or its action when it has none.
function Voice.Key(line)
  if type(line) ~= "table" then
    return nil
  elseif line.pattern then
    return Voice.Key(line.pattern) -- a variant is switched off with its pattern (ADR 0089)
  elseif type(line[3]) == "string" and line[3] ~= "" then
    return line[3]
  elseif type(line.act) == "string" and line.act ~= "" then
    return "act:" .. line.act
  end
  return nil
end

local function candidates(lines, facts, opts, useRecent)
  local byMood = {}
  local never = opts.never
  for _, line in ipairs(lines) do
    local mood = line[2]
    local moodOn = opts.moods == nil or (opts.moods[mood] or 0) > 0
    local spoken = opts.via ~= "say" or line[3]
    local fresh = not (useRecent and opts.recent and opts.recent[line])
    local allowed = not (never and never[Voice.Key(line)])
    if moodOn and spoken and fresh and allowed then
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

-- The line for `facts`, or nil, realised (Voice.Realise). `opts`: `moods` { mood = weight } (nil:
-- all alike; a mood left out is off), `via` "say" (silent lines are out), `recent` (Voice.Remember's
-- table), `fresh` (nil rather than a line from `recent`), `rand` () -> 0..1.
function Voice.Choose(lines, facts, opts)
  opts = opts or {}
  local line = Voice.ChoosePattern(lines, facts, opts)
  return line and Voice.Realise(line, facts, opts.rand or math.random) or nil
end

-- The pattern Voice.Choose realises.
function Voice.ChoosePattern(lines, facts, opts)
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

-- Notes a line as said (or offered); the oldest is forgotten after `limit` (default RECENT).
-- A line is remembered by its pattern (ADR 0089), whichever variant was said. `order` keeps the
-- lines as they were offered.
function Voice.Remember(recent, line, limit)
  recent.order = recent.order or {}
  local source = Voice.Source(line)
  if recent[source] then
    for i, l in ipairs(recent.order) do
      if Voice.Source(l) == source then
        table.remove(recent.order, i) -- again: it moves to the newest place
        break
      end
    end
  end
  recent[source] = true
  table.insert(recent.order, line)
  if #recent.order > (limit or Voice.RECENT) then
    local gone = table.remove(recent.order, 1)
    recent[Voice.Source(gone)] = nil
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
  if line.lang ~= nil and not Voice.PACKS[line.lang] then
    return string.format(L["unknown language: %s"], tostring(line.lang))
  elseif type(line[1]) ~= "string" or not situations[line[1]] then
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
  local textLong, actLong = Voice.Longest(text), Voice.Longest(act)
  if not textLong or not actLong then
    return L["a { choice | group } does not close"]
  end
  if line.when ~= nil and type(line.when) ~= "table" then
    return string.format(L["unknown condition: %s"], tostring(line.when))
  end
  for key in pairs(line.when or {}) do
    if not Voice.CONDITIONS[key] then
      return string.format(L["unknown condition: %s"], tostring(key))
    end
  end
  if textLong + actLong + 3 > Voice.MAX_BYTES - Voice.NAME_ROOM then
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
