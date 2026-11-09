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

-- "scan, 3 min ago" | "EU normal, 2 d ago" | "Auctionator, 1 d ago" | "scan, 3 d ago, stale"
function Sections.SourceText(p)
  local named = p.source == "market" or p.source == "addon"
  local parts = { named and (p.label or L["market"]) or L["scan"] }
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
-- What to buy a thing for: a reagent a vendor sells at the vendor's price when that is the lower,
-- else the auction house's median; nil when neither is known.
local function costOf(itemID)
  local d = B:GetService("data")
  local service = prices()
  local p = service and service:Price(itemID) or nil
  local median = p and p.median or nil
  local item = d and d:Get("item", itemID)
  local sellers = d and d:Index("npc.bySoldItem", itemID)
  local vendor = item and item.buy and item.buy > 0 and sellers and #sellers > 0 and item.buy or nil
  if median and vendor then
    return math.min(median, vendor)
  end
  return median or vendor
end
Sections.CostOf = costOf

local function medianOf(itemID)
  local service = prices()
  local p = service and service:Price(itemID) or nil
  return p and p.median or nil
end
Sections.MedianOf = medianOf

-- What disenchanting the item brings after the cut: value, missing materials (Craft for gold);
-- nil when the item has no disenchant list.
function Sections.DisenchantValue(itemID)
  local d = B:GetService("data")
  local item = d and d:Get("item", itemID)
  local list = item and item.disenchant and d:Get("disenchant", item.disenchant)
  if not (list and list.loot) then
    return nil
  end
  return ns.Pricing.Disenchant(list.loot, medianOf)
end

-- "Disenchanting brings": the materials' value after the cut, with what is unknown said.
local function disenchantRow(itemID)
  local d = B:GetService("data")
  local item = d and d:Get("item", itemID)
  local list = item and item.disenchant and d:Get("disenchant", item.disenchant)
  if not (list and type(list.loot) == "table" and #list.loot > 0) then
    return nil
  end
  local value, missing = ns.Pricing.Disenchant(list.loot, medianOf)
  if value <= 0 then
    return nil
  end
  local words = missing > 0 and L["Disenchanting brings at least"] or L["Disenchanting brings"]
  return { text = words, value = value, valueKind = "money" }
end

-- A recipe's margin: the reagents at the cheaper of vendor and AH, the product after the cut.
local function craftRows(ref)
  local _, recipeID = B.Entity.Parse(ref)
  local d = B:GetService("data")
  local recipe = d and d:Get("recipe", recipeID)
  if not (recipe and recipe.reagents) then
    return nil
  end
  local c = ns.Pricing.Craft(recipe, function(itemID)
    return itemID == recipe.item and medianOf(itemID) or costOf(itemID)
  end)
  local rows = {}
  local words = c.missing > 0 and L["Reagents cost at least"] or L["Reagents cost"]
  rows[#rows + 1] = { text = words, value = c.cost, valueKind = "money" }
  if c.missing > 0 then
    rows[#rows + 1] = { text = string.format(L["%d reagents without a price"], c.missing), color = S.C.dim }
  end
  if c.net then
    rows[#rows + 1] = { text = L["The product brings, after the cut"], value = c.net, valueKind = "money" }
  else
    rows[#rows + 1] = { text = L["The product's price is unknown"], color = S.C.dim }
  end
  if c.profit then
    rows[#rows + 1] = { text = L["Profit per craft"], value = c.profit, valueKind = "money" }
  end
  return rows
end

local POSITION_WORDS = {
  buy = "Low in its 30-day range: a time to buy.",
  hold = "In the middle of its 30-day range.",
  sell = "High in its 30-day range: a time to sell.",
}

-- An item's tile (ADR 0056): the mark "Bargain" while the lowest listing is far under the 30-day
-- median (catalog review A5.3); nothing otherwise, so Data's line stays. Dropped on every price update.
local function itemTile(ref)
  local _, itemID = B.Entity.Parse(ref)
  if type(itemID) ~= "number" then
    return nil
  end
  local service = prices()
  local p = service and service:Price(itemID) or nil
  if ns.Pricing.Bargain(p) then
    return { mark = { text = L["Bargain"], token = "good" } }
  end
  return nil
end

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
    rows[#rows + 1] = ns.History.Row(itemID) -- the sparkline of the own scans (#19), nil below two days
    local position = ns.Pricing.Position(p)
    if position then
      rows[#rows + 1] = { text = L[POSITION_WORDS[position.signal]] }
    end
    if ns.Pricing.Dumped(p) then
      rows[#rows + 1] = { text = L["The lowest listing is far under the median: wait, do not follow it."] }
    end
    if ns.Pricing.Bargain(p) then
      rows[#rows + 1] = { text = L["The lowest listing is far under the 30-day median: a bargain to buy."] }
    end
  else
    local why = service and L["no scan, no market data"] or L["Gold is disabled"]
    rows[#rows + 1] = { text = L["AH price"] .. ": " .. L["unknown"] .. " (" .. why .. ")", color = S.C.dim }
  end
  local sell = Sections.SellPrice(itemID)
  if sell then
    rows[#rows + 1] = { text = L["Vendor sells for"], value = sell, valueKind = "money" }
  end
  local disenchant = disenchantRow(itemID)
  if disenchant then
    rows[#rows + 1] = disenchant
  end
  for _, row in ipairs(ns.Ledger.Rows(B:Entity(ref):Name())) do
    rows[#rows + 1] = row
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
    chapter = "worth", -- on the sheet (ADR 0054)
    title = L["Price"],
    types = { "item" },
    order = 25,
    block = { limit = 10 }, -- the dossier block (C2): every price line shows
    cache = false, -- the age in the text moves with the clock; the service answers from memory
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = priceRows,
    tooltip = { max = 3, build = priceTooltipRows }, -- median, lowest buyout, the vendor line (R9)
  })
  B:RegisterFacet(mod, {
    facet = "tile",
    types = { "item" },
    priority = 120, -- over Data's line (100); it answers the mark only
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    rule = itemTile,
  })
  B:RegisterDetailSection(mod, {
    id = "gold.craft",
    chapter = "worth", -- on the sheet (ADR 0054)
    title = L["Craft margin"],
    types = { "recipe" },
    order = 26,
    cache = false,
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = craftRows,
  })
  B:RegisterDetailSection(mod, {
    id = "gold.sells",
    chapter = "sells", -- on the sheet (ADR 0054)
    title = L["Sells (seen)"],
    types = { "npc" },
    order = 31,
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = sellsRows,
  })
end
