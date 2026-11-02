-- Bastian's Voice, the bridge (voice.md §2): the line of an entity (a quest's accept line, a zone's
-- or area's lore, a boss's story, a readable's pages), Voice's own source in Spoken's player for
-- everything but quests (which keep Spoken Quests' player), play and stop, the heard list.
local ADDON, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice
local Model = Voice.Model
local SD = ns.SpokenData

local lines = {} -- ref -> line | false, asked once per session (the packs do not change)
local source -- Voice's Spoken source, registered on first use

local function data()
  return B:GetService("data")
end

local function entityName(ref)
  return B:Entity(ref):Name()
end

-- The zone a Data area is kept in (its record's `zone`, else its place's map).
local function areaZone(id)
  local d = data()
  local r = d and d:Get("area", id)
  if r and r.zone then
    return r.zone
  end
  local places = B:Entity("area:" .. id):Locations()
  return places[1] and places[1].map or nil
end

-- A line: { kind, key, title, ref, textOnly, clip | pages | sound }. The builders below return nil
-- where no installed pack has the line.
local builders = {}

-- Whether the game's voice may read a text where Spoken has no line (the setting, and the client's
-- text to speech with a voice).
function Voice.TtsOn()
  local mod = Voice.mod
  local p = mod and mod.db and mod.db.profile
  return (p == nil or p.tts ~= false) and B.Compat.CanSpeak()
end

