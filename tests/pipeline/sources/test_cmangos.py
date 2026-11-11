"""CMaNGOS dump reader against a small .sql.gz made from the real classic-db 1.12.1 dump."""

import gzip
from pathlib import Path

import pytest

from bastians_build.sources import cmangos

DUMP = (
    Path(__file__).resolve().parents[2]
    / "fixtures"
    / "sources"
    / "cmangos"
    / "classicdb_mini.sql.gz"
)


@pytest.fixture(scope="module")
def tables():
    return cmangos.read_tables(DUMP)


def test_tokenizer_handles_commas_parens_quotes_and_null():
    line = r"(1,'a, (b)',NULL,-2.5,'it\'s'),(2,'x''y','\"q\"\n',0,1e3);"
    assert list(cmangos.parse_values(line)) == [
        [1, "a, (b)", None, -2.5, "it's"],
        [2, "x'y", '"q"\n', 0, 1000.0],
    ]


def test_unescape():
    assert cmangos.unescape(r"a\\b\'c\"d\ne") == "a\\b'c\"d\ne"


def test_read_lines_takes_columns_from_create_table():
    lines = [
        "CREATE TABLE `t` (\n",
        "  `a` int NOT NULL,\n",
        "  `b` varchar(10),\n",
        "  `c` int,\n",
        ") ENGINE=InnoDB;\n",
        "INSERT INTO `t` VALUES (1,'x',3),(2,NULL,4);\n",
        "INSERT INTO `other` VALUES (9);\n",
    ]
    assert cmangos.read_lines(lines, {"t": ("c", "b")}) == {
        "t": [{"c": 3, "b": "x"}, {"c": 4, "b": None}]
    }
    with pytest.raises(KeyError):
        cmangos.read_lines(lines, {"t": ("nope",)})


def test_streams_only_wanted_tables(tmp_path):
    path = tmp_path / "d.sql.gz"
    with gzip.open(path, "wt", encoding="utf-8") as fh:
        fh.write("CREATE TABLE `t` (\n  `a` int,\n) ;\nINSERT INTO `t` VALUES (7);\n")
    assert cmangos.read_tables(path, {"t": ("a",)}) == {"t": [{"a": 7}]}


def test_table_counts(tables):
    assert {k: len(v) for k, v in tables.items()} == {
        "quest_template": 5,
        "creature_template": 6,
        "creature": 6,
        "gameobject_template": 4,  # with Mageroyal, the owner of loot list 1417 (11.11.2026)
        "gameobject": 3,
        "npc_vendor": 6,
        "npc_trainer": 6,
        "npc_trainer_template": 8,
        "creature_loot_template": 9,
        "gameobject_loot_template": 3,
        "reference_loot_template": 5,
        "item_template": 9,
        "spell_template": 28,
        "disenchant_loot_template": 4,  # lists 1 and 21 (31.10.2026)
        "creature_spawn_entry": 0,  # the fixture has none: test_a_spawn_of_id_0_takes_its_entries
        "gameobject_spawn_entry": 0,
        # the links' tables (package QD3): not in the fixture dump; the tests below read text
        "item_loot_template": 0,
        "skinning_loot_template": 0,
        "pickpocketing_loot_template": 0,
        "fishing_loot_template": 0,
        "spell_script_target": 0,
        "quest_poi": 0,
        "quest_poi_points": 0,
        "areatrigger_involvedrelation": 0,
    }


def test_disenchant_lists_and_the_items_that_name_them(tables):
    lists = cmangos.disenchant_lists(tables)
    # uncommon armour: Strange Dust at 80 %, the essence shares the rest of the group
    assert lists[1] == [[10940, 80.0, 1, 2], [10938, 20.0, 1, 2]]
    assert lists[21] == [[10938, 80.0, 1, 2], [10940, 20.0, 1, 2]]  # uncommon weapons
    items = {it.id: it.disenchant_id for it in cmangos.item_rows(tables)}
    assert items[6085] == 1 and items[6215] == 21
    assert items[2589] is None  # Linen Cloth: not disenchantable


