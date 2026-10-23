-- Manually completed Forever handoff for build 1.60.1.69893.
-- Regenerating with generate.py will overwrite these additions.
-- See docs/forever-data.md and docs/forever-map-override-audit.md.
-- Local consumer compatibility additions must survive any future exporter refresh.

local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

-- Canonical synthetic continent/world areas, matching the forward aliases.
---@type string
ZoneDB.private.uiMapIdToAreaIdOverride = [[return {
    [947] = 10089, -- Azeroth
    [1414] = 10073, -- Kalimdor
    [1415] = 10074, -- Eastern Kingdoms
    [310] = 209, -- Referenced dungeon area
}]]

-- Keep the 54 direct AreaIDs canonical; do not invert the many-to-one descendant lookup.
---@type string
ZoneDB.private.uiMapIdToAreaId = [[return {
    [1411] = 14, -- Durotar
    [1412] = 215, -- Mulgore
    [1413] = 17, -- The Barrens
    [1416] = 36, -- Alterac Mountains
    [1417] = 45, -- Arathi Highlands
    [1418] = 3, -- Badlands
    [1419] = 4, -- Blasted Lands
    [1420] = 85, -- Tirisfal Glades
}]]
