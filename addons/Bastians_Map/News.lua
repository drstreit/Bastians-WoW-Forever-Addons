-- What's new of Bastian's Map and Map Art (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.3.0:1",
    date = "2026-11-11",
    version = "2.3.0",
    text = 'Stormwind has a painted City & dungeon map in its own window: the "City map" button on the map opens it, with your position, the map\'s layers and a pin for every house and the people in it. Release 2.2.0 had left its pictures out.',
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Zone level ranges on the map are coloured for your character's level.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The map's footer shows the travel time to the point under your cursor.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The physical map no longer shows a stray strip of old parchment west of Kalimdor.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The level band under a zone's name on the map reads clearly in every difficulty colour.",
  },
  {
    id = "2.1.0:5",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'The map\'s right-click menu no longer lists "Show on map" twice.',
  },
  {
    id = "2.1.0:6",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The map keeps you centred by default; looking around pauses it until the map closes, and only the Centred button switches it off.",
  },
  {
    id = "2.1.0:7",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The minimap shows only the herbs and ore the game's tracking really finds, not every known spawn.",
  },
  {
    id = "2.1.0:8",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The minimap follows your character even when the game reports no movement, on boats, after a knockback or a teleport.",
  },
  {
    id = "2.1.0:9",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Switching a layer off also clears its pins from the minimap.",
  },
  {
    id = "2.1.0:10",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Creatures found by hunter, druid, paladin and warlock tracking now show on Bastian's map styles.",
  },
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "The herbs and ore the game tracks no longer vanish from Bastian's minimap styles with a map layer, the pin limit or the layers-on-the-minimap setting; they show as yellow pins of their own.",
  },
  {
    id = "2.0.0:2",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Herbs and ore on Bastian's minimap styles now sit exactly where the game's own dots are.",
  },
  {
    id = "2.0.0:3",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Bastian's minimap styles show only the herbs and ore your tracking finds, no more stray pins on you or on quest marks.",
  },
  {
    id = "2.0.0:4",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Zephras Isle no longer shows an empty map in the Blizzard, Modern, Pencil and Parchment styles.",
  },
  {
    id = "1.5.0:1",
    date = "2026-11-04",
    version = "1.5.0",
    text = "Bastian's minimap shows the herbs, ore and creatures your tracking finds on its own styles too, and the game's tracking button is back in its tools row.",
  },
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
}
