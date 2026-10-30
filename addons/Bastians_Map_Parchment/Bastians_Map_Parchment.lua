-- Bastian's Map: Parchment: one of Bastian's map styles (ADR 0027). The cells and their table are
-- Generated/ (tools/map_style.py); this file only tells the Map that the style's addon is present, so
-- its settings can say when the generated part is missing. Order-independent like Map Art's.
local ADDON = ...
local B = Bastians or {}
Bastians = B
B.Map = B.Map or {}
B.Map.styleAddons = B.Map.styleAddons or {}
B.Map.styleAddons["parchment"] = ADDON
