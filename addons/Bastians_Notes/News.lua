-- What's new of Bastian's Notes (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Bastian's Notes keeps your notes on NPCs, quests, items and spots, shows them on tooltips, pages and the map, and reminds you when you come near or target the NPC.",
  },
}
