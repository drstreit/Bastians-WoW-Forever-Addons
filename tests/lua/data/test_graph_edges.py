"""The edges the packs declare (ADR 0070, data.md "The edge registry", packages QD2 and QD3):
the build's registry writes its rows into each pack's header, and `graph:Edges` answers every
one of them from either end with the same properties. A data contract test: the packs are the
real generator's, from a small world that stores a link in every form."""

from pathlib import Path

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def linked_world():
    from bastians_build.model import World

    w = World(client="forever", build="test", sources=[])
    w.add("zone", 1429, {"name": "Elwynn Forest"})
    w.add(
        "npc",
        1,
        {
            "name": "Seller",
            "loot": [[10, 45.5], [11]],
            "vendor": [[10, 260, 20, False, "classic"], [12, None, None, True, "fdb"]],
            "trainer": [[133, "Fireball", 1200, 0, 6, 0, "classic"]],
        },
    )
    w.add("npc", 3, {"name": "Other", "vendor": [[10, 300, 20, False, "classic"]]})
    w.add("object", 2, {"name": "Chest", "loot": [[12, 100.0]]})
    w.add(
        "quest",
        5,
        {
            "name": "All of it",
            "starts": ["npc:1", "object:2"],
            "ends": ["npc:1"],
            "pre": [6],
            "preAny": [7, 8],
            "excl": [9],
            "chain": 6,
            # two creatures count for the one kill objective; the item is the required one
            "objectives": [["slay", "npc:1", 0], ["slay", "npc:3", 0], ["loot", "npc:1", 0]],
            # the sword is made by a recipe: a recipe on the way is no link of `targets`
            "requiredItems": [[10, 3], [11, 1]],
            "gives": [[12, 1]],
            "rewards": {"money": 5, "items": [[10, 2]], "choices": [[11, 1], [12, 1]]},
        },
    )
    w.add("quest", 6, {"name": "Before", "starts": ["item:10"], "preAny": [7]})
    w.add("quest", 7, {"name": "First", "starts": ["npc:1"], "ends": ["object:2"]})
    w.add("quest", 8, {"name": "Or this", "starts": ["npc:3"]})
    w.add("quest", 9, {"name": "The other side", "starts": ["npc:3"], "excl": [5]})
    # Cloth is dropped by the seller and the chest; only the seller's loot lists it. And the
    # ways to it that are no drop, each kind an edge of its own (package QD3)
    w.add(
        "item",
        10,
        {
            "name": "Cloth",
            "drops": [["npc:1", 45.5, False], ["object:2"]],
            "ways": [
                ["container", "item:12", 5.0],
                ["make", "item:11", None, "object:2"],
                ["fish", "zone:1429", 50.0],
                ["skin", "npc:3", 60.0],
                ["pick", "npc:1"],
            ],
        },
    )
    w.add("item", 11, {"name": "Sword"})
    w.add("item", 12, {"name": "Key"})
    w.add("recipe", 20, {"name": "Bandage", "item": 11, "count": 3, "reagents": [[10, 2], [12]]})
    return w


def boot(wow: WowRuntime, tmp_path: Path):
    """The addon with the packs the real generator made of the linked world."""
    from bastians_build.build import build
    from bastians_build.config import load_config

    world = linked_world()
    result = build(world, load_config(), tmp_path)
    assert result.ok, result.problems
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in result.packs:
        if pack.pack.name in ("world", "quests", "items"):
            wow.execute(pack.path.read_text(encoding="utf-8"))
    wow.execute("Bastians.Deliver()")
    wow.run_frames(5)
    wow.execute('g = Bastians:GetService("graph")')
    return world


def expected(world) -> dict[tuple[str, str, str], list]:
    """What every end of every edge has to answer, from the build's own reading of the world:
    (edge, direction, ref) -> the links. An end answers what its own records store, and what the
    edge's index leads to; an edge without an index answers each end from that end's records."""
    from bastians_build import links

    out: dict[tuple[str, str, str], list] = {}
    for edge in links.EDGES:
        for part in edge.parts:
            ends = links.far_types(edge, part)
            for record_id, rec in world.records.get(part.on, {}).items():
                near = f"{part.on}:{record_id}"
                for far, props in links.part_links(rec, part):
                    if far.partition(":")[0] not in ends:
                        continue  # a step's `via` names a quest too: no link of the edge
                    here, there = ("out", "in") if part.side == "from" else ("in", "out")
                    out.setdefault((edge.name, here, near), []).append((far, props))
                    if edge.index:
                        out.setdefault((edge.name, there, far), []).append((near, props))
    return out


