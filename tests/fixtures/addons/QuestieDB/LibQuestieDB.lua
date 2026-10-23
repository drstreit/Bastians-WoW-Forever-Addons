-- Fixture: the LibQuestieDB surface our bridge uses (contract 4, as AHSyncGuide Spawns.lua calls it).
-- Spawns are { [areaId] = { {x, y}, ... } } in map percent; names are localized strings.
local npcs = {
  [448] = { name = "Hogger", spawns = { [12] = { { 27.1, 85.9 }, { 29.8, 80.2 } }, [999] = { { 50, 50 } } } },
  [9999] = { name = "Questie Only Guy", spawns = { [87] = { { 44.0, 66.0 } } } },
}
local objects = {
  [1734] = { name = "Wanted Poster", spawns = { [87] = { { 42.1, 66.2 } } } },
}
local items = { [2589] = "Linen Cloth", [7777] = "Questie Only Item" }

LibQuestieDB = {
  CONTRACT = QuestieDB_FixtureContract or 4,
  RequireContract = function(n)
    local have = QuestieDB_FixtureContract or 4
    if n == have then
      return true
    end
    return false, "contract " .. tostring(have) .. " loaded, " .. tostring(n) .. " required"
  end,
  Npc = {
    name = function(id)
      return npcs[id] and npcs[id].name or nil
    end,
    spawns = function(id)
      return npcs[id] and npcs[id].spawns or nil
    end,
  },
  Object = {
    name = function(id)
      return objects[id] and objects[id].name or nil
    end,
    spawns = function(id)
      return objects[id] and objects[id].spawns or nil
    end,
  },
  Item = {
    name = function(id)
      return items[id]
    end,
    npcDrops = function()
      return {}
    end,
  },
  Quest = {
    objectives = function()
      return nil
    end,
  },
}
