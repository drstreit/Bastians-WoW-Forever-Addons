-- Journey (quests.md "Journey", S3, 22.10.2026): what a session brought per zone, the port of
-- AHSyncGuide's Journey.lua. One entry per session and zone in BastiansQuestsDB.global.journey
-- (account-wide, every character writes the same list; the shape AHSync's journey.py reads):
--   { c = "Name-Realm", cls = "MAGE", s = <login, unix>, m = <uiMapID>, mn = <map name>,
--     t0 = <start>, t1 = <last event>, lv = <level at start>, xp = n, gold = <copper, signed>,
--     kills = n, q = { questID, ... } }
-- XP from PLAYER_XP_UPDATE (the difference; across a level-up the rest of the old bar plus the
-- new one), gold from PLAYER_MONEY (every delta, so vendoring, repairs and the AH count), kills
-- from CHAT_MSG_COMBAT_XP_GAIN (kills that gave experience), quests from QUEST_TURNED_IN. A zone
-- change closes the entry; an entry under 30 seconds with nothing in it is dropped; at most 500
-- entries, the oldest go first. Reads only; nothing is sent.
local _, ns = ...
local B = Bastians
local L = ns.L

local Journey = {}
ns.Journey = Journey

Journey.VERSION = 1
Journey.MAX = 500
Journey.MIN_SECONDS = 30
Journey.NOTIFY_DELAY = 15 -- seconds between two BASTIANS_JOURNEY_CHANGED while figures change

local mod
local cur -- the open entry, nil until the first touch
local session -- the login time, the `s` of every entry of this session
local lastXP, lastMax, lastLevel, lastMoney

local function now()
  return time()
end

local function enabled()
  return mod ~= nil and mod.db.profile.journey ~= false
end

local function store()
  local g = mod.db.global
  if type(g.journey) ~= "table" or type(g.journey.entries) ~= "table" then
    g.journey = { version = Journey.VERSION, entries = {} }
  end
  g.journey.version = Journey.VERSION
  return g.journey
end
Journey.Store = store

local function character()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function classToken()
  local _, token = UnitClass("player")
  return token or "?"
end

local function isEmpty(e)
  return (e.xp or 0) == 0 and (e.gold or 0) == 0 and (e.kills or 0) == 0 and not e.q
end

-- The zone's name from the data, nil until the pack is loaded (filled in at the next touch).
local function mapName(map)
  return B:Entity("zone:" .. map):Name()
end

-- The map the player stands on now (the client's answer, not the coalesced announcement: a
-- zone change must close the old entry at once).
local function playerMap()
  local map = select(4, B.Coords.Player())
  if not map and B.Coords.PlayerMap then
    map = B.Coords.PlayerMap()
  end
  return map
end

local function changed()
  if mod then
    mod:Coalesce("journey", Journey.NOTIFY_DELAY, function()
      B:Fire("BASTIANS_JOURNEY_CHANGED")
    end)
  end
end

-- Close the open entry; drop it when it holds nothing and lasted under MIN_SECONDS.
function Journey.Close()
  local e = cur
  if not e then
    return
  end
  e.t1 = math.max(e.t1 or e.t0, now())
  if not e.mn then
    e.mn = mapName(e.m)
  end
  cur = nil
  if isEmpty(e) and (e.t1 - e.t0) < Journey.MIN_SECONDS then
    local entries = store().entries
    for i = #entries, 1, -1 do
      if entries[i] == e then
        table.remove(entries, i)
        break
      end
    end
  end
  changed()
end

function Journey.Open(map)
  Journey.Close()
  if not (enabled() and map) then
    return nil
  end
  local entries = store().entries
  local t = now()
  local e = {
    c = character(),
    cls = classToken(),
    s = session,
    m = map,
    mn = mapName(map),
    t0 = t,
    t1 = t,
    lv = UnitLevel("player"),
    xp = 0,
    gold = 0,
    kills = 0,
  }
  entries[#entries + 1] = e
  while #entries > Journey.MAX do
    table.remove(entries, 1)
  end
  cur = e
  return e
end

-- The entry for the zone the player stands in (opens one when the zone changed), nil in
-- instances without a map position and while the setting is off.
function Journey.Touch()
  if not enabled() then
    Journey.Close()
    return nil
  end
  local map = playerMap()
  if not map then
    return cur
  end
  if not cur or cur.m ~= map then
    Journey.Open(map)
  end
  if cur then
    cur.t1 = now()
    if not cur.mn then
      cur.mn = mapName(map)
    end
  end
  return cur
end

function Journey.Current()
  return cur
end

-- Experience: the difference to the last reading; across a level-up the remainder of the old bar
-- plus the new reading.
function Journey.OnXP()
  local xp, max, level = B.Compat.GetPlayerXP()
  if not xp then
    return
  end
  if lastXP ~= nil then
    local gain
    if level > (lastLevel or level) then
      gain = ((lastMax or 0) - lastXP) + xp
    else
      gain = xp - lastXP
    end
    if gain > 0 then
      local e = Journey.Touch()
      if e then
        e.xp = (e.xp or 0) + gain
        changed()
      end
    end
  end
  lastXP, lastMax, lastLevel = xp, max, level
end

function Journey.OnMoney()
  local m = B.Compat.GetMoney() or 0
  if lastMoney ~= nil and m ~= lastMoney then
    local e = Journey.Touch()
    if e then
      e.gold = (e.gold or 0) + (m - lastMoney)
      changed()
    end
  end
  lastMoney = m
end

function Journey.OnKill()
  local e = Journey.Touch()
  if e then
    e.kills = (e.kills or 0) + 1
    changed()
  end
end

function Journey.OnQuest(questID)
  questID = tonumber(questID)
  if not questID then
    return
  end
  local e = Journey.Touch()
  if not e then
    return
  end
  e.q = e.q or {}
  e.q[#e.q + 1] = questID
  changed()
end

-- A login or a zone load: the readings start again (no XP or money is attributed to the load).
function Journey.OnEnteringWorld()
  local xp, max, level = B.Compat.GetPlayerXP()
  lastXP, lastMax, lastLevel = xp, max, level
  lastMoney = B.Compat.GetMoney() or 0
  Journey.Touch()
end

-- ---------------------------------------------------------------------------------------------
-- Totals (pure over the entries)
-- ---------------------------------------------------------------------------------------------

local function newTotal(map, name)
  return { m = map, mn = name, seconds = 0, xp = 0, gold = 0, kills = 0, quests = 0, entries = 0 }
end

-- An entry that would be dropped at its close (nothing in it, under MIN_SECONDS) counts nowhere.
local function counts(e)
  return not (isEmpty(e) and ((e.t1 or e.t0) - e.t0) < Journey.MIN_SECONDS)
end

local function addTo(z, e)
  z.seconds = z.seconds + math.max(0, (e.t1 or e.t0) - e.t0)
  z.xp, z.gold, z.kills = z.xp + (e.xp or 0), z.gold + (e.gold or 0), z.kills + (e.kills or 0)
  z.quests = z.quests + (e.q and #e.q or 0)
  z.entries = z.entries + 1
end

-- This session per zone, in the order the zones were first entered:
-- { { m, mn, seconds, xp, gold, kills, quests, entries } }.
function Journey.Summary()
  local out, by = {}, {}
  if not (mod and session) then
    return out
  end
  if cur then
    cur.t1 = now()
  end
  for _, e in ipairs(store().entries) do
    if e.s == session and counts(e) then
      local z = by[e.m]
      if not z then
        z = newTotal(e.m, e.mn or ns.Rows.zoneName(e.m))
        by[e.m] = z
        out[#out + 1] = z
      end
      addTo(z, e)
    end
  end
  return out
end

-- One zone: `session` (this session's total or nil) and `all` (every entry of the account or nil,
-- with `sessions` = the number of distinct sessions).
function Journey.Zone(map)
  if not (mod and map) then
    return nil, nil
  end
  if cur and cur.m == map then
    cur.t1 = now()
  end
  local this, all, sessions = nil, nil, {}
  for _, e in ipairs(store().entries) do
    if e.m == map and counts(e) then
      all = all or newTotal(map, e.mn or ns.Rows.zoneName(map))
      addTo(all, e)
      if e.s then
        sessions[e.s] = true
      end
      if e.s == session then
        this = this or newTotal(map, e.mn or ns.Rows.zoneName(map))
        addTo(this, e)
      end
    end
  end
  if all then
    local n = 0
    for _ in pairs(sessions) do
      n = n + 1
    end
    all.sessions = n
  end
  return this, all
end

-- ---------------------------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------------------------

local function signedMoney(copper)
  if copper < 0 then
    return "-" .. B.UI.Money(-copper)
  end
  return "+" .. B.UI.Money(copper)
end

local function perHour(n, seconds)
  if seconds < 60 then
    return nil
  end
  return math.floor(n / (seconds / 3600) + 0.5)
end

-- "42 min, 1,230 xp (1,760/h), +12s 30c, 17 kills, 3 quests"
function Journey.Words(z)
  local parts = {}
  local minutes = math.floor(z.seconds / 60 + 0.5)
  if minutes >= 90 then
    parts[#parts + 1] = string.format("%.1f h", z.seconds / 3600)
  else
    parts[#parts + 1] = string.format(L["%d min"], minutes)
  end
  local rate = perHour(z.xp, z.seconds)
  parts[#parts + 1] = rate and string.format(L["%d xp (%d/h)"], z.xp, rate) or string.format(L["%d xp"], z.xp)
  parts[#parts + 1] = signedMoney(z.gold)
  parts[#parts + 1] = string.format(L["%d kills"], z.kills)
  parts[#parts + 1] = string.format(L["%d quests"], z.quests)
  return table.concat(parts, ", ")
end

-- The rows of the Journey block on a zone page and in the Here column: this session here, then
-- every session of the account here. Nothing recorded: no block.
local function zoneRows(ref)
  local map = tonumber(string.match(ref or "", "^zone:(%d+)$"))
  local this, all = Journey.Zone(map)
  if not (this or all) then
    return nil
  end
  local GREY = ns.Rows.COLOR.grey
  local rows = {}
  if this then
    rows[#rows + 1] = {
      id = "journey:session",
      text = L["This session"] .. "  " .. GREY .. Journey.Words(this) .. "|r",
    }
  end
  if all and (not this or all.entries > this.entries) then
    rows[#rows + 1] = {
      id = "journey:all",
      text = string.format(L["%d sessions"], all.sessions or 0) .. "  " .. GREY .. Journey.Words(all) .. "|r",
    }
  end
  return rows
end

-- "/bq journey": this session's totals per zone in the chat.
function Journey.Print()
  local rows = Journey.Summary()
  if #rows == 0 then
    B:Say(L["Journey: nothing recorded yet this session"])
    return
  end
  B:Say(L["Journey (this session):"])
  for _, z in ipairs(rows) do
    B:Say("  %s: %s", z.mn, Journey.Words(z))
  end
end

-- ---------------------------------------------------------------------------------------------
-- Wiring (one handler per event per module, Core: QUEST_TURNED_IN and PLAYER_ENTERING_WORLD are
-- the module's own handlers in Quests.lua, which call OnQuest and OnEnteringWorld)
-- ---------------------------------------------------------------------------------------------

function Journey.Register(self)
  mod = self
  session = now()
  cur = nil
  lastXP, lastMax, lastLevel, lastMoney = nil, nil, nil, nil
  B:DeclareMessage("BASTIANS_JOURNEY_CHANGED")
  B:RegisterDetailSection(self, {
    id = "quests.journey",
    title = L["Journey"],
    types = { "zone" },
    order = 98,
    block = { columns = 1 },
    here = { order = 4, limit = 2 },
    invalidateOn = { "BASTIANS_JOURNEY_CHANGED", "BASTIANS_PLAYER_MOVED_ZONE" },
    build = zoneRows,
  })
  self:RegisterEvent("PLAYER_XP_UPDATE", Journey.OnXP)
  self:RegisterEvent("PLAYER_MONEY", Journey.OnMoney)
  self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", Journey.OnKill)
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Journey.Touch)
  self:RegisterEvent("PLAYER_LOGOUT", Journey.Close)
  Journey.OnEnteringWorld()
end

function Journey.Unregister()
  Journey.Close()
end
