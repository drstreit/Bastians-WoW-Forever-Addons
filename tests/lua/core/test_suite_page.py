"""The Suite page: the first page of
the hub and the root of the Blizzard panel lists every app of this client with its words, its
switch, its minimap button and its Open button; an app that is not installed says so; every app's
own page starts with its words; the welcome window opens from the page."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Gold",
    "Bastians_Browser",
)
SETTINGS = "Bastians.UI.Settings"


def strip(text) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text or ""))
    return text.replace("|r", "")


def labels(wow: WowRuntime) -> list[str]:
    out = []
    for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values():
        label = w.label
        out.append(strip(label.GetText(label)) if label is not None else "<button>")
    return out


def checkbox(wow: WowRuntime, index: int):
    return list(wow.eval("Bastians.UI.Hub.canvas.widgets").values())[index]


def test_the_suite_page_is_first_and_lists_every_app_of_this_client(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, GOLD, BROWSER)
    wow.run_frames(5)
    wow.execute("Mock.addons['Bastians_Notes'] = nil")  # not on this machine
    wow.slash("/bastians")
    assert wow.eval("Bastians.UI.Hub.current.suite") is True  # opens on the Suite page
    texts = labels(wow)
    assert texts[0].startswith("Bastian's Suite is Azeroth, told in your own way")
    # every app of this client, installed or not, in the suite's order
    headers = [
        t
        for t in texts
        if t in ("Quests", "Map", "Browser", "Gold", "Route", "Strategies", "Notes", "Data")
    ]
    if wow.client == "forever":
        assert headers == [
            "Quests",
            "Map",
            "Browser",
            "Gold",
            "Route",
            "Strategies",
            "Notes",
            "Data",
        ]
    else:  # Gold and the book ship for WoW Forever only (ADR 0022): not listed on retail
        assert headers == ["Quests", "Map", "Browser", "Route", "Notes", "Data"]
    q = texts.index("Quests")
    assert texts[q + 1].startswith("Every quest: what to do next") and texts[q + 1].endswith("/bq")
    assert texts[q + 2] == "Enabled"
    assert texts[q + 3] == "<button>"  # Open Quests
    assert texts[q + 4] == "Its own minimap button"
    # an app that is not installed says so, with the client's files
    n = texts.index("Notes")
    assert texts[n + 2].startswith("Not installed. Install the")
    # the parts and companions of this client follow (ADR 0015)
    assert any(t.startswith("Bastian's addons for") for t in texts)
    assert wow.errors == []


def test_the_switch_turns_an_app_off_and_on_and_the_minimap_button_follows(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(5)
    wow.execute("Bastians.UI.Hub.Open('suite')")
    texts = labels(wow)
    q = texts.index("Quests")
    switch = checkbox(wow, q + 2)
    assert switch.GetChecked(switch) is True
    switch.Click(switch)
    assert wow.eval("Bastians:GetModule('Quests'):IsEnabled()") is False
    assert wow.eval("Bastians:GetModule('Map'):IsEnabled()") is True  # the others keep working
    # the page drew again: the switch shows off, the navigation says (off)
    texts = labels(wow)
    switch = checkbox(wow, texts.index("Quests") + 2)
    assert switch.GetChecked(switch) is False
    nav = [
        strip(b.label.GetText(b.label))
        for b in wow.eval("Bastians.UI.Hub.nav:GetChildren()")
        if b.IsShown(b)
    ]
    assert any(n.startswith("Quests") and "(off)" in n for n in nav)
    switch.Click(switch)
    assert wow.eval("Bastians:GetModule('Quests'):IsEnabled()") is True
    # the minimap button switch writes the launcher's setting
    texts = labels(wow)
    mm = checkbox(wow, texts.index("Quests") + 4)
    mm.Click(mm)
    assert wow.eval("Bastians.UI.Launcher.AppSettings('Quests').hide") is True
    mm.Click(mm)
    assert not wow.eval("Bastians.UI.Launcher.AppSettings('Quests').hide")
    assert wow.errors == []


def test_every_apps_own_page_starts_with_its_words(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(5)
    wow.execute("Bastians.UI.Hub.Open('Map')")
    texts = labels(wow)
    assert texts[0].startswith("One seamless map of the world") and texts[0].endswith("/bmap")
    assert texts[1] == "What it does"  # the page skeleton (plan-launch-review O4, 01.11.2026)
    assert "Enabled" in texts and texts.index("Enabled") > texts.index("What it does")
    # the app's own window colour and opacity follow the Open and minimap rows (30.10.2026)
    assert "Window background" in texts and "Window opacity (%)" in texts
    wow.execute("Bastians.UI.Hub.Open('Core')")
    texts = labels(wow)
    assert texts[0] == "Profiles"  # General has no app words and no parts list any more
    assert not any(t.startswith("Bastian's addons for") for t in texts)
    assert wow.errors == []


def test_the_blizzard_panel_root_is_the_suite_page(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(5)
    cats = wow.eval("Mock.settingsCategories")
    assert cats[1].name == "Bastians"
    children = sorted(c.name for c in cats[1].children.values())
    assert children[:2] == ["Data", "General"]
    wow.execute(f"{SETTINGS}.Panels().Suite.canvas:Show()")
    widgets = list(wow.eval(f"{SETTINGS}.Panels().Suite.canvas.widgets").values())
    assert len(widgets) > 8 and wow.eval(f"{SETTINGS}.Panels().Suite.canvas.suite") is True
    wow.execute(f"{SETTINGS}.Open()")  # no module: the Suite page
    assert wow.eval("Mock.settingsOpened") == wow.eval(
        f"{SETTINGS}.Panels().Suite.category:GetID()"
    )
    assert wow.errors == []
