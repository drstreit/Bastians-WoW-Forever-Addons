-- Bastian's Helpers, the merchant (helpers.md "Merchant"): repair, sell junk with Undo, restock
-- the character's list, Alt-click buys a stack.
local _, ns = ...
local B = Bastians
local L = ns.L
local Helpers = ns.Helpers
local Model = Helpers.Model

local Merchant = {}
ns.Merchant = Merchant
Helpers.Merchant = Merchant

Merchant.SELL_BATCH = 8 -- stacks sold per step
Merchant.SELL_STEP = 0.2 -- seconds between the steps

local open = false
local visit -- { sold = { { itemID, count } }, value, unknown } of this merchant visit

-- The merchant's offers as Model.Restock wants them.
local function offers()
  local out = {}
  for i = 1, B.Compat.GetNumMerchantItems() do
    local it = B.Compat.GetMerchantItem(i)
    if it and it.itemID and it.isPurchasable ~= false and not it.hasExtendedCost then
      out[#out + 1] = {
        index = i,
        itemID = it.itemID,
        stack = it.stack or 1,
        price = it.price,
        numAvailable = it.numAvailable,
        maxStack = B.Compat.MerchantMaxStack(i),
      }
    end
  end
  return out
end

function Merchant.Repair()
  local r = B.Compat.MerchantRepair()
  local who = Model.Repair(r, B.Compat.GetMoney(), Helpers.Profile().guildRepair)
  if who == "guild" or who == "self" then
    B.Compat.RepairAll(who == "guild")
    Helpers.Notice(
      string.format(
        who == "guild" and L["Repaired for %s from the guild bank"] or L["Repaired for %s"],
        B.UI.Money(r.cost)
      )
    )
  elseif who == "short" then
    Helpers.Notice(
      string.format(L["Repair costs %s, you have %s"], B.UI.Money(r.cost), B.UI.Money(B.Compat.GetMoney()))
    )
  end
  return who
end

function Merchant.Restock()
  local want = Helpers.Char().restock
  if not next(want) then
    return {}
  end
  local have = {}
  for id in pairs(want) do
    have[id] = B.Compat.GetItemCount(id)
  end
  local buys = Model.Restock(want, have, offers(), B.Compat.GetMoney())
  local spent, names = 0, {}
  for _, b in ipairs(buys) do
    if B.Compat.MerchantBuy(b.index, b.count) then
      spent = spent + b.cost
      names[b.itemID] = (names[b.itemID] or 0) + b.count
    end
  end
  if spent > 0 then
    local parts = {}
    for id, n in pairs(names) do
      parts[#parts + 1] = Helpers.ItemName(id) .. " x" .. n
    end
    table.sort(parts)
    Helpers.Notice(string.format(L["Restocked %s for %s"], table.concat(parts, ", "), B.UI.Money(spent)))
  end
  return buys
end

local function soldWords()
  local words = string.format(L["Sold %d items for %s"], #visit.sold, B.UI.Money(visit.value))
  if visit.unknown > 0 then
    words = words .. " " .. string.format(L["(%d of unknown price)"], visit.unknown)
  end
  return words
end

-- Buys this visit's sales back from the buyback tab.
function Merchant.Undo()
  if not (visit and open) then
    return 0
  end
  local n = 0
  for _, index in ipairs(Model.Undo(visit.sold, B.Compat.GetBuybackItems())) do
    if B.Compat.Buyback(index) then
      n = n + 1
    end
  end
  visit.sold, visit.value, visit.unknown = {}, 0, 0
  Helpers.Notice(string.format(L["Bought back %d items"], n))
  return n
end

-- Sells the junk a batch at a time while the merchant stays open; then `after()`.
function Merchant.SellJunk(after)
  local junk = Model.Junk(B.Compat.GetBagItems(), Helpers.Global().neverSell, Helpers.SellPrice)
  local i = 0
  local function step()
    if not open then
      return
    end
    for _ = 1, Merchant.SELL_BATCH do
      i = i + 1
      local j = junk[i]
      if not j then
        if #visit.sold > 0 then
          Helpers.Notice(soldWords(), { label = L["Undo"], run = Merchant.Undo })
        end
        if after then
          after()
        end
        return
      end
      if B.Compat.SellBagItem(j.bag, j.slot) then
        visit.sold[#visit.sold + 1] = { itemID = j.itemID, count = j.count }
        if j.value then
          visit.value = visit.value + j.value
        else
          visit.unknown = visit.unknown + 1
        end
      end
    end
    C_Timer.After(Merchant.SELL_STEP, step)
  end
  step()
end

function Merchant.OnShow()
  open = true
  visit = { sold = {}, value = 0, unknown = 0 }
  Merchant.visit = visit
  if Helpers.Paused() then
    return
  end
  if Helpers.On("repair") then
    Merchant.Repair()
  end
  local function restock()
    if Helpers.On("restock") then
      Merchant.Restock()
    end
  end
  if Helpers.On("sellJunk") then
    Merchant.SellJunk(restock) -- the sales' money counts for the restock
  else
    restock()
  end
end

-- Alt-click on a merchant item: one full purchase (the most one purchase buys, never more than
-- the money), on the merchant's tab only.
function Merchant.OnModifiedClick(button)
  if not (open and Helpers.On("altStack") and B.Compat.ModifierDown("alt")) then
    return
  end
  local frame = rawget(_G, "MerchantFrame")
  if frame and frame.selectedTab and frame.selectedTab ~= 1 then
    return -- the buyback tab
  end
  local index = button and button.GetID and button:GetID()
  local it = index and B.Compat.GetMerchantItem(index)
  if not (it and it.price and it.price > 0) then
    return
  end
  local max = B.Compat.MerchantMaxStack(index) or it.stack or 1
  local offer = {
    index = index,
    itemID = it.itemID,
    stack = it.stack,
    price = it.price,
    numAvailable = it.numAvailable,
    maxStack = max,
  }
  local buys = Model.Restock({ [it.itemID] = max }, {}, { offer }, B.Compat.GetMoney())
  for _, b in ipairs(buys) do
    B.Compat.MerchantBuy(b.index, b.count)
  end
  return buys
end

function Merchant.Attach(mod)
  mod:RegisterEvent("MERCHANT_SHOW", Merchant.OnShow)
  mod:RegisterEvent("MERCHANT_CLOSED", function()
    open = false
  end)
  if not Merchant.hooked and type(rawget(_G, "MerchantItemButton_OnModifiedClick")) == "function" then
    Merchant.hooked = true
    hooksecurefunc("MerchantItemButton_OnModifiedClick", function(button)
      Merchant.OnModifiedClick(button)
    end)
  end
end
