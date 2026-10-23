"""The tracker features of the log view (owner round 1, retail, 22.10.2026; what Questie's tracker
had and slim mode lacked): objective progress in colour, "Hide done" and "Tracked" toggles on the
toolbar and in the hub (the Here column's "My quests here" honours them), auto-track on accept,
and the zone groups that fold and stay folded."""

import re

from harness import WowRuntime
from pages import block_controls, block_rows

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Quests')"
WIN = f"{MOD}.Window"
ROWS = f"{MOD}.Rows"
BMOD = "Bastians:GetModule('Browser')"
SIZE = f"{WIN}.tree.scroll:SetSize(500, 400); {WIN}.tree:Refresh()"
JASPERLODE = (
    "Mock.questLog[#Mock.questLog + 1] = { questID = 76, title = 'The Jasperlode Mine', level = 9, "
    "complete = false, objectives = {} }"
)
NOWHERE = (
    "Mock.questLog[#Mock.questLog + 1] = { questID = 99999, title = 'A Song for Our Future', "
    "level = 10, complete = false, objectives = {} }"
)


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def open_log(wow: WowRuntime) -> None:
    wow.slash("/bq log")
    wow.execute(SIZE)
    wow.run_frames(5)


def settle(wow: WowRuntime) -> None:
    wow.advance(0.3)
    wow.run_frames(5)


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def raw(wow: WowRuntime) -> list[str]:
    return [r.text for r in wow.eval(f"{WIN}.tree.flat").values()]


def flat(wow: WowRuntime) -> list[str]:
    return [strip(t) for t in raw(wow)]


def summary(wow: WowRuntime) -> str:
    return strip(wow.eval(f"{WIN}.summary:GetText()"))


def watched(wow: WowRuntime) -> list[int]:
    return list(wow.eval("Mock.watched").values())


def test_progress_colour_runs_from_red_to_green(core: WowRuntime):
    core.start(CORE, DATA, QUESTS)
    core.run_frames(5)
    colour = f"{ROWS}.progressColor"
    assert core.eval(f"{colour}(0, 4)") == "|cffff4040"
    assert core.eval(f"{colour}(1, 4)") == "|cffff9020"
    assert core.eval(f"{colour}(2, 4)") == "|cffffe000"
    assert core.eval(f"{colour}(3, 4)") == "|cffbfd800"
    assert core.eval(f"{colour}(4, 4)") == "|cff40c040"  # done: the green of the rows
    assert core.eval(f"{colour}(0.5)") == "|cffffe000"  # a fraction alone
    assert core.eval(f"{colour}(nil, nil)") == "|cffffffff"  # unknown: white, never a guess
    assert core.eval(f"{colour}(0, 0)") == "|cffffffff"


