"""Explore (route.md "Explore", R26.11, W10 step 1): the value of an activity and its rate with the
way there (pure), the candidates the facet rules name, the graph's Activities over the network
fixture, Quests' and Gold's activity rules on the fixture world, and Route's Explore view."""

import re
import sys
from pathlib import Path

import pytest
from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data"))
from test_graph_network import SETUP
from test_navnet_search import lua_pack

CORE, DATA, QUESTS, GOLD, ROUTE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Route",
)
ACT = "Bastians.Data.Activity"

# Three test things on the network fixture's map: near waypoint 2 (west), east (0.65, 0.1), and a
# place the network cannot reach. Each an activity: a quick quest-like run, an hourly farm, a run
# without a time.
THINGS = """
local m = Bastians:NewModule("Things", { addon = "Bastians_TestApp" })
local PLACES = { { x = 0.425, y = 0.1 }, { x = 0.65, y = 0.1 }, { x = 0.9, y = 0.9 } }
Bastians:RegisterEntityType(m, { type = "testthing", name = function(id) return "Thing " .. id end,
  locations = function(id) local p = PLACES[tonumber(id)]
    return { { map = 9000, x = p.x, y = p.y } } end })
local ACTS = {
  ["testthing:1"] = { kind = "quest", takes = 60, gives = { { kind = "copper", amount = 100 },
    { kind = "xp", amount = 900 } } },
  ["testthing:2"] = { kind = "spot", gives = { { kind = "copper", amount = 50000, per = "hour" } } },
  ["testthing:3"] = { kind = "quest", gives = { { kind = "xp", amount = 500 } } },
}
Bastians:RegisterFacet(m, { facet = "activity", types = { "testthing" },
  rule = function(ref) return ACTS[ref] end,
  list = function() return { "testthing:1", "testthing:2", "testthing:3", "testthing:1" } end })
"""


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute(SETUP)
    wow.start(*(addons or (CORE, DATA)))
    wow.run_frames(5)
    wow.execute(lua_pack())
    wow.execute("Bastians.Deliver(); g = Bastians:GetService('graph')")
    wow.execute(THINGS)
    return wow


def settle(wow: WowRuntime) -> None:
    """The first ask starts the cache, the second queues the things' places; frames time them."""
    for _ in range(2):
        wow.execute("g:Activities()")
        wow.run_frames(10)


def test_the_value_and_the_rate_with_the_way(wow: WowRuntime):
    boot(wow)
    worth = "function(id) return ({ [1] = 1000, [2] = 300 })[id] end"
    act = """{ takes = 300, gives = { { kind = "copper", amount = 150 }, { kind = "xp", amount = 600 },
      { kind = "item", id = 2, amount = 2 }, { kind = "item", id = 9 },
      { kind = "item", id = 1, choice = true }, { kind = "item", id = 2, choice = true } } }"""
    run, hour, unpriced = wow.eval(f"{ACT}.Value({act}, {worth})")
    # 150 money, 2 x 300 for the item, the best choice 1000; item 9 has no worth: counted, not 0
    assert (run.copper, run.xp, unpriced) == (150 + 600 + 1000, 600, 1)
    assert dict(hour.items()) == {}
    # a fixed-time run: value x 3600 / (takes + way)
    copper, xp, _ = wow.eval(f"{ACT}.Rate({act}, 300, 3600, {worth})")
    assert (copper, xp) == (1750 * 6, 600 * 6)
    # an hourly one worked for an hour, 20 minutes away: three quarters of its rate
    farm = '{ gives = { { kind = "copper", amount = 10000, per = "hour" } } }'
    assert wow.eval(f"{ACT}.Rate({farm}, 1200, 3600)")[0] == 7500
    # a run without a time has no rate; a run on the spot counts at least 30 seconds
    assert (
        wow.eval(f"{ACT}.Rate({{ gives = {{ {{ kind = 'xp', amount = 5 }} }} }}, 10, 3600)")[1]
        is None
    )
    quick = "{ takes = 0, gives = { { kind = 'copper', amount = 10 } } }"
    assert wow.eval(f"{ACT}.Rate({quick}, 0, 3600)")[0] == 1200
    assert wow.errors == []


def test_the_rules_name_their_candidates_each_once(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """local m = Bastians:NewModule("More", { addon = "Bastians_TestApp2" })
        Bastians:RegisterFacet(m, { facet = "activity", types = { "testthing" }, priority = 10,
          rule = function() return nil end, list = function() return { "testthing:2", "testthing:4" } end })
        Bastians:RegisterFacet(m, { facet = "activity", types = { "testthing" }, priority = 5,
          rule = function() return nil end, list = function() error("broken list") end })"""
    )
    refs = list(wow.eval("Bastians:FacetCandidates('activity')").values())
    assert refs == ["testthing:1", "testthing:2", "testthing:3", "testthing:4"]
    assert any("broken list" in line.text for line in wow.eval("Bastians:GetLog()").values())
    assert list(wow.eval("Bastians:FacetCandidates('nothing')").values()) == []


