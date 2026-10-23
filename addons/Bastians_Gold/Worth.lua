-- Bastian's Gold: what items, mobs, nodes, farm spots and strategies are worth (gold.md "Worth",
-- C3): the AH median with its age and the vendor sell price for an item, the expected loot value
-- per kill for a mob, the item's price for a node, gold per hour and the status for a spot or a
-- strategy. Pure functions take plain tables; the provider feeds them from the services.
-- Unknown stays unknown ("price unknown"), never 0.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Worth = {}
ns.Worth = Worth

-- Worth.item(price, sell): price = the prices service answer ({ median, age, ... }) or nil, sell =
-- the vendor sell price in copper or nil.
function Worth.item(price, sell)
  local median = price and price.median or nil
  if not median and not sell then
    return { text = L["price unknown"] }
  end
  local parts = {}
  if median then
    local text = L["AH"] .. " " .. B.UI.Money(median)
    local age = price.age and ns.Sections and ns.Sections.AgeText(price.age) or nil
    if age then
      text = text .. " (" .. age .. ")"
    end
    parts[#parts + 1] = text
  end
  if sell then
    parts[#parts + 1] = L["vendor"] .. " " .. B.UI.Money(sell)
  end
  return { text = table.concat(parts, " - "), copper = median or sell }
end

-- Worth.mob(loot, priceOf): loot = { { itemID, chancePercent }, ... }; priceOf(itemID) -> copper
-- or nil. The sum of chance x price over the rows with a price, per kill.
function Worth.mob(loot, priceOf)
  if not loot or #loot == 0 then
    return nil
  end
  local total, known, unknown = 0, 0, 0
  for _, l in ipairs(loot) do
    local price = priceOf and priceOf(l[1]) or nil
    if price and l[2] then
      total = total + price * l[2] / 100
      known = known + 1
    else
      unknown = unknown + 1
    end
  end
  if known == 0 then
    return { text = L["loot price unknown"] }
  end
  local copper = math.floor(total + 0.5)
  local text = string.format(L["~%s per kill"], B.UI.Money(copper))
  if unknown > 0 then
    text = text .. " " .. string.format(L["(%d items without price)"], unknown)
  end
  return { text = text, copper = copper }
end

-- Worth.node(itemID, priceOf): the price of what the node yields.
function Worth.node(itemID, priceOf)
  local price = itemID and priceOf and priceOf(itemID) or nil
  if not price then
    return { text = L["price unknown"] }
  end
  return { text = L["AH"] .. " " .. B.UI.Money(price), copper = price }
end

-- Worth.spot(gph, unknown, status): gold per hour in copper or nil, items without a price, the
-- status word (verified, unverified, refuted).
function Worth.spot(gph, unknown, status)
  local parts = {}
  if gph then
    parts[#parts + 1] = B.UI.MoneyShort(gph) .. "/h"
  else
    parts[#parts + 1] = L["gold/h unknown"]
  end
  if unknown and unknown > 0 then
    parts[#parts + 1] = string.format(L["(%d items without price)"], unknown)
  end
  parts[#parts + 1] = L[status or "unverified"]
  return { text = table.concat(parts, ", "), copper = gph }
end

-- The worth provider (core-contracts §4): items, mobs and objects with loot, nodes, spots and
-- strategies, from the prices and data services.
-- Worth.topDrops(loot, priceOf, n): the n drops worth most per kill (chance x price), each
-- { itemID, chance, price }; drops without a price follow by chance (unknown is not zero).
function Worth.topDrops(loot, priceOf, n)
  local out = {}
  for _, l in ipairs(loot or {}) do
    local price = priceOf and priceOf(l[1]) or nil
    out[#out + 1] = { itemID = l[1], chance = l[2], price = price }
  end
  table.sort(out, function(a, b)
    local va = a.price and a.chance and a.price * a.chance or nil
    local vb = b.price and b.chance and b.price * b.chance or nil
    if (va ~= nil) ~= (vb ~= nil) then
      return va ~= nil
    end
    if va ~= vb then
      return va > vb
    end
    if (a.chance or 0) ~= (b.chance or 0) then
      return (a.chance or 0) > (b.chance or 0)
    end
    return a.itemID < b.itemID
  end)
  for i = #out, (n or 3) + 1, -1 do
    out[i] = nil
  end
  return out
end

function Worth.Register(mod)
  local Spots = ns.Spots
  mod.Worth = Worth -- for the tests
  local function priceOf(itemID)
    local service = B:GetService("prices")
    local p = service and service:Price(itemID) or nil
    return p and p.median or nil
  end
  -- The drops worth most on a monster's tooltip (guide gaps, 23.10.2026: AHSyncGuide showed the
  -- top drops with chance and price): tooltip lines only, the page has Data's Drops block.
  B:RegisterDetailSection(mod, {
    id = "gold.loot",
    title = L["Drops"],
    types = { "npc", "object" },
    order = 41,
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    build = function()
      return nil
    end,
    tooltip = {
      max = 3,
      build = function(ref)
        local typ, id = B.Entity.Parse(ref)
        local data = B:GetService("data")
        local r = data and data:Get(typ, id) or nil
        if not (r and r.loot) then
          return nil
        end
        local rows = {}
        for _, drop in ipairs(Worth.topDrops(r.loot, priceOf, 3)) do
          local name = B:Entity("item:" .. drop.itemID):Name() or ("item " .. drop.itemID)
          local chance = drop.chance and string.format("  %s %%", drop.chance) or ""
          rows[#rows + 1] = {
            text = name .. chance,
            icon = B:Entity("item:" .. drop.itemID):Icon(),
            value = drop.price,
            valueKind = "money",
          }
        end
        return #rows > 0 and rows or nil
      end,
    },
  })
  B:RegisterWorth(mod, {
    types = { "item", "npc", "object", "node", "spot", "strategy" },
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_DATA_LOADED" },
    worth = function(ref)
      local typ, id = B.Entity.Parse(ref)
      local data = B:GetService("data")
      local r = data and data:Get(typ, id) or nil
      if typ == "item" then
        local service = B:GetService("prices")
        return Worth.item(service and service:Price(id) or nil, r and r.sell or nil)
      elseif typ == "npc" or typ == "object" then
        return Worth.mob(r and r.loot or nil, priceOf)
      elseif typ == "node" then
        return Worth.node(r and r.item or nil, priceOf)
      elseif typ == "spot" then
        if not (r and Spots) then
          return nil
        end
        local gph, unknown = Spots.GoldPerHour(r)
        return Worth.spot(gph, unknown, r.status)
      elseif typ == "strategy" then
        if not r then
          return nil
        end
        local spot = r.subject and data:Get("spot", r.subject) or nil
        if spot and Spots then
          local gph, unknown = Spots.GoldPerHour(spot)
          return Worth.spot(gph, unknown, r.status)
        end
        return { text = L[r.status or "unverified"] }
      end
      return nil
    end,
  })
  -- The sorts Gold adds to the lists (ADR 0016): loot per kill, gold per hour, the price.
  local function short(copper)
    return B.UI.MoneyShort(copper)
  end
  B:RegisterFilter(mod, {
    id = "gold.lootPerKill",
    kind = "sort",
    types = { "npc" },
    label = L["Loot per kill"],
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    value = function(_, r)
      local w = r and Worth.mob(r.loot, priceOf) or nil
      return w and w.copper or nil
    end,
    text = function(copper)
      return string.format(L["~%s per kill"], short(copper))
    end,
  })
  B:RegisterFilter(mod, {
    id = "gold.perHour",
    kind = "sort",
    types = { "spot" },
    label = L["Gold per hour"],
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    value = function(_, r)
      if not (r and Spots) then
        return nil
      end
      return (Spots.GoldPerHour(r))
    end,
    text = function(copper)
      return short(copper) .. "/h"
    end,
  })
  B:RegisterFilter(mod, {
    id = "gold.price",
    kind = "sort",
    types = { "item", "node" },
    label = L["Price"],
    invalidateOn = { "BASTIANS_PRICES_UPDATED" },
    value = function(ref, r)
      local typ, id = B.Entity.Parse(ref)
      if typ == "item" then
        return priceOf(id) or (r and r.sell) or nil
      end
      return r and r.item and priceOf(r.item) or nil
    end,
    text = short,
  })
end