def answer(wow: WowRuntime, ref: str, edge: str, direction: str) -> list:
    got = wow.eval(f"g:Edges('{ref}', '{edge}', '{direction}')")
    return [(e.ref, dict(e.props.items())) for e in got.values()]


def same(a: list, b: list) -> bool:
    def key(link):
        return (link[0], sorted((k, str(v)) for k, v in link[1].items()))

    return sorted(a, key=key) == sorted(b, key=key)


def test_every_edge_answers_both_ways_with_the_same_properties(wow: WowRuntime, tmp_path: Path):
    from bastians_build import links

    world = boot(wow, tmp_path)
    want = expected(world)
    edges = {name for name, _, _ in want}
    assert edges == {e.name for e in links.EDGES}  # the world stores every edge of the registry
    for (edge, direction, ref), rows in sorted(want.items()):
        got = answer(wow, ref, edge, direction)
        assert same(got, rows), f"{edge} {direction} of {ref}: {got} is not {rows}"
    # both directions of every edge with an index were asked
    for e in links.EDGES:
        asked = {direction for name, direction, _ in want if name == e.name}
        assert asked == {"out", "in"}, e.name
    assert wow.errors == []


def test_single_links_read_as_the_spec_says(wow: WowRuntime, tmp_path: Path):
    boot(wow, tmp_path)
    # a quest and who needs it, with how
    assert answer(wow, "quest:5", "needs", "out") == [
        ("quest:6", {"all": True}),
        ("quest:7", {"any": True}),
        ("quest:8", {"any": True}),
    ]
    assert same(
        answer(wow, "quest:7", "needs", "in"),
        [("quest:5", {"any": True}), ("quest:6", {"any": True})],
    )
    # what a quest wants, and which quest wants a creature: the same properties on both ends.
    # The seller counts for the kill and is on the way to the cloth; the other one counts too
    wants = [
        ("npc:1", {"kind": "slay", "nth": 1}),
        ("npc:3", {"kind": "slay", "nth": 1}),
        ("item:10", {"kind": "get", "count": 3, "nth": 1}),
        ("npc:1", {"kind": "get", "nth": 1, "how": "loot", "via": True}),
        ("object:2", {"kind": "get", "nth": 1, "how": "loot", "via": True}),
        ("item:11", {"kind": "get", "count": 1, "nth": 2}),  # and not `recipe:20`, its way
    ]
    assert wow.eval("Bastians:GetService('data'):Get('quest', 5).steps[3][6][1]") == "recipe:20"
    assert same(answer(wow, "quest:5", "targets", "out"), wants)
    assert same(
        answer(wow, "npc:1", "targets", "in"),
        [
            ("quest:5", {"kind": "slay", "nth": 1}),
            ("quest:5", {"kind": "get", "nth": 1, "how": "loot", "via": True}),
        ],
    )
    assert answer(wow, "npc:3", "targets", "in") == [("quest:5", {"kind": "slay", "nth": 1})]
    # what the giver hands over; the ways to an item that are no drop, from both ends
    assert answer(wow, "item:12", "gives", "in") == [("quest:5", {"count": 1})]
    assert answer(wow, "item:10", "holds", "in") == [("item:12", {"chance": 5})]
    assert answer(wow, "item:12", "holds", "out") == [("item:10", {"chance": 5})]
    assert answer(wow, "item:10", "yields", "in") == [("item:11", {"at": "object:2"})]
    assert answer(wow, "zone:1429", "fished", "out") == [("item:10", {"chance": 50})]
    assert answer(wow, "item:10", "rewards", "in") == [("quest:5", {"count": 2})]
    assert answer(wow, "item:11", "rewards", "in") == [("quest:5", {"count": 1, "choice": True})]
    # an index older suites read, keyed by the far end's id
    assert same(
        answer(wow, "item:10", "sells", "in"),
        [
            ("npc:1", {"price": 260, "stack": 20, "limited": False}),
            ("npc:3", {"price": 300, "stack": 20, "limited": False}),
        ],
    )
    assert answer(wow, "quest:6", "chains", "in") == [("quest:5", {})]
    # a property from another field of the record; an unknown one stays out: it is not zero
    assert answer(wow, "item:11", "makes", "in") == [("recipe:20", {"count": 3})]
    assert answer(wow, "item:12", "uses", "in") == [("recipe:20", {})]
    assert answer(wow, "spell:133", "teaches", "in") == [
        ("npc:1", {"cost": 1200, "skill": 0, "level": 6})
    ]
    # stored at both ends, each end reads its own list: the chest's loot does not list the cloth;
    # who it is skinned and picked from is the item's side only, and says how
    assert same(
        answer(wow, "item:10", "drops", "in"),
        [
            ("npc:1", {"chance": 45.5}),
            ("object:2", {}),
            ("npc:3", {"chance": 60, "how": "skin"}),
            ("npc:1", {"how": "pick"}),
        ],
    )
    assert answer(wow, "object:2", "drops", "out") == [("item:12", {"chance": 100})]
    assert wow.errors == []


