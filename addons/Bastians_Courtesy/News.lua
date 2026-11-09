-- What's new of Bastian's Courtesy (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Bastian's Courtesy is now an addon of its own: when someone helps you, a small ring offers a fitting thank-you, and your click says it in character.",
  },
}
