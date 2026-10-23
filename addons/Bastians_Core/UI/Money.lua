-- UI kit: money and number formatting. Money is integer copper; unknown (nil) stays nil, never "0c".
local _, ns = ...
local B = ns.B

-- The coin letters in the theme's coin colours (ST3), built at use: a theme change shows at once.
local function coins()
  local H = ns.Style.H
  return H.coinGold .. "g|r", H.coinSilver .. "s|r", H.coinCopper .. "c|r"
end

-- Bastians.UI.Money(copper) -> "12g 03s" | "3s 45c" | "45c" | nil for nil (unknown is not zero).
function B.UI.Money(copper)
  if copper == nil then
    return nil
  end
  copper = math.floor(copper + 0.5)
  local negative = copper < 0
  if negative then
    copper = -copper
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local GOLD, SILVER, COPPER = coins()
  local text
  if g > 0 then
    text = string.format("%d%s %02d%s", g, GOLD, s, SILVER)
  elseif s > 0 then
    text = string.format("%d%s %02d%s", s, SILVER, c, COPPER)
  else
    text = string.format("%d%s", c, COPPER)
  end
  return negative and ("-" .. text) or text
end

-- Short form for tight columns: "12.3g", "45s", "7c"; nil stays nil.
function B.UI.MoneyShort(copper)
  if copper == nil then
    return nil
  end
  copper = math.floor(copper + 0.5)
  local GOLD, SILVER, COPPER = coins()
  if copper >= 10000 then
    return string.format("%.1f%s", copper / 10000, GOLD)
  elseif copper >= 100 then
    return string.format("%d%s", math.floor(copper / 100), SILVER)
  end
  return string.format("%d%s", copper, COPPER)
end

-- Bastians.UI.Distance(yards) -> "210 yd" | "1.2 k yd" | nil for nil (unknown stays unknown).
function B.UI.Distance(yards)
  if yards == nil then
    return nil
  end
  if yards >= 1000 then
    return string.format("%.1f k yd", yards / 1000)
  end
  return string.format("%d yd", math.floor(yards + 0.5))
end

-- Formats a row value by its kind (core-contracts §7). Unknown kinds and nil pass through.
function B.UI.FormatValue(value, kind)
  if value == nil then
    return nil
  end
  if kind == "money" then
    return B.UI.Money(value)
  elseif kind == "percent" then
    -- whole numbers from 10 %, one decimal below, never a rare drop shown as "0 %" (rule 2)
    if value >= 9.95 then
      return string.format("%d %%", math.floor(value + 0.5))
    elseif value >= 0.05 then
      return string.format("%.1f %%", value)
    end
    return "<0.1 %"
  elseif kind == "number" then
    return tostring(value)
  end
  return tostring(value)
end
