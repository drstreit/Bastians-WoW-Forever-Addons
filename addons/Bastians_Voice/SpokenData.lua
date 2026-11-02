-- Bastian's Voice, every reach into Spoken (voice.md §1): the public API of the player, Spoken
-- Quests' VoiceOver environment for a quest's line, and the data the modules keep in globals: the
-- voice pack registries of Places and Readables, the readables' index, the bosses' stories. Each
-- table is shape-checked here and nowhere else; a table that is missing or changed means no lines
-- of that kind, never an error. Read 01.11.2026 from the Forever install (Spoken 3.5, API 1).
local _, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice
local Model = Voice.Model

local SD = {}
ns.SpokenData = SD

local REQUIRED_API = 1
local PACK_FORMAT = 1 -- both registries' `version`

local function global(name)
  local value = rawget(_G, name)
  return type(value) == "table" and value or nil
end

-- Spoken itself, or nil and the reason (a locale string for the settings hub).
function SD.Spoken()
  local Spoken = global("Spoken")
  if not Spoken or type(Spoken.IsCompatible) ~= "function" then
    return nil, L["Spoken is not installed: no voice lines"]
  end
  if not Spoken:IsCompatible(REQUIRED_API) then
    return nil, L["Spoken is too old for the voice lines"]
  end
  return Spoken
end

-- Spoken Quests' environment, as the old Quests bridge reached it: PrepareSound builds a quest
-- line's clip, PlayNow plays it in the quests source.
function SD.VoiceOver()
  local Spoken, why = SD.Spoken()
  if not Spoken then
    return nil, why
  end
  local VO = global("VoiceOver")
  local DM = VO and rawget(VO, "DataModules")
  local P = VO and rawget(VO, "Player")
  local E = VO and rawget(VO, "Enums")
  if
    type(DM) ~= "table"
    or type(DM.PrepareSound) ~= "function"
    or type(P) ~= "table"
    or type(P.PlayNow) ~= "function"
    or type(E) ~= "table"
    or type(E.SoundEvent) ~= "table"
  then
    return nil, L["Spoken Quests is not installed or changed: no quest lines"]
  end
  return VO
end

-- The languages a line is looked for in, in order: Spoken's voice language, then the fallback it
-- names (none with "Stay silent"). Without Spoken's choice, the client's.
function SD.Languages()
  local Spoken = SD.Spoken()
  local voice, fallback
  if Spoken and Spoken.VoiceLanguage then
    voice = Spoken:VoiceLanguage()
  end
  if Spoken and Spoken.GetLanguageChoice then
    local _, fb = Spoken:GetLanguageChoice()
    fallback = fb
  end
  voice = voice or GetLocale()
  local out = { voice }
  if fallback and fallback ~= "none" and fallback ~= voice then
    out[2] = fallback
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- Voice packs: the registries the pack addons write into (Spoken: "reading them is permanent")
-- ---------------------------------------------------------------------------------------------

local packCache = {}

