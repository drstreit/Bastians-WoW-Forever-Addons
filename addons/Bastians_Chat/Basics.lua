-- Bastian's Chat, what the game's chat did and ours must not lose (plan-chat-two-decks.md §7, V37;
-- ADR 0077 decision 2): the game's Chat Settings, the emotes, the language of the input line, the
-- channel list and the combat log's own window, each reached from our menus. Every client call
-- here is assumed until the owner's probe round (X15, X16, X19): each is looked up at use, and an
-- entry whose call the client lacks is left out.
local _, ns = ...
local B = Bastians
local L = ns.L
local Compat = ns.Compat

local Basics = {}
ns.Basics = Basics

-- the emotes offered when the client names none (its tokens; DoEmote takes them)
Basics.EMOTES = { "WAVE", "HELLO", "BYE", "THANK", "CHEER", "BOW", "DANCE", "LAUGH", "YES", "NO", "SIT" }
Basics.EMOTES_MAX = 40 -- a menu's length

local function global(name)
  local v = rawget(_G, name)
  return v ~= nil and v or nil
end

-- The game's Chat Settings (I3): the dialog of the first chat window. False when the client has
-- no such dialog, or in a fight (a panel the game places itself).
function Basics.ChatSettings()
  local frame, show = global("ChatConfigFrame"), global("ShowUIPanel")
  if type(frame) ~= "table" or type(show) ~= "function" or InCombatLockdown() then
    return false
  end
  if rawget(_G, "CURRENT_CHAT_FRAME_ID") == nil then
    rawset(_G, "CURRENT_CHAT_FRAME_ID", 1) -- the window the dialog edits
  end
  return (pcall(show, frame))
end

function Basics.HasChatSettings()
  return type(global("ChatConfigFrame")) == "table" and type(global("ShowUIPanel")) == "function"
end

-- The emotes as { token, label }: the client's own list where it has one, its slash word as the
-- label ("/wave").
function Basics.Emotes()
  local list = global("EmoteList")
  local tokens = type(list) == "table" and #list > 0 and list or Basics.EMOTES
  local words = {}
  local max = tonumber(global("MAXEMOTEINDEX")) or 0
  for i = 1, max do
    local token, cmd = global("EMOTE" .. i .. "_TOKEN"), global("EMOTE" .. i .. "_CMD1")
    if type(token) == "string" and type(cmd) == "string" then
      words[token] = cmd
    end
  end
  local out = {}
  for i = 1, math.min(#tokens, Basics.EMOTES_MAX) do
    local token = tokens[i]
    if type(token) == "string" then
      out[#out + 1] = { token = token, label = words[token] or ("/" .. token:lower()) }
    end
  end
  return out
end

function Basics.Emote(token)
  local emote = global("DoEmote")
  if type(emote) ~= "function" then
    return false
  end
  return (pcall(emote, token))
end

function Basics.EmoteMenu(anchor)
  local items = {}
  for _, e in ipairs(Basics.Emotes()) do
    items[#items + 1] = {
      label = e.label,
      onClick = function()
        Basics.Emote(e.token)
      end,
    }
  end
  B.UI.Menu(anchor, L["Emotes"], items, ns.mod)
  return items
end

-- The languages the character speaks as { name, id }.
function Basics.Languages()
  local count, at = global("GetNumLanguages"), global("GetLanguageByIndex")
  local out = {}
  if type(count) ~= "function" or type(at) ~= "function" then
    return out
  end
  local ok, n = pcall(count)
  n = ok and tonumber(Compat.Plain(n)) or 0
  for i = 1, n do
    local okL, name, id = pcall(at, i)
    if okL and type(name) == "string" then
      out[#out + 1] = { name = name, id = id }
    end
  end
  return out
end

-- The input line speaks `lang` from now on (the bar's own fields, as the game's menu sets them).
function Basics.SetLanguage(lang)
  for _, box in ipairs(Compat.EditBoxes()) do
    box.language, box.languageID = lang.name, lang.id
  end
  ns.mod.db.char.language = lang.name
  return true
end

function Basics.LanguageMenu(anchor)
  local items = {}
  local current = ns.mod.db.char.language
  for _, lang in ipairs(Basics.Languages()) do
    items[#items + 1] = {
      label = lang.name,
      on = current == lang.name,
      onClick = function()
        Basics.SetLanguage(lang)
      end,
    }
  end
  B.UI.Menu(anchor, L["Language"], items, ns.mod)
  return items
end

-- The game's channel list (I6).
function Basics.HasChannels()
  return type(global("ToggleChannelFrame")) == "function" or type(global("ChannelFrame")) == "table"
end

function Basics.Channels()
  if InCombatLockdown() then
    return false
  end
  local toggle = global("ToggleChannelFrame")
  if type(toggle) == "function" then
    return (pcall(toggle))
  end
  local frame, show = global("ChannelFrame"), global("ShowUIPanel")
  if type(frame) == "table" and type(show) == "function" then
    return (pcall(show, frame))
  end
  return false
end

-- The combat log's window (I1, V45): shown or hidden. The first time it opens the game's frame
-- moves into our window, which waits for the fight's end (a frame of the game's is never
-- re-parented in combat; returns "later" then); once it is there, a fight changes nothing.
local logWanted

function Basics.HasLog()
  return Compat.CombatLogFrame() ~= nil
end

function Basics.LogShown()
  return ns.Chat.LogShown()
end

function Basics.ToggleLog()
  local on = not ns.Chat.LogShown()
  if InCombatLockdown() and not ns.Chat.LogHeld() then
    logWanted = on
    B:Say(L["The combat log follows when the fight is over."])
    return "later"
  end
  logWanted = nil
  return ns.Chat.ShowLog(on)
end

-- The fight is over: what the player asked for in it.
function Basics.AfterFight()
  if logWanted ~= nil and not InCombatLockdown() then
    local on = logWanted
    logWanted = nil
    if on ~= ns.Chat.LogShown() then
      ns.Chat.ShowLog(on)
    end
  end
end

-- The entries of "the game's chat" for a menu: what this client has.
function Basics.Entries(items, anchor)
  items[#items + 1] = { label = L["The game's chat"], header = true }
  if Basics.HasLog() then
    items[#items + 1] = {
      label = L["Combat log"],
      on = Basics.LogShown(),
      onClick = function()
        Basics.ToggleLog()
        if ns.Decks then
          ns.Decks.DrawHeads()
        end
      end,
    }
  end
  if Basics.HasChatSettings() then
    items[#items + 1] = {
      label = L["Chat settings (game)"],
      onClick = function()
        if not Basics.ChatSettings() then
          B:Say(L["The game's chat settings cannot be opened now."])
        end
      end,
    }
  end
  items[#items + 1] = {
    label = L["Emotes"],
    onClick = function()
      Basics.EmoteMenu(anchor)
    end,
  }
  if #Basics.Languages() > 1 then
    items[#items + 1] = {
      label = L["Language"],
      onClick = function()
        Basics.LanguageMenu(anchor)
      end,
    }
  end
  if Basics.HasChannels() then
    items[#items + 1] = {
      label = L["Channels"],
      onClick = function()
        if not Basics.Channels() then
          B:Say(L["The channel list cannot be opened now."])
        end
      end,
    }
  end
  return items
end
