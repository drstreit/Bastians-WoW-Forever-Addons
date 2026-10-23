"""Slim mode (C8, ADR 0014): the window collapses to the Here column (width remembered, default
260 px) with a Slim/Wide toggle in the title bar and `/bq slim`; while slim the game's objective
tracker is hidden out of combat (setting, default on) and comes back when the window widens or
hides; in combat the wish waits for PLAYER_REGEN_ENABLED."""

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
TRACKER = "ObjectiveTrackerFrame"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute(f'{TRACKER} = CreateFrame("Frame", "{TRACKER}", UIParent)')  # the game's tracker
    # Quests' own tracker frame (R6) claims the game's tracker by default; these tests look at
    # slim mode alone
    wow.execute("Bastians:GetModule('Quests').db.profile.trackerFrame = false")
    wow.execute("Bastians:GetModule('Quests').Tracker.Apply()")
    return wow


def tracker_shown(wow: WowRuntime) -> bool:
    return wow.eval(f"{TRACKER}:IsShown()")


def test_slim_and_wide_round_trip(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq")
    assert wow.eval(f"{MOD}.toolbar.slim.label:GetText()") == "Slim"
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 1000  # three panes (ADR 0018)
    wow.execute(f"{MOD}.toolbar.slim:Click()")
    assert wow.eval(f"{BR}.IsSlim()") is True and wow.eval(f"{MOD}.db.profile.slim") is True
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 260
    assert wow.eval(f"{MOD}.nav:IsShown()") is False  # the tracker: the log view alone
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is False
    assert wow.eval(f"{MOD}.splitter:IsShown()") is False
    assert wow.eval(f"{BR}.Current().id") == "quests.log"
    assert wow.eval(f"{MOD}.toolbar.slim.label:GetText()") == "Wide"
    assert list(wow.eval(f"{MOD}.db.profile.wideSize").values()) == [1000, 600]
    # a resize while slim is remembered as the slim width
    wow.execute(f"{MOD}.win.frame:SetWidth(300); {MOD}.win.opts.onResize({MOD}.win, false)")
    assert wow.eval(f"{MOD}.db.profile.slimWidth") == 300
    wow.execute(f"{MOD}.toolbar.slim:Click()")
    assert wow.eval(f"{BR}.IsSlim()") is False
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 1000
    assert (
        wow.eval(f"{MOD}.nav:IsShown()") is True and wow.eval(f"{MOD}.splitter:IsShown()") is True
    )
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    wow.execute(f"{MOD}.toolbar.slim:Click()")
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 300  # the slim width remembered
    # /bq slim toggles it; the mode comes back with the profile
    wow.slash("/bq slim")
    assert wow.eval(f"{BR}.IsSlim()") is False
    wow.slash("/bq slim")
    assert wow.eval(f"{BR}.IsSlim()") is True
    fresh = wow.reload()
    fresh.run_frames(10)
    fresh.execute(f'{TRACKER} = CreateFrame("Frame", "{TRACKER}", UIParent)')
    fresh.slash("/bq")
    assert fresh.eval(f"{BR}.IsSlim()") is True and fresh.eval(f"{MOD}.win.frame:GetWidth()") == 300
    assert fresh.errors == []
    assert wow.errors == []


def test_the_tracker_hides_in_slim_mode_out_of_combat_only(wow: WowRuntime):
    boot(wow)
    wow.slash("/bq")
    assert tracker_shown(wow) is True
    wow.execute(f"{BR}.SetSlim(true)")
    assert tracker_shown(wow) is False  # slim and shown: the game's tracker goes
    wow.execute("BastiansBrowserFrame:Hide()")
    assert tracker_shown(wow) is True  # the window hides: the tracker comes back
    wow.slash("/bq")
    assert tracker_shown(wow) is False
    # in combat nothing is touched; the wish waits for the end of combat
    wow.set_combat(True)
    wow.execute(f"{BR}.SetSlim(false)")
    assert tracker_shown(wow) is False and wow.eval(f"{BR}.IsSlim()") is False
    wow.set_combat(False)
    assert tracker_shown(wow) is True
    wow.set_combat(True)
    wow.execute(f"{BR}.SetSlim(true)")
    assert tracker_shown(wow) is True
    wow.set_combat(False)
    assert tracker_shown(wow) is False
    # the setting off: the tracker is left alone
    wow.execute(f"{BR}.SetSlim(false)")
    assert tracker_shown(wow) is True
    wow.execute(f"{MOD}.db.profile.hideTracker = false")
    wow.execute(f"{BR}.SetSlim(true)")
    assert tracker_shown(wow) is True
    assert wow.errors == []


def test_slim_needs_the_browser(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    wow.slash("/bq slim")
    assert any("Slim mode needs" in line for line in wow.chat)
    assert wow.errors == []


def test_dock_sits_in_the_title_bar_and_the_gesture_is_wired(wow: WowRuntime):
    """slim mode could not dock (Dock lived on the hidden toolbar);
    a right-button drag over the window goes back and forward; the bar is 26 px with 30 px arrows."""
    boot(wow)
    wow.slash("/bb")
    assert wow.eval(f"{MOD}.toolbar.dock:GetParent() == {MOD}.win.head") is True
    wow.execute(f"{MOD}.toolbar.slim:Click()")
    assert wow.eval(f"{BR}.IsSlim()") is True
    assert wow.eval(f"{MOD}.toolbar.dock:IsShown()") is True
    assert wow.eval(f"{MOD}.toolbar:IsShown()") is False
    wow.execute(f"{MOD}.toolbar.slim:Click()")
    g = wow.eval(f"{MOD}.win.opts.gestures")
    assert g.back is not None and g.forward is not None
    assert wow.eval(f"{MOD}.toolbar:GetHeight()") == 26
    assert wow.eval(f"{MOD}.toolbar.back:GetWidth()") == 30
    assert wow.errors == []