def test_quests(tables):
    rows = {q.id: q for q in cmangos.quest_rows(tables)}
    assert sorted(rows) == [6, 7, 62, 76, 176]
    q62 = rows[62]
    assert q62.title == "The Fargodeep Mine"
    assert (q62.quest_level, q62.min_level, q62.zone_or_sort) == (7, 4, 12)
    assert q62.reward_money == 125 and q62.required_money == 0
    assert q62.reward_money_max_level == 288
    assert q62.next_quest_in_chain == 76 and q62.prev_quest_id is None
    assert q62.required_races == 77 and q62.required_classes is None
    assert q62.details.startswith("The mine in Northshire isn't the only one with problems!")
    assert "$B$B" in q62.details  # server placeholders stay
    assert rows[76].prev_quest_id == 62 and rows[76].reward_money == 350
    hogger = rows[176]
    assert hogger.title == 'Wanted: "Hogger"'  # escaped quote in the dump, folded double space
    assert hogger.required_items == ((1931, 1),)
    assert hogger.choice_items == ((6085, 1), (6084, 1), (6215, 1))
    assert hogger.reward_items == ()
    assert hogger.type == 1 and hogger.reward_money == 0
    assert hogger.reward_money_max_level == 525
    assert hogger.src_item_id is None


def test_creature_templates_and_escaped_apostrophe(tables):
    npcs = {r["Entry"]: r for r in tables["creature_template"]}
    assert npcs[448]["Name"] == "Hogger"
    assert npcs[448]["SubName"] is None and npcs[448]["Rank"] == 1
    assert (npcs[448]["MinLevel"], npcs[448]["MaxLevel"]) == (11, 11)
    assert npcs[240]["Name"] == "Marshal Dughan" and npcs[240]["NpcFlags"] == 3
    assert npcs[268]["Name"] == "Sirra Von'Indi"
    assert npcs[54]["SubName"] == "Weaponsmith"


def test_npc_flags_are_the_classic_bits_not_the_retail_family(tables):
    """Stormwind's auctioneers showed as repairers and its stable masters as flight masters
    (Forever, 05.11.2026): the dump's NpcFlags are the Classic 1.12 bits and were read with the
    retail table. The values are the dump's own (ClassicDB z2815)."""
    assert cmangos.npc_services(4096) == ["auctioneer"]  # Auctioneer Chilton, Fitch, Jaxon
    assert cmangos.npc_services(8193) == ["stablemaster"]  # Sylista, Jenova Stoneshield
    assert cmangos.npc_services(11) == ["questgiver", "flightmaster"]  # Dungar Longdrink
    assert cmangos.npc_services(135) == ["questgiver", "vendor", "innkeeper"]  # Innkeeper Allison
    assert cmangos.npc_services(257) == ["banker"]  # Olivia Burnside
    assert cmangos.npc_services(2049) == ["battlemaster"]
    assert cmangos.npc_services(19) == ["questgiver", "trainer"]
    # every Classic service bit has one flag, and none of the retail family's high bits is read
    assert cmangos.npc_services(0x7FFF) == list(cmangos.NPC_FLAGS.values())
    assert sorted(cmangos.NPC_FLAGS) == [2, 4, 8, 16, 128, 256, 2048, 4096, 8192, 16384]
    assert cmangos.npc_services(65536 | 131072 | 1048576 | 2097152 | 4194304) == []
    # gossip, spirit healer and guide, petitioner, tabard designer: no service flag; unknown: none
    assert cmangos.npc_services(1 | 32 | 64 | 512 | 1024) == []
    assert cmangos.npc_services(None) == [] and cmangos.npc_services(0) == []
    # the fixture's rows: Corina Steele sells and repairs (4 + 16384), the mage trainer trains
    npcs = {r["Entry"]: r for r in tables["creature_template"]}
    assert npcs[54]["NpcFlags"] == 16388
    assert cmangos.npc_services(npcs[54]["NpcFlags"]) == ["vendor", "repair"]
    assert cmangos.npc_services(npcs[198]["NpcFlags"]) == ["questgiver", "trainer"]
    assert cmangos.npc_services(npcs[448]["NpcFlags"]) == []  # Hogger serves nobody


