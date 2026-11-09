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

-- The lines of an item's tooltip as the game builds it ("the item it
-- produces with picture and all stats"): C_TooltipInfo.GetItemByID, the retail family's (the
-- namespace is on Forever with 82 functions, forever-api.md; this one assumed until measured).
-- Texts through Plain (secret values on retail 12.x); nil while the client has not the item.
define("shared", "ItemTooltipLines", function(itemID)
  if type(itemID) ~= "number" or not has(C_TooltipInfo, "GetItemByID") then
    return nil
  end
  local data = C_TooltipInfo.GetItemByID(itemID)
  if type(data) ~= "table" or type(data.lines) ~= "table" then
    return nil
  end
  local out = {}
  for _, line in ipairs(data.lines) do
    local left = plain(line.leftText)
    if type(left) == "string" then
      local c = type(line.leftColor) == "table" and line.leftColor or {}
      local right = plain(line.rightText)
      out[#out + 1] = {
        left = left,
        right = type(right) == "string" and right ~= "" and right or nil,
        r = plain(c.r),
        g = plain(c.g),
        b = plain(c.b),
      }
    end
  end
  local retrieving = rawget(_G, "RETRIEVING_ITEM_INFO")
  if #out == 0 or (retrieving and out[1].left == retrieving) then
    return nil
  end
  return out
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

-- The entity of a unit token ("target", "mouseover"): Creature and Vehicle GUIDs give npc:<id>,
-- GameObject object:<id>; players, pets and a missing unit give nil (Helpers' rare alert, A3.3).
define("shared", "UnitEntity", function(unit)
  if type(UnitExists) == "function" and not UnitExists(unit) then
    return nil
  end
  if type(UnitIsPlayer) == "function" and plain(UnitIsPlayer(unit)) then
    return nil
  end
  return Compat.EntityFromGUID(type(UnitGUID) == "function" and plain(UnitGUID(unit)) or nil)
end)

define("shared", "TargetEntity", function()
  return Compat.UnitEntity("target")
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
  local className, class, classID = UnitClass("player")
  local _, race, raceID = UnitRace("player")
  local faction = UnitFactionGroup("player")
  local health, max = plain(UnitHealth("player")), plain(UnitHealthMax("player")) -- secret on retail 12.x
  return {
    level = UnitLevel("player"),
    raceID = raceID,
    classID = classID,
    faction = faction,
    class = class,
    className = className, -- in the client's language (the class quests view's summary)
    race = race,
    health = (health and max and max > 0) and health / max or nil,
  }
end)

-- Bag counts (C_Item.GetItemCount: documented identically on both clients).
define("shared", "GetItemCount", function(itemID, includeBank)
  return C_Item.GetItemCount(itemID, includeBank) or 0
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

-- The Addon Compartment (retail 11.0+; the frame is in Forever's P1 dump of 70532, the Lua call
-- assumed, forever-api.md). `func` gets the mouse button's name.
define("shared", "RegisterCompartment", function(entry)
  local frame = rawget(_G, "AddonCompartmentFrame")
  if type(frame) ~= "table" or type(frame.RegisterAddon) ~= "function" then
    note("RegisterCompartment", "none")
    return false
  end
  note("RegisterCompartment", "AddonCompartmentFrame")
  frame:RegisterAddon({
    text = entry.text,
    icon = entry.icon,
    notCheckable = true,
    func = function(_, input)
      entry.func(type(input) == "table" and input.buttonName or "LeftButton")
    end,
    funcOnEnter = entry.onEnter,
    funcOnLeave = entry.onLeave,
  })
  return true
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

-- An item's cooldown left in seconds (C_Container.GetItemCooldown, documented on both clients;
-- 0 when ready, nil when the client cannot tell). Bastian's Campfire's features (probe C3).
define("shared", "ItemCooldown", function(itemID)
  if has(C_Container, "GetItemCooldown") then
    return cooldownLeft(C_Container.GetItemCooldown(itemID))
  end
  return nil
end)

-- What this character knows (alts.md "Knowledge", 01.11.2026): a spell or recipe by id, the whole
-- spell book, the open profession's learned recipes. Each answers nil where the client has no API.
define("shared", "IsSpellKnown", function(id)
  id = tonumber(id)
  if not id then
    return nil
  end
  if has(C_SpellBook, "IsSpellKnown") then
    return plain(C_SpellBook.IsSpellKnown(id)) == true
  elseif type(_G.IsSpellKnown) == "function" then
    return plain(_G.IsSpellKnown(id)) == true
  elseif type(_G.IsPlayerSpell) == "function" then
    return plain(_G.IsPlayerSpell(id)) == true
  end
  return nil
end)

define("shared", "KnownSpells", function()
  if
    not (has(C_SpellBook, "GetNumSpellBookSkillLines") and has(C_SpellBook, "GetSpellBookSkillLineInfo"))
  then
    return nil
  end
  if not has(C_SpellBook, "GetSpellBookItemInfo") then
    return nil
  end
  local bank = rawget(_G, "Enum") and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local out = {}
  local lines = plain(C_SpellBook.GetNumSpellBookSkillLines()) or 0
  for i = 1, lines do
    local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
    local offset, count =
      info and plain(info.itemIndexOffset) or 0, info and plain(info.numSpellBookItems) or 0
    for j = offset + 1, offset + count do
      local item = C_SpellBook.GetSpellBookItemInfo(j, bank)
      local spellID = item and plain(item.spellID)
      if spellID and item.isPassive ~= true then
        out[spellID] = true
      end
    end
  end
  return out
end)

define("shared", "OpenRecipes", function()
  if not (has(C_TradeSkillUI, "GetAllRecipeIDs") and has(C_TradeSkillUI, "GetRecipeInfo")) then
    return nil
  end
  local ids = C_TradeSkillUI.GetAllRecipeIDs()
  if type(ids) ~= "table" then
    return nil
  end
  local out = {}
  for _, id in ipairs(ids) do
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    if info and plain(info.learned) == true then
      out[plain(info.recipeID) or id] = true
    end
  end
  return out
end)

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

-- Whether the client would let the player use a toy now (C_ToyBox.IsToyUsable, in the P1 dump; its
-- answer outside a toy's event assumed, Campfire's Violet Dust). nil when the client cannot tell.
define("shared", "ToyUsable", function(itemID)
  local toys = rawget(_G, "C_ToyBox")
  if not has(toys, "IsToyUsable") then
    return nil
  end
  local usable = plain(toys.IsToyUsable(itemID))
  if usable == nil then
    return nil
  end
  return usable and true or false
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

-- Custom chat channels (#20, Campfire's public beacon; JoinTemporaryChannel, LeaveChannelByName,
-- GetChannelName, ChatFrame_RemoveChannel as the retail FrameXML has them, assumed on Forever).
define("shared", "ChannelNumber", function(name)
  if type(_G.GetChannelName) ~= "function" then
    return nil
  end
  local number = _G.GetChannelName(name)
  return type(number) == "number" and number > 0 and number or nil
end)

define("shared", "JoinChannel", function(name)
  if type(_G.JoinTemporaryChannel) ~= "function" then
    return nil
  end
  _G.JoinTemporaryChannel(name)
  if type(_G.ChatFrame_RemoveChannel) == "function" then
    for i = 1, rawget(_G, "NUM_CHAT_WINDOWS") or 10 do
      local frame = rawget(_G, "ChatFrame" .. i)
      if frame then
        _G.ChatFrame_RemoveChannel(frame, name)
      end
    end
  end
  return Compat.ChannelNumber(name)
end)

define("shared", "LeaveChannel", function(name)
  if type(_G.LeaveChannelByName) ~= "function" then
    return false
  end
  _G.LeaveChannelByName(name)
  return true
end)

-- Bag slots (C_Container: 47 functions present on Forever, P1 of 20.10.2026; the info table is the
-- retail shape, assumed on Forever until the bag advisor ran there). Bags 0 to the last equipped one.
local function containerRows(bags)
  local out = {}
  if type(C_Container) ~= "table" or not C_Container.GetContainerNumSlots then
    return out
  end
  for _, bag in ipairs(bags) do
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
end

-- The name is in both P1 dumps (Forever 70450, 70532; retail 70448); the order of its answers is
-- retail's and assumed on Forever (forever-api.md).
define("shared", "GetInboxInvoices", function()
  local read = rawget(_G, "GetInboxInvoiceInfo")
  local header = rawget(_G, "GetInboxHeaderInfo")
  local count = rawget(_G, "GetInboxNumItems")
  local out = {}
  if not (read and header and count) then
    return out
  end
  for index = 1, count() do
    local kind, item, _, bid, _, deposit, consignment, _, _, _, units = read(index)
    if kind and item then
      out[#out + 1] = {
        kind = kind,
        item = item,
        bid = bid,
        deposit = deposit,
        consignment = consignment,
        count = units,
        daysLeft = select(7, header(index)),
      }
    end
  end
  return out
end)

define("shared", "GetBagItems", function()
  local last = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS") or rawget(_G, "NUM_BAG_SLOTS") or 4
  local bags = {}
  for bag = 0, last do
    bags[#bags + 1] = bag
  end
  return containerRows(bags)
end)

define("shared", "GetContainerItems", function(bags)
  return containerRows(bags or {})
end)

-- The bank's containers (Bastian's Alts, ADR 0041; the retail family's Enum.BagIndex names: Bank and
-- BankBag_1..7 on the old layout, CharacterBankTab_1..9 on both clients' API dumps (6 to 14; there
-- -1 is the keyring, so it is only taken without the enum), Reagentbank; the account's warband
-- tabs are left out, they are no character's). Assumed on Forever until measured (forever-api.md).
define("shared", "BankBags", function()
  local out, seen = {}, {}
  local function add(id)
    if type(id) == "number" and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  local index = rawget(_G, "Enum") and Enum.BagIndex
  if type(index) == "table" then
    add(index.Bank)
    for i = 1, 7 do
      add(index["BankBag_" .. i])
    end
    for i = 1, 9 do -- Forever's dump names nine, retail's six (measured in the API stubs)
      add(index["CharacterBankTab_" .. i])
    end
    add(index.Reagentbank)
  end
  if #out == 0 then
    add(rawget(_G, "BANK_CONTAINER") or -1)
    local first = (rawget(_G, "NUM_BAG_SLOTS") or 4) + 1
    for bag = first, first + (rawget(_G, "NUM_BANKBAGSLOTS") or 6) - 1 do
      add(bag)
    end
  end
  return out
end)

-- The worn items by slot (GetInventoryItemLink, in both P1 dumps; verified through the reward
-- comparison, W1).
define("shared", "GetEquippedLinks", function()
  local out = {}
  if type(GetInventoryItemLink) ~= "function" then
    return out
  end
  for slot = 1, 19 do
    local link = plain(GetInventoryItemLink("player", slot))
    local byID = rawget(_G, "GetInventoryItemID")
    if type(link) ~= "string" and type(byID) == "function" then
      -- the link withheld (a secret value on the retail family): the id still names the item
      local id = plain(byID("player", slot))
      link = id and ("item:" .. id) or nil
    end
    if link then
      out[slot] = link
    end
  end
  return out
end)

-- A global of the client's mail API, nil when the client lacks it.
local function mailApi(name)
  return rawget(_G, name)
end

-- The mailbox (GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem, GetInboxItemLink: the retail
-- family's globals, assumed on Forever until measured): every attachment and the money.
define("shared", "GetInboxItems", function()
  local numItems, header, item, itemLink =
    mailApi("GetInboxNumItems"),
    mailApi("GetInboxHeaderInfo"),
    mailApi("GetInboxItem"),
    mailApi("GetInboxItemLink")
  if type(numItems) ~= "function" or type(item) ~= "function" then
    return nil, nil
  end
  local rows, money = {}, 0
  local perMail = rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16
  for i = 1, numItems() or 0 do
    local cash = type(header) == "function" and select(5, header(i)) or nil
    if type(cash) == "number" then
      money = money + cash
    end
    for at = 1, perMail do
      local _, itemID, _, count, quality = item(i, at)
      if itemID then
        local link = type(itemLink) == "function" and itemLink(i, at) or nil
        rows[#rows + 1] = { itemID = itemID, count = count or 1, link = link, quality = quality }
      end
    end
  end
  return rows, money
end)

-- Writing a mail (the mail frame's send tab: MailFrameTab2, SendMailNameEditBox,
-- SendMailSubjectEditBox; ClickSendMailItemButton and C_Container.PickupContainerItem as Postal
-- and TSM's mailing use them; assumed on Forever). Never in combat.
define("shared", "MailPrepare", function(recipient, subject)
  if (type(InCombatLockdown) == "function" and InCombatLockdown()) or not _G.SendMailNameEditBox then
    return false
  end
  local tab = _G.MailFrameTab2
  if tab and tab.Click then
    tab:Click()
  end
  _G.SendMailNameEditBox:SetText(recipient or "")
  if _G.SendMailSubjectEditBox then
    _G.SendMailSubjectEditBox:SetText(subject or "")
  end
  return true
end)

local function sendSlots()
  return rawget(_G, "ATTACHMENTS_MAX_SEND") or 12
end

define("shared", "GetSendMailItems", function()
  local out = {}
  local get = mailApi("GetSendMailItem")
  if type(get) ~= "function" then
    return out
  end
  for i = 1, sendSlots() do
    local _, itemID, _, count = get(i)
    if itemID then
      out[itemID] = (out[itemID] or 0) + (count or 1)
    end
  end
  return out
end)

define("shared", "MailFreeSlots", function()
  if type(mailApi("GetSendMailItem")) ~= "function" then
    return 0
  end
  local free = 0
  for i = 1, sendSlots() do
    if not mailApi("GetSendMailItem")(i) then
      free = free + 1
    end
  end
  return free
end)

define("shared", "MailAttach", function(bag, slot)
  if
    (type(InCombatLockdown) == "function" and InCombatLockdown())
    or type(mailApi("ClickSendMailItemButton")) ~= "function"
    or type(mailApi("GetSendMailItem")) ~= "function"
    or not (type(C_Container) == "table" and C_Container.PickupContainerItem)
  then
    return false
  end
  for i = 1, sendSlots() do
    if not mailApi("GetSendMailItem")(i) then
      C_Container.PickupContainerItem(bag, slot)
      mailApi("ClickSendMailItemButton")(i)
      return true
    end
  end
  return false
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

-- The game's Key Bindings screen (the welcome's "Set the clear-screen key", plan-launch-review
-- O1): an addon cannot bind a key itself. The retail family opens the Settings panel's key
-- bindings category; the old client loads Blizzard_BindingUI (**assumed** on both clients
-- 01.11.2026, forever-api.md). -> whether a screen opened.
define("shared", "OpenKeyBindings", function()
  if Has.SettingsAPI and type(Settings.OpenToCategory) == "function" and Settings.KEYBINDINGS_CATEGORY_ID then
    note("OpenKeyBindings", "Settings.KEYBINDINGS_CATEGORY_ID")
    Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    return true
  end
  local load = rawget(_G, "KeyBindingFrame_LoadUI")
  if type(load) == "function" then
    note("OpenKeyBindings", "KeyBindingFrame_LoadUI")
    load()
    local frame, show = rawget(_G, "KeyBindingFrame"), rawget(_G, "ShowUIPanel")
    if frame and type(show) == "function" then
      show(frame)
      return true
    end
  end
  note("OpenKeyBindings", "no key bindings screen")
  return false
end)

-- The key set for a binding action (the app pages' Keys rows, the Help page): the first key the
-- game names, nil when none is set or the client lacks GetBindingKey (**assumed** on both clients
-- 01.11.2026, forever-api.md).
define("shared", "BindingKey", function(action)
  local get = rawget(_G, "GetBindingKey")
  if type(get) ~= "function" then
    note("BindingKey", "no GetBindingKey")
    return nil
  end
  local key = get(action)
  if key == nil or key == "" then
    return nil
  end
  return key
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

-- What an item is in the client's words: its kind and slot ("Mail", "Chest"), each nil where the
-- client has none or the item is not one to wear (ADR 0056, PA2.3). No request, no event: the
-- instant answer. Forever assumed 06.11.2026 (forever-api.md).
define("shared", "ItemKind", function(itemID)
  local api = rawget(_G, "C_Item")
  itemID = tonumber(itemID)
  if not (itemID and api and type(api.GetItemInfoInstant) == "function") then
    return nil, nil
  end
  local _, _, kind, equipLoc = api.GetItemInfoInstant(itemID)
  local slot = equipLoc and equipLoc ~= "" and rawget(_G, equipLoc) or nil
  note("ItemKind", "GetItemInfoInstant")
  return kind ~= "" and kind or nil, type(slot) == "string" and slot or nil
end)

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

-- The game's own window parts ("I need a clearly skinned style according
-- to Blizzard examples"): Blizzard's SharedXML templates, in Forever's UI files of 1.60.1 (the
-- Mainline SharedUIPanelTemplates.xml) and on retail. C_XMLUtil.GetTemplateInfo says whether the
-- client knows one; without that function the frame is tried. nil where the client lacks it.
local function templated(parent, template)
  local util = rawget(_G, "C_XMLUtil")
  if
    type(util) == "table"
    and type(util.GetTemplateInfo) == "function"
    and not util.GetTemplateInfo(template)
  then
    return nil
  end
  local ok, frame = pcall(CreateFrame, "Frame", nil, parent, template)
  return ok and frame or nil
end

-- PortraitFrameTemplate: the metal frame, the rock ground (`Bg`), the title bar (`SetTitle`), the
-- red close button (`CloseButton`) and the round portrait (`SetPortraitToAsset`).
define("shared", "NewGameWindow", function(parent)
  local frame = templated(parent, "PortraitFrameTemplate")
  if frame and frame.CloseButton and type(frame.SetPortraitToAsset) == "function" and frame.SetTitle then
    note("NewGameWindow", "PortraitFrameTemplate")
    return frame
  end
  if frame then
    frame:Hide()
  end
  return nil
end)

-- InsetFrameTemplate: the marble ground (`Bg`) in its bevelled edge, the game's inner panels.
define("shared", "NewInset", function(parent)
  local frame = templated(parent, "InsetFrameTemplate")
  if frame and frame.Bg then
    note("NewInset", "InsetFrameTemplate")
    return frame
  end
  if frame then
    frame:Hide()
  end
  return nil
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
  -- the distance stays unknown in combat: retail refuses CheckInteractDistance there (blocked 12x,
  -- taint log 31.10.2026, retail 12.1.5.70688)
  local within
  if not call("InCombatLockdown") then
    if call("CheckInteractDistance", unit, 3) then
      within = 10
    elseif call("CheckInteractDistance", unit, 1) then
      within = 28
    end
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

-- Whether the client hides auras from addons right now (C_Secrets.ShouldAurasBeSecret; false measured
-- out of combat, Forever 08.11.2026). Reading one then raises, no pcall needed: ask first.
define("shared", "AurasSecret", function()
  local secrets = rawget(_G, "C_Secrets")
  if not has(secrets, "ShouldAurasBeSecret") then
    return false
  end
  return plain(secrets.ShouldAurasBeSecret()) ~= false
end)

-- A unit's helpful auras with their end (C_UnitAuras.GetAuraDataByIndex, the retail family's
-- AuraData: expirationTime 0 for an aura without an end; assumed on Forever, probe C1).
define("shared", "UnitAuras", function(unit)
  local out = {}
  if not has(C_UnitAuras, "GetAuraDataByIndex") or Compat.AurasSecret() then
    return out
  end
  for i = 1, 80 do
    local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
    if type(a) ~= "table" then
      break
    end
    local id = plain(a.spellId)
    if id then
      local ends = plain(a.expirationTime)
      out[#out + 1] = {
        spellId = id,
        name = plain(a.name),
        expires = type(ends) == "number" and ends > 0 and ends or nil,
        duration = plain(a.duration),
        source = plain(a.sourceUnit),
      }
    end
  end
  note("UnitAuras", "C_UnitAuras")
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

-- Whether a tracking spell that shows creatures is on (Track Beasts and its kin): the classes that
-- have one, then an active spell that is not a gathering one. C_Minimap.GetTrackingInfo is in the
-- Forever dump, its shape assumed (forever-api.md): a table on the retail family, a list on Classic.
local CREATURE_TRACKERS = { HUNTER = true, DRUID = true, PALADIN = true, WARLOCK = true }
local GATHERING_SPELLS = { [2383] = true, [2580] = true, [2481] = true, [43308] = true }
define("shared", "CreatureTrackingOn", function()
  local class = select(2, UnitClass("player"))
  if not CREATURE_TRACKERS[plain(class)] then
    return false
  end
  if not (has(C_Minimap, "GetNumTrackingTypes") and has(C_Minimap, "GetTrackingInfo")) then
    return nil
  end
  for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
    local a, _, c, d, _, f = C_Minimap.GetTrackingInfo(i)
    local active, kind, spell = c, d, f
    if type(a) == "table" then
      active, kind, spell = a.active, a.type, a.spellID
    end
    if plain(active) and plain(kind) == "spell" and not GATHERING_SPELLS[plain(spell)] then
      return true
    end
  end
  return false
end)

-- The whole name of a unit, for a mail or a whisper. UnitName's second value is the surname on Forever
-- (measured 08.11.2026, 1.60.1.70862; the first name alone does not deliver), a realm on retail,
-- nil for the player's own realm. A mail takes "First Surname".
define("shared", "FullName", function(unit)
  local first, second = UnitName(unit)
  first, second = plain(first), plain(second)
  if type(first) ~= "string" or first == "" then
    return nil
  end
  if type(second) ~= "string" or second == "" then
    return first
  end
  return first .. (Bastians.Client == "forever" and " " or "-") .. second
end)

-- The client remembers a slash command's handler after its first use (hash_SlashCmdList, FrameXML;
-- assumed on Forever, forever-api.md): a handler changed later needs that one entry gone (ADR 0062).
-- Only an entry that exists is written.
define("shared", "ForgetSlash", function(command)
  local hash = rawget(_G, "hash_SlashCmdList")
  local key = string.upper(command)
  if type(hash) == "table" and hash[key] ~= nil then
    hash[key] = nil
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

-- The client's text-to-speech (assumed; forever-api.md, library.md 10.3, the Orbiter's fallback
-- where Spoken has no line, ). Both clients' SpeakText takes (voiceID, text, rate,
-- volume, overlap) (api stubs, 28.10.2026); the older (voiceID, text, destination, rate, volume)
-- put 0 into the volume and the owner heard nothing on retail. A client whose signature differs
-- answers false through pcall. The rate and volume are the player's under Accessibility
-- (C_TTSSettings). The voice is the caller's where it names one the client lists, else a woman's
-- voice by its name (the client's default is a man's, and nobody finds the
-- Accessibility setting), else the first voice the client lists.
local function ttsVoices()
  local vc = rawget(_G, "C_VoiceChat")
  if not (vc and vc.SpeakText and vc.GetTtsVoices) then
    return {}
  end
  local voices = vc.GetTtsVoices()
  return type(voices) == "table" and voices or {}
end

-- The women among the Windows (SAPI, OneCore) and macOS voices the clients list, by first name.
local WOMEN_VOICES = {
  "zira",
  "hazel",
  "susan",
  "linda",
  "catherine",
  "hedda",
  "katja",
  "hortense",
  "julie",
  "caroline",
  "helena",
  "laura",
  "sabina",
  "elsa",
  "haruka",
  "ayumi",
  "huihui",
  "yaoyao",
  "hanhan",
  "tracy",
  "heami",
  "heera",
  "kalpana",
  "irina",
  "paulina",
  "herena",
  "maria",
  "lucia",
  "helia",
  "hilda",
  "hoda",
  "salma",
  "samantha",
  "victoria",
  "karen",
  "moira",
  "tessa",
  "fiona",
  "kate",
  "serena",
  "amelie",
  "anna",
  "alice",
  "alva",
  "ellen",
  "ioana",
  "joana",
  "kyoko",
  "lekha",
  "luciana",
  "mariska",
  "melina",
  "milena",
  "monica",
  "nora",
  "sara",
  "satu",
  "yuna",
  "zosia",
  "zuzana",
}

local function womanVoice(voices)
  for _, v in ipairs(voices) do
    local name = type(v.name) == "string" and v.name:lower() or ""
    for _, woman in ipairs(WOMEN_VOICES) do
      if name:find(woman, 1, true) and v.voiceID then
        return v.voiceID
      end
    end
  end
  return nil
end

define("shared", "CanSpeak", function()
  local voices = ttsVoices()
  return voices[1] ~= nil and voices[1].voiceID ~= nil
end)

define("shared", "Voices", function()
  local out = {}
  for _, v in ipairs(ttsVoices()) do
    if v.voiceID then
      out[#out + 1] =
        { voiceID = v.voiceID, name = type(v.name) == "string" and v.name or tostring(v.voiceID) }
    end
  end
  return out
end)

define("shared", "Speak", function(text, voiceID)
  local vc = rawget(_G, "C_VoiceChat")
  if type(text) ~= "string" or text == "" then
    return false
  end
  local voices = ttsVoices()
  if not (voices[1] and voices[1].voiceID) then
    return false
  end
  local voice, rate, volume = nil, 0, 100
  for _, v in ipairs(voices) do
    if voiceID ~= nil and v.voiceID == voiceID then
      voice = voiceID
    end
  end
  voice = voice or womanVoice(voices) or voices[1].voiceID
  local T = rawget(_G, "C_TTSSettings")
  if has(T, "GetSpeechRate") then
    rate = tonumber(T.GetSpeechRate()) or rate
  end
  if has(T, "GetSpeechVolume") then
    volume = tonumber(T.GetSpeechVolume()) or volume
  end
  if vc.StopSpeakingText then
    pcall(vc.StopSpeakingText) -- one text at a time
  end
  return pcall(vc.SpeakText, voice, text, rate, volume, false) == true
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
  -- above the suite's windows (FULLSCREEN_DIALOG): the picker opened behind the settings (owner,
  -- retail 31.10.2026)
  if type(f.SetFrameStrata) == "function" then
    f:SetFrameStrata("TOOLTIP")
    f:Raise()
  end
  return true
end)

-- ---------------------------------------------------------------------------------------------
-- Bastian's Helpers (helpers.md): the merchant, the mailbox, quest givers, durability, bags. The
-- retail family's globals and C_GossipInfo; every one is in both P1 dumps (Forever 21.10.2026,
-- retail 22.10.2026), the behaviour assumed until the helpers' in-game checklist (forever-api.md).
-- ---------------------------------------------------------------------------------------------

-- A global function of the client, nil when it lacks it (the legacy globals are no stubs).
local function api(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn or nil
end

local function shown(name)
  local f = rawget(_G, name)
  return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() and true or false
end

-- Calls the client function `name` with the arguments: true when the client has it.
local function invoke(name, ...)
  local fn = api(name)
  if not fn then
    return false
  end
  fn(...)
  return true
end

define("shared", "MerchantRepair", function()
  local cost = api("GetRepairAllCost")
  if not (shown("MerchantFrame") and cost) then
    return nil
  end
  local amount, can = cost()
  local merchant, guild, withdraw =
    api("CanMerchantRepair"), api("CanGuildBankRepair"), api("GetGuildBankWithdrawMoney")
  local guildMoney = withdraw and plain(withdraw()) or nil
  if type(guildMoney) == "number" and guildMoney < 0 then
    guildMoney = nil -- the guild master: no limit
  end
  return {
    canRepair = (merchant == nil or merchant()) and can and true or false,
    cost = plain(amount) or 0,
    guild = guild ~= nil and guild() and true or false,
    guildMoney = guildMoney,
  }
end)

define("shared", "RepairAll", function(useGuild)
  return invoke("RepairAllItems", useGuild and true or nil)
end)

-- Selling is "using" the stack while the merchant listens: with the window closed the same call
-- would equip, eat or open the item, so it is refused then.
define("shared", "SellBagItem", function(bag, slot)
  if not (shown("MerchantFrame") and has(C_Container, "UseContainerItem")) then
    return false
  end
  C_Container.UseContainerItem(bag, slot)
  return true
end)

define("shared", "MerchantBuy", function(index, count)
  return shown("MerchantFrame") and invoke("BuyMerchantItem", index, count)
end)

define("shared", "MerchantMaxStack", function(index)
  local max = api("GetMerchantItemMaxStack")
  local n = max and max(index)
  return type(n) == "number" and n > 0 and n or nil
end)

define("shared", "GetBuybackItems", function()
  local out = {}
  local num, link, info = api("GetNumBuybackItems"), api("GetBuybackItemLink"), api("GetBuybackItemInfo")
  if not (num and link) then
    return out
  end
  for i = 1, num() or 0 do
    local id = tonumber(string.match(tostring(link(i) or ""), "item:(%d+)"))
    if id then
      local count, price = 1, nil
      if info then
        local _, _, p, n = info(i)
        price, count = p, n or 1
      end
      out[#out + 1] = { index = i, itemID = id, count = count, price = price }
    end
  end
  return out
end)

define("shared", "Buyback", function(index)
  return shown("MerchantFrame") and invoke("BuybackItem", index)
end)

define("shared", "GetInboxMail", function()
  local out = {}
  local num, header, item = api("GetInboxNumItems"), api("GetInboxHeaderInfo"), api("GetInboxItem")
  if not (num and header) then
    return out
  end
  local perMail = item and (rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16) or 0
  for i = 1, num() or 0 do
    local _, _, sender, subject, money, cod = header(i)
    local items = 0
    for a = 1, perMail do
      if select(2, item(i, a)) then
        items = items + 1
      end
    end
    out[#out + 1] = {
      index = i,
      sender = plain(sender),
      subject = plain(subject),
      money = money or 0,
      cod = cod or 0,
      items = items,
    }
  end
  return out
end)

define("shared", "TakeInboxMoney", function(index)
  return invoke("TakeInboxMoney", index)
end)

define("shared", "TakeInboxItems", function(index)
  return invoke("AutoLootMailItem", index)
end)

define("shared", "MailRecipient", function(name)
  local box = rawget(_G, "SendMailNameEditBox")
  if (type(InCombatLockdown) == "function" and InCombatLockdown()) or not box then
    return false
  end
  box:SetText(name or "")
  return true
end)

define("shared", "MailRecipientText", function()
  local box = rawget(_G, "SendMailNameEditBox")
  return box and box:GetText() or nil
end)

-- An auto-accepted quest only wants the acknowledgement (QuestGetAutoAccept, retail family).
define("shared", "QuestAccept", function(kind)
  if kind == "confirm" then
    return invoke("ConfirmAcceptQuest")
  end
  local auto = api("QuestGetAutoAccept")
  if auto and auto() and invoke("AcknowledgeAutoAcceptQuest") then
    return true
  end
  return invoke("AcceptQuest")
end)

define("shared", "QuestProgress", function()
  local completable, money = api("IsQuestCompletable"), api("GetQuestMoneyToGet")
  return completable ~= nil and completable() and true or false, money and money() or 0
end)

define("shared", "QuestContinue", function()
  return invoke("CompleteQuest")
end)

define("shared", "QuestChoices", function()
  local out = {}
  local num, link, info = api("GetNumQuestChoices"), api("GetQuestItemLink"), api("GetQuestItemInfo")
  for i = 1, num and num() or 0 do
    local id = link and tonumber(string.match(tostring(link("choice", i) or ""), "item:(%d+)")) or nil
    local count = info and select(3, info("choice", i)) or 1
    out[#out + 1] = { index = i, itemID = id, count = count }
  end
  return out
end)

define("shared", "QuestTakeReward", function(index)
  return invoke("GetQuestReward", index)
end)

-- A quest's rewards as the client says them (ADR 0053). All of these are in the Forever P1 dump,
-- their answers assumed from retail (forever-api.md); a zero or a secret value says nothing here.
local function paid(value)
  value = plain(value)
  return type(value) == "number" and value > 0 and value or nil
end

-- { { itemID, count } } of `n` rewards, nil without one. info(i) -> name, icon, count, quality,
-- usable, itemID; the link stands in where the id is missing.
local function rewardItems(n, info, link)
  local out = {}
  for i = 1, plain(n) or 0 do
    local _, _, count, _, _, itemID = info(i)
    itemID = plain(itemID) or tonumber(string.match(tostring(link and link(i) or ""), "item:(%d+)"))
    if itemID then
      out[#out + 1] = { itemID, plain(count) or 1 }
    end
  end
  return #out > 0 and out or nil
end

local function lineOf(fn, ...)
  local args = { ... }
  return function(i)
    if not fn then
      return nil
    end
    local argv = { unpack(args) }
    table.insert(argv, 2, i) -- GetQuestLogItemLink(kind, i, questID), GetQuestItemLink(kind, i)
    return fn(unpack(argv))
  end
end

-- The rewards of a log quest. On Classic Era these functions ignore the id and answer for the
-- selected quest (EverythingQuests measured it, 2026-10-20), so the quest is selected first and the
-- selection restored. Nil when the client says nothing: unknown, never "no reward".
define("shared", "GetQuestLogRewards", function(questID)
  if
    not (
      questID
      and has(C_QuestLog, "SetSelectedQuest")
      and has(C_QuestLog, "GetLogIndexForQuestID")
      and C_QuestLog.GetLogIndexForQuestID(questID)
    )
  then
    return nil
  end
  local money, xp = api("GetQuestLogRewardMoney"), api("GetQuestLogRewardXP")
  local numItems, itemInfo = api("GetNumQuestLogRewards"), api("GetQuestLogRewardInfo")
  local numChoices, choiceInfo = api("GetNumQuestLogChoices"), api("GetQuestLogChoiceInfo")
  local link = api("GetQuestLogItemLink")
  local before = has(C_QuestLog, "GetSelectedQuest") and C_QuestLog.GetSelectedQuest() or nil
  C_QuestLog.SetSelectedQuest(questID)
  local out = {
    money = money and paid(money(questID)) or nil,
    xp = xp and paid(xp(questID)) or nil,
  }
  if numItems and itemInfo then
    out.items = rewardItems(numItems(questID), function(i)
      return itemInfo(i, questID)
    end, lineOf(link, "reward", questID))
  end
  if numChoices and choiceInfo then
    out.choices = rewardItems(numChoices(questID, true), function(i)
      return choiceInfo(i, questID)
    end, lineOf(link, "choice", questID))
  end
  if before and before > 0 and before ~= questID then
    C_QuestLog.SetSelectedQuest(before)
  end
  if next(out) == nil then
    return nil
  end
  note("GetQuestLogRewards", "GetQuestLogRewardMoney")
  return out
end)

-- The rewards of the quest a giver shows now (QUEST_DETAIL, QUEST_COMPLETE); nil when it says none.
define("shared", "GetOfferRewards", function()
  local money, xp = api("GetRewardMoney"), api("GetRewardXP")
  local numItems, numChoices = api("GetNumQuestRewards"), api("GetNumQuestChoices")
  local info, link = api("GetQuestItemInfo"), api("GetQuestItemLink")
  local out = { money = money and paid(money()) or nil, xp = xp and paid(xp()) or nil }
  if info and numItems then
    out.items = rewardItems(numItems(), function(i)
      return info("reward", i)
    end, lineOf(link, "reward"))
  end
  if info and numChoices then
    out.choices = rewardItems(numChoices(), function(i)
      return info("choice", i)
    end, lineOf(link, "choice"))
  end
  if next(out) == nil then
    return nil
  end
  note("GetOfferRewards", "GetRewardMoney")
  return out
end)

define("shared", "GreetingQuests", function()
  local active, available = {}, {}
  local numActive, activeTitle = api("GetNumActiveQuests"), api("GetActiveTitle")
  local numAvailable, availableTitle = api("GetNumAvailableQuests"), api("GetAvailableTitle")
  for i = 1, numActive and numActive() or 0 do
    local title, complete
    if activeTitle then
      title, complete = activeTitle(i)
    end
    active[#active + 1] = { index = i, title = plain(title), complete = complete and true or false }
  end
  for i = 1, numAvailable and numAvailable() or 0 do
    available[#available + 1] = { index = i, title = availableTitle and plain(availableTitle(i)) or nil }
  end
  return active, available
end)

-- The giver of the open window (UnitGUID("npc"), as Voice reads it).
define("shared", "NpcEntity", function()
  return Compat.EntityFromGUID(type(UnitGUID) == "function" and plain(UnitGUID("npc")) or nil)
end)

-- UnitQuestTrivialLevelRange: in both clients' dumps, assumed until seen (forever-api.md).
define("shared", "QuestTrivialRange", function()
  local range = api("UnitQuestTrivialLevelRange")
  return range and plain(range("player")) or nil
end)

-- The realm's clock (C_DateAndTime: in both clients' dumps, assumed until seen). A time without
-- its hour is no time: 00:00 would read as before every event's start.
define("shared", "CalendarNow", function()
  if not has(C_DateAndTime, "GetCurrentCalendarTime") then
    return nil
  end
  local t = C_DateAndTime.GetCurrentCalendarTime()
  local month, day, hour = plain(t and t.month), plain(t and t.monthDay), plain(t and t.hour)
  if not (month and day and hour) then
    return nil
  end
  return {
    year = plain(t.year),
    month = month,
    day = day,
    weekday = plain(t.weekday),
    hour = hour,
    minute = plain(t.minute) or 0,
  }
end)

define("shared", "GossipQuests", function()
  local active, available = {}, {}
  if has(C_GossipInfo, "GetActiveQuests") then
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
      active[#active + 1] =
        { questID = q.questID, title = plain(q.title), complete = q.isComplete and true or false }
    end
  end
  if has(C_GossipInfo, "GetAvailableQuests") then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      available[#available + 1] = { questID = q.questID, title = plain(q.title) }
    end
  end
  return active, available
end)

define("shared", "GossipOptions", function()
  local out = {}
  if has(C_GossipInfo, "GetOptions") then
    for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
      out[#out + 1] = { id = o.gossipOptionID, name = plain(o.name) }
    end
  end
  return out
end)

-- The gossip frame selects by option and quest id (C_GossipInfo), the greeting frame by list index.
local GOSSIP_SELECT =
  { option = "SelectOption", active = "SelectActiveQuest", available = "SelectAvailableQuest" }
local GREETING_SELECT = { active = "SelectActiveQuest", available = "SelectAvailableQuest" }
define("shared", "NpcSelect", function(frame, kind, id)
  if id == nil then
    return false
  end
  if frame == "gossip" then
    local fn = GOSSIP_SELECT[kind]
    if not (fn and has(C_GossipInfo, fn)) then
      return false
    end
    C_GossipInfo[fn](id)
    return true
  elseif frame == "greeting" and GREETING_SELECT[kind] then
    return invoke(GREETING_SELECT[kind], id)
  end
  return false
end)

-- The quest frame's texts (Bastian's Voice draws the conversation itself).
define("shared", "QuestDetail", function()
  local title = api("GetTitleText")
  if not title then
    return nil
  end
  local function text(name)
    local fn = api(name)
    local value = fn and fn()
    return type(value) == "string" and value ~= "" and plain(value) or nil
  end
  return {
    title = plain(title()),
    text = text("GetQuestText"),
    objectives = text("GetObjectiveText"),
    reward = text("GetRewardText"),
    progress = text("GetProgressText"),
  }
end)

define("shared", "QuestID", function()
  local fn = api("GetQuestID")
  local id = fn and fn()
  return type(id) == "number" and id > 0 and id or nil
end)

define("shared", "QuestDecline", function()
  return invoke("DeclineQuest")
end)

define("shared", "NpcClose", function()
  local closed = false
  if has(C_GossipInfo, "CloseGossip") then
    C_GossipInfo.CloseGossip()
    closed = true
  elseif api("CloseGossip") then
    closed = invoke("CloseGossip") or closed
  end
  if api("CloseQuest") then
    closed = invoke("CloseQuest") or closed
  end
  return closed
end)

-- The game's NPC windows stay built and keep their events; they are only made invisible and
-- deaf to the mouse (as DialogueUI does), never re-parented, and left alone in combat the first
-- time (a protected frame is not touched then).
local npcFramesHidden = false
define("shared", "NpcFramesHidden", function(hidden)
  hidden = hidden and true or false
  if hidden == npcFramesHidden then
    return false
  end
  if hidden and type(InCombatLockdown) == "function" and InCombatLockdown() then
    return false
  end
  for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
    local frame = rawget(_G, name)
    if type(frame) == "table" and frame.SetAlpha then
      frame:SetAlpha(hidden and 0 or 1)
      if frame.EnableMouse then
        frame:EnableMouse(not hidden)
      end
    end
  end
  npcFramesHidden = hidden
  return true
end)

-- The character's saved instances (the raid info; Alts' lockouts, A2.5): { { name, instance
-- (Map.db2 id, the 14th value of GetSavedInstanceInfo), reset (seconds left), locked, raid } };
-- nil when the client has no raid info API. RequestRaidInfo asks the server for a fresh list, which
-- arrives with UPDATE_INSTANCE_INFO (assumed on Forever, forever-api.md).
define("shared", "SavedInstances", function()
  local count, info = fnOf("GetNumSavedInstances"), fnOf("GetSavedInstanceInfo")
  if not (count and info) then
    return nil
  end
  local out = {}
  for i = 1, plain(count()) or 0 do
    local name, _, reset, _, locked, _, _, raid, _, _, _, _, _, instanceID = info(i)
    instanceID = plain(instanceID)
    out[#out + 1] = {
      name = plain(name),
      instance = type(instanceID) == "number" and instanceID > 0 and instanceID or nil,
      reset = plain(reset),
      locked = plain(locked) == true,
      raid = plain(raid) == true,
    }
  end
  return out
end)

define("shared", "RequestRaidInfo", function()
  local f = fnOf("RequestRaidInfo")
  if f then
    f()
    return true
  end
  return false
end)

define("shared", "InstanceMap", function()
  local inside = fnOf("IsInInstance")
  local info = fnOf("GetInstanceInfo")
  if not (inside and info) then
    return nil
  end
  local is, kind = inside()
  if not is or (kind ~= "party" and kind ~= "raid") then
    return nil
  end
  local name, _, _, _, _, _, _, instanceID = info()
  instanceID = plain(instanceID)
  if type(instanceID) ~= "number" or instanceID <= 0 then
    return nil
  end
  return instanceID, plain(name)
end)

define("shared", "PushQuest", function(questID)
  if
    not (
      api("QuestLogPushQuest")
      and has(C_QuestLog, "IsPushableQuest")
      and C_QuestLog.IsPushableQuest(questID)
    )
  then
    return false
  end
  if has(C_QuestLog, "SetSelectedQuest") then
    C_QuestLog.SetSelectedQuest(questID)
  end
  return invoke("QuestLogPushQuest")
end)

define("shared", "GetDurability", function()
  local get = api("GetInventoryItemDurability")
  if not get then
    return nil
  end
  local lowest, broken
  for slot = 1, 19 do
    local cur, max = get(slot)
    if type(cur) == "number" and type(max) == "number" and max > 0 then
      lowest = math.min(lowest or 1, cur / max)
      broken = (broken or 0) + (cur == 0 and 1 or 0)
    end
  end
  return lowest, broken
end)

define("shared", "BagSpace", function()
  if not has(C_Container, "GetContainerNumFreeSlots") then
    return nil, nil
  end
  local free, total = 0, 0
  for bag = 0, rawget(_G, "NUM_BAG_SLOTS") or 4 do
    local n, family = C_Container.GetContainerNumFreeSlots(bag)
    if (family or 0) == 0 then -- general bags only: a herb bag takes no cloth
      free = free + (n or 0)
      total = total + (C_Container.GetContainerNumSlots(bag) or 0)
    end
  end
  return free, total
end)

-- The chat window of a tab name (GetChatWindowInfo: name first; ChatFrame1..NUM_CHAT_WINDOWS;
-- in both P1 dumps, assumed): the addon chat of Core's notices.
define("shared", "ChatFrameNamed", function(name)
  local info = api("GetChatWindowInfo")
  if not (info and type(name) == "string" and name ~= "") then
    return nil
  end
  local want = string.lower(name)
  for i = 1, rawget(_G, "NUM_CHAT_WINDOWS") or 10 do
    local tab = plain(info(i))
    local frame = rawget(_G, "ChatFrame" .. i)
    if type(tab) == "string" and string.lower(tab) == want and frame then
      return frame
    end
  end
  return nil
end)

-- Links in a frame's texts (`|H...|h...|h`): Frame:SetHyperlinksEnabled, then the frame's
-- OnHyperlinkEnter, OnHyperlinkLeave and OnHyperlinkClick scripts fire (retail's API docs; assumed
-- on Forever, forever-api.md: the gold book's names, 07.11.2026). -> true when the frame took it.
define("shared", "EnableLinks", function(frame)
  local ok = pcall(function()
    frame:SetHyperlinksEnabled(true)
  end)
  return ok
end)

local MODIFIERS = { shift = "IsShiftKeyDown", ctrl = "IsControlKeyDown", alt = "IsAltKeyDown" }
define("shared", "ModifierDown", function(key)
  local fn = api(MODIFIERS[key] or "")
  return fn ~= nil and fn() and true or false
end)
