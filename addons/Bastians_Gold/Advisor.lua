-- The bag advisor (gold.md "Bag advisor", S4, 22.10.2026): per bag item post, vendor or keep, with
-- the reason. The verdict is pure (Advisor.Advise over plain tables); the bags come through
-- Compat.GetBagItems, the prices through the `prices` service and Sections.SellPrice. Unknown is
-- said, never 0: an item without any price is kept with "price unknown".
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Advisor = {}
ns.Advisor = Advisor

Advisor.AH_CUT = 0.05 -- the auction house keeps this share of a sale (both clients)
Advisor.MARGIN = 1.25 -- the AH net must beat the vendor by a quarter to be worth the posting
Advisor.SLOW_SALES = 0.5 -- sales per day below which a posting is unlikely to sell
Advisor.VERDICTS = { "post", "vendor", "keep" }

local mod
local openedByShop = false -- the window was opened by a merchant or the AH, so it closes with it

local function prices()
  return B:GetService("prices")
end

-- One item: { itemID, count, quality (0 = poor), bound, noValue, sell (copper per unit or nil),
-- cost (what the ledger says one unit cost, or nil), price = { median, minBuyout, salesPerDay,
-- stale } or nil } -> { verdict, reason, unit, total }.
-- `unit` is the copper one unit is expected to bring on the advised way, nil when nothing is known.
function Advisor.Advise(item, opts)
  local cut = opts and opts.cut or Advisor.AH_CUT
  local margin = opts and opts.margin or Advisor.MARGIN
  local slow = opts and opts.slowSales or Advisor.SLOW_SALES
  local count = item.count or 1
  local sell = item.sell and item.sell > 0 and item.sell or nil
  local p = item.price
  local median = p and p.median and p.median > 0 and p.median or nil
  local net = median and math.floor(median * (1 - cut) + 0.5) or nil
  local function out(verdict, reason, unit)
    return { verdict = verdict, reason = reason, unit = unit, total = unit and unit * count or nil }
  end
  if item.quality == 0 then
    if sell then
      return out("vendor", string.format(L["grey, the vendor pays %s"], B.UI.Money(sell)), sell)
    end
    return out("keep", L["grey, no vendor price known"], nil)
  end
  if item.bound then
    if sell then
      return out("keep", string.format(L["soulbound (a vendor would pay %s)"], B.UI.Money(sell)), nil)
    end
    return out("keep", L["soulbound"], nil)
  end
  if not net then
    if sell then
      return out("keep", string.format(L["AH price unknown, the vendor pays %s"], B.UI.Money(sell)), nil)
    end
    if item.noValue then
      return out("keep", L["cannot be sold"], nil)
    end
    return out("keep", L["price unknown"], nil)
  end
  local stale = p.stale and (" " .. L["(stale scan)"]) or ""
  local slowSales = p.salesPerDay ~= nil and p.salesPerDay < slow
  if sell and net <= math.floor(sell * margin + 0.5) then
    if net <= sell then
      local words =
        string.format(L["AH %s after the cut, below the vendor's %s"], B.UI.Money(net), B.UI.Money(sell))
      return out("vendor", words .. stale, sell)
    end
    return out(
      "vendor",
      string.format(L["AH %s after the cut, barely above the vendor's %s"], B.UI.Money(net), B.UI.Money(sell))
        .. stale,
      sell
    )
  end
  if item.cost and net < item.cost then
    local words = L["you paid %s, the AH pays %s after the cut"]
    return out("keep", string.format(words, B.UI.Money(item.cost), B.UI.Money(net)) .. stale, nil)
  end
  if ns.Pricing.Dumped(p) and not p.stale then
    local words = L["the lowest listing %s is far under the median %s: wait"]
    return out("keep", string.format(words, B.UI.Money(p.minBuyout), B.UI.Money(median)), nil)
  end
  if slowSales and sell then
    return out(
      "vendor",
      string.format(L["sells %.1f a day on the AH; the vendor pays %s now"], p.salesPerDay, B.UI.Money(sell))
        .. stale,
      sell
    )
  end
  local reason
  if sell then
    reason = string.format(L["AH %s after the cut, the vendor pays %s"], B.UI.Money(net), B.UI.Money(sell))
  else
    reason = string.format(L["AH %s after the cut, no vendor value"], B.UI.Money(net))
  end
  if slowSales then
    reason = reason .. string.format(L[", slow (%.1f a day)"], p.salesPerDay)
  end
  return out("post", reason .. stale, net)
end

