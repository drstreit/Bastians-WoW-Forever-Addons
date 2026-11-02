-- The client wrappers Gestures needs beyond Core's Compat (as Chat kept its own during its
-- development): the chat message with a language, the character's languages; since the editor v2
-- the client's emote list, the reading of a command's lines, the game's controls. They move into
-- Core's Compat/Shared.lua with the next Core change; every call is **assumed** on Forever
-- (docs/forever-api.md) until the in-game checklist.
local _, ns = ...

local Compat = {}
ns.Compat = Compat

local function fnOf(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

-- The languages the character speaks: { { id, name } } in the client's order; empty when the
-- client does not say (GetNumLanguages, GetLanguageByIndex: retail family, assumed on Forever).
function Compat.Languages()
  local count, byIndex = fnOf("GetNumLanguages"), fnOf("GetLanguageByIndex")
  if not (count and byIndex) then
    return {}
  end
  local out = {}
  local n = tonumber(count()) or 0
  for i = 1, n do
    local name, id = byIndex(i)
    if type(name) == "string" and name ~= "" then
      out[#out + 1] = { id = id, name = name }
    end
  end
  return out
end

-- Whether the character knows the language named so.
function Compat.KnowsLanguage(name)
  if not name then
    return false
  end
  for _, lang in ipairs(Compat.Languages()) do
    if lang.name == name then
      return true
    end
  end
  return false
end

-- Sends one chat message of at most 255 bytes: `channel` SAY, EMOTE or YELL; `language` only
-- when the character knows it (else the default language). -> whether it was handed to the
-- client (false without the API).
function Compat.SendChat(text, channel, language, target)
  local send = fnOf("SendChatMessage")
  if not send or type(text) ~= "string" or text == "" then
    return false
  end
  if language and not Compat.KnowsLanguage(language) then
    language = nil
  end
  send(text, channel or "SAY", language, target)
  return true
end

-- Declines a request politely (plan-second-wave.md S7): the game's own call for the kind
-- (`CancelDuel`, `CloseTrade`, `DeclineGroup`; retail family, assumed on Forever) and its popup
-- hidden. -> whether the client offered the call.
local DECLINE = { duel = "CancelDuel", trade = "CloseTrade", invite = "DeclineGroup" }
local POPUP = { duel = "DUEL_REQUESTED", invite = "PARTY_INVITE" }
function Compat.Decline(kind)
  local fn = DECLINE[kind] and fnOf(DECLINE[kind]) or nil
  if fn then
    fn()
  end
  local hide = POPUP[kind] and fnOf("StaticPopup_Hide") or nil
  if hide then
    hide(POPUP[kind])
  end
  return fn ~= nil
end

-- The unit token's player name, or nil when the client gives none (the unit left reach).
function Compat.UnitPlayerName(unit)
  local name = fnOf("UnitName")
  if not (name and unit) then
    return nil
  end
  local n = name(unit)
  return type(n) == "string" and n ~= "" and n or nil
end

-- Whether the unit is the player or in the player's group (no courtesy to those).
function Compat.IsMineOrGroup(unit)
  if not unit then
    return false
  end
  local isUnit = fnOf("UnitIsUnit")
  if isUnit and isUnit(unit, "player") then
    return true
  end
  local party, raid = fnOf("UnitInParty"), fnOf("UnitInRaid")
  if party and party(unit) then
    return true
  end
  if raid and raid(unit) then
    return true
  end
  return false
end

-- A global function's answer, or nil when the client has no such function.
function Compat.Call(name, ...)
  local f = fnOf(name)
  if not f then
    return nil
  end
  return f(...)
end

-- ---------------------------------------------------------------------------------------------
-- The editor v2: the client's emotes, the lines of a command, the
-- game's controls. The globals EMOTE<i>_TOKEN, EMOTE<i>_CMD1 and MAXEMOTEINDEX are in the probe
-- dumps of Forever 70532 and retail 70448 (data/probe); their values are **assumed** the retail
-- family's until the in-game checklist.
-- ---------------------------------------------------------------------------------------------

local emoteList, emoteByCmd

local function scanEmotes()
  if emoteList then
    return
  end
  emoteList, emoteByCmd = {}, {}
  local seen = {}
  for i = 1, tonumber(rawget(_G, "MAXEMOTEINDEX")) or 0 do
    local token = rawget(_G, "EMOTE" .. i .. "_TOKEN")
    if type(token) == "string" and token ~= "" and not seen[token] then
      seen[token] = true
      local cmd = rawget(_G, "EMOTE" .. i .. "_CMD1")
      local entry = { token = token, cmd = type(cmd) == "string" and cmd or nil, cmds = {} }
      for c = 1, 9 do
        local alias = rawget(_G, "EMOTE" .. i .. "_CMD" .. c)
        if type(alias) ~= "string" then
          break
        end
        entry.cmds[#entry.cmds + 1] = alias
        emoteByCmd[string.lower(alias)] = token
      end
      emoteList[#emoteList + 1] = entry
    end
  end
end

-- Every emote the client knows: { { token, cmd, cmds } } in the client's order (gaps skipped;
-- `cmd` the first slash command, `cmds` all of them); read once, empty without the globals.
function Compat.GameEmotes()
  scanEmotes()
  return emoteList
end

-- The emote token of a slash command ("/dance" -> "DANCE"), nil for none.
function Compat.EmoteOfCommand(cmd)
  scanEmotes()
  return emoteByCmd[string.lower(cmd or "")]
end

-- The chat commands a command line may start with: the client's own words (SLASH_SAY1, ...) and
-- the English ones.
local CHAT = {
  SAY = { "/s", "/say" },
  EMOTE = { "/e", "/em", "/me", "/emote" },
  YELL = { "/y", "/yell", "/sh", "/shout" },
  PARTY = { "/p", "/party" },
  GUILD = { "/g", "/guild" },
  RAID = { "/ra", "/raid" },
  INSTANCE_CHAT = { "/i", "/instance" },
  WHISPER = { "/w", "/whisper", "/t", "/tell" },
}
local chatOf

local function chatChannel(cmd)
  if not chatOf then
    chatOf = {}
    for channel, words in pairs(CHAT) do
      for _, w in ipairs(words) do
        chatOf[w] = channel
      end
      for i = 1, 9 do
        local w = rawget(_G, "SLASH_" .. channel .. i)
        if type(w) ~= "string" then
          break
        end
        chatOf[string.lower(w)] = channel
      end
    end
  end
  return chatOf[string.lower(cmd)]
end

-- The secure commands (SecureCmdList: casting, using, targeting, ...) the client runs from its
-- own macros and buttons only; an addon's call is blocked (RunMacroText itself is HasRestrictions
-- in both clients' API documentation). IsSecureCmd (FrameXML) decides where the client offers it,
-- the English list where it does not.
local SECURE = {}
for _, w in ipairs({
  "cast",
  "use",
  "castsequence",
  "castrandom",
  "userandom",
  "target",
  "tar",
  "targetenemy",
  "targetfriend",
  "targetparty",
  "targetraid",
  "targetexact",
  "targetlasttarget",
  "targetlastenemy",
  "targetlastfriend",
  "assist",
  "focus",
  "clearfocus",
  "cleartarget",
  "startattack",
  "stopattack",
  "stopcasting",
  "cancelaura",
  "cancelform",
  "equip",
  "eq",
  "equipslot",
  "equipset",
  "click",
  "dismount",
  "leavevehicle",
  "petattack",
  "petfollow",
  "petstay",
  "petpassive",
  "petdefensive",
  "petassist",
  "worldmarker",
  "clearworldmarker",
  "stopmacro",
}) do
  SECURE["/" .. w] = true
end

local function isSecure(cmd)
  local check = fnOf("IsSecureCmd")
  if check and check(cmd) then
    return true
  end
  return SECURE[string.lower(cmd)] == true
end

-- The handler of a registered slash command (SlashCmdList with its SLASH_<KEY>n words).
local function slashHandler(cmd)
  local list = rawget(_G, "SlashCmdList")
  if type(list) ~= "table" then
    return nil
  end
  cmd = string.lower(cmd)
  for key, fn in pairs(list) do
    local i = 1
    while true do
      local w = rawget(_G, "SLASH_" .. key .. i)
      if type(w) ~= "string" then
        break
      end
      if string.lower(w) == cmd then
        return fn
      end
      i = i + 1
    end
  end
  return nil
end

-- One line of a command slot, read: { kind = "chat", channel, text, to } (no slash: say) |
-- { kind = "emote", token } | { kind = "slash", fn, rest, cmd } | { kind = "secure", cmd } |
-- { kind = "client", line, cmd } (a command of the client's own chat, such as /reload, /played,
-- /who, /macro: not in SlashCmdList, so the chat's edit box sends it, follow-up of 01.11.2026) |
-- { kind = "unknown", cmd } (a /w without a text) | nil (an empty line or a #comment).
function Compat.ParseLine(line)
  line = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" or line:sub(1, 1) == "#" then
    return nil
  end
  if line:sub(1, 1) ~= "/" then
    return { kind = "chat", channel = "SAY", text = line }
  end
  local cmd, rest = line:match("^(/%S+)%s*(.-)$")
  local channel = chatChannel(cmd)
  if channel == "WHISPER" then
    local to, text = rest:match("^(%S+)%s+(.+)$")
    if not to then
      return { kind = "unknown", cmd = cmd }
    end
    return { kind = "chat", channel = channel, text = text, to = to }
  elseif channel then
    if rest == "" then
      return nil
    end
    return { kind = "chat", channel = channel, text = rest }
  end
  local token = Compat.EmoteOfCommand(cmd)
  if not token then
    local upper = string.upper(cmd:sub(2))
    for _, e in ipairs(ns.Model and ns.Model.EMOTES or {}) do
      if e[1] == upper then
        token = upper -- a curated gesture by its token, where the client did not list it
      end
    end
  end
  if token then
    return { kind = "emote", token = token }
  end
  if isSecure(cmd) then
    return { kind = "secure", cmd = cmd }
  end
  local fn = slashHandler(cmd)
  if fn then
    return { kind = "slash", fn = fn, rest = rest, cmd = cmd }
  end
  return { kind = "client", line = line, cmd = cmd }
end

-- The chat frame's edit box (the client's own): DEFAULT_CHAT_FRAME.editBox, else
-- ChatFrame1EditBox.
function Compat.ChatEditBox()
  local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
  local box = type(frame) == "table" and frame.editBox or nil
  if type(box) ~= "table" then
    box = rawget(_G, "ChatFrame1EditBox")
  end
  return type(box) == "table" and box or nil
end

-- Sends one line through the chat's edit box as if the player typed it (`ChatEdit_SendText`,
-- FrameXML of both clients, assumed): the chat runs the client's built-in commands and answers an
-- unknown one itself ("Type /help ..."). -> false when the client offers no edit box or no send.
function Compat.SendToChat(line)
  local send, box = fnOf("ChatEdit_SendText"), Compat.ChatEditBox()
  if not (send and box and type(box.SetText) == "function") then
    return false
  end
  box:SetText(line)
  send(box, 1)
  return true
end

-- ---------------------------------------------------------------------------------------------
-- The player's macros (follow-up of 01.11.2026): GetNumMacros -> the account's and the
-- character's count, GetMacroInfo(i) -> name, icon, body, the character's from
-- MAX_ACCOUNT_MACROS + 1 (120 where the client names no constant); GetMacroIndexByName(name) -> 0
-- when there is none. Retail family, **assumed** on Forever. The client runs a macro only from a
-- secure action button the player clicks (Core's ring kit lays one over the wedge).
-- ---------------------------------------------------------------------------------------------

function Compat.Macros()
  local count, info = fnOf("GetNumMacros"), fnOf("GetMacroInfo")
  if not (count and info) then
    return {}
  end
  local account, character = count()
  local first = tonumber(rawget(_G, "MAX_ACCOUNT_MACROS")) or 120
  local out = {}
  local function add(i, mine)
    local name, icon, body = info(i)
    if type(name) == "string" and name ~= "" then
      out[#out + 1] = { name = name, icon = icon, body = body, character = mine }
    end
  end
  for i = 1, tonumber(account) or 0 do
    add(i, false)
  end
  for i = 1, tonumber(character) or 0 do
    add(first + i, true)
  end
  return out
end

-- Whether a macro of that name exists now (never guessed: no API, no macro).
function Compat.MacroExists(name)
  local byName, info = fnOf("GetMacroIndexByName"), fnOf("GetMacroInfo")
  if not (name and byName and info) then
    return false
  end
  local index = tonumber(byName(name)) or 0
  if index == 0 then
    return false
  end
  return info(index) == name
end

-- The game's controls (Model.GAME): what each needs of the client and the call. None of them is
-- HasRestrictions in the API documentation of either client (wow-ui-source, 01.11.2026); every
-- one is **assumed** on Forever until the in-game checklist. Never called in combat (Ring).
local function toggleShown()
  local ui = rawget(_G, "UIParent")
  if type(ui) ~= "table" or type(ui.SetShown) ~= "function" then
    return false
  end
  ui:SetShown(not ui:IsShown())
  return true
end

local function mountJournal()
  local mj = rawget(_G, "C_MountJournal")
  return type(mj) == "table" and type(mj.SummonByID) == "function" and mj or nil
end

local GAME = {
  screenshot = {
    has = function()
      return fnOf("Screenshot") ~= nil
    end,
    run = function()
      return Bastians.Compat.TakeScreenshot()
    end,
  },
  ui = {
    has = function()
      local ui = rawget(_G, "UIParent")
      return type(ui) == "table" and type(ui.SetShown) == "function"
    end,
    run = toggleShown,
  },
  sheath = {
    has = function()
      return fnOf("ToggleSheath") ~= nil
    end,
    run = function()
      ToggleSheath()
      return true
    end,
  },
  dismount = {
    has = function()
      return fnOf("Dismount") ~= nil
    end,
    run = function()
      Dismount()
      return true
    end,
  },
  sit = {
    has = function()
      return fnOf("ToggleSit") ~= nil or fnOf("DoEmote") ~= nil
    end,
    run = function()
      local toggle = fnOf("ToggleSit")
      if toggle then
        toggle()
        return true
      end
      return Bastians.Compat.Emote("SIT")
    end,
  },
  helm = {
    has = function()
      return fnOf("ShowHelm") ~= nil and fnOf("ShowingHelm") ~= nil
    end,
    run = function()
      ShowHelm(not ShowingHelm())
      return true
    end,
  },
  cloak = {
    has = function()
      return fnOf("ShowCloak") ~= nil and fnOf("ShowingCloak") ~= nil
    end,
    run = function()
      ShowCloak(not ShowingCloak())
      return true
    end,
  },
  mount = {
    has = function()
      return mountJournal() ~= nil
    end,
    run = function()
      mountJournal().SummonByID(0) -- 0: a random favourite
      return true
    end,
  },
}

-- Whether the client offers game control `id`.
function Compat.HasGame(id)
  local g = GAME[id]
  return g ~= nil and g.has() == true
end

-- Runs game control `id` -> whether it was handed to the client.
function Compat.RunGame(id)
  if not Compat.HasGame(id) then
    return false
  end
  return GAME[id].run() and true or false
end