def test_objective_rows_and_the_quest_row_carry_the_progress_colour(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.questLog[2].objectives = {"
        " { text = 'Kobolds slain', type = 'monster', finished = false, numFulfilled = 2, numRequired = 4 },"
        " { text = 'Candles taken', type = 'item', finished = true, numFulfilled = 3, numRequired = 3 },"
        " { text = 'Explore the mine', type = 'event', finished = false } }"
    )
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    open_log(wow)
    texts = raw(wow)
    quest = next(t for t in texts if "[11] The Fargodeep Mine" in strip(t))
    assert "|cffffaa151/3|r" in quest  # one of three objectives done: orange-red
    kobolds = next(t for t in texts if "Kobolds slain" in t)
    assert kobolds.count("|cffffe000") == 2  # the words and the count, half way: yellow
    candles = next(t for t in texts if "Candles taken" in t)
    assert "|cff40c040Candles taken|r" in candles and "|cff40c0403/3|r" in candles
    explore = next(t for t in texts if "Explore the mine" in t)
    assert explore == "|cffffffffExplore the mine|r"  # no count: white, no progress fragment
    assert wow.errors == []


def test_hide_done_hides_the_complete_quests_on_the_toolbar_and_in_the_hub(wow: WowRuntime):
    boot(wow)
    open_log(wow)
    assert flat(wow)[0] == "HAND IN HERE  1"
    assert wow.eval(f"{MOD}.db.profile.logHideDone") is False
    wow.execute(f"{WIN}.bar.byId.logHideDone:Click()")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.db.profile.logHideDone") is True
    assert "HAND IN HERE  1" not in flat(wow) and "OBJECTIVES HERE  1" in flat(wow)
    assert summary(wow) == "2 in the log - 0 to hand in - 1 objectives here - 1 hidden"
    # the hub's toggle is the same flag: the window follows a setting change
    wow.execute(f"{MOD}.db.profile.logHideDone = false")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Quests', 'logHideDone', false)")
    settle(wow)
    assert flat(wow)[0] == "HAND IN HERE  1"
    # everything complete and hidden: the view says why instead of showing nothing
    wow.execute("Mock.questLog[2].complete = true")
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    wow.execute(f"{WIN}.bar.byId.logHideDone:Click()")
    wow.run_frames(5)
    assert flat(wow) == ["Every quest in the log is complete and hidden: switch Hide done off."]
    assert wow.errors == []


def test_tracked_only_follows_the_objective_tracker(wow: WowRuntime):
    boot(wow)
    open_log(wow)
    wow.execute(f"{WIN}.bar.byId.logTrackedOnly:Click()")
    wow.run_frames(5)
    assert wow.eval(f"{MOD}.db.profile.logTrackedOnly") is True
    assert flat(wow) == ["No tracked quest: track one from its row, or switch Tracked off."]
    assert summary(wow).endswith("2 hidden")
    # a Track action re-renders the view through BASTIANS_TRACKED_CHANGED
    wow.execute("Bastians:RunAction('quests.track', 'quest:176', { source = 'test' })")
    settle(wow)
    assert flat(wow)[0] == "OBJECTIVES HERE  1" and "HAND IN HERE  1" not in flat(wow)
    assert summary(wow).endswith("1 hidden")
    wow.execute("Bastians:RunAction('quests.untrack', 'quest:176', { source = 'test' })")
    settle(wow)
    assert flat(wow) == ["No tracked quest: track one from its row, or switch Tracked off."]
    wow.execute(f"{WIN}.bar.byId.logTrackedOnly:Click()")
    wow.run_frames(5)
    assert flat(wow)[0] == "HAND IN HERE  1"
    assert wow.errors == []


def test_the_here_column_honours_the_tracker_filters(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    HD = f"{BMOD}.hereDossier"
    wow.slash("/bb npc:240")
    wow.run_frames(5)
    assert len(block_rows(wow, HD, "My quests here  2")) == 2
    wow.execute(f"{MOD}.db.profile.logHideDone = true")
    wow.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Quests', 'logHideDone', true)")
    settle(wow)
    rows = block_rows(wow, HD, "My quests here  1")
    assert len(rows) == 1 and "Fargodeep Mine II" not in rows[0]
    # the toggles sit on the tracker's toolbar in the Browser too (slim mode)
    wow.execute(f"{BMOD}.Browser.SetSlim(true)")
    wow.run_frames(5)
    assert wow.eval(f"{BMOD}.controlBar.byId.logHideDone:IsShown()") is True
    assert wow.eval(f"{BMOD}.controlBar.byId.logTrackedOnly:IsShown()") is True
    assert wow.errors == []


def test_an_accepted_quest_is_tracked_at_once_unless_the_setting_is_off(wow: WowRuntime):
    boot(wow)
    assert watched(wow) == []
    wow.execute(JASPERLODE)
    wow.fire("QUEST_ACCEPTED", 76)
    settle(wow)
    assert watched(wow) == [76]
    assert wow.eval(f"{MOD}.State.IsTracked(76)") is True
    # the log arriving late at login is not tracked wholesale
    wow.execute(NOWHERE)
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    assert watched(wow) == [76]
    # the event before the log has the quest (retail may order it so): tracked once it shows up
    wow.execute("table.remove(Mock.questLog)")
    wow.fire("QUEST_REMOVED", 99999)
    settle(wow)
    wow.fire("QUEST_ACCEPTED", 99999)
    settle(wow)
    assert watched(wow) == [76]
    wow.execute(NOWHERE)
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    assert watched(wow) == [76, 99999]
    # the Classic argument shape (questLogIndex, questID) and an event without an id
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 77, title = 'Gold Dust Exchange', level = 7, "
        "complete = false, objectives = {} }"
    )
    wow.fire("QUEST_ACCEPTED", 5, 77)
    settle(wow)
    assert watched(wow) == [76, 99999, 77]
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 78, title = 'Kobold Candles', level = 7, "
        "complete = false, objectives = {} }"
    )
    wow.fire("QUEST_ACCEPTED")
    settle(wow)
    assert watched(wow) == [76, 99999, 77, 78]
    # the setting off: nothing is tracked
    wow.execute(f"{MOD}.db.profile.autoTrack = false")
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 79, title = 'A Fishy Peril', level = 9, "
        "complete = false, objectives = {} }"
    )
    wow.fire("QUEST_ACCEPTED", 79)
    settle(wow)
    assert watched(wow) == [76, 99999, 77, 78]
    assert wow.errors == []


