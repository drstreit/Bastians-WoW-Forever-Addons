-- What's new of Bastian's Voice (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.9.0:1",
    date = "2026-11-24",
    version = "2.9.0",
    text = "The Orbiter answers every click (and says when the game did not take it), lights up what is under the pointer, has no more black symbols, and shows the game's own quest marks.",
  },
  {
    id = "2.7.0:1",
    date = "2026-11-22",
    version = "2.7.0",
    text = 'The Orbiter no longer stacks a guard\'s answers on top of each other; long lists come in pages behind "More".',
  },
  {
    id = "2.6.0:1",
    date = "2026-11-20",
    version = "2.6.0",
    text = "The voice button plays a quest's line with one click and stops it with the next, as a green play and a red stop, and no other line starts after a stop.",
  },
  {
    id = "2.5.0:1",
    date = "2026-11-15",
    version = "2.5.0",
    text = "The Orbiter's conversation shows every quest of a quest giver, also two of the same name; the hand-in of one was hidden behind the other (Harvesting the Harvesters).",
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Hovering a quest reward in the Orbiter shows the item's full stats.",
  },
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "The Orbiter has a small lock under its play button: click it to lock the ring in place or to move it freely.",
  },
  {
    id = "1.6.0:1",
    date = "2026-11-05",
    version = "1.6.0",
    text = "Orbiter: hovering a quest mark shows the quest's chain position and its rewards (money, reputation, items).",
  },
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Bastian's Voice: Play on quests, zones, areas, bosses and books where Spoken has a line, the Lore Orbit around you, and quest conversations without the game's windows (off by default).",
  },
  {
    id = "1.3.0:2",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Bastian's Orbiter (the Voice addon, renamed): the panel keeps its place and grows around its middle, says what it plays and what a click did, has pictogram controls and its own minimap button; the game's settings pages of the suite scroll.",
  },
  {
    id = "1.3.0:3",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Without Spoken, the Orbiter reads a quest's text with the game's own voice (Accessibility settings).",
  },
  {
    id = "1.3.0:4",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The game's voice that reads quest texts is a woman's by default and can be chosen in the Orbiter's settings.",
  },
}
