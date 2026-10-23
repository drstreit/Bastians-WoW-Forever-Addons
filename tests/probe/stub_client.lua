-- Minimal stub client for the Bastians_Probe smoke test (the full WoW mock comes with B2.2).
local messages = {}
local timers = {}
local handlers = {}

-- any unknown method on a stub object is a no-op returning nil
local function object()
  local o = {}
  return setmetatable(o, { __index = function(_, k)
    if k == "GetTexture" then return function(self) return rawget(self, "_tex") end end
    if k == "SetTexture" then return function(self, v) rawset(self, "_tex", v); return true end end
    if k == "SetScript" then return function(self, name, fn) local s = rawget(self, "_scripts") or {}; rawset(self, "_scripts", s); s[name] = fn end end
    if k == "HasScript" then return function() return false end end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return object() end end
    return function() return nil end
  end })
end

function CreateFrame()
  local f = object()
  table.insert(handlers, f)
  return f
end
UIParent = object()
GameTooltip = object()
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(messages, m) end }
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local clock = 0
function debugprofilestop() clock = clock + 0.001; return clock end
function GetTime() return clock end
date = os.date
function GetBuildInfo() return "1.60.1", "70450", "Oct 16 2026", 16001 end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 12 end
function GetLocale() return "enUS" end
function GetRealmName() return "TestRealm" end
function GetCurrentRegion() return 110 end
function GetZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Goldshire" end
function UnitPosition() return -9460.0, 62.0, 56.0, 0 end
function UnitGUID() return "Creature-0-1-0-1-448-0000" end
function hooksecurefunc() end
function TakeTaxiNode() end
SlashCmdList = {}

local function vec(x, y) return { GetXY = function() return x, y end } end
function CreateVector2D(x, y) return vec(x, y) end
C_Map = {
  GetMapInfo = function(id) if id == 1429 or id == 1453 then return { name = "Map" .. id, mapType = 3, parentMapID = 1415, flags = 0 } end end,
  GetWorldPosFromMapPos = function(id, v) local x, y = v:GetXY(); return 0, vec(x * 1000, y * 1000) end,
  GetMapGroupID = function() return nil end,
  GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
  GetMapArtLayerTextures = function() return { 1001, 1002, 1003 } end,
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return vec(0.42, 0.65) end,
}
C_QuestLog = {
  GetNumQuestLogEntries = function() return 2 end,
  GetInfo = function(i) return { title = "Quest " .. i, questID = 100 + i, isHeader = false } end,
  GetQuestIDForLogIndex = function(i) return 100 + i end,
  GetQuestObjectives = function() return { { text = "x", finished = false, numFulfilled = 1, numRequired = 5 } } end,
  IsComplete = function() return false end,
  GetAllCompletedQuestIDs = function() return { 1, 2, 3 } end,
}
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function() end }
Settings = {
  RegisterCanvasLayoutCategory = function() return {} end,
  RegisterAddOnCategory = function() end,
}

function stub_fire(event, ...)
  for _, f in ipairs(handlers) do
    local s = rawget(f, "_scripts"); if s and s.OnEvent then s.OnEvent(f, event, ...) end
  end
end
function stub_drain()
  local guard = 0
  while #timers > 0 do
    guard = guard + 1
    if guard > 100000 then error("timers do not drain") end
    local fn = table.remove(timers, 1)
    fn()
  end
end
function stub_messages() return messages end
