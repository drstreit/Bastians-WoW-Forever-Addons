"""Quest state (B5.2): cached log, diff on quest events, completed set, `progress` service, flight paths."""

import time

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"

WATCHER = """
messages = {}
local w = Bastians:NewModule("QuestWatcher", { addon = "Bastians_Quests" })
w:On("BASTIANS_QUESTS_CHANGED", function(_, _, ids, diff)
  messages[#messages + 1] = { ids = ids, diff = diff }
end)
"""

COUNT_COMPLETED_CALLS = """
asked = 0
local real = C_QuestLog.GetAllCompletedQuestIDs
C_QuestLog.GetAllCompletedQuestIDs = function(...) asked = asked + 1 return real(...) end
"""

TWENTY_QUESTS = """
Mock.questLog = { { header = "Elwynn Forest" } }
for i = 1, 20 do
  local objectives = {}
  for j = 1, 3 do
    objectives[j] = { text = "Objective " .. j, type = "monster", finished = false, numFulfilled = 0, numRequired = 8 }
  end
  Mock.questLog[#Mock.questLog + 1] =
    { questID = 1000 + i, title = "Quest " .. i, level = 10, complete = false, objectives = objectives }
end
"""

STATUS = (
    "Bastians:GetModule('Quests').Logic.status(%d, Bastians:GetModule('Quests').State.ForLogic())"
)


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.execute(WATCHER)
    return wow


def state(wow: WowRuntime, expr: str):
    return wow.eval(f"Bastians:GetModule('Quests').State.{expr}")


def progress(wow: WowRuntime, expr: str):
    return wow.eval(f"Bastians:GetService('progress'):{expr}")


def messages(wow: WowRuntime) -> list:
    return list(wow.g.messages.values())


def ids(lua_table) -> list:
    return list(lua_table.values())


def settle(wow: WowRuntime) -> None:
    """Let the coalesced refresh run."""
    wow.advance(0.1)


def toggle_objective(wow: WowRuntime) -> None:
    wow.execute(
        "Mock.questLog[2].objectives[1].numFulfilled = (Mock.questLog[2].objectives[1].numFulfilled + 1) % 2"
    )


def assert_clean(wow: WowRuntime) -> None:
    assert wow.errors == []
    assert not [
        line.text
        for line in wow.eval("Bastians:GetLog()").values()
        if line.level == "error" and "registered no data" not in line.text
    ]


def test_login_snapshot_and_progress_service(wow: WowRuntime):
    boot(wow)
    assert state(wow, "count") == 2
    assert ids(state(wow, "order")) == [176, 62]
    entry = state(wow, "Entry(176)")
    assert (entry.title, entry.header, entry.index) == ("The Fargodeep Mine", "Elwynn Forest", 2)
    assert state(wow, "doneLoaded") is True
    facts = state(wow, "facts")
    assert (facts.level, facts.raceID, facts.classID, facts.faction) == (12, 1, 8, "Alliance")
    assert progress(wow, "IsQuestDone(783)") is True
    assert progress(wow, "IsQuestDone(176)") is False
    assert progress(wow, "IsInLog(176)") is True
    assert progress(wow, "IsInLog(999)") is False
    assert messages(wow) == []  # the first snapshot has nothing to diff against
    assert_clean(wow)


def test_objective_update_diffs_only_that_quest(wow: WowRuntime):
    boot(wow)
    wow.execute("before62 = Bastians:GetModule('Quests').State.Entry(62)")
    wow.execute("Mock.questLog[2].objectives[1].numFulfilled = 1")
    for _ in range(3):  # the client fires the event in bursts
        wow.fire("QUEST_LOG_UPDATE")
    assert messages(wow) == []  # nothing until the burst settles
    settle(wow)
    msgs = messages(wow)
    assert len(msgs) == 1
    assert ids(msgs[0].ids) == [176]
    diff = msgs[0].diff
    assert (ids(diff.added), ids(diff.removed), ids(diff.changed)) == ([], [], [176])
    assert state(wow, "Entry(176).objectives[1].fulfilled") == 1
    assert wow.eval("before62 == Bastians:GetModule('Quests').State.Entry(62)") is True
    wow.fire("QUEST_LOG_UPDATE")  # no change: no message
    settle(wow)
    assert len(messages(wow)) == 1
    assert_clean(wow)


def test_turn_in_accept_and_live_logic_state(wow: WowRuntime):
    boot(wow)
    assert wow.eval(STATUS % 62) == "log"
    assert wow.eval(STATUS % 76)[0] == "prereq"  # 62 is in the log, not done
    wow.execute("table.remove(Mock.questLog, 3)")  # 62 leaves the log
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    assert progress(wow, "IsQuestDone(62)") is True
    assert progress(wow, "IsInLog(62)") is False
    msgs = messages(wow)
    assert len(msgs) == 1 and ids(msgs[0].diff.removed) == [62]
    assert wow.eval(STATUS % 62) == "done"
    assert wow.eval(STATUS % 76) == "available"
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = "
        "{ questID = 76, title = 'The Jasperlode Mine', level = 9, complete = false, objectives = {} }"
    )
    wow.fire("QUEST_ACCEPTED", 76)
    settle(wow)
    msgs = messages(wow)
    assert len(msgs) == 2 and ids(msgs[1].diff.added) == [76] and ids(msgs[1].ids) == [76]
    assert ids(state(wow, "order")) == [176, 76]
    assert wow.eval(STATUS % 76) == "log"
    assert_clean(wow)


