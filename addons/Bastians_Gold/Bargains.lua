-- Bargains: every item whose lowest
-- listing lies far under its 30-day median (Pricing.Bargain), the biggest saving first. The owner
-- on the Price section's bargain line: "HOW am I supposed to find one?". Built in a job over the
-- items the data knows; unknown is not zero: an item without both prices is no bargain and no row.
local _, ns = ...
local B = Bastians
local L = ns.L
local S = B.UI.Style

local Bargains = {}
ns.Bargains = Bargains

Bargains.VIEW = "gold.bargains"
local STEP = 200 -- items per slice of the job

local mod

-- One item's row, or nil when it is no bargain. `p` is the prices service's record.
function Bargains.Row(itemID, p)
  if not ns.Pricing.Bargain(p) then
    return nil
  end
  local e = B:Entity("item:" .. itemID)
  local name = e:Name() or ("item:" .. itemID)
  local meta =
    string.format(L["lowest %s, usually %s (30 days)"], B.UI.Money(p.minBuyout), B.UI.Money(p.median30d))
  local saving = p.median30d - p.minBuyout
  return {
    ref = "item:" .. itemID,
    title = name,
    icon = e:Icon(),
    meta = meta,
    text = name .. "  " .. S.H.muted .. meta .. "|r",
    value = saving,
    valueKind = "money",
    saving = saving,
  }
end

-- The bargains of `ids` with `priceOf(id)` -> record. Pure but for the entity names. -> rows.
function Bargains.Rows(ids, priceOf)
  local rows = {}
  for _, id in ipairs(ids) do
    local row = Bargains.Row(id, priceOf(id))
    if row then
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, function(a, b)
    if a.saving ~= b.saving then
      return a.saving > b.saving
    end
    return a.title < b.title
  end)
  return rows
end

local function summaryOf(rows)
  if #rows == 0 then
    return L["No item is far under its 30-day median now."]
  end
  return string.format(L["%d bargains on the auction house"], #rows)
end

local function render(host)
  host:SetControls({})
  local d = B:GetService("data")
  local service = B:GetService("prices")
  if not (d and service) then
    host:SetRows({})
    host:SetSummary(L["Bargains need Bastian's Data and its market data."])
    return
  end
  local status = service:Status()
  if not (status and status.pack) then
    host:SetRows({})
    host:SetSummary(L["Bargains need the 30-day medians of the Data pack's market."])
    return
  end
  local job = Bargains.job
  if job and not (job:IsDone() or job:IsCancelled()) then
    host:SetSummary(L["Building the list ..."])
    return
  end
  host:SetSummary(L["Building the list ..."])
  local found = {}
  Bargains.job = host:Job("gold-bargains", function(yield)
    local n = 0
    for _, id in ipairs(d:Each("item") or {}) do
      n = n + 1
      if yield and n % STEP == 0 then
        yield()
      end
      local row = Bargains.Row(id, service:Price(id))
      if row then
        found[#found + 1] = row
      end
    end
  end, function()
    table.sort(found, function(a, b)
      if a.saving ~= b.saving then
        return a.saving > b.saving
      end
      return a.title < b.title
    end)
    host:SetRows(found)
    host:SetSummary(summaryOf(found))
  end)
end

function Bargains.Open()
  return B:ShowView(Bargains.VIEW)
end

function Bargains.Register(module)
  mod = module
  B:RegisterView(mod, {
    id = Bargains.VIEW,
    title = L["Bargains"],
    group = L["Gold"],
    rail = "gold", -- the Atlas's rail entry (ADR 0058)
    order = 44,
    render = render,
    summary = function()
      return L["items far under their usual price"]
    end,
    invalidateOn = { "BASTIANS_PRICES_UPDATED", "BASTIANS_DATA_LOADED" },
  })
end
