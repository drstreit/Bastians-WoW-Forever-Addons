-- What's new of Bastian's Alts (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.2.0:12",
    date = "2026-10-31",
    version = "1.2.0",
    text = "New app Bastian's Alts: every character's bags, bank, mail and equipment in the Browser and on item tooltips, searchable, and ask another character for an item; its next mailbox visit fills the mail.",
  },
}
