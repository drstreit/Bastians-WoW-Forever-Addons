"""What's new for the whole suite (ADR 0021, core.md "What's new"): the modules' entries, a first
start that says nothing, an update that gives one chat line and the dot, the hub page that marks
everything seen, the setting (always, weekly, never), nothing in combat, the links, and the
fingerprint that keeps a Data edition from listing the optional addons again."""

import re

from harness import WowRuntime

CORE = "Bastians_Core"
NEWS = "Bastians.UI.News"
CORE_NEWS = "Bastians:GetModule('Core').def.news"
STATE = "Bastians:GetModule('Core').db.global.news"


def strip(text) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text or ""))
    return text.replace("|r", "")


def add(wow: WowRuntime, date: str, text: str, version: str | None = None) -> None:
    v = f", version = {version!r}" if version else ""
    wow.execute(f"table.insert({CORE_NEWS}, 1, {{ date = {date!r}, text = {text!r}{v} }})")


def updated_lines(wow: WowRuntime) -> list[str]:
    return [strip(x) for x in wow.chat if "Bastian's Suite updated" in strip(x)]


def dot(wow: WowRuntime):
    shown = wow.eval("Bastians.UI.Launcher.Current() and Bastians.UI.Launcher.Current().newsDot")
    return shown is not None and shown.IsShown(shown)


def page(wow: WowRuntime) -> list[str]:
    wow.slash("/bastians news")
    canvas = wow.eval("Bastians.UI.Hub.canvas")
    return [strip(w.text) for w in canvas.widgets.values() if w.IsShown(w)]


def start_empty(wow: WowRuntime) -> WowRuntime:
    """Core logged in with its shipped News.lua emptied (the releases fill it)."""
    wow.load_addon(CORE)
    wow.execute(f"for k in pairs({CORE_NEWS}) do {CORE_NEWS}[k] = nil end")
    wow.login()
    return wow


def first_start(wow: WowRuntime) -> WowRuntime:
    """Core with two entries already there at the first start on this account."""
    wow.load_addon(CORE)
    add(wow, "2026-10-20", "The suite opens.")
    wow.login()
    wow.advance(4)
    return wow


def test_only_core_shows_that_nothing_is_new(wow: WowRuntime):
    start_empty(wow)
    wow.advance(4)
    assert wow.eval("Bastians:NewsUnseen()") == 0 and not dot(wow) and updated_lines(wow) == []
    assert any(t.startswith("Nothing new yet") for t in page(wow))
    assert wow.errors == []


def test_a_first_start_says_nothing_and_an_update_says_it_once(wow: WowRuntime):
    first_start(wow)
    assert updated_lines(wow) == [] and not dot(wow)
    assert wow.eval("Bastians:NewsUnseen()") == 0  # what was there counts as seen
    fresh = wow.reload()
    add(fresh, "2026-10-20", "The suite opens.")  # News.lua ships what it had, plus the new
    add(fresh, "2026-10-25", "What's new opens from the minimap.", "1.0.1")
    add(fresh, "2026-10-25", "The hub lists the news.", "1.0.1")
    fresh.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.1'")
    fresh.advance(4)
    assert updated_lines(fresh) == [
        "Bastians: Bastian's Suite updated: 2 new things, /bastians news"
    ]
    assert dot(fresh) and fresh.eval("Bastians:NewsUnseen()") == 2
    tip = fresh.eval(
        "(function() local t = { lines = {} } "
        "function t:AddLine(s) table.insert(self.lines, s) end "
        "Bastians.UI.News.TipLine(t) return t.lines[1] end)()"
    )
    assert strip(tip) == "2 new things: /bastians news"
    shown = page(fresh)
    assert "2026-10-25" in shown and "2026-10-20" in shown  # by date, newest first
    assert shown.index("2026-10-25") < shown.index("2026-10-20")
    assert "new  General: The hub lists the news. (1.0.1)" in shown
    assert "General: The suite opens." in shown  # seen before: no mark
    assert fresh.eval("Bastians:NewsUnseen()") == 0 and not dot(fresh)  # the page was shown
    # a reload without an update: no line
    again = fresh.reload()
    again.advance(4)
    assert updated_lines(again) == [] and not dot(again)
    assert again.errors == []


