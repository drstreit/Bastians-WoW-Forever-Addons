"""The Browser's title bar and what Slim left behind. Slim mode (C8, ADR 0014: the window collapsed
to the log as a tracker and hid the game's tracker) went with ADR 0056 (PA1.3; ADR 0054 B13: "Slim
would not be missed"): Quests has a tracker frame of its own. A profile saved in slim mode opens
wide again, `/bq slim` is no command any more, the `views` service has no `Slim`."""

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
    # the Browser alone
    wow.execute("Bastians:GetModule('Quests').db.profile.trackerFrame = false")
    wow.execute("Bastians:GetModule('Quests').Tracker.Apply()")
    return wow


def test_slim_is_gone_and_a_slim_profile_opens_wide(wow: WowRuntime):
    boot(wow)
    # a profile as slim mode left it: the narrow window saved, the wide size kept beside it
    wow.execute(
        f"""
        local p = {MOD}.db.profile
        p.slim, p.slimWidth, p.hideTracker = true, 300, true
        p.wideSize = {{ 900, 640 }}
        p.window = p.window or {{}}
        p.window.size = {{ 300, 640 }}
        """
    )
    wow.slash("/bq")
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 900  # wide again
    p = f"{MOD}.db.profile"
    assert wow.eval(f"{p}.slim == nil and {p}.slimWidth == nil and {p}.wideSize == nil") is True
    assert wow.eval(f"{p}.hideTracker") is None
    assert (
        wow.eval(f"{MOD}.rail:IsShown()") is True and wow.eval(f"{MOD}.toolbar:IsShown()") is True
    )
    assert wow.eval(f"{MOD}.listPane:IsShown()") is True
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is True
    assert wow.eval(f"{MOD}.toolbar.slim") is None  # no button
    assert (
        wow.eval(f"{BR}.SetSlim == nil and {BR}.IsSlim == nil and {BR}.ToggleSlim == nil") is True
    )
    assert wow.eval("Bastians:GetService('views').Slim") is None
    # the Browser no longer touches the game's tracker
    assert wow.eval(f"{TRACKER}:IsShown()") is True
    assert wow.eval("Bastians.UI.GameTrackerHidden()") is False
    # `/bq slim` is no command: the usage line, without the word
    wow.chat.clear()
    wow.slash("/bq slim")
    assert any("Usage: /bq" in line and "slim" not in line for line in wow.chat)
    assert wow.errors == []


def test_dock_sits_in_the_title_bar_and_the_gesture_is_wired(wow: WowRuntime):
    """Dock lives in the title bar; a right-button drag over the window
    goes back and forward; the bar is 26 px with 30 px arrows."""
    boot(wow)
    wow.slash("/bb")
    assert wow.eval(f"{MOD}.toolbar.dock:GetParent() == {MOD}.win.head") is True
    assert wow.eval(f"{MOD}.toolbar.dock:IsShown()") is True
    g = wow.eval(f"{MOD}.win.opts.gestures")
    assert g.back is not None and g.forward is not None
    assert wow.eval(f"{MOD}.toolbar:GetHeight()") == 26
    assert (
        wow.eval(f"{MOD}.toolbar.back:GetWidth()") >= 30
    )  # self-sized since ADR 0046 (pictogram and word)
    assert wow.errors == []
