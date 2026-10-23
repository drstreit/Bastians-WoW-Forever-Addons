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
  local _, _, classID = UnitClass("player")
  local _, _, raceID = UnitRace("player")
  local faction = UnitFactionGroup("player")
  return { level = UnitLevel("player"), raceID = raceID, classID = classID, faction = faction }
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
