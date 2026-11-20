-- What's new of the suite as a whole (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.6.0:1",
    date = "2026-11-20",
    version = "2.6.0",
    text = "A chosen filter chip is now filled, so it stands out from the others in every look.",
  },
  {
    id = "2.6.0:2",
    date = "2026-11-20",
    version = "2.6.0",
    text = "Filter chips are quiet until chosen, and the suite ships the typefaces of Bastian's Book.",
  },
  {
    id = "2.6.0:3",
    date = "2026-11-20",
    version = "2.6.0",
    text = "Filter chips are round at both ends in every window.",
  },
  {
    id = "2.6.0:4",
    date = "2026-11-20",
    version = "2.6.0",
    text = "Orgrimmar, Ironforge, Thunder Bluff, Darnassus and Undercity have a city map of their own, as Stormwind has.",
  },
  {
    id = "2.5.0:1",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Bastian's Chat follows your look completely, light ones too, shows every channel in its own colour (or the game's), and its windows and every window of the suite can wear LibSharedMedia borders and textures.",
  },
  {
    id = "2.5.0:2",
    date = "2026-11-15",
    version = "2.5.0",
    text = "In its Modern and Glass looks Bastian's Chat draws its heads and tabs in Barlow Condensed and its counts, times and prices in IBM Plex Mono, and the suite offers five more fonts: IBM Plex Sans, IBM Plex Mono, Oswald, Varela Round and Almendra.",
  },
  {
    id = "2.5.0:3",
    date = "2026-11-15",
    version = "2.5.0",
    text = "On WoW Forever, Core notices the spells you learn (it listened for an event the game no longer has).",
  },
  {
    id = "2.5.0:4",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Long choices in the settings no longer run past their buttons.",
  },
  {
    id = "2.2.0:1",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Quest givers and hand-ins that ForeverDB players saw in the game fill gaps on the map sooner.",
  },
  {
    id = "2.2.0:2",
    date = "2026-11-11",
    version = "2.2.0",
    text = "A rumour in the gold book names its three newest travellers and counts the others.",
  },
  {
    id = "2.2.0:3",
    date = "2026-11-11",
    version = "2.2.0",
    text = "A quest whose next step has no known place no longer routes you back to its giver.",
  },
  {
    id = "2.2.0:4",
    date = "2026-11-11",
    version = "2.2.0",
    text = 'A quest whose place nobody knows says so, with Map and Route greyed; the quest round stops once per open objective, and "Route to" picks among the nearest places.',
  },
  {
    id = "2.2.0:5",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Quests that ask for an item no loot table knew, like Mirror Lake's water sample, now lead to where the item is found.",
  },
  {
    id = "2.2.0:6",
    date = "2026-11-11",
    version = "2.2.0",
    text = 'The suite notes where your quest steps counted, and "Copy my captures" can share those places, so quests no source can place get one later.',
  },
  {
    id = "2.2.0:7",
    date = "2026-11-11",
    version = "2.2.0",
    text = "The flight bar and the learned flight times name the flight you took; the game lists its flight points in another order than its buttons.",
  },
  {
    id = "2.2.0:8",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Abandoning a quest that takes items back no longer raises an error; the game's question names the items.",
  },
  {
    id = "2.2.0:9",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Ring wedges and the Campfire's foot icon act on a click whatever the game's key-down setting, and a ring opened by its toggle key stays until that key closes it, over a reload too.",
  },
  {
    id = "2.2.0:10",
    date = "2026-11-11",
    version = "2.2.0",
    text = "Courtesy whispers its line to the person who buffed or invited you when the game gives their whole name, and offers its ring for a buff that landed during a longer fight.",
  },
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
}