def test_weekly_says_it_once_a_week_and_never_says_nothing(wow: WowRuntime):
    first_start(wow)
    wow.execute("Bastians:GetModule('Core').db.global.newsMode = 'weekly'")
    fresh = wow.reload()
    add(fresh, "2026-10-25", "One.")
    fresh.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.1'")
    fresh.advance(4)
    assert len(updated_lines(fresh)) == 1
    second = fresh.reload()
    add(second, "2026-10-26", "Two.")
    second.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.2'")
    second.advance(4)
    assert updated_lines(second) == [] and dot(second)  # within the week: the dot only
    third = second.reload()
    third.execute(f"{STATE}.said = time() - 8 * 24 * 3600")
    add(third, "2026-10-27", "Three.")
    third.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.3'")
    third.advance(4)
    assert len(updated_lines(third)) == 1
    third.execute("Bastians:GetModule('Core').db.global.newsMode = 'never'")
    fourth = third.reload()
    add(fourth, "2026-10-28", "Four.")
    fourth.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.4'")
    fourth.advance(4)
    assert updated_lines(fourth) == [] and not dot(fourth)
    assert "new  General: Four." in page(fourth)  # the page still lists everything
    assert fourth.errors == []


def test_nothing_shows_in_combat(wow: WowRuntime):
    first_start(wow)
    fresh = wow.reload()
    add(fresh, "2026-10-25", "Later.")
    fresh.execute("Mock.addons['Bastians_Core'].meta.Version = '1.0.1'")
    fresh.set_combat(True)
    fresh.advance(4)
    assert updated_lines(fresh) == [] and not dot(fresh)
    fresh.set_combat(False)
    assert len(updated_lines(fresh)) == 1 and dot(fresh)
    assert fresh.errors == []


def test_entries_open_their_target_or_their_app_and_an_app_marks_its_own(wow: WowRuntime):
    start_empty(wow)
    wow.execute(
        "Bastians:NewModule('Demo', { addon = 'Bastians_Core', title = 'Demo', "
        "open = function() Mock.demoOpened = 'app' end, news = { "
        "{ id = 'a', date = '2026-10-25', text = 'Opens the app.' }, "
        "{ id = 'b', date = '2026-10-24', text = 'Opens a place.', "
        "open = function() Mock.demoOpened = 'place' end } } })"
    )
    wow.advance(4)
    entries = wow.eval("Bastians:NewsEntries()")
    assert [e.key for e in entries.values()][:2] == ["Demo:a", "Demo:b"]
    wow.execute(f"{STATE}.seen = {{}}")
    wow.execute("Bastians:MarkNewsSeen(Bastians:GetModule('Demo'))")
    assert wow.eval("Bastians:NewsUnseen()") == 0
    page(wow)
    for name, expected in (("Opens the app.", "app"), ("Opens a place.", "place")):
        wow.execute(
            "for _, w in ipairs(Bastians.UI.Hub.canvas.widgets) do "
            f"if w.text and w.text:find({name!r}, 1, true) then w:Click() end end"
        )
        assert wow.eval("Mock.demoOpened") == expected
    # a switched-off module shows none of its entries
    wow.execute("Bastians:GetModule('Demo'):Disable()")
    assert all(not e.key.startswith("Demo:") for e in wow.eval("Bastians:NewsEntries()").values())
    assert wow.errors == []


def test_a_data_edition_does_not_list_the_optional_addons_again(wow: WowRuntime):
    wow.start(CORE, "Bastians_Data")
    wow.execute("Mock.addons['Bastians_Data'].meta.Version = '1.0.0-beta.10+data.20261024.2'")
    short = wow.eval("Bastians.UI.Settings.Fingerprint()")
    full = wow.eval("Bastians.UI.Settings.Fingerprint(true)")
    assert "Bastians_Data=1.0.0-beta.10;" in short + ";" and "+data" not in short
    assert "Bastians_Data=1.0.0-beta.10+data.20261024.2" in full
    assert wow.errors == []