-- Every pack of the registries, newest registry first, a folder seen once (a pack renamed from its
-- old folder name is the same pack); packs of another format are left out.
local function collect(kind, registries, renames)
  if packCache[kind] then
    return packCache[kind]
  end
  local packs, seen = {}, {}
  for _, registry in ipairs(registries) do
    local table_ = global(registry)
    if table_ then
      local names = {}
      for name in pairs(table_) do
        names[#names + 1] = name
      end
      table.sort(names)
      for _, name in ipairs(names) do
        local pack = table_[name]
        local renamed = renames and string.gsub(name, renames[1], renames[2]) or name
        if type(pack) == "table" and not seen[name] and not seen[renamed] then
          seen[name] = true
          if pack.version == PACK_FORMAT then
            pack.language = pack.language or "enUS"
            pack.addon = pack.addon or name
            packs[#packs + 1] = pack
          end
        end
      end
    end
  end
  packCache[kind] = packs
  return packs
end

function SD.PlacePacks()
  return collect(
    "places",
    { "SpokenPlacesAudioPacks", "SpokenZonesAudioPacks", "ZoneLoreAudioPacks" },
    { "^SpokenZonesAudio", "SpokenPlacesAudio" }
  )
end

function SD.ReadablePacks()
  return collect(
    "readables",
    { "SpokenReadablesAudioPacks", "SpokenBooksAudioPacks" },
    { "^SpokenBooksAudio", "SpokenReadablesAudio" }
  )
end

-- The packs' lists change only when a pack loads (VOICE_PACKS_LOADED) or the language is chosen.
function SD.Reset()
  packCache = {}
end

local function soundPath(pack, file)
  return "Interface\\AddOns\\" .. pack.addon .. "\\Sounds\\" .. file .. ".mp3"
end

-- The first pack in language order that has `pick(pack)`: returns the entry and its pack.
local function firstEntry(packs, pick)
  for _, lang in ipairs(SD.Languages()) do
    for _, pack in ipairs(packs) do
      if pack.language == lang then
        local entry = pick(pack)
        if type(entry) == "table" and entry.file then
          return entry, pack
        end
      end
    end
  end
  return nil
end

-- A zone's lore: { path, length, times } or nil (Spoken Places' `zones[mapID]`).
function SD.ZoneClip(mapID)
  local entry, pack = firstEntry(SD.PlacePacks(), function(pack)
    return pack.zones and pack.zones[mapID]
  end)
  if not entry then
    return nil
  end
  return {
    path = soundPath(pack, entry.file),
    length = entry.len,
    times = entry.times,
    language = pack.language,
  }
end

-- An area's lore by the zone it is kept under and Spoken's key of its name (`subzones[mapID][key]`).
function SD.AreaClip(mapID, key)
  if not key then
    return nil
  end
  local entry, pack = firstEntry(SD.PlacePacks(), function(pack)
    local zone = pack.subzones and pack.subzones[mapID]
    return zone and zone[key]
  end)
  if not entry then
    return nil
  end
  return {
    path = soundPath(pack, entry.file),
    length = entry.len,
    times = entry.times,
    language = pack.language,
  }
end

-- The dungeon's story as Spoken keeps it: the Places area telling it ({ mapID, key }) from
-- Spoken's Data/Dungeons.lua, or nil.
function SD.DungeonStory(instanceMap)
  local dungeons = global("SpokenDungeons")
  local entry = dungeons and type(dungeons.dungeons) == "table" and dungeons.dungeons[instanceMap]
  local story = type(entry) == "table" and entry.story
  if type(story) == "table" and story[1] and story[2] then
    return story[1], story[2]
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- Readables: SpokenReadablesData (the corpus) and SpokenReadablesPlaces (where each one is)
-- ---------------------------------------------------------------------------------------------

local function readables()
  local data = global("SpokenReadablesData")
  if data and type(data.index) == "table" and type(data.books) == "table" then
    return data
  end
  return nil
end

-- The page ids of the readable titled `title`, in page order; nil when the corpus has no such title.
function SD.BookPages(title)
  local data = readables()
  local pages = data and title and data.index[title]
  if type(pages) ~= "table" then
    return nil
  end
  local numbers = {}
  for n, byChecksum in pairs(pages) do
    if type(n) == "number" and type(byChecksum) == "table" then
      numbers[#numbers + 1] = n
    end
  end
  table.sort(numbers)
  local out = {}
  for _, n in ipairs(numbers) do
    local pageId
    for _, id in pairs(pages[n]) do
      if pageId == nil or id < pageId then
        pageId = id -- one page may have several checksums (the text changed); any names the page
      end
    end
    out[#out + 1] = pageId
  end
  return #out > 0 and out or nil
end

-- A page's clip: { path, length (nil when the pack recorded none), text, times } or nil.
function SD.PageClip(pageId)
  local entry, pack = firstEntry(SD.ReadablePacks(), function(pack)
    return pack.pages and pack.pages[pageId]
  end)
  if not entry then
    return nil
  end
  local length = entry.len
  if type(length) ~= "number" or length <= 0 then
    length = nil
  end
  return {
    path = soundPath(pack, entry.file),
    length = length,
    text = entry.text,
    times = entry.times,
    language = pack.language,
  }
end

-- The book a page belongs to and its title (`data.pages[pageId] = { book, number }`).
function SD.BookOf(pageId)
  local data = readables()
  local place = data and type(data.pages) == "table" and data.pages[pageId]
  local book = place and data.books[place.book]
  if type(book) ~= "table" then
    return nil
  end
  return place.book, book.title, place.number, type(book.pages) == "table" and #book.pages or nil
end

-- The readables Spoken lists for a zone: { { bookId, title, kind, type } }, sorted by title.
function SD.ReadablesIn(mapID)
  local data, places = readables(), global("SpokenReadablesPlaces")
  if not (data and places and type(places.books) == "table") then
    return {}
  end
  local out = {}
  for bookId, place in pairs(places.books) do
    local book = data.books[bookId]
    if type(place) == "table" and type(book) == "table" and type(place.zones) == "table" then
      for _, zone in ipairs(place.zones) do
        if zone == mapID then
          out[#out + 1] = { bookId = bookId, title = book.title, kind = place.kind, type = place.type }
          break
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.title) < tostring(b.title)
  end)
  return out
end

-- The pages of a book by its id, in order.
function SD.PagesOf(bookId)
  local data = readables()
  local book = data and data.books[bookId]
  if type(book) ~= "table" or type(book.pages) ~= "table" then
    return nil
  end
  return book.pages
end

-- ---------------------------------------------------------------------------------------------
-- Bosses: SpokenBossCreatures (creature ids) and SpokenBossStories (text, no voice)
-- ---------------------------------------------------------------------------------------------

local byCreature

local function bosses()
  local creatures, stories = global("SpokenBossCreatures"), global("SpokenBossStories")
  if not (creatures and stories) then
    return nil
  end
  return creatures, stories
end

-- A boss by its creature id: { map, key, creature, display, story } or nil without a story.
function SD.Boss(creatureID)
  local creatures, stories = bosses()
  if not creatures then
    return nil
  end
  if not byCreature then
    byCreature = {}
    for map, list in pairs(creatures) do
      if type(list) == "table" then
        for key, entry in pairs(list) do
          if type(entry) == "table" and entry.creature then
            byCreature[entry.creature] = { map = map, key = key, display = entry.display }
          end
        end
      end
    end
  end
  local found = byCreature[creatureID]
  local story = found and stories[found.map] and stories[found.map][found.key]
  if type(story) ~= "string" then
    return nil
  end
  return { map = found.map, key = found.key, creature = creatureID, display = found.display, story = story }
end

-- The bosses of an instance map with a story, by key.
function SD.BossesOf(instanceMap)
  local creatures, stories = bosses()
  local list = creatures and creatures[instanceMap]
  local told = stories and stories[instanceMap]
  local out = {}
  if type(list) == "table" and type(told) == "table" then
    for key, entry in pairs(list) do
      if type(entry) == "table" and type(told[key]) == "string" then
        out[#out + 1] = {
          map = instanceMap,
          key = key,
          creature = entry.creature,
          display = entry.display,
          story = told[key],
        }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

-- The name of a boss key ("edwin vancleef" -> "Edwin Vancleef"); our data's NPC name is better
-- where the creature is known.
function SD.BossName(boss)
  if boss.creature then
    local name = B:Entity("npc:" .. boss.creature):Name()
    if name then
      return name
    end
  end
  return (
    string.gsub(boss.key, "(%a)(%w*)", function(first, rest)
      return string.upper(first) .. rest
    end)
  )
end

-- ---------------------------------------------------------------------------------------------
-- Quest lines through Spoken Quests (as Quests.Spoken did before Voice)
-- ---------------------------------------------------------------------------------------------

-- The sound table of a quest's line, prepared by Spoken Quests (the path filled in), or nil when no
-- installed pack has it. `event` is "accept" (default), "progress" or "complete".
function SD.QuestSound(questID, title, event)
  local VO = SD.VoiceOver()
  if not VO then
    return nil
  end
  local DM, E = VO.DataModules, VO.Enums
  local eventName = "QuestAccept"
  if event == "progress" then
    eventName = "QuestProgress"
  elseif event == "complete" then
    eventName = "QuestComplete"
  end
  local eventID = E.SoundEvent[eventName]
  if not eventID then
    return nil
  end
  local kind, id
  if DM.GetQuestLogQuestGiverTypeAndID then
    kind, id = DM:GetQuestLogQuestGiverTypeAndID(questID)
  end
  local U, G = rawget(VO, "Utils"), E.GUID
  local canGUID = id and G and G.CanHaveID and G:CanHaveID(kind) and U and U.MakeGUID
  local sound = {
    event = eventID,
    questID = questID,
    title = title,
    name = (id and DM.GetObjectName and DM:GetObjectName(kind, id)) or title or "Unknown Name",
    unitGUID = canGUID and U:MakeGUID(kind, id) or nil,
    unitIsObjectOrItem = id ~= nil and not (G and G.IsCreature and G:IsCreature(kind)),
    origin = "Bastians_Voice",
  }
  if not DM:PrepareSound(sound) then
    return nil
  end
  sound.key = sound.key or Model.Key("quest", questID, event or "accept")
  return sound
end

-- Plays a prepared quest sound now in Spoken's quests source.
function SD.PlayQuestSound(sound)
  local VO = SD.VoiceOver()
  if not VO then
    return false
  end
  VO.Player:PlayNow(sound)
  return true
end
