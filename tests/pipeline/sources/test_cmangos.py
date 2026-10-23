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
        "gameobject_template": 3,
        "gameobject": 3,
        "npc_vendor": 6,
        "npc_trainer": 6,
        "npc_trainer_template": 8,
        "creature_loot_template": 9,
        "gameobject_loot_template": 3,
        "reference_loot_template": 5,
        "item_template": 9,
        "spell_template": 28,
    }


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


def test_spawns(tables):
    rows = {r.guid: r for r in cmangos.spawn_rows(tables)}
    assert rows[81064] == cmangos.SpawnRow("creature", 81064, 448, 0, -9947.88, 594.773, 39.608)
    assert rows[80334].entry == 240 and rows[80334].position_x == -9465.52
    assert rows[456].kind == "object" and rows[456].entry == 1617
    assert rows[458].map_id == 1  # Kalimdor
    assert len(rows) == 9


def test_gameobject_template(tables):
    objs = {r["entry"]: r for r in tables["gameobject_template"]}
    assert objs[1617] == {"entry": 1617, "type": 3, "name": "Silverleaf"}
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
    obj = [r for r in rows if r.kind == "object" and r.entry == 1417]
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
