-- The Today list (gold.md): up to ten lines across Sell, Farm, Craft and Avoid from the Market pack's
-- signals of the player's market, sorted by gold per play-minute. Pure: the signals and the
-- character's capital, time and professions come in through `ctx`, so the filters are tested on the
-- fixture. A line never claims more than its signal: unknown inputs keep the line with a note.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Today = {}
ns.Today = Today

Today.MAX_LINES = 10
Today.ACTIONS = { "sell", "farm", "craft", "avoid" }

-- The profession a flag asks for ("needs:Leatherworking"), or nil.
local function neededProfession(flags)
  for _, f in ipairs(flags or {}) do
    local name = string.match(f, "^needs:(.+)$")
    if name then
      return name
    end
  end
  return nil
end

-- One signal record -> a line, or nil with the reason it was dropped.
-- ctx = { capital (copper), minutes (play time available), professions ({ [name] = rank } or nil),
--         now (epoch), level }
function Today.line(signal, ctx)
  if signal.validUntil and ctx.now and signal.validUntil < ctx.now then
    return nil, "expired"
  end
  local capital = signal.capital or 0
  if ctx.capital and capital > ctx.capital then
    return nil, "capital" -- the AHSync rule: never suggest what the player cannot afford
  end
  local minutes = signal.minutes or 0
  if ctx.minutes and minutes > ctx.minutes then
    return nil, "time"
  end
  local notes = {}
  local needs = neededProfession(signal.flags)
  if needs then
    if ctx.professions == nil then
      notes[#notes + 1] = string.format(L["needs %s (your professions are unknown)"], needs)
    elseif not ctx.professions[needs] then
      return nil, "profession"
    end
  end
  local profit = signal.profit
  local gpm
  if signal.action == "avoid" then
    gpm = math.huge -- avoiding a loss costs no time; it goes first in its group
  elseif profit then
    gpm = profit / math.max(minutes, 1)
  else
    gpm = 0
    notes[#notes + 1] = L["profit unknown"]
  end
  return {
    key = signal.id,
    action = signal.action,
    item = signal.item,
    module = signal.module,
    horizon = signal.horizon,
    confidence = signal.confidence,
    rationale = signal.rationale,
    capital = capital,
    profit = profit,
    minutes = minutes,
    gpm = gpm,
    flags = signal.flags,
    notes = notes,
  }
end

-- The ranked list for a market's signals: lines (at most MAX_LINES, by gold per minute) and the
-- counts of what was dropped and why.
function Today.build(signals, ctx)
  local lines, dropped = {}, { expired = 0, capital = 0, time = 0, profession = 0 }
  for _, signal in ipairs(signals) do
    local line, why = Today.line(signal, ctx)
    if line then
      lines[#lines + 1] = line
    else
      dropped[why] = (dropped[why] or 0) + 1
    end
  end
  table.sort(lines, function(a, b)
    if a.gpm ~= b.gpm then
      return a.gpm > b.gpm
    end
    if (a.profit or 0) ~= (b.profit or 0) then
      return (a.profit or 0) > (b.profit or 0)
    end
    return tostring(a.key) < tostring(b.key)
  end)
  local total = #lines
  local max = ctx.maxLines or Today.MAX_LINES
  while #lines > max do
    lines[#lines] = nil
  end
  return lines, dropped, total
end

-- Lines grouped by action in the fixed order, only the actions that have lines.
function Today.groups(lines)
  local by = {}
  for _, line in ipairs(lines) do
    by[line.action] = by[line.action] or {}
    table.insert(by[line.action], line)
  end
  local out = {}
  for _, action in ipairs(Today.ACTIONS) do
    if by[action] then
      out[#out + 1] = { action = action, lines = by[action] }
    end
  end
  return out
end

-- "+8s in 5 min (1s 60c/min), 80 %" for the row.
function Today.reason(line)
  local parts = {}
  if line.action == "avoid" then
    parts[#parts + 1] = L["do not buy or craft now"]
  else
    if line.profit then
      parts[#parts + 1] = "+" .. B.UI.MoneyShort(line.profit)
    end
    if line.minutes > 0 then
      parts[#parts + 1] = string.format(L["%d min"], line.minutes)
    end
    if line.profit and line.gpm and line.gpm ~= math.huge then
      parts[#parts + 1] = B.UI.MoneyShort(math.floor(line.gpm)) .. "/" .. L["min"]
    end
    if line.capital > 0 then
      parts[#parts + 1] = string.format(L["capital %s"], B.UI.MoneyShort(line.capital))
    end
  end
  if line.confidence then
    parts[#parts + 1] = string.format("%d %%", math.floor(line.confidence * 100 + 0.5))
  end
  for _, n in ipairs(line.notes) do
    parts[#parts + 1] = n
  end
  return table.concat(parts, ", ")
end
