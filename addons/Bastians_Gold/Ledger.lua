-- The ledger: what the auction house's invoices say the
-- character bought and sold, per item, in BastiansGoldDB.global.ledger per realm and faction. Read
-- at the mailbox through Compat.GetInboxInvoices; the other player's name is never kept (CLAUDE.md
-- section 8). A mail stays until it is taken, so each invoice is counted once by its key.
local _, ns = ...
local B = Bastians
local S = B.UI.Style
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Ledger = {}
ns.Ledger = Ledger

Ledger.KEEP_SEEN = 35 * 86400 -- a mail lives 30 days; a key older than that cannot come back
Ledger.DELAY = 0.2

local mod

local function book(key)
  local g = mod and mod.db.global
  if not g then
    return nil
  end
  if type(g.ledger) ~= "table" then
    g.ledger = {}
  end
  local k = key or ns.History.Key()
  if type(g.ledger[k]) ~= "table" then
    g.ledger[k] = { items = {}, seen = {} }
  end
  return g.ledger[k]
end

-- Pure: an invoice's key, stable while the mail waits: its expiry to the hour, and which of the
-- same invoices of this look it is (`nth`: five stacks sold alike are five sales).
function Ledger.Key(inv, now, nth)
  local expires = math.floor((now + (inv.daysLeft or 0) * 86400) / 3600)
  return table.concat({ inv.kind, inv.item, inv.bid or 0, inv.count or 1, expires, nth or 1 }, "|")
end

-- Pure: books one invoice into `b` { items, seen }; false when the key is known or it brings nothing.
function Ledger.Add(b, inv, key, now)
  if b.seen[key] or not inv.item or not inv.bid then
    return false
  end
  local count = inv.count or 1
  local row = b.items[inv.item]
  if not row then
    row = { bought = 0, spent = 0, sold = 0, earned = 0 }
    b.items[inv.item] = row
  end
  if inv.kind == "buyer" then
    row.bought, row.spent = row.bought + count, row.spent + inv.bid
  elseif inv.kind == "seller" then
    row.sold, row.earned = row.sold + count, row.earned + inv.bid - (inv.consignment or 0)
  else
    return false -- seller_temp_invoice: the money comes later with the real invoice
  end
  b.seen[key] = now
  return true
end

-- Pure: a row's figures: avgBuy and avgSell per unit (nil without one), the profit of what was
-- sold against what such units cost (nil while no purchase is known: bought nothing is no cost 0).
function Ledger.Figures(row)
  if not row then
    return nil
  end
  local avgBuy = row.bought > 0 and row.spent / row.bought or nil
  local avgSell = row.sold > 0 and row.earned / row.sold or nil
  local profit = avgBuy and row.sold > 0 and row.earned - avgBuy * row.sold or nil
  return { avgBuy = avgBuy, avgSell = avgSell, profit = profit, sold = row.sold, bought = row.bought }
end

-- Reads the inbox's invoices into the ledger; how many were new.
function Ledger.Scan(now)
  local b = book()
  if not b then
    return 0
  end
  local time = now or GetServerTime()
  local added, same = 0, {}
  for _, inv in ipairs(B.Compat.GetInboxInvoices()) do
    local base = Ledger.Key(inv, time, 0)
    same[base] = (same[base] or 0) + 1
    if Ledger.Add(b, inv, Ledger.Key(inv, time, same[base]), time) then
      added = added + 1
    end
  end
  for key, ts in pairs(b.seen) do
    if time - ts > Ledger.KEEP_SEEN then
      b.seen[key] = nil
    end
  end
  return added
end

-- What the character paid for one unit on average, or nil when it bought none.
function Ledger.AvgBuy(name)
  local b = book()
  local f = b and name and Ledger.Figures(b.items[name])
  return f and f.avgBuy or nil
end

-- The rows of the book, the best profit first, those without one after them: { name, figures }.
function Ledger.Items()
  local b = book()
  local out = {}
  for name, row in pairs(b and b.items or {}) do
    out[#out + 1] = { name = name, figures = Ledger.Figures(row) }
  end
  table.sort(out, function(x, y)
    local px, py = x.figures.profit, y.figures.profit
    if (px ~= nil) ~= (py ~= nil) then
      return px ~= nil
    end
    if px and px ~= py then
      return px > py
    end
    return x.name < y.name
  end)
  return out
end

-- Earned and spent over the whole book.
function Ledger.Totals()
  local b = book()
  local earned, spent = 0, 0
  for _, row in pairs(b and b.items or {}) do
    earned, spent = earned + row.earned, spent + row.spent
  end
  return earned, spent
end

-- The Price section's rows of an item: what was paid and earned, the floor a purchase sets.
function Ledger.Rows(name)
  local b = book()
  local f = b and name and Ledger.Figures(b.items[name])
  if not f then
    return {}
  end
  local rows = {}
  if f.avgBuy then
    rows[#rows + 1] =
      { text = L["You paid on average"], value = math.floor(f.avgBuy + 0.5), valueKind = "money" }
    rows[#rows + 1] = {
      text = L["Post at least, to cover that"],
      value = ns.Pricing.Floor(f.avgBuy),
      valueKind = "money",
    }
  end
  if f.avgSell then
    rows[#rows + 1] =
      { text = L["You sold at on average"], value = math.floor(f.avgSell + 0.5), valueKind = "money" }
  end
  if f.profit then
    rows[#rows + 1] =
      { text = L["Your profit on it"], value = math.floor(f.profit + 0.5), valueKind = "money" }
  end
  return rows
end

function Ledger.Tree()
  local items = Ledger.Items()
  local roots = {}
  if #items == 0 then
    local text = L["No sales or purchases yet: the ledger reads the auction house's mail."]
    roots[1] = { text = S.H.muted .. text .. "|r", kind = "para" }
  end
  for i, it in ipairs(items) do
    local f = it.figures
    local words = string.format(L["sold %d, bought %d"], f.sold, f.bought)
    roots[#roots + 1] = {
      id = "ledger:" .. i,
      text = it.name .. "  " .. S.H.muted .. words .. "|r",
      value = f.profit and math.floor(f.profit + 0.5) or nil,
      valueKind = f.profit and "money" or nil,
    }
  end
  local earned, spent = Ledger.Totals()
  local line = string.format(L["Earned %s, spent %s"], B.UI.Money(earned), B.UI.Money(spent))
  return roots, line
end

function Ledger.Register(self)
  mod = self
  self:RegisterEvent("MAIL_INBOX_UPDATE", function()
    self:Coalesce("ledger", Ledger.DELAY, Ledger.Scan)
  end)
end
