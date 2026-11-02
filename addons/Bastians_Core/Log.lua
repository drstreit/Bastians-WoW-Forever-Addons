-- Ring-buffer log (core-contracts §14): never spams chat, shown with /bastians log.
local _, ns = ...
local B = ns.B

local SIZE = 500
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

local buffer = {} -- ring of { time, owner, level, text }
local head = 0 -- index of the newest line
local count = 0

ns.log = { buffer = buffer, LEVELS = LEVELS, SIZE = SIZE }
B.debug = false

-- The chat prefix colour of the theme (Style loads after this file; before it, no colour).
local function chat()
  local S = ns.Style
  return S and S.H.chat or ""
end

local function ownerName(owner)
  if type(owner) == "table" then
    return owner.name or "?"
  end
  return tostring(owner or "Core")
end

-- Bastians:Log(owner, level, fmt, ...) ; level is "debug" | "info" | "warn" | "error".
-- Debug lines are dropped unless Bastians.debug is on. Formatting errors never raise.
function B:Log(owner, level, fmt, ...)
  if level == "debug" and not B.debug then
    return
  end
  local text = fmt
  if select("#", ...) > 0 then
    local ok, formatted = pcall(string.format, tostring(fmt), ...)
    text = ok and formatted or (tostring(fmt) .. " [format error]")
  end
  head = head % SIZE + 1
  count = math.min(count + 1, SIZE)
  buffer[head] = { time = GetTime(), owner = ownerName(owner), level = level, text = tostring(text) }
  if B.debug and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage((chat() .. "Bastians|r [%s] %s: %s"):format(level, ownerName(owner), text))
  end
end

-- Bastians:GetLog(n) returns the newest n lines (default all), oldest first.
function B:GetLog(n)
  n = math.min(n or count, count)
  local out = {}
  for i = n - 1, 0, -1 do
    local idx = (head - i - 1) % SIZE + 1
    out[#out + 1] = buffer[idx]
  end
  return out
end

function B:ClearLog()
  for k in pairs(buffer) do
    buffer[k] = nil
  end
  head, count = 0, 0
end

-- A notice of an app for the addon chat:
-- BASTIANS_NOTICE(text, owner name) for the coming chat replacement, and one line in the chat
-- window whose tab is named as Core's `noticeTab` ("Addons"). Without such a tab the normal chat
-- stays untouched. Returns true when a chat window took the line.
function B:Notify(owner, text)
  text = tostring(text)
  local name = type(owner) == "table" and owner.title and tostring(owner.title) or ownerName(owner)
  B:Log(owner, "info", "%s", text)
  B:Fire("BASTIANS_NOTICE", text, name)
  local core = ns.core
  local tab = core and core.db and core.db.profile.noticeTab or "Addons"
  local frame = B.Compat and B.Compat.ChatFrameNamed and B.Compat.ChatFrameNamed(tab)
  if not frame then
    return false
  end
  frame:AddMessage(chat() .. name .. ":|r " .. text)
  return true
end

-- The suite's own words (plan-launch-review.md R5.3, "speech not text" for the
-- Wanderer): a notice, a reminder, a route step or an arrival goes to text, to the voice or to
-- both, as the General page's Words section says per kind (`words<Kind>` = text | voice | both).
-- The text is what the app shows today (`showText(text)`, else B:Notify); the voice is the
-- `voice` service (the Orbiter: the game's voice in the player's chosen voice). Without the
-- service, voice falls back to text, so nothing is ever lost. -> whether the words were spoken.
B.WORD_KINDS = { "notice", "reminder", "step", "arrival" }
function B:Tell(owner, kind, text, showText)
  text = tostring(text)
  local core = ns.core
  local p = core and core.db and core.db.profile
  local how = p and p["words" .. kind:sub(1, 1):upper() .. kind:sub(2)] or "text"
  local voice = B:GetService("voice")
  local spoken = false
  if (how == "voice" or how == "both") and voice and voice.Can and voice.Can() then
    spoken = voice.Speak(text, kind) and true or false
  end
  if how ~= "voice" or not spoken then
    if showText then
      showText(text)
    else
      B:Notify(owner, text)
    end
  end
  return spoken
end

-- One chat line, used for things the player must see (a module disabled itself, a scan is saving).
function B:Say(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage(chat() .. "Bastians:|r " .. tostring(text))
end
