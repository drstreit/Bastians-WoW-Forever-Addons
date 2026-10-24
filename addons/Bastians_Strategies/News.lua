-- What's new of Bastian's Strategies (the app; the book's daily entries come from its pack) (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.0.0-beta.11:1",
    date = "2026-10-24",
    version = "1.0.0-beta.11",
    text = "The book's What's new tells of new travellers, proven rumours and new rumours in the mill, and opens the page or the mill with a click.",
  },
  {
    id = "1.0.0-beta.11:2",
    date = "2026-10-24",
    version = "1.0.0-beta.11",
    text = "The book adds one line a day to the suite's What's new that opens the new page, the mill or the book's own list.",
  },
}
