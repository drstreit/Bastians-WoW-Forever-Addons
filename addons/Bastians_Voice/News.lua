-- What's new of Bastian's Voice (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
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
