-- The player's own courtesy lines (courtesy.md "Your own lines", ADR 0063): what Bastians_MyLines
-- handed to Core, checked once; the switch in the options decides whether they are used.
local _, ns = ...
local B = Bastians
local L = ns.L
local Voice = ns.Voice

local Mine = {}
ns.Mine = Mine

local checked -- the last check: { total, usable = { lines }, own = { [line] = true }, problems }

local function check()
  local handedIn = B:GetCourtesyLines()
  if checked and checked.total == #handedIn then
    return checked
  end
  local known = Voice.Situations(ns.CourtesyLines)
  checked = { total = #handedIn, usable = {}, own = {}, problems = {} }
  for index, line in ipairs(handedIn) do
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

local function switchedOn()
  return ns.Main.mod.db.profile.myLines == true
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

-- The line for a moment: one of the player's where one fits, else one of ours. -> line or nil.
function Mine.Choose(facts, opts)
  local pool = Mine.Pool()
  local line = pool ~= ns.CourtesyLines and Voice.Choose(pool, facts, opts) or nil
  return line or Voice.Choose(ns.CourtesyLines, facts, opts)
end

-- `/bcourtesy mine`, the button: how many lines work, what is wrong with the others, how to install.
function Mine.Report()
  local state = check()
  if state.total == 0 then
    B:Say(
      L["No lines of your own found: Bastians_MyLines is not installed, or its file has a typing error."] -- luacheck: ignore 631 (a locale key stays one literal)
    )
    B:Say(
      L["To install: copy Bastians_Courtesy/Template/Bastians_MyLines to Interface/AddOns, then restart the game."] -- luacheck: ignore 631 (a locale key stays one literal)
    )
    return false
  end
  B:Say(L["My lines: %d can be used, %d cannot."], #state.usable, #state.problems)
  for _, problem in ipairs(state.problems) do
    B:Say(L["Line %d: %s"], problem[1], problem[2])
  end
  if not switchedOn() then
    B:Say(L["The switch is off: only the lines that come with the addon are used."])
  end
  return true
end
