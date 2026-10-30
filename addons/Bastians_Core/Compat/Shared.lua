-- Compat layer "shared": capability flags and wrappers over APIs identical in the forever and live docs.
local _, ns = ...
local Compat = ns.Compat
local define, note = ns.Compat.define, ns.Compat.note
local Has = Compat.Has

local function has(tbl, fn)
  return type(tbl) == "table" and type(tbl[fn]) == "function"
end

-- Secret values (the retail family's restriction; Forever 70532 has `issecretvalue` and the
-- C_Secrets checks, probe of 23.10.2026): some APIs hand back a number or string an addon may not
-- compare, compute with or index, and an attempt raises an error (244 times a session from
-- GetUnitSpeed("player") in Route, ). Such a value is unknown to us: nil.
function Compat.Plain(value)
  local check = rawget(_G, "issecretvalue")
  if value ~= nil and check and check(value) then
    return nil
  end
  return value
end
local plain = Compat.Plain

-- Capability flags: apps read these instead of the client name (core-contracts §10).
Has.SettingsAPI = has(Settings, "RegisterCanvasLayoutCategory")
Has.TooltipDataProcessor = has(TooltipDataProcessor, "AddTooltipPostCall")
  and type(Enum) == "table"
  and type(Enum.TooltipDataType) == "table"
Has.ModernQuestLog = has(C_QuestLog, "GetInfo")
Has.ReplicateAH = has(C_AuctionHouse, "ReplicateItems")
-- The combat log (COMBAT_LOG_EVENT_UNFILTERED) for an addon: registering it is forbidden on retail
-- 12.x (measured 27.10.2026, 12.1.5.70575: ADDON_ACTION_FORBIDDEN on RegisterEvent); unknown on
-- Forever, off until the probe shows it works (forever-api.md). Core's fact layer reads it only
-- when true.
Has.CombatLog = false
Has.WorldPosFromMapPos = has(C_Map, "GetWorldPosFromMapPos")
Has.MerchantAPI = has(C_MerchantFrame, "GetItemInfo")
Has.TrainerType = has(C_Trainer, "GetTrainerType") -- Forever only in the docs (ADR 0009)

-- ---------------------------------------------------------------------------------------------
-- Addons (C_AddOns: 29 functions, identical on both clients)
-- ---------------------------------------------------------------------------------------------

-- C_AddOns.GetAddOnEnableState(name, character) in both P1 dumps (0 none, 1 some, 2 all; the
-- argument order of the namespace, the legacy global took the character first and is absent).
define("shared", "IsAddOnEnabled", function(name)
  if not C_AddOns.DoesAddOnExist(name) then
    return false
  end
  if type(C_AddOns.GetAddOnEnableState) ~= "function" then
    return true
  end
  local state = C_AddOns.GetAddOnEnableState(name, UnitName("player"))
  return type(state) ~= "number" or state > 0
end)

define("shared", "GetAddOnInfo", function(name)
  if not C_AddOns.DoesAddOnExist(name) then
    return nil
  end
  local realName, title, notes, loadable, reason = C_AddOns.GetAddOnInfo(name)
  return {
    name = realName,
    title = title,
    notes = notes,
    loadable = loadable,
    reason = reason,
    loaded = (C_AddOns.IsAddOnLoaded(name)),
    loadOnDemand = C_AddOns.IsAddOnLoadOnDemand(name),
  }
end)

-- Loading in combat is deferred to PLAYER_REGEN_ENABLED (CLAUDE.md golden rule 6).
local pendingLoads = {}
local regenFrame

local function flushPending()
  regenFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
  local list = pendingLoads
  pendingLoads = {}
  for _, p in ipairs(list) do
    Compat.LoadAddOn(p.name, p.onLoaded)
  end
end

define("shared", "LoadAddOn", function(name, onLoaded)
  if not C_AddOns.DoesAddOnExist(name) then
    return "missing", "MISSING"
  end
  if C_AddOns.IsAddOnLoaded(name) then
    if onLoaded then
      onLoaded(name)
    end
    return "loaded"
  end
  if InCombatLockdown() then
    pendingLoads[#pendingLoads + 1] = { name = name, onLoaded = onLoaded }
    if not regenFrame then
      regenFrame = CreateFrame("Frame")
      regenFrame:SetScript("OnEvent", flushPending)
    end
    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    return "deferred"
  end
  local ok, reason = C_AddOns.LoadAddOn(name)
  if not ok then
    return "failed", reason
  end
  ns.B.Deliver() -- the addon's generated files queue their registrations (Init.lua)
  if onLoaded then
    onLoaded(name)
  end
  return "loaded"
end)

-- ---------------------------------------------------------------------------------------------
-- Items (C_Item.GetItemInfo; GetItemInfo verified on Forever, forever-api.md)
-- ---------------------------------------------------------------------------------------------

define("shared", "GetItemInfo", function(idOrLink)
  local name, link, quality, level, minLevel, class, subclass, stack, equipLoc, icon, sell, classID, subID =
    C_Item.GetItemInfo(idOrLink)
  if not name then
    return nil
  end
  return {
    id = tonumber(idOrLink) or tonumber(string.match(link or "", "item:(%d+)")),
    name = name,
    link = link,
    quality = quality,
    level = level,
    minLevel = minLevel,
    class = class,
    subclass = subclass,
    stack = stack,
    equipLoc = equipLoc,
    icon = icon,
    sellPrice = sell,
    classID = classID,
    subclassID = subID,
  }
end)

-- Item stats (C_Item.GetItemStats in both P1 dumps; the legacy global GetItemStats is Forever's
-- fallback). The keys are the client's ITEM_MOD_* names, the values the amounts; nil while the item
-- is not cached or no API answers (S7, reward comparison).
define("shared", "GetItemStats", function(idOrLink)
  local link = idOrLink
  if type(idOrLink) == "number" then
    link = "item:" .. idOrLink
  end
  local stats
  if has(C_Item, "GetItemStats") then
    note("GetItemStats", "C_Item.GetItemStats")
    stats = C_Item.GetItemStats(link)
  elseif type(_G.GetItemStats) == "function" then
    note("GetItemStats", "GetItemStats")
    stats = _G.GetItemStats(link)
  end
  if type(stats) ~= "table" then
    return nil
  end
  local out = {}
  for key, amount in pairs(stats) do
    if type(amount) == "number" and amount ~= 0 then
      out[key] = amount
    end
  end
  return out
end)

-- The inventory slots an equip location may take (the retail family numbering: a ranged weapon
-- sits in the main hand on retail; slot 18 is tried as well so a Classic-era layout on Forever is
-- read too, assumed 22.10.2026, forever-api.md).
local INVENTORY_SLOTS = {
  INVTYPE_HEAD = { 1 },
  INVTYPE_NECK = { 2 },
  INVTYPE_SHOULDER = { 3 },
  INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 16, 18 },
  INVTYPE_RANGEDRIGHT = { 16, 18 },
  INVTYPE_THROWN = { 16, 18 },
  INVTYPE_RELIC = { 18 },
  INVTYPE_TABARD = { 19 },
}
Compat.INVENTORY_SLOTS = INVENTORY_SLOTS

