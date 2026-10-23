-- Capture (gold.md "Capture", port of AHSyncCapture 0.5.2): the full auction listing as a lossless
-- raw dump (format 1, docs/data/savedvariables.md), merchant offers, trainer services and vendor sell
-- prices. Reads, never acts: nothing is bought, posted or sent. It listens to
-- REPLICATE_ITEM_LIST_UPDATE whoever asked for the listing; its own request respects the 15-minute
-- window, counted from every addon's ReplicateItems call (hooked) and starting with the request.
local _, ns = ...
local B = Bastians
ns.L = ns.L or B.NewLocale()
local L = ns.L
local Compat = B.Compat

local Capture = {}
ns.Capture = Capture

Capture.VERSION = "0.1.0"
Capture.FORMAT = 1 -- BastiansGoldDB.global.capture
Capture.RAW_FORMAT = 1 -- BastiansGoldRaw
-- Column order of a raw record, ":" separated; written into the dump as `fields`.
Capture.FIELDS = "itemID,count,buyout,bid,minBid,minIncrement,level,levelType,quality,usable,"
  .. "saleStatus,hasAllInfo,timeLeft,texture,name,highBidder,bidderFullName,owner,ownerFullName,link"

local PACK_CHUNK = 250 -- listings per job slice
local RETRY_DELAY = 2.0 -- seconds before listings without item data are read once more
local RETRY_LOAD_MAX = 3000 -- item-data requests sent for those listings
local TRACE_BURST_S = 30 -- the same event is logged at most this often (it comes in thousands)
local DEDUPE_S = 120 -- a second list event this soon is the same listing
local DEFAULT_KEEP = 8 -- scan summaries kept per realm and faction
local DEFAULT_KEEP_RAW = 3 -- raw dumps kept per realm and faction (about 2 MB each)
local LOG_MAX = 40 -- lines of the diagnostic log kept in the saved file
local SAMPLE_EVERY = 4000 -- every Nth listing is also saved readable
local WINDOW_S = 15 * 60 -- the server ignores a second full-listing request for this long
local MERCHANT_DELAY = 0.5 -- seconds after the merchant window opens before the offers are read
local TRAINER_DELAY = 0.5
local TRAINER_RETRIES = 2
local TRAINER_TYPES = { "available", "unavailable", "used" }
Capture.DEFAULT_KEEP, Capture.DEFAULT_KEEP_RAW = DEFAULT_KEEP, DEFAULT_KEEP_RAW

local mod -- the Gold module, set by Capture.Register
local db -- BastiansGoldDB.global.capture
local rawDb -- BastiansGoldRaw
local capture -- the running scan or nil
local requested = false -- we asked the server ourselves
local lastCaptureAt = -1e9

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local function nowEpoch()
  return GetServerTime()
end

