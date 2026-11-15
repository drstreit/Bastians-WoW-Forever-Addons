-- The player's own courtesy lines (courtesy.md "Your own lines", ADR 0063 and its amendment of
-- 15.11.2026, owner: "I have the feeling its confusing to have Bastians_MyLines and hard coded?"):
-- kept in the game, in the account's saved variables, written in the window My lines (Editor.lua);
-- the switch in the options decides whether they are used. Lines of either kind can be switched
-- off for good ("Never offer"). The retired addon Bastians_MyLines hands its lines over once.
local _, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice

local Mine = {}
ns.Mine = Mine

-- The template's eight examples (Bastians_MyLines as it shipped until 15.11.2026): never taken over,
-- they were examples, not the player's words.
Mine.TEMPLATE = {
  ["Thank you, %t. I will not forget it."] = true,
  ["May your road stay dry, %t."] = true,
  ["Finally, someone thinks I need to think. Thanks, %t."] = true,
  ["Oh, lovely! Good %h to you, %t!"] = true,
  ["One more step, then. Thank you, %t."] = true,
  ["So the road goes on after all. My thanks, %t."] = true,
  ["act:smiles back at %t."] = true,
  ["Another time, %t. Good %h to you."] = true,
}

local checked -- the last check: { usable = { lines }, own = { [line] = true }, problems }
local mod

local function global()
  return mod and mod.db.global or {}
end

-- The player's lines as kept (the list itself, in the file's format).
function Mine.List()
  local g = global()
  g.myLines = type(g.myLines) == "table" and g.myLines or {}
  return g.myLines
end

-- The keys of the lines never to be offered (Voice.Key -> true).
function Mine.NeverSet()
  local g = global()
  g.never = type(g.never) == "table" and g.never or {}
  return g.never
end

local function check()
  if checked then
    return checked
  end
  local known = Voice.Situations(ns.CourtesyLines)
  checked = { usable = {}, own = {}, problems = {} }
  for index, line in ipairs(Mine.List()) do
    local why = Voice.Problem(line, known)
    if why then
      checked.problems[#checked.problems + 1] = { index, why }
    else
      checked.usable[#checked.usable + 1] = line
      checked.own[line] = true
    end
  end
  return checked
end

local function changed()
  checked = nil
  if mod then
    B:Fire("BASTIANS_SETTING_CHANGED", mod.name, "myLinesList", #Mine.List())
  end
end

local function switchedOn()
  return mod ~= nil and mod.db.profile.myLines == true
end

-- The lines were changed from outside (a test, an import): checked again on the next use.
function Mine.Reset()
  changed()
end

-- Why a line cannot be used, nil when it can.
function Mine.Problem(line)
  return Voice.Problem(line, Voice.Situations(ns.CourtesyLines))
end

-- Adds a line (or replaces the line at `index`). -> true, or false and why.
function Mine.Put(line, index)
  local why = Mine.Problem(line)
  if why then
    return false, why
  end
  local list = Mine.List()
  if index and list[index] then
    list[index] = line
  else
    list[#list + 1] = line
  end
  changed()
  return true
end

function Mine.Remove(index)
  local list = Mine.List()
  if list[index] then
    table.remove(list, index)
    changed()
    return true
  end
  return false
end

-- A line, ours or the player's, is never offered again (or again, with `allow`).
function Mine.Never(line, allow)
  local key = Voice.Key(line)
  if not key then
    return false
  end
  Mine.NeverSet()[key] = not allow or nil
  changed()
  return true
end

-- A line never offered may be offered again (its key, Voice.Key).
function Mine.Allow(key)
  if Mine.NeverSet()[key] then
    Mine.NeverSet()[key] = nil
    changed()
    return true
  end
  return false
end

function Mine.IsNever(line)
  local key = Voice.Key(line)
  return key ~= nil and Mine.NeverSet()[key] == true
end

-- The lines a moment draws from first: the player's, or ours when the switch is off or none is usable.
function Mine.Pool()
  local usable = check().usable
  if switchedOn() and #usable > 0 then
    return usable
  end
  return ns.CourtesyLines
end

-- Whether a line is one of the player's.
function Mine.Owns(line)
  return check().own[line] == true
end

-- The line for a moment: one of the player's where one fits and was not said lately, else one of
-- ours; a line switched off is no candidate of either. -> line or nil. A player's lines are never
-- repeated in place of ours.
function Mine.Choose(facts, opts)
  opts = opts or {}
  local never = Mine.NeverSet()
  local pool = Mine.Pool()
  local line
  if pool ~= ns.CourtesyLines then
    line = Voice.Choose(pool, facts, setmetatable({ fresh = true, never = never }, { __index = opts }))
  end
  return line or Voice.Choose(ns.CourtesyLines, facts, setmetatable({ never = never }, { __index = opts }))
end

-- Once: the lines the retired Bastians_MyLines (and the lines kept from Gestures) handed to Core go
-- into the saved variables, all but the template's examples and a line already there. Nothing
-- happens while Core holds none (the folder may load after this addon); the flag is set only when
-- something was there. -> how many came over, or nil when there was nothing to look at.
function Mine.Import()
  local g = global()
  if g.myLinesImported then
    return nil
  end
  local handed = B:GetCourtesyLines()
  if #handed == 0 then
    return nil
  end
  g.myLinesImported = true
  local have = {}
  for _, line in ipairs(Mine.List()) do
    have[(line[1] or "") .. "|" .. (Voice.Key(line) or "")] = true
  end
  local n = 0
  for _, line in ipairs(handed) do
    local key = Voice.Key(line)
    local id = (line[1] or "") .. "|" .. (key or "")
    if key and not Mine.TEMPLATE[key] and not have[id] and not Mine.Problem(line) then
      local copy = { line[1], line[2], line[3], act = line.act, emote = line.emote, when = line.when }
      table.insert(Mine.List(), copy)
      have[id] = true
      n = n + 1
    end
  end
  changed()
  local came =
    L["%d of your lines from Bastians_MyLines are now in Courtesy's window My lines. You can delete the folder Bastians_MyLines."] -- luacheck: ignore 631 (a locale key stays one literal)
  local none =
    L["Bastians_MyLines holds only the template's examples. You can delete the folder Bastians_MyLines."] -- luacheck: ignore 631 (a locale key stays one literal)
  if n > 0 then
    B:Say(came, n)
  else
    B:Say(none)
  end
  return n
end

-- How many lines of the player's are kept and can be used; the problems of the others.
function Mine.State()
  local state = check()
  return #Mine.List(), #state.usable, state.problems
end

-- `/bcourtesy mine`, the button: the window, and in the chat how many lines work and what is wrong.
function Mine.Report()
  local total, usable, problems = Mine.State()
  B:Say(L["My lines: %d can be used, %d cannot."], usable, #problems)
  for _, problem in ipairs(problems) do
    B:Say(L["Line %d: %s"], problem[1], problem[2])
  end
  if not switchedOn() then
    B:Say(L["The switch is off: only the lines that come with the addon are used."])
  end
  if ns.Editor then
    ns.Editor.Open()
  end
  return total > 0
end

-- The module enabled (Main.lua, after the lines kept from Gestures went to Core): the one import.
function Mine.Attach(m)
  mod = m
  checked = nil
  Mine.Import()
end
