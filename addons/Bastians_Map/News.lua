-- What's new of Bastian's Map and Map Art (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The map has a Dungeons and raids layer, and it switches on by itself when you pick a dungeon in the Browser.",
  },
  {
    id = "1.3.0:2",
    date = "2026-11-02",
    version = "1.3.0",
    text = '"Show on map" now draws what you chose (its icon and name at every place) and selects it, even when its layer is off.',
  },
  {
    id = "1.3.0:3",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The minimap's search finds only NPCs, quests, zones, your notes and bookmarks, and marks the place it jumps to; a quest marks its quest giver.",
  },
  {
    id = "1.0.0-beta.13:8-core",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Quest signs on the map show the quest, its chain and all its rewards; the map search works with the arrow keys.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map no longer causes a blocked-action error when you press keys in combat; Full switches back with Window, and Follow is gone.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map has a layer bar to switch every layer and keeps bookmarks of places you want to come back to.",
  },
  {
    id = "1.0.0-beta.13:3",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map shows zone names with their levels and can show flight masters, docks, inns, banks, mailboxes, vendors, trainers and resource nodes.",
  },
  {
    id = "1.0.0-beta.13:4",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map's layer bar slides, bookmarks get names, zones show their creature levels and resources, and a new route always shows on the map.",
  },
  {
    id = "1.0.0-beta.13:5",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map switches between the physical map and Blizzard's painted maps, from the layer bar or the settings.",
  },
  {
    id = "1.0.0-beta.13:6",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Three new optional map styles, Modern, Pencil and Parchment, drawn by Bastian from the world itself, one addon each (about 100 MB); pick them in the map's style bar.",
  },
  {
    id = "1.0.0-beta.13:7",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map's layer bar shows one icon per layer, with the map style and the bookmarks behind one icon each.",
  },
  {
    id = "1.0.0-beta.13:8",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map can keep you in the middle while you move (the Centred button).",
  },
  {
    id = "1.0.0-beta.13:9",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Bastian's minimap: the game's minimap in a frame with a search bar, the map's styles and layers, zoom and dragging, and a box for all addon minimap buttons.",
  },
  {
    id = "1.0.0-beta.13:10",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "An info sign on Bastian's minimap explains the game's minimap and Bastian's styles with their pros and cons.",
  },
  {
    id = "1.0.0-beta.13:11",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The minimap sizes and moves in the game style, shows travel and service places, and has a frame.",
  },
  {
    id = "1.0.0-beta.13:12",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Other addons' minimap buttons (LibDBIcon) are visible in the button box.",
  },
  {
    id = "1.0.0-beta.13:13",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The minimap follows you again when you walk, and your arrow shows above the pins.",
  },
  {
    id = "1.0.0-beta.13:14",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Minimap buttons moved out of the button box with Ctrl+click sit on the rim of Bastian's minimap instead of disappearing.",
  },
  {
    id = "1.0.0-beta.13:15",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Minimap buttons on the rim of Bastian's minimap show above the map, and the minimap settings can put every button back into the box.",
  },
  {
    id = "1.0.0-beta.13:16",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Minimap buttons on the rim of Bastian's minimap sit centred on its ring.",
  },
  {
    id = "1.0.0-beta.13:17",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The Blizzard map style is now one seamless map of Blizzard's own paintings, every zone explored and every name sharp at any zoom (optional addon Bastian's Map: Blizzard).",
  },
  {
    id = "1.0.0-beta.13:18",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Zone names on the map no longer appear twice at middle zoom.",
  },
  {
    id = "1.0.0-beta.13:19",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map no longer draws thin rectangles around every zone.",
  },
  {
    id = "1.0.0-beta.13:20",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The names on the map are dark and readable on every map style.",
  },
  {
    id = "1.0.0-beta.13:21",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Every map style names the world like Blizzard's map: the seas and cities from afar, villages and smaller places as you zoom in, each sized by its importance.",
  },
  {
    id = "1.0.0-beta.13:22",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The names on the map have a light rim, readable on dark ground too.",
  },
}
