-- Whether a world event runs (quests.md "What the game offers", ADR 0051). Pure: the time comes in
-- as a table. The rules and dates are Everything Quests' (Modules/MapPOI/Holidays.lua, MIT): an
-- end before its start wraps the new year; what cannot be told counts as running, so the failure
-- is a surplus pin, never a missing one.
local _, ns = ...

local Holidays = {}
ns.Holidays = Holidays

Holidays.EVENTS = {
  ["Brewfest"] = { "20/9 10:00", "6/10 10:00" },
  ["Children's Week"] = { "27/4 10:00", "4/5 10:00" },
  ["Day of the Dead"] = { "1/11 10:00", "3/11 10:00" },
  ["Hallow's End"] = { "18/10 10:00", "1/11 11:00" },
  ["Harvest Festival"] = { "21/9 00:01", "27/9 23:59" },
  ["Love is in the Air"] = { "11/2 10:00", "15/2 10:00" },
  ["Midsummer"] = { "21/6 04:00", "5/7 04:00" },
  ["Noblegarden"] = { "5/4 00:01", "11/4 23:59" },
  ["Pilgrim's Bounty"] = { "24/11 01:00", "30/11 23:59" },
  ["Winter Veil"] = { "15/12 10:00", "2/1 10:00" },
}
-- The one table that needs a new row every year: the lunar new year moves.
Holidays.LUNAR = {
  [2026] = { "16/2 06:00", "9/3 06:00" },
  [2027] = { "5/2 06:00", "19/2 06:00" },
  [2028] = { "24/1 06:00", "14/2 06:00" },
}

local function stamp(month, day, hour, minute)
  return month * 1000000 + day * 10000 + hour * 100 + minute
end

local function parse(text)
  local day, month, hour, minute = string.match(text, "^(%d+)/(%d+) (%d+):(%d+)$")
  return stamp(tonumber(month), tonumber(day), tonumber(hour), tonumber(minute))
end

local function within(range, now)
  local current = stamp(now.month, now.day, now.hour, now.minute or 0)
  local from, to = parse(range[1]), parse(range[2])
  if from <= to then
    return current >= from and current <= to
  end
  return current >= from or current <= to
end

-- The faire opens on the first Monday on or after the 4th and runs seven days from 03:00.
local function darkmoon(now)
  if not now.weekday then
    return true
  end
  local first = (now.weekday - 1 - (now.day - 1)) % 7 + 1 -- the weekday of the 1st, 1 = Sunday
  local start = (3 - first - 4) % 7 + 4
  if now.day == start then
    return now.hour >= 3
  elseif now.day == start + 7 then
    return now.hour < 3
  end
  return now.day > start and now.day < start + 7
end

-- Whether the event runs at `now` ({ year, month, day, weekday, hour, minute }, nil when the client
-- has no clock); an event without dates counts as running.
function Holidays.Running(name, now)
  if not now then
    return true
  end
  if name == "Darkmoon Faire" then
    return darkmoon(now)
  end
  local range = Holidays.EVENTS[name]
  if name == "Lunar Festival" then
    range = Holidays.LUNAR[now.year]
  end
  return range == nil or within(range, now)
end
