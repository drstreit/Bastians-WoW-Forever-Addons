"""Retail objective spots at runtime (D2, ADR 0014): where the pack has no spots for a log quest,
the client's next waypoint feeds "My quests here" and the log view's step, and the client's quest
POIs of the player's map feed the `quests.objectives` layer. Through Compat wrappers, nil and
empty when the client has nothing; the pack's spots win where they exist."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
ELWYNN_VIEW = "{ continent = 0, x1 = -300, y1 = -300, x2 = 300, y2 = 300, level = 5 }"
RETAIL_QUEST = """
Mock.questLog[#Mock.questLog + 1] = { questID = 99999, title = "A Song for Our Future", level = 10,
  complete = false, objectives = { { text = "Sing", type = "event", finished = false, numFulfilled = 0, numRequired = 1 } } }
"""


def find_row(rows, qid: int):
    """The row of a quest anywhere under the view's roots (a quest without a place sits under
    "Elsewhere > Unknown place")."""
    for row in rows.values():
        if row.qid == qid:
            return row
        if row.children:
            found = find_row(row.children, qid)
            if found is not None:
                return found
    return None


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute(RETAIL_QUEST)
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def test_the_compat_wrappers_are_quiet_without_client_data(core: WowRuntime):
    assert core.eval("Bastians.Compat.GetQuestWaypoint(99999, 1429)") is None
    assert core.eval("#Bastians.Compat.GetQuestsOnMap(1429)") == 0
    core.execute("Mock.waypoints[99999] = { map = 1429, x = 0.3, y = 0.4 }")
    assert core.eval("Bastians.Compat.GetQuestWaypoint(99999, 1429)") == (0.3, 0.4)
    assert core.eval("Bastians.Compat.GetQuestWaypoint(99999, 1436)") is None  # another map
    pois = core.eval("Bastians.Compat.GetQuestsOnMap(1429)")
    assert [(p.questID, p.x, p.y) for p in pois.values()] == [(99999, 0.3, 0.4)]
    assert core.eval("Bastians.Compat.CONTRACT.GetQuestWaypoint ~= nil") is True


def test_a_log_quest_without_pack_spots_takes_the_clients_step(wow: WowRuntime):
    boot(wow)
    MOD = "Bastians:GetModule('Quests')"
    # without a waypoint the step is unknown: no place, no pin, the row says so in the log view
    rows = wow.eval(f"({MOD}.Views.active(1429, 0.42, 0.65, {{}}))")
    song = find_row(rows, 99999)
    assert song is not None
    assert song.map is None and song.target == "objective"
    pins = wow.eval(f"Bastians:QueryLayer('quests.objectives', {ELWYNN_VIEW})")
    assert not any(p.ref == "quest:99999" for p in pins.values())
    # the client knows the next step: the row has it, the layer draws it
    wow.execute("Mock.waypoints[99999] = { map = 1429, x = 0.3, y = 0.4 }")
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    rows = wow.eval(f"({MOD}.Views.active(1429, 0.42, 0.65, {{}}))")
    song = find_row(rows, 99999)
    assert song is not None
    assert (song.map, song.x, song.y, song.src) == (1429, 0.3, 0.4, "client")
    pins = wow.eval(f"Bastians:QueryLayer('quests.objectives', {ELWYNN_VIEW})")
    mine = [p for p in pins.values() if p.ref == "quest:99999"]
    assert len(mine) == 1 and mine[0].label == "A Song for Our Future"
    assert (round(mine[0].wx), round(mine[0].wy)) == (40, 80)  # 200 - 400*0.4, 200 - 400*0.3
    # the pack's spots win where they exist: the fixture quest keeps its own
    assert wow.eval("Bastians.Compat.GetQuestWaypoint(176, 1429)") is None
    assert any(p.ref == "quest:176" for p in pins.values())
    assert wow.errors == []


def test_the_here_column_lists_the_clients_step_with_its_distance(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    wow.execute(
        "Mock.waypoints[99999] = { map = 1429, x = 0.42, y = 0.65 }"
    )  # where the player stands
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.slash("/bq")
    rows = wow.eval("Bastians:GetDetailSections('zone:1429')")
    log = next(s for s in rows.values() if s.id == "quests.here.log")
    texts = [strip(r.text) for r in log.rows.values()]
    assert any(t.startswith("A Song for Our Future") and t.endswith("0 yd") for t in texts)
    assert wow.errors == []


def test_the_quest_text_block_falls_back_to_the_client_then_says_so(wow: WowRuntime):
    """the quest text must show; retail has no texts in the pack, so a log
    quest shows the client's own text and any other quest a note (the Text pack and Spoken carry
    it on Forever)."""
    wow.execute(RETAIL_QUEST)
    wow.execute(
        'Mock.questLog[#Mock.questLog].details = "Sing it loud."; '
        'Mock.questLog[#Mock.questLog].objectivesText = "Find the choir."'
    )
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    wow.advance(0.3)
    sections = {s.id: s for s in wow.eval("Bastians:GetDetailSections('quest:99999')").values()}
    texts = [strip(r.text) for r in sections["quests.text"].rows.values()]
    assert texts == ["Sing it loud.", "Find the choir."]  # the client's text, pack loaded or not
    wow.execute("Bastians:GetService('data'):LoadPack('text')")
    wow.run_frames(5)
    sections = {s.id: s for s in wow.eval("Bastians:GetDetailSections('quest:176')").values()}
    assert len(list(sections["quests.text"].rows.values())) == 3  # the pack's text wins
    wow.execute("table.remove(Mock.questLog)")
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.execute("Bastians:Fire('BASTIANS_DATA_LOADED', 'text')")  # drops the section cache
    sections = {s.id: s for s in wow.eval("Bastians:GetDetailSections('quest:99999')").values()}
    texts = [strip(r.text) for r in sections["quests.text"].rows.values()]
    assert texts[0].startswith("No quest text in the data for this client")
    assert wow.errors == []
