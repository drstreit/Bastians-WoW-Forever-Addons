-- Bastian's Voice, the modules (voice.md): `Voice` with the play action and the settings,
-- `Voice.Orbit` the round panel, `Voice.Talk` the conversation (off by default), `/bv`.
local ADDON, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice
local SD = ns.SpokenData
local Orbit = ns.Orbit
local Talk = ns.Talk

local callbacks = {}

local function note()
  local Spoken, why = SD.Spoken()
  if not Spoken then
    -- a missing Spoken has the game's voice as the fallback; a too old one keeps its own note
    if rawget(_G, "Spoken") == nil then
      return Voice.NoSpokenNote()
    end
    return why
  end
  local parts = {}
  if SD.VoiceOver() then
    parts[#parts + 1] = L["quests"]
  end
  if #SD.PlacePacks() > 0 then
    parts[#parts + 1] = L["zones and areas"]
  end
  if #SD.ReadablePacks() > 0 then
    parts[#parts + 1] = L["readables"]
  end
  if rawget(_G, "SpokenBossStories") then
    parts[#parts + 1] = L["boss stories"]
  end
  if #parts == 0 then
    return L["Spoken is installed, but no voice pack was found"]
  end
  local text = string.format(L["Spoken reads: %s"], table.concat(parts, ", "))
  local version = Voice.SpokenVersionNote() -- newer or older than tested with (S2)
  return version and (text .. " " .. version) or text
end

local function registerAction(self)
  -- Gestures' "Mark heard" (plan-second-wave.md S6): the place here heard, or unheard again;
  -- offered to the ring only (ctx.source), the Orbit's own marks stay its own
  B:RegisterAction(self, {
    id = "voice.heard",
    label = L["Mark the place heard"],
    icon = B.UI.IconTexture("done"),
    types = "*",
    order = 81,
    when = function(_, ctx)
      return ctx ~= nil and ctx.source == "gestures" and Voice.HereLine() ~= nil
    end,
    active = function()
      local line = Voice.HereLine()
      return line ~= nil and Voice.IsHeard(line.key) == true
    end,
    run = function()
      local line = Voice.HereLine()
      if line then
        Voice.MarkHeard(line.key, not Voice.IsHeard(line.key))
        Orbit.Refresh()
      end
    end,
  })
  B:RegisterAction(self, {
    id = "voice.play",
    main = true, -- a button of the sheet (ADR 0054)
    label = L["Play the voice line"],
    short = L["Play"],
    activeShort = L["Stop"],
    icon = B.UI.IconTexture("voice"),
    types = { "quest", "zone", "area", "npc", "item", "object" },
    order = 80,
    -- only where a line exists (ADR 0013 C): `has` is the row renderers' question, `when` the
    -- menu's and the card's; both answer from the per-ref cache after the first ask
    has = function(ref)
      return Voice.Has(ref)
    end,
    when = function(ref)
      return Voice.Has(ref)
    end,
    active = function(ref)
      return Voice.Playing(ref)
    end,
    run = function(ref, ctx)
      local ok, why = Voice.Toggle(ref, ctx and ctx.shift)
      if not ok and why == "noline" then
        B:Say(L["No voice line for this in the installed packs"])
      elseif not ok and why == "refused" then
        B:Say(L["Spoken did not take the line"])
      end
      Orbit.Refresh()
    end,
  })
end

local function listen(self)
  local Spoken = SD.Spoken()
  if not (Spoken and Spoken.RegisterCallback) then
    return
  end
  callbacks[#callbacks + 1] = Spoken:RegisterCallback("AUDIO_CHANGED", function()
    self:Fire("BASTIANS_ACTION_STATE", "voice.play") -- play and stop buttons elsewhere follow
    B:Fire("BASTIANS_VOICE_CHANGED")
  end)
  callbacks[#callbacks + 1] = Spoken:RegisterCallback("VOICE_PACKS_LOADED", function()
    Voice.Reset()
    B:Fire("BASTIANS_VOICE_CHANGED")
    B:InvalidateEntities()
  end)
end

local function unlisten()
  local Spoken = SD.Spoken()
  for _, handle in ipairs(callbacks) do
    if Spoken and Spoken.UnregisterCallback then
      Spoken:UnregisterCallback(handle)
    end
  end
  callbacks = {}
end

local OPTIONS = {
  { type = "note", text = note },
  {
    type = "toggle",
    key = "tts",
    label = L["Read quest texts with the game's voice where Spoken has no line"],
  },
  {
    -- the client's voices by name; "auto" is a woman's voice (the client's
    -- default is a man's and the Accessibility setting is hard to find)
    type = "select",
    key = "voice",
    label = L["The game's voice that reads"],
    values = function()
      local values = { auto = L["A woman's voice (auto)"] }
      for _, v in ipairs(B.Compat.Voices()) do
        values[tostring(v.voiceID)] = v.name
      end
      return values
    end,
  },
  { type = "toggle", key = "hoverWide", label = L["Open wide when the pointer is over it"] },
  {
    type = "range",
    key = "scale",
    label = L["Scale (percent of the auto size)"],
    min = 50,
    max = 200,
    step = 5,
  },
  {
    type = "select",
    key = "anchor",
    label = L["Anchor until you move it"],
    values = {
      topright = L["Top right"],
      bottomright = L["Bottom right"],
      bottomcenter = L["Bottom centre"],
    },
  },
  { type = "toggle", key = "lock", label = L["Lock the position"] },
  { type = "toggle", key = "fadeInCombat", label = L["Fade in combat"] },
  {
    type = "execute",
    label = L["Reset position and size"],
    func = function()
      Voice.ResetOrbit()
    end,
  },
}

local mod = B:NewModule("Voice", {
  news = ns.NEWS, -- What's new (ADR 0021)
  addon = ADDON,
  open = function()
    Orbit.Toggle()
  end,
  title = L["Orbiter"], -- "call it Orbiter, not voice" (the folder stays)
  icon = B.UI.IconTexture("orbit"), -- its minimap button (Core's launcher)
  apiVersion = 1,
  optional = {
    "Spoken",
    "Spoken_Quests",
    "Spoken_Places",
    "Spoken_Readables",
    "Spoken_NPCs",
    "Bastians_Browser",
  },
  defaults = {
    profile = {
      tts = true, -- the game's voice where Spoken has no line
      voice = "auto", -- a woman's voice; else a voiceID as a string
      hoverWide = true,
      scale = 100,
      anchor = "topright",
      lock = false,
      fadeInCombat = true,
      orbit = {},
    },
    char = {},
    global = {},
  },
  options = OPTIONS,
  OnEnable = function(self)
    registerAction(self)
    listen(self)
    -- the suite's own words (Core's B:Tell, plan-launch-review R5.3): the Orbiter speaks them
    B:ProvideService(self, "voice", {
      Can = function()
        return Voice.TtsOn()
      end,
      Speak = function(text)
        return Voice.SpeakWords(text)
      end,
    })
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED", Voice.TtsStarted) -- the hold (S2)
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED", Voice.TtsFinished)
    self:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED", Voice.TtsFailed)
    ns.Feed.Register(self) -- the Orbiter's feed (ADR 0043, S12)
    -- the client lists its voices after our load (the hub kept saying
    -- "Spoken is not installed" with text to speech switched on): the fallback lines, the hub and
    -- the entities follow the list
    self:RegisterEvent("VOICE_CHAT_TTS_VOICES_UPDATE", function()
      Voice.Reset()
      B:InvalidateEntities()
      B:Fire("BASTIANS_VOICE_CHANGED")
      Orbit.Refresh()
    end)
    self:On("BASTIANS_SUITE_HIDDEN", function(_, _, hidden)
      -- the clear-screen key (plan-round4 F1), only while the page "Hidden by the key" ticks the
      -- Orbiter
      local Screen = B.UI.Screen
      if hidden and Screen and Screen.Hides and not Screen.Hides("Voice") then
        return
      end
      Orbit.HideByKey(hidden == true)
    end)
    self:On("BASTIANS_SETTING_CHANGED", function(_, _, name, key)
      if name == "Voice" and key == "tts" then
        Voice.Reset() -- the quests' fallback lines come and go with the switch
        B:InvalidateEntities()
      end
    end)
  end,
  OnDisable = function()
    unlisten()
    Voice.StopAll()
    Voice.Reset()
  end,
})
Voice.mod = mod
mod.Voice = Voice
mod.Orbit = Orbit
mod.Talk = Talk
mod.SpokenData = SD

B:NewModule("Voice.Orbit", {
  title = L["The orbit"],
  options = {
    {
      type = "note",
      text = L["The round panel: the zone, the dungeon, the areas, the quest givers and their quests, bosses and books around you."], -- luacheck: ignore 631 (a locale key stays one literal)
    },
  },
  OnEnable = function(self)
    Orbit.Attach(self)
  end,
  OnDisable = function()
    Orbit.Detach()
  end,
})

B:NewModule("Voice.Talk", {
  title = L["Conversation without windows"],
  defaults = { profile = { enabled = false, pauseKey = "shift" } }, -- off by default
  options = {
    {
      type = "note",
      text = L["Talking to an NPC shows its quests and what to say on the orbit; the game's gossip and quest windows stay shut."], -- luacheck: ignore 631 (a locale key stays one literal)
    },
    {
      type = "select",
      key = "pauseKey",
      label = L["Hold to keep the game's windows this visit"],
      values = { shift = L["Shift"], ctrl = L["Ctrl"], alt = L["Alt"] },
    },
  },
  OnEnable = function(self)
    Talk.Attach(self)
  end,
  OnDisable = function()
    Talk.Detach()
  end,
})

-- the heard list, what plays, or the conversation changed (hosts that draw them re-render)
B:DeclareMessage("BASTIANS_VOICE_CHANGED")
B:DeclareMessage("BASTIANS_VOICE_TALK")

function Voice.ResetOrbit()
  mod.db.profile.scale = 100
  Orbit.ResetPlace()
  Orbit.ApplyScale()
end

-- `/bv` toggles the orbit; `/bv reset` puts it back; `/bv stop` stops every line.
function Voice.Slash(text)
  local cmd = string.match(text or "", "^%s*(%S*)")
  if cmd == "reset" then
    Voice.ResetOrbit()
    return "reset"
  elseif cmd == "stop" then
    Voice.StopAll()
    return "stop"
  elseif cmd == "voices" then
    -- what the game lists for reading, for a player who hears nothing (retail 01.11.2026)
    local voices = B.Compat.Voices()
    B:Say(L["The game lists %d voice(s) for reading"], #voices)
    for _, v in ipairs(voices) do
      B:Say("  %s (%s)", tostring(v.name), tostring(v.voiceID))
    end
    return "voices"
  end
  return Orbit.Toggle()
end

SLASH_BASTIANSVOICE1 = "/bv"
SLASH_BASTIANSVOICE2 = "/orbiter"
SlashCmdList.BASTIANSVOICE = function(text)
  Voice.Slash(text)
end

-- Key bindings (Bindings.xml reads these globals); the header is the addon's own: a second
-- Bindings.xml naming Core's header made the client warn "loaded more than once" (retail 01.11.2026)
BINDING_HEADER_BASTIANS_VOICE = "Bastian's Orbiter"
BINDING_NAME_BASTIANS_VOICE_ORBIT = L["Toggle the Orbiter"]
BINDING_NAME_BASTIANS_VOICE_PLAY = L["Orbiter: play or pause"]
BINDING_NAME_BASTIANS_VOICE_STOP = L["Orbiter: stop"]
BINDING_NAME_BASTIANS_VOICE_HEARD = L["Orbiter: mark heard"]

function Voice.MarkNowHeard()
  local now = Voice.Now()
  if now and now.key then
    Voice.MarkHeard(now.key)
    Voice.StopAll()
  end
end