-- The saved file carries a short log, so a problem can be diagnosed from the file alone.
local function trace(msg)
  if not db then
    return
  end
  db.log = db.log or {}
  local stamp = type(date) == "function" and date("!%H:%M:%S", nowEpoch()) or "?"
  db.log[#db.log + 1] = stamp .. " " .. msg
  while #db.log > LOG_MAX do
    table.remove(db.log, 1)
  end
end

local function say(msg)
  trace(msg)
  B:Say("%s", msg)
end

-- One field of a raw record: numbers as they came, booleans as 1/0, nothing as empty.
-- %.0f, not %d: the client's %d is a 32-bit integer and one absurd price would throw.
local function field(x)
  local t = type(x)
  if t == "number" then
    return string.format("%.0f", x)
  end
  if t == "boolean" then
    return x and "1" or "0"
  end
  return ""
end

local function windowLeft()
  local last = db and tonumber(db.lastRequestAt)
  if not last then
    return 0
  end
  return math.max(0, last + WINDOW_S - nowEpoch())
end

local function minutes(seconds)
  return math.ceil(seconds / 60)
end

-- Every call of C_AuctionHouse.ReplicateItems, by any addon, is noted and persisted (hooked below).
function Capture.NoteRequest()
  if not db then
    return
  end
  db.lastRequestAt = nowEpoch()
  db.pending = true
  db.requestCount = (db.requestCount or 0) + 1
  db.requestLog = db.requestLog or {}
  db.requestLog[#db.requestLog + 1] = db.lastRequestAt .. (requested and " this addon" or " another addon")
  while #db.requestLog > 12 do
    table.remove(db.requestLog, 1)
  end
  trace(requested and "replicate requested by this addon" or "replicate requested by another addon")
end

if Compat.Has.ReplicateAH and type(hooksecurefunc) == "function" then
  hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
    Capture.NoteRequest()
  end)
end

local REGIONS = { "us", "kr", "eu", "tw", "cn" }

local function regionName()
  local r = GetCurrentRegion()
  return REGIONS[r] or tostring(r) -- never mapped for decisions (110 on the beta), only recorded
end

local function clientInfo()
  local version, build = GetBuildInfo()
  return {
    realm = GetRealmName() or "unknown",
    faction = UnitFactionGroup("player") or "unknown",
    region = regionName(),
    build = string.format("%s (%s)", tostring(version), tostring(build)),
  }
end

local function ahOpen()
  if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then
    return true
  end
  if AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() then
    return true
  end
  return false
end

-- Text is stored once per scan. Index 0 means "no value".
local function intern(c, text)
  if text == nil or text == "" then
    return 0
  end
  local i = c.stringIdx[text]
  if not i then
    i = #c.strings + 1
    c.strings[i] = text
    c.stringIdx[text] = i
  end
  return i
end

-- Only the item part of a link: the colour codes and the display name are noise.
local function linkCore(link)
  if type(link) ~= "string" then
    return nil
  end
  return string.match(link, "item:[%-%d:]*") or link
end

local lastTrace = {}
local function traceBurst(key, msg)
  local now = GetTime()
  if now - (lastTrace[key] or -1e9) < TRACE_BURST_S then
    return
  end
  lastTrace[key] = now
  trace(msg)
end

local function bump(t, key)
  t[key] = (t[key] or 0) + 1
end

-- ---------------------------------------------------------------------------------------------
-- The scan: reading listings into raw records
-- ---------------------------------------------------------------------------------------------

-- GetReplicateItemInfo returns 18 values: 1 name, 2 texture, 3 count, 4 quality, 5 usable, 6 level,
-- 7 levelType, 8 minBid, 9 minIncrement, 10 buyout, 11 bid, 12 highBidder, 13 bidderFullName,
-- 14 owner, 15 ownerFullName, 16 saleStatus, 17 itemID, 18 hasAllInfo. Prices are stack totals.
local function readRecord(c, index)
  local r = { C_AuctionHouse.GetReplicateItemInfo(index) }
  local name, texture, count, quality, usable, level, levelType = r[1], r[2], r[3], r[4], r[5], r[6], r[7]
  local minBid, minIncrement, buyout, bid, highBidder, bidderFull = r[8], r[9], r[10], r[11], r[12], r[13]
  local owner, ownerFull, sale, itemID, hasAll = r[14], r[15], r[16], r[17], r[18]
  if not itemID or itemID <= 0 or not count or count <= 0 then
    return nil
  end
  local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft(index)
  local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(index)
  local who = ownerFull
  if not who or who == "" then
    who = owner
  end
  if who == "" then
    who = nil
  end
  local state = (who ~= nil) and "name" or ((owner == nil and ownerFull == nil) and "nil" or "empty")
  local rec = table.concat({
    field(itemID),
    field(count),
    field(buyout),
    field(bid),
    field(minBid),
    field(minIncrement),
    field(level),
    intern(c, levelType ~= nil and tostring(levelType) or nil),
    field(quality),
    field(usable),
    field(sale),
    field(hasAll),
    field(timeLeft),
    field(texture),
    intern(c, name),
    intern(c, highBidder),
    intern(c, bidderFull),
    intern(c, owner),
    intern(c, ownerFull),
    intern(c, linkCore(link)),
  }, ":")
  return rec, who, state, hasAll, sale
end

-- All 18 raw values of one listing as readable text, so the saved file shows what came.
local function rawSample(index)
  local r = { C_AuctionHouse.GetReplicateItemInfo(index) }
  local parts = {}
  for i = 1, 18 do
    parts[i] = tostring(r[i])
  end
  local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(index)
  return index .. " | " .. table.concat(parts, " | ") .. " | link=" .. string.gsub(tostring(link), "|", "!")
end

local function noteSeller(c, who)
  if who then
    c.known = c.known + 1
    if not c.seen[who] then
      c.seen[who] = true
      c.sellers = c.sellers + 1
    end
  end
end

local function packOne(c, index)
  local rec, who, state, hasAll, sale = readRecord(c, index)
  if not rec then
    c.skipped = c.skipped + 1
    return
  end
  c.n = c.n + 1
  c.parts[c.n] = rec
  bump(c.stats, "owner_" .. state)
  bump(c.stats, hasAll and "hasAllInfo_true" or "hasAllInfo_false")
  bump(c.stats, "sale_" .. tostring(sale))
  noteSeller(c, who)
  if not hasAll then -- no item data yet: read this listing once more later
    c.pendingIdx[#c.pendingIdx + 1] = index
    c.pendingSlot[#c.pendingSlot + 1] = c.n
  end
  local kind
  if index < 6 then
    kind = "first"
  elseif index % SAMPLE_EVERY == 0 then
    kind = "every"
  elseif string.match(rec, "^%-?%d+:1:") and (c.samplesOf.single or 0) < 4 then
    kind = "single"
  end
  if kind then
    c.samplesOf[kind] = (c.samplesOf[kind] or 0) + 1
    c.samples[#c.samples + 1] = kind .. " " .. rawSample(index)
  end
end

local function trim(list, scan, keep)
  local perMarket = 0
  for i = #list, 1, -1 do
    local s = list[i]
    if s.realm == scan.realm and s.faction == scan.faction then
      perMarket = perMarket + 1
      if perMarket > keep then
        table.remove(list, i)
      end
    end
  end
end

-- Sell-to-vendor price of every item in the scan (copper per item). Only items whose data is on
-- the client answer; the rest come with a later scan.
local function collectSellPrices(parts)
  local seen, added = {}, 0
  for i = 1, #parts do
    local id = tonumber(string.match(parts[i], "^(%-?%d+):"))
    if id and not seen[id] then
      seen[id] = true
      local info = Compat.GetItemInfo(id)
      local price = info and tonumber(info.sellPrice) or nil
      if price and db.sellPrices[id] ~= price then
        if db.sellPrices[id] == nil then
          added = added + 1
        end
        db.sellPrices[id] = price
      end
    end
  end
  return added
end

local function finish()
  local c = capture
  capture = nil
  if not c then
    return
  end
  if c.n == 0 then
    say(L["the listing arrived empty; nothing saved"])
    return
  end
  local current = C_AuctionHouse.GetNumReplicateItems()
  local scan = {
    ts = c.ts,
    realm = c.info.realm,
    faction = c.info.faction,
    region = c.info.region,
    build = c.info.build,
    count = c.n,
    strings = c.strings,
    data = table.concat(c.parts, ";"),
  }
  local meta = {
    ts = c.ts,
    realm = c.info.realm,
    faction = c.info.faction,
    region = c.info.region,
    build = c.info.build,
    count = c.n,
    addon = Capture.VERSION,
    trigger = c.trigger,
    expected = c.count,
    skipped = c.skipped,
    ownersKnown = c.known,
    sellers = c.sellers,
    stats = c.stats,
    samples = c.samples,
    retryPending = c.npendingStart, -- listings without item data at the first read
    retryFound = c.retryFound, -- of those, how many had it at the second
    changed = (current ~= c.count) or nil, -- the list changed while it was being read
  }
  meta.sellPricesNew = collectSellPrices(c.parts)
  table.insert(rawDb.scans, scan)
  trim(rawDb.scans, scan, db.keepRaw or DEFAULT_KEEP_RAW)
  table.insert(db.scans, meta)
  trim(db.scans, meta, db.keep or DEFAULT_KEEP)
  lastCaptureAt = GetTime()
  local pct = 100 * c.known / c.n
  say(
    string.format(
      L["saved %d listings (%s); seller known for %.0f%% (%d sellers)%s. Type /reload to write the files."],
      c.n,
      c.trigger,
      pct,
      c.sellers,
      meta.changed and L["; the list changed meanwhile, scan may be mixed"] or ""
    )
  )
  if c.known == 0 then
    say(L["no seller names came back at all; the raw dump keeps every field the server sent"])
  end
  -- the prices service summarises the new dump and fires BASTIANS_PRICES_UPDATED("scan") when done
  ns.Prices.Rebuild("scan")
end

local function discard(c, err)
  if capture == c then
    capture = nil
  end
  say(string.format(L["the listing could not be read (%s); scan discarded"], tostring(err)))
end

-- The second pass over the listings whose item data was missing, as a job.
local function retryPass(c)
  c.phase = "retry"
  local function retryOne(k)
    local index, slot = c.pendingIdx[k], c.pendingSlot[k]
    local rec, who, _, hasAll = readRecord(c, index)
    if rec then
      c.parts[slot] = rec -- whatever arrived since is in the new record
      if hasAll then
        c.retryFound = (c.retryFound or 0) + 1
      end
      noteSeller(c, who)
    end
  end
  c.job = B.Jobs:Run(mod, "ah-scan-retry", function(yield)
    for k = 1, #c.pendingIdx do
      local ok, err = pcall(retryOne, k)
      if not ok then
        say(string.format(L["could not complete the second pass (%s); saving what we have"], tostring(err)))
        return
      end
      if k % PACK_CHUNK == 0 then
        yield()
      end
    end
  end, {
    budgetMs = 8,
    onDone = function()
      if capture == c then
        finish()
      end
    end,
  })
end

local function startRetry(c)
  c.npendingStart = #c.pendingIdx
  if C_Item and C_Item.RequestLoadItemDataByID then
    local sent, seen = 0, {}
    for k = 1, #c.pendingIdx do
      if sent >= RETRY_LOAD_MAX then
        break
      end
      local id = select(17, C_AuctionHouse.GetReplicateItemInfo(c.pendingIdx[k]))
      if id and not seen[id] then
        seen[id] = true
        sent = sent + 1
        pcall(C_Item.RequestLoadItemDataByID, id)
      end
    end
  end
  c.phase = "retry-wait"
  c.timer = C_Timer.NewTimer(RETRY_DELAY, function()
    c.timer = nil
    if capture == c then
      retryPass(c)
    end
  end)
end

local function afterPack(c)
  if #c.pendingIdx > 0 and not c.closing then
    startRetry(c)
  else
    finish()
  end
end

local function beginCapture(trigger)
  local count = C_AuctionHouse.GetNumReplicateItems() or 0
  if count <= 0 then
    return
  end
  lastCaptureAt = GetTime()
  local c = {
    phase = "pack",
    count = count,
    n = 0,
    skipped = 0,
    known = 0,
    sellers = 0,
    parts = {},
    strings = {},
    stringIdx = {},
    seen = {},
    pendingIdx = {},
    pendingSlot = {},
    stats = {},
    samples = {},
    samplesOf = {},
    ts = nowEpoch(),
    info = clientInfo(),
    trigger = trigger,
  }
  capture = c
  say(string.format(L["reading the auction listing (%d listings); do not /reload until it is saved"], count))
  -- Lua 5.1 cannot yield across pcall, so every listing is protected on its own and the
  -- yield sits outside; the first error ends the pass and discards the scan.
  c.job = B.Jobs:Run(mod, "ah-scan", function(yield)
    for index = 0, c.count - 1 do
      local ok, err = pcall(packOne, c, index)
      if not ok then
        c.failed = err
        return
      end
      if index % PACK_CHUNK == PACK_CHUNK - 1 then
        yield()
      end
    end
  end, {
    budgetMs = 8,
    onDone = function()
      if capture ~= c then
        return
      end
      if c.failed then
        discard(c, c.failed)
      else
        afterPack(c)
      end
    end,
  })
end

function Capture.RequestScan(force)
  trace(
    string.format(
      "request: house open %s, ReplicateItems %s",
      tostring(ahOpen()),
      tostring(Compat.Has.ReplicateAH)
    )
  )
  if capture then
    say(L["a capture is already running"])
    return
  end
  if not Compat.Has.ReplicateAH then
    say(L["this client does not expose C_AuctionHouse.ReplicateItems"])
    return
  end
  if not ahOpen() then
    say(L["open the auction house first"])
    return
  end
  local left = windowLeft()
  if left > 0 and not force then
    local ago = math.floor((WINDOW_S - left) / 60)
    say(
      string.format(
        L["not sending: a full-listing request was made %d min ago (by any addon),"]
          .. " "
          .. L["and the server ignores another for about %d more min."]
          .. " %s"
          .. L["Use /bgold scan force to send anyway."],
        ago,
        minutes(left),
        db.pending and L["That request has not been answered yet; keep the house open and do not /reload. "]
          or ""
      )
    )
    return
  end
  requested = true
  say(L["requesting the full listing; the server allows about one every 15 minutes"])
  C_AuctionHouse.ReplicateItems()
end

function Capture.Status()
  local last = db.scans[#db.scans]
  say(
    string.format(
      L["version %s, %d scan summaries (keep %d), %d raw dumps (keep %d) per realm and faction"],
      Capture.VERSION,
      #db.scans,
      db.keep or DEFAULT_KEEP,
      #rawDb.scans,
      db.keepRaw or DEFAULT_KEEP_RAW
    )
  )
  local left = windowLeft()
  if left > 0 then
    say(
      string.format(
        L["15-minute window: last request %d min ago (%s); a new one is likely ignored for %d more min"],
        math.floor((WINDOW_S - left) / 60),
        db.pending and L["no reply yet"] or L["answered"],
        minutes(left)
      )
    )
  else
    say(L["15-minute window: free (no request seen in the last 15 min)"])
  end
  if last then
    local age = math.floor((nowEpoch() - (last.ts or 0)) / 60)
    say(
      string.format(
        L["last: %s %s, %d listings, seller known for %d, %d min ago"],
        tostring(last.realm),
        tostring(last.faction),
        last.count or 0,
        last.ownersKnown or 0,
        age
      )
    )
  end
end

function Capture.IsScanning()
  return capture ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Merchants and trainers: where the player stands is the NPC's place to within a few yards
-- ---------------------------------------------------------------------------------------------

local function npcID()
  local guid = Compat.Plain(UnitGUID("npc"))
  if type(guid) ~= "string" then
    return nil
  end
  return tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- uiMapID and 0-100 coordinates with one decimal; nil where the map has no position (instances).
local function playerPosition()
  local _, _, _, mapID, x, y = B.Coords.Player()
  if not (mapID and x and y) or (x == 0 and y == 0) then
    return nil
  end
  return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function placeText(x, y)
  return x and string.format(" at %.1f, %.1f", x, y) or "; no map position"
end

local merchantPending = false
local merchantAnnounce = false -- MERCHANT_UPDATE also fires on every purchase; only the first read talks

local function readMerchant()
  merchantPending = false
  local n = Compat.GetNumMerchantItems()
  if n == 0 then
    return
  end
  local info = clientInfo()
  local id = npcID()
  local name = UnitName("npc")
  local offers, missing = {}, 0
  for i = 1, n do
    local it = Compat.GetMerchantItem(i)
    if it and it.itemID and it.price then
      -- itemID:price:stack:available:extended; price is for the whole stack, available is empty
      -- when unlimited, extended is 1 when tokens or items are part of the price
      offers[#offers + 1] = table.concat({
        it.itemID,
        it.price,
        field(it.stack),
        (it.numAvailable and it.numAvailable >= 0) and it.numAvailable or "",
        it.hasExtendedCost and 1 or "",
      }, ":")
    else
      missing = missing + 1
    end
  end
  local key = tostring(info.realm) .. "|" .. tostring(id or name or "?")
  local mapID, x, y = playerPosition()
  db.merchants[key] = {
    npcID = id,
    name = name,
    realm = info.realm,
    faction = info.faction,
    zone = GetZoneText(),
    mapID = mapID,
    x = x,
    y = y,
    at = nowEpoch(),
    count = n,
    missing = missing,
    fields = "itemID,price,stack,available,extended",
    offers = table.concat(offers, ";"),
  }
  -- the vendor sell prices of what this merchant offers (R9, "sell price known
  -- for 0 items" after a first scan, whose items the client had not cached yet)
  collectSellPrices(offers)
  B:Fire("BASTIANS_PRICES_UPDATED", "merchant") -- the Sells section of this NPC changed
  local note = merchantAnnounce and say or trace
  merchantAnnounce = false
  note(
    string.format(
      "merchant %s (%s): %d offers, %d without data%s",
      tostring(name),
      tostring(id),
      #offers,
      missing,
      placeText(x, y)
    )
  )
end

local function scheduleMerchant()
  if merchantPending then
    return
  end
  merchantPending = true
  C_Timer.After(MERCHANT_DELAY, readMerchant)
end

local trainerPending = false

-- Switches on every filter that is off. Returns the kinds it switched (to switch back) and whether
-- all three are on now; nil when the client has no filter API.
local function openTrainerFilters()
  if Compat.GetTrainerFilter("available") == nil then
    return nil, false
  end
  local switched, allOn = {}, true
  for _, kind in ipairs(TRAINER_TYPES) do
    if not Compat.GetTrainerFilter(kind) then
      if pcall(Compat.SetTrainerFilter, kind, true) and Compat.GetTrainerFilter(kind) then
        switched[#switched + 1] = kind
      else
        allOn = false
      end
    end
  end
  return switched, allOn
end

local function restoreTrainerFilters(switched)
  for _, kind in ipairs(switched or {}) do
    if not pcall(Compat.SetTrainerFilter, kind, false) then
      trace("could not switch the trainer filter '" .. kind .. "' back off")
    end
  end
end

local function trainerServices()
  local n = Compat.GetNumTrainerServices()
  local services, missing, collapsed = {}, 0, 0
  local counts = { available = 0, unavailable = 0, used = 0 }
  local group
  for i = 1, n do
    local e = Compat.GetTrainerService(i)
    if e and e.kind == "header" then
      group = e.name
      if e.expanded == false then
        collapsed = collapsed + 1
      end
    elseif e and e.name then
      -- a missing value stays absent; a cost of 0 is the game saying "free"
      local s = { name = e.name, kind = e.kind, group = group, icon = e.icon }
      if e.subtext and e.subtext ~= "" then
        s.rank = e.subtext
      end
      s.cost = e.cost
      if e.levelReq and e.levelReq > 0 then
        s.level = e.levelReq
      end
      if e.skillReq and e.skillReq.name and e.skillReq.name ~= "" then
        s.skill, s.skillLevel = e.skillReq.name, e.skillReq.rank
      end
      s.itemID, s.spellID = e.itemID, e.spellID
      services[#services + 1] = s
      if counts[e.kind] then
        counts[e.kind] = counts[e.kind] + 1
      end
    else
      missing = missing + 1
    end
  end
  return services, missing, collapsed, counts
end

local function readTrainer(attempt)
  trainerPending = false
  attempt = attempt or 1
  local switched, allOn = openTrainerFilters()
  local ok, services, missing, collapsed, counts = pcall(trainerServices)
  restoreTrainerFilters(switched)
  if not ok then
    say(string.format(L["could not read the trainer window (%s)"], tostring(services)))
    return
  end
  if #services == 0 and missing == 0 then
    if attempt <= TRAINER_RETRIES then
      C_Timer.After(TRAINER_DELAY, function()
        readTrainer(attempt + 1)
      end)
    else
      trace("trainer window stayed empty")
    end
    return
  end
  local info = clientInfo()
  local id = npcID()
  local name = Compat.Plain(UnitName("npc"))
  local tradeskill = Compat.IsTradeskillTrainer()
  local key = tostring(info.realm) .. "|" .. tostring(id or name or "?")
  local mapID, x, y = playerPosition()
  db.trainers[key] = {
    npcID = id,
    name = name,
    realm = info.realm,
    faction = info.faction,
    zone = GetZoneText(),
    mapID = mapID,
    x = x,
    y = y,
    at = nowEpoch(),
    count = #services,
    missing = missing,
    collapsed = collapsed,
    tradeskill = tradeskill ~= nil and (tradeskill and 1 or 0) or nil,
    allShown = allOn and 1 or 0,
    services = services,
  }
  say(
    string.format(
      "trainer %s (%s): %d services (%d available, %d not yet, %d learned), %d without data%s%s",
      tostring(name),
      tostring(id),
      #services,
      counts.available,
      counts.unavailable,
      counts.used,
      missing,
      (collapsed > 0 and string.format("; %d groups collapsed, their services are missing", collapsed) or "")
        .. (allOn and "" or "; filters stayed closed, hidden services are missing"),
      placeText(x, y)
    )
  )
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

local function countEvent(event)
  db.events = db.events or {}
  db.events[event] = (db.events[event] or 0) + 1
  traceBurst(
    event,
    string.format(
      "event %s (house open: %s, capturing: %s, replicate items: %s)",
      event,
      tostring(ahOpen()),
      tostring(capture ~= nil),
      tostring(Compat.Has.ReplicateAH and C_AuctionHouse.GetNumReplicateItems() or "?")
    )
  )
end

local function onReplicate(_, event)
  countEvent(event)
  db.pending = false
  db.lastReplyAt = nowEpoch()
  if capture then
    return
  end
  if not ahOpen() then
    traceBurst("ignored-closed", "ignored: the auction house window does not count as open")
    return
  end
  if GetTime() - lastCaptureAt < DEDUPE_S then
    traceBurst("ignored-recent", "ignored: a capture finished less than " .. DEDUPE_S .. "s ago")
    return
  end
  local trigger = requested and "own request" or "another addon's scan"
  requested = false
  beginCapture(trigger)
end

local function onClosed(_, event)
  countEvent(event)
  requested = false
  ns.Advisor.OnShop(false) -- the bag advisor closes with the auction house (S4)
  if db.pending and not capture then
    say(
      L["the auction house closed before the full listing arrived;"]
        .. " "
        .. L["that request still used up the 15-minute window"]
    )
  end
  local c = capture
  if not c then
    return
  end
  -- The list stays readable only while the house is open: read the rest in this one frame.
  c.closing = true
  if c.phase == "pack" then
    B.Jobs:Flush(c.job)
  elseif c.phase == "retry-wait" then
    if c.timer then
      c.timer:Cancel()
      c.timer = nil
    end
    finish()
  elseif c.phase == "retry" then
    B.Jobs:Flush(c.job)
  end
end

local function onThrottled(_, event)
  countEvent(event)
  db.droppedAt = nowEpoch()
  if requested and not capture then
    requested = false
    say(L["the server refused the request; it allows about one full listing every 15 minutes"])
  end
end

function Capture.Register(m)
  mod = m
  db = m.db.global.capture
  db.format = Capture.FORMAT
  db.scans = db.scans or {}
  db.merchants = db.merchants or {}
  db.trainers = db.trainers or {}
  db.sellPrices = db.sellPrices or {}
  if type(BastiansGoldRaw) ~= "table" then
    BastiansGoldRaw = {}
  end
  rawDb = BastiansGoldRaw
  rawDb.format = Capture.RAW_FORMAT
  rawDb.fields = Capture.FIELDS
  rawDb.scans = rawDb.scans or {}
  if db.pending and nowEpoch() - (tonumber(db.lastRequestAt) or 0) > 600 then
    db.pending = false
  end
  m:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", onReplicate)
  m:RegisterEvent("AUCTION_HOUSE_SHOW", function(_, event)
    countEvent(event)
    ns.Advisor.OnShop(true) -- the bag advisor (S4); one handler per event per module
  end)
  m:RegisterEvent("AUCTION_HOUSE_CLOSED", onClosed)
  m:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", onThrottled)
  m:RegisterEvent("MERCHANT_SHOW", function(_, event)
    countEvent(event)
    merchantAnnounce = true
    scheduleMerchant()
    ns.Advisor.OnShop(true) -- the bag advisor (S4)
  end)
  m:RegisterEvent("MERCHANT_UPDATE", function(_, event)
    countEvent(event)
    scheduleMerchant()
  end)
  m:RegisterEvent("TRAINER_SHOW", function(_, event)
    countEvent(event)
    if not trainerPending then
      trainerPending = true
      C_Timer.After(TRAINER_DELAY, function()
        readTrainer(1)
      end)
    end
  end)
  trace("loaded v" .. Capture.VERSION)
end

-- The captured merchant record of an NPC on this realm, or nil.
function Capture.Merchant(id)
  if not db then
    return nil
  end
  return db.merchants[tostring(GetRealmName() or "unknown") .. "|" .. tostring(id)]
end

-- The vendor sell price per unit seen in a scan, or nil.
function Capture.SellPrice(itemID)
  return db and db.sellPrices[itemID] or nil
end

-- The counts for /bgold vendors and the settings note.
function Capture.Counts()
  local merchants, offers, sells, trainers, services = 0, 0, 0, 0, 0
  for _, m in pairs(db and db.merchants or {}) do
    merchants = merchants + 1
    offers = offers + (m.count or 0)
  end
  for _ in pairs(db and db.sellPrices or {}) do
    sells = sells + 1
  end
  for _, t in pairs(db and db.trainers or {}) do
    trainers = trainers + 1
    services = services + (t.count or 0)
  end
  return {
    merchants = merchants,
    offers = offers,
    sellPrices = sells,
    trainers = trainers,
    services = services,
  }
end

function Capture.Slash(msg)
  local cmd, rest = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  rest = string.lower(rest or "")
  if cmd == "scan" then
    Capture.RequestScan(rest == "force")
  elseif cmd == "keep" or cmd == "keepraw" then
    local n = tonumber(rest)
    local max = (cmd == "keep") and 30 or 10
    if n and n >= 1 and n <= max then
      db[cmd == "keep" and "keep" or "keepRaw"] = math.floor(n)
      say(
        string.format(
          L["keeping %d %s per realm and faction"],
          math.floor(n),
          cmd == "keep" and L["scan summaries"] or L["raw dumps"]
        )
      )
    else
      say(string.format(L["usage: /bgold %s 1..%d"], cmd, max))
    end
  elseif cmd == "" or cmd == "status" then
    Capture.Status()
  elseif cmd == "vendors" then
    local c = Capture.Counts()
    say(
      string.format(
        L["%d merchants with %d offers noted; %d trainers with %d services; sell price known for %d items"],
        c.merchants,
        c.offers,
        c.trainers,
        c.services,
        c.sellPrices
      )
    )
  elseif cmd == "log" then
    db.log = db.log or {}
    for i = math.max(1, #db.log - 9), #db.log do
      B:Say("%s", db.log[i])
    end
  else
    say(L["commands: /bgold status | scan [force] | vendors | log | keep <1-30> | keepraw <1-10>"])
  end
end
