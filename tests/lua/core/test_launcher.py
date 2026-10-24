"""Minimap buttons (core.md "Launcher"; "all main functions need
separate minimap buttons"): the suite's button plus one per app with a window, each with its
icon, its place around the minimap and a switch on the app's settings page."""

from harness import WowRuntime

APPS = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Gold",
    "Bastians_Browser",
)
LAUNCHER = "Bastians.UI.Launcher"


def test_every_app_with_a_window_has_its_own_minimap_button(wow: WowRuntime):
    wow.start(*APPS)
    wow.run_frames(5)
    assert wow.eval("BastiansMinimapButton ~= nil") is True  # the suite's own stays
    gold = wow.made_for("Bastians_Gold")  # no Gold on retail
    names = ("Browser", *(["Gold"] if gold else []), "Map", "Quests")
    for name in names:
        assert (
            wow.eval(
                f"BastiansMinimapButton{name} ~= nil and BastiansMinimapButton{name}:IsShown()"
            )
            is True
        ), name
    # each at its own place around the minimap
    angles = {wow.eval(f"{LAUNCHER}.AppSettings('{n}').angle") for n in names}
    assert len(angles) == len(names)
    if gold:  # a click opens the app's window
        wow.execute("BastiansMinimapButtonGold:Click('LeftButton')")
        assert wow.eval("BastiansGoldFrame and BastiansGoldFrame:IsShown()") is True
    # the right-click menu of the suite's button lists the apps
    wow.execute(f"{LAUNCHER}.ShowMenu(BastiansMinimapButton)")
    labels = [
        b.label.GetText(b.label)
        for b in wow.eval("BastiansLauncherMenu.items").values()
        if b.IsShown(b)
    ]
    assert "Map" in labels and ("Gold" in labels) is gold and labels[-1] == "Settings"
    # the switch on the app's settings page hides it, and the choice is kept
    wow.execute(f"{LAUNCHER}.SetAppButton('Map', false)")
    assert wow.eval("BastiansMinimapButtonMap:IsShown()") is False
    assert wow.eval("Bastians:GetModule('Core').db.profile.minimapApps.Map.hide") is True
    wow.execute(f"{LAUNCHER}.SetAppButton('Map', true)")
    assert wow.eval("BastiansMinimapButtonMap:IsShown()") is True
    # an app switched off hides its button
    if gold:
        wow.execute("Bastians:GetModule('Gold'):Disable()")
        assert wow.eval("BastiansMinimapButtonGold:IsShown()") is False
    wow.execute("Bastians.UI.Hub.Open('Map')")
    texts = [
        w.label.GetText(w.label)
        for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values()
        if w.label is not None
    ]
    assert "Its own minimap button" in texts
    assert wow.errors == []
