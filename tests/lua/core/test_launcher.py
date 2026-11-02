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
    # the options window has a button of its own, toggled on the General page
    assert wow.eval("BastiansMinimapButtonOptions:IsShown()") is True
    wow.execute("BastiansMinimapButtonOptions:Click('LeftButton')")
    assert wow.eval("BastiansHubFrame:IsShown()") is True
    wow.execute("BastiansMinimapButtonOptions:Click('LeftButton')")
    assert wow.eval("BastiansHubFrame:IsShown()") is False
    wow.execute(f"{LAUNCHER}.SetAppButton('Options', false)")
    assert wow.eval("BastiansMinimapButtonOptions:IsShown()") is False
    wow.execute(f"{LAUNCHER}.SetAppButton('Options', true)")
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


def test_a_second_click_closes_and_a_switched_off_app_opens_its_page(wow: WowRuntime):
    """the Browser's and the Campfire's buttons "open but do not close";
    the Gestures button "should open their options, not the radial menu" and close them again;
    Chat's button "just says switched off, never on, unclear what it even does": a switched-off
    app's button opens its page, where its Enabled switch is; the welcome has a button of its own
    ("I miss the intro page with wanderer and scholar")."""
    apps = ["Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Gestures"]
    apps += ["Bastians_Chat"]
    camp = wow.made_for("Bastians_Campfire")
    if camp:
        apps.append("Bastians_Campfire")
    wow.start(*apps)
    wow.run_frames(5)
    views = "Bastians:GetService('views')"
    wow.execute("BastiansMinimapButtonBrowser:Click('LeftButton')")
    assert wow.eval(f"{views}:IsShown()") is True
    wow.execute("BastiansMinimapButtonBrowser:Click('LeftButton')")
    assert wow.eval(f"{views}:IsShown()") is False
    # Gestures: the options page, closed by a second click; the ring stays on its key
    wow.execute("BastiansMinimapButtonGestures:Click('LeftButton')")
    assert wow.eval("Bastians.UI.Hub.Shows('Gestures')") is True
    wow.execute("BastiansMinimapButtonGestures:Click('LeftButton')")
    assert wow.eval("BastiansHubFrame:IsShown()") is False
    obj = "Bastians:FeedObject('Gestures')"
    wow.execute(f"{obj}.OnClick(nil, 'LeftButton')")
    assert wow.eval("Bastians.UI.Hub.Shows('Gestures')") is True
    wow.execute(f"{obj}.OnClick(nil, 'LeftButton')")
    assert wow.eval("BastiansHubFrame:IsShown()") is False
    if camp:  # the planner in the Browser, closed by a second click
        wow.execute("Bastians:FeedObject('Campfire').OnClick(nil, 'LeftButton')")
        assert wow.eval(f"{views}:IsShown('campfire.planner')") is True
        wow.execute("Bastians:FeedObject('Campfire').OnClick(nil, 'LeftButton')")
        assert wow.eval(f"{views}:IsShown()") is False
    # Chat ships off: its button and the Messenger's open Chat's page with the switch
    assert wow.eval("Bastians:GetModule('Chat'):IsEnabled()") is False
    wow.execute("Bastians:FeedObject('Chat').OnClick(nil, 'LeftButton')")
    assert wow.eval("Bastians.UI.Hub.Shows('Chat')") is True
    wow.execute("BastiansHubFrame:Hide()")
    wow.execute(
        f"for _, e in ipairs({LAUNCHER}.ButtonEntries()) do "
        "if e.name == 'ChatMessenger' then e.open() end end"
    )
    assert wow.eval("Bastians.UI.Hub.Shows('Chat')") is True
    wow.execute("BastiansHubFrame:Hide()")
    # the welcome's own button
    assert wow.eval("BastiansMinimapButtonWelcome:IsShown()") is True
    wow.execute("BastiansMinimapButtonWelcome:Click('LeftButton')")
    assert wow.eval("Bastians.UI.Welcome.IsShown()") is True
    wow.execute("BastiansMinimapButtonWelcome:Click('LeftButton')")
    assert wow.eval("Bastians.UI.Welcome.IsShown()") is False
    assert wow.errors == []