def test_what_is_no_end_of_an_edge_answers_empty_and_an_unknown_edge_nil(
    wow: WowRuntime, tmp_path: Path
):
    boot(wow, tmp_path)
    assert answer(wow, "zone:1429", "drops", "out") == []  # a zone drops nothing
    assert answer(wow, "npc:1", "needs", "out") == []
    assert answer(wow, "npc:999999", "drops", "out") == []  # no such record
    assert answer(wow, "item:999999", "sells", "in") == []
    assert wow.eval("g:Edges('npc:1', 'flies')") is None
    assert wow.eval("g:Edges('nonsense', 'drops')") is None
    assert wow.eval("g:Edges(nil, 'drops')") is None
    assert wow.errors == []


def test_a_pack_without_edges_answers_as_before(wow: WowRuntime, tmp_path: Path):
    """An edition from before the registry: the hand-written table answers, outward where it had
    no other direction. A later pack with `edges` is read again."""
    boot(wow, tmp_path)
    wow.execute(
        """kept = {}
        for name, pack in pairs(Bastians.Data.packs) do kept[name], pack.edges = pack.edges, nil end
        Bastians.Data.Graph.ResetEdges()"""
    )
    assert [e.ref for e in wow.eval("g:Edges('quest:5', 'needs')").values()] == [
        "quest:6",
        "quest:7",
        "quest:8",
    ]
    assert list(wow.eval("g:Edges('quest:7', 'needs', 'in')").values()) == []
    assert [e.ref for e in wow.eval("g:Edges('npc:1', 'starts')").values()] == [
        "quest:5",
        "quest:7",
    ]
    assert wow.eval("g:Edges('npc:1', 'flies')") is None
    wow.execute(
        """for name, pack in pairs(Bastians.Data.packs) do pack.edges = kept[name] end
        Bastians:Fire("BASTIANS_DATA_LOADED", "quests")"""
    )
    assert len(answer(wow, "quest:7", "needs", "in")) == 2
    assert wow.errors == []


def test_the_fixture_packs_declare_their_edges(wow: WowRuntime):
    """The committed packs of the fixture world are the generator's: the header names the edges
    of each pack's types and the index of each."""
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in ("world", "quests", "items"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.execute('g = Bastians:GetService("graph")')
    packs = wow.eval("Bastians.Data.packs")
    assert sorted(packs.quests.edges.keys()) == [
        "chains",
        "ends",
        "excludes",
        "gives",
        "needs",
        "rewards",
        "starts",
        "targets",
    ]
    assert sorted(packs.world.edges.keys()) == ["drops", "sells", "teaches"]
    assert sorted(packs["items"].edges.keys()) == [
        "drops",
        "fished",
        "holds",
        "makes",
        "uses",
        "yields",
    ]
    assert packs.quests.edges.targets.index == "edge.targets"
    # the registry's own indexes come as text and are compiled when first asked for; the ones
    # installed suites read stay tables
    assert wow.eval("type(Bastians.Data.packs.quests.index['edge.targets'])") == "string"
    assert wow.eval("type(Bastians.Data.packs.quests.index['quest.byGiver'])") == "table"
    assert wow.eval("Bastians:GetService('data'):Index('edge.targets', 'npc:448')[1]") == 176
    assert wow.eval("type(Bastians.Data.packs.quests.index['edge.targets'])") == "table"
    assert wow.eval("type(Bastians.Data.packs.quests.index['edge.rewards'])") == "string"
    # Hogger has the claw the quest wants (on the way to it), and the quest's choice names
    # its quest
    assert answer(wow, "npc:448", "targets", "in") == [
        ("quest:176", {"kind": "get", "nth": 1, "how": "loot", "via": True})
    ]
    assert answer(wow, "item:1931", "targets", "in") == [
        ("quest:176", {"kind": "get", "nth": 1, "count": 1})
    ]
    assert answer(wow, "item:1185", "rewards", "in") == [
        ("quest:176", {"count": 1, "choice": True})
    ]
    assert wow.errors == []
