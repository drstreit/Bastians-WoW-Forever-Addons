---@diagnostic disable: deprecated
-----------------------------------------------------------------
--   L O C A L I Z A T I O N   D A T A B A S E   M O D U L E   --
-----------------------------------------------------------------
local localize = function(t, data) for k,v in pairs(data) do t[k] = v end end
local appName, _, a = ...
local L = _.L
-- Localization Strings
L.ABOUT_TOP = "trimmed"
L.HEADER_NAMES = setmetatable({}, { __index = function(t, k) return "Header " .. k end })
local ObjectNames = {
	[61] = _.WOWAPI.GetItemClassInfo(3),
	[2076] = "Atal'Gral, Zuldazar",
	[2702] = "Stone of Inner Binding",
	[2846] = "Tattered Chest",
	[164955] = "Northern Crystal Pylon",
	[999001] = string.format(SPELLBOOK_AVAILABLE_AT, 48),
	[999002] = L.HEADER_NAMES[-5],
	[999003] = GetSpellInfo(123),
} _.ObjectNames = ObjectNames
for _,objectID in ipairs({999004}) do
	ObjectNames[objectID] = "Alliance Bonfire"
end