-- The hub's and the About page's words while Spoken is missing ("I
-- enabled the voice narrator ... still only get 'Spoken is not installed' and no voice"): what
-- reads instead, or why nothing does.
function Voice.NoSpokenNote()
  if Voice.TtsOn() then
    return L["Spoken is not installed: the game's voice reads the quest texts"]
  end
  local mod = Voice.mod
  local p = mod and mod.db and mod.db.profile
  if p and p.tts == false then
    return L["Spoken is not installed; the game's voice is switched off in the Orbiter's settings"]
  end
  return L["Spoken is not installed, and the game lists no voice yet (Options, Accessibility, Text to Speech)"] -- luacheck: ignore 631 (a locale key stays one literal)
end

-- A quest's text for the game's voice: the Text pack's (details, objectives, offer) where it is
-- loaded, else the client's own text of a log quest; nil without either.
function Voice.QuestText(id)
  local d = data()
  local t = d and d:PackLoaded("text") and d:Get("questText", id) or nil
  local parts = {}
  if t then
    parts[#parts + 1] = t.details
    parts[#parts + 1] = t.objectives
  else
    local details, objectives = B.Compat.GetQuestText(id)
    parts[#parts + 1] = details
    parts[#parts + 1] = objectives
  end
  local out = {}
  for _, p in ipairs(parts) do
    if type(p) == "string" and p ~= "" then
      out[#out + 1] = p
    end
  end
  if #out == 0 then
    return nil
  end
  return table.concat(out, " ")
end

function builders.quest(id, ref)
  local title = entityName(ref)
  local sound = SD.Spoken() and SD.QuestSound(id, title, "accept") or nil
  if sound then
    return { kind = "quest", key = Model.Key("quest", id, "accept"), title = title, ref = ref, questID = id }
  end
  -- the fallback: the game's voice reads the text
  local text = Voice.TtsOn() and Voice.QuestText(id) or nil
  if not text then
    return nil
  end
  return {
    kind = "quest",
    tts = true,
    key = "t:" .. Model.Key("quest", id, "accept"),
    title = title,
    ref = ref,
    questID = id,
    text = text,
  }
end

-- A zone's name: our data's, else the client's.
function Voice.ZoneName(id)
  local name = B:Entity("zone:" .. id):Name()
  if name then
    return name
  end
  local info = C_Map.GetMapInfo(id)
  return info and info.name or tostring(id)
end

function builders.zone(id, ref)
  local clip = SD.ZoneClip(id)
  if not clip then
    return nil
  end
  return {
    kind = "zone",
    key = Model.Key("zone", id),
    title = Voice.ZoneName(id),
    ref = ref,
    clip = clip,
    mapID = id,
  }
end

function builders.area(id, ref)
  local name = entityName(ref)
  local key = Model.AreaKey(name)
  local mapID = areaZone(id)
  local clip = key and mapID and SD.AreaClip(mapID, key)
  if not clip then
    return nil
  end
  return {
    kind = "area",
    key = Model.Key("area", mapID, key),
    title = name,
    ref = ref,
    clip = clip,
    mapID = mapID,
  }
end

function builders.npc(id, ref)
  local boss = SD.Boss(id)
  if not boss then
    return nil
  end
  return {
    kind = "boss",
    key = Model.Key("boss", boss.map, boss.key),
    title = entityName(ref) or SD.BossName(boss),
    ref = ref,
    textOnly = true,
    story = boss.story,
    creature = boss.creature,
    display = boss.display,
    map = boss.map,
  }
end

-- A readable by its title (the item's or object's name; English clients, voice.md §2).
local function readable(title, ref)
  local pages = title and SD.BookPages(title)
  if not pages then
    return nil
  end
  local clips = {}
  for _, pageId in ipairs(pages) do
    local clip = SD.PageClip(pageId)
    if clip then
      clips[#clips + 1] = clip
      clip.pageId = pageId
    end
  end
  if #clips == 0 then
    return nil
  end
  local bookId = SD.BookOf(pages[1])
  return {
    kind = "read",
    key = Model.Key("read", bookId or pages[1]),
    title = title,
    ref = ref,
    pages = clips,
    bookId = bookId,
  }
end

function builders.item(_, ref)
  return readable(entityName(ref), ref)
end
builders.object = builders.item

-- A readable without an entity (the zone's list from Spoken): by its book id.
function Voice.BookLine(bookId, title)
  local pages = SD.PagesOf(bookId)
  if not pages then
    return nil
  end
  local clips = {}
  for _, pageId in ipairs(pages) do
    local clip = SD.PageClip(pageId)
    if clip then
      clip.pageId = pageId
      clips[#clips + 1] = clip
    end
  end
  if #clips == 0 then
    return nil
  end
  return { kind = "read", key = Model.Key("read", bookId), title = title, pages = clips, bookId = bookId }
end

-- A dungeon's story (a Places area in Spoken's dungeon table), without an entity ref.
function Voice.DungeonLine(instanceMap, title)
  local mapID, key = SD.DungeonStory(instanceMap)
  local clip = mapID and SD.AreaClip(mapID, key)
  if not clip then
    return nil
  end
  return { kind = "dungeon", key = Model.Key("area", mapID, key), title = title, clip = clip, mapID = mapID }
end

-- The line of an entity, or nil; cached per ref (ADR 0013: `has` is asked while rendering rows).
function Voice.Line(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local known = lines[ref]
  if known ~= nil then
    return known or nil
  end
  local typ, id = B.Entity.Parse(ref)
  if not SD.Spoken() and typ ~= "quest" then
    return nil -- only a quest's text has the game's voice as a fallback
  end
  local build = builders[typ]
  local line = build and type(id) == "number" and build(id, ref) or nil
  lines[ref] = line or false
  return line
end

function Voice.Has(ref)
  return Voice.Line(ref) ~= nil
end

-- Dropped when the packs load or the language changes.
function Voice.Reset()
  lines = {}
  SD.Reset()
end

-- ---------------------------------------------------------------------------------------------
-- Heard
-- ---------------------------------------------------------------------------------------------

local function heardList()
  local mod = Voice.mod
  local char = mod and mod.db and mod.db.char
  if not char then
    return nil
  end
  if type(rawget(char, "heard")) ~= "table" then
    rawset(char, "heard", {})
  end
  return char.heard
end

function Voice.IsHeard(key)
  local list = heardList()
  return list ~= nil and key ~= nil and list[key] == true
end

-- The line of the place the player stands in: the area the client names where Spoken has its
-- lore, else the zone; nil without a line (plan-second-wave.md S6: Gestures' "Mark heard").
function Voice.HereLine()
  local uiMapID = C_Map.GetBestMapForUnit("player")
  if not uiMapID then
    return nil
  end
  local sub = GetSubZoneText()
  if type(sub) == "string" and sub ~= "" then
    local key = Model.AreaKey(sub)
    local clip = key and SD.AreaClip(uiMapID, key)
    if clip then
      return {
        kind = "area",
        key = Model.Key("area", uiMapID, key),
        title = sub,
        clip = clip,
        mapID = uiMapID,
      }
    end
  end
  return Voice.Line("zone:" .. uiMapID)
end

function Voice.MarkHeard(key, on)
  local list = heardList()
  if not (list and key) then
    return false
  end
  list[key] = (on ~= false) and true or nil
  B:Fire("BASTIANS_VOICE_CHANGED")
  return true
end

-- ---------------------------------------------------------------------------------------------
-- Playing through Spoken
-- ---------------------------------------------------------------------------------------------

-- Voice's source in Spoken's player, registered once (Spoken:RegisterSource is the documented way
-- a feature addon joins the player).
function Voice.Source()
  if source then
    return source
  end
  local Spoken = SD.Spoken()
  if not (Spoken and Spoken.RegisterSource) then
    return nil
  end
  source = Spoken:RegisterSource("bastians", {
    title = L["Bastian's"],
    addon = ADDON,
    icon = B.UI.IconTexture("voice"),
    about = L["Zones, areas, bosses and books from Bastian's apps and the Lore Orbit."],
    order = 9,
  })
  return source
end

local function stopped(clip, finished)
  if finished and clip.key then
    Voice.MarkHeard(clip.key)
  end
end

-- The clips of a line as Spoken's player takes them: one for a zone, an area or a boss (text
-- only), one per page of a readable, grouped so they read on without a cue between.
function Voice.Clips(line)
  local out = {}
  if line.kind == "read" then
    for i, page in ipairs(line.pages) do
      local _, _, number, total = SD.BookOf(page.pageId)
      out[#out + 1] = {
        key = line.key .. ":" .. tostring(page.pageId),
        path = page.path,
        length = page.length,
        group = "book:" .. tostring(line.bookId or line.key),
        present = {
          header = line.title,
          label = total and total > 1 and string.format(L["page %d of %d"], number or i, total) or nil,
          transcript = page.text,
          timings = page.times,
          bullet = "book",
        },
        stopCallback = i == #line.pages and stopped or nil,
        line = line.key,
      }
    end
  elseif line.kind == "boss" then
    out[1] = {
      key = line.key,
      textOnly = true,
      length = Model.ReadingTime(line.story),
      priority = "low",
      present = {
        header = line.ref and B:Entity(line.ref):Summary() or nil,
        label = line.title,
        transcript = line.story,
        bullet = "boss",
        portrait = line.display and { kind = "model", creatureID = line.creature, displayID = line.display }
          or nil,
      },
      stopCallback = stopped,
      line = line.key,
    }
  elseif line.clip then
    local present = {
      header = line.kind == "area" and line.mapID and Voice.ZoneName(line.mapID) or nil,
      label = line.title,
      timings = line.clip.times,
      bullet = "zone",
    }
    out[1] = {
      key = line.key,
      path = line.clip.path,
      length = line.clip.length,
      present = present,
      stopCallback = stopped,
      line = line.key,
    }
  end
  return out
end

-- Every clip of ours or of the quests source in Spoken's queue with this line's key.
function Voice.Queued(line)
  local Spoken = SD.Spoken()
  if not (Spoken and line) then
    return {}
  end
  local out = {}
  for _, clip in ipairs(Spoken:GetQueue() or {}) do
    if clip.line == line.key or clip.key == line.key or (line.questID and clip.questID == line.questID) then
      out[#out + 1] = clip
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The game's voice (text to speech): one text at a time, no queue, no pause
-- ---------------------------------------------------------------------------------------------

local tts -- { key, title, ref, text, started, length } while the game's voice reads

local function ttsChanged()
  B:Fire("BASTIANS_VOICE_CHANGED")
  if Voice.mod then
    Voice.mod:Fire("BASTIANS_ACTION_STATE", "voice.play")
  end
end

-- The client's text to speech is shared with Spoken (its own queue) and Spoken Players (the
-- people's lines): three voices must not talk over each other (plan-second-wave.md S2). A line
-- another addon started (VOICE_CHAT_TTS_PLAYBACK_STARTED without our own call just before)
-- holds the suite's words until its end: `durationMS` of the event is assumed (forever-api.md),
-- ten seconds without it; the finished or failed event ends the hold early.
local ownStart = false
local otherUntil = 0
local OTHER_HOLD_S = 10

function Voice.TtsStarted(...)
  if ownStart then
    ownStart = false
    return
  end
  local numbers = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "number" then
      numbers[#numbers + 1] = v
    end
  end
  local duration = numbers[2] -- utteranceID, durationMS
  otherUntil = GetTime() + (duration and duration > 0 and duration / 1000 or OTHER_HOLD_S)
end

function Voice.OtherTtsPlaying()
  return otherUntil > GetTime()
end

local function speakOwn(text, voiceID)
  ownStart = true
  local ok = B.Compat.Speak(text, voiceID)
  if not ok then
    ownStart = false
  end
  return ok
end

-- The suite's own words (Core's `voice` service, plan-launch-review R5.3): a notice, a reminder,
-- a route step or an arrival read by the game's voice in the chosen voice. One text at a time:
-- a line spoken while another plays takes its place (the client's TTS has no queue).
function Voice.SpeakWords(text)
  if not Voice.TtsOn() or type(text) ~= "string" or text == "" then
    return false
  end
  -- never over Spoken's line or another addon's: the words fall back to their text form
  local Spoken = SD.Spoken()
  if (Spoken and Spoken.IsPlaying and Spoken:IsPlaying()) or Voice.OtherTtsPlaying() then
    return false
  end
  return speakOwn(text, Voice.ChosenVoice()) and true or false
end

-- Spoken's version against the one the suite was tested with (B.TESTED_WITH, plan-second-wave.md
-- S2, ): nil while they match or Spoken names no version, else one sentence for the
-- hub's note. Versions compare part by part ("3.7.0" < "3.10.0").
local function versionParts(v)
  local parts = {}
  for n in tostring(v):gmatch("%d+") do
    parts[#parts + 1] = tonumber(n)
  end
  return parts
end

function Voice.VersionCompare(a, b)
  local pa, pb = versionParts(a), versionParts(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then
      return x < y and -1 or 1
    end
  end
  return 0
end

function Voice.SpokenVersionNote()
  local Spoken = SD.Spoken()
  local tested = B.TESTED_WITH and B.TESTED_WITH.Spoken
  local have = Spoken and rawget(Spoken, "ADDON_VERSION")
  if not (Spoken and tested and type(have) == "string") then
    return nil
  end
  local c = Voice.VersionCompare(have, tested)
  if c > 0 then
    return string.format(L["Spoken %s is newer than the suite was tested with (%s)"], have, tested)
  elseif c < 0 then
    return string.format(
      L["Spoken %s is older than %s: boss stories and the newest lines are missing"],
      have,
      tested
    )
  end
  return nil
end

-- The voice the player chose in the Orbiter's settings ("auto": Compat's woman's voice).
function Voice.ChosenVoice()
  local mod = Voice.mod
  local p = mod and mod.db and mod.db.profile
  return p and tonumber(p.voice) or nil
end

local function ttsSpeak(line)
  if not speakOwn(line.text, Voice.ChosenVoice()) then
    return false
  end
  tts = {
    key = line.key,
    title = line.title,
    ref = line.ref,
    text = line.text,
    started = GetTime(),
    length = Model.ReadingTime(line.text),
  }
  ttsChanged()
  return true
end

local function ttsStop()
  if not tts then
    return false
  end
  tts = nil
  B.Compat.StopSpeaking()
  ttsChanged()
  return true
end

-- The game's voice finished (VOICE_CHAT_TTS_PLAYBACK_FINISHED): the text is heard.
function Voice.TtsFinished()
  otherUntil = 0
  if not tts then
    return
  end
  local key = tts.key
  tts = nil
  Voice.MarkHeard(key)
  ttsChanged()
end

function Voice.TtsFailed()
  otherUntil = 0
  if tts then
    tts = nil
    ttsChanged()
  end
end

-- Whether a line is queued or playing.
function Voice.Playing(ref)
  local line = type(ref) == "table" and ref or Voice.Line(ref)
  if not line then
    return false
  end
  if line.tts then
    return tts ~= nil and tts.key == line.key
  end
  return #Voice.Queued(line) > 0
end

-- Plays a line now (`queue` = true: after what plays). Returns true, or false and why ("missing":
-- no Spoken; "noline"; "refused": the player did not take it).
function Voice.Play(line, queue)
  if type(line) == "string" then
    line = Voice.Line(line)
  end
  if not line then
    return false, "noline"
  end
  if line.tts then
    return ttsSpeak(line) or false, "refused"
  end
  local Spoken = SD.Spoken()
  if not Spoken then
    return false, "missing"
  end
  if line.kind == "quest" then
    local sound = SD.QuestSound(line.questID, line.title, "accept")
    if not sound then
      lines[line.ref] = false
      return false, "noline"
    end
    sound.stopCallback = stopped
    sound.line = line.key
    if not SD.PlayQuestSound(sound) then
      return false, "missing"
    end
    ttsChanged() -- the feed and the buttons follow (S12)
    return true
  end
  local src = Voice.Source()
  if not src then
    return false, "missing"
  end
  local clips = Voice.Clips(line)
  if #clips == 0 then
    return false, "noline"
  end
  if line.textOnly and Spoken.ShowsNarratorFor and not Spoken:ShowsNarratorFor("bastians") then
    return false, "refused" -- a text-only line is worth queueing only where the narrator shows words
  end
  local taken = 0
  for i, clip in ipairs(clips) do
    local ok
    if i == 1 and not queue then
      ok = src:PlayNow(clip)
    else
      ok = src:Enqueue(clip, true) -- asked for: read in a battleground too
    end
    if ok then
      taken = taken + 1
    end
  end
  if taken == 0 then
    return false, "refused"
  end
  ttsChanged() -- the feed and the buttons follow (S12)
  return true
end

-- Removes a line's clips from the queue (ours through the source, a quest's through Spoken's
-- quests source).
function Voice.Stop(line)
  if type(line) == "string" then
    line = Voice.Line(line)
  end
  if line and line.tts then
    return Voice.Playing(line) and ttsStop() or false
  end
  local Spoken = SD.Spoken()
  if not (Spoken and line) then
    return false
  end
  local clips = Voice.Queued(line)
  if #clips == 0 then
    return false
  end
  local quests = line.kind == "quest" and Spoken:GetSource("quests") or nil
  for _, clip in ipairs(clips) do
    local src = clip.source or quests or source
    if src and src.Remove then
      src:Remove(clip)
    else
      Spoken:StopAll()
      break
    end
  end
  ttsChanged() -- the feed and the buttons follow (S12)
  return true
end

-- Play, or stop when it is queued already. Returns true and "playing" | "stopped", or false and the
-- reason of Voice.Play.
function Voice.Toggle(ref, queue)
  local line = Voice.Line(ref)
  if not line then
    return false, (SD.Spoken() or Voice.TtsOn()) and "noline" or "missing"
  end
  if Voice.Playing(line) then
    Voice.Stop(line)
    return true, "stopped"
  end
  local ok, why = Voice.Play(line, queue)
  if not ok then
    return false, why
  end
  return true, "playing"
end

function Voice.StopAll()
  ttsStop()
  local Spoken = SD.Spoken()
  if Spoken then
    Spoken:StopAll()
  end
  ttsChanged()
end

-- The player's state for the hub: { clip, title, progress (0..1 or nil), paused, speaking, tts }.
function Voice.Now()
  if tts then
    local elapsed = GetTime() - tts.started
    return {
      clip = { length = tts.length, ref = tts.ref, key = tts.key },
      title = tts.title,
      progress = math.min(1, elapsed / tts.length),
      paused = false,
      speaking = true,
      key = tts.key,
      tts = true,
    }
  end
  local Spoken = SD.Spoken()
  if not Spoken then
    return nil
  end
  local head = Spoken.GetNowPlaying and Spoken:GetNowPlaying() or Spoken:GetCurrent()
  if not head then
    return nil
  end
  local caption = Spoken.GetCaption and Spoken:GetCaption() or nil
  local present = head.present or {}
  return {
    clip = head,
    title = present.label or head.title or present.header,
    progress = caption and caption.progress or nil,
    paused = Spoken:IsPaused() and true or false,
    speaking = caption and caption.speaking or false,
    key = head.line or head.key,
  }
end

-- The game's voice has no pause: it stops.
function Voice.TogglePause()
  if tts then
    ttsStop()
    return
  end
  local Spoken = SD.Spoken()
  if Spoken and Spoken.TogglePause then
    Spoken:TogglePause()
  end
end

-- Jump to the start: Spoken has no seek, so the head plays again from its start.
function Voice.Restart()
  if tts then
    return ttsSpeak(tts)
  end
  local Spoken = SD.Spoken()
  if not Spoken then
    return false
  end
  local head = Spoken:GetCurrent()
  if not head then
    return false
  end
  local src = head.source
  if src and src.Remove and src.PlayNow then
    local again = {}
    for k, v in pairs(head) do
      again[k] = v
    end
    again.id, again.handle, again.source, again.nextSoundTimer = nil, nil, nil, nil
    src:Remove(head)
    src:PlayNow(again)
    return true
  end
  if Spoken.Pause and Spoken.Resume then
    Spoken:Pause()
    Spoken:Resume() -- resume replays from the start (Spoken's API)
    return true
  end
  return false
end