def test_activities_within_the_way_by_gold_or_xp(wow: WowRuntime):
    boot(wow)
    hits, waiting = wow.eval("g:Activities({ minutes = 10 })")
    assert hits is None or waiting > 0  # the ways are being timed
    settle(wow)
    hits, waiting = wow.eval("g:Activities({ minutes = 10, by = 'gold' })")
    rows = [(h.ref, h.kind, h.gold is not None, h.xp is not None) for h in hits.values()]
    # the farm earns most gold, the run less; the third has no time (no rate) and stands last;
    # the unreachable place is no candidate and nothing is still timed
    assert [r[0] for r in rows] == ["testthing:2", "testthing:1"]
    assert waiting == 0
    farm, run = hits[1], hits[2]
    assert farm.gold == 50000 * 3600 / (3600 + farm.seconds) and farm.xp is None
    assert abs(run.gold - 100 * 3600 / (60 + run.seconds)) < 1e-6
    assert run.seconds < farm.seconds
    # by XP the run leads; a short way limit leaves the far farm out
    first = wow.eval("g:Activities({ minutes = 10, by = 'xp' })")[0][1]
    assert first.ref == "testthing:1"
    near = wow.eval(f"g:Activities({{ minutes = {run.seconds / 60 + 0.01}, by = 'gold' }})")[0]
    assert [h.ref for h in near.values()] == ["testthing:1"]
    only = wow.eval("g:Activities({ minutes = 10, kinds = { spot = true } })")[0]
    assert [h.ref for h in only.values()] == ["testthing:2"]
    assert wow.errors == []


def test_a_run_without_a_time_is_listed_after_the_known_rates(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """Bastians:RegisterEntityType(Bastians:GetModule("Things"), { type = "testnear",
          name = function() return "Near" end,
          locations = function() return { { map = 9000, x = 0.425, y = 0.1 } } end })
        Bastians:RegisterFacet(Bastians:GetModule("Things"), { facet = "activity", types = { "testnear" },
          rule = function() return { kind = "quest", gives = { { kind = "xp", amount = 1 } } } end,
          list = function() return { "testnear:1" } end })"""
    )
    settle(wow)
    hits = wow.eval("g:Activities({ by = 'xp' })")[0]
    assert [h.ref for h in hits.values()] == ["testthing:1", "testnear:1", "testthing:2"]
    assert hits[2].xp is None  # unknown, never 0
    assert wow.errors == []


def test_quests_offer_their_quests_timed_from_the_next_place(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    wow.advance(0.3)
    reg = "Bastians:GetModule('Quests').Registrations"
    act = wow.eval(f"{reg}.QuestActivity('quest:176')")
    assert act.kind == "quest" and act.src == "estimate" and act.takes > 0
    gives = [(g.kind, g.amount, g.id, g.choice) for g in act.gives.values()]
    assert gives[0][0] == "xp" and gives[0][1] > 0
    assert ("copper", 150, None, None) in gives
    assert any(g[0] == "item" and g[3] for g in gives)  # the reward choice
    # the facet answers Quests' rule above Data's
    assert wow.eval("Bastians:Entity('quest:176'):Facet('activity').src") == "estimate"
    assert wow.eval(f"{reg}.QuestActivity('quest:999999')") is None
    refs = list(wow.eval(f"{reg}.ExploreQuests()").values())
    assert refs and all(r.startswith("quest:") for r in refs)
    log = wow.eval("Bastians:GetModule('Quests').State.log")
    for qid in log:
        assert f"quest:{qid}" in refs
    assert wow.errors == []


def test_gold_offers_its_farm_spots_by_the_hour(wow: WowRuntime):
    if wow.client != "forever":
        pytest.skip("Gold is Forever's only (tests/lua/gold/conftest.py)")
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(CORE, DATA, GOLD)
    wow.run_frames(10)
    spots = "Bastians:GetModule('Gold').Spots"
    act = wow.eval("Bastians:Entity('spot:1'):Facet('activity')")
    record = "Bastians:GetService('data'):Get('spot', select(2, Bastians.Entity.Parse('spot:1')))"
    gph, unknown = wow.eval(f"{spots}.GoldPerHour({record})")
    assert act.kind == "spot" and act.unpriced == unknown
    assert (act.gives[1].kind, act.gives[1].amount, act.gives[1].per) == ("copper", gph, "hour")
    # a spot without any price gives nothing known: no gold rate, never 0
    refuted = wow.eval("Bastians:Entity('spot:3'):Facet('activity')")
    assert len(refuted.gives) == 0
    refs = list(wow.eval("Bastians:FacetCandidates('activity')").values())
    assert "spot:1" in refs and "spot:3" in refs
    assert wow.errors == []


def test_the_explore_view_lists_rows_and_says_what_is_still_timed(wow: WowRuntime):
    boot(wow, CORE, DATA, "Bastians_Map", ROUTE)
    explore = "Bastians:GetModule('Route').Explore"
    rows, summary = wow.eval(f"{explore}.Build(10, 'gold')")
    assert "ways still being timed" in summary or summary == "Timing the ways from here..."
    settle(wow)
    rows, summary = wow.eval(f"{explore}.Build(10, 'gold')")
    assert strip(summary) == "2 things to do within 10 min"
    farm = rows[1]
    assert farm.ref == "testthing:2" and farm.valueKind == "money" and farm.value > 0
    assert farm.meta.startswith("farm spot, ") and " away" in farm.meta
    run = rows[2]
    assert run.meta.startswith("quest, ") and "XP/h" in run.meta  # the other rate in grey
    rows, _ = wow.eval(f"{explore}.Build(10, 'xp')")
    assert rows[1].ref == "testthing:1" and rows[1].value.endswith("XP/h")
    # the cap decides the order: XP below it, gold at it, XP when the client cannot tell
    assert wow.eval(f"{explore}.DefaultOrder()") == "xp"
    wow.execute("Mock.maxLevel = 1")
    assert wow.eval(f"{explore}.DefaultOrder()") == "gold"
    # without a host the command says the best rows in the chat
    wow.slash("/broute explore")
    assert any("things to do within" in line for line in wow.chat[-3:])
    assert wow.errors == []
