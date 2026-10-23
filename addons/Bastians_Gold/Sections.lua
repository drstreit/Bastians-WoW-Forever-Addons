-- Gold's detail sections (gold.md): the item "Price" section with its tooltip lines, and the NPC
-- "Sells" section from the own merchant captures (unit prices with the AH comparison). Data keeps its
-- vendor list from the data; this one is what the player saw. Unknown is never shown as 0.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Sections = {}
ns.Sections = Sections

local function prices()
  return B:GetService("prices")
end

local function itemName(itemID)
  local name = B:Entity("item:" .. itemID):Name()
  if name then
    return name
  end
  local info = B.Compat.GetItemInfo(itemID)
  return info and info.name or (L["Item"] .. " " .. itemID)
end

-- "3 min ago", "2 h ago", "4 d ago"; nil without an age.
function Sections.AgeText(seconds)
  if not seconds then
    return nil
  end
  if seconds < 3600 then
    return string.format(L["%d min ago"], math.floor(seconds / 60))
  elseif seconds < 86400 then
    return string.format(L["%d h ago"], math.floor(seconds / 3600))
  end
  return string.format(L["%d d ago"], math.floor(seconds / 86400))
end

-- "scan, 3 min ago" | "US beta, 2 d ago" | "scan, 3 d ago, stale"
function Sections.SourceText(p)
  local parts = { p.source == "market" and (p.label or L["market"]) or L["scan"] }
  local age = Sections.AgeText(p.age)
  if age then
    parts[#parts + 1] = age
  end
  if p.stale then
    parts[#parts + 1] = L["stale"]
  end
  return table.concat(parts, ", ")
end

-- Vendor sell price per unit: the own capture first, else the client's item data; nil when unknown.
function Sections.SellPrice(itemID)
  local captured = ns.Capture.SellPrice and ns.Capture.SellPrice(itemID) or nil
  if captured then
    return captured
  end
  local info = B.Compat.GetItemInfo(itemID)
  local sell = info and tonumber(info.sellPrice) or nil
  if sell and sell > 0 then
    return sell
  end
  return nil
end

-- The item "Price" rows: AH median, lowest buyout, sales per day, vendor sell price. A line is only
-- there when its value is known; without any AH price the first row says so.
local function priceRows(ref)
  local _, itemID = B.Entity.Parse(ref)
  if type(itemID) ~= "number" then
    return nil
  end
  local rows = {}
  local service = prices()
  local p = service and service:Price(itemID) or nil
  if p and (p.median or p.minBuyout) then
    local source = " (" .. Sections.SourceText(p) .. ")"
    if p.median then
      rows[#rows + 1] = { text = L["AH median"] .. source, value = p.median, valueKind = "money" }
    end
    if p.minBuyout then
      rows[#rows + 1] = { text = L["AH lowest buyout"], value = p.minBuyout, valueKind = "money" }
    end
    if p.quantity then
      rows[#rows + 1] = { text = L["Listed"], value = p.quantity, valueKind = "number" }
    end
    if p.salesPerDay then
      rows[#rows + 1] = { text = L["Sales per day"], value = p.salesPerDay, valueKind = "number" }
    end
    if p.median30d then
      rows[#rows + 1] = { text = L["30-day median"], value = p.median30d, valueKind = "money" }
    end
    if p.low30d and p.high30d then
      rows[#rows + 1] = {
        text = L["30-day range"] .. "  " .. B.UI.Money(p.low30d) .. " - " .. B.UI.Money(p.high30d),
      }
    end
  else
    local why = service and L["no scan, no market data"] or L["Gold is disabled"]
    rows[#rows + 1] = { text = L["AH price"] .. ": " .. L["unknown"] .. " (" .. why .. ")", color = S.C.dim }
  end
  local sell = Sections.SellPrice(itemID)
  if sell then
    rows[#rows + 1] = { text = L["Vendor sells for"], value = sell, valueKind = "money" }
  end
  return rows
end

local sectionsMod -- the Gold module, set by Sections.Register (the tooltip reads its settings)

-- Tooltip lines: only what is known, so an unknown price shows nothing rather than 0.
local function priceTooltipRows(ref)
  local _, itemID = B.Entity.Parse(ref)
  if type(itemID) ~= "number" then
    return nil
  end
  local service = prices()
  local p = service and service:Price(itemID) or nil
  local rows = {}
  if p and p.median then
    rows[#rows + 1] = {
      text = L["AH median"] .. " (" .. Sections.SourceText(p) .. ")",
      value = p.median,
      valueKind = "money",
    }
  end
  if p and p.minBuyout then
    rows[#rows + 1] = { text = L["AH lowest buyout"], value = p.minBuyout, valueKind = "money" }
  end
  -- the vendor sell price the client knows: also without any
  -- auction data, so retail tooltips say something; off through the setting
  if sectionsMod and sectionsMod.db.profile.tooltipSell ~= false then
    local sell = Sections.SellPrice(itemID)
    if sell then
      rows[#rows + 1] = { text = L["Vendor sells for"], value = sell, valueKind = "money" }
    end
  end
  return #rows > 0 and rows or nil
end

-- The NPC "Sells" rows from the own capture of this merchant: unit price, stack, limited stock and
-- the AH median beside it when known.
local function sellsRows(ref)
  local _, npcID = B.Entity.Parse(ref)
  local m = type(npcID) == "number" and ns.Capture.Merchant(npcID) or nil
  if not (m and m.offers and m.offers ~= "") then
    return nil
  end
  local rows = {}
  local service = prices()
  for offer in string.gmatch(m.offers, "[^;]+") do
    local itemID, price, stack, available, extended =
      string.match(offer, "^(%-?%d+):(%d*):(%d*):(%d*):(%d*)$")
    itemID, price, stack, available = tonumber(itemID), tonumber(price), tonumber(stack), tonumber(available)
    if itemID then
      local unit = (price and stack and stack > 0) and math.floor(price / stack + 0.5) or price
      local text = itemName(itemID)
      if stack and stack > 1 then
        text = text .. " x" .. stack
      end
      if available then
        text = text .. " " .. string.format(L["(%d in stock)"], available)
      end
      if extended == "1" then
        text = text .. " " .. L["(plus tokens or items)"]
      end
      local p = service and service:Price(itemID) or nil
      if p and p.median then
        text = text .. "  " .. S.H.muted .. L["AH"] .. " " .. B.UI.Money(p.median) .. "|r"
      end
      rows[#rows + 1] =
        { text = text, ref = "item:" .. itemID, value = unit, valueKind = unit and "money" or nil }
    end
  end
  if #rows == 0 then
    return nil
  end
  local age = Sections.AgeText(GetServerTime() - (m.at or 0))
  if age then
    rows[#rows + 1] = { text = string.format(L["seen %s"], age), color = S.C.dim }
  end
  return rows
end

function Sections.Register(mod)
  sectionsMod = mod
  if ns.Worth then
    ns.Worth.Register(mod) -- the worth of items, mobs, nodes, spots and strategies (C3)
  end
  B:RegisterDetailSection(mod, {
    id = "gold.price",
    title = L["Price"],
    types = { "item" },
    order = 25,
    block = { limit = 10 }, -- the dossier block (C2): every price line shows
    cache = false, -- the age in the text moves with the clock; the service answers from memory
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = priceRows,
    tooltip = { max = 3, build = priceTooltipRows }, -- median, lowest buyout, the vendor line (R9)
  })
  B:RegisterDetailSection(mod, {
    id = "gold.sells",
    title = L["Sells (seen)"],
    types = { "npc" },
    order = 31,
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = sellsRows,
  })
end
