-- What's new of the suite as a whole (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'A dungeon in a list says "in 4 levels" while it is still ahead of you.',
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A zone's page says the fishing skill it asks for.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Dungeon pages list the quests whose targets live inside, from the Classic data, for 16 more dungeons and raids.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The Atlas's lists come in pages that fit the window instead of a scroll.",
  },
  {
    id = "2.1.0:5",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Stat tiles on Here, Gold and Characters; a dungeon's and a character's page read in tabs.",
  },
  {
    id = "2.1.0:6",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Gold's Bags tab gives one answer per bag item with the reason.",
  },
  {
    id = "2.1.0:7",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The settings hub reads as a rail of apps with their one-line purpose and every option on a card.",
  },
  {
    id = "2.1.0:8",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'Share the walks, flight times and ride waits your game learned through "Copy my captures" in the settings.',
  },
  {
    id = "2.1.0:9",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Dragging a window no longer jumps it over the top of the screen, and Dock works again after the docked Browser was closed by hand.",
  },
  {
    id = "2.1.0:10",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The people on a quest's sheet show their faces again.",
  },
  {
    id = "2.1.0:11",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'A dungeon one level away now says "in 1 level".',
  },
  {
    id = "2.1.0:12",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A page in the Browser has its own filter: type to narrow every list on it.",
  },
  {
    id = "2.1.0:13",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The Browser's sections and tabs are coloured symbols with text instead of green buttons.",
  },
  {
    id = "2.1.0:14",
    date = "2026-11-09",
    version = "2.1.0",
    text = "/balts opens your characters in the Browser: the list on the left, a character's tabs on the right.",
  },
  {
    id = "2.1.0:15",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The Gold Stories list shows each story as a tile with Bastian's picture and its first words.",
  },
  {
    id = "2.1.0:16",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A window you open always comes to the front, also one that was already open behind another.",
  },
  {
    id = "2.1.0:17",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Trainers and vendors say what kind they are, also when their title has no word Trainer in it.",
  },
  {
    id = "2.0.1:1",
    date = "2026-11-06",
    version = "2.0.1",
    text = 'The Browser\'s search no longer stays on "Searching ..." while other things happen; a search that fails says so.',
  },
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Quests now open on a parchment sheet with the task first, the story and large rewards, from My quests, the map and on hover at the Orbiter's quest marks.",
  },
  {
    id = "2.0.0:2",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Rewards come from the game itself, so quests no source knows show their real experience, money and items.",
  },
  {
    id = "2.0.0:3",
    date = "2026-11-06",
    version = "2.0.0",
    text = "My quests shows each quest on two lines, a finished quest has its own mark and says who takes it, and the voice and chain buttons stay on the row.",
  },
  {
    id = "2.0.0:4",
    date = "2026-11-06",
    version = "2.0.0",
    text = "The chain symbol shows a quest chain as a trail with every step, what it needs and what is still ahead.",
  },
  {
    id = "2.0.0:5",
    date = "2026-11-06",
    version = "2.0.0",
    text = "The map shows the targets of one quest, the focused or the nearest, and finished quests' hand-ins as large signs.",
  },
  {
    id = "2.0.0:6",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A second click on a quest closes its sheet, and the sheet shows the quest giver and the target in 3D.",
  },
  {
    id = "2.0.0:7",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Show on map opens at the nearest group of a quest's targets, not between two far camps.",
  },
  {
    id = "2.0.0:8",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A page in the Browser reads like the quest sheet: the figure large at the left on a wide window, the name and what matters first, the main buttons with the rest under More, and chapters in one column instead of a grid of blocks.",
  },
  {
    id = "2.0.0:9",
    date = "2026-11-06",
    version = "2.0.0",
    text = 'Pages are sorted into chapters in a fixed reading order: a zone\'s quests under one heading, an item under "Where to get it", "What it is for", "Worth" and "Yours", a monster\'s drops first.',
  },
  {
    id = "2.0.0:10",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A page in the Browser is drawn on parchment like the quest sheet, its rows are calm (two lines, icons only under the mouse), and a zone's quest groups you cannot act on yet are folded until clicked.",
  },
  {
    id = "2.0.0:11",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A zone's page lists its people by what they do, vendors, trainers, zones and dungeons say in one sentence what they are, quests far above your level no longer lead \"To do here\", and pages on parchment keep the paper's colours under the mouse and switch without a reload.",
  },
  {
    id = "2.0.0:12",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Pages on parchment keep readable colours everywhere, a place's mini map opens the large map there, a dungeon's floor map no longer sticks to other pages, the quest sheet opens on the free side of the Orbiter, and a locked Orbiter says that it is locked.",
  },
}
