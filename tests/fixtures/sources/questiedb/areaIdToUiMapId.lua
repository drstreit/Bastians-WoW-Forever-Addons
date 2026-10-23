-- Reviewed Forever DBC relationships through build 1.60.1.70291.
-- Refresh candidates with tools/dbc/support.py; preserve authored compatibility.
-- See docs/forever-data.md and docs/forever-map-override-audit.md.
-- Local consumer compatibility additions must survive any future exporter refresh.

local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

-- Existing Questie aliases/display policy, not inferred DBC assignments.
---@type string
ZoneDB.private.areaIdToUiMapIdOverride = [[return {
    [0] = 0, -- Existing fail-safe
    [2257] = 0, -- Deeprun Tram: retain existing display suppression
    [2917] = 0, -- Hall of Legends: retain existing display suppression
    [2918] = 0, -- Champions' Hall: retain existing display suppression
    [10073] = 1414, -- Synthetic AreaID: Kalimdor continent map
}]]

-- Includes direct areas and descendants resolved through their highest mapped ancestor.
-- This selects a displayed map; it does not reproject any coordinates.
---@type string
ZoneDB.private.areaIdToUiMapId = [[return {
    [1] = 1426, -- Dun Morogh
    [2] = 1436, -- Longshore -> Westfall
    [3] = 1418, -- Badlands
    [4] = 1419, -- Blasted Lands
    [7] = 1434, -- Blackwater Cove -> Stranglethorn Vale
    [8] = 1435, -- Swamp of Sorrows
    [9] = 1429, -- Northshire Valley -> Elwynn Forest
    [10] = 1431, -- Duskwood
}]]
