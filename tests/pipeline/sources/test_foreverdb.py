"""ForeverDB readers against trimmed copies of the real 0.39.0 data files."""

from pathlib import Path

import pytest

from bastians_build.sources import foreverdb as fdb

FIX = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "foreverdb"


def text(name: str) -> str:
    return (FIX / name).read_text(encoding="utf-8")


def test_meta():
    meta = fdb.parse_meta(text("Meta.lua"))
    assert meta == fdb.ForeverMeta("2026-10-19.1f762939", 1792378948, "1.60.1.70450", "0.39.0")


def test_npcs():
    rows = {r.id: r for r in fdb.parse_npcs(text("NPCs.lua"))}
    assert len(rows) == 10
    assert list(rows) == sorted(rows)
    assert rows[54] == fdb.NpcRow(
        54, "Corina Steele", "Weaponsmith", 1429, 41.6, 65.8, "A", seen_in_forever=True
    )
    assert rows[167].seen_in_forever is False  # Classic place, nobody saw the NPC
    assert rows[233].title is None  # empty title is unknown, not ""
    assert rows[1669].side is None  # neutral vendor
    assert rows[74].title == "Cloth & Leather Armor Merchant"


def test_npcs_file_helper():
    assert len(fdb.read_npcs(FIX / "NPCs.lua")) == 10


def test_reagents_and_learned_from():
    assert fdb.parse_reagents("765:1,3371:2") == ((765, 1), (3371, 2))
    assert fdb.parse_reagents("") == ()
    assert fdb.parse_learned_from("i250380") == ("item", 250380)
    assert fdb.parse_learned_from("a") == ("auto", None)
    assert fdb.parse_learned_from("t") == ("trainer", None)
    assert fdb.parse_learned_from("") == (None, None)
    with pytest.raises(ValueError):
        fdb.parse_learned_from("x9")


def test_recipes():
    rows = fdb.parse_recipes(text("Recipes.lua"))
    assert len(rows) == 25
    assert [r.profession for r in rows[:1]] == ["Alchemy"]
    assert {r.profession for r in rows} == {"Alchemy", "Cooking", "First Aid", "Fishing"}
    by_spell = {r.spell_id: r for r in rows}
    assert by_spell[1245250] == fdb.RecipeRow(
        "Alchemy",
        1245250,
        "Elixir of Minor Force",
        1,
        10,
        12,
        15,
        247755,
        1,
        ((765, 1), (3371, 1)),
        "auto",
        None,
        0,
        new_in_forever=True,
    )
    learned = by_spell[1250793]
    assert (learned.source_kind, learned.source_item_id) == ("item", 250380)
    assert by_spell[3170].source_kind == "trainer"
    unknown = by_spell[1230564]  # learned_from "" in the file
    assert (unknown.source_kind, unknown.source_item_id) == (None, None)
    assert unknown.camp_tier == 1
    assert by_spell[1262998].camp_tier == 3
    assert by_spell[7183].new_in_forever is False


def test_decode_points():
    assert fdb.decode_points("069v") == [(0.6, 35.5)]
    assert fdb.decode_points("") == []
    with pytest.raises(ValueError):
        fdb.decode_points("069")


def test_decode_points_values():
    # "1r" = 1*36+27 = 63 -> 6.3; "9f" = 9*36+15 = 339 -> 33.9
    assert fdb.decode_points("1r9f") == [(6.3, 33.9)]
    assert fdb.decode_points("zzzz") == [(129.5, 129.5)]


def test_gather():
    kinds, points, zones = fdb.parse_gather(text("Gather.lua"))
    assert [k.id for k in kinds] == [1, 2, 3, 4, 5, 6, 45, 47, 52]
    assert kinds[1] == fdb.GatherKind(
        2, "Peacebloom", "herb", 1, 2447, 133939, (1618, 3724), (), None
    )
    skin = {k.id: k for k in kinds}[45]
    assert (skin.profession, skin.npc_ids, skin.level_range) == ("skin", (2956,), (6, 7))
    assert skin.item_id is None and skin.object_ids == ()
    assert zones == [fdb.GatherZone(1411, 25), fdb.GatherZone(1412, 25)]
    briar = [p for p in points if p.kind_id == 6 and p.ui_map_id == 1411]
    assert len(briar) == 7  # "c" has 28 characters
    assert briar[0] == fdb.GatherPoint(6, 1411, 0.7, 35.4, "classic", 2.3)
    seen = [p for p in points if p.src == "forever"]
    assert seen == [fdb.GatherPoint(52, 1411, 59.6, 82.8, "forever", 60.0)]
    assert len(points) == 341


