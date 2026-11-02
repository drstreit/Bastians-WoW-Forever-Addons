-- What's new of Bastian's Browser (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.2.0:1",
    date = "2026-10-31",
    version = "1.2.0",
    text = "A dungeon's page shows the floor maps with numbered boss pins and the door.",
  },
  {
    id = "1.2.0:2",
    date = "2026-10-31",
    version = "1.2.0",
    text = "Quest chains and attunements show where you stand: numbered steps, what each needs, and the step to do next; a dungeon's page shows its attunement.",
  },
  {
    id = "1.2.0:3",
    date = "2026-10-31",
    version = "1.2.0",
    text = "Dungeon pages show the game's own dungeon maps per floor; the boss numbers open the boss, a click on a map enlarges it.",
  },
  {
    id = "1.2.0:6",
    date = "2026-10-31",
    version = "1.2.0",
    text = "Service chips with counts on the NPC list, the nearest list grouped by zone, long lists open at once and fill in steps, arrow keys and Enter in the Browser's search box, the search window grouped by type with Tab.",
  },
  {
    id = "1.2.0:7",
    date = "2026-10-31",
    version = "1.2.0",
    text = "Item rows show the game's full item tooltip with every stat, and boss numbers on a dungeon map no longer cover each other.",
  },
  {
    id = "1.2.0:8",
    date = "2026-10-31",
    version = "1.2.0",
    text = "The Browser has a Mobs list apart from the NPCs, a filter box over every list, level chips for quest chains, and the Quests list filters by status and type (All quests is folded into it).",
  },
  {
    id = "1.2.0:9",
    date = "2026-10-31",
    version = "1.2.0",
    text = "Recipe pages show the item they make with its picture and stats; item pages list their stats and the recipes that use or make them.",
  },
  {
    id = "1.1.0:1",
    date = "2026-10-30",
    version = "1.1.0",
    text = "Dungeons and raids have their own pages: the bosses in order, the loot, the dungeon quests and the door on the map.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Quests, items and NPCs have a button that puts their Wowhead link into the chat input to copy.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Scrolling or reading a page in the Browser no longer jumps to another entry.",
  },
  {
    id = "1.0.0-beta.13:3",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The Browser's middle list slides out when you pick a category and stays out of the way otherwise.",
  },
}
