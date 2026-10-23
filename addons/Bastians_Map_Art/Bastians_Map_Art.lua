-- Bastian's Map Art: the overview textures of Bastian's Map (map.md "Imagery pipeline"). The data is
-- Generated/Overview.lua and Generated/Tiles/*.blp from the pipeline command `mapart --overview`; this
-- file only tells the Map that the art addon is present, so its settings note can say when the
-- generated part is missing. Order-independent: the client may run this before Bastians_Map
-- (Forever beta, 20.10.2026), so it creates the hook table the Map keeps (Tiles.lua: B.Map or {}).
local ADDON = ...
local B = Bastians or {}
Bastians = B
B.Map = B.Map or {}
B.Map.artLoaded = ADDON
