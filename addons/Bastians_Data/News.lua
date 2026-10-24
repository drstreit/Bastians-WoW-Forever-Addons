-- What's new of Bastian's Data (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.0.0-beta.12:1",
    date = "2026-10-24",
    version = "1.0.0-beta.12",
    text = "On retail an item's page and pins show what a vendor pays for it.",
  },
}