def test_zone_groups_fold_and_stay_folded(wow: WowRuntime):
    boot(wow)
    wow.execute(NOWHERE)  # no data, no place: "Elsewhere > Unknown place"
    wow.fire("QUEST_ACCEPTED", 99999)
    settle(wow)
    open_log(wow)
    texts = flat(wow)
    i = texts.index("ELSEWHERE  1")
    assert texts[i + 1] == "Unknown place  1" and "A Song for Our Future" in texts[i + 2]
    wow.execute(
        f"for _, r in ipairs({WIN}.tree.flat) do if r.id == 'az:0' then {WIN}.tree:ToggleFold(r) end end"
    )
    texts = flat(wow)
    assert "Unknown place  1" in texts and not any("A Song for Our Future" in t for t in texts)
    assert wow.eval(f"{MOD}.db.profile.tree.collapsed['az:0']") is True
    # a re-render (a quest event) keeps the fold; the section folds the same way
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    wow.execute(f"{WIN}.Render()")
    texts = flat(wow)
    assert "Unknown place  1" in texts and not any("A Song for Our Future" in t for t in texts)
    wow.execute(
        f"for _, r in ipairs({WIN}.tree.flat) do if r.id == 's:a_elsewhere' then {WIN}.tree:ToggleFold(r) end end"
    )
    assert "Unknown place  1" not in flat(wow) and "ELSEWHERE  1" in flat(wow)
    assert wow.errors == []


def test_the_here_block_carries_the_log_toggles(wow: WowRuntime):
    """Hide done and Tracked sit on the "My quests here" title line,
    the same flags as the log view and the hub; the dossier prints the count, the title not."""
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    HD = f"{BMOD}.hereDossier"
    wow.slash("/bb npc:240")
    wow.run_frames(5)
    assert block_controls(wow, HD, "My quests here  2") == [
        ("Hide done", False),
        ("Tracked", False),
    ]
    assert len(block_rows(wow, HD, "My quests here  2")) == 2
    wow.execute(
        f"for _, bf in ipairs({HD}.blockPool) do for _, b in ipairs(bf.controls) do "
        f"if b:IsShown() and b.control.label == 'Hide done' then b:Click() end end end"
    )
    settle(wow)
    assert wow.eval(f"{MOD}.db.profile.logHideDone") is True
    assert block_controls(wow, HD, "My quests here  1") == [("Hide done", True), ("Tracked", False)]
    assert len(block_rows(wow, HD, "My quests here  1")) == 1
    assert wow.errors == []


def test_a_zone_group_folds_on_click(wow: WowRuntime):
    """the zone group's header folds on a click, not only on its marker."""
    boot(wow)
    wow.execute(NOWHERE)
    wow.fire("QUEST_ACCEPTED", 99999)
    settle(wow)
    open_log(wow)
    assert any("A Song for Our Future" in t for t in flat(wow))
    wow.execute(
        f"for _, r in ipairs({WIN}.tree.flat) do if r.id == 'az:0' then {WIN}.tree.opts.onClick(r, 'LeftButton') end end"
    )
    assert not any("A Song for Our Future" in t for t in flat(wow))
    assert wow.eval(f"{MOD}.db.profile.tree.collapsed['az:0']") is True
    assert wow.errors == []


TRACKER = f"{MOD}.Tracker"
TF = "BastiansTrackerFrame"
GAME = "ObjectiveTrackerFrame"


def boot_tracker(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute(f'{GAME} = CreateFrame("Frame", "{GAME}", UIParent)')  # the game's tracker
    boot(wow, *addons)
    wow.execute(NOWHERE)
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)
    return wow