-- The item level the client reports for a link: the detailed one (upgrades counted) when the API
-- is there, else the base level from the item info.
local function itemLevel(link, base)
  if link and has(C_Item, "GetDetailedItemLevelInfo") then
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if type(level) == "number" and level > 0 then
      return level
    end
  end
  return base
end

-- What the player wears where an item of that equip location would go: the worn item with the
-- lowest level among the location's slots (the one an upgrade replaces), `{ slot }` when every
-- slot is empty, nil for a location that is not equippable (GetInventoryItemLink in both P1 dumps).
define("shared", "GetEquippedItem", function(equipLoc)
  local slots = INVENTORY_SLOTS[equipLoc or ""]
  if not slots or type(GetInventoryItemLink) ~= "function" then
    return nil
  end
  local worst
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    local worn
    if link then
      local id = tonumber(string.match(link, "item:(%d+)"))
      local info = Compat.GetItemInfo(link)
      local level = itemLevel(link, info and info.level or nil)
      worn = { slot = slot, id = id, link = link, name = info and info.name or nil, level = level }
    elseif not (slot == 17 and #slots > 1) then
      -- an empty off hand is no place for a one-hand weapon unless the player dual-wields: the
      -- main hand is compared then; an empty ring, trinket or single slot is the place
      worn = { slot = slot }
    end
    if worn and (not worst or (worn.level or 0) < (worst.level or 0)) then
      worst = worn
    end
  end
  return worst or { slot = slots[1] }
end)

-- Names the data packs do not carry (data.md "Retail data"): quest titles, creature names and item
-- data from the client. All three APIs are documented identically on both clients (forever-api.md,
-- probe P2/P6); a missing function answers nil or false instead of raising.

define("shared", "RequestItemData", function(itemID)
  if not has(C_Item, "RequestLoadItemDataByID") then
    return false
  end
  C_Item.RequestLoadItemDataByID(itemID)
  return true
end)

define("shared", "GetQuestName", function(questID)
  if not has(C_QuestLog, "GetTitleForQuestID") then
    return nil
  end
  local title = C_QuestLog.GetTitleForQuestID(questID)
  if type(title) == "string" and title ~= "" then
    return title
  end
  return nil
end)

define("shared", "RequestQuestData", function(questID)
  if not has(C_QuestLog, "RequestLoadQuestByID") then
    return false
  end
  C_QuestLog.RequestLoadQuestByID(questID)
  return true
end)

-- A creature's name from a tooltip built for a synthetic unit link; nil until the client has the
-- creature cached (it asks the server on the first miss).
define("shared", "GetUnitNameByID", function(npcID)
  if not has(C_TooltipInfo, "GetHyperlink") then
    return nil
  end
  local data = C_TooltipInfo.GetHyperlink(("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
  local line = data and data.lines and data.lines[1]
  local text = line and plain(line.leftText)
  if type(text) == "string" and text ~= "" then
    return text
  end
  return nil
end)

-- The entity behind a GUID (C6): "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>" (the id
-- in the sixth field, retail shape, assumed the same on Forever: forever-api.md). Creature and
-- Vehicle are NPCs, GameObject objects; Player, Pet, Item and anything else give nil.
local GUID_KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "object" }
function Compat.EntityFromGUID(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  local typ = kind and GUID_KINDS[kind]
  if not (typ and id) then
    return nil
  end
  return typ .. ":" .. tonumber(id)
end

define("shared", "TargetEntity", function()
  if type(UnitExists) == "function" and not UnitExists("target") then
    return nil
  end
  if type(UnitIsPlayer) == "function" and plain(UnitIsPlayer("target")) then
    return nil
  end
  return Compat.EntityFromGUID(type(UnitGUID) == "function" and plain(UnitGUID("target")) or nil)
end)

-- The game's objective tracker (C8, slim mode): ObjectiveTrackerFrame on retail (12.1.5), the
-- same name assumed on Forever (forever-api.md, verified at launch). Never touched in combat
-- lockdown: the caller keeps the wish for PLAYER_REGEN_ENABLED.
define("shared", "SetObjectiveTrackerShown", function(on)
  local f = _G.ObjectiveTrackerFrame
  if not f or (type(InCombatLockdown) == "function" and InCombatLockdown()) then
    return false
  end
  note("SetObjectiveTrackerShown", "ObjectiveTrackerFrame")
  if on then
    f:Show()
  else
    f:Hide()
  end
  return true
end)

-- The client's quest steps (D2, retail where the pack has no objective spots): the next waypoint
-- of a log quest on a map and the quest POIs of a map. Both functions are in the P1 dumps of both
-- clients (api_retail, api_forever); their returns are assumed from the retail docs and verified
-- by P2 on Forever at launch. Nil and an empty list when the client has nothing.
define("shared", "GetQuestWaypoint", function(questID, uiMapID)
  if not (questID and uiMapID and has(C_QuestLog, "GetNextWaypointForMap")) then
    return nil
  end
  local x, y = C_QuestLog.GetNextWaypointForMap(questID, uiMapID)
  if type(x) == "number" and type(y) == "number" then
    note("GetQuestWaypoint", "C_QuestLog.GetNextWaypointForMap")
    return x, y
  end
  return nil
end)

define("shared", "GetQuestsOnMap", function(uiMapID)
  local out = {}
  if not (uiMapID and has(C_QuestLog, "GetQuestsOnMap")) then
    return out
  end
  local list = C_QuestLog.GetQuestsOnMap(uiMapID)
  for _, info in ipairs(type(list) == "table" and list or {}) do
    if type(info) == "table" and info.questID and type(info.x) == "number" and type(info.y) == "number" then
      out[#out + 1] = { questID = info.questID, x = info.x, y = info.y }
    end
  end
  if #out > 0 then
    note("GetQuestsOnMap", "C_QuestLog.GetQuestsOnMap")
  end
  return out
end)

-- ---------------------------------------------------------------------------------------------
-- Player facts (UnitLevel, UnitRace, UnitClass, UnitFactionGroup: identical in both API docs)
-- ---------------------------------------------------------------------------------------------

define("shared", "GetPlayerFacts", function()
  local _, class, classID = UnitClass("player")
  local _, race, raceID = UnitRace("player")
  local faction = UnitFactionGroup("player")
  local health, max = plain(UnitHealth("player")), plain(UnitHealthMax("player")) -- secret on retail 12.x
  return {
    level = UnitLevel("player"),
    raceID = raceID,
    classID = classID,
    faction = faction,
    class = class,
    race = race,
    health = (health and max and max > 0) and health / max or nil,
  }
end)

-- Bag counts (C_Item.GetItemCount: documented identically on both clients).
define("shared", "GetItemCount", function(itemID)
  return C_Item.GetItemCount(itemID) or 0
end)

-- Reputation: C_Reputation.GetFactionDataByID is documented on both; the legacy global is the fallback.
define("shared", "GetReputation", function(factionID)
  if type(C_Reputation) == "table" and type(C_Reputation.GetFactionDataByID) == "function" then
    local d = C_Reputation.GetFactionDataByID(factionID)
    if d then
      note("GetReputation", "C_Reputation.GetFactionDataByID")
      return { name = d.name, standing = d.reaction, value = d.currentStanding }
    end
    return nil
  end
  if type(GetFactionInfoByID) == "function" then
    local name, _, standing, _, _, value = GetFactionInfoByID(factionID)
    if name then
      note("GetReputation", "GetFactionInfoByID")
      return { name = name, standing = standing, value = value }
    end
  end
  return nil
end)

-- The font files the client's own font objects use (GetFonts in the P1 dumps of both clients,
-- 23.10.2026): { [path] = true }; every one loads, since the client draws with it.
define("shared", "GetFontFiles", function()
  local out = {}
  if type(GetFonts) ~= "function" then
    return out
  end
  for _, name in ipairs(GetFonts() or {}) do
    local object = rawget(_G, name)
    if type(object) == "table" and type(object.GetFont) == "function" then
      local path = object:GetFont()
      if type(path) == "string" and path ~= "" then
        out[path] = true
      end
    end
  end
  return out
end)

-- Facing (GetPlayerFacing: documented identically on both clients).
define("shared", "GetPlayerFacing", function()
  return plain(GetPlayerFacing())
end)

-- The chat input (ChatFrame_OpenChat is FrameXML on both clients; without it the line goes to chat).
define("shared", "OpenChat", function(text)
  if type(ChatFrame_OpenChat) == "function" then
    note("OpenChat", "ChatFrame_OpenChat")
    ChatFrame_OpenChat(text)
  else
    note("OpenChat", "chat line")
    print(text)
  end
end)

-- Hearthstone (GetBindLocation and the item cooldown: documented identically on both clients; retail
-- reads the cooldown through C_Container, the legacy global is the fallback). The global cooldown of
-- 1.5 s or less never counts as "not ready".
local HEARTHSTONE = 6948
define("shared", "GetHearthstone", function()
  local start, duration = 0, 0
  if type(C_Container) == "table" and type(C_Container.GetItemCooldown) == "function" then
    note("GetHearthstone", "C_Container.GetItemCooldown")
    start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
  elseif type(_G.GetItemCooldown) == "function" then
    note("GetHearthstone", "GetItemCooldown")
    start, duration = _G.GetItemCooldown(HEARTHSTONE) -- legacy global, gone on retail
  end
  local remaining = 0
  if start and duration and start > 0 and duration > 1.5 then
    remaining = math.max(0, start + duration - GetTime())
  end
  local count = type(C_Item) == "table"
      and type(C_Item.GetItemCount) == "function"
      and C_Item.GetItemCount(HEARTHSTONE)
    or 0
  return {
    bindName = type(GetBindLocation) == "function" and GetBindLocation() or nil,
    hasStone = (count or 0) > 0,
    ready = remaining == 0,
    remaining = remaining,
  }
end)

-- Movement (GetUnitSpeed, IsMounted, UnitOnTaxi: documented identically on both clients).
define("shared", "GetMoveSpeed", function()
  local speed = plain(GetUnitSpeed("player")) -- nil while the client keeps it secret
  return speed, plain(IsMounted()) and true or false, plain(UnitOnTaxi("player")) and true or false
end)

-- Death (R26.8): UnitIsGhost and UnitIsDeadOrGhost, documented identically on both clients.
define("shared", "GetDeathState", function()
  if plain(UnitIsGhost("player")) then
    return "ghost"
  end
  if plain(UnitIsDeadOrGhost("player")) then
    return "dead"
  end
  return "alive"
end)

-- The corpse: C_DeathInfo.GetCorpseMapPosition(uiMapID) answers for the map the corpse lies on, so
-- the player's map and then its parents are asked (a graveyard may lie in the next zone). Present
-- on Forever 70532 (P1 dump, 23.10.2026); its answer is not verified there yet.
define("shared", "GetCorpsePosition", function()
  if not has(C_DeathInfo, "GetCorpseMapPosition") then
    note("GetCorpsePosition", "none")
    return nil
  end
  note("GetCorpsePosition", "C_DeathInfo.GetCorpseMapPosition")
  local map = C_Map.GetBestMapForUnit("player")
  for _ = 1, 4 do -- zone, continent, world: a short chain
    if not map then
      return nil
    end
    local pos = C_DeathInfo.GetCorpseMapPosition(map)
    if pos then
      local x, y
      if type(pos.GetXY) == "function" then
        x, y = pos:GetXY()
      else
        x, y = pos.x, pos.y
      end
      x, y = plain(x), plain(y)
      if x and y and (x > 0 or y > 0) then
        return map, x, y
      end
    end
    local info = C_Map.GetMapInfo(map)
    map = info and info.parentMapID ~= 0 and info.parentMapID or nil
  end
  return nil
end)

-- Teleports (R26.7): a spell known (C_SpellBook.IsSpellKnown, the legacy IsSpellKnown), an item in
-- the bags or worn (C_Item), a toy collected (PlayerHasToy); the cooldown from C_Spell or the item
-- cooldown. All documented on retail; present on Forever by the P1 dump, answers assumed. An
-- answer the client does not give stays unknown (nil), never "owned".
local function cooldownLeft(start, duration)
  start, duration = plain(start), plain(duration)
  if start == nil or duration == nil then
    return nil
  end
  if start > 0 and duration > 1.5 then
    return math.max(0, start + duration - GetTime())
  end
  return 0
end

define("shared", "GetTeleportState", function(kind, id, reagent)
  local owned
  if kind == "spell" then
    if has(C_SpellBook, "IsSpellKnown") then
      owned = plain(C_SpellBook.IsSpellKnown(id))
    elseif type(_G.IsSpellKnown) == "function" then
      owned = plain(_G.IsSpellKnown(id))
    end
  elseif kind == "toy" then
    if type(_G.PlayerHasToy) == "function" then
      owned = plain(_G.PlayerHasToy(id))
    end
  elseif kind == "item" then
    owned = Compat.GetItemCount(id) > 0
      or (has(C_Item, "IsEquippedItem") and plain(C_Item.IsEquippedItem(id)) == true)
  end
  if owned == nil then
    return nil
  end
  if not owned then
    return false, false, nil
  end
  if reagent and Compat.GetItemCount(reagent) == 0 then
    return true, false, nil
  end
  local left
  if kind == "spell" then
    if has(C_Spell, "GetSpellCooldown") then
      local cd = C_Spell.GetSpellCooldown(id)
      left = type(cd) == "table" and cooldownLeft(cd.startTime, cd.duration) or nil
    elseif type(_G.GetSpellCooldown) == "function" then
      left = cooldownLeft(_G.GetSpellCooldown(id))
    end
  elseif has(C_Container, "GetItemCooldown") then
    left = cooldownLeft(C_Container.GetItemCooldown(id))
  end
  if left == nil then
    return true, nil, nil
  end
  return true, left == 0, left
end)

define("shared", "GetItemSpell", function(itemID)
  if not has(C_Item, "GetItemSpell") then
    return nil
  end
  local _, spellID = C_Item.GetItemSpell(itemID)
  return plain(spellID)
end)

-- Addon messages (notes.md N3; C_ChatInfo.RegisterAddonMessagePrefix and SendAddonMessage present
-- on Forever 70532 by the P1 dump, answers assumed from the retail docs 26.10.2026; the legacy
-- globals as the fallback).
define("shared", "RegisterAddonPrefix", function(prefix)
  local C = rawget(_G, "C_ChatInfo")
  if has(C, "IsAddonMessagePrefixRegistered") and C.IsAddonMessagePrefixRegistered(prefix) then
    return true
  end
  if has(C, "RegisterAddonMessagePrefix") then
    note("RegisterAddonPrefix", "C_ChatInfo")
    local result = C.RegisterAddonMessagePrefix(prefix)
    return result == nil or result == true or result == 0 -- retail answers an enum, 0 = success
  end
  if type(_G.RegisterAddonMessagePrefix) == "function" then
    note("RegisterAddonPrefix", "RegisterAddonMessagePrefix")
    return _G.RegisterAddonMessagePrefix(prefix) ~= false
  end
  note("RegisterAddonPrefix", "none")
  return false
end)

define("shared", "SendAddonMessage", function(prefix, text, channel, target)
  local C = rawget(_G, "C_ChatInfo")
  if has(C, "SendAddonMessage") then
    C.SendAddonMessage(prefix, text, channel, target)
    return true
  end
  if type(_G.SendAddonMessage) == "function" then
    _G.SendAddonMessage(prefix, text, channel, target)
    return true
  end
  return false
end)

-- Bag slots (C_Container: 47 functions present on Forever, P1 of 20.10.2026; the info table is the
-- retail shape, assumed on Forever until the bag advisor ran there). Bags 0 to the last equipped one.
define("shared", "GetBagItems", function()
  local out = {}
  if type(C_Container) ~= "table" or not C_Container.GetContainerNumSlots then
    return out
  end
  local last = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or rawget(_G, "NUM_BAG_SLOTS") or 4
  for bag = 0, last do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        out[#out + 1] = {
          bag = bag,
          slot = slot,
          itemID = info.itemID,
          count = info.stackCount or 1,
          quality = info.quality,
          bound = info.isBound == true,
          noValue = info.hasNoValue == true,
          icon = info.iconFileID,
          link = info.hyperlink,
        }
      end
    end
  end
  return out
end)

-- Money (GetMoney: documented identically on both clients).
define("shared", "GetMoney", function()
  return GetMoney() or 0
end)

-- Experience (UnitXP, UnitXPMax: legacy globals on both clients; verified by use on the Forever
-- beta through AHSyncGuide 0.4's Journey, journey reports 19.-20.10.2026).
define("shared", "GetPlayerXP", function()
  if not UnitXP then
    return nil, nil, UnitLevel("player")
  end
  return UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end)

-- Professions: Forever lists skill lines (C_SkillInfo, Forever-only in the docs), retail the
-- profession trade skill lines (C_TradeSkillUI, documented on both). Nil when neither answers.
define("shared", "GetProfessions", function()
  local out, any = {}, false
  if type(C_SkillInfo) == "table" and type(C_SkillInfo.GetNumSkillLines) == "function" then
    note("GetProfessions", "C_SkillInfo")
    for i = 1, C_SkillInfo.GetNumSkillLines() or 0 do
      local s = C_SkillInfo.GetSkillLineInfo(i)
      if type(s) == "table" and not (s.isHeader or s.header) then
        local name = s.skillName or s.name
        local rank = s.skillRank or s.rank
        if name and (rank or 0) > 0 then
          out[name] = rank
          any = true
        end
      end
    end
    return any and out or {}
  end
  if
    type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) == "function"
  then
    note("GetProfessions", "C_TradeSkillUI")
    for _, id in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines() or {}) do
      local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID
        and C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
      if info and info.professionName and (info.skillLevel or 0) > 0 then
        out[info.professionName] = info.skillLevel
        any = true
      end
    end
    return any and out or {}
  end
  return nil
end)

-- Party state: legacy globals, present on every client since Mists (assumed on Forever, probe P1).
-- The group's channel and members (R26.9): IsInRaid and GetNumGroupMembers, documented on both
-- clients; assumed on Forever until a group is formed in game.
define("shared", "GroupChannel", function()
  if type(_G.IsInRaid) == "function" and plain(_G.IsInRaid()) then
    return "RAID"
  end
  return Compat.IsInGroup() and "PARTY" or nil
end)

define("shared", "InGuild", function()
  return type(_G.IsInGuild) == "function" and plain(_G.IsInGuild()) and true or false
end)

-- The realm's clock (R26.6: a ferry's loop is the same for every player of the realm).
define("shared", "ServerTime", function()
  if type(_G.GetServerTime) == "function" then
    local t = plain(_G.GetServerTime())
    if t then
      return t
    end
  end
  return time()
end)

-- The level cap (R26.11: Explore orders by XP below it, by gold at it); nil when the client
-- cannot tell.
define("shared", "MaxLevel", function()
  for _, name in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel" }) do
    local fn = _G[name]
    if type(fn) == "function" then
      local level = plain(fn())
      if type(level) == "number" and level > 0 then
        return level
      end
    end
  end
  return nil
end)

-- The friends list (R26.16: sharing my location with a friend). C_FriendList is documented on
-- both clients (the retail family); the answer's shape is assumed until seen on Forever.
define("shared", "Friends", function()
  local out = {}
  local fl = _G.C_FriendList
  if not (fl and type(fl.GetNumFriends) == "function" and type(fl.GetFriendInfoByIndex) == "function") then
    return out
  end
  local n = plain(fl.GetNumFriends()) or 0
  for i = 1, n do
    local info = fl.GetFriendInfoByIndex(i)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
      out[#out + 1] =
        { name = info.name, online = info.connected and true or false, area = info.area, level = info.level }
    end
  end
  return out
end)

define("shared", "GroupUnits", function()
  local out = {}
  local raid = type(_G.IsInRaid) == "function" and plain(_G.IsInRaid())
  local n = type(_G.GetNumGroupMembers) == "function" and plain(_G.GetNumGroupMembers()) or 0
  local me = UnitName("player")
  for i = 1, raid and n or math.min(n, 5) - 1 do
    local unit = (raid and "raid" or "party") .. i
    local name = plain(UnitName(unit))
    if name and name ~= me then
      out[#out + 1] = { unit = unit, name = name }
    end
  end
  return out
end)

define("shared", "IsInGroup", function()
  if type(IsInGroup) == "function" then
    return IsInGroup() and true or false
  end
  return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end)

-- ---------------------------------------------------------------------------------------------
-- Settings (Settings.RegisterCanvasLayoutCategory exists in both source trees; runtime is probe P6)
-- ---------------------------------------------------------------------------------------------

define("shared", "RegisterSettingsCategory", function(frame, name, parent)
  if not Has.SettingsAPI then
    note("RegisterSettingsCategory", "no Settings API")
    return nil
  end
  note("RegisterSettingsCategory", "Settings.RegisterCanvasLayoutCategory")
  if parent then
    return Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
  end
  local category = Settings.RegisterCanvasLayoutCategory(frame, name)
  Settings.RegisterAddOnCategory(category)
  return category
end)

define("shared", "OpenSettings", function(category)
  if Has.SettingsAPI and category then
    Settings.OpenToCategory(category:GetID())
  end
end)

-- ---------------------------------------------------------------------------------------------
-- Map transforms: the API first, else the generated table from Data (coordinates.md)
-- ---------------------------------------------------------------------------------------------

local transforms -- [uiMapID] = { continent, wx0, wxDx, wxDy, wy0, wyDx, wyDy } (affine, map fractions in)
local scratch = Has.WorldPosFromMapPos and CreateVector2D(0, 0) or nil

define("shared", "SetTransformTable", function(tbl)
  transforms = tbl
end)

define("shared", "MapPosToWorld", function(uiMapID, x, y)
  if scratch then
    scratch:SetXY(x, y)
    local continent, pos = C_Map.GetWorldPosFromMapPos(uiMapID, scratch)
    if pos then
      note("MapPosToWorld", "C_Map.GetWorldPosFromMapPos")
      local wx, wy = pos:GetXY()
      return continent, wx, wy
    end
  end
  local t = transforms and transforms[uiMapID]
  if t then
    note("MapPosToWorld", "transform table")
    return t[1], t[2] + x * t[3] + y * t[4], t[5] + x * t[6] + y * t[7]
  end
  return nil
end)

-- ---------------------------------------------------------------------------------------------
-- 3D portraits:
-- a DressUpModel or a PlayerModel; SetCreature(npcID) for a creature, SetItem(itemID) for an item
-- with a model of its own (~~SetUnit("player") + Undress + TryOn~~: the player half naked or in
-- the old outfit, ). Assumed on both clients until seen (forever-api.md); every call
-- checks first.
-- ---------------------------------------------------------------------------------------------

-- A spell's name (C_Spell.GetSpellName, in the P1 dumps of both clients): retail's recipes come
-- without names (28.10.2026).
define("shared", "GetSpellName", function(spellID)
  local api = rawget(_G, "C_Spell")
  spellID = tonumber(spellID)
  if not (spellID and api and type(api.GetSpellName) == "function") then
    return nil
  end
  local name = api.GetSpellName(spellID)
  return type(name) == "string" and name ~= "" and name or nil
end)

-- PlayerModel first: creatures and items show on it; the DressUpModel was for trying gear on
-- the player, no longer used (28.10.2026).
define("shared", "NewModel", function(parent)
  for _, kind in ipairs({ "PlayerModel", "DressUpModel" }) do
    local ok, model = pcall(CreateFrame, kind, nil, parent)
    if ok and model then
      note("NewModel", kind)
      return model
    end
  end
  return nil
end)

define("shared", "ShowCreature", function(model, npcID)
  npcID = tonumber(npcID)
  if not (model and npcID and type(model.SetCreature) == "function") then
    return false
  end
  if type(model.ClearModel) == "function" then
    model:ClearModel()
  end
  model:SetCreature(npcID)
  note("ShowCreature", "SetCreature")
  return true
end)

-- The slots whose items have a model of their own (a chest piece or boots exist only as textures on a
-- body: those keep their icon; "the item only as an item, not on the char").
Compat.MODEL_SLOTS = {
  INVTYPE_WEAPON = true,
  INVTYPE_2HWEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_SHIELD = true,
  INVTYPE_HOLDABLE = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
  INVTYPE_HEAD = true,
  INVTYPE_SHOULDER = true,
}

define("shared", "ShowItem", function(model, itemID)
  itemID = tonumber(itemID)
  local api = rawget(_G, "C_Item")
  if not (model and itemID and api and type(api.GetItemInfoInstant) == "function") then
    return false
  end
  local _, _, _, equipLoc = api.GetItemInfoInstant(itemID)
  if not (equipLoc and Compat.MODEL_SLOTS[equipLoc] and type(model.SetItem) == "function") then
    return false
  end
  if type(model.ClearModel) == "function" then
    model:ClearModel()
  end
  model:SetItem(itemID)
  note("ShowItem", "SetItem")
  return true
end)

define("shared", "ZoomModel", function(model, scale)
  if model and type(model.SetCamDistanceScale) == "function" then
    model:SetCamDistanceScale(scale)
  end
end)

-- The skin (ADR 0034, all assumed until seen in game): a model's animation, a frame with the
-- game's backdrop (the BackdropTemplate of the retail family), an item's quality and its colour.
define("shared", "Animate", function(model, animID)
  if not (model and animID and type(model.SetAnimation) == "function") then
    return false
  end
  model:SetAnimation(animID)
  return true
end)

define("shared", "HasAnimation", function(model, animID)
  if not (model and animID and type(model.HasAnimation) == "function") then
    return nil -- the client cannot tell
  end
  return model:HasAnimation(animID) and true or false
end)

define("shared", "NewBackdrop", function(parent)
  local ok, frame = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
  if not (ok and frame) then
    ok, frame = pcall(CreateFrame, "Frame", nil, parent)
  end
  if ok and frame and type(frame.SetBackdrop) == "function" then
    note("NewBackdrop", "BackdropTemplate")
    return frame
  end
  return nil
end)

-- An item's icon from the client's own item table (C_Item.GetItemIconByID, in Forever's P1 dump;
-- the answer assumed from the retail docs, 29.10.2026): no server round trip, so an item the client
-- has not cached yet has its picture at once.
define("shared", "ItemIcon", function(itemID)
  local api = rawget(_G, "C_Item")
  itemID = tonumber(itemID)
  if not (itemID and api and type(api.GetItemIconByID) == "function") then
    return nil
  end
  local icon = api.GetItemIconByID(itemID)
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end)

define("shared", "ItemQuality", function(itemID)
  local api = rawget(_G, "C_Item")
  itemID = tonumber(itemID)
  if not (itemID and api and type(api.GetItemQualityByID) == "function") then
    return nil
  end
  local q = api.GetItemQualityByID(itemID)
  return type(q) == "number" and q or nil
end)

define("shared", "QualityColor", function(quality)
  local api = rawget(_G, "C_Item")
  if type(quality) ~= "number" then
    return nil
  end
  if api and type(api.GetItemQualityColor) == "function" then
    local r, g, b = api.GetItemQualityColor(quality)
    if type(r) == "number" then
      return r, g, b
    end
  end
  local colors = rawget(_G, "ITEM_QUALITY_COLORS")
  local c = type(colors) == "table" and colors[quality]
  if c and type(c.r) == "number" then
    return c.r, c.g, c.b
  end
  return nil
end)

-- ---------------------------------------------------------------------------------------------
-- Mask textures (Frame:CreateMaskTexture, Texture:AddMaskTexture; retail family, Forever assumed
-- until `/bprobe mask` shows it, forever-api.md). The Map masks the sea out of native coast tiles.
-- ---------------------------------------------------------------------------------------------

Has.MaskTexture = type(CreateFrame) == "function"
  and type(UIParent) == "table"
  and type(UIParent.CreateMaskTexture) == "function"

define("shared", "AddMask", function(texture, path)
  if type(texture) ~= "table" or type(texture.AddMaskTexture) ~= "function" then
    return nil
  end
  local mask = texture.bastiansMask
  if not path then
    if mask and texture.bastiansMasked then
      texture:RemoveMaskTexture(mask)
      texture.bastiansMasked = false
      mask:Hide()
    end
    return nil
  end
  if not mask then
    local parent = texture:GetParent()
    if not (parent and type(parent.CreateMaskTexture) == "function") then
      return nil
    end
    mask = parent:CreateMaskTexture()
    mask:SetAllPoints(texture) -- follows the texture wherever it is placed
    texture.bastiansMask = mask
  end
  -- CLAMP, not CLAMPTOBLACKADDITIVE: clamping to black would fade every tile's border to transparent
  mask:SetTexture(path, "CLAMP", "CLAMP")
  if mask:GetTexture() == nil then
    -- the file did not load (a mask the client refuses would hide the whole tile, 22.10.2026):
    -- no mask then, the tile keeps its own water
    if texture.bastiansMasked then
      texture:RemoveMaskTexture(mask)
      texture.bastiansMasked = false
    end
    mask:Hide()
    note("AddMask", "mask file did not load")
    return nil
  end
  mask:Show()
  if not texture.bastiansMasked then
    texture:AddMaskTexture(mask)
    texture.bastiansMasked = true
  end
  note("AddMask", "mask textures")
  return mask
end)

-- ---------------------------------------------------------------------------------------------
-- The fact layer (library.md §4, ADR 0028): units, the player's state, loot, readable text, emotes,
-- the combat log. All assumed 27.10.2026 (forever-api.md probe rows); every call is guarded so a
-- client without a function answers nil or false, never an error.
-- ---------------------------------------------------------------------------------------------

local function fnOf(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function call(name, ...)
  local f = fnOf(name)
  if not f then
    return nil
  end
  return plain(f(...))
end

define("shared", "UnitFacts", function(unit)
  if not call("UnitExists", unit) or call("UnitIsPlayer", unit) then
    return nil
  end
  local guid = call("UnitGUID", unit)
  local health, max = call("UnitHealth", unit), call("UnitHealthMax", unit)
  local within
  if call("CheckInteractDistance", unit, 3) then
    within = 10
  elseif call("CheckInteractDistance", unit, 1) then
    within = 28
  end
  return {
    unit = unit,
    guid = guid,
    ref = Compat.EntityFromGUID(guid),
    name = call("UnitName", unit),
    alive = not call("UnitIsDeadOrGhost", unit),
    level = call("UnitLevel", unit),
    health = (health and max and max > 0) and health / max or nil,
    reaction = call("UnitReaction", "player", unit),
    targetsPlayer = call("UnitIsUnit", unit .. "target", "player") and true or false,
    within = within,
  }
end)

define("shared", "PlayerState", function()
  local function is(name, ...)
    return call(name, ...) and true or false
  end
  return {
    combat = is("UnitAffectingCombat", "player"),
    stealthed = is("IsStealthed"),
    swimming = is("IsSwimming"),
    submerged = is("IsSubmerged"),
    falling = is("IsFalling"),
    flying = is("IsFlying"),
    mounted = is("IsMounted"),
    onTaxi = is("UnitOnTaxi", "player"),
    resting = is("IsResting"),
    indoors = is("IsIndoors"),
  }
end)

define("shared", "PlayerAuras", function()
  local out = {}
  if has(C_UnitAuras, "GetAuraDataByIndex") then
    for i = 1, 80 do
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if type(a) ~= "table" then
        break
      end
      local id = plain(a.spellId)
      if id then
        out[id] = plain(a.name) or true
      end
    end
    note("PlayerAuras", "C_UnitAuras")
    return out
  end
  local ua = fnOf("UnitAura")
  if ua then
    for i = 1, 80 do
      local name, _, _, _, _, _, _, _, _, spellId = ua("player", i, "HELPFUL")
      if not name then
        break
      end
      if plain(spellId) then
        out[plain(spellId)] = plain(name)
      end
    end
    note("PlayerAuras", "UnitAura")
  end
  return out
end)

define("shared", "LootSlots", function()
  local n = call("GetNumLootItems")
  if not n then
    return {}, false
  end
  local out = {}
  for i = 1, n do
    local link = call("GetLootSlotLink", i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if id then
      local _, _, quantity = GetLootSlotInfo(i)
      out[#out + 1] = {
        slot = i,
        item = "item:" .. id,
        count = plain(quantity) or 1,
        from = Compat.EntityFromGUID(call("GetLootSourceInfo", i)),
      }
    end
  end
  return out, call("IsFishingLoot") and true or false
end)

define("shared", "ItemText", function()
  local text = call("ItemTextGetText")
  if text == nil then
    return nil
  end
  return { item = call("ItemTextGetItem"), text = text, page = call("ItemTextGetPage") or 1 }
end)

define("shared", "Emote", function(token, target)
  if not fnOf("DoEmote") or (type(InCombatLockdown) == "function" and InCombatLockdown()) then
    return false
  end
  DoEmote(token, target)
  return true
end)

define("shared", "TakeScreenshot", function()
  if not fnOf("Screenshot") then
    return false
  end
  Screenshot()
  return true
end)

-- The worn items: slots 1 (head) to 19 (tabard)
define("shared", "EquippedItems", function()
  local out = {}
  for slot = 1, 19 do
    local id = call("GetInventoryItemID", "player", slot)
    if id then
      out[id] = slot
    end
  end
  return out
end)

define("shared", "IsPvPFlagged", function()
  return call("UnitIsPVP", "player") and true or false
end)

define("shared", "InstanceType", function()
  local f = fnOf("IsInInstance")
  if not f then
    return "none"
  end
  local _, kind = f()
  return plain(kind) or "none"
end)

-- The bags' use: C_Container on the retail family, the old global where only that exists (one
-- hook, so a client with both does not report a use twice)
define("shared", "HookItemUse", function(fn)
  if type(hooksecurefunc) ~= "function" then
    return false
  end
  local function used(bag, slot)
    local id
    if has(C_Container, "GetContainerItemID") then
      id = C_Container.GetContainerItemID(bag, slot)
    elseif fnOf("GetContainerItemID") then
      id = _G.GetContainerItemID(bag, slot)
    end
    id = plain(id)
    if id then
      fn(id)
    end
  end
  if has(C_Container, "UseContainerItem") then
    hooksecurefunc(C_Container, "UseContainerItem", used)
    return true
  end
  if fnOf("UseContainerItem") then
    hooksecurefunc("UseContainerItem", used)
    return true
  end
  return false
end)

-- A uiMap's name in the client's language (C_Map.GetMapInfo, verified; the language packs, ADR 0033).
define("shared", "MapName", function(uiMapID)
  if not (uiMapID and has(C_Map, "GetMapInfo")) then
    return nil
  end
  local info = C_Map.GetMapInfo(uiMapID)
  return type(info) == "table" and type(info.name) == "string" and info.name ~= "" and info.name or nil
end)

define("shared", "AreaName", function(areaID)
  if not has(C_Map, "GetAreaInfo") then
    return nil
  end
  return plain(C_Map.GetAreaInfo(areaID))
end)

define("shared", "PlayKit", function(id)
  local play = fnOf("PlaySound")
  if play and id then
    play(id)
  end
end)

define("shared", "PlayFile", function(path, channel)
  local play = fnOf("PlaySoundFile")
  if not play then
    return nil
  end
  local willPlay, handle = play(path, channel or "Dialog")
  if not willPlay then
    return nil
  end
  return handle or true
end)

define("shared", "StopFile", function(handle)
  local stop = fnOf("StopSound")
  if stop and type(handle) == "number" then
    stop(handle)
  end
end)

-- The client's text-to-speech (assumed; forever-api.md, library.md 10.3): the first voice the
-- client offers. Both clients' SpeakText takes (voiceID, text, rate, volume, overlap) (api stubs,
-- 28.10.2026); the older (voiceID, text, destination, rate, volume) put 0 into the volume and the
-- owner heard nothing on retail. A client whose signature differs answers false through pcall.
define("shared", "Speak", function(text)
  local vc = rawget(_G, "C_VoiceChat")
  if not (vc and vc.SpeakText and vc.GetTtsVoices) or type(text) ~= "string" or text == "" then
    return false
  end
  local voices = vc.GetTtsVoices()
  local voice = type(voices) == "table" and voices[1]
  if not (voice and voice.voiceID) then
    return false
  end
  return pcall(vc.SpeakText, voice.voiceID, text, 0, 100, false) == true
end)

define("shared", "StopSpeaking", function()
  local vc = rawget(_G, "C_VoiceChat")
  if vc and vc.StopSpeakingText then
    pcall(vc.StopSpeakingText)
  end
end)

define("shared", "CombatEvent", function()
  local f = fnOf("CombatLogGetCurrentEventInfo")
  if not f then
    return nil
  end
  local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, a12, _, _, a15 = f()
  if type(subevent) ~= "string" then
    return nil
  end
  local spellID, amount
  if subevent == "SWING_DAMAGE" then
    amount = plain(a12)
  elseif subevent:find("^SPELL") or subevent:find("^RANGE") then
    spellID = plain(a12)
    if subevent:find("_DAMAGE$") or subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
      amount = plain(a15)
    end
  end
  return {
    subevent = subevent,
    sourceGUID = plain(sourceGUID),
    sourceName = plain(sourceName),
    destGUID = plain(destGUID),
    destName = plain(destName),
    spellID = spellID,
    amount = amount,
  }
end)

-- The game's colour picker (R27.2): SetupColorPickerAndShow on the retail family since 10.2.5, the
-- frame's fields before it. Assumed 27.10.2026 on both clients (forever-api.md).
define("shared", "PickColor", function(r, g, b, onChange)
  local f = rawget(_G, "ColorPickerFrame")
  if type(f) ~= "table" or type(f.GetColorRGB) ~= "function" then
    return false
  end
  local function changed()
    local nr, ng, nb = f:GetColorRGB()
    if nr then
      onChange(nr, ng, nb)
    end
  end
  local function cancelled()
    onChange(r, g, b)
  end
  if type(f.SetupColorPickerAndShow) == "function" then
    f:SetupColorPickerAndShow({ r = r, g = g, b = b, swatchFunc = changed, cancelFunc = cancelled })
    note("PickColor", "SetupColorPickerAndShow")
  else
    f.func, f.cancelFunc, f.hasOpacity, f.previousValues = changed, cancelled, false, { r, g, b }
    f:SetColorRGB(r, g, b)
    f:Show()
    note("PickColor", "the frame's fields")
  end
  return true
end)
