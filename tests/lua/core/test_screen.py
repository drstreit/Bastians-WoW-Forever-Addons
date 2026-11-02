"""One key clears the screen: the ticked windows of
the suite hide and come back, the game's own frames fade (never hidden; a protected one keeps
its mouse), other addons' windows by name, an absent name is skipped, the bus message tells the
apps, the hub page builds its rows when shown."""

from harness import WowRuntime

SCREEN = "Bastians.UI.Screen"
CORE = "Bastians:GetModule('Core')"
P = f"{CORE}.db.profile"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    wow.execute(
        """
        ScreenTest = { fired = {} }
        ScreenTest.win = Bastians.UI.Window('ScreenTestWindow', { title = 'T', module = 'Core' }); ScreenTest.win:Show()
        ScreenTest.other = Bastians.UI.Window('ScreenTestOther', { title = 'O', module = 'Other' }); ScreenTest.other:Show()
        MinimapCluster = CreateFrame('Frame', 'MinimapCluster', UIParent)
        PlayerFrame = CreateFrame('Frame', 'PlayerFrame', UIParent)
        PlayerFrame.IsProtected = function() return true end
        PlayerFrame:EnableMouse(true)
        SomeAddonFrame = CreateFrame('Frame', 'SomeAddonFrame', UIParent)
        SomeAddonFrame.IsProtected = function() return false end
        SomeAddonFrame:EnableMouse(true)
        Bastians:GetModule('Core'):On('BASTIANS_SUITE_HIDDEN', function(_, _, on) table.insert(ScreenTest.fired, on) end)
        """
    )
    return wow


def test_the_key_hides_the_ticked_things_and_brings_them_back(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"{P}.screen_Other = false {P}.screenMinimap = true {P}.screenUnits = true {P}.screenOther_SomeAddonFrame = true {P}.screenOther_Missing = true"
    )
    assert wow.eval(f"{SCREEN}.Toggle()") is True
    assert wow.eval(f"{SCREEN}.Hidden()") is True
    assert wow.eval("ScreenTest.win.frame:IsShown()") is False
    assert wow.eval("ScreenTest.other.frame:IsShown()") is True  # not ticked
    assert wow.eval("MinimapCluster:GetAlpha()") == 0
    assert wow.eval("PlayerFrame:GetAlpha()") == 0
    assert wow.eval("PlayerFrame:IsMouseEnabled()") is True  # protected: the mouse stays
    assert wow.eval("SomeAddonFrame:GetAlpha()") == 0
    assert wow.eval("SomeAddonFrame:IsMouseEnabled()") is False
    assert list(wow.eval("ScreenTest.fired").values()) == [True]
    assert wow.eval(f"{SCREEN}.Toggle()") is True
    assert wow.eval(f"{SCREEN}.Hidden()") is False
    assert wow.eval("ScreenTest.win.frame:IsShown()") is True
    assert wow.eval("MinimapCluster:GetAlpha()") == 1
    assert wow.eval("PlayerFrame:GetAlpha()") == 1
    assert wow.eval("SomeAddonFrame:IsMouseEnabled()") is True
    assert list(wow.eval("ScreenTest.fired").values()) == [True, False]
    assert wow.errors == []


def test_the_page_lists_the_groups_and_the_ticked_names(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{P}.screenOther_SomeAddonFrame = true")
    rows = list(wow.eval(f"{SCREEN}.Options()").values())
    labels = [r.label for r in rows]
    assert labels[0] == "The suite" and "The game's own" in labels and "Other addons" in labels
    assert "Minimap" in labels and "Action bars" in labels and "Unit frames" in labels
    assert "SomeAddonFrame" in labels
    keys = [r.key for r in rows if r.key]
    assert "screenMinimapButtons" in keys and "screenOthersAll" in keys
    assert labels.count("Tick all") == 3 and labels.count("Untick all") == 3
    # Tick all of the game's groups, then untick: the profile follows
    ticks = [r for r in rows if r.label == "Tick all"]
    wow.execute(f"({SCREEN}.Options())[{rows.index(ticks[1]) + 1}].func()")
    assert wow.eval(f"{P}.screenMinimap") is True and wow.eval(f"{P}.screenBars") is True
    unticks = [r for r in rows if r.label == "Untick all"]
    wow.execute(f"({SCREEN}.Options())[{rows.index(unticks[1]) + 1}].func()")
    assert wow.eval(f"{P}.screenMinimap") is False
    # the Map's minimap frame hides with the Map; the state is kept for the next login
    wow.execute("BastiansMiniMap = CreateFrame('Frame', 'BastiansMiniMap', UIParent)")
    wow.execute(f"{SCREEN}.Hide()")
    assert wow.eval("BastiansMiniMap:IsShown()") is False
    assert wow.eval(f"{P}.screenHidden") is True
    wow.execute(f"{SCREEN}.Show()")
    assert wow.eval("BastiansMiniMap:IsShown()") is True
    assert wow.eval(f"{P}.screenHidden") is None
    page = wow.eval("Bastians.UI.Settings.Page(Bastians:GetModule('Core'), 'screen')")
    assert page.title == "Hidden by the key"
    assert (
        wow.eval("BINDING_NAME_BASTIANS_CLEAR_SCREEN")
        == "Clear the screen (hide and show what is ticked)"
    )
    assert wow.errors == []
