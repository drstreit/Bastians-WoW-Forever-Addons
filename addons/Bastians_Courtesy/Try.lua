-- /bcourtesy try (courtesy.md): the lines without another player. Invented moments are printed to the
-- player's own chat and nothing is sent; `ring` opens the real ring on the real facts, and a click
-- on it really sends the line.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style
local Model, Voice, Mine, Facts = ns.Model, ns.Voice, ns.Mine, ns.Facts

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
local LEVELS = { "higher", "lower", "peer" }
local FLAGS = { "fight", "heavy", "hurt", "many" } -- a word says it is so; unnamed, chance decides
-- An example place for each kind of country: { zone, the place in it }, so that an invented moment
-- does not put sand into Elwynn. English names: the real moment has the client's own.
local PLACES = {
  forest = { "Elwynn Forest", "Goldshire" },
  jungle = { "Stranglethorn Vale", "Nesingwary's Expedition" },
  swamp = { "Wetlands", "Menethil Harbor" },
  plains = { "The Barrens", "The Crossroads" },
  desert = { "Tanaris", "Gadgetzan" },
  mountains = { "Redridge Mountains", "Lakeshire" },
  frost = { "Dun Morogh", "Kharanos" },
  waste = { "Western Plaguelands", "Andorhal" },
  city = { "Stormwind City", "Trade District" },
}
-- An example spell for a buff situation when the client names none of the kind.
local SPELLS = {
  mind = "Arcane Intellect",
  stamina = "Power Word: Fortitude",
  nature = "Mark of the Wild",
  ["nature.thorns"] = "Thorns",
  blessing = "Blessing of Light",
  ["blessing.might"] = "Blessing of Might",
  ["blessing.wisdom"] = "Blessing of Wisdom",
  ["blessing.kings"] = "Blessing of Kings",
  shield = "Power Word: Shield",
  heal = "Renew",
}

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

-- What a /bcourtesy try asks for: { situation, mood, weather, time, land, level, fight, heavy, hurt,
-- many, race, class, sex, myRace, mySex, count, ring, unknown = { words } }. Any order; lower or
-- upper case.
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
    elseif PLACES[token] then
      w.land = token
    elseif has(LEVELS, token) then
      w.level = token
    elseif has(FLAGS, token) then
      w[token] = true
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

-- The spell of a buff situation: the client's name of one of that kind, else an example's.
local function spellOf(situation)
  local kind = string.match(situation or "", "^buff%.(.+)$")
  if not kind then
    return situation == "buff" and SPELLS.nature or nil
  end
  local ids = {}
  for id, of in pairs(Model.BUFFS) do
    if of == kind then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return (ids[1] and B.Compat.GetSpellName(ids[1])) or SPELLS[kind]
end

-- What only a buff has: the spell, a fight, more than one; named by the words or, with `rand`, by
-- chance. The words never take away what the moment has.
local function buffFacts(facts, w, rand)
  if not string.find(facts.situation or "", "^buff") then
    return
  end
  facts.spell = facts.spell or spellOf(facts.situation)
  for _, flag in ipairs({ "fight", "many" }) do
    if w[flag] then
      facts[flag] = true
    elseif rand then
      facts[flag] = rand() < 0.25
    end
  end
end

-- An invented moment: the words first, the rest by chance.
function Try.Invent(w, lines, rand)
  local facts = Facts.Surroundings(speaker(w))
  facts.situation = w.situation or pick(sortedKeys(Voice.Situations(lines)), rand)
  facts.target = Try.NAME
  facts.time = w.time or pick(TIMES, rand)
  facts.weather = w.weather or pick(WEATHERS, rand)
  facts.heavy = nil
  if facts.weather ~= "clear" then
    facts.heavy = w.heavy or rand() < 0.25
  end
  facts.land = w.land or pick(sortedKeys(PLACES), rand)
  facts.zone, facts.subzone = PLACES[facts.land][1], PLACES[facts.land][2]
  facts.level = w.level or pick(LEVELS, rand)
  facts.hurt = w.hurt or rand() < 0.25
  buffFacts(facts, w, rand)
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
  facts.land = w.land or facts.land
  facts.level = w.level or facts.level
  facts.heavy = w.heavy or facts.heavy
  facts.hurt = w.hurt or facts.hurt
  buffFacts(facts, w)
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
  for _, fact in ipairs({ facts.land or false, facts.level or false }) do
    if fact then
      tag[#tag + 1] = fact
    end
  end
  for _, flag in ipairs(FLAGS) do
    if facts[flag] then
      tag[#tag + 1] = flag
    end
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
      L["Try a line: /bcourtesy try [situation] [mood] [weather] [time] [race] [class] [m/f] [me:race] [land] [higher/lower] [fight] [heavy] [hurt] [many] [number] [ring]"] -- luacheck: ignore 631 (a locale key stays one literal)
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
