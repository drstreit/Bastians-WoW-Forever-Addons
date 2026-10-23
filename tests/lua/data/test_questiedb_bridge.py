"""Data.QuestieDB (B3.6): QuestieDB as a second provider for spawns and names, never required."""

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"


def boot(wow: WowRuntime, *extra: str) -> WowRuntime:
    wow.start(CORE, *extra, DATA, QUESTS)
    wow.run_frames(10)
    return wow


def test_without_questiedb_the_bridge_is_inactive_and_quiet(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:GetModule('Data.QuestieDB').status") == "missing"
    assert wow.eval("Bastians:Entity('npc:9999'):Name()") is None
    assert len(wow.eval("Bastians:Entity('npc:448'):Locations()")) == 2  # our data only
    assert wow.errors == []
    assert not [line for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"]


def test_with_questiedb_spawns_and_names_fill_the_gaps(wow: WowRuntime):
    boot(wow, "QuestieDB")
    assert wow.eval("Bastians:GetModule('Data.QuestieDB').status") == "ok"
    assert wow.eval("Bastians:Entity('npc:448'):Name()") == "Hogger"  # our data wins (priority 100)
    points = list(wow.eval("Bastians:Entity('npc:448'):Locations()").values())
    srcs = [p.src for p in points]
    assert (
        srcs.count("questie") == 3 and "eq" in srcs
    )  # 1 from the pack, 2 from the bridge; area 999 skipped
    bridge_points = {(p.map, round(p.x, 3), round(p.y, 3)) for p in points if p.src == "questie"}
    assert {(1429, 0.271, 0.859), (1429, 0.298, 0.802)} <= bridge_points  # percent -> fractions
    assert wow.eval("Bastians:Entity('npc:9999'):Name()") == "Questie Only Guy"
    guy = list(wow.eval("Bastians:Entity('npc:9999'):Locations()").values())
    assert [(p.map, p.src) for p in guy] == [(1429, "questie")]  # Goldshire area 87 -> 1429
    assert wow.eval("Bastians:Entity('object:1734'):Name()") == "Wanted Poster"
    assert wow.eval("Bastians:Entity('item:7777'):Name()") == "Questie Only Item"
    assert wow.errors == []


def test_contract_mismatch_keeps_the_bridge_off(wow: WowRuntime):
    wow.execute("QuestieDB_FixtureContract = 3")
    boot(wow, "QuestieDB")
    assert wow.eval("Bastians:GetModule('Data.QuestieDB').status") == "contract"
    assert wow.eval("Bastians:Entity('npc:9999'):Name()") is None
    assert wow.errors == []


def test_disabling_the_bridge_removes_its_providers(wow: WowRuntime):
    boot(wow, "QuestieDB")
    wow.execute("Bastians:GetModule('Data.QuestieDB'):Disable()")
    assert wow.eval("Bastians:Entity('npc:9999'):Name()") is None
    assert len(wow.eval("Bastians:Entity('npc:448'):Locations()")) == 2
