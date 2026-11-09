-- What's new of Bastian's Data (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "2.0.0:1",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Auctioneers, stable masters, innkeepers, bankers, flight masters and battlemasters are marked as what they are, and several hundred more vendors and repairers are found.",
  },
  {
    id = "2.0.0:2",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Stormwind's bankers, guards, mailboxes and other people and objects inside the city are listed and shown in Stormwind City, no longer in Elwynn Forest.",
  },
  {
    id = "2.0.0:3",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Test and placeholder records of the game's data (unused NPCs, invisible triggers, deprecated and test items, the weapons monsters hold) no longer show in lists, zone pages and the search.",
  },
  {
    id = "2.0.0:4",
    date = "2026-11-06",
    version = "2.0.0",
    text = "The zones Forever added now have their people, objects, quest hand-ins, objectives and objective texts, and the airships to Zephras Isle are on the routes.",
  },
  {
    id = "2.0.0:5",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Forever's vendors show their stock, quests show the XP players measured and the rewards seen in Forever, and more Classic creatures have a place on the map.",
  },
  {
    id = "2.0.0:6",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Routes now lead to the doors of the City of Dalaran, the Excavation Site in the Wetlands, the Ruins of Lordaeron and the Hall of Thanes.",
  },
  {
    id = "2.0.0:7",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Auction prices left over from the beta are now labelled as such.",
  },
  {
    id = "2.0.0:8",
    date = "2026-11-06",
    version = "2.0.0",
    text = "Routes to Zephras Isle use Dalaran's skyboat, the skycutter at Skywatcher Plateau and, for the Alliance, the portal in Stormwind's Wizard's Sanctum.",
  },
  {
    id = "1.5.0:1",
    date = "2026-11-04",
    version = "1.5.0",
    text = "The Strategies book's Rumour mill keeps only rumours told in the last 20 days; older ones leave by themselves.",
  },
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
