-- The `prices` service (gold.md "Prices service", core-contracts §11): the own latest scan when it is
-- fresh, else the Market pack, else the stale scan flagged as such, else nil. Every answer carries its
-- source and age; unknown stays nil. Market detection from realm name and faction through the table
-- below, never from GetCurrentRegion() alone (110 on the beta).
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L

local Prices = {}
ns.Prices = Prices

Prices.DEFAULT_MAX_AGE_HOURS = 24
local PARSE_CHUNK = 2000 -- raw records per job slice

-- Realm name -> ruleset and region, as AHledger names its markets
-- (`forever/{normal,pvp,rp}/{alliance,horde}/{us,eu,cn}`). Launch realm names are unknown on
-- 19.10.2026; add them here on launch night. An unknown realm gets "normal" and the region guess.
Prices.REALMS = {
  ["Classic Beta PvE"] = { ruleset = "normal", region = "us" },
  ["Classic Beta PvP"] = { ruleset = "pvp", region = "us" },
}
local REGIONS = { "us", "kr", "eu", "tw", "cn" }

local mod -- the Gold module
local market -- { id, game, ruleset, faction, region, realm, known }
local scan -- { ts, realm, faction, items = { [itemID] = { median, minBuyout, quantity } }, count }
local building -- the job that parses the newest raw scan

-- ---------------------------------------------------------------------------------------------
-- Market
-- ---------------------------------------------------------------------------------------------

local function regionGuess()
  local r = GetCurrentRegion()
  return REGIONS[r] -- nil for 110 and other surprises
end

function Prices.DetectMarket()
  local realm = GetRealmName() or "unknown"
  local faction = string.lower(UnitFactionGroup("player") or "neutral")
  local known = Prices.REALMS[realm]
  local m
  if B.Client == "retail" then
    m = { game = "retail", ruleset = "normal", faction = "neutral", region = regionGuess() or "unknown" }
  else
    m = {
      game = "forever",
      ruleset = known and known.ruleset or "normal",
      faction = faction,
      region = known and known.region or regionGuess() or "unknown",
    }
  end
  m.realm = realm
  m.charFaction = faction -- the scans are per character faction even where the market is neutral
  m.known = known ~= nil or B.Client == "retail"
  m.id = table.concat({ m.game, m.ruleset, m.faction, m.region }, "/")
  market = m
  return m
end

-- ---------------------------------------------------------------------------------------------
-- The own scan: per-item unit prices from the newest raw dump of this market
-- ---------------------------------------------------------------------------------------------

local function newestRaw()
  local scans = type(BastiansGoldRaw) == "table" and BastiansGoldRaw.scans or nil
  if not scans or not market then
    return nil
  end
  local best
  for _, s in ipairs(scans) do
    if s.realm == market.realm and string.lower(s.faction or "") == market.charFaction then
      if not best or (s.ts or 0) > (best.ts or 0) then
        best = s
      end
    end
  end
  return best
end

local function median(list)
  table.sort(list)
  local n = #list
  if n == 0 then
    return nil
  end
  if n % 2 == 1 then
    return list[(n + 1) / 2]
  end
  return math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

