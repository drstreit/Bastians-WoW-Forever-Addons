-- The price history (gold.md "Price history", #19, 04.11.2026): the own scans' medians, one line per
-- scan day, kept 14 days per realm and faction in BastiansGoldDB.global.history, and the sparkline
-- the Price section draws from it. A day without a scan is a gap, never a price of 0.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L

local History = {}
ns.History = History

History.DAYS = 14
local BAR = "Interface\\Buttons\\WHITE8X8"
local BAR_W, BAR_LOW, BAR_HIGH = 3, 2, 12 -- pixels: a bar's width, the lowest and highest bar

local mod

local function scanKey(realm, faction)
  return tostring(realm or "unknown") .. "/" .. tostring(faction or "unknown")
end

-- The realm and faction of the player, the way Capture names its scans.
function History.Key()
  return scanKey(GetRealmName() or "unknown", UnitFactionGroup("player") or "unknown")
end

local function store(key)
  local g = mod and mod.db.global
  if not g then
    return nil
  end
  if type(g.history) ~= "table" then
    g.history = {}
  end
  local h = g.history[key]
  if type(h) ~= "table" then
    h = { days = {}, ts = {} }
    g.history[key] = h
  end
  return h
end

-- Pure: one scan day's line, ";id:median;id:median;" by item id (items as Prices builds them).
function History.Line(items)
  local ids = {}
  for id, it in pairs(items or {}) do
    if type(id) == "number" and it.median then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local parts = {}
  for i, id in ipairs(ids) do
    parts[i] = id .. ":" .. items[id].median
  end
  return ";" .. table.concat(parts, ";") .. ";"
end

-- Keeps a summarised scan as its day's line (the day's newest scan wins) and drops the days older
-- than History.DAYS. A scan already kept (the newest one again after a /reload) changes nothing.
function History.Record(scan)
  if not (scan and scan.ts and scan.items) then
    return false
  end
  local h = store(scanKey(scan.realm, scan.faction))
  if not h then
    return false
  end
  local day = math.floor(scan.ts / 86400)
  if h.ts[day] and h.ts[day] >= scan.ts then
    return false
  end
  h.days[day], h.ts[day] = History.Line(scan.items), scan.ts
  for d in pairs(h.days) do
    if d <= day - History.DAYS then
      h.days[d], h.ts[d] = nil, nil
    end
  end
  return true
end

-- An item's medians, oldest first: { { day, median } } over the kept days that saw it.
function History.Series(itemID, key)
  local h = mod and type(mod.db.global.history) == "table" and mod.db.global.history[key or History.Key()]
  if not (h and itemID) then
    return {}
  end
  local days = {}
  for d in pairs(h.days) do
    days[#days + 1] = d
  end
  table.sort(days)
  local out, needle = {}, ";" .. itemID .. ":(%d+);"
  for _, d in ipairs(days) do
    local median = tonumber(string.match(h.days[d], needle))
    if median then
      out[#out + 1] = { day = d, median = median }
    end
  end
  return out
end

-- Pure: the sparkline of a series as inline textures (one bar per known day, the lowest median
-- the shortest bar), so every place that shows a row's text draws it; nil below two points.
function History.Spark(series, color)
  if #series < 2 then
    return nil
  end
  local low, high = series[1].median, series[1].median
  for _, p in ipairs(series) do
    low, high = math.min(low, p.median), math.max(high, p.median)
  end
  local c = color or S.C.gold
  local r, g, b = c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5
  local bars = {}
  for i, p in ipairs(series) do
    local h = high > low and BAR_LOW + (BAR_HIGH - BAR_LOW) * (p.median - low) / (high - low)
      or (BAR_LOW + BAR_HIGH) / 2
    h = math.floor(h + 0.5)
    -- bottoms aligned: the client centres an inline texture on the line, so lower it by half
    -- of what it lacks of the highest bar
    bars[i] = string.format(
      "|T%s:%d:%d:0:%d:8:8:0:8:0:8:%d:%d:%d|t",
      BAR,
      h,
      BAR_W,
      -math.floor((BAR_HIGH - h) / 2 + 0.5),
      r,
      g,
      b
    )
  end
  return table.concat(bars, "|T" .. BAR .. ":1:1:0:0:8:8:0:0:0:0|t")
end

-- Pure: the change from the first kept day to the last, "+12 %", "-8 %" or "steady".
function History.Change(series)
  local first, last = series[1], series[#series]
  if not (first and last and first ~= last and first.median > 0) then
    return nil
  end
  local pct = math.floor((last.median - first.median) / first.median * 100 + 0.5)
  if pct == 0 then
    return L["steady"]
  end
  return string.format("%+d %%", pct)
end

-- The Price section's row, or nil while fewer than two scan days saw the item.
function History.Row(itemID)
  local series = History.Series(itemID)
  local spark = History.Spark(series)
  if not spark then
    return nil
  end
  return {
    text = string.format(L["Your scans, %d days"], #series) .. "  " .. spark,
    value = History.Change(series),
  }
end

function History.Register(m)
  mod = m
end
