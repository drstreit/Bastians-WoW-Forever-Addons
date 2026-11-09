-- Bastian's Map: Painted: the game's zone paintings as one seamless map (ADR 0036). The cells, their
-- table and Blizzard's names are Generated/ (tools/map_blizzard.py, tools/map_style.py --emit); this
-- file only tells the Map that the style's addon is present, so its settings can say when the
-- generated part is missing. Order-independent like Map Art's.
local ADDON = ...
local B = Bastians or {}
Bastians = B
B.Map = B.Map or {}
B.Map.styleAddons = B.Map.styleAddons or {}
B.Map.styleAddons["blizzard"] = ADDON
