-- Core: the fact layer (library.md §4, ADR 0028): what the game lets us sense, as state facts read
-- on demand and happenings raised from events, with an injector for authors and tests and a report
-- for the inspector. Events are registered only while a happening has a watcher (CLAUDE.md §4.7).
local _, ns = ...
local B = ns.B
local Compat = B.Compat
local Coords = B.Coords

local Facts = {}
B.Facts = Facts

Facts.VERSION = 1
Facts.NIGHT = { from = 21, to = 6 } -- server hours counted as night (assumed, library.md)
-- auras that make the character invisible to mobs (mage Invisibility, the two potions; assumed)
Facts.INVISIBILITY = { [66] = true, [32612] = true, [3680] = true, [11392] = true }

local states = {} -- name -> read()
local happenings = {} -- name -> { events = { [event] = fn(...) -> payload or nil }, hook = fn }
local watchers = {} -- name -> array of { id, owner, fn, active }
local fakes = {} -- name -> value (a state faked by the injector)
local last = {} -- name -> { payload, at }
local uses = {} -- event -> number of watched happenings that need it
local frame
local nextId = 0

local function now()
  return Compat.ServerTime()
end

-- ---------------------------------------------------------------------------------------------
-- Registration (Core's own; a tale or an app never defines a fact)
-- ---------------------------------------------------------------------------------------------

function Facts.DefineState(name, read)
  states[name] = read
end

function Facts.DefineHappening(name, def)
  happenings[name] = def
end

-- ---------------------------------------------------------------------------------------------
-- States: read on demand, faked by the injector
-- ---------------------------------------------------------------------------------------------

-- The state fact `name` now, or nil when the client cannot tell; a faked value wins. A keyed state
-- (reputation: one faction) takes the key; its fake is a table by key.
function Facts.Get(name, key)
  if fakes[name] ~= nil then
    if key ~= nil then
      return type(fakes[name]) == "table" and fakes[name][key] or nil
    end
    return fakes[name]
  end
  local read = states[name]
  if not read then
    return nil
  end
  local ok, value = pcall(read, key)
  if ok then
    return value
  end
  return nil
end

-- The injector: `value` replaces the state until Fake(name, nil).
function Facts.Fake(name, value)
  fakes[name] = value
end

function Facts.IsFaked(name)
  return fakes[name] ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Happenings: events turned into payloads, handed to the watchers
-- ---------------------------------------------------------------------------------------------

-- Events an addon may not register on every client (the client answers ADDON_ACTION_FORBIDDEN,
-- which no pcall catches): the capability flag that allows each.
Facts.RESTRICTED = { COMBAT_LOG_EVENT_UNFILTERED = "CombatLog" }

-- True when this client lets an addon register the event.
function Facts.Allowed(event)
  local flag = Facts.RESTRICTED[event]
  return flag == nil or Compat.Has[flag] == true
end

local function listen(event, on)
  if not Facts.Allowed(event) then
    return
  end
  local n = (uses[event] or 0) + (on and 1 or -1)
  uses[event] = n > 0 and n or nil
  if not frame then
    return
  end
  if on and n == 1 then
    pcall(frame.RegisterEvent, frame, event) -- a client without the event loses the fact only
  elseif not on and n == 0 then
    pcall(frame.UnregisterEvent, frame, event)
  end
end

local function dispatch(event, ...)
  for name, def in pairs(happenings) do
    local fn = def.events and def.events[event]
    if fn and watchers[name] and #watchers[name] > 0 then
      local ok, payload = pcall(fn, ...)
      if ok and payload then
        Facts.Emit(name, payload)
      end
    end
  end
end

local function ensureFrame()
  if frame then
    return
  end
  frame = CreateFrame("Frame")
  frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(event, ...)
  end)
  for event in pairs(uses) do
    pcall(frame.RegisterEvent, frame, event)
  end
end

-- False for a happening whose every event this client forbids (the combat log's damage, healing
-- and deaths on retail 12.x): watching it is allowed, it never fires; its facts stay unknown.
function Facts.Available(name)
  local def = happenings[name]
  if not def then
    return false
  end
  if def.hook then
    return true
  end
  for event in pairs(def.events or {}) do
    if Facts.Allowed(event) then
      return true
    end
  end
  return false
end

