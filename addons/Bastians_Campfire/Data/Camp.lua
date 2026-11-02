-- The camp data of Bastian's Campfire (campfire.md "Data"): the features, their items, auras and
-- skill tiers, the benefits per level. Hand-written v1.
-- Sources: Campfire Tooltips: Forever 1.0.1 (GideonWhitlock, GPL-3.0-or-later; checked by its
-- author against build 1.60.1.70009, informed by Tweaks Forever, GPL-3.0-or-later) for the auras,
-- the placement spells, the object entries and the level brackets; every id cross-checked against
-- the launch client's tables (build 1.60.1.70707, SpellName and ItemSparse, 02.11.2026: all 49
-- spell ids present with the same names); the items, skills and ranks from ItemSparse alone.
-- A number not measured on our side stays as the source gives it; a missing one stays nil.
local _, ns = ...

local Camp = {}
ns.Camp = Camp

Camp.BUILD = "1.60.1.70707" -- the client tables the ids were checked against
Camp.SOURCE_BUILD = "1.60.1.70009" -- the build Campfire Tooltips' brackets were read from

-- The client's auras around a camp (SpellName, 70707). Whether each shows on the player as an aura
-- is assumed until probes C1 and C7 (forever-api.md).
Camp.NEARBY = 1283391 -- "Campfire Nearby": within some distance of any fire (C7: the radius)
Camp.RESTING = { [1229739] = true, [1289723] = true } -- "Welcoming Campfire": the 60 s rest
Camp.REST_SECONDS = 60 -- SpellMisc -> SpellDuration (Campfire Tooltips' SOURCES.md)
Camp.TENT_REST = 1229487 -- "Camp Tent": 30 s by the tent
Camp.BUFF_SECONDS = 3600 -- the stat auras' duration (the same source)
Camp.FADING_SECONDS = 600 -- the warning before the warmth ends (plan-second-wave.md S5)

-- Professions by skill line id (SkillLine, 70707); the names are the client's, translated in the
-- locales from the client's own tables.
Camp.SKILLS = {
  [129] = "First Aid",
  [164] = "Blacksmithing",
  [165] = "Leatherworking",
  [171] = "Alchemy",
  [182] = "Herbalism",
  [185] = "Cooking",
  [186] = "Mining",
  [197] = "Tailoring",
  [202] = "Engineering",
  [333] = "Enchanting",
  [356] = "Fishing",
  [393] = "Skinning",
}

-- The benefits: the aura the player gets, what it gives, the class buff it does not stack with
-- (the client's spell name, translated in the locales), the value per level as literal brackets
-- { up to level, value } (the first bracket whose level is >= the player's applies).
Camp.BENEFITS = {
  mana = {
    aura = 1230587,
    label = "Mana every 5 seconds",
    exclusive = "Blessing of Wisdom",
    levels = { { 23, 10 }, { 33, 15 }, { 43, 20 }, { 53, 24 }, { 60, 29 } },
    format = "+%s mana every 5 seconds",
  },
  strength = {
    aura = 1230172,
    label = "Strength",
    exclusive = "Strength of Earth Totem",
    levels = { { 23, 6 }, { 37, 11 }, { 51, 20 }, { 60, 34 } },
    format = "+%s Strength",
  },
  lute = {
    aura = 1230653,
    label = "Armor, attributes and resistances",
    exclusive = "Mark of the Wild",
    armor = { { 9, 28 }, { 19, 71 }, { 29, 114 }, { 39, 163 }, { 49, 211 }, { 59, 260 }, { 60, 308 } },
    attributes = { { 9, 0 }, { 19, 2 }, { 29, 4 }, { 39, 7 }, { 49, 9 }, { 59, 12 }, { 60, 13 } },
    resistances = { { 29, 0 }, { 39, 6 }, { 49, 12 }, { 59, 16 }, { 60, 22 } },
  },
  stamina = {
    aura = 1230124,
    label = "Stamina",
    exclusive = "Power Word: Fortitude",
    levels = { { 11, 3 }, { 23, 8 }, { 35, 21 }, { 47, 34 }, { 59, 45 }, { 60, 56 } },
    format = "+%s Stamina",
  },
  fish = {
    aura = 1230098,
    label = "All attributes",
    exclusive = "Blessing of Kings",
    levels = { { 60, 8 } },
    format = "+%s%% all attributes",
  },
  intellect = {
    aura = 1229513,
    label = "Intellect",
    exclusive = "Arcane Intellect",
    levels = { { 13, 2 }, { 27, 6 }, { 41, 12 }, { 55, 18 }, { 60, 25 } },
    format = "+%s Intellect",
  },
  attack = {
    aura = 1230164,
    label = "Melee attack power",
    exclusive = "Blessing of Might",
    levels = { { 11, 12 }, { 21, 20 }, { 31, 32 }, { 41, 49 }, { 51, 67 }, { 60, 90 } },
    format = "+%s melee attack power",
  },
  chair = {
    aura = 1229519,
    label = "Critical strike chance",
    exclusive = "Moonkin Aura",
    levels = { { 60, 2 } },
    format = "+%s%% critical strike chance",
  },
  spirit = {
    aura = 1229718,
    label = "Spirit (the banner's faction)",
    exclusive = "Divine Spirit",
    levels = { { 39, 14 }, { 49, 19 }, { 59, 27 }, { 60, 32 } },
    format = "+%s Spirit",
  },
  tent = {
    aura = 1229451, -- "Boosted Rest": the repeat lockout, an hour
    label = "Rested experience",
    levels = { { 60, 5 } },
    format = "Rested experience up to %s%% of a level",
  },
}

-- The order the planner and the card list the benefits in.
Camp.BENEFIT_ORDER =
  { "stamina", "fish", "mana", "strength", "lute", "intellect", "attack", "chair", "spirit", "tent" }

-- The features a player can place: the camp item (ItemSparse), its placement spell, the object
-- entry, the benefit, the profession (skill line) and the rank the item needs, the tier
-- (1 from the trainer or quests, 2 and 3 from a blueprint), the blueprint item. Fields that the
-- client tables do not give stay nil.
local function f(item, spell, object, benefit, skill, rank, blueprint, name, extra)
  local t = {
    item = item,
    spell = spell,
    object = object,
    benefit = benefit,
    skill = skill,
    rank = rank,
    tier = rank >= 300 and 3 or rank >= 140 and 2 or 1,
    blueprint = blueprint,
    name = name,
  }
  for k, v in pairs(extra or {}) do
    t[k] = v
  end
  return t
end

Camp.FEATURES = {
  f(279956, 1307259, 651948, "mana", 171, 20, nil, "Mana Well"),
  f(279970, 1307242, 612120, "mana", 171, 140, 273085, "Fermenter"),
  f(279990, 1307172, 612139, "mana", 171, 300, 273112, "Alchemy Laboratory"),
  f(279944, 1307392, 651950, "strength", 164, 20, nil, "Sharpening Wheel"),
  f(279988, 1307175, 612125, "strength", 164, 140, 273086, "Anvil"),
  f(279955, 1307261, 612136, "strength", 164, 300, 273113, "Master Forge"),
  f(279976, 1307234, 651952, "lute", 333, 20, nil, "Enchanted Lute"),
  f(279985, 1307223, 612130, "lute", 333, 140, 273103, "Arcane Salvager"),
  f(279987, 1307176, 612143, "lute", 333, 300, 273116, "Arcane Forge"),
  f(279968, 1307244, 651953, "stamina", 129, 20, nil, "First Aid Kit"),
  f(279940, 1307396, 612091, "stamina", 129, 140, 273105, "Toxin Study"),
  f(279951, 1307265, 612110, "stamina", 129, 300, 273118, "Plague Doctor's Laboratory"),
  f(279967, 1307245, 651954, "fish", 356, 20, nil, "Fish Bowl"),
  f(279965, 1307247, 612090, "fish", 356, 140, 273141, "Fishing Rack"),
  f(279966, 1307246, 612092, "fish", 356, 300, 273119, "Fishing Hut"),
  f(279962, 1307251, 651955, "intellect", 182, 20, nil, "Incense Candle"),
  f(279964, 1307248, 612087, "intellect", 182, 140, 273106, "Greenhouse"),
  f(279947, 1307387, nil, "intellect", 182, 300, 273120, "Seed Hybridizer", { creature = 260105 }),
  f(279960, 1307254, 651956, "attack", 186, 20, nil, "Lodestone"),
  f(279948, 1307386, 654285, "attack", 186, 140, 273097, "Rock Garden"),
  f(279952, 1307264, 612134, "attack", 186, 300, 273122, "Molten Foundry"),
  f(279979, 1307229, 612275, "chair", 393, 20, nil, "Camp Chair"),
  f(279969, 1307243, 612088, "chair", 393, 140, 273098, "Field Guide"),
  f(279938, 1307397, 612082, "chair", 393, 300, 273109, "Trapper's Workbench"),
  f(279973, 1307239, 612351, "spirit", 197, 20, nil, "Faction Banner", { faction = "Alliance" }),
  f(279972, 1307240, 612350, "spirit", 197, 20, nil, "Faction Banner", { faction = "Horde" }),
  f(279943, 1307393, 612123, "spirit", 197, 140, 273099, "Spinning Wheel"),
  f(279959, 1307255, 612142, "spirit", 197, 300, 273124, "Loom"),
  f(279978, 1307230, 528996, "tent", 165, 20, nil, "Camp Tent"),
  f(279941, 1307395, 612122, "tent", 165, 140, 273096, "Tanning Rack"),
  f(279945, 1307391, 612140, "tent", 165, 300, 273121, "Sewing Machine"),
  -- service features without a camp aura
  f(279950, 1307266, nil, nil, 202, 20, nil, "Reagent Bot", { creature = 242498, service = "Reagents" }),
  f(279949, 1307385, nil, nil, 202, 140, 273092, "Repair Bot", { creature = 254695, service = "Repairs" }),
  f(279989, 1307174, 612145, nil, 202, 300, 273117, "Anarchist's Workbench", { service = "Crafting" }),
  f(279957, 1307257, 612073, nil, 185, 140, 273102, "Cookie's Feast", { service = "Food" }),
  f(279982, 1307226, 612132, nil, 185, 300, 273115, "Iron Oven", { service = "Advanced cooking" }),
}

-- The fires themselves: the kit item, its placement spell, how many features it holds.
Camp.KITS = {
  {
    item = 279981,
    spell = 1307227,
    object = 529161,
    size = 3,
    skill = 185,
    rank = 1,
    name = "Basic Campfire Kit",
  },
  {
    item = 279961,
    spell = 1307252,
    object = 630660,
    size = 5,
    skill = 185,
    rank = 140,
    blueprint = 273087,
    name = "Journeyman Campfire Kit",
  },
  {
    item = 279974,
    spell = 1307237,
    object = 650137,
    size = 10,
    skill = 185,
    rank = 220,
    blueprint = 273101,
    name = "Expert Campfire Kit",
  },
}

-- Lookups, built once.
Camp.BY_AURA, Camp.BY_SPELL, Camp.BY_ITEM = {}, {}, {}
for key, b in pairs(Camp.BENEFITS) do
  b.key = key
  Camp.BY_AURA[b.aura] = key
end
for _, feature in ipairs(Camp.FEATURES) do
  Camp.BY_SPELL[feature.spell] = feature
  Camp.BY_ITEM[feature.item] = feature
end
for _, kit in ipairs(Camp.KITS) do
  kit.kit = true
  Camp.BY_SPELL[kit.spell] = kit
  Camp.BY_ITEM[kit.item] = kit
end