def test_spawns(tables):
    rows = {r.guid: r for r in cmangos.spawn_rows(tables)}
    assert rows[81064] == cmangos.SpawnRow(
        "creature", 81064, 448, 0, -9947.88, 594.773, 39.608, spawndist=8.0
    )  # Hogger roams 8 yards (W5: area runs)
    assert rows[456].spawndist is None  # objects do not roam
    assert rows[80334].entry == 240 and rows[80334].position_x == -9465.52
    assert rows[456].kind == "object" and rows[456].entry == 1617
    assert rows[458].map_id == 1  # Kalimdor
    assert len(rows) == 9


def test_gameobject_template(tables):
    objs = {r["entry"]: r for r in tables["gameobject_template"]}
    assert objs[1617] == {
        "entry": 1617,
        "type": 3,
        "name": "Silverleaf",
        "data0": 29,
        "data1": 1414,  # its list in gameobject_loot_template
    }
    assert objs[35]["name"] == "Captain's Footlocker"


def test_vendor_rows(tables):
    rows = cmangos.vendor_rows(tables)
    assert rows[0] == cmangos.VendorRow(66, 6270, 1, 9000)  # limited stock restocks
    assert rows[1] == cmangos.VendorRow(66, 6260, None, None)  # unlimited: not zero
    assert {r.npc_id for r in rows} == {66, 167}


def test_trainer_services_direct_and_template(tables):
    services = cmangos.trainer_services(tables)
    mage = [s for s in services if s.trainer_id == 198]
    assert len(mage) == 6
    frostbolt = next(s for s in mage if s.spell_id == 1142)
    assert frostbolt.learned_spell_id == 116  # the trainer entry teaches a different spell
    assert frostbolt.name == "Frostbolt" and frostbolt.rank == "Rank 1"
    assert frostbolt.cost == 100 and frostbolt.req_level == 4
    assert frostbolt.trainer_name == "Khelden Bremen"
    assert frostbolt.trainer_subname == "Mage Trainer"
    assert frostbolt.req_skill is None and frostbolt.item_id is None
    food = next(s for s in mage if s.spell_id == 1249)
    assert food.name == "Conjure Food" and food.item_id == 5349  # creates an item
    # Mogwah uses trainer template 11 (npc_trainer_template), no direct rows
    warrior = [s for s in services if s.trainer_id == 1403]
    assert len(warrior) == 8
    rend = next(s for s in warrior if s.name == "Rend")
    assert (rend.learned_spell_id, rend.cost, rend.req_level) == (772, 100, 4)
    thunder = next(s for s in warrior if s.learned_spell_id == 8198)
    assert thunder.name == "Thunder Clap" and thunder.rank == "Rank 2" and thunder.cost == 3000
    # creatures without services produce no rows
    assert not [s for s in services if s.trainer_id == 448]


def test_loot_rows(tables):
    rows = cmangos.loot_rows(tables)
    hogger = [r for r in rows if r.kind == "creature" and r.entry == 448]
    by_item = {r.item_id: r for r in hogger if r.item_id}
    claw = by_item[1931]
    assert claw.quest_drop is True and claw.chance_pct == 100.0  # stored as -100
    assert by_item[2589].chance_pct == 23.3306 and by_item[2589].max_count == 4
    assert by_item[117].quest_drop is False
    ref = next(r for r in hogger if r.reference_id)
    assert ref == cmangos.LootRow("creature", 448, None, 0.8, False, None, None, None, 50502)
    # a chest's rows are those of the list it names in `data1`, under the chest's own id: list
    # 1417 is Mageroyal's (object 1620), and no object 1417 holds it (11.11.2026)
    assert not [r for r in rows if r.kind == "object" and r.entry == 1417]
    obj = [r for r in rows if r.kind == "object" and r.entry == 1620]
    assert len(obj) == 3 and obj[0].item_id == 785 and obj[0].max_count == 3
    refs = [r for r in rows if r.kind == "reference"]
    assert len(refs) == 5 and all(r.group_id == 1 for r in refs)
    assert all(r.chance_pct == 20.0 for r in refs)  # no explicit chance: equal share of the group


