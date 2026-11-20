-- Data: ForeverDB.net (https://foreverdb.net). Reuse requires this credit.
local _, ns = ...
ns.specialQuests = { v = 1, built = "2026-10-15", chains = {
  { key = "sleeping-bag", name = "Cozy Sleeping Bag", cat = "Secret", start = "a charred note",
    why = "A bedroll you can unroll anywhere.", seen = true, lv = { 14 }, reward = { 211527, 216619 },
    steps = {
      { q = 79007, side = "h", t = "Read the note.", title = "A note", m = 1413, x = 46.3, y = 73.9, seen = true },
      { q = 79008, side = "a", t = "Read the note.", title = "A note", m = 1436, x = 37.0, y = 50.0, seen = true },
      { q = 79976, t = "Hand it in.", title = "The end", m = 1437, x = 10.0, y = 20.0 },
    } },
  { key = "camping-elwynn", name = "The Great Outdoors: Elwynn Forest", cat = "Camping", side = "a",
    start = "Marshal McBride", why = "Camping \226\128\148 rest by a fire.", seen = true, lv = { 6 }, reward = { },
    steps = {
      { q = 96627, t = "Take The Adventurer.", m = 1429, x = 48.9, y = 41.6 },
      { qany = { 97915, 97916 }, t = "Learn a camp item." },
    } },
  { key = "musical-gustjumper", name = "Musical Gustjumper", cat = "Secret pets", start = "the frogs",
    why = "A pet frog.", note = "reported by players", reward = { 268109 },
    steps = { { item = 268109, t = "Sing to the frogs.", m = 2521, x = 51.5, y = 72.1 } } },
  { key = "keystone-fragment", name = "Keystone Fragment (unsolved)", cat = "Secret", start = "a riddle",
    why = "Nobody knows.", reward = { }, steps = { { t = "Find the fragment." } } },
} }