-- Parses the dump's `data` (";" records, ":" fields: itemID, count, buyout, ...) into unit prices.
-- Runs as a job; `onDone(summary)` gets { ts, items, count }.
function Prices.Rebuild(source, onDone)
  local rawScan = newestRaw()
  if not rawScan then
    scan = nil
    if onDone then
      onDone(nil)
    end
    if source then
      B:Fire("BASTIANS_PRICES_UPDATED", source)
    end
    return
  end
  if building then
    building:Cancel()
  end
  local units = {} -- itemID -> { unit prices }
  local quantity = {}
  local data = rawScan.data or ""
  building = B.Jobs:Run(mod, "price-summary", function(yield)
    local n = 0
    for rec in string.gmatch(data, "[^;]+") do
      local itemID, count, buyout = string.match(rec, "^(%-?%d+):(%d*):(%d*)")
      itemID, count, buyout = tonumber(itemID), tonumber(count), tonumber(buyout)
      if itemID and count and count > 0 and buyout and buyout > 0 then
        local list = units[itemID]
        if not list then
          list = {}
          units[itemID] = list
        end
        list[#list + 1] = math.floor(buyout / count + 0.5)
        quantity[itemID] = (quantity[itemID] or 0) + count
      end
      n = n + 1
      if n % PARSE_CHUNK == 0 then
        yield()
      end
    end
  end, {
    budgetMs = 6,
    onDone = function()
      building = nil
      local items, count = {}, 0
      for itemID, list in pairs(units) do
        local minBuyout = list[1]
        for i = 2, #list do
          if list[i] < minBuyout then
            minBuyout = list[i]
          end
        end
        items[itemID] = { median = median(list), minBuyout = minBuyout, quantity = quantity[itemID] }
        count = count + 1
      end
      scan =
        { ts = rawScan.ts, realm = rawScan.realm, faction = rawScan.faction, items = items, count = count }
      if onDone then
        onDone(scan)
      end
      if source then
        B:Fire("BASTIANS_PRICES_UPDATED", source)
      end
    end,
  })
end

-- ---------------------------------------------------------------------------------------------
-- The Market pack
-- ---------------------------------------------------------------------------------------------

local function data()
  return B:GetService("data")
end

local function marketInfo()
  local d = data()
  if not (d and market and d:PackLoaded("market")) then
    return nil
  end
  return d:Index("market.list", market.id)
end

-- The market whose records the pack holds for the player's: its own, or the one a fill points
-- at (`alias`: an EU market before launch reads the US beta's rows, data.md "Market pack").
local function packMarket()
  local info = marketInfo()
  return info and info.alias or (market and market.id)
end
Prices.PackMarket = packMarket

local function packPrice(itemID)
  local d = data()
  if not (d and market and d:PackLoaded("market")) then
    return nil
  end
  return d:Get("price", packMarket() .. ":" .. itemID)
end

-- ---------------------------------------------------------------------------------------------
-- The service
-- ---------------------------------------------------------------------------------------------

local function maxAge()
  local hours = mod and mod.db.profile.scanMaxAgeHours or Prices.DEFAULT_MAX_AGE_HOURS
  return hours * 3600
end

local service = {}
Prices.service = service

function service:Market()
  return market
end

-- { median, minBuyout, quantity, salesPerDay, age (seconds), source = "scan" | "market", label,
--   stale = true when an old scan is all there is } or nil when nothing is known.
function service:Price(itemID)
  if not itemID then
    return nil
  end
  local now = GetServerTime()
  local own = scan and scan.items[itemID] or nil
  local ownAge = scan and (now - (scan.ts or 0)) or nil
  if own and ownAge <= maxAge() then
    return {
      median = own.median,
      minBuyout = own.minBuyout,
      quantity = own.quantity,
      salesPerDay = nil, -- one scan cannot tell
      age = ownAge,
      source = "scan",
    }
  end
  local p = packPrice(itemID)
  if p then
    local info = marketInfo()
    return {
      median = p.median,
      minBuyout = p.minBuyout,
      quantity = p.quantity,
      salesPerDay = p.salesPerDay,
      median7d = p.median7d,
      median30d = p.median30d,
      low30d = p.low30d,
      high30d = p.high30d,
      age = p.scanTs and (now - p.scanTs) or nil,
      source = "market",
      label = (info and info.alias and info.label) or p.src or (info and info.label) or nil,
    }
  end
  if own then
    return {
      median = own.median,
      minBuyout = own.minBuyout,
      quantity = own.quantity,
      age = ownAge,
      source = "scan",
      stale = true,
    }
  end
  return nil
end

-- What the service has: { market, scan = { ts, items } or nil, pack = { ts, items, label } or nil }.
function service:Status()
  local info = marketInfo()
  return {
    market = market,
    scan = scan and { ts = scan.ts, items = scan.count } or nil,
    pack = info and { ts = info.scanTs, items = info.items, label = info.label } or nil,
  }
end

-- A one-line note for the settings page.
function Prices.Note()
  local s = service:Status()
  local parts = {}
  if s.market then
    parts[#parts + 1] = string.format(
      L["Market %s (%s)"],
      s.market.id,
      s.market.known and L["known realm"] or L["realm not in the table"]
    )
  end
  if s.scan then
    parts[#parts + 1] = string.format(
      L["own scan: %d items, %d min old"],
      s.scan.items,
      math.floor((GetServerTime() - (s.scan.ts or 0)) / 60)
    )
  else
    parts[#parts + 1] = L["no own scan yet"]
  end
  if s.pack then
    parts[#parts + 1] = string.format(L["market pack: %d items (%s)"], s.pack.items or 0, s.pack.label or "?")
  else
    parts[#parts + 1] = L["no market data yet"]
  end
  return table.concat(parts, "; ")
end

function Prices.Register(m)
  mod = m
  Prices.DetectMarket()
  B:ProvideService(m, "prices", service, { priority = 100 })
  m:On("BASTIANS_DATA_LOADED", function(_, _, pack)
    if pack == "market" then
      B:Fire("BASTIANS_PRICES_UPDATED", "market")
    end
  end)
  Prices.Rebuild(nil) -- the newest saved scan, so prices answer right after login
end

function Prices.Scan()
  return scan
end