def test_group_chances_without_free_members():
    rows = [{"groupid": 1, "ChanceOrQuestChance": 100}, {"groupid": 1, "ChanceOrQuestChance": 0}]
    assert [c for _, c in cmangos._group_chances(rows)] == [100.0, 0.0]


def test_items(tables):
    items = {i.id: i for i in cmangos.item_rows(tables)}
    assert items[117].name == "Tough Jerky"
    assert items[117].buy_price == 25 and items[117].stackable == 20
    assert items[1931].name == "Huge Gnoll Claw" and items[1931].quality == 1


def test_spells_have_effect_columns(tables):
    spells = {s["Id"]: s for s in tables["spell_template"]}
    assert spells[1142]["Effect1"] == cmangos.EFFECT_LEARN_SPELL
    assert spells[1142]["EffectTriggerSpell1"] == 116
    assert spells[116]["SpellName"] == "Frostbolt"


def test_quest_rewards_carry_reputation_spell_and_the_xp_of_the_max_level_money():
    """a quest page shows what the quest earns. 1.12 has no XP column; the money
    a quest pays at level 60 is its XP at 6 copper per 10 XP (Kobold Camp Cleanup: 102 -> 170)."""
    from bastians_build.canon import quest_xp
    from bastians_build.sources.cmangos import quest_rows

    row = {
        "entry": 7,
        "Title": "Kobold Camp Cleanup",
        "RewOrReqMoney": 25,
        "RewMoneyMaxLevel": 102,
        "RewRepFaction1": 72,
        "RewRepValue1": 250,
        "RewRepFaction2": 0,
        "RewRepValue2": 0,
        "RewRepFaction3": 54,
        "RewRepValue3": -25,
    }
    cluck = {"entry": 3861, "Title": "CLUCK!", "RewSpell": 0, "RewSpellCast": 13563}
    q, c = quest_rows({"quest_template": [row, cluck]})
    assert q.reward_rep == ((72, 250), (54, -25)) and q.reward_spell is None
    assert c.reward_rep == () and c.reward_spell == 13563
    assert quest_xp(102) == 170 and quest_xp(525) == 875 and quest_xp(288) == 480
    assert quest_xp(0) is None and quest_xp(None) is None


def test_a_spawn_of_id_0_takes_its_entries():
    place = {"map": 0, "position_x": 1.0, "position_y": 2.0, "position_z": 3.0}
    rows = cmangos.spawn_rows(
        {
            "creature": [{"guid": 7, "id": 0, **place}, {"guid": 8, "id": 46, **place}],
            "creature_spawn_entry": [{"guid": 7, "entry": 97}, {"guid": 7, "entry": 98}],
            "gameobject": [{"guid": 9, "id": 0, **place}],
        }
    )
    assert [(r.kind, r.guid, r.entry) for r in rows] == [
        ("creature", 7, 97),
        ("creature", 7, 98),
        ("creature", 8, 46),
    ]  # the object has no entry row: it stays out, as an id of 0 did


# ---- the links (package QD3): text dumps of the tables the fixture dump lacks ------------------

