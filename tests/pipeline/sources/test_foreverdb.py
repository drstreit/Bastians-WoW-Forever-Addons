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
    # Elwynn's row joined the fixture for the zone's fishing skill (catalog review A3.6)
    assert zones == [fdb.GatherZone(1411, 25), fdb.GatherZone(1412, 25), fdb.GatherZone(1429, 25)]
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


TEN_COLUMNS = (
    '-- [quest] = "title|level|min level|objective text|starts|ends|players who saw it'
    '|1 = new in Forever|confirmed previous quest|lowest player level seen completing it"\n'
)


def quests_file(header: str, *rows: str) -> str:
    body = ",".join(f'[{i}]="{row}"' for i, row in enumerate(rows, 1))
    return f"local _, ns = ...\n{header}ns.qfQuests = {{{body}}}"


def test_quests_in_the_ten_column_layout_of_foreverdb_0_57_14():
    rows = fdb.parse_quests(
        quests_file(TEN_COLUMNS, "T|3|1|do a|n5|o6|7|1|18|5", "U|2|0|||n12696|1|0|0|26")
    )
    assert rows[0] == fdb.QuestRow(1, "T", 3, 1, "do a", ("npc:5",), ("object:6",), 7, True, 18, 5)
    assert rows[1].starts == () and rows[1].ends == ("npc:12696",)
    assert rows[1].objective_text is None
    assert rows[1].seen_by_players == 1 and rows[1].new_in_forever is False
    assert rows[1].confirmed_previous is None and rows[1].lowest_level_seen == 26  # 0 is none


def test_quest_text_with_pipe_stays_in_objective_in_the_ten_column_layout():
    rows = fdb.parse_quests(quests_file(TEN_COLUMNS, "T|3|1|do a|b|n5|n6|2|1|0|7"))
    assert rows[0].objective_text == "do a|b"
    assert rows[0].starts == ("npc:5",) and rows[0].ends == ("npc:6",)


def test_quest_rejects_a_short_record_in_the_ten_column_layout():
    with pytest.raises(ValueError, match="expected 10 fields, got 8"):
        fdb.parse_quests(quests_file(TEN_COLUMNS, "T|3|1|do a|n5|n6|2|1"))


ELEVEN_COLUMNS = (
    TEN_COLUMNS[:-2] + '|side (a/h, from its NPCs and the quest before it; empty: unknown)"\n'
)


def test_quests_in_the_eleven_column_layout_of_foreverdb_0_57_24():
    """11.11.2026: the eleventh column held ForeverDB 0.57.24 for a day (the notebook's alarm)."""
    rows = fdb.parse_quests(
        quests_file(
            ELEVEN_COLUMNS,
            "T|3|1|do a|b|n5|o6|7|1|18|5|a",
            "U|2|0|||n12696|1|0|0|26|",
            "V|2|0|x|n1|n2|1|0|0|0|h",
        )
    )
    assert rows[0] == fdb.QuestRow(
        1, "T", 3, 1, "do a|b", ("npc:5",), ("object:6",), 7, True, 18, 5, "A"
    )
    assert rows[1].side is None and rows[1].lowest_level_seen == 26  # empty: unknown
    assert rows[1].starts == () and rows[1].ends == ("npc:12696",)
    assert rows[2].side == "H"


def test_a_column_added_behind_the_known_ones_is_left_unread():
    """ForeverDB adds columns at the end; a new one no longer holds the source."""
    header = ELEVEN_COLUMNS[:-2] + '|something new"\n'
    rows = fdb.parse_quests(quests_file(header, "T|3|1|do a|b|n5|n6|2|1|0|7|h|new"))
    assert rows[0].objective_text == "do a|b"
    assert rows[0].starts == ("npc:5",) and rows[0].ends == ("npc:6",)
    assert rows[0].lowest_level_seen == 7 and rows[0].side == "H"


def test_a_known_column_that_moved_stops_the_read_and_is_named():
    header = '-- [quest] = "title|level|min level|objective text|starts|ends|a new one|saw|new"\n'
    with pytest.raises(ValueError, match="column 7 is 'a new one', the reader expects 'saw'"):
        fdb.parse_quests(quests_file(header, "T|3|1|do a|n5|n6|x|2|1"))
    with pytest.raises(ValueError, match="has 3 columns"):
        fdb.parse_quests(quests_file('-- [quest] = "title|level|min level"\n', "T|3|1"))


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


def test_dungeons():
    rows = {r.id: r for r in fdb.parse_dungeons(text("Dungeons.lua"))}
    assert sorted(rows) == [34, 36, 249]
    deadmines = rows[36]
    assert (deadmines.name, deadmines.kind, deadmines.size) == ("The Deadmines", "dungeon", 5)
    assert (deadmines.level_lo, deadmines.level_hi, deadmines.level_req) == (15, 25, 10)
    assert deadmines.zone_name == "Elwynn Forest"
    assert deadmines.bosses[0] == fdb.DungeonBoss(1, 1144, "Rhahk'Zor")
    assert [b.number for b in deadmines.bosses] == [1144, 1145, 448]  # encounter ids
    assert deadmines.loot[0] == fdb.DungeonLoot(872, 1, "s")
    assert deadmines.loot[-1] == fdb.DungeonLoot(5187, 0, "c")  # the instance's unassigned loot
    assert deadmines.quests == (6, 166)
    onyxia = rows[249]
    assert onyxia.kind == "raid" and onyxia.size == 40 and onyxia.quests == ()
    assert onyxia.loot == (fdb.DungeonLoot(16914, 1, "c"),)
    assert rows[34].loot == () and rows[34].quests == ()


