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

-- One chat line, used for things the player must see (a module disabled itself, a scan is saving).
function B:Say(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage(chat() .. "Bastians:|r " .. tostring(text))
end
