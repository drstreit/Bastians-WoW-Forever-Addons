-- What's new of Bastian's Quests (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The map no longer sends you to quest givers who are not there or have nothing to give: world event quests wait for their event, quests that are not in the game are gone, and a giver who does not list a quest loses its pin until you gain a level.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'Quests far below your level stay on the map in grey, marked "Low level".',
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = 'A "Class quests" view lists your class\'s quests by status and level.',
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A quest's sheet under the mouse on a chain's step shows over the Browser instead of behind it.",
  },
  {
    id = "2.1.0:5",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A click on a class quest no longer empties the Class quests list while it is rebuilt.",
  },
  {
    id = "2.1.0:6",
    date = "2026-11-09",
    version = "2.1.0",
    text = "My quests lists every objective of a quest with its count, not just the first open one.",
  },
  {
    id = "2.1.0:7",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The map shows only the quest targets you still need, each labelled with what to do there and how many are left.",
  },
  {
    id = "2.1.0:8",
    date = "2026-11-09",
    version = "2.1.0",
    text = "The quest window has a Route to the giver button.",
  },
  {
    id = "2.1.0:9",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A quest item you already hold no longer keeps its pin where it lay.",
  },
  {
    id = "2.1.0:10",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Quests now wait for the quest players were seen to need first, where that cannot lock them out.",
  },
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Hovering a quest lights its whole block in one colour and the row under the mouse in another, so chain quests no longer look like quests of their own.",
  },
  {
    id = "2.0.0:2",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Quests now say what to do first: the task sits right under the quest in My quests and opens the quest page, with the story last.",
  },
  {
    id = "2.0.0:3",
    date = "2026-11-06",
    version = "2.0.0",
    text = 'Objectives show their count once, a quest with one objective counts its items, and "worth unknown" no longer fills a line.',
  },
  {
    id = "2.0.0:4",
    date = "2026-11-06",
    version = "2.0.0",
    text = '"To do here" ranks a quest by the experience it really gives where the game data names it, no longer by an estimate from its level.',
  },
  {
    id = "2.0.0:5",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A quest chain is a page of its own: the Quest chains list opens the chain with its steps in order, how far you are, the next step and the zones it leads through.",
  },
  {
    id = "2.0.0:6",
    date = "2026-11-06",
    version = "2.0.0",
    text = "A chain's page shows its side quests under the step they follow, and the steps of other races and classes dashed.",
  },
  {
    id = "2.0.0:7",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Follow on a quest chain's page tracks the step you are on and, after the hand-in, the next one by itself.",
  },
  {
    id = "1.6.0:1",
    date = "2026-11-05",
    version = "1.6.0",
    text = "Quests: right-click a quest in your log to abandon it; the game asks first.",
  },
  {
    id = "1.5.1:1",
    date = "2026-11-05",
    version = "1.5.1",
    text = "Quests: the zone view no longer errors on quests that are new in Forever.",
  },
  {
    id = "1.2.0:1",
    date = "2026-10-31",
    version = "1.2.0",
    text = "My quests shows the next quest of a chain under its predecessor, greyed until you hand that one in; then it stands on its own until you take it.",
  },
}