def test_dungeons_file_helper(tmp_path):
    path = tmp_path / "Dungeons.lua"
    path.write_text('local _, ns = ...\nns.dungeons = {[1]={n="A",kind="dungeon"}}', "utf-8")
    rows = fdb.read_dungeons(path)
    assert rows[0].id == 1 and rows[0].size is None and rows[0].level_lo is None
    assert rows[0].bosses == () and rows[0].loot == () and rows[0].zone_name is None


def test_boss_creatures():
    """Loot.lua names the bosses' creatures per instance, and the instances only Forever has."""
    b = fdb.parse_boss_creatures(text("Loot.lua"))
    assert b.npcs[36] == {"rhahk'zor": 644, "edwin vancleef": 639}  # Mr. Smite: none
    assert b.npcs[249] == {"onyxia": 10184}
    assert b.forever == frozenset({2999})


def test_dungeon_maps():
    rows = {r.id: r for r in fdb.parse_dungeon_maps(text("DungeonMaps.lua"))}
    assert sorted(rows) == [36, 249]
    deadmines = rows[36]
    assert len(deadmines.floors) == 1 and deadmines.floors[0].name == "Map"
    assert (deadmines.floors[0].width, deadmines.floors[0].height) == (1125, 725)
    assert deadmines.floors[0].tiles[0] == fdb.FloorTile(205041, -672, -1025, 1067, 1068, 0)
    assert deadmines.floors[0].tiles[1].q == 2
    assert deadmines.boss_spots == ((1, 1, 20.86, 58.69), (3, 1, 34.89, 48.04))
    # the floor's place in the world: a spot in percent becomes a world point (DG2c)
    floor = deadmines.floors[0]
    assert (floor.scale, floor.x0, floor.y0, floor.z_lo, floor.z_hi) == (
        2.0,
        21.09,
        -335.85,
        6.4,
        87.4,
    )
    wx, wy = floor.world_point(20.86, 58.69)
    assert (round(wx, 1), round(wy, 1), round(floor.z_mid, 1)) == (-191.7, -453.2, 46.9)
    assert rows[249].floors[0].world_point(50, 50) == (0 - 75.0, 0 - 100.0)
    assert deadmines.door == (1, 85.72, 65.22) and deadmines.why is None
    ony = rows[249]
    assert [len(f.tiles) for f in ony.floors] == [0, 1]  # the first floor: no readable file
    assert ony.door is None and ony.why.startswith("The client's file")


def test_the_tables_of_what_players_saw():
    text = """
    local _, ns = ...
    ns.qfSeen = { [92461] = { s = "15p6t2r", e = "15p6t2r", o = { [1] = "15p7d5s 15p7g83" } } }
    ns.qfNpcNames = { [251361] = "Name" }
    """
    seen = fdb.parse_quest_seen(text)[92461]
    assert seen.starts == seen.ends
    assert seen.starts[0].ui_map_id == 2521
    assert 0 <= seen.starts[0].x_pct <= 100 and 0 <= seen.starts[0].y_pct <= 100
    assert len(seen.objectives[1]) == 2
    assert fdb.parse_npc_names(text) == {251361: "Name"}


def test_stock_turns_round_to_the_seller_and_zero_is_unknown():
    text = """
    local _, ns = ...
    ns.sold = { [2488] = { 54, 536, 1, 0, 66, 0, 5, 1 } }
    ns.classTrainers = { WARRIOR = { 4087 } }
    ns.profTrainers = { Alchemy = { 2837, 257019 } }
    """
    sold = fdb.parse_sold(text)
    assert sold[54] == [fdb.SoldRow(2488, 536, 1, False)]
    assert sold[66] == [fdb.SoldRow(2488, None, 5, True)]
    assert fdb.parse_trainers(text) == {4087, 2837, 257019}


def test_the_guide_takes_only_what_it_marks_as_forever():
    text = """
    local _, ns = ...
    ns.qgQuests = {
      [1] = "3|4|5|ff|15|f|80:2|7:2|8 9|f||",
      [2] = "3|4|5|cc|15|c|80:2|7|8|c||",
      [3] = "3|4|5|ff|-5|f|80:2|||f||",
    }
    """
    guide = fdb.parse_quest_guide(text)
    assert guide == {1: fdb.GuideRewards(1, 15, ((7, 2),), ((8, 1), (9, 1)))}


def test_measured_quest_xp():
    text = "local _, ns = ...\nns.qxp = { q = { [2] = 2450, [6] = 340 } }\n"
    assert fdb.parse_quest_xp(text) == {2: 2450, 6: 340}


def test_an_older_file_without_the_tables_reads_as_empty():
    text = "local _, ns = ...\n"
    assert fdb.parse_quest_seen(text) == {}
    assert fdb.parse_sold(text) == {}
    assert fdb.parse_trainers(text) == frozenset()
