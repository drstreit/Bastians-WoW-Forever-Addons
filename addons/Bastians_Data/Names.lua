-- Bastian's Data: names the packs do not carry, asked from the client (data.md "Retail data").
-- The retail sources store no quest titles and few NPC names, and the Items pack holds referenced
-- items only. Answers are cached per session; a name that arrives later (QUEST_DATA_LOAD_RESULT,
-- ITEM_DATA_LOAD_RESULT) invalidates the entity cache once, coalesced.
local _, ns = ...
local B = Bastians
local Data = ns.Data

local Names = { cache = {}, requested = {} } -- cache["quest:1"] = name or false (asked, unknown)
Data.Names = Names

local INVALIDATE_DELAY = 0.2 -- seconds after the last arrival before the entity cache is bumped
-- The store: every name the client answers is kept in
-- BastiansDataDB.global.names[typ][id], so the next session knows it at once and the search finds
-- it ("A Song for Our Future" was in the log, its name shown, and the search had never heard of
-- it). Capped: past STORE_CAP names the oldest fifth goes (an insertion list keeps the order).
Names.STORE_CAP = 20000
local STORE_TYPES = { quest = true, item = true, npc = true }
local store -- global.names: { quest = { [id] = name }, item = {}, npc = {}, order = { "quest:1", ... } }
local mod -- the Data module, set by Names.Attach

local function key(typ, id)
  return typ .. ":" .. tostring(id)
end

local function remember(typ, id, name)
  if not (store and STORE_TYPES[typ]) or store[typ][id] == name then
    return
  end
  if store[typ][id] == nil then
    store.order[#store.order + 1] = key(typ, id)
    if #store.order > Names.STORE_CAP then
      local keep, from = {}, math.floor(Names.STORE_CAP / 5)
      for i = 1, from do
        local t, i2 = string.match(store.order[i], "^(%a+):(%d+)$")
        if t and store[t] then
          store[t][tonumber(i2)] = nil
        end
      end
      for i = from + 1, #store.order do
        keep[#keep + 1] = store.order[i]
      end
      store.order = keep
    end
  end
  store[typ][id] = name
end

-- The stored names of a type: { [id] = name }, empty without a store (the search reads it).
function Names.Store(typ)
  return store and store[typ] or {}
end

local function invalidateLater(typ)
  if mod then
    mod:Coalesce("names-" .. typ, INVALIDATE_DELAY, function()
      B:InvalidateEntities(typ)
    end)
  end
end

-- The client's name for an entity, or nil. Quests and items the client has not loaded are
-- requested once; their names come through the load events.
function Names.Get(typ, id)
  if type(id) ~= "number" then
    return nil
  end
  local k = key(typ, id)
  local cached = Names.cache[k]
  if cached ~= nil then
    return cached or nil
  end
  local stored = store and STORE_TYPES[typ] and store[typ][id]
  if stored then
    Names.cache[k] = stored -- known from an earlier session: no client call
    return stored
  end
  local name
  if typ == "quest" then
    name = B.Compat.GetQuestName(id)
    if not name and not Names.requested[k] then
      Names.requested[k] = B.Compat.RequestQuestData(id)
    end
  elseif typ == "item" then
    local info = B.Compat.GetItemInfo(id)
    name = info and info.name or nil
    if not name and not Names.requested[k] then
      Names.requested[k] = B.Compat.RequestItemData(id)
    end
  elseif typ == "npc" then
    name = B.Compat.GetUnitNameByID(id) -- the client asks the server itself on a miss
  else
    return nil
  end
  if name then
    Names.cache[k] = name
    remember(typ, id, name)
  end
  return name
end

local function onLoaded(typ)
  return function(_, _, id, success)
    local k = key(typ, id)
    if not Names.requested[k] then
      return -- a load another addon asked for
    end
    Names.requested[k] = nil
    local name = success and Names.Get(typ, id) or nil
    if not name then
      Names.cache[k] = false -- asked and unknown: no second request this session
    end
    invalidateLater(typ)
  end
end

-- Called from the Data module's OnEnable: event handlers belong to the module.
function Names.Attach(module)
  mod = module
  local global = module:GetDB().global
  if type(global.names) ~= "table" then
    global.names = {}
  end
  store = global.names
  for typ in pairs(STORE_TYPES) do
    if type(store[typ]) ~= "table" then
      store[typ] = {}
    end
  end
  if type(store.order) ~= "table" then
    store.order = {}
  end
  module:RegisterEvent("QUEST_DATA_LOAD_RESULT", onLoaded("quest"))
  module:RegisterEvent("ITEM_DATA_LOAD_RESULT", onLoaded("item"))
end

function Names.Reset()
  Names.cache, Names.requested = {}, {}
end
