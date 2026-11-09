-- What's new of Bastian's Strategies (the app; the book's daily entries come from its pack) (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The gold stories' map scales smoothly with its window, which takes the map's shape; tokens light up under the cursor; the book opens on the map.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The gold book's text follows the suite's text size and uses three font sizes instead of seven.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The gold book's maps and the story map's marks open their place on the world map.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The names in the gold book's pages are links: hover for the tooltip, click to open.",
  },
  {
    id = "1.0.0:1-core",
    date = "2026-10-30",
    version = "1.0.0",
    text = "The book's place maps lie on the zone's map, with a Route there button, and the book window can be as large as you like.",
  },
  {
    id = "1.0.0:1",
    date = "2026-10-30",
    version = "1.0.0",
    text = "Bastian's book has pictures on its title page, What's new, index and bookmarks.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The book searches its whole text, shows a painted picture on every page, and lists the likeliest loot first before there are prices.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Every page of the book gives you its address on bastians.dev to copy.",
  },
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
