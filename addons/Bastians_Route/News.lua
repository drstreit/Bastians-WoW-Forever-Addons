-- What's new of Bastian's Route (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.4.1:1",
    date = "2026-11-12",
    version = "2.4.1",
    text = "Route no longer spends your hearthstone to save a few seconds: the stone or a teleport is only part of a route when it saves at least three minutes.",
  },
  {
    id = "2.2.0:1",
    date = "2026-11-11",
    version = "2.2.0",
    text = "The flight bar goes away when you land, and Route now learns how long your flights take; on WoW Forever it never noticed a landing.",
  },
  {
    id = "2.1.0:1",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A small bar shows the time left on a flight whose duration you flew before.",
  },
  {
    id = "2.1.0:2",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A route says in one word whether the way is safe, needs care or is risky for your level.",
  },
  {
    id = "2.1.0:3",
    date = "2026-11-09",
    version = "2.1.0",
    text = "A route starts on your side of a ridge instead of across a mountain.",
  },
  {
    id = "2.1.0:4",
    date = "2026-11-09",
    version = "2.1.0",
    text = "After you die, Bastian's Route drops the old arrow and guides you on foot back to your corpse, marked clearly on the map.",
  },
  {
    id = "2.1.0:5",
    date = "2026-11-09",
    version = "2.1.0",
    text = "/way now works without TomTom and starts a route; several lines become one route, and a button chooses a new route or adding to the current one.",
  },
  {
    id = "2.1.0:6",
    date = "2026-11-09",
    version = "2.1.0",
    text = "Routes inside Stormwind no longer detour around the harbour to reach a street nearby.",
  },
  {
    id = "2.0.1:1",
    date = "2026-11-06",
    version = "2.0.1",
    text = "Bastian's Route now has the walk network of both continents: routes follow roads, passes and bridges instead of the straight line.",
  },
  {
    id = "1.0.0-beta.13:4",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes to another continent take the boat or zeppelin with the expected wait.",
  },
  {
    id = "1.0.0-beta.13:7",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Clicking a route step to a map spot no longer raises an error.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes walk the paths of the game world itself, through tunnels, over bridges and inside cities, where the data for the continent is installed.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "A route shortens as you go, counts its time down and re-routes sooner when you leave it.",
  },
}
