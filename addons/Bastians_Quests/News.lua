-- What's new of Bastian's Quests (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.2.0:1",
    date = "2026-10-31",
    version = "1.2.0",
    text = "My quests shows the next quest of a chain under its predecessor, greyed until you hand that one in; then it stands on its own until you take it.",
  },
}