def test_entity_refs():
    assert fdb.parse_entity_refs("n823") == ("npc:823",)
    assert fdb.parse_entity_refs("o1234, n5") == ("object:1234", "npc:5")
    assert fdb.parse_entity_refs("") == ()
    with pytest.raises(ValueError):
        fdb.parse_entity_refs("x5")


def test_quests():
    rows = {r.id: r for r in fdb.parse_quests(text("QuestForever.lua"))}
    assert len(rows) == 14
    assert rows[6] == fdb.QuestRow(
        6,
        "Bounty on Garrick Padfoot",
        5,
        2,
        "Kill Garrick Padfoot and bring his head to Deputy Willem at Northshire Abbey.",
        ("npc:823",),
        ("npc:823",),
        3,
        new_in_forever=False,
    )
    assert rows[2].starts == () and rows[2].ends == ("npc:12696",)  # empty starts
    assert rows[20].title is None and rows[20].objective_text is None
    assert rows[11].starts == () and rows[11].ends == ()
    assert rows[37].ends == ("object:55",)
    assert rows[45].starts == ("object:55",)
    assert rows[9].objective_text is None
    assert rows[2].min_level == 0  # kept as in the file: no minimum


def test_quest_rejects_short_record():
    with pytest.raises(ValueError):
        fdb.parse_quests('local _, ns = ...\nns.qfQuests = {[1]="a|1|0"}')


def test_quest_text_with_pipe_stays_in_objective():
    rows = fdb.parse_quests('local _, ns = ...\nns.qfQuests = {[1]="T|3|1|do a|b|n5|n6|2|1"}')
    assert rows[0].objective_text == "do a|b"
    assert rows[0].starts == ("npc:5",)
    assert rows[0].ends == ("npc:6",)
    assert rows[0].seen_by_players == 2 and rows[0].new_in_forever is True


def test_items():
    rows = {r.id: r for r in fdb.parse_items(text("Items.lua"))}
    assert len(rows) == 12
    assert rows[38].drop == fdb.Drop("Tattered Chest", 1.4, True, 1)
    assert rows[117].vendors == fdb.Vendors(50, "Barkeep Morag", "Orgrimmar", True)
    assert rows[117].drop == fdb.Drop("Battered Chest", 19.0, True, 17)
    assert rows[117].drops_seen == fdb.DropsSeen(35, 5)
    assert rows[117].quest == "Break a Few Eggs"
    assert rows[118].made_by == fdb.MadeBy("First Aid", 55)  # file indexes professions from 0
    assert rows[118].used_in == fdb.UsedIn(1, ("Tailoring",))
    assert rows[118].drop.classic is False
    assert rows[159].used_in == fdb.UsedIn(14, ("Cooking", "Engineering", "First Aid"))
    assert rows[724].changed_in_forever and not rows[724].new_in_forever
    assert rows[724].made_by == fdb.MadeBy("Cooking", 50)
    assert rows[763].changed_in_forever and rows[763].made_by is None
    assert rows[33154].new_in_forever
    assert rows[787].vendors.seen_in_forever is False
    assert rows[1164].reputation == fdb.Reputation("Argent Dawn", "Honored")
    assert rows[60].made_by is None and rows[60].vendors is None  # unknown stays None
    assert rows[60].raw == "qBounty on Garrick Padfoot"


def test_item_fact_with_unexpected_shape_stays_raw():
    prof = ["Alchemy"]
    facts = fdb.parse_item_facts(1, "mX|v1~a", prof, ["Hated"])
    assert facts.made_by is None and facts.vendors is None
    assert facts.raw == "mX|v1~a"


def test_search_names():
    names = fdb.parse_search_names(text("SearchNames.lua"))
    assert len(names) == 12
    assert names[25] == "Worn Shortsword"
    assert names[41] == "OLDRecruit's Belt"  # verbatim
    assert fdb.is_old(names[41]) and fdb.is_old(names[42])
    assert not fdb.is_old(names[43])
    assert names.get(26) is None
