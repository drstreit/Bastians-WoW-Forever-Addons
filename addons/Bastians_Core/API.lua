-- The public API for other addons (ADR 0044): Bastians.API, answers as copies of plain values.
-- The definition for addon authors is API.md in the suite's repository.
--
-- For other addons: list Bastians_Core in ## OptionalDeps, then
--   local api = Bastians and Bastians.API
--   if api and api.Price then local p = api.Price(2589) end  -- test a function before calling it
-- Unknown is nil: an app not installed or switched off, data not loaded yet. Money is integer
-- copper; map positions are uiMapID, x, y with x and y in 0..1; world positions continent, wx, wy
-- in yards. API.VERSION counts breaking changes only; a new function or field keeps it.
-- Events: api.RegisterCallback(target, event, fn) with an event of api.EVENTS; fn(event, ...)
-- gets strings, numbers and booleans only. UnregisterCallback(target, event) and
-- UnregisterAllCallbacks(target) as in CallbackHandler-1.0.
local _, ns = ...
local B = ns.B

local API = { VERSION = 1 }
B.API = API

-- What other addons may listen to; WeakAuras and ForeverAuras get the same (ADR 0043 decision 5).
API.EVENTS = {
  "BASTIANS_QUESTS_CHANGED", -- the quest log changed; read Quest/QuestLog again
  "BASTIANS_TRACKED_CHANGED", -- ref ("quest:123"), tracked
  "BASTIANS_ROUTE_CHANGED", -- a route started, moved on a step or ended; read Route again
  "BASTIANS_PRICES_UPDATED", -- source: "scan", "market" or "merchant"; read Price again
  "BASTIANS_NOTES_CHANGED",
  "BASTIANS_ALTS_CHANGED",
  "BASTIANS_PLAYER_MOVED_ZONE", -- uiMapID, continent
  "BASTIANS_MODULE_STATE", -- app name, enabled
  "BASTIANS_GRAPH_TIMES", -- travel times were worked out again; read TravelTime again
  "BASTIANS_PLAY_CHANGED", -- play preset id ("wanderer", "scholar", "everything", "custom")
  "BASTIANS_CHAT_UNREAD", -- count of whisper conversations with unread lines (Bastian's Chat)
  "BASTIANS_VOICE_CHANGED", -- what the Orbiter plays changed; read Now-like state through Speak
  "BASTIANS_CAMP_SHARED", -- uiMapID, x, y: a fire shared by the group or guild (Bastian's Campfire)
  "BASTIANS_CAMP_WARMED", -- host name or nil: the camp's buffs landed on the player
  "BASTIANS_CAMP_FADING", -- seconds left of the camp's buffs (ten minutes before they end)
  "BASTIANS_WAYPOINT_CHANGED", -- uiMapID, x, y of the new waypoint, or nothing when cleared
}

-- The services (core-contracts §11, B.SERVICES) the API reads, and the ones it never will, with
-- the reason: tests/lua/core/test_public_surface.py refuses a service in neither list, so a new
-- one is either offered to other addons or named internal on purpose (plan-second-wave.md S12).
API.READS = {
  prices = "Price",
  progress = "Quest, QuestLog",
  route = "Route, RouteTo",
  graph = "TravelTime",
  knowledge = "Known",
  voice = "Speak",
  camps = "Camp",
  notes = "NotesNear",
  income = "Income",
  waypoint = "Waypoint, SetWaypoint, ClearWaypoint",
  account = "AccountGold",
}
API.INTERNAL = {
  data = "the packs' loader: the calls above answer from it",
  travel = "Route's own travel model; TravelTime is the public face",
  views = "the Browser's view registry: windows of the suite",
  questSheet = "a window of the suite, opened on hover by the Orbiter",
  mapPicture = "the Map's style cells for the suite's own mini maps",
  facts = "the Library's facts injector: private until the Library ships",
  library = "the Library: private until it ships",
  requests = "Alts' asks between the account's characters: Gold's Bags read them (ADR 0058 PH6)",
  neversell = "Helpers' never-sell list: Gold's Bags read it (ADR 0058 PH6)",
}

local function scalar(v)
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" then
    return v
  end
  return nil
end

-- A new table with the plain values of `fields`; a table or function of the suite never leaves.
local function copy(src, fields)
  local out = {}
  for _, k in ipairs(fields) do
    out[k] = scalar(src[k])
  end
  return out
end

-- Every call runs safely: an error inside the suite is logged against Core, the caller gets nil.
local function safe(fn, two)
  return function(...)
    local ok, a, b = ns.safecall(ns.coreOwner, fn, ...)
    if not ok then
      return nil
    elseif two and a ~= nil then
      return a, b
    end
    return a
  end
end

local function service(name)
  return B:GetService(name)
end

local function isFraction(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

-- Apps() -> { { name, title, version, enabled } }, the suite's installed apps by name.
API.Apps = safe(function()
  local out = {}
  for _, mod in ipairs(ns.moduleList) do
    if not mod.parent then
      out[#out + 1] = {
        name = mod.name,
        title = scalar(mod.title),
        version = C_AddOns.GetAddOnMetadata(mod.addon, "Version"),
        enabled = mod:IsEnabled(),
      }
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end)

-- IsEnabled(name) -> true while that app ("Quests", "Gold", ...) runs, else false.
API.IsEnabled = safe(function(name)
  local mod = ns.modules[name]
  return mod ~= nil and mod:IsEnabled()
end)

local PRICE = {
  "median",
  "minBuyout",
  "quantity",
  "salesPerDay",
  "median7d",
  "median30d",
  "low30d",
  "high30d",
  "age",
  "source",
  "stale",
  "label",
}

-- Price(itemID) -> { median, minBuyout, quantity, salesPerDay, median7d, median30d, low30d,
-- high30d (copper), age (seconds), source ("scan" | "market"), stale, label } or nil. Bastian's Gold.
API.Price = safe(function(itemID)
  local prices = service("prices")
  if not prices or type(itemID) ~= "number" then
    return nil
  end
  local p = prices:Price(itemID)
  return p and copy(p, PRICE) or nil
end)

-- Quest(questID) -> { done, inLog, ready } or nil (Bastian's Quests, after its first look at the log).
API.Quest = safe(function(questID)
  local progress = service("progress")
  if not progress or type(questID) ~= "number" or progress:LogCounts() == nil then
    return nil
  end
  local inLog = progress:IsInLog(questID) == true
  return {
    done = progress:IsQuestDone(questID) == true,
    inLog = inLog,
    ready = inLog and progress:IsReady(questID) == true,
  }
end)

-- QuestLog() -> { count, ready }: quests in the log and how many can be turned in; or nil.
API.QuestLog = safe(function()
  local progress = service("progress")
  if not progress then
    return nil
  end
  local count, ready = progress:LogCounts()
  if count == nil then
    return nil
  end
  return { count = count, ready = ready }
end)

local ROUTE = { "goal", "continent", "wx", "wy", "seconds", "step", "steps" }

-- Route() -> { goal (its name), continent, wx, wy, seconds (left), step, steps } or nil.
API.Route = safe(function()
  local route = service("route")
  local r = route and route:Current()
  return r and copy(r, ROUTE) or nil
end)

-- TravelTime(uiMapID, x, y) -> seconds, approx; nil when not known yet (never a search: listen to
-- BASTIANS_GRAPH_TIMES and ask again).
API.TravelTime = safe(function(uiMapID, x, y)
  local graph = service("graph")
  if not graph or type(uiMapID) ~= "number" or not isFraction(x) or not isFraction(y) then
    return nil
  end
  local continent, wx, wy = B.Coords.ToWorld(uiMapID, x, y)
  if not continent then
    return nil
  end
  local seconds, approx = graph:Time({ map = continent, wx = wx, wy = wy })
  if type(seconds) ~= "number" then
    return nil
  end
  return seconds, approx == true
end, true)

-- RouteTo(uiMapID, x, y, name) -> true when Bastian's Route started planning a route there.
API.RouteTo = safe(function(uiMapID, x, y, name)
  local route = service("route")
  if not route or type(uiMapID) ~= "number" or not isFraction(x) or not isFraction(y) then
    return nil
  end
  local continent, wx, wy = B.Coords.ToWorld(uiMapID, x, y)
  if not continent then
    return nil
  end
  return route:ToPoint(continent, wx, wy, type(name) == "string" and name or nil) == true
end)

-- Known(spellID) -> { me, others, names }: whether this character knows the spell or recipe
-- (true, false, or nil when the client does not say), how many other characters of the account
-- do and their names ("Marla, Tobb"); or nil without Bastian's Alts.
API.Known = safe(function(spellID)
  local knowledge = service("knowledge")
  if not knowledge or type(spellID) ~= "number" then
    return nil
  end
  local k = knowledge:Known(spellID)
  if type(k) ~= "table" then
    return nil
  end
  local alts = type(k.alts) == "table" and k.alts or {}
  return { me = scalar(k.me), others = #alts, names = table.concat(alts, ", ") }
end)

-- Speak(text) -> true when the Orbiter spoke the text in the player's chosen voice; false when it
-- did not (another line plays, the voice is off); nil without the Orbiter.
API.Speak = safe(function(text)
  local voice = service("voice")
  if not voice or type(text) ~= "string" or text == "" then
    return nil
  end
  return voice.Can() and voice.Speak(text) == true or false
end)

-- Camp() -> { nearby, state, warmIn, left, buffs, readyIn, fires } or nil without Bastian's
-- Campfire: whether a fire is near, the state ("away", "near", "warming", "warm", "fading"),
-- seconds until warm and left of the camp's buffs (nil unknown), how many camp buffs, seconds until
-- the player's features can be placed again (nil unknown), how many shared fires are on the map.
API.Camp = safe(function()
  local camps = service("camps")
  if not camps then
    return nil
  end
  local n, mine = camps.Nearby() or {}, camps.Mine() or {}
  return {
    nearby = n.nearby == true,
    state = scalar(n.state),
    warmIn = scalar(n.warmIn),
    left = scalar(n.left),
    buffs = #(camps.Buffs() or {}),
    readyIn = scalar(mine.readyIn),
    fires = scalar(camps.Fires()),
  }
end)

-- Play() -> the play preset: "wanderer", "scholar", "everything" or "custom" (what the player
-- chose at the first start or on the Suite page; a companion addon can follow the Wanderer).
API.Play = safe(function()
  local settings = B.UI.Settings
  local id = settings and settings.PlayId and settings.PlayId()
  return scalar(id)
end)

-- Open(name) -> true when the app `name` opened its window (or its settings page when it has no
-- window); nil for an unknown or switched-off app. Never in combat for a window.
API.Open = safe(function(name)
  local mod = type(name) == "string" and ns.modules[name] or nil
  if not mod or mod.parent or not mod:IsEnabled() then
    return nil
  end
  if type(mod.def.open) == "function" then
    if InCombatLockdown() then
      return false
    end
    mod.def.open()
    return true
  end
  local hub = B.UI.Hub
  if hub and hub.Open then
    hub.Open(name)
    return true
  end
  return nil
end)

-- Entity(ref) -> { ref, type, id, name, summary } or nil: any thing of the suite by its ref
-- ("npc:299", "quest:7", "item:2589", "zone:1429"), the name in the client's language where the data
-- has it; nil for a ref nothing knows (04.11.2026).
API.Entity = safe(function(ref)
  if type(ref) ~= "string" then
    return nil
  end
  local typ, id = B.Entity.Parse(ref)
  if not typ or id == nil then
    return nil
  end
  local e = B:Entity(ref)
  local name = scalar(e:Name())
  if name == nil then
    return nil
  end
  return { ref = ref, type = typ, id = scalar(id), name = name, summary = scalar(e:Summary()) }
end)

-- Where(ref, max) -> { { uiMapID, x, y } } (x, y in 0..1): the places of the thing that matter now
-- (a quest's giver, an NPC's spawns, a node's spots), at most `max` (10 by default); nil without one.
API.Where = safe(function(ref, max)
  if type(ref) ~= "string" or not B.Entity.Parse(ref) then
    return nil
  end
  local limit = type(max) == "number" and max >= 1 and math.floor(max) or 10
  local out = {}
  for _, p in ipairs(B:Entity(ref):Locations() or {}) do
    if #out >= limit then
      break
    end
    if type(p.map) == "number" and isFraction(p.x) and isFraction(p.y) then
      out[#out + 1] = { uiMapID = p.map, x = p.x, y = p.y }
    end
  end
  return #out > 0 and out or nil
end)

-- NotesNear(uiMapID, x, y, yards) -> { { title, text, yards } } nearest first: the player's notes on
-- a spot within `yards` (40 by default, at most 500) of that point; nil without Bastian's Notes.
API.NotesNear = safe(function(uiMapID, x, y, yards)
  local notes = service("notes")
  if not (notes and notes.Spots) or type(uiMapID) ~= "number" or not isFraction(x) or not isFraction(y) then
    return nil
  end
  local continent, wx, wy = B.Coords.ToWorld(uiMapID, x, y)
  if not continent then
    return nil
  end
  local radius = type(yards) == "number" and yards > 0 and math.min(yards, 500) or 40
  local out = {}
  for _, n in ipairs(notes:Spots(continent) or {}) do
    local d = math.sqrt((n.wx - wx) ^ 2 + (n.wy - wy) ^ 2)
    if d <= radius then
      out[#out + 1] = { title = scalar(n.title), text = scalar(n.text), yards = math.floor(d + 0.5) }
    end
  end
  table.sort(out, function(a, b)
    return a.yards < b.yards
  end)
  return out
end)

-- Income(days) -> { ah, loot, spent } in copper over the last `days` days, today included (1 by
-- default, at most 30): gold from the auction house, from loot, and what was spent; nil without
-- Bastian's Gold.
API.Income = safe(function(days)
  local income = service("income")
  if not income then
    return nil
  end
  local n = type(days) == "number" and math.max(1, math.min(30, math.floor(days))) or 1
  local t = income:Total(n)
  return type(t) == "table" and copy(t, { "ah", "loot", "spent" }) or nil
end)

-- Waypoint() -> { uiMapID, x, y, label } (x, y in 0..1) of the player's own waypoint on Bastian's
-- Map, or nil when there is none (or without the Map).
API.Waypoint = safe(function()
  local w = service("waypoint")
  local p = w and w:Get()
  if type(p) ~= "table" or not (p.map and p.x and p.y) then
    return nil
  end
  return { uiMapID = p.map, x = p.x, y = p.y, label = scalar(p.label) }
end)

-- SetWaypoint(uiMapID, x, y, label) -> true when Bastian's Map set the waypoint there; nil without
-- the Map or for a point on no known map.
API.SetWaypoint = safe(function(uiMapID, x, y, label)
  local w = service("waypoint")
  if not w or type(uiMapID) ~= "number" or not isFraction(x) or not isFraction(y) then
    return nil
  end
  local continent, wx, wy = B.Coords.ToWorld(uiMapID, x, y)
  if not continent then
    return nil
  end
  return w:Set(continent, wx, wy, type(label) == "string" and label or nil, uiMapID, x, y) == true
end)

-- ClearWaypoint() -> true when the waypoint is gone; nil without the Map.
API.ClearWaypoint = safe(function()
  local w = service("waypoint")
  return w and w:Clear() == true or nil
end)

-- AccountGold() -> { copper, characters }: the money of the account's characters as last seen by
-- Bastian's Alts and how many it covers; nil without Alts or before any is known (unknown, not 0).
API.AccountGold = safe(function()
  local account = service("account")
  if not account then
    return nil
  end
  local copper, known = account:Money()
  if type(copper) ~= "number" then
    return nil
  end
  return { copper = copper, characters = scalar(known) }
end)

-- ItemSets() -> { { id, label, kind } }: the suite's item sets for bag addons ("category", "junk"
-- or "mark"), by id; an empty table when no app registered one.
API.ItemSets = safe(function()
  local out = {}
  for _, id in ipairs(B.Bags.order) do
    local def = B.Bags.defs[id]
    if def then
      out[#out + 1] = { id = id, label = scalar(def.label), kind = scalar(def.kind) }
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end)

-- ItemSet(id) -> { itemID, ... } sorted: the items of that set now; nil for an unknown set.
API.ItemSet = safe(function(id)
  local def = type(id) == "string" and B.Bags.defs[id]
  if not def then
    return nil
  end
  local ok, set = ns.safecall(def.owner, def.items)
  local out = {}
  if ok and type(set) == "table" then
    for itemID, on in pairs(set) do
      if type(itemID) == "number" and on then
        out[#out + 1] = itemID
      end
    end
  end
  table.sort(out)
  return out
end)

-- RegisterCallback, UnregisterCallback, UnregisterAllCallbacks
local callbacks = LibStub("CallbackHandler-1.0"):New(API)

for _, msg in ipairs(API.EVENTS) do
  ns.on(msg, function(_, _, a, b, c)
    a, b, c = scalar(a), scalar(b), scalar(c)
    callbacks:Fire(msg, a, b, c)
    local wa = rawget(_G, "WeakAuras")
    if type(wa) == "table" and type(wa.ScanEvents) == "function" then
      wa.ScanEvents(msg, a, b, c)
    end
  end)
end
