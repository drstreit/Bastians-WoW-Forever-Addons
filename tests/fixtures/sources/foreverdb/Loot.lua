-- Data: ForeverDB.net (https://foreverdb.net), build fixture. Reuse requires this credit: see NOTICE.txt (GPL-3.0 section 7(b)).
-- Test fixture in the shape of ForeverDB 0.44.0's Loot.lua: the bosses' creatures (Mr. Smite has none here).
local _, ns = ...
ns.lootDB = {
  v = 1, built = "fixture",
  inst = {
    { id = 36, name = "The Deadmines", kind = "dungeon", lv = "15-25", zone = 1436, open = true,
      bosses = {
        { npc = 644, name = "Rhahk'Zor", loot = "872:0:f:2" },
        { name = "Mr. Smite", loot = "" },
        { npc = 639, name = "Edwin VanCleef", loot = "5187:0:c" },
      },
    },
    { id = 249, name = "Onyxia's Lair", kind = "raid", lv = "60", zone = 1445,
      bosses = {
        { npc = 10184, name = "Onyxia", loot = "16914:100:c" },
      },
    },
    { id = 2999, name = "Ruins of Lordaeron", kind = "dungeon", lv = "15-22", zone = 1420, forever = true, open = true,
      bosses = {
        { npc = 250483, name = "Witherfang", loot = "" },
      },
    },
  },
}
