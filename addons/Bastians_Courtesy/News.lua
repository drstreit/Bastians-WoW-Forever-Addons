-- What's new of Bastian's Courtesy (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.9.0:1",
    date = "2026-11-24",
    version = "2.9.0",
    text = "In Courtesy's My lines window the Situation, Mood and Language boxes no longer overlap, and the three lists are tabs at the top.",
  },
  {
    id = "2.7.0:1",
    date = "2026-11-22",
    version = "2.7.0",
    text = "Courtesy answers sound like something a person would say, in English and in German: one or two short spoken sentences, thanks first, many variants of each.",
  },
  {
    id = "2.7.0:2",
    date = "2026-11-22",
    version = "2.7.0",
    text = "Courtesy keeps a small symbol on the screen that you can drag anywhere: point at it for a few kind words at any time; a moment now waits a minute (adjustable) for your answer.",
  },
  {
    id = "2.5.0:1",
    date = "2026-11-15",
    version = "2.5.0",
    text = 'Courtesy says "Good day" around noon, offers fresher lines instead of the same few, and greets everyone at a campfire aloud when you sit down, naming the people there.',
  },
  {
    id = "2.5.0:2",
    date = "2026-11-15",
    version = "2.5.0",
    text = "Your own Courtesy lines are written in the game now (Courtesy page, My lines), and any line can be switched off for good; lines from the old Bastians_MyLines folder come over by themselves.",
  },
  {
    id = "2.4.0:1",
    date = "2026-11-11",
    version = "2.4.0",
    text = "Courtesy's thank-yous now know what you were given, where you are, the weather and whether you were fighting, with 957 lines instead of 209.",
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Bastian's Courtesy is now an addon of its own: when someone helps you, a small ring offers a fitting thank-you, and your click says it in character.",
  },
}