LOOT = (
    "  `entry` int,\n  `item` int,\n  `ChanceOrQuestChance` float,\n  `groupid` int,\n"
    "  `mincountOrRef` int,\n  `maxcount` int\n);\n"
)
LINKS_SQL = (
    "CREATE TABLE `quest_template` (\n"
    "  `entry` int,\n  `SrcItemId` int,\n  `SrcItemCount` int,\n"
    "  `ReqCreatureOrGOId1` int,\n  `ReqCreatureOrGOId2` int,\n"
    "  `ReqCreatureOrGOCount1` int,\n  `ReqCreatureOrGOCount2` int,\n"
    "  `ReqSpellCast1` int,\n  `ReqSpellCast2` int,\n"
    "  `SpecialFlags` int,\n  `PointMapId` int,\n  `PointX` float,\n  `PointY` float\n);\n"
    "INSERT INTO `quest_template` VALUES (1861,7207,1,0,0,0,0,0,0,0,0,0,0),"
    "(905,0,0,3256,-20359,8,0,0,6717,2,1,-650.5,-3900.25);\n"
    "CREATE TABLE `item_template` (\n"
    "  `entry` int,\n  `name` varchar(100),\n  `spellid_1` int,\n  `spelltrigger_1` int\n);\n"
    "INSERT INTO `item_template` VALUES (7207,'Jennea''s Flask',8919,0),"
    "(7206,'Mirror Lake Water Sample',0,0),(5,'Worn Charm',8919,1),(6,'Totem',700,0);\n"
    "CREATE TABLE `spell_template` (\n"
    "  `Id` int,\n  `SpellName` varchar(100),\n  `RequiresSpellFocus` int,\n"
    "  `Effect1` int,\n  `EffectItemType1` int\n);\n"
    "INSERT INTO `spell_template` VALUES (8919,'Fill Jennea''s Flask',123,24,7206),"
    "(700,'Plant Totem',0,3,0);\n"
    "CREATE TABLE `spell_script_target` (\n"
    "  `entry` int,\n  `type` int,\n  `targetEntry` int\n);\n"
    "INSERT INTO `spell_script_target` VALUES (700,1,4000),(700,0,5000);\n"
    "CREATE TABLE `gameobject_template` (\n"
    "  `entry` int,\n  `type` int,\n  `name` varchar(100),\n  `data0` int,\n  `data1` int\n);\n"
    "INSERT INTO `gameobject_template` VALUES (174794,8,'Mirror Lake Waterwall',123,0),"
    "(102414,8,'Mirror Lake Water',123,0),(2843,3,'Battered Chest',57,2843),"
    "(2849,3,'Battered Chest',57,2843),(180000,25,'School of Fish',0,9000);\n"
    "CREATE TABLE `gameobject_loot_template` (\n" + LOOT + "INSERT INTO `gameobject_loot_template` "
    "VALUES (2843,2589,40,0,1,2),(9000,6358,100,0,1,1),(77,1,100,0,1,1);\n"
    "CREATE TABLE `creature_template` (\n"
    "  `Entry` int,\n  `Name` varchar(100),\n  `PickpocketLootId` int,\n  `SkinningLootId` int\n"
    ");\n"
    "INSERT INTO `creature_template` VALUES (113,'Stonetusk Boar',0,113),(119,'Longsnout',0,113),"
    "(98,'Riverpaw Taskmaster',98,0);\n"
    "CREATE TABLE `item_loot_template` (\n" + LOOT + "INSERT INTO `item_loot_template` VALUES "
    "(5523,5498,5,0,1,1),(5523,7974,95,0,1,1),(5523,11111,100,0,-11111,1);\n"
    "CREATE TABLE `skinning_loot_template` (\n" + LOOT + "INSERT INTO `skinning_loot_template` "
    "VALUES (113,2318,60,1,1,1),(113,2934,0,1,1,1);\n"
    "CREATE TABLE `pickpocketing_loot_template` (\n" + LOOT + "INSERT INTO "
    "`pickpocketing_loot_template` VALUES (98,2589,12.5,0,1,1);\n"
    "CREATE TABLE `fishing_loot_template` (\n" + LOOT + "INSERT INTO `fishing_loot_template` "
    "VALUES (12,6291,50,0,1,1),(40,6291,20,0,1,1);\n"
    "CREATE TABLE `quest_poi` (\n"
    "  `questId` int,\n  `poiId` int,\n  `objIndex` int,\n  `mapId` int\n);\n"
    "INSERT INTO `quest_poi` VALUES (905,0,-1,1),(905,1,0,1),(905,2,16,1),(905,3,4,1);\n"
    "CREATE TABLE `quest_poi_points` (\n"
    "  `questId` int,\n  `poiId` int,\n  `x` int,\n  `y` int\n);\n"
    "INSERT INTO `quest_poi_points` VALUES (905,0,-400,-2600),(905,1,-10,-20),(905,1,-30,-40),"
    "(905,2,5,6);\n"
    "CREATE TABLE `areatrigger_involvedrelation` (\n  `id` int,\n  `quest` int\n);\n"
    "INSERT INTO `areatrigger_involvedrelation` VALUES (87,76),(88,76),(98,201);\n"
)