-- Raises the happening `name` with `payload` for every watcher; the injector's entry too.
function Facts.Emit(name, payload)
  last[name] = { payload = payload, at = now() }
  local list = watchers[name]
  if not list then
    return
  end
  for i = 1, #list do
    local w = list[i]
    if w.active then
      ns.safecall(w.owner, w.fn, w.owner, payload, name)
    end
  end
end

-- fn(owner, payload, name) whenever the happening is raised; -> an id for Unwatch. Registers the
-- happening's events with the first watcher.
function Facts.Watch(owner, name, fn)
  local def = happenings[name]
  if not def then
    error(("Facts.Watch: unknown happening %q"):format(tostring(name)), 2)
  end
  local list = watchers[name]
  if not list then
    list = {}
    watchers[name] = list
  end
  if #list == 0 then
    ensureFrame()
    for event in pairs(def.events or {}) do
      listen(event, true)
    end
    if def.hook and not def.hooked then
      def.hooked = true
      pcall(def.hook)
    end
  end
  nextId = nextId + 1
  local w = { id = nextId, owner = owner, fn = fn, active = true, name = name }
  list[#list + 1] = w
  return w.id
end

local function drop(name, keep)
  local list = watchers[name]
  if not list then
    return
  end
  local kept = {}
  for _, w in ipairs(list) do
    if keep(w) then
      kept[#kept + 1] = w
    else
      w.active = false
    end
  end
  watchers[name] = kept
  if #kept == 0 then
    for event in pairs(happenings[name].events or {}) do
      listen(event, false)
    end
  end
end

function Facts.Unwatch(id)
  for name in pairs(watchers) do
    drop(name, function(w)
      return w.id ~= id
    end)
  end
end

function Facts.UnwatchAll(owner)
  for name in pairs(watchers) do
    drop(name, function(w)
      return w.owner ~= owner
    end)
  end
end

-- True while the fact layer listens to the client event (the tests' check of §4.7).
function Facts.IsListening(event)
  return uses[event] ~= nil
end

-- The last payload of a happening and when it was raised, or nil.
function Facts.Last(name)
  local l = last[name]
  if l then
    return l.payload, l.at
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The inspector
-- ---------------------------------------------------------------------------------------------

function Facts.Names()
  local out = { states = {}, happenings = {} }
  for name in pairs(states) do
    out.states[#out.states + 1] = name
  end
  for name in pairs(happenings) do
    out.happenings[#out.happenings + 1] = name
  end
  table.sort(out.states)
  table.sort(out.happenings)
  return out
end

-- { [state] = value, faked = { [state] = true }, last = { [happening] = { payload, at } } }
function Facts.Report()
  local out = { faked = {}, last = {} }
  for name in pairs(states) do
    out[name] = Facts.Get(name)
    if fakes[name] ~= nil then
      out.faked[name] = true
    end
  end
  for name, l in pairs(last) do
    out.last[name] = { payload = l.payload, at = l.at }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------
-- The states (library.md §4)
-- ---------------------------------------------------------------------------------------------

Facts.DefineState("player", function()
  local f = Compat.GetPlayerFacts() or {}
  local g = Compat.GroupUnits() or {}
  return {
    level = f.level,
    faction = f.faction,
    classID = f.classID,
    raceID = f.raceID,
    class = f.class,
    race = f.race,
    health = f.health,
    money = Compat.GetMoney(),
    group = #g + 1,
    guild = Compat.InGuild(),
    dead = Compat.GetDeathState(),
  }
end)

Facts.DefineState("state", function()
  local s = Compat.PlayerState() or {}
  local auras = Compat.PlayerAuras() or {}
  local invisible = false
  for id in pairs(auras) do
    if Facts.INVISIBILITY[id] then
      invisible = true
    end
  end
  local speed, mounted, onTaxi = Compat.GetMoveSpeed()
  s.invisible = invisible
  s.mounted = s.mounted or mounted or false
  s.onTaxi = s.onTaxi or onTaxi or false
  s.moving = speed ~= nil and speed > 0
  s.dead = Compat.GetDeathState()
  return s
end)

Facts.DefineState("auras", function()
  return Compat.PlayerAuras()
end)

Facts.DefineState("position", function()
  local continent, wx, wy, uiMapID, x, y = Coords.Player()
  local s = Compat.PlayerState() or {}
  local facing = Compat.GetPlayerFacing()
  return {
    map = continent,
    wx = wx,
    wy = wy,
    uiMapID = uiMapID,
    x = x,
    y = y,
    zone = type(GetZoneText) == "function" and GetZoneText() or nil,
    subzone = type(GetSubZoneText) == "function" and GetSubZoneText() or nil,
    indoors = s.indoors,
    instance = type(IsInInstance) == "function" and (IsInInstance()) or false,
    facing = facing and math.deg(facing) or nil, -- degrees, 0 north, counter-clockwise
  }
end)

Facts.DefineState("target", function()
  return Compat.UnitFacts("target")
end)

Facts.DefineState("mouseover", function()
  return Compat.UnitFacts("mouseover")
end)

Facts.DefineState("time", function()
  local t = now()
  local d = date("*t", t)
  local hour = d and d.hour or nil
  local night = hour ~= nil and (hour >= Facts.NIGHT.from or hour < Facts.NIGHT.to)
  return {
    server = t,
    hour = hour,
    minute = d and d.min,
    weekday = d and d.wday,
    month = d and d.month,
    day = d and d.day,
    night = night,
  }
end)

Facts.DefineState("bags", function()
  local out = {}
  for _, slot in ipairs(Compat.GetBagItems() or {}) do
    if slot.itemID then
      out[slot.itemID] = (out[slot.itemID] or 0) + (slot.count or 1)
    end
  end
  return out
end)

Facts.DefineState("equipped", function()
  return Compat.EquippedItems()
end)

-- The quests the character has turned in: { [questID] = true }
Facts.DefineState("quests", function()
  local out = {}
  for _, id in ipairs(Compat.GetCompletedQuestIDs() or {}) do
    out[id] = true
  end
  return out
end)

-- ---------------------------------------------------------------------------------------------
-- The happenings (library.md §4): each event handler gives the payload or nil
-- ---------------------------------------------------------------------------------------------

local function playerGUID()
  return type(UnitGUID) == "function" and Compat.Plain(UnitGUID("player")) or nil
end

local function playerName()
  return type(UnitName) == "function" and Compat.Plain(UnitName("player")) or nil
end

local function shortName(name)
  return type(name) == "string" and name:match("^([^%-]+)") or name
end

-- The chat line is the player's own: by GUID when the event carries one, else by name.
local function ownLine(sender, guid)
  local mine = playerGUID()
  if guid and mine then
    return guid == mine
  end
  return shortName(sender) == playerName()
end

local function words(text)
  local out = {}
  for w in tostring(text or ""):lower():gmatch("%a+") do
    out[#out + 1] = w
  end
  return out
end

local function ref(unit)
  local guid = type(UnitGUID) == "function" and Compat.Plain(UnitGUID(unit)) or nil
  return Compat.EntityFromGUID(guid)
end

local CHAT = {
  CHAT_MSG_SAY = "say",
  CHAT_MSG_YELL = "yell",
  CHAT_MSG_EMOTE = "emote",
  CHAT_MSG_PARTY = "party",
  CHAT_MSG_PARTY_LEADER = "party",
  CHAT_MSG_RAID = "raid",
  CHAT_MSG_GUILD = "guild",
  CHAT_MSG_WHISPER_INFORM = "whisper",
}
local sayEvents = {}
for event, channel in pairs(CHAT) do
  sayEvents[event] = function(text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not ownLine(sender, guid) then
      return nil
    end
    return { channel = channel, text = text, words = words(text), target = ref("target") }
  end
end
Facts.DefineHappening("say", { events = sayEvents })

-- Gestures: the token from the hooked DoEmote (locale-free), the target as an entity
Facts.DefineHappening("emote", {
  events = {},
  hook = function()
    if type(DoEmote) == "function" and type(hooksecurefunc) == "function" then
      hooksecurefunc("DoEmote", function(token, target)
        Facts.Emit("emote", {
          token = tostring(token or ""):upper(),
          target = target,
          ref = ref(target or "target"),
        })
      end)
    end
  end,
})

-- Another player's gesture at the character: counted, never who (CLAUDE.md §8)
Facts.DefineHappening("received", {
  events = {
    CHAT_MSG_TEXT_EMOTE = function(text, sender, _, _, _, _, _, _, _, _, _, guid)
      if ownLine(sender, guid) then
        return nil
      end
      local me = playerName()
      local t = tostring(text or "")
      if not (t:find(" you%f[%A]") or (me and t:find(me, 1, true))) then
        return nil
      end
      return { text = t }
    end,
  },
})

local MONSTER = {
  CHAT_MSG_MONSTER_SAY = "say",
  CHAT_MSG_MONSTER_YELL = "yell",
  CHAT_MSG_MONSTER_EMOTE = "emote",
  CHAT_MSG_MONSTER_WHISPER = "whisper",
}
local heardEvents = {}
for event, channel in pairs(MONSTER) do
  heardEvents[event] = function(text, sender, _, _, _, _, _, _, _, _, _, guid)
    return {
      channel = channel,
      text = text,
      words = words(text),
      npc = sender,
      ref = Compat.EntityFromGUID(guid),
    }
  end
end
Facts.DefineHappening("heard", { events = heardEvents })

-- Loot: the slots are read when the window opens, a slot cleared is an item looted
local lootSlots, lootFishing = {}, false
local function readLoot()
  local slots, fishing = Compat.LootSlots()
  lootSlots, lootFishing = {}, fishing or false
  for _, s in ipairs(slots or {}) do
    lootSlots[s.slot] = s
  end
  return nil
end
Facts.DefineHappening("loot", {
  events = {
    LOOT_READY = readLoot,
    LOOT_OPENED = readLoot,
    LOOT_SLOT_CLEARED = function(slot)
      local s = lootSlots[slot]
      if not s then
        return nil
      end
      lootSlots[slot] = nil
      return { item = s.item, count = s.count, from = s.from, fishing = lootFishing }
    end,
  },
})

-- The combat log: kills by the character or the group, damage dealt, healing to an NPC
local function byWhom(sourceGUID)
  if not sourceGUID then
    return nil
  end
  if sourceGUID == playerGUID() then
    return "me"
  end
  if type(UnitGUID) == "function" and Compat.Plain(UnitGUID("pet")) == sourceGUID then
    return "me"
  end
  for _, m in ipairs(Compat.GroupUnits() or {}) do
    if type(UnitGUID) == "function" and Compat.Plain(UnitGUID(m.unit)) == sourceGUID then
      return "group"
    end
  end
  return nil
end

local function combatPayload()
  local e = Compat.CombatEvent()
  if not e then
    return nil
  end
  local by = byWhom(e.sourceGUID)
  local target = Compat.EntityFromGUID(e.destGUID)
  if e.subevent == "UNIT_DIED" and target then
    return "died", { ref = target }
  elseif by == "me" and target and e.subevent:find("_DAMAGE$") then
    return "damage", { ref = target, amount = e.amount, spell = e.spellID }
  elseif by == "me" and target and e.subevent == "SPELL_HEAL" then
    return "healed", { ref = target, amount = e.amount, spell = e.spellID }
  end
  return nil
end

-- Kills: PARTY_KILL (attacker, victim) fires for the kills of the character and its group, also
-- where the combat log is closed (retail 12.x; Total RP 3: Extended does the same). The GUIDs may
-- be secret: then the victim or the killer is unknown.
Facts.DefineHappening("kill", {
  events = {
    PARTY_KILL = function(attackerGUID, targetGUID)
      local attacker, target = Compat.Plain(attackerGUID), Compat.Plain(targetGUID)
      return { ref = Compat.EntityFromGUID(target), by = byWhom(attacker) }
    end,
  },
})

-- Deaths, damage and healing need the combat log: only where an addon may read it
-- (Compat.Has.CombatLog; measured forbidden on retail 27.10.2026).
for _, name in ipairs({ "died", "damage", "healed" }) do
  Facts.DefineHappening(name, {
    events = {
      COMBAT_LOG_EVENT_UNFILTERED = function()
        local kind, payload = combatPayload()
        if kind == name then
          return payload
        end
        return nil
      end,
    },
  })
end

Facts.DefineHappening("read", {
  events = {
    ITEM_TEXT_READY = function()
      local t = Compat.ItemText()
      if not t then
        return nil
      end
      return { item = t.item, text = t.text, page = t.page, words = words(t.text) }
    end,
  },
})

local function here()
  local p = Facts.Get("position")
  return p and { map = p.map, wx = p.wx, wy = p.wy } or nil
end

Facts.DefineHappening("mail", {
  events = {
    MAIL_SHOW = function()
      return { opened = true, at = here() }
    end,
    MAIL_INBOX_UPDATE = function()
      return { received = true }
    end,
    MAIL_SEND_SUCCESS = function()
      return { sent = true }
    end,
  },
})

local OPENED = {
  GOSSIP_SHOW = "gossip",
  QUEST_GREETING = "quest",
  QUEST_DETAIL = "quest",
  MERCHANT_SHOW = "vendor",
  TRAINER_SHOW = "trainer",
  TAXIMAP_OPENED = "taxi",
  BANKFRAME_OPENED = "bank",
  AUCTION_HOUSE_SHOW = "auction",
  PET_STABLE_SHOW = "stable",
  MAIL_SHOW = "mail",
}
local openedEvents = {}
for event, kind in pairs(OPENED) do
  openedEvents[event] = function()
    return { kind = kind, ref = ref("npc") or ref("target") }
  end
end
Facts.DefineHappening("opened", { events = openedEvents })

-- Casts: the target name travels with UNIT_SPELLCAST_SENT, the success with SUCCEEDED
local castTargets = {}
Facts.DefineHappening("cast", {
  events = {
    UNIT_SPELLCAST_SENT = function(unit, target, castGUID, spellID)
      if unit == "player" then
        castTargets[castGUID or spellID or 0] = target
      end
      return nil
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
      if unit ~= "player" then
        return nil
      end
      local target = castTargets[castGUID or 0] or castTargets[spellID or 0]
      castTargets[castGUID or 0], castTargets[spellID or 0] = nil, nil
      return { spell = spellID, target = target, ref = ref("target") }
    end,
  },
})

Facts.DefineHappening("quest", {
  events = {
    QUEST_ACCEPTED = function(a, b)
      return { id = type(b) == "number" and b or a, accepted = true }
    end,
    QUEST_TURNED_IN = function(id)
      return { id = id, turned_in = true }
    end,
    QUEST_REMOVED = function(id)
      return { id = id, removed = true }
    end,
  },
})

Facts.DefineHappening("level", {
  events = {
    PLAYER_LEVEL_UP = function(level)
      return { level = level }
    end,
  },
})

Facts.DefineHappening("death", {
  events = {
    PLAYER_DEAD = function()
      return { dead = true, at = here() }
    end,
    PLAYER_ALIVE = function()
      return { alive = true }
    end,
    PLAYER_UNGHOST = function()
      return { alive = true }
    end,
  },
})

local function zonePayload()
  local p = Facts.Get("position")
  return { zone = p and p.zone, subzone = p and p.subzone, indoors = p and p.indoors, map = p and p.map }
end
Facts.DefineHappening("zone", {
  events = {
    ZONE_CHANGED_NEW_AREA = zonePayload,
    ZONE_CHANGED = zonePayload,
    ZONE_CHANGED_INDOORS = zonePayload,
    PLAYER_UPDATE_RESTING = zonePayload,
  },
})

Facts.DefineHappening("combat", {
  events = {
    PLAYER_REGEN_DISABLED = function()
      return { entered = true }
    end,
    PLAYER_REGEN_ENABLED = function()
      return { left = true }
    end,
  },
})

Facts.DefineHappening("moved", {
  events = {
    PLAYER_STARTED_MOVING = function()
      return { moving = true }
    end,
    PLAYER_STOPPED_MOVING = function()
      return { moving = false, at = here() }
    end,
  },
})

local lastMoney
Facts.DefineHappening("money", {
  events = {
    PLAYER_MONEY = function()
      local copper = Compat.GetMoney()
      local delta = lastMoney and copper and (copper - lastMoney) or nil
      lastMoney = copper
      return { copper = copper, delta = delta }
    end,
  },
})

Facts.DefineHappening("screenshot", {
  events = {
    SCREENSHOT_SUCCEEDED = function()
      return { at = here() }
    end,
  },
})

Facts.DefineHappening("target", {
  events = {
    PLAYER_TARGET_CHANGED = function()
      return { unit = Compat.UnitFacts("target") }
    end,
    UPDATE_MOUSEOVER_UNIT = function()
      return { unit = Compat.UnitFacts("mouseover"), mouseover = true }
    end,
  },
})

-- A creature turning to the character (UNIT_TARGET on the target and the nameplates)
Facts.DefineHappening("targeted", {
  events = {
    UNIT_TARGET = function(unit)
      if unit == "player" then
        return nil
      end
      local u = Compat.UnitFacts(unit)
      if not (u and u.targetsPlayer) then
        return nil
      end
      return { unit = unit, ref = u.ref }
    end,
  },
})

Facts.DefineHappening("bags", {
  events = {
    BAG_UPDATE_DELAYED = function()
      return { changed = true }
    end,
  },
})

Facts.DefineHappening("equipment", {
  events = {
    PLAYER_EQUIPMENT_CHANGED = function(slot)
      return { slot = slot }
    end,
  },
})

Facts.DefineHappening("xp", {
  events = {
    PLAYER_XP_UPDATE = function()
      return { gained = true }
    end,
  },
})

Facts.DefineHappening("learned", {
  events = {
    LEARNED_SPELL_IN_TAB = function(spellID)
      return type(spellID) == "number" and { spell = "spell:" .. spellID } or nil
    end,
  },
})

-- The group and the guild changed (the `player` state says how)
local function social()
  return { changed = true }
end
Facts.DefineHappening("social", {
  events = { GROUP_ROSTER_UPDATE = social, PLAYER_GUILD_UPDATE = social },
})

-- The game's own lines turned into patterns: "Discovered %s: %d experience gained" ->
-- "^Discovered (.+): %d+ experience gained$". The client's global strings are in its language; the
-- English ones stand in where a client has none (all assumed, library.md 8.4).
local function linePattern(global, english)
  local s = type(_G[global]) == "string" and _G[global] or english
  s = s:gsub("%%%d%$", "%%") -- "%1$s" -> "%s"
  s = s:gsub("%%s", "\1"):gsub("%%d", "\2")
  s = s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  s = s:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
  return "^" .. s .. "$"
end
Facts.linePattern = linePattern

local function itemOf(link)
  local id = type(link) == "string" and link:match("item:(%d+)")
  return id and ("item:" .. id) or nil
end

-- Exploration: the system line of a first discovery, with the area's name
local DISCOVERED = {
  linePattern("ERR_ZONE_EXPLORED_XP", "Discovered %s: %d experience gained"),
  linePattern("ERR_ZONE_EXPLORED", "Discovered: %s"),
}
local function discovered(...)
  for i = 1, select("#", ...) do
    local line = select(i, ...)
    if type(line) == "string" then
      for _, pat in ipairs(DISCOVERED) do
        local name = line:match(pat)
        if name then
          local p = Facts.Get("position")
          return { name = name, zone = p and p.uiMapID and ("zone:" .. p.uiMapID) or nil }
        end
      end
    end
  end
  return nil
end
Facts.DefineHappening("discovered", {
  events = { CHAT_MSG_SYSTEM = discovered, UI_INFO_MESSAGE = discovered },
})

-- Reputation and skills are states asked of the client; the happenings say when to look again.
Facts.DefineState("reputation", function(faction)
  local id = type(faction) == "string" and tonumber(faction:match("(%d+)$")) or tonumber(faction)
  return id and Compat.GetReputation(id) or nil
end)
local function changed()
  return { changed = true }
end
Facts.DefineHappening("reputation", {
  events = { UPDATE_FACTION = changed, CHAT_MSG_COMBAT_FACTION_CHANGE = changed },
})

Facts.DefineState("professions", function()
  return Compat.GetProfessions()
end)
Facts.DefineHappening("skills", {
  events = { SKILL_LINES_CHANGED = changed, CHAT_MSG_SKILL = changed },
})

-- PvP: the flag going up, an honourable kill, entering a battleground
local pvpFlagged, inBattleground = false, false
Facts.DefineHappening("pvp", {
  events = {
    PLAYER_FLAGS_CHANGED = function(unit)
      local flagged = Compat.IsPvPFlagged()
      local rose = flagged and not pvpFlagged and (unit == nil or unit == "player")
      pvpFlagged = flagged
      return rose and { kind = "flagged" } or nil
    end,
    CHAT_MSG_COMBAT_HONOR_GAIN = function()
      return { kind = "honor_kill" }
    end,
    ZONE_CHANGED_NEW_AREA = function()
      local inside = Compat.InstanceType() == "pvp"
      local entered = inside and not inBattleground
      inBattleground = inside
      return entered and { kind = "battleground" } or nil
    end,
  },
})

-- Duels: the end, then the system line naming the winner (compared with the character's own name
-- only; no other player's name is kept, CLAUDE.md §8)
local DUEL_WON = linePattern("DUEL_WINNER_KNOCKOUT", "%1$s has defeated %2$s in a duel")
local DUEL_FLED = linePattern("DUEL_WINNER_RETREAT", "%2$s has fled from %1$s in a duel")
Facts.DefineHappening("duel", {
  events = {
    DUEL_FINISHED = function()
      return { finished = true }
    end,
    CHAT_MSG_SYSTEM = function(line)
      if type(line) ~= "string" then
        return nil
      end
      local me = playerName()
      local winner = line:match(DUEL_WON)
      if not winner then
        local _, w = line:match(DUEL_FLED) -- "%2$s has fled from %1$s": the first capture is the loser
        winner = w
      end
      if not (winner and me) then
        return nil
      end
      return { result = shortName(winner) == me and "won" or "lost" }
    end,
  },
})

-- A trade done: the client's info line
local function tradeDone(...)
  local done = type(_G.ERR_TRADE_COMPLETE) == "string" and _G.ERR_TRADE_COMPLETE or "Trade complete."
  for i = 1, select("#", ...) do
    if select(i, ...) == done then
      return { traded = true }
    end
  end
  return nil
end
Facts.DefineHappening("traded", { events = { UI_INFO_MESSAGE = tradeDone, CHAT_MSG_SYSTEM = tradeDone } })

-- Pets and mounts: a pet that appears after Tame Beast is tamed; any pet is summoned; a mount going
-- up is summoned too
Facts.TAME_BEAST = 1515
Facts.TAME_SECONDS = 30
local tameAt, wasMounted = nil, false
local function petPayload(kind)
  if not (type(UnitExists) == "function" and Compat.Plain(UnitExists("pet"))) then
    return nil
  end
  return { kind = kind, ref = ref("pet") }
end
Facts.DefineHappening("tamed", {
  events = {
    UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
      if unit == "player" and spellID == Facts.TAME_BEAST then
        tameAt = GetTime()
      end
      return nil
    end,
    UNIT_PET = function(unit)
      if unit ~= "player" or not (tameAt and GetTime() - tameAt <= Facts.TAME_SECONDS) then
        return nil
      end
      tameAt = nil
      return petPayload("pet")
    end,
  },
})
local function mountUp()
  local mounted = Compat.PlayerState().mounted == true
  local rose = mounted and not wasMounted
  wasMounted = mounted
  return rose and { kind = "mount" } or nil
end
Facts.DefineHappening("summoned", {
  events = {
    UNIT_PET = function(unit)
      return unit == "player" and petPayload("pet") or nil
    end,
    PLAYER_MOUNT_DISPLAY_CHANGED = mountUp,
    COMPANION_UPDATE = mountUp,
  },
})

-- Travel: a taxi from losing control on it to getting it back. A jump of the character (a loading
-- screen, or a new zone far away right after a spell) is a hearth after a hearth spell, a portal
-- after any other spell or into or out of an instance, else a ferry (boats and zeppelins carry the
-- character through a loading screen).
Facts.HEARTH_SPELLS = { [8690] = true, [556] = true } -- the Hearthstone, Astral Recall
Facts.JUMP_YARDS = 300
Facts.CAST_SECONDS = 20
Facts.JUMP_QUIET = 10 -- seconds after a jump in which the same jump's other events are ignored
local taxiFrom, lastPlace, lastCast, leaving, jumpedAt
local function jump(from, loading)
  local to = here()
  lastPlace = to or lastPlace
  if not (from and to) or taxiFrom or (jumpedAt and GetTime() - jumpedAt < Facts.JUMP_QUIET) then
    return nil
  end
  local far = from.map ~= to.map
  if not far then
    local dx, dy = (from.wx or 0) - (to.wx or 0), (from.wy or 0) - (to.wy or 0)
    far = math.sqrt(dx * dx + dy * dy) > Facts.JUMP_YARDS
  end
  local cast = lastCast and GetTime() - lastCast.at <= Facts.CAST_SECONDS and lastCast or nil
  if not far or not (cast or loading) then
    return nil
  end
  local kind
  if cast then
    kind = Facts.HEARTH_SPELLS[cast.spell] and "hearth" or "portal"
  else
    kind = Compat.InstanceType() ~= "none" and "portal" or "ferry"
  end
  lastCast, jumpedAt = nil, GetTime()
  return { kind = kind, from = from, to = to }
end
Facts.DefineHappening("travel", {
  events = {
    PLAYER_CONTROL_LOST = function()
      if Compat.PlayerState().onTaxi then
        taxiFrom = here()
      end
      return nil
    end,
    PLAYER_CONTROL_GAINED = function()
      if not taxiFrom then
        return nil
      end
      local from, to = taxiFrom, here()
      taxiFrom, lastPlace = nil, to
      return { kind = "taxi", from = from, to = to }
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
      if unit == "player" then
        lastCast = { spell = spellID, at = GetTime() }
        lastPlace = here() or lastPlace
      end
      return nil
    end,
    PLAYER_LEAVING_WORLD = function()
      leaving = here() or lastPlace
      return nil
    end,
    PLAYER_ENTERING_WORLD = function()
      local from = leaving
      leaving = nil
      return jump(from, true)
    end,
    ZONE_CHANGED_NEW_AREA = function()
      return jump(lastPlace, false)
    end,
    PLAYER_STOPPED_MOVING = function()
      lastPlace = here() or lastPlace
      return nil
    end,
  },
})

-- At a merchant: the bags and the money before and after each change. More of an item for less
-- money is bought, less of it for more money is sold; money gone with nothing changed in the bags
-- after the gear's durability rose is a repair. One payload per item: { kind, item, count, npc }.
local shop
local function bagCounts()
  local out = {}
  for _, slot in ipairs(Compat.GetBagItems() or {}) do
    if slot.itemID then
      out[slot.itemID] = (out[slot.itemID] or 0) + (slot.count or 1)
    end
  end
  return out
end
local function snapshot()
  shop = shop or {}
  shop.bags, shop.money, shop.mended = bagCounts(), Compat.GetMoney(), false
end
-- The money and the bags change in separate events: a trade is read once both have moved (a
-- repair once the money and the durability have).
local function trade()
  if not shop then
    return nil
  end
  local bags, money = bagCounts(), Compat.GetMoney() or 0
  local spent = (shop.money or 0) - money
  local deltas = {}
  for id, n in pairs(bags) do
    if n ~= (shop.bags[id] or 0) then
      deltas[id] = n - (shop.bags[id] or 0)
    end
  end
  for id, n in pairs(shop.bags) do
    if bags[id] == nil then
      deltas[id] = -n
    end
  end
  if next(deltas) == nil then
    if spent > 0 and shop.mended then
      Facts.Emit("merchant", { kind = "repaired", npc = shop.npc })
      snapshot()
    end
    return nil -- else the bags have not caught up yet
  end
  if spent == 0 then
    return nil -- the money has not caught up yet (or the bags moved for another reason)
  end
  for id, delta in pairs(deltas) do
    if delta > 0 and spent > 0 then
      Facts.Emit("merchant", { kind = "bought", item = "item:" .. id, count = delta, npc = shop.npc })
    elseif delta < 0 and spent < 0 then
      Facts.Emit("merchant", { kind = "sold", item = "item:" .. id, count = -delta, npc = shop.npc })
    end
  end
  snapshot()
  return nil
end
Facts.DefineHappening("merchant", {
  events = {
    MERCHANT_SHOW = function()
      snapshot()
      shop.npc = ref("npc")
      return nil
    end,
    MERCHANT_CLOSED = function()
      shop = nil
      return nil
    end,
    UPDATE_INVENTORY_DURABILITY = function()
      if shop then
        shop.mended = true
      end
      return trade()
    end,
    BAG_UPDATE_DELAYED = trade,
    PLAYER_MONEY = trade,
  },
})

-- Crafting: the client's loot line of a thing the character made
local CREATED = {
  linePattern("LOOT_ITEM_CREATED_SELF_MULTIPLE", "You create: %sx%d."),
  linePattern("LOOT_ITEM_CREATED_SELF", "You create: %s."),
}
Facts.DefineHappening("crafted", {
  events = {
    CHAT_MSG_LOOT = function(line)
      if type(line) ~= "string" then
        return nil
      end
      for _, pat in ipairs(CREATED) do
        local link, n = line:match(pat)
        if link and itemOf(link) then
          return { item = itemOf(link), count = tonumber(n) or 1 }
        end
      end
      return nil
    end,
  },
})

-- An item used from the bags (the hook) with the place; the engine also knows an item by the spell
-- its use casts (`cast`, Compat.GetItemSpell)
Facts.DefineHappening("used", {
  events = {},
  hook = function()
    Compat.HookItemUse(function(itemID)
      Facts.Emit("used", { item = "item:" .. itemID, at = here() })
    end)
  end,
})

-- ---------------------------------------------------------------------------------------------
-- The service (core-contracts §11)
-- ---------------------------------------------------------------------------------------------

B:ProvideService(ns.coreOwner, "facts", Facts)
