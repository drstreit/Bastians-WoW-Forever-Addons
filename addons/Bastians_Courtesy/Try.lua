-- /bcourtesy try (courtesy.md): the lines without another player. Invented moments are printed to the
-- player's own chat and nothing is sent; `ring` opens the real ring on the real facts, and a click
-- on it really sends the line.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Voice, Mine, Facts = ns.Voice, ns.Mine, ns.Facts

local Try = {}
ns.Try = Try

Try.DEFAULT = 5 -- moments of a plain /bcourtesy try
Try.MAX = 40
Try.NAME = "Mirelle" -- the invented other person, nobody's real name

local RACES = {
  human = { "Human", "Human" },
  dwarf = { "Dwarf", "Dwarf" },
  nightelf = { "NightElf", "Night Elf" },
  gnome = { "Gnome", "Gnome" },
  orc = { "Orc", "Orc" },
  troll = { "Troll", "Troll" },
  undead = { "Scourge", "Undead" },
  tauren = { "Tauren", "Tauren" },
}
local CLASSES = {
  warrior = "Warrior",
  paladin = "Paladin",
  hunter = "Hunter",
  rogue = "Rogue",
  priest = "Priest",
  shaman = "Shaman",
  mage = "Mage",
  warlock = "Warlock",
  druid = "Druid",
}
local TIMES = { "morning", "afternoon", "evening", "night" }
local WEATHERS = { "clear", "rain", "snow", "sandstorm" }
local SEXES = { "m", "f" }

local function sortedKeys(map)
  local out = {}
  for key in pairs(map) do
    out[#out + 1] = key
  end
  table.sort(out)
  return out
end

local function has(list, value)
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

local function pick(list, rand)
  return list[math.floor(rand() * #list) + 1]
end

-- What a /bcourtesy try asks for: { situation, mood, weather, time, race, class, sex, myRace, mySex,
-- count, ring, unknown = { words } }. Any order; lower or upper case.
function Try.Parse(text, lines)
  local situations = Voice.Situations(lines)
  local w = { unknown = {} }
  for token in string.gmatch(string.lower(text or ""), "%S+") do
    local own = string.match(token, "^me:(.+)$")
    if token == "ring" then
      w.ring = true
    elseif tonumber(token) then
      w.count = math.max(1, math.min(Try.MAX, math.floor(tonumber(token))))
    elseif own and RACES[own] then
      w.myRace = own
    elseif own and has(SEXES, own) then
      w.mySex = own
    elseif situations[token] then
      w.situation = token
    elseif has(Voice.MOODS, token) then
      w.mood = token
    elseif has(WEATHERS, token) then
      w.weather = token
    elseif has(TIMES, token) then
      w.time = token
    elseif RACES[token] then
      w.race = token
    elseif CLASSES[token] then
      w.class = token
    elseif has(SEXES, token) then
      w.sex = token
    else
      w.unknown[#w.unknown + 1] = token
    end
  end
  return w
end

-- The speaker: the character as it is, unless the words said otherwise.
local function speaker(w)
  local facts = Facts.Speaker()
  facts.myName = facts.myName or Try.NAME
  if w.myRace then
    facts.myRaceKey, facts.myRace = RACES[w.myRace][1], RACES[w.myRace][2]
  end
  facts.mySex = w.mySex or facts.mySex
  return facts
end

local function setRace(facts, key)
  facts.raceKey, facts.race = RACES[key][1], RACES[key][2]
end

local function setClass(facts, key)
  facts.classKey, facts.class = string.upper(key), CLASSES[key]
end

-- An invented moment: the words first, the rest by chance.
function Try.Invent(w, lines, rand)
  local facts = Facts.Surroundings(speaker(w))
  facts.situation = w.situation or pick(sortedKeys(Voice.Situations(lines)), rand)
  facts.target = Try.NAME
  facts.time = w.time or pick(TIMES, rand)
  facts.weather = w.weather or pick(WEATHERS, rand)
  facts.sex = w.sex or pick(SEXES, rand)
  setRace(facts, w.race or pick(sortedKeys(RACES), rand))
  setClass(facts, w.class or pick(sortedKeys(CLASSES), rand))
  return Voice.Complete(facts)
end

-- The moment as it is: the clock, the weather, the zone and the player's target, if a player. What
-- the client does not say stays unknown; the words still overrule it.
function Try.Real(w, lines, rand)
  local facts = Facts.Surroundings(speaker(w))
  facts.situation = w.situation or pick(sortedKeys(Voice.Situations(lines)), rand)
  facts.target = Try.NAME
  if UnitExists("target") and UnitIsPlayer("target") then
    facts.target = B.Compat.Plain((UnitName("target"))) or Try.NAME
    Facts.Unit(facts, "target")
  end
  facts.time = w.time or facts.time
  facts.weather = w.weather or facts.weather
  facts.sex = w.sex or facts.sex
  if w.race then
    setRace(facts, w.race)
  end
  if w.class then
    setClass(facts, w.class)
  end
  return Voice.Complete(facts)
end

local recent = {} -- the lines of this session, so that a long try does not repeat

local function show(line, facts)
  local tag = { line[1], line[2] }
  for _, fact in ipairs({ facts.weather or false, facts.time or false, facts.race or false }) do
    if fact then
      tag[#tag + 1] = fact
    end
  end
  if facts.sex then
    tag[#tag + 1] = facts.sex
  end
  if facts.class then
    tag[#tag + 1] = facts.class
  end
  if line.emote then
    tag[#tag + 1] = "/" .. string.lower(line.emote)
  end
  if Mine.Owns(line) then
    tag[#tag + 1] = L["my line"]
  end
  B:Say("%s[%s]|r %s %s", S.H.muted, table.concat(tag, ", "), facts.myName, Voice.Words(line, facts, "emote"))
end

local function choose(w, facts, rand)
  local line = Mine.Choose(facts, {
    moods = w.mood and { [w.mood] = 1 } or nil,
    recent = recent,
    rand = rand,
  })
  if line then
    Voice.Remember(recent, line)
    show(line, facts)
  else
    B:Say(L["No line fits these facts."])
  end
  return line
end

-- The real ring on the real facts. A click on a line really sends it.
function Try.Ring(w, rand)
  local facts = Try.Real(w, Mine.Pool(), rand)
  local unit = UnitExists("target") and UnitIsPlayer("target") and "target" or nil
  ns.Courtesy.Show(
    { kind = "try", who = facts.target, unit = unit, situation = facts.situation },
    facts,
    w.mood
  )
  return true
end

-- `/bcourtesy try ...`. -> whether something was tried.
function Try.Run(text, rand)
  rand = rand or math.random
  local w = Try.Parse(text, ns.CourtesyLines)
  if #w.unknown > 0 then
    for _, token in ipairs(w.unknown) do
      B:Say(L["Unknown word: %s"], token)
    end
    B:Say(
      L["Try a line: /bcourtesy try [situation] [mood] [weather] [time] [race] [class] [m/f] [me:race] [number] [ring]"] -- luacheck: ignore 631 (a locale key stays one literal)
    )
    return false
  end
  if w.ring then
    return Try.Ring(w, rand)
  end
  for _ = 1, w.count or Try.DEFAULT do
    choose(w, Try.Invent(w, Mine.Pool(), rand), rand)
  end
  return true
end