def test_level_up_marks_everything_changed(wow: WowRuntime):
    boot(wow)
    wow.fire("PLAYER_LEVEL_UP", 13, 20, 0, 0, 0, 0, 0, 0, 0)
    msgs = messages(wow)
    assert len(msgs) == 1 and msgs[0].ids is None and msgs[0].diff.level == 13
    assert state(wow, "facts.level") == 13
    assert state(wow, "ForLogic().level") == 13
    assert_clean(wow)


def test_completed_list_delivered_late_is_retried(wow: WowRuntime):
    wow.execute("Mock.completedQuests = {}")
    wow.execute(COUNT_COMPLETED_CALLS)
    boot(wow)
    assert state(wow, "doneLoaded") is False
    assert progress(wow, "IsQuestDone(7)") is False
    wow.execute("Mock.completedQuests = { 7 }")
    wow.fire("PLAYER_ENTERING_WORLD", False, True)
    settle(wow)
    assert progress(wow, "IsQuestDone(7)") is True
    assert state(wow, "doneLoaded") is True
    asked = wow.g.asked
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    assert wow.g.asked == asked  # loaded: not asked again


def test_empty_completed_list_is_asked_at_most_three_times(wow: WowRuntime):
    wow.execute("Mock.completedQuests = {}")
    wow.execute(COUNT_COMPLETED_CALLS)
    boot(wow)
    for _ in range(6):
        toggle_objective(wow)
        wow.fire("QUEST_LOG_UPDATE")
        settle(wow)
    assert wow.g.asked == 3
    assert state(wow, "doneLoaded") is False


def test_flight_paths_are_learned_and_persisted(wow: WowRuntime):
    boot(wow)
    assert dict(progress(wow, "KnownFlightPaths()").items()) == {}
    wow.fire("TAXIMAP_OPENED", 1)
    known = progress(wow, "KnownFlightPaths()")
    assert sorted(known.keys()) == [2, 4]  # current and reachable; the unreachable one is not known
    assert (known[2].name, known[2].map, known[2].x, known[2].y) == (
        "Stormwind, Elwynn",
        1415,
        0.66,
        0.47,
    )
    assert wow.eval("Bastians.Compat.Report().GetTaxiNodes.note") == "C_TaxiMap.GetAllTaxiNodes"
    fresh = wow.reload()
    fresh.run_frames(10)
    assert sorted(fresh.eval("Bastians:GetService('progress'):KnownFlightPaths()").keys()) == [2, 4]
    assert_clean(fresh)


def test_flight_paths_legacy_fallback_keys_by_name(wow: WowRuntime):
    boot(wow)
    wow.execute("C_TaxiMap.GetAllTaxiNodes = function() return {} end")
    wow.fire("TAXIMAP_OPENED", 1)
    known = progress(wow, "KnownFlightPaths()")
    assert sorted(known.keys()) == ["Sentinel Hill, Westfall", "Stormwind, Elwynn"]
    assert wow.eval("Bastians.Compat.Report().GetTaxiNodes.note") == "NumTaxiNodes"
    assert_clean(wow)


def test_service_absent_without_quests_and_while_disabled(wow: WowRuntime):
    wow.start(CORE, DATA)
    assert wow.eval("Bastians:GetService('progress')") is None
    wow.load_addon(QUESTS)
    wow.run_frames(10)
    assert wow.eval("Bastians:GetService('progress')") is not None
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    assert wow.eval("Bastians:GetService('progress')") is None
    wow.execute("Mock.questLog[2].objectives[1].numFulfilled = 1")
    wow.fire("QUEST_LOG_UPDATE")  # ignored while disabled
    wow.advance(0.1)
    assert state(wow, "Entry(176).objectives[1].fulfilled") == 0
    wow.execute("Bastians:GetModule('Quests'):Enable()")
    assert wow.eval("Bastians:GetService('progress'):IsInLog(176)") is True
    assert state(wow, "Entry(176).objectives[1].fulfilled") == 1  # re-enable takes a fresh snapshot
    assert_clean(wow)


def test_twenty_quests_refresh_under_two_ms(wow: WowRuntime):
    boot(wow)
    wow.execute(TWENTY_QUESTS)
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    assert state(wow, "count") == 20
    refresh = wow.eval("Bastians:GetModule('Quests').State.Refresh")
    best = float("inf")
    for i in range(5):
        wow.execute(f"Mock.questLog[11].objectives[2].numFulfilled = {i + 1}")
        start = time.perf_counter()
        diff = refresh()
        elapsed = time.perf_counter() - start
        best = min(best, elapsed)
        assert ids(diff.changed) == [1010] and ids(diff.added) == [] and ids(diff.removed) == []
    assert best < 0.002, f"refresh took {best * 1000:.2f} ms"
