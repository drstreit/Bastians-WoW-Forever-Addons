-- Data.QuestieDB (data.md): QuestieDB as a second entity provider for NPC and object spawns and names,
-- through LibQuestieDB contract 4 (verified on the Forever beta 18.10.2026 via AHSync). Never required.
local _, ns = ...
local B = Bastians
local L = ns.L
local Data = ns.Data

local CONTRACT = 4
local MAX_POINTS = 24 -- an NPC can have hundreds of spawns; the map clusters anyway
local PRIORITY = 50 -- below our own data (100)

local Bridge = {}
Data.QuestieDB = Bridge

-- "ok" with the library, or "missing" / "contract" with a reason.
function Bridge.Status()
  local lib = rawget(_G, "LibQuestieDB")
  if type(lib) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Object) ~= "table" then
    return "missing", L["QuestieDB is not loaded"]
  end
  if type(lib.RequireContract) == "function" then
    local ok, accepted, reason = pcall(lib.RequireContract, CONTRACT)
    if not ok then
      return "contract", tostring(accepted)
    end
    if not accepted then
      return "contract", reason or L["QuestieDB version mismatch"]
    end
  end
  return "ok", lib
end

local function areaToMap(areaId)
  local idx = Data.service:Index("area.toMap")
  return idx and idx[areaId] or nil
end

-- { [areaId] = { {x, y}, ... } } in map percent -> our spawn points (fractions, src "questie")
local function locationsFrom(db, id)
  local ok, spawns = pcall(db.spawns, id)
  if not ok or type(spawns) ~= "table" then
    return nil
  end
  local out = {}
  for areaId, list in pairs(spawns) do
    local map = areaToMap(areaId)
    if map and type(list) == "table" then
      for _, p in ipairs(list) do
        if #out >= MAX_POINTS then
          return out
        end
        local x, y = p[1], p[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
          out[#out + 1] = { map = map, x = x / 100, y = y / 100, src = "questie" }
        end
      end
    end
  end
  return out
end

local function nameFrom(db, id)
  local ok, name = pcall(db.name, id)
  return ok and type(name) == "string" and name or nil
end

local function provider(entityType, db)
  return {
    type = entityType,
    priority = PRIORITY,
    name = function(id)
      return nameFrom(db, id)
    end,
    locations = function(id)
      return locationsFrom(db, id)
    end,
  }
end

B:NewModule("Data.QuestieDB", {
  title = L["QuestieDB bridge"],
  optional = { "QuestieDB" },
  options = {
    {
      type = "note",
      text = function()
        local status, detail = Bridge.Status()
        if status == "ok" then
          return L["QuestieDB is loaded: its NPC and object spawns fill the gaps in our data."]
        end
        return tostring(detail)
      end,
    },
  },
  OnEnable = function(self)
    local status, lib = Bridge.Status()
    self.status = status
    if status ~= "ok" then
      self:Log("info", "QuestieDB bridge inactive: %s", tostring(lib))
      return
    end
    B:RegisterEntityType(self, provider("npc", lib.Npc))
    B:RegisterEntityType(self, provider("object", lib.Object))
    if type(lib.Item) == "table" then
      B:RegisterEntityType(self, {
        type = "item",
        priority = PRIORITY,
        name = function(id)
          return nameFrom(lib.Item, id)
        end,
      })
    end
    self:Log("info", "QuestieDB bridge active (contract %d)", CONTRACT)
  end,
})
