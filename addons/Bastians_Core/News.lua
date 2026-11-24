-- What's new of the suite as a whole (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.9.0:1",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Every window opens in the book's frame: a tall head with the app's mark for windows you read, a low one for what stays on screen, filters in a band of their own, and the book's faces for headings and labels.",
  },
  {
    id = "2.9.0:2",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Bastian's Book opens on a table set for you: the newest gold story and six wonders near you and at your level, a note from Bastian and a door to every chapter; tiles lift under the mouse.",
  },
  {
    id = "2.9.0:3",
    date = "2026-11-24",
    version = "2.9.0",
    text = "A wonder's page in Bastian's Book says how to get it: every source is a link with its zone, level and odds or price, and can be shown on the map or routed to; zones in the book are drawn whole, also where you have not been.",
  },
  {
    id = "2.9.0:4",
    date = "2026-11-24",
    version = "2.9.0",
    text = "The settings window's list of apps scrolls in a low window, a character's Bank and Mail tabs carry their names, and resizing the minimap buttons' window no longer raises an error.",
  },
  {
    id = "2.9.0:5",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Bastian's Book: every shelf can be read as a list that says how to get each wonder and which ones you already have; Collections opens as one.",
  },
  {
    id = "2.9.0:6",
    date = "2026-11-24",
    version = "2.9.0",
    text = 'Bastian\'s Book: "Your record" is now "Your diary", a journal by the day with a line for every find, your progress per collection and zone, an album of your companions and mounts, and a dated stamp on what you have done.',
  },
  {
    id = "2.9.0:7",
    date = "2026-11-24",
    version = "2.9.0",
    text = "My quests and the quest log wear the suite's one look: Lock in the frame's head, the filters as chips in a band, the views as tabs, and a done quest's line names who takes it.",
  },
  {
    id = "2.9.0:8",
    date = "2026-11-24",
    version = "2.9.0",
    text = "The map's search and buttons stand in the window's head in the suite's one look; the map fills the window from edge to edge.",
  },
  {
    id = "2.9.0:9",
    date = "2026-11-24",
    version = "2.9.0",
    text = "The large numbers on stat tiles (a character's level, counts) are drawn in the text font, so 17 no longer reads as I7.",
  },
  {
    id = "2.9.0:10",
    date = "2026-11-24",
    version = "2.9.0",
    text = "The Notes window wears the suite's one look: New list, Import and Share in its head, the chosen list with Rename and Remove in a foot.",
  },
  {
    id = "2.9.0:11",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Icons without a label (the map's layer icons, a window's options and close) show their name the moment the mouse is on them, even with button tips switched off.",
  },
  {
    id = "2.9.0:12",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Bastian's Book: on the Atlas a rare is its round portrait, a moment after its zone is opened for the first time.",
  },
  {
    id = "2.9.0:13",
    date = "2026-11-24",
    version = "2.9.0",
    text = "A quest's row in the Browser is no longer cut off: it names the coin, the XP and the best reward; the whole line stands on the quest's page.",
  },
  {
    id = "2.9.0:14",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Campfire's planner in the Browser shows a feature's facts on short lines instead of one cut-off line.",
  },
  {
    id = "2.9.0:15",
    date = "2026-11-24",
    version = "2.9.0",
    text = "Long quest rewards, the Route's empty hint and the book's chapter cards no longer get cut off in narrow windows.",
  },
  {
    id = "2.9.0:16",
    date = "2026-11-24",
    version = "2.9.0",
    text = "A quest shown on the map beside its page has the question mark again: gold when it is ready to hand in, grey while it runs.",
  },
  {
    id = "2.7.0:1",
    date = "2026-11-22",
    version = "2.7.0",
    text = "One look for the whole suite: every window wears Bastian's Book's buttons, chips, tabs and switches, on the new Folio theme, in the game's frame; your saved look is carried over once.",
  },
  {
    id = "2.7.0:2",
    date = "2026-11-22",
    version = "2.7.0",
    text = "On the city map your marker no longer hides the pin you stand at.",
  },
  {
    id = "2.7.0:3",
    date = "2026-11-22",
    version = "2.7.0",
    text = "Quests knows breadcrumb quests: it says to turn the breadcrumb in first and drops a breadcrumb once you took its quest, and no longer offers quests you have outlevelled.",
  },
  {
    id = "2.7.0:4",
    date = "2026-11-22",
    version = "2.7.0",
    text = "The rings of Gestures and Courtesy take the book's look: dark seals with a gold edge, the chosen answer filled in gold.",
  },
  {
    id = "2.7.0:5",
    date = "2026-11-22",
    version = "2.7.0",
    text = 'Docks, zeppelin towers and portals on the maps show a ship or a zeppelin and say where they go, like "Boat to Auberdine".',
  },
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
}