-- One answer per bag item (ADR 0058, PH6; catalog review A5.4): sell, auction, disenchant, mail,
-- keep, with the reason. Pure: `ctx` = { wanted = { name, count } (another character of yours
-- asked for it: Alts' requests), neverSell = true (Helpers' list), disenchant = copper per unit
-- (the materials' value with every one priced, else nil) }. Built on Advise: its post is auction,
-- its vendor sell, its keep keeps; disenchanting wins when it beats the way Advise found; a
-- character who asked wins over everything. Unknown stays unknown: no price, no figure.
Advisor.ANSWERS = { "mail", "sell", "auction", "disenchant", "keep" }

function Advisor.Answer(item, ctx, opts)
  ctx = ctx or {}
  local count = item.count or 1
  if ctx.wanted and ctx.wanted.name then
    local n = math.min(count, ctx.wanted.count or count)
    return {
      answer = "mail",
      to = ctx.wanted.name,
      reason = string.format(L["%s asked for %d of these"], ctx.wanted.name, n),
      unit = nil,
      total = nil,
    }
  end
  if item.quality == 0 and ctx.neverSell then
    return { answer = "keep", reason = L["on your never-sell list"], unit = nil, total = nil }
  end
  local a = Advisor.Advise(item, opts)
  local de = ctx.disenchant and ctx.disenchant > 0 and ctx.disenchant or nil
  if de and not item.bound and (a.unit == nil or de > a.unit) and item.quality ~= 0 then
    local words = item.sell and L["disenchanting brings %s, the vendor pays %s"]
      or L["disenchanting brings %s"]
    return {
      answer = "disenchant",
      reason = string.format(words, B.UI.Money(de), B.UI.Money(item.sell or 0)),
      unit = de,
      total = de * count,
    }
  end
  local answer = a.verdict == "post" and "auction" or a.verdict == "vendor" and "sell" or "keep"
  return { answer = answer, reason = a.reason, unit = a.unit, total = a.total }
end

-- The answers of the bags: every slot with its answer, in bag order; what Alts and Helpers know
-- comes through Core's services (every app works alone: without them no mail, no never-sell).
function Advisor.Answers()
  local requests = B:GetService("requests")
  local neverSell = B:GetService("neversell")
  local out = {}
  for _, item in ipairs(Advisor.BagItems()) do
    local wanted = requests and requests:For(item.itemID) or nil
    local ctx = {
      wanted = wanted and wanted[1] or nil,
      neverSell = neverSell and neverSell:Is(item.itemID) or nil,
      disenchant = ns.Sections.DisenchantValue(item.itemID),
    }
    local a = Advisor.Answer(item, ctx)
    a.item = item
    out[#out + 1] = a
  end
  return out
end

-- The verdicts of a bag, grouped: { post = { items, total }, vendor = { items, total }, keep = {
-- items, total = nil } }, each group's items sorted by total (unknown last) then name.
function Advisor.Build(items, opts)
  local groups = {}
  for _, v in ipairs(Advisor.VERDICTS) do
    groups[v] = { items = {}, total = 0, known = false }
  end
  for _, item in ipairs(items) do
    local a = Advisor.Advise(item, opts)
    a.item = item
    local g = groups[a.verdict]
    g.items[#g.items + 1] = a
    if a.total then
      g.total = g.total + a.total
      g.known = true
    end
  end
  for _, g in pairs(groups) do
    table.sort(g.items, function(a, b)
      if (a.total or -1) ~= (b.total or -1) then
        return (a.total or -1) > (b.total or -1)
      end
      return (a.item.name or "") < (b.item.name or "")
    end)
    if not g.known then
      g.total = nil
    end
  end
  return groups
end

-- The bags as advisor items: the client's slots, each with its name, sell price and AH price.
function Advisor.BagItems()
  local service = prices()
  local out = {}
  for _, slot in ipairs(B.Compat.GetBagItems()) do
    local info = B.Compat.GetItemInfo(slot.itemID)
    local name = B:Entity("item:" .. slot.itemID):Name() or (info and info.name)
    out[#out + 1] = {
      itemID = slot.itemID,
      bag = slot.bag,
      slot = slot.slot,
      count = slot.count,
      quality = slot.quality or (info and info.quality),
      bound = slot.bound,
      noValue = slot.noValue,
      name = name or (L["Item"] .. " " .. slot.itemID),
      cost = ns.Ledger.AvgBuy(name),
      icon = (info and info.icon) or slot.icon,
      sell = ns.Sections.SellPrice(slot.itemID),
      price = service and service:Price(slot.itemID) or nil,
    }
  end
  return out
end

-- A merchant or the auction house opened (true) or closed (false): with the setting on, the
-- window opens on the Bags tab and closes again with the shop, unless the player had it open.
function Advisor.OnShop(open)
  if not mod then
    return
  end
  if open then
    if mod.db.profile.advisorAuto ~= false and not ns.Window.IsShown() then
      if ns.Window.Open("bags") then
        openedByShop = true
      end
    end
  elseif openedByShop then
    openedByShop = false
    ns.Window.Hide()
  end
end

function Advisor.OpenedByShop()
  return openedByShop
end

-- The window was hidden (by hand or by us): the shop's close has nothing left to close.
function Advisor.WindowHidden()
  openedByShop = false
end

function Advisor.Register(self)
  mod = self
  openedByShop = false
  self:RegisterEvent("MERCHANT_CLOSED", function()
    Advisor.OnShop(false)
  end)
  self:RegisterEvent("BAG_UPDATE_DELAYED", function()
    ns.Window.ScheduleIf("bags")
  end)
end
