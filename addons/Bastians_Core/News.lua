-- What's new of the suite as a whole (ADR 0021): one entry per release note, newest first.
local _, ns = ...

-- { id, date = "YYYY-MM-DD", version, text }; written by tools/suite_release.py from the
-- Release-note trailers of the commits (ADR 0020), kept by hand where a sentence needs it.
ns.NEWS = {
  {
    id = "1.1.1:1",
    date = "2026-10-30",
    version = "1.1.1",
    text = "The book has a search page instead of the index and scales with its window; minimap buttons on the rim keep the place you drag them to; the button box has a filter.",
  },
  {
    id = "1.1.0:1",
    date = "2026-10-30",
    version = "1.1.0",
    text = "Dungeons and raids have their own pages: the bosses in order, the loot, the dungeon quests and the door on the map.",
  },
  {
    id = "1.1.0:2",
    date = "2026-10-30",
    version = "1.1.0",
    text = "A Suite page lists every app with a switch, a welcome window explains the suite at the first start, each window can have its own colour and opacity, and a Blizzard skin dresses the suite in the game's frames and gold.",
  },
  {
    id = "1.1.0:3",
    date = "2026-10-30",
    version = "1.1.0",
    text = "The game's window frames are the standard look, one button switches the whole suite to the full WoW look, and the options window has its own minimap button.",
  },
  {
    id = "1.1.0:4",
    date = "2026-10-30",
    version = "1.1.0",
    text = "The minimap button box grows with its width, holds any number of buttons and scrolls; window titles stay on one line.",
  },
  {
    id = "1.0.0:1",
    date = "2026-10-30",
    version = "1.0.0",
    text = "The book's place maps lie on the zone's map, with a Route there button, and the book window can be as large as you like.",
  },
  {
    id = "1.0.0-beta.13:1",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The About page credits the image model behind the book's drawings and gives the suite's new address, bastians.dev/wow.",
  },
  {
    id = "1.0.0-beta.13:2",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Lists and cards show the travel time to a place instead of the straight-line distance.",
  },
  {
    id = "1.0.0-beta.13:3",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Flight masters and measured flight times are kept by Bastian's Data, so every app's travel times use them.",
  },
  {
    id = "1.0.0-beta.13:4",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes to another continent take the boat or zeppelin with the expected wait.",
  },
  {
    id = "1.0.0-beta.13:5",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Every Bastian's addon shows its own icon in the game's AddOns list.",
  },
  {
    id = "1.0.0-beta.13:6",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes no longer draw a loop out and back at Stormwind's gate, and map clusters are round and see-through.",
  },
  {
    id = "1.0.0-beta.13:7",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Clicking a route step to a map spot no longer raises an error.",
  },
  {
    id = "1.0.0-beta.13:8",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Quest signs on the map show the quest, its chain and all its rewards; the map search works with the arrow keys.",
  },
  {
    id = "1.0.0-beta.13:9",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "All symbols share one style, a coloured tile like the addon icons; quest chains and objects have their own.",
  },
  {
    id = "1.0.0-beta.13:10",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The map's buttons are coloured with symbols, and two new ones open the route's step list and the Browser.",
  },
  {
    id = "1.0.0-beta.13:11",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Route remembers where you died, shows your corpse and earlier deaths on the map, and plans the way back to the corpse after you release.",
  },
  {
    id = "1.0.0-beta.13:12",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes use the teleports you have ready (mage and druid teleports, the Everlook ripper), Route learns where each one lands, and Home plans the way to your inn.",
  },
  {
    id = "1.0.0-beta.13:13",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Every route comes as fastest, safest and without flight costs, the safest one avoiding creatures too strong for your level, and the step list warns about dangerous stretches.",
  },
  {
    id = "1.0.0-beta.13:14",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "The quest round plans one route through every open quest and every hand-in of your log in the best order (/bq round or the button in My quests).",
  },
  {
    id = "1.0.0-beta.13:15",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "With Bastian's Notes the map's bookmarks are kept in your lists, can be renamed there and hidden with their list.",
  },
  {
    id = "1.0.0-beta.13:16",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Share a list of notes and bookmarks with your party, raid, guild or a friend, or copy it as text; a received list is only kept when you accept it, and private notes never leave.",
  },
  {
    id = "1.0.0-beta.13:17",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Send a spot or a place to your group, see what your group sends you on the map for half an hour, and plan a route to a member with /broute member.",
  },
  {
    id = "1.0.0-beta.13:18",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Routes over boats and zeppelins know when they leave once you or a group or guild member has ridden them.",
  },
  {
    id = "1.0.0-beta.13:19",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Explore lists the quests and farm spots near you by gold or XP per hour, the way there included.",
  },
  {
    id = "1.0.0-beta.13:20",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Right-click the map's Player button to jump to where your other characters are, or to send your location to your group, your guild or a friend.",
  },
  {
    id = "1.0.0-beta.13:21",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Explore now lists the market's sale and craft opportunities at the auction house beside quests and farm spots (Forever).",
  },
  {
    id = "1.0.0-beta.13:22",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Explore can plan your next hour: the best stops in order, with arrival times and gains, and one click routes through them.",
  },
  {
    id = "1.0.0-beta.13:23",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Creatures that roam show their area on the map.",
  },
  {
    id = "1.0.0-beta.13:24",
    date = "2026-10-29",
    version = "1.0.0-beta.13",
    text = "Where you walk and the map knew no way, the route planner learns the way and uses it at once.",
  },
}
