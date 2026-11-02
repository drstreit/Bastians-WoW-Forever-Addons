-- The text keys of every box (ADR 0045): the Windows and Word keys for all of them, the readline
-- (bash) keys for the boxes that ask. The edits as plain functions of (text, cursor); the cursor is
-- a byte offset as the client's edit box has it (0 = before the first letter). Pure: no WoW API.
local _, ns = ...
local B = ns.B

local TextKeys = {}
B.TextKeys = TextKeys

local sub, find = string.sub, string.find

-- Ctrl + key in every box. Ctrl+C, X, V and A are the client's (copy, cut, paste, select all).
TextKeys.WINDOWS =
  { BACKSPACE = "deleteWordLeft", DELETE = "deleteWordRight", LEFT = "wordLeft", RIGHT = "wordRight" }
-- The readline set on top (a box's opts.shell): Ctrl + key and Alt + key.
TextKeys.SHELL_CTRL =
  { A = "home", E = "end", U = "killLeft", K = "killRight", W = "killWord", Y = "yank", T = "transpose" }
TextKeys.SHELL_ALT = { B = "wordLeft", F = "wordEnd", D = "killWordRight" }

-- Ctrl + Shift + key: the selection grows by a word.
TextKeys.SELECT = { LEFT = "selectWordLeft", RIGHT = "selectWordRight" }

-- The op of a key, or nil. `extra` adds Ctrl keys of the box's own (the chat's search).
function TextKeys.Op(key, ctrl, alt, shell, extra, shift)
  if ctrl and shift and not alt then
    return TextKeys.SELECT[key]
  elseif ctrl and not alt then
    if extra and extra[key] then
      return extra[key]
    end
    if shell and TextKeys.SHELL_CTRL[key] then
      return TextKeys.SHELL_CTRL[key]
    end
    return TextKeys.WINDOWS[key]
  elseif alt and not ctrl and shell then
    return TextKeys.SHELL_ALT[key]
  end
  return nil
end

-- 0 a space, 1 a word letter (letters, digits, _ and every non-ASCII byte), 2 punctuation.
local function class(text, i)
  local c = sub(text, i, i)
  if c == "" or find(c, "%s") then
    return 0
  elseif find(c, "[%w_\128-\255]") then
    return 1
  end
  return 2
end

-- The start of the word before `cursor` (Ctrl+Left, Alt+B, Ctrl+Backspace).
local function wordStart(text, cursor)
  local i = cursor
  while i > 0 and class(text, i) == 0 do
    i = i - 1
  end
  local c = class(text, i)
  while i > 0 and class(text, i) == c do
    i = i - 1
  end
  return i
end

-- The start of the next word after `cursor` (Ctrl+Right, Ctrl+Delete: Windows).
local function nextWord(text, cursor)
  local n, i = #text, cursor + 1
  local c = class(text, i)
  if c ~= 0 then
    while i <= n and class(text, i) == c do
      i = i + 1
    end
  end
  while i <= n and class(text, i) == 0 do
    i = i + 1
  end
  return i - 1
end

-- The end of the word at or after `cursor` (Alt+F, Alt+D: readline).
local function wordEnd(text, cursor)
  local n, i = #text, cursor + 1
  while i <= n and class(text, i) ~= 1 do
    i = i + 1
  end
  while i <= n and class(text, i) == 1 do
    i = i + 1
  end
  return i - 1
end

-- The byte where the UTF-8 letter that holds byte `i` starts.
local function letterStart(text, i)
  while i > 1 and find(sub(text, i, i), "[\128-\191]") do
    i = i - 1
  end
  return i
end

-- text, cursor, kill (the text the last kill took) -> new text, new cursor, killed text. nil when
-- the op is not an edit of the text.
function TextKeys.Edit(op, text, cursor, kill)
  text = text or ""
  cursor = math.max(0, math.min(cursor or #text, #text))
  local before, after = sub(text, 1, cursor), sub(text, cursor + 1)
  if op == "home" then
    return text, 0
  elseif op == "end" then
    return text, #text
  elseif op == "wordLeft" or op == "selectWordLeft" then
    return text, wordStart(text, cursor)
  elseif op == "wordRight" or op == "selectWordRight" then
    return text, nextWord(text, cursor)
  elseif op == "wordEnd" then
    return text, wordEnd(text, cursor)
  elseif op == "deleteWordLeft" then
    local s = wordStart(text, cursor)
    return sub(text, 1, s) .. after, s
  elseif op == "deleteWordRight" then
    return before .. sub(text, nextWord(text, cursor) + 1), cursor
  elseif op == "killLeft" then
    return after, 0, cursor > 0 and before or nil
  elseif op == "killRight" then
    return before, cursor, after ~= "" and after or nil
  elseif op == "killWord" then
    -- readline's Ctrl+W: back to the space before the word
    local start = find(before, "%S+%s*$") or find(before, "%s+$")
    if not start then
      return text, cursor
    end
    return sub(text, 1, start - 1) .. after, start - 1, sub(before, start)
  elseif op == "killWordRight" then
    local e = wordEnd(text, cursor)
    local killed = sub(text, cursor + 1, e)
    return before .. sub(text, e + 1), cursor, killed ~= "" and killed or nil
  elseif op == "yank" then
    if not kill or kill == "" then
      return text, cursor
    end
    return before .. kill .. after, cursor + #kill
  elseif op == "transpose" then
    -- the letter before the cursor with the one at it; at the end, the last two
    if #text < 2 or cursor == 0 then
      return text, cursor
    end
    local at = cursor
    if at >= #text then
      at = letterStart(text, #text) - 1
    end
    local s1 = letterStart(text, at)
    local s2 = at + 1
    local e2 = s2
    while e2 < #text and find(sub(text, e2 + 1, e2 + 1), "[\128-\191]") do
      e2 = e2 + 1
    end
    if s1 < 1 then
      return text, cursor
    end
    local a, b = sub(text, s1, s2 - 1), sub(text, s2, e2)
    return sub(text, 1, s1 - 1) .. b .. a .. sub(text, e2 + 1), e2
  end
  return nil
end
