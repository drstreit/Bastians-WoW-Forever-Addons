-- What's new of Bastian's Chat (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "Bastian's Chat gets a live tab filter, tab windows that dock back, a Messenger of the WhatsApp kind with class icons and a search, and a lock on every chat window.",
  },
}
