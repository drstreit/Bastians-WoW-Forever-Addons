"""The hub's menu, the app pages and the Help page (plan-launch-review.md O3 to O5, 01.11.2026):
the menu shows every app's one icon and nests a module's own pages under it with a tooltip of
the app's words; every app page follows one skeleton (the sentence, What it does, the switch,
Keys, its options with a tip on each described one, Works with); the Help page lists the story,
the two ways to play, every slash command and every key; `/bastians help` opens it and the usage
line names every subcommand."""

import re
from pathlib import Path

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, BROWSER, VOICE, ROUTE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Voice",
    "Bastians_Route",
)
HUB = "Bastians.UI.Hub"
SETTINGS = "Bastians.UI.Settings"
ADDONS = Path(__file__).resolve().parents[3] / "addons"


def strip(text) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text or ""))
    return text.replace("|r", "")


def labels(wow: WowRuntime) -> list[str]:
    out = []
    for w in wow.eval(f"{HUB}.canvas.widgets").values():
        label = w.label
        out.append(strip(label.GetText(label)) if label is not None else "<button>")
    return out


def nav(wow: WowRuntime) -> list:
    return [b for b in wow.eval(f"{HUB}.navButtons").values() if b.IsShown(b)]


def test_the_menu_shows_the_app_icons_and_nests_the_pages(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(5)
    wow.slash("/bastians")
    buttons = nav(wow)
    names = [strip(b.label.GetText(b.label)) for b in buttons]
    assert names[:2] == ["Bastian's Suite", "General"]
    # Core's own page sits under General, the Map's under the Map, indented
    assert names[2] == "Hidden by the key"
    assert names.index("Minimap") == names.index("Map") + 1
    by_name = dict(zip(names, buttons, strict=True))
    assert by_name["Minimap"].entry.indent is True
    assert by_name["Map"].icon.IsShown(by_name["Map"].icon)
    assert str(by_name["Map"].icon.GetTexture(by_name["Map"].icon)).endswith("Tiles\\app_map")
    assert str(by_name["Quests"].icon.GetTexture(by_name["Quests"].icon)).endswith(
        "Tiles\\app_quests"
    )
    # every other row carries a pictogram too
    for name, kind in (
        ("Bastian's Suite", "app_suite"),
        ("General", "settings"),
        ("Hidden by the key", "hide"),
        ("Minimap", "zone"),
        ("Help", "help"),
        ("What's new", "note"),
        ("About", "app_suite"),
    ):
        assert by_name[name].icon.IsShown(by_name[name].icon), name
        assert str(by_name[name].icon.GetTexture(by_name[name].icon)).endswith("Tiles\\" + kind), (
            name
        )
    # the tooltip: the app's words
    assert by_name["Quests"].tip.startswith("Every quest:")
    assert by_name["Help"].tip is not None
    # Help sits between the apps and What's new
    assert names.index("Help") == names.index("What's new") - 1
    assert names[-1] == "About"
    assert wow.errors == []


def test_every_app_page_follows_the_skeleton(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    for app in wow.eval("Bastians.APPS").values():
        assert app.does is not None and len(list(app.does.values())) >= 3, app.module
    # keys: every addon with a Bindings.xml names its actions in its identity
    bound = {
        p.parent.name: re.findall(r'Binding name="([A-Z_]+)"', p.read_text(encoding="utf-8"))
        for p in ADDONS.glob("*/Bindings.xml")
    }
    for app in wow.eval("Bastians.APPS").values():
        if app.addon in bound and app.addon != CORE:
            # `keys` is lupa's own method name on a table: read the field in Lua
            joined = wow.eval(
                f"table.concat(Bastians.UI.Settings.AppByModule('{app.module}').keys, ',')"
            )
            assert sorted(str(joined).split(",")) == sorted(bound[app.addon]), app.addon
    assert sorted(wow.eval(f"{SETTINGS}.CORE_KEYS").values()) == sorted(bound[CORE])
    wow.execute("Mock.addons['Bastians_Route'] = nil")  # not on this machine
    wow.execute(f"{HUB}.Open('Quests')")
    texts = labels(wow)
    assert texts[0].startswith("Every quest:") and texts[0].endswith("/bq")
    for header in ("What it does", "Enabled", "Keys", "Works with"):
        assert header in texts, header
    assert (
        texts.index("What it does")
        < texts.index("Enabled")
        < texts.index("Keys")
        < texts.index("Works with")
    )
    bullets = texts[texts.index("What it does") + 1 : texts.index("Enabled")]
    assert 3 <= len(bullets) <= 5 and all(b.startswith("- ") for b in bullets)
    keys = texts[texts.index("Keys") + 1 : texts.index("Keys") + 3]
    assert keys[0] == "Open Bastian's Quests: not set"  # the mock has no GetBindingKey
    assert keys[1] == "Set the keys"
    works = texts[texts.index("Works with") + 1 :]
    assert any(t == "Show on map needs Bastian's Map (on)." for t in works)
    assert any(t == "Route there needs Bastian's Route (not installed)." for t in works)
    assert any(t == "Play the quest's voice needs Bastian's Orbiter (on)." for t in works)
    # General: Profiles first, the suite's keys after its options
    wow.execute(f"{HUB}.Open('Core')")
    texts = labels(wow)
    assert texts[0] == "Profiles" and "Keys" in texts
    assert texts.index("Keys") > texts.index("Diagnostics")
    assert wow.errors == []


def test_a_described_option_of_any_type_gets_the_tip(wow: WowRuntime):
    wow.start(CORE, DATA)
    wow.run_frames(5)
    wow.execute(f"{HUB}.Open('Core')")
    tips = {}
    for w in wow.eval(f"{HUB}.canvas.widgets").values():
        label = w.label
        if label is not None and w.tip is not None:
            tips[strip(label.GetText(label))] = str(w.tip)
    assert "Text size (percent)" in tips  # a range
    assert "Faces in the rows of NPCs" in tips  # a toggle
    assert "Tell me about updates" in tips  # a select
    assert "Window background" in tips  # a colour
    assert tips["Tell me about updates"].startswith("After an update:")
    assert wow.errors == []


def test_the_help_page_and_the_usage_line(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, VOICE)
    wow.run_frames(5)
    wow.execute("Mock.addons['Bastians_Route'] = nil")  # not on this machine
    wow.slash("/bastians help")
    assert wow.eval(f"{HUB}.current.help") is True
    assert wow.eval(f"{HUB}.canvas.help") is True
    texts = labels(wow)
    assert texts[0].startswith("Bastian's Suite is Azeroth, told in your own way.")
    for header in (
        "Two ways to play",
        "Play as",
        "Slash commands",
        "Keys",
        "How the apps link",
        "Where to ask",
    ):
        assert header in texts, header
    assert any(t.startswith("The Wanderer:") for t in texts)
    assert "Quests: /bq" in texts and "Map: /bmap" in texts and "Orbiter: /bv" in texts
    assert not any(t.startswith("Route:") for t in texts)  # not installed: no command listed
    keys = texts[texts.index("Keys") + 1 : texts.index("How the apps link")]
    assert keys[0].startswith("Open the search (omnibox): ")
    assert "Open Bastian's Map: not set" in keys and "Toggle the Orbiter: not set" in keys
    assert not any("Route" in k for k in keys)
    assert keys[-1] == "Set the keys"
    # the Play as select on the Help page writes the preset
    wow.execute(f"{SETTINGS}.ApplyPlay('scholar')")
    wow.execute(f"{HUB}.Refresh()")
    assert any(t.startswith("Every quest, creature, item and place") for t in labels(wow))
    # the usage line names every subcommand
    wow.slash("/bastians nonsense")
    usage = next(line for line in wow.chat if "/bastians:" in line)
    for word in (
        "hub",
        "suite",
        "help",
        "news",
        "about",
        "addons",
        "welcome",
        "log [n]",
        "debug",
        "profile [name]",
        "perf",
    ):
        assert word in usage, word
    assert wow.errors == []


def test_the_rail_rows_carry_the_sentence_and_the_options_are_cards(wow: WowRuntime):
    """ADR 0058, PH7: the hub's menu is a rail of rows with the app's icon, its name and its one
    sentence under it (a page of an app stays a plain row under it); every option of a page is a
    card with its description under the widget and the control at the right."""
    wow.start(CORE, DATA, QUESTS, MAP)
    wow.run_frames(5)
    wow.slash("/bastians")
    buttons = nav(wow)
    by_name = {strip(b.label.GetText(b.label)): b for b in buttons}
    quests = by_name["Quests"]
    assert quests.GetHeight(quests) == 40 and quests.sub.IsShown(quests.sub)
    assert strip(quests.sub.GetText(quests.sub)).startswith("Every quest:")
    minimap = by_name["Minimap"]
    assert minimap.GetHeight(minimap) == 24 and not minimap.sub.IsShown(minimap.sub)
    # the rows stack by their heights, none over another
    tops = [
        -wow.eval(f"select(5, {HUB}.navButtons[{i}]:GetPoint(1))")
        for i in range(1, len(buttons) + 1)
    ]
    heights = [b.GetHeight(b) for b in buttons]
    for i in range(1, len(tops)):
        assert tops[i] == tops[i - 1] + heights[i - 1], i
    # the Quests page: the options on cards, the toggles' boxes at the right, the description under
    wow.execute(f"{HUB}.Open('Quests')")
    assert wow.eval(f"{HUB}.canvas.cardCount") >= 3
    widgets = list(wow.eval(f"{HUB}.canvas.widgets").values())
    toggles = [w for w in widgets if w.box is not None and w.card is not None]
    assert toggles and all(w.controlRight is True for w in toggles)
    assert all(
        wow.eval(f"(select(1, {HUB}.canvas.widgets[{i + 1}].box:GetPoint(1)))") == "RIGHT"
        for i, w in enumerate(widgets)
        if w.box is not None and w.card is not None
    )
    # General's options carry descriptions: the card shows the description under the widget
    wow.execute(f"{HUB}.Open('Core')")
    widgets = list(wow.eval(f"{HUB}.canvas.widgets").values())
    described = [(i, w) for i, w in enumerate(widgets) if w.card not in (None, "")]
    assert described
    i, w = described[0]
    n = sum(1 for x in widgets[: i + 1] if x.card is not None)  # the card's number among the cards
    assert strip(wow.eval(f"{HUB}.canvas.cardPool[{n}].desc:GetText()")) == strip(str(w.card))
    assert wow.eval(f"{HUB}.canvas.cardPool[{n}]:IsShown()") is True
    # a header and a note are no cards
    headers = [w for w in widgets if w.card is None]
    assert headers
    assert wow.errors == []