def tracker_rows(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{TRACKER}.tree.flat").values()]


def test_the_tracker_frame_shows_the_log_under_the_minimap_and_replaces_the_games(
    wow: WowRuntime,
):
    """R6: the log view in its own frame, on by default, under the
    minimap, two-line rows, the toggles on its bar; the game's tracker hides while it shows, out
    of combat only; the position survives a reload; the setting hides it again."""
    boot_tracker(wow)
    assert wow.eval(f"{TRACKER}.IsShown()") is True
    assert wow.eval(f"{TF}:IsShown()") is True and wow.eval(f"{GAME}:IsShown()") is False
    assert wow.eval(f"({TF}:GetPoint(1))") == "TOPRIGHT"
    assert wow.eval(f"select(2, {TF}:GetPoint(1)) == Minimap") is True
    assert wow.eval(f"{TF}:GetFrameStrata()") == "MEDIUM"
    assert any("A Song for Our Future" in t for t in tracker_rows(wow))
    assert wow.eval(f"{TRACKER}.tree.opts.twoLine") is True
    labels = [
        strip(b.label.GetText(b.label))
        for b in wow.eval(f"{TRACKER}.bar.pools.button").values()
        if b.IsShown(b)
    ]
    assert "Hide done" in labels and "Tracked" in labels
    # the item bar sits beside the frame; ESC leaves the frame alone
    assert wow.eval(f"{WIN}.ItemsOf") is not None
    assert TF not in list(wow.eval("UISpecialFrames").values())
    # in combat the game's tracker is not touched; the wish waits for the end of combat
    wow.set_combat(True)
    wow.execute(f"{TRACKER}.Hide()")
    assert wow.eval(f"{GAME}:IsShown()") is False
    wow.set_combat(False)
    assert wow.eval(f"{GAME}:IsShown()") is True
    wow.execute(f"{TRACKER}.Apply()")
    assert wow.eval(f"{TF}:IsShown()") is True and wow.eval(f"{GAME}:IsShown()") is False
    # a moved frame keeps its place through a reload (the window kit saves the place on a drag;
    # the profile carries it)
    wow.execute(f"{MOD}.db.profile.tracker.pos = {{ 100, -200 }}")
    fresh = wow.reload()
    fresh.execute(f'{GAME} = CreateFrame("Frame", "{GAME}", UIParent)')
    fresh.run_frames(5)
    fresh.advance(0.3)
    assert fresh.eval(f"{TF}:IsShown()") is True
    assert fresh.eval(f"select(4, {TF}:GetPoint(1))") == (100, -200)
    # the setting off: the frame goes and the game's tracker comes back; /bq tracker brings it back
    fresh.execute(f"{MOD}.db.profile.trackerFrame = false")
    fresh.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Quests', 'trackerFrame', false)")
    assert fresh.eval(f"{TF}:IsShown()") is False
    assert fresh.eval(f"{GAME}:IsShown()") is True
    fresh.slash("/bq tracker")
    assert fresh.eval(f"{TF}:IsShown()") is True and fresh.eval(f"{GAME}:IsShown()") is False
    # the lock: no drag, no grip
    fresh.execute(f"{MOD}.db.profile.trackerLocked = true")
    fresh.execute("Bastians:Fire('BASTIANS_SETTING_CHANGED', 'Quests', 'trackerLocked', true)")
    assert fresh.eval(f"{TRACKER}.win.grip:IsShown()") is False
    # the lock on the frame itself: it shows the state and switches it
    lock = f"{TRACKER}.win.lock"
    assert fresh.eval(f"{lock}.label:GetText()") == "Locked"
    fresh.execute(f"{lock}:Click()")
    assert fresh.eval(f"{MOD}.db.profile.trackerLocked") is False
    assert fresh.eval(f"{TRACKER}.win.grip:IsShown()") is True
    assert fresh.eval(f"{lock}.label:GetText()") == "Lock"
    fresh.execute(f"{lock}:Click()")
    assert fresh.eval(f"{MOD}.db.profile.trackerLocked") is True
    assert fresh.eval(f"{TRACKER}.win.grip:IsShown()") is False
    assert fresh.errors == []


def test_the_game_tracker_comes_back_when_the_last_claim_goes(wow: WowRuntime):
    """The Companion's slim mode and the tracker frame both claim the game's tracker (Core): it
    returns only when neither needs it."""
    boot_tracker(wow, CORE, DATA, QUESTS, BROWSER)
    assert wow.eval(f"{GAME}:IsShown()") is False  # the tracker frame's claim
    wow.slash("/bq")
    wow.execute(f"{BMOD}.Browser.SetSlim(true)")
    assert wow.eval(f"{GAME}:IsShown()") is False
    wow.execute(f"{TRACKER}.Hide()")
    assert wow.eval(f"{GAME}:IsShown()") is False  # slim still claims it
    wow.execute(f"{BMOD}.Browser.SetSlim(false)")
    assert wow.eval(f"{GAME}:IsShown()") is True
    assert wow.eval("Bastians.UI.GameTrackerHidden()") is False
    assert wow.errors == []
