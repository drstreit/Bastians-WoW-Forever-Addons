-- What's new of Bastian's Gold (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.4.0:1",
    date = "2026-11-04",
    version = "1.4.0",
    text = "An item's price page shows a small chart of the prices your own auction house scans saw over the last two weeks.",
  },
}
