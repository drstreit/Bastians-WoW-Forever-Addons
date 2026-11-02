-- What's new of Bastian's Data (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.3.0:1",
    date = "2026-11-02",
    version = "1.3.0",
    text = "The dungeon pages name the right bosses; some showed an unrelated creature (Shadowfang Keep's first boss as Archaedas) with loot that was not its own.",
  },
  {
    id = "1.0.0-beta.13:3-core",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Flight masters and measured flight times are kept by Bastian's Data, so every app's travel times use them.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Quest recommendations use the walking network's travel time from where you stand.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes use the lifts of Undercity and Thunder Bluff and reach the Booty Bay and Undercity zeppelin docks.",
  },
  {
    id = "1.0.0-beta.13:3",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes and travel times to places under another floor, such as Undercity under the ruins, now lead to the right floor.",
  },
  {
    id = "1.0.0-beta.13:4",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "On Forever the safest route now sees the guards of the other faction and no longer avoids harmless critters.",
  },
  {
    id = "1.0.0-beta.13:5",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Subzones such as Crystal Lake can be found in the Map and Browser search.",
  },
  {
    id = "1.0.0-beta.12:1",
    date = "2026-10-24",
    version = "1.0.0-beta.12",
    text = "On retail an item's page and pins show what a vendor pays for it.",
  },
}
