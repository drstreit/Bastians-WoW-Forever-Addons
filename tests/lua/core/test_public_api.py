"""The public API for other addons (ADR 0044, API.md): Bastians.API answers with copies of plain
values, nil when unknown or when the app is missing, never an error in the caller's code; RouteTo
hands a target to Route; events through CallbackHandler with scalar arguments; the functions and
events match API.md, the page for other addon authors."""

import re
from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
DOC = ROOT / "API.md"  # public: in this repository and in the snapshot
API = "Bastians.API"


def test_without_the_apps_every_answer_is_nil(wow: WowRuntime):
    wow.start("Bastians_Core")
    assert wow.eval(f"{API}.VERSION") == 1
    for call in (
        "Price(2589)",
        "Quest(7)",
        "QuestLog()",
        "Route()",
        "TravelTime(1429, 0.5, 0.5)",
        "RouteTo(1429, 0.5, 0.5, 'x')",
    ):
        assert wow.eval(f"select('#', {API}.{call})") == 1, call  # one nil, also for a pair
        assert wow.eval(f"({API}.{call})") is None, call
    assert wow.eval(f"{API}.IsEnabled('Quests')") is False
    assert wow.eval(f"{API}.IsEnabled('Core')") is True
    assert wow.errors == []


def test_prices_are_copies_of_plain_values(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """Live = { median = 1200, minBuyout = 999, source = "scan", age = 60,
             secret = "no", inner = { 1 }, fn = function() end }
        Bastians:ProvideService(Bastians:GetModule("Core"), "prices",
          { Price = function(_, id) if id == 2589 then return Live end end }, { priority = 999 })"""
    )
    p = dict(wow.eval(f"{API}.Price(2589)").items())
    assert p == {
        "median": 1200,
        "minBuyout": 999,
        "source": "scan",
        "age": 60,
    }  # no tables, no extras
    wow.execute(f"P = {API}.Price(2589); P.median = 1")
    assert wow.eval("Live.median") == 1200  # a copy: the caller cannot change the suite
    assert wow.eval(f"{API}.Price(4306)") is None  # not known: nil, never 0
    assert wow.eval(f"{API}.Price('2589')") is None
    assert wow.errors == []


def test_an_error_inside_the_suite_is_nil_for_the_caller(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """Bastians:ProvideService(Bastians:GetModule("Core"), "prices",
          { Price = function() error("broken") end }, { priority = 999 })
        Got = { pcall(Bastians.API.Price, 2589) }"""
    )
    got = list(wow.eval("Got").values())
    assert got == [True]  # the call itself succeeded and answered nothing
    log = wow.eval("Bastians:GetLog()").values()
    assert any(e.level == "error" and "broken" in e.text for e in log)  # logged against Core


def test_quests_and_the_apps_list(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests")
    wow.run_frames(5)
    log = dict(wow.eval(f"{API}.QuestLog()").items())
    assert log == {"count": 2, "ready": 1}  # the mock's quest log
    ids = list(wow.eval("Bastians:GetModule('Quests').State.order").values())
    states = [dict(wow.eval(f"{API}.Quest({i})").items()) for i in ids]
    assert sorted(s["ready"] for s in states) == [False, True]
    assert all(s["inLog"] is True and s["done"] is False for s in states)
    assert dict(wow.eval(f"{API}.Quest(999999)").items()) == {
        "done": False,
        "inLog": False,
        "ready": False,
    }
    apps = [dict(a.items()) for a in wow.eval(f"{API}.Apps()").values()]
    names = [a["name"] for a in apps]
    assert names == sorted(names) and "Quests" in names and "Data" in names
    assert not any("." in n for n in names)  # apps, not their parts
    quests = next(a for a in apps if a["name"] == "Quests")
    assert quests["enabled"] is True and isinstance(quests["title"], str)
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    assert wow.eval(f"{API}.QuestLog()") is None and wow.eval(f"{API}.Quest({ids[0]})") is None
    assert wow.eval(f"{API}.IsEnabled('Quests')") is False
    assert wow.errors == []


def test_route_to_and_the_active_route(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route")
    wow.run_frames(5)
    assert wow.eval(f"{API}.Route()") is None
    assert wow.eval(f"{API}.RouteTo(1429, 2, 0.5)") is None  # not a map position
    assert wow.eval(f"{API}.RouteTo(1429, 0.42, 0.65, 'Goldshire')") is True
    wow.run_frames(5)
    r = dict(wow.eval(f"{API}.Route()").items())
    assert r["goal"] == "Goldshire" and r["step"] == 1 and r["steps"] >= 1
    assert isinstance(r["seconds"], (int, float)) and r["continent"] == 0
    wow.slash("/broute clear")
    assert wow.eval(f"{API}.Route()") is None
    assert wow.errors == []


def test_events_reach_callbacks_with_scalar_arguments(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.execute(
        """Heard = {} ; Other = {}
        Bastians.API.RegisterCallback(Other, "BASTIANS_PLAYER_MOVED_ZONE", function(e, a, b)
          Heard[#Heard + 1] = { e = e, a = a, b = b } end)
        Bastians.API.RegisterCallback(Other, "BASTIANS_ROUTE_CHANGED", function(e, a)
          Heard[#Heard + 1] = { e = e, a = a } end)"""
    )
    wow.execute("Bastians:Fire('BASTIANS_PLAYER_MOVED_ZONE', 1429, 0)")
    wow.execute("Bastians:Fire('BASTIANS_ROUTE_CHANGED', { steps = {} })")  # a table stays home
    wow.execute("Bastians:Fire('BASTIANS_THEME_CHANGED', 'dark')")  # not public
    heard = [dict(x.items()) for x in wow.eval("Heard").values()]
    assert heard == [
        {"e": "BASTIANS_PLAYER_MOVED_ZONE", "a": 1429, "b": 0},
        {"e": "BASTIANS_ROUTE_CHANGED"},
    ]
    wow.execute("Bastians.API.UnregisterAllCallbacks(Other)")
    wow.execute("Bastians:Fire('BASTIANS_PLAYER_MOVED_ZONE', 1430, 0)")
    assert len(list(wow.eval("Heard").values())) == 2
    assert wow.errors == []


def test_the_functions_and_events_are_the_documented_ones(wow: WowRuntime):
    """CLAUDE.md §9: the public API is checked before every commit; this keeps code and API.md
    equal, so the page other authors read never promises what the code does not do."""
    wow.start("Bastians_Core")
    doc = DOC.read_text(encoding="utf-8")
    names = {k for k, v in wow.eval(API).items() if wow.eval(f"type({API}.{k})") == "function"}
    documented = set(re.findall(r"^\| `(\w+)\(", doc, flags=re.M))
    assert names == documented, (sorted(names - documented), sorted(documented - names))
    events = list(wow.eval(f"{API}.EVENTS").values())
    assert events == re.findall(r"^\| `(BASTIANS_\w+)`", doc, flags=re.M)  # same order too
    assert f"`Bastians.API.VERSION` is `{wow.eval(f'{API}.VERSION')}`" in doc
    assert "docs/" not in doc  # public: no links into the private documents
