"""Dungeons (data.md "Dungeons"): the fixture World pack's Deadmines is an entity found by the search,
its page lists the bosses and the loot, its place is its door, a boss and a dungeon quest link back,
and Quests lists the dungeon's quests under the status headers."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"


def boot(wow: WowRuntime, *extra: str) -> WowRuntime:
    wow.start(CORE, DATA, *extra)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.execute('Bastians:GetService("data"):LoadPack("quests")')
    wow.execute('Bastians:GetService("data"):LoadPack("items")')
    wow.run_frames(5)
    return wow


def strip(text: str) -> str:
    return re.sub(r"\|T[^|]*\|t ?", "", text)


def search(wow: WowRuntime, text: str) -> list:
    wow.execute(
        f"_G.got = nil local q, types = Bastians.ParseSearch('{text}') "
        "Bastians:Search(q, { limit = 10, types = types }, function(r, done) "
        "if done then _G.got = r end end)"
    )
    wow.run_frames(10)
    return list(wow.eval("got").values())


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def test_the_dungeon_is_an_entity_the_search_finds(wow: WowRuntime):
    boot(wow)
    hits = [r for r in search(wow, "deadmines") if r.ref == "dungeon:36"]
    assert hits and hits[0].label == "The Deadmines"
    # "dungeon" and "raid" before or after the words keep the dungeons only
    assert [r.ref for r in search(wow, "dungeon dead")] == ["dungeon:36"]
    assert [r.ref for r in search(wow, "dead raid")] == ["dungeon:36"]
    assert wow.eval("Bastians:Entity('dungeon:36'):Name()") == "The Deadmines"
    assert (
        wow.eval("Bastians:Entity('dungeon:36'):Summary()")
        == "Dungeon, Level 15-25, 5 players, Westfall"
    )
    assert wow.errors == []


def test_the_dungeon_page_lists_bosses_in_order_and_the_loot_by_boss(wow: WowRuntime):
    boot(wow)
    page = sections(wow, "dungeon:36")
    bosses = list(page["data.bosses"].rows.values())
    assert [(r.ref, strip(r.text), r.value) for r in bosses] == [
        ("npc:644", "Rhahk'Zor", 1),
        ("npc:639", "Edwin VanCleef", 2),
    ]
    loot = list(page["data.dungeonloot"].rows.values())
    assert [(r.ref, strip(r.text), r.note) for r in loot] == [
        ("item:1185", "Blood Saber", "Rhahk'Zor"),
        ("item:2589", "Linen Cloth", None),  # the instance's loot without a boss named
    ]
    # Quests' section: the dungeon's quests, by status, with the game's status words
    assert "quests.dungeon" not in page  # Quests is not loaded here
    assert wow.errors == []


def test_the_dungeon_stands_at_its_door_and_the_door_the_boss_and_the_quest_link_back(
    wow: WowRuntime,
):
    boot(wow)
    places = list(wow.eval("Bastians:Entity('dungeon:36'):Locations()").values())
    door = list(wow.eval("Bastians:Entity('entrance:36-1'):Locations()").values())
    assert places and [(p.map, p.x, p.y) for p in places] == [(p.map, p.x, p.y) for p in door]
    for ref in ("npc:644", "entrance:36-1", "quest:62"):
        rows = list(sections(wow, ref)["data.dungeon"].rows.values())
        assert [(r.ref, strip(r.text)) for r in rows] == [("dungeon:36", "The Deadmines")], ref
    # an NPC outside any dungeon has no such section
    assert "data.dungeon" not in sections(wow, "npc:448")
    # a boss's loot seen in Forever has no chance: the note stays empty, never "0%"
    boss_loot = list(sections(wow, "npc:644")["data.loot"].rows.values())
    assert [(r.ref, r.note, r.chance) for r in boss_loot] == [("item:1185", None, None)]
    assert wow.errors == []


def test_quests_lists_the_dungeons_quests(wow: WowRuntime):
    boot(wow, QUESTS)
    rows = list(sections(wow, "dungeon:36")["quests.dungeon"].rows.values())
    # grouped: a status header row with the quests it holds as its children
    assert [r.kind for r in rows] == ["section"]
    assert [c.ref for c in rows[0].children.values()] == ["quest:62"]
    assert wow.errors == []
