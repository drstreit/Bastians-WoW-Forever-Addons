-- What's new of Bastian's Gestures (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The gesture ring stays open until you press its key again.",
  },
  {
    id = "1.4.0:1",
    date = "2026-11-04",
    version = "1.4.0",
    text = "A Gestures command can now cast, use and target: /cast and friends run as a macro when you click the wedge.",
  },
}
