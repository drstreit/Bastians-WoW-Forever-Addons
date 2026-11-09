-- The prices other addons hold for the player's own market:
-- read at runtime when the player has them, nothing of theirs is copied into our data. AHledger's
-- API first (its table of this very market), then the player's Auctionator scans, then TSM's.
local _, ns = ...
local B = Bastians

local Bridges = {}
ns.Bridges = Bridges

Bridges.CALLER = "Bastian's Gold" -- what Auctionator's API wants to know

local function ahledger(itemID)
  local api = rawget(_G, "AHledgerAPI")
  local p = api and api.GetPrice and api.GetPrice(itemID)
  if not (p and p.median) then
    return nil
  end
  return {
    median = p.median,
    minBuyout = p.minBuyout,
    salesPerDay = p.soldPerDay,
    label = "AHledger (ahledger.com)", -- AHledgerAPI.CREDIT's terms: the credit where prices show
  }
end

local function auctionator(itemID)
  local a = rawget(_G, "Auctionator")
  local api = a and a.API and a.API.v1
  local price = api and api.GetAuctionPriceByItemID and api.GetAuctionPriceByItemID(Bridges.CALLER, itemID)
  if not price then
    return nil
  end
  local days = api.GetAuctionAgeByItemID and api.GetAuctionAgeByItemID(Bridges.CALLER, itemID)
  return { median = price, minBuyout = price, age = days and days * 86400 or nil, label = "Auctionator" }
end

local function tsm(itemID)
  local api = rawget(_G, "TSM_API")
  local price = api and api.GetCustomPriceValue and api.GetCustomPriceValue("dbmarket", "i:" .. itemID)
  if not price then
    return nil
  end
  return { median = price, label = "TradeSkillMaster" }
end

Bridges.READERS = { ahledger, auctionator, tsm }

-- The first addon that knows the item, as a price of source "addon", or nil. A foreign addon is a
-- module boundary: its error stays out of ours and that addon is skipped.
function Bridges.Price(itemID)
  for _, read in ipairs(Bridges.READERS) do
    local ok, p = pcall(read, itemID)
    if ok and p then
      p.source = "addon"
      return p
    end
    if not ok then
      B:Log("Gold", "warn", "price bridge failed: %s", tostring(p))
    end
  end
  return nil
end
