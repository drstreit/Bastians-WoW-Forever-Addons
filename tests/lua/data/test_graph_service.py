"""The world graph's service (ADR 0026, data.md "The world graph"), step 1: places, what is
around, the named edges, facets, profiles, the character and what it learned; the network's
answers are nil until the nav pack carries the network."""

from itertools import pairwise

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in ("world", "quests", "items"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.execute('g = Bastians:GetService("graph")')
    return wow


def refs(answer) -> list[str]:
    return sorted(e.ref for e in answer.values())


def test_the_service_is_there_and_says_it_has_no_network_yet(wow: WowRuntime):
    boot(wow)
    assert wow.eval("g ~= nil") is True
    assert wow.eval("g:Ready(0)") is False
    assert wow.eval("g:Time('npc:448')") is None
    assert wow.eval("g:Nearest('rest.inn', 3)") is None
    wow.execute("why = nil; g:Route('player', 'npc:448', {}, function(r, reason) why = reason end)")
    assert wow.eval("why") == "no network"


def test_places_and_what_is_around(wow: WowRuntime):
    boot(wow)
    places = list(wow.eval("g:Place('npc:327')").values())
    assert places[0].wz == 41.3 and places[0].src == "classic"
    assert wow.eval("g:Place('npc:999999')") is None
    assert wow.eval("g:Place('nonsense')") is None
    here = "g:Place('npc:295')[1]"  # Innkeeper Farley
    around = list(wow.eval(f"g:Around({here}, nil, 50)").values())
    assert around[0].ref == "npc:295" and around[0].yards == 0
    assert all(a.yards <= b.yards for a, b in pairwise(around))
    inns = list(wow.eval(f"g:Around({here}, {{ roles = {{ 'rest.inn' }} }})").values())
    assert [a.ref for a in inns] == ["npc:295"]


def test_the_named_edges_in_both_directions(wow: WowRuntime):
    boot(wow)
    # Hogger drops Linen Cloth; the cloth names its droppers
    drops = wow.eval("g:Edges('npc:448', 'drops')")
    assert "item:2589" in refs(drops)
    assert [e.props.chance for e in drops.values() if e.ref == "item:2589"] == [45.5]
    assert refs(wow.eval("g:Edges('item:2589', 'drops', 'in')")) == ["npc:327", "npc:448"]
    # a giver starts its quests; a quest names its givers
    givers = wow.eval(
        """(function()
          local data = Bastians:GetService("data")
          for _, id in ipairs(data:Each("quest")) do
            local r = data:Get("quest", id)
            if r.starts and r.starts[1] then return id, r.starts[1] end
          end
        end)()"""
    )
    quest_id, giver = givers
    assert f"quest:{quest_id}" in refs(wow.eval(f"g:Edges('{giver}', 'starts')"))
    assert giver in refs(wow.eval(f"g:Edges('quest:{quest_id}', 'starts', 'in')"))
    # the recipe makes its item from its reagents
    assert refs(wow.eval("g:Edges('recipe:2152', 'makes')")) == ["item:2304"]
    assert refs(wow.eval("g:Edges('recipe:2152', 'uses')")) == ["item:2318"]
    # unknown edge: nil; a direction the type lacks: empty; an unloaded record: empty
    assert wow.eval("g:Edges('npc:448', 'flies')") is None
    assert refs(wow.eval("g:Edges('zone:1429', 'drops')")) == []
    assert refs(wow.eval("g:Edges('npc:999999', 'drops')")) == []


def test_learned_facts_are_kept_and_announced(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """parts = {}
        Bastians:NewModule("Listener", { addon = "Bastians_TestApp" }):On("BASTIANS_GRAPH_CHANGED",
          function(_, _, part) parts[#parts + 1] = part end)"""
    )
    assert wow.eval(
        "g:Learn({ kind = 'taxi', from = 'taxinode:6', to = 'taxinode:2', seconds = 211 })"
    )
    assert wow.eval("BastiansDataDB.global.learned.taxi['taxinode:6>taxinode:2']") == 211
    assert wow.eval("g:Learn({ kind = 'taxi', from = 'taxinode:6', to = 'taxinode:2' })") is False
    assert wow.eval("g:Learn({ kind = 'teleport' })") is False
    assert wow.eval("g:Learn({ kind = 'ride', ref = 'transport:1', wait = 42 })") is True
    wow.execute("Bastians.Data.Graph.WALKS_KEPT = 2")
    for n in range(3):
        wow.execute(
            f"g:Learn({{ kind = 'walk', map = 0, points = {{ {{ 0, {n} }}, {{ 1, {n} }} }} }})"
        )
    walks = wow.eval("BastiansDataDB.global.learned.walk")
    assert len(walks) == 2 and walks[1].points[1][2] == 1  # the oldest went (W11: { map, points })
    assert list(wow.eval("parts").values()) == ["learned"] * 5
    assert wow.eval("g:Character().taxi ~= nil") is True


def test_profiles_include_the_extensions(wow: WowRuntime):
    boot(wow)
    assert list(wow.eval("g:Profiles()").values()) == ["fastest", "noswim", "safe", "nocost"]
    wow.execute(
        """Bastians:RegisterGraphExtension(Bastians:NewModule("Ext", { addon = "Bastians_TestApp" }),
          { ns = "gp", profiles = { avoidHorde = function() return nil end } })"""
    )
    assert list(wow.eval("g:Profiles()").values()) == [
        "fastest",
        "noswim",
        "safe",
        "nocost",
        "gp.avoidHorde",
    ]
