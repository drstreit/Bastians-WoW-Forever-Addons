-- Compat layer "modern": the retail API family (quest log, taxi, tooltips, merchant, trainer, retail order).
local _, ns = ...
local Compat = ns.Compat
local define, note = ns.Compat.define, ns.Compat.note
local Has = Compat.Has

-- ---------------------------------------------------------------------------------------------
-- Quest log (C_QuestLog: 90 functions identical to retail; runtime shape is probe P2)
-- ---------------------------------------------------------------------------------------------

define("modern", "GetQuestLogEntries", function()
  local out = {}
  local header
  for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
    local info = C_QuestLog.GetInfo(i)
    if info then
      if info.isHeader then
        header = info.title
      elseif info.questID and info.questID > 0 then
        local id = info.questID
        local entry = {
          index = i,
          questID = id,
          title = info.title,
          level = info.level,
          header = header,
          isComplete = C_QuestLog.IsComplete(id) or false,
          readyForTurnIn = C_QuestLog.ReadyForTurnIn(id) or false,
          objectives = {},
        }
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
          entry.objectives[#entry.objectives + 1] = {
            text = o.text,
            kind = o.type,
            finished = o.finished or false,
            fulfilled = o.numFulfilled,
            required = o.numRequired,
          }
        end
        out[#out + 1] = entry
      end
    end
  end
  return out
end)

define("modern", "GetCompletedQuestIDs", function()
  return C_QuestLog.GetAllCompletedQuestIDs() or {}
end)

define("modern", "IsQuestCompleted", function(questID)
  return C_QuestLog.IsQuestFlaggedCompleted(questID) or false
end)

-- Objective tracker (C_QuestLog watch functions: identical in both API docs, one argument).
define("modern", "GetWatchedQuestIDs", function()
  local out = {}
  for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
    local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
    if id and id > 0 then
      out[#out + 1] = id
    end
  end
  return out
end)

define("modern", "SetQuestWatched", function(questID, on)
  local watched = C_QuestLog.GetQuestWatchType(questID) ~= nil
  if on and not watched then
    return C_QuestLog.AddQuestWatch(questID) and true or false
  elseif not on and watched then
    return C_QuestLog.RemoveQuestWatch(questID) and true or false
  end
  return false
end)

-- The quest's usable item (legacy global, used by Blizzard's own objective tracker on both clients).
define("modern", "GetQuestItem", function(questLogIndex)
  if type(GetQuestLogSpecialItemInfo) ~= "function" or not questLogIndex then
    return nil
  end
  local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(questLogIndex)
  local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
  if not itemID then
    return nil
  end
  local count = C_Item.GetItemCount(itemID) or 0
  return {
    itemID = itemID,
    link = link,
    icon = icon,
    charges = charges,
    showWhenComplete = showWhenComplete or false,
    inBags = count > 0,
  }
end)

-- Quest text in the client's language: needs the quest selected; the selection is restored.
define("modern", "GetQuestText", function(questID)
  if type(GetQuestLogQuestText) ~= "function" or not C_QuestLog.SetSelectedQuest then
    return nil
  end
  local before = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or nil
  C_QuestLog.SetSelectedQuest(questID)
  local details, objectives = GetQuestLogQuestText()
  if before and before > 0 and before ~= questID then
    C_QuestLog.SetSelectedQuest(before)
  end
  if details == "" then
    details = nil
  end
  return details, objectives
end)

-- ---------------------------------------------------------------------------------------------
-- Taxi (C_TaxiMap.GetAllTaxiNodes documented identically on both; runtime shape is probe P7 = assumed).
-- The legacy NumTaxiNodes path has no node IDs; it is the fallback and keeps `id` nil.
-- ---------------------------------------------------------------------------------------------

local STATE_NAMES = { [0] = "current", [1] = "reachable", [2] = "unreachable" }
local LEGACY_STATES = { CURRENT = "current", REACHABLE = "reachable", DISTANT = "unreachable" }

local function taxiMapID()
  if type(GetTaxiMapID) == "function" then
    local id = GetTaxiMapID()
    if id and id > 0 then
      return id
    end
  end
  return C_Map.GetBestMapForUnit("player")
end

define("modern", "GetTaxiNodes", function()
  local out = {}
  local map = taxiMapID()
  if not map then
    return out
  end
  if type(C_TaxiMap) == "table" and type(C_TaxiMap.GetAllTaxiNodes) == "function" then
    local states = type(Enum) == "table" and Enum.FlightPathState or nil
    local nodes = C_TaxiMap.GetAllTaxiNodes(map)
    if nodes and #nodes > 0 then
      note("GetTaxiNodes", "C_TaxiMap.GetAllTaxiNodes")
      for _, n in ipairs(nodes) do
        local x, y
        if n.position and n.position.GetXY then
          x, y = n.position:GetXY()
        elseif n.position then
          x, y = n.position.x, n.position.y
        end
        local state = n.state
        if states then
          state = state == states.Current and "current"
            or state == states.Reachable and "reachable"
            or state == states.Unreachable and "unreachable"
            or nil
        else
          state = STATE_NAMES[state]
        end
        out[#out + 1] = { id = n.nodeID, name = n.name, map = map, x = x, y = y, state = state }
      end
      return out
    end
  end
  if type(NumTaxiNodes) ~= "function" then
    return out
  end
  note("GetTaxiNodes", "NumTaxiNodes")
  for i = 1, NumTaxiNodes() or 0 do
    local x, y = TaxiNodePosition(i)
    out[#out + 1] = {
      id = nil,
      name = TaxiNodeName(i),
      map = map,
      x = x,
      y = y,
      state = LEGACY_STATES[TaxiNodeGetType(i)],
    }
  end
  return out
end)

-- ---------------------------------------------------------------------------------------------
-- Merchant (C_MerchantFrame.GetItemInfo documented on both; the link comes from the legacy global)
-- ---------------------------------------------------------------------------------------------

define("modern", "GetNumMerchantItems", function()
  return GetMerchantNumItems() or 0
end)

define("modern", "GetMerchantItem", function(index)
  local info = C_MerchantFrame.GetItemInfo(index)
  if not info or not info.name then
    return nil
  end
  local link = GetMerchantItemLink(index)
  return {
    index = index,
    itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil,
    link = link,
    name = info.name,
    icon = info.texture,
    price = info.price,
    stack = info.stackCount,
    numAvailable = info.numAvailable,
    isPurchasable = info.isPurchasable,
    isUsable = info.isUsable,
    hasExtendedCost = info.hasExtendedCost,
    currencyID = info.currencyID,
    spellID = info.spellID,
  }
end)

-- ---------------------------------------------------------------------------------------------
-- Trainer: legacy globals, not in the generated docs. Order name, subtext, kind, expanded is the
-- retail/Classic FrameXML convention (assumed); Forever overrides this in Compat/Forever.lua (verified).
-- ---------------------------------------------------------------------------------------------

function ns.Compat.trainerCommon(index, entry)
  entry.cost = GetTrainerServiceCost(index)
  local skill, rank = GetTrainerServiceSkillReq(index)
  if skill then
    entry.skillReq = { name = skill, rank = rank }
  end
  entry.levelReq = GetTrainerServiceLevelReq(index)
  local link = type(GetTrainerServiceItemLink) == "function" and GetTrainerServiceItemLink(index) or nil
  if type(link) == "string" then
    entry.itemID = tonumber(string.match(link, "item:(%d+)"))
    entry.spellID = tonumber(string.match(link, "spell:(%d+)") or string.match(link, "enchant:(%d+)"))
  end
  return entry
end

define("modern", "GetTrainerFilter", function(kind)
  if type(GetTrainerServiceTypeFilter) ~= "function" then
    return nil
  end
  local on = GetTrainerServiceTypeFilter(kind)
  return on == true or on == 1
end)

define("modern", "IsTradeskillTrainer", function()
  if type(IsTradeskillTrainer) ~= "function" then
    return nil
  end
  return IsTradeskillTrainer() and true or false
end)

define("modern", "GetNumTrainerServices", function()
  return GetNumTrainerServices() or 0
end)

define("modern", "GetTrainerService", function(index)
  local name, subtext, kind, expanded = GetTrainerServiceInfo(index)
  if not name then
    return nil
  end
  local entry = { index = index, name = name, subtext = subtext, kind = kind }
  if kind == "header" then
    entry.expanded = expanded ~= false and expanded ~= 0
  end
  return ns.Compat.trainerCommon(index, entry)
end)

define("modern", "SetTrainerFilter", function(kind, on)
  note("SetTrainerFilter", "number")
  SetTrainerServiceTypeFilter(kind, on and 1 or 0)
end)

-- ---------------------------------------------------------------------------------------------
-- Tooltips: TooltipDataProcessor when present, GameTooltip script hooks otherwise (probe P6)
-- ---------------------------------------------------------------------------------------------

local KIND_TO_ENUM = { unit = "Unit", item = "Item", spell = "Spell", object = "Object" }
local KIND_TO_SCRIPT = { unit = "OnTooltipSetUnit", item = "OnTooltipSetItem", spell = "OnTooltipSetSpell" }
local hooks = { unit = {}, item = {}, spell = {}, object = {} }
local installed = {}

local function npcIDFromGUID(guid)
  return guid and tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
end

local function dispatch(kind, tooltip, info)
  for _, fn in ipairs(hooks[kind]) do
    fn(tooltip, info)
  end
end

local function installProcessor(kind)
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[KIND_TO_ENUM[kind]], function(tooltip, data)
    local plain = Compat.Plain -- a secret id or GUID is unknown, never indexed (Z2, 23.10.2026)
    local info = {
      kind = kind,
      id = data and plain(data.id),
      guid = data and plain(data.guid),
      link = data and plain(data.hyperlink),
    }
    if (kind == "unit" or kind == "object") and not info.id then
      info.id = npcIDFromGUID(info.guid) -- GameObject GUIDs carry the id in the same field
    end
    dispatch(kind, tooltip, info)
  end)
end

local function installScript(kind)
  local script = KIND_TO_SCRIPT[kind]
  if not (script and GameTooltip:HasScript(script)) then
    return false
  end
  GameTooltip:HookScript(script, function(tooltip)
    local info = { kind = kind }
    if kind == "unit" then
      local _, unit = tooltip:GetUnit()
      info.guid = unit and Compat.Plain(UnitGUID(unit)) or nil
      info.id = npcIDFromGUID(info.guid)
    elseif kind == "item" then
      local _, link = tooltip:GetItem()
      info.link = link
      info.id = link and tonumber(string.match(link, "item:(%d+)")) or nil
    end
    dispatch(kind, tooltip, info)
  end)
  return true
end

define("modern", "HookTooltip", function(kind, fn)
  local list = hooks[kind]
  if not list then
    error(("HookTooltip: unknown kind %s"):format(tostring(kind)), 2)
  end
  list[#list + 1] = fn
  if installed[kind] then
    return
  end
  installed[kind] = true
  if Has.TooltipDataProcessor and Enum.TooltipDataType[KIND_TO_ENUM[kind]] then
    note("HookTooltip", "TooltipDataProcessor")
    installProcessor(kind)
  elseif installScript(kind) then
    note("HookTooltip", "script hooks")
  else
    note("HookTooltip", "no hook for " .. kind)
  end
end)