@pytest.fixture(scope="module")
def link_tables():
    """The tables of LINKS_SQL with the columns the text has; a column it lacks reads as None."""
    wanted = {}
    for name, columns in cmangos.WANTED.items():
        block = LINKS_SQL.partition(f"CREATE TABLE `{name}` (")[2].partition(");")[0]
        if block:
            wanted[name] = tuple(c for c in columns if f"`{c}`" in block)
    return cmangos.read_lines(LINKS_SQL.splitlines(), wanted)


def test_a_quests_goals_its_handed_item_and_its_own_point(link_tables):
    """plan-quest-links.md G3, G6: the creature and object columns with their counts and the
    spell to cast, the provided item with its count, the quest's own point."""
    quests = {q.id: q for q in cmangos.quest_rows(link_tables)}
    mirror, totem = quests[1861], quests[905]
    assert mirror.src_item_id == 7207 and mirror.src_item_count == 1
    assert mirror.goals == () and mirror.point is None and mirror.exploration is False
    assert totem.goals == (
        cmangos.QuestGoal("npc", 3256, 8, None, column=1),
        # a negative id is an object; no count
        cmangos.QuestGoal("object", 20359, None, 6717, column=2),
    )
    assert totem.point == (1, -650.5, -3900.25) and totem.exploration is True
    assert totem.src_item_id is None and totem.src_item_count is None


def test_a_chests_list_is_read_under_every_object_that_opens_it(link_tables):
    """11.11.2026: `gameobject_loot_template` is keyed by `data1`, not by the object."""
    assert cmangos.object_loot_owners(link_tables) == {2843: [2843, 2849], 9000: [180000]}
    rows = [r for r in cmangos.loot_rows(link_tables) if r.kind == "object"]
    assert [(r.entry, r.item_id) for r in rows] == [(2843, 2589), (2849, 2589), (180000, 6358)]
    # a dump cut down to the old columns: the list id stands for the object, as before
    old = {
        "gameobject_template": [{"entry": 77, "type": 3, "name": "Chest"}],
        "gameobject_loot_template": link_tables["gameobject_loot_template"],
    }
    assert cmangos.object_loot_owners(old) is None
    assert {r.entry for r in cmangos.loot_rows(old)} == {77, 2843, 9000}


def test_links_what_is_made_held_skinned_picked_and_fished(link_tables):
    links = cmangos.links(link_tables)
    flask = cmangos.Made(item_id=7207, spell_id=8919, focus=123, targets=())
    assert links.made == {7206: [flask]}  # the charm's spell is no use spell (trigger 1)
    totem = cmangos.Made(6, 700, None, (("npc", 4000), ("object", 5000)))
    assert links.uses == {6: [totem], 7207: [flask]}  # used at a place, product or not
    assert links.spells == {6: (700,), 7207: (8919,)}
    assert links.focus_objects == {123: [102414, 174794]}  # a chest's data0 is no focus
    # only what a list names itself: the lockbox's shared list (a reference) is no source
    assert links.held == {5498: [(5523, 5.0)], 7974: [(5523, 95.0)]}
    # a list is shared by the creatures that name it; a member without a chance shares the rest
    assert links.skinned == {2318: [(113, 60.0), (119, 60.0)], 2934: [(113, 40.0), (119, 40.0)]}
    assert links.picked == {2589: [(98, 12.5)]}
    assert links.fished == {6291: [(12, 50.0), (40, 20.0)]}  # by AreaTable id, the likeliest first


def test_links_a_quests_classic_points_and_triggers(link_tables):
    links = cmangos.links(link_tables)
    assert links.points == {
        905: [
            (-1, 1, ((-400.0, -2600.0),)),
            (0, 1, ((-10.0, -20.0), (-30.0, -40.0))),
            (16, 1, ((5.0, 6.0),)),
        ]  # the area without a point (poi 3) is left out
    }
    assert links.triggers == {76: [87, 88], 201: [98]}
