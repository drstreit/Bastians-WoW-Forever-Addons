-- What's new of Bastian's Helpers (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "New app Bastian's Helpers: sells junk, repairs, restocks, takes all mail, helps at quest givers and shows IDs on tooltips.",
  },
}
