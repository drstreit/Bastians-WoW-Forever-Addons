-- What's new of Bastian's Helpers (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Targeting or mousing over a rare creature shows its name with a Map button.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Send to writes a character's name with its surname, so the mail reaches them on Forever.",
  },
  {
    id = "1.4.0:1",
    date = "2026-11-04",
    version = "1.4.0",
    text = "Mail rules: tell Helpers which character gets your herbs, ore, cloth and more, and one click beside the send tab fills the mail.",
  },
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "New app Bastian's Helpers: sells junk, repairs, restocks, takes all mail, helps at quest givers and shows IDs on tooltips.",
  },
}
