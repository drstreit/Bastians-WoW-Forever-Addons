-- What's new of Bastian's Alts (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'A "Trainer" view lists the spells your class trainers teach you now, with cost and the nearest trainer.',
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Your character's page names the gold to save for: the next training, riding and a mount.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A dungeon's page lists your characters' runs and lockouts.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Alts can forget a character you deleted, and its filter now finds class, race, place and every item held.",
  },
  {
    id = "1.2.0:12",
    date = "2026-10-31",
    version = "1.2.0",
    text = "New app Bastian's Alts: every character's bags, bank, mail and equipment in the Browser and on item tooltips, searchable, and ask another character for an item; its next mailbox visit fills the mail.",
  },
}
