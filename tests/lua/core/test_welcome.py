"""The welcome window: shown once at
the first start of the suite on an account, never in combat (then at the next login), again from
the Suite page and `/bastians welcome`; its lines name the apps, how to open things and the
guidelines."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
WELCOME = "Bastians.UI.Welcome"


def strip(text) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text or ""))
    return text.replace("|r", "")


def shown(wow: WowRuntime) -> bool:
    return wow.eval(f"{WELCOME}.IsShown()") is True


def lines(wow: WowRuntime) -> list[tuple[str, str]]:
    return [(x.kind, strip(x.text)) for x in wow.eval(f"{WELCOME}.Lines()").values()]


def test_the_first_start_shows_the_welcome_once(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(5)
    assert not shown(wow)
    wow.advance(4)  # News.Check runs three seconds after login
    assert shown(wow)
    assert wow.eval("Bastians:GetModule('Core').db.global.welcomed") is True
    wow.execute(f"{WELCOME}.Hide()")
    fresh = wow.reload()
    fresh.advance(4)
    assert not shown(fresh)  # once per account
    fresh.slash("/bastians welcome")
    assert shown(fresh)
    assert fresh.errors == []


def test_in_combat_the_welcome_waits_for_the_next_login(wow: WowRuntime):
    wow.start(CORE)
    wow.run_frames(5)
    wow.execute("Mock.SetCombat(true)")
    wow.advance(4)
    assert not shown(wow)
    assert not wow.eval("Bastians:GetModule('Core').db.global.welcomed")
    wow.execute("Mock.SetCombat(false)")
    fresh = wow.reload()
    fresh.advance(4)
    assert shown(fresh)
    assert fresh.errors == []


def test_the_lines_name_the_apps_how_to_open_things_and_the_guidelines(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(5)
    wow.execute("Mock.addons['Bastians_Map'] = nil")  # not on this machine
    rows = lines(wow)
    kinds = [k for k, _ in rows]
    assert kinds[0] == "note" and kinds.count("header") == 3
    headers = [t for k, t in rows if k == "header"]
    assert headers == ["Your apps", "How to open things", "Good to know"]
    apps = [t for k, t in rows if k == "app"]
    assert apps[0].startswith("Quests  /bq: Every quest")
    assert any(t.startswith("Map (not installed)  /bmap:") for t in apps)
    assert any(t.startswith("Data: The game data") for t in apps)
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    assert any(t.startswith("Quests (off)  /bq:") for k, t in lines(wow) if k == "app")
    notes = [t for k, t in rows if k == "note"]
    assert any("restart the game fully" in t for t in notes)
    assert any("bastians.dev/wow" in t for t in notes)
    # the window draws every line and its buttons open the settings and close it
    wow.execute(f"{WELCOME}.Show()")
    widgets = list(wow.eval(f"{WELCOME}.canvas.widgets").values())
    assert len(widgets) == len(rows)
    wow.execute(f"{WELCOME}.win.content:GetChildren()")  # the footer exists
    wow.execute("Bastians.UI.Welcome.win:Hide()")
    assert not shown(wow)
    assert wow.errors == []
