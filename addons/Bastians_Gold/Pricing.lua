-- The pricing rules: pure, plain tables in and out, no
-- WoW API. Where a price sits in its range, a listing far under the median, the floor a cost sets,
-- what a craft and a disenchant bring. Unknown stays nil: a missing price is counted, never 0.
local _, ns = ...

local Pricing = {}
ns.Pricing = Pricing

Pricing.AH_CUT = 0.05 -- the auction house keeps this share of a sale (both clients)
Pricing.LOW_BAND, Pricing.HIGH_BAND = 0.25, 0.75 -- the lower and upper part of the 30-day range
Pricing.MIN_SPREAD = 1.25 -- a high under a quarter above the low is no range to read
Pricing.DUMP_RATIO = 0.7 -- a lowest listing under this share of the median is a dump
Pricing.BARGAIN_RATIO = 0.7 -- a lowest listing under this share of the 30-day median is a bargain

-- Where the median sits in its 30-day range: { at = 0..1, signal = "buy" | "hold" | "sell" }, or
-- nil when the range is unknown or too narrow to mean anything.
function Pricing.Position(p)
  local low, high, now = p and p.low30d, p and p.high30d, p and p.median
  if not (low and high and now) or low <= 0 or high < low * Pricing.MIN_SPREAD then
    return nil
  end
  local at = math.max(0, math.min(1, (now - low) / (high - low)))
  local signal = at <= Pricing.LOW_BAND and "buy" or at >= Pricing.HIGH_BAND and "sell" or "hold"
  return { at = at, signal = signal }
end

-- True when the lowest listing lies far under the median: posting now means following a dump.
function Pricing.Dumped(p)
  local low, median = p and p.minBuyout, p and p.median
  return low ~= nil and median ~= nil and median > 0 and low < median * Pricing.DUMP_RATIO
end

-- The buyer's side of the same number (catalog review A5.3, 07.11.2026): true when the lowest
-- listing lies far under the 30-day median, so buying now beats the usual price. The 30-day median,
-- not today's: a day's dump pulls today's median down with it. Unknown is nil, never false.
function Pricing.Bargain(p)
  local low, median = p and p.minBuyout, p and p.median30d
  if low == nil or median == nil or median <= 0 then
    return nil
  end
  return low < median * Pricing.BARGAIN_RATIO
end

-- The lowest price that brings a cost back after the house's cut, whole copper.
function Pricing.Floor(cost, cut)
  if not cost or cost <= 0 then
    return nil
  end
  return math.ceil(cost / (1 - (cut or Pricing.AH_CUT)))
end

-- A craft: recipe = { count, reagents = { { itemID, count } }, item }, priceOf(itemID) -> copper or
-- nil; opts.yield is the units a craft gives on average when it is not the recipe's count.
-- -> { cost, missing (reagents without a price), net (the product after the cut), profit, unit }.
-- A cost with a reagent missing is a lower bound: `profit` stays nil then.
function Pricing.Craft(recipe, priceOf, opts)
  local cut = opts and opts.cut or Pricing.AH_CUT
  local yield = opts and opts.yield or (recipe and recipe.count) or 1
  local cost, missing = 0, 0
  for _, rg in ipairs(recipe and recipe.reagents or {}) do
    local price = priceOf(rg[1])
    if price then
      cost = cost + price * (rg[2] or 1)
    else
      missing = missing + 1
    end
  end
  local product = recipe and recipe.item and priceOf(recipe.item)
  local net = product and math.floor(product * yield * (1 - cut) + 0.5) or nil
  local out = { cost = cost, missing = missing, net = net }
  if yield > 0 then
    out.unit = math.ceil(cost / yield)
  end
  if net and missing == 0 then
    out.profit = net - cost
  end
  return out
end

-- The three ways to sell a craft (gold.md "Craft for gold", A5.1): the product at the auction
-- house after the cut, to a vendor, or disenchanted, times the recipe's count. `sellOf(item)` the
-- vendor price, `disenchantOf(item)` -> value, missing. -> { cost, missing, ah, vendor,
-- disenchant, best, way, profit }: `best` the highest known way ("ah" | "vendor" | "disenchant"),
-- `profit` = best - cost only when every reagent has a price; an unknown way stays nil, and a
-- disenchant value with an unpriced material counts as unknown (a lower bound is no way to pick).
function Pricing.Ways(recipe, priceOf, sellOf, disenchantOf, opts)
  local c = Pricing.Craft(recipe, priceOf, opts)
  local yield = opts and opts.yield or (recipe and recipe.count) or 1
  local out = { cost = c.cost, missing = c.missing, ah = c.net }
  local item = recipe and recipe.item
  local sell = item and sellOf and sellOf(item) or nil
  if sell then
    out.vendor = sell * yield
  end
  if item and disenchantOf then
    local value, missing = disenchantOf(item)
    if value and (missing or 0) == 0 then
      out.disenchant = math.floor(value * yield + 0.5)
    end
  end
  for _, way in ipairs({ "ah", "vendor", "disenchant" }) do
    local v = out[way]
    if v and (not out.best or v > out.best) then
      out.best, out.way = v, way
    end
  end
  if out.best and c.missing == 0 then
    out.profit = out.best - c.cost
  end
  return out
end

-- What disenchanting brings after the cut: loot = { { itemID, chance percent, min, max } }.
-- -> value, missing (materials without a price or a chance); value is what the known ones bring.
function Pricing.Disenchant(loot, priceOf, cut)
  local keep = 1 - (cut or Pricing.AH_CUT)
  local value, missing = 0, 0
  for _, l in ipairs(loot or {}) do
    local price, chance = priceOf(l[1]), l[2]
    if price and chance then
      local count = ((l[3] or 1) + (l[4] or l[3] or 1)) / 2
      value = value + price * count * chance / 100 * keep
    else
      missing = missing + 1
    end
  end
  return math.floor(value + 0.5), missing
end
