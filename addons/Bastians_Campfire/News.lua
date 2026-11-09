-- What's new of Bastian's Campfire (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The campfire flame can be dragged anywhere and remembers its place.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The campfire card is now a stylized flame you click: sit down, share or hide.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A new minimap button lights a kit you carry, and the foot icon offers what you can add to a fire, Violet Dust included.",
  },
}
