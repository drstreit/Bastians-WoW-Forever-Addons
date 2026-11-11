"""The edge registry (ADR 0070, data.md "The edge registry", packages QD2 and QD3): a link is
declared once; its index for the other direction and the rows a pack's header carries come from
that declaration."""

import pytest

from bastians_build import derive, links
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.links import Edge, LinkError, Part
from bastians_build.model import World
from bastians_build.pack import index_names, pack_table


def linked_world() -> World:
    """Every form a link is stored in: refs, ids, one id, rows, a table inside a field, a
    property from another field, an edge stored at both ends, rows of one field that are
    several edges (`item.ways`), and a row with several far ends (a step)."""
    w = World(client="forever", build="test", sources=[])
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
            "objectives": [["slay", "npc:1", 0], ["loot", "item:10", 0, "npc:1"], ["object", None]],
            "rewards": {"money": 5, "items": [[10, 2]], "choices": [[11, 1], [12, 1]]},
            "gives": [[12, 1], [11]],
            "requiredItems": [[10, 3]],
            # steps as the resolver writes them (steps.py; a build resolves them again from
            # the rows above): two creatures count for the first; the second names who has
            # the item and a quest on the way; the third has no subject
            "steps": [
                [None, "slay", "npc:1", 8, None, None, None, None, 1, ["npc:3"]],
                [2, "get", "item:10", 3, "loot", ["npc:1", "quest:6"]],
                [None, "reach"],
            ],
        },
    )
    w.add("quest", 6, {"name": "Before", "starts": ["item:10"], "preAny": [7]})
    w.add(
        "item",
        10,
        {
            "name": "Cloth",
            "drops": [["npc:1", 45.5, False], ["object:2"]],
            "ways": [
                ["container", "item:12", 5.0],
                ["make", "item:11", None, "object:2"],
                ["make", "item:12"],
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


def of(world: World, name: str) -> list[tuple]:
    edge = next(e for e in links.EDGES if e.name == name)
    return list(links.links(world, edge))


def test_every_form_of_storage_gives_its_links_with_their_properties():
    w = linked_world()
    assert of(w, "starts") == [
        ("npc:1", "quest:5", {}),
        ("object:2", "quest:5", {}),
        ("item:10", "quest:6", {}),
    ]
    assert of(w, "needs") == [
        ("quest:5", "quest:6", {"all": True}),
        ("quest:5", "quest:7", {"any": True}),
        ("quest:5", "quest:8", {"any": True}),
        ("quest:6", "quest:7", {"any": True}),
    ]
    assert of(w, "excludes") == [("quest:5", "quest:9", {})]
    assert of(w, "chains") == [("quest:5", "quest:6", {})]
    # a step's subject with its numbers; every creature that counts for it; a step without
    # a subject is no link. Then what is on the way: who has the item (a quest on the way is
    # no creature, object or item, so no link of this edge)
    assert of(w, "targets") == [
        ("quest:5", "npc:1", {"kind": "slay", "count": 8, "nth": 1}),
        ("quest:5", "npc:3", {"kind": "slay", "count": 8, "nth": 1}),
        ("quest:5", "item:10", {"n": 2, "kind": "get", "count": 3}),
        ("quest:5", "npc:1", {"n": 2, "kind": "get", "how": "loot", "via": True}),
    ]
    assert of(w, "gives") == [("quest:5", "item:12", {"count": 1}), ("quest:5", "item:11", {})]
    assert of(w, "rewards") == [
        ("quest:5", "item:10", {"count": 2}),
        ("quest:5", "item:11", {"count": 1, "choice": True}),
        ("quest:5", "item:12", {"count": 1, "choice": True}),
    ]
    # stored at both ends: once per end; unknown stays out of the properties, it is not zero
    assert of(w, "drops") == [
        ("npc:1", "item:10", {"chance": 45.5}),
        ("npc:1", "item:11", {}),
        ("object:2", "item:12", {"chance": 100.0}),
        ("npc:1", "item:10", {"chance": 45.5}),
        ("object:2", "item:10", {}),
        # skinned and picked: the rows of `item.ways` of that kind, said in `how`
        ("npc:3", "item:10", {"chance": 60.0, "how": "skin"}),
        ("npc:1", "item:10", {"how": "pick"}),
    ]
    # the other kinds of way are edges of their own, from what the item comes of
    assert of(w, "holds") == [("item:12", "item:10", {"chance": 5.0})]
    assert of(w, "yields") == [
        ("item:11", "item:10", {"at": "object:2"}),
        ("item:12", "item:10", {}),
    ]
    assert of(w, "fished") == [("zone:1429", "item:10", {"chance": 50.0})]
    assert of(w, "sells") == [
        ("npc:1", "item:10", {"price": 260, "stack": 20, "limited": False}),
        ("npc:1", "item:12", {"limited": True}),
        ("npc:3", "item:10", {"price": 300, "stack": 20, "limited": False}),
    ]
    assert of(w, "teaches") == [("npc:1", "spell:133", {"cost": 1200, "skill": 0, "level": 6})]
    assert of(w, "makes") == [("recipe:20", "item:11", {"count": 3})]
    assert of(w, "uses") == [
        ("recipe:20", "item:10", {"count": 2}),
        ("recipe:20", "item:12", {}),
    ]
    assert links.counts(w)["drops"] == 7 and links.counts(w)["ends"] == 1


def test_the_index_of_an_edge_serves_the_direction_no_field_stores():
    w = linked_world()
    assert links.index(w, "quest.byGiver") == {"npc:1": [5], "object:2": [5], "item:10": [6]}
    assert links.index(w, "quest.byEnder") == {"npc:1": [5]}
    assert links.index(w, "edge.needs") == {"quest:6": [5], "quest:7": [5, 6], "quest:8": [5]}
    assert links.index(w, "edge.excludes") == {"quest:9": [5]}
    assert links.index(w, "edge.targets") == {"npc:1": [5], "npc:3": [5], "item:10": [5]}
    assert links.index(w, "edge.gives") == {"item:12": [5], "item:11": [5]}
    assert links.index(w, "edge.holds") == {"item:12": [10]}
    assert links.index(w, "edge.yields") == {"item:11": [10], "item:12": [10]}
    assert links.index(w, "edge.fished") == {"zone:1429": [10]}
    assert links.index(w, "edge.rewards") == {"item:10": [5], "item:11": [5], "item:12": [5]}
    assert links.index(w, "edge.teaches") == {"spell:133": [1]}
    assert links.index(w, "edge.makes") == {"item:11": [20]}
    assert links.index(w, "edge.uses") == {"item:10": [20], "item:12": [20]}
    # the indexes installed suites read keep their names and their keys: the far end's id
    assert links.index(w, "quest.chainFrom") == {6: [5]}
    assert links.index(w, "npc.bySoldItem") == {10: [1, 3], 12: [1]}
    # the build asks the registry for an edge's index, and says what it knows otherwise
    assert derive.build_index(w, "edge.uses") == links.index(w, "edge.uses")
    with pytest.raises(KeyError, match=r"edge\.needs.*quest\.byZone"):
        derive.build_index(w, "edge.nothing")


def test_a_packs_header_carries_the_rows_of_its_types():
    quests = links.manifest({"quest", "attunement"})
    assert set(quests) == {
        "starts",
        "ends",
        "needs",
        "excludes",
        "chains",
        "targets",
        "gives",
        "rewards",
    }
    assert quests["needs"] == {
        "from": ["quest"],
        "to": ["quest"],
        "index": "edge.needs",
        "key": "ref",
        "parts": [
            {"on": "quest", "field": "pre", "form": "ids", "side": "from", "far": "quest"}
            | {"const": {"all": True}},
            {"on": "quest", "field": "preAny", "form": "ids", "side": "from", "far": "quest"}
            | {"const": {"any": True}},
        ],
    }
    assert quests["starts"]["parts"] == [
        {"on": "quest", "field": "starts", "form": "refs", "side": "to"}
    ]
    assert quests["targets"]["parts"] == [
        {
            "on": "quest",
            "field": "steps",
            "form": "rows",
            "side": "from",
            "ref": 3,
            "props": {"n": 1, "kind": 2, "count": 4, "nth": 9},
            "many": 10,
        },
        {
            "on": "quest",
            "field": "steps",
            "form": "rows",
            "side": "from",
            "ref": 0,  # no far end of its own: those of `via`
            "props": {"n": 1, "kind": 2, "nth": 9, "how": 5},
            "const": {"via": True},
            "many": 6,
        },
    ]
    # an edge stored in two packs is in both, each with its own parts and no index
    world, items = links.manifest({"npc", "object", "zone"}), links.manifest({"item", "recipe"})
    assert [p["on"] for p in world["drops"]["parts"]] == ["npc", "object"]
    assert [p["on"] for p in items["drops"]["parts"]] == ["item", "item", "item"]
    assert items["drops"]["parts"][1]["when"] == [1, "skin"]  # the rows of `ways` that are it
    assert items["holds"]["parts"] == [
        {"on": "item", "field": "ways", "form": "rows", "side": "to", "ref": 2}
        | {"props": {"chance": 3}, "when": [1, "container"]}
    ]
    assert items["yields"]["index"] == "edge.yields" and items["fished"]["from"] == ["zone"]
    assert "index" not in world["drops"] and "index" not in items["drops"]
    assert items["makes"]["parts"][0]["also"] == {"count": "count"}
    assert world["sells"]["key"] == "id" and world["sells"]["index"] == "npc.bySoldItem"
    assert links.manifest({"price", "signal"}) == {}
    assert links.indexes_for({"recipe", "item"}) == [
        "edge.holds",
        "edge.yields",
        "edge.fished",
        "edge.makes",
        "edge.uses",
    ]


def test_the_pack_gets_the_edges_indexes_without_a_line_in_the_configuration():
    config = load_config()
    names = index_names(config.packs["quests"])
    assert names[: len(config.packs["quests"].indexes)] == config.packs["quests"].indexes
    assert {"edge.needs", "edge.excludes", "edge.targets", "edge.rewards"} <= set(names)
    assert len(names) == len(set(names))  # one build.toml names already is not there twice
    # every index of the registry is in exactly one pack
    homes = {
        n: [p for p, cfg in config.packs.items() if n in index_names(cfg)] for n in links.BY_INDEX
    }
    assert all(len(packs) == 1 for packs in homes.values()), homes
    table = pack_table(linked_world(), config.packs["quests"])
    assert table["index"]["edge.targets"] == {"npc:1": [5], "npc:3": [5], "item:10": [5]}
    assert table["edges"]["chains"]["index"] == "quest.chainFrom"
    assert "edges" not in pack_table(linked_world(), config.packs["market"])


def test_the_report_lists_every_edge_with_its_links_and_its_index(tmp_path):
    result = build(linked_world(), load_config(), tmp_path)
    assert result.ok
    report = result.report
    assert "## Links" in report
    row = next(line for line in report.splitlines() if line.startswith("| needs |"))
    assert row.split(" | ")[1:6] == ["quest", "quest", "4", "edge.needs", "3"]
    assert row.rstrip(" |").endswith("KB")
    drops = next(line for line in report.splitlines() if line.startswith("| drops |"))
    assert "stored at both ends" in drops and "| 7 |" in drops
    # the build resolves the steps itself (steps.py) and says how they came out
    assert "## Quest steps" in report and "2 steps in 1 of 2 quests." in report


def test_the_registrys_own_indexes_go_out_as_text(tmp_path):
    """Compiled when first asked for, as the records are: nobody pays for a direction nobody
    asks about. The indexes installed suites read stay tables."""
    assert {
        "edge.needs",
        "edge.excludes",
        "edge.targets",
        "edge.gives",
        "edge.rewards",
        "edge.holds",
        "edge.yields",
        "edge.fished",
        "edge.teaches",
        "edge.makes",
        "edge.uses",
    } == links.LAZY
    result = build(linked_world(), load_config(), tmp_path)
    quests = next(p for p in result.packs if p.pack.name == "quests")
    text = quests.path.read_text(encoding="utf-8")
    # the build's own steps of the world: the creature, and the item with who has it
    as_text = '[=[{ ["item:10"] = { 5 }, ["npc:1"] = { 5 }, ["object:2"] = { 5 } }]=]'
    assert f'["edge.targets"] = {as_text},' in text
    assert '["quest.byGiver"] = {\n' in text
    assert quests.index_counts["edge.targets"] == 3  # counted as keys, whatever its form
    assert quests.index_bytes["edge.targets"] == len(as_text)


def test_a_row_that_cannot_be_read_without_a_special_case_is_refused():
    part = Part("quest", "pre", "ids", far="quest")
    good = Edge("needs", ("quest",), ("quest",), (part,), index="edge.needs")
    links.check((good,))
    bad = {
        "declared twice": (good, good),
        "stored nowhere": (Edge("x", ("quest",), ("quest",), (), index="i"),),
        "an index or the reason": (Edge("x", ("quest",), ("quest",), (part,)),),
        "unknown key": (Edge("x", ("quest",), ("quest",), (part,), index="i", key="name"),),
        "unknown form or side": (
            Edge("x", ("quest",), ("quest",), (Part("quest", "pre", "list"),), index="i"),
        ),
        "is no from end": (Edge("x", ("npc",), ("quest",), (part,), index="i"),),
        "is no far end": (
            Edge("x", ("quest",), ("npc",), (Part("quest", "pre", "ids", far="quest"),), index="i"),
        ),
        "ids of no named type": (
            Edge("x", ("quest",), ("quest",), (Part("quest", "pre", "ids"),), index="i"),
        ),
        "serves two edges": (good, Edge("y", ("quest",), ("quest",), (part,), index="edge.needs")),
        "only rows have": (
            Edge(
                "x",
                ("quest",),
                ("quest",),
                (Part("quest", "pre", "ids", far="quest", when=(1, "a")),),
                index="i",
            ),
        ),
        "on one type and side": (
            Edge(
                "x",
                ("npc", "object"),
                ("item",),
                (
                    Part("npc", "loot", "rows", far="item"),
                    Part("object", "loot", "rows", far="item"),
                ),
                index="i",
            ),
        ),
        "an id key needs one far type": (
            Edge(
                "x",
                ("quest",),
                ("npc", "object"),
                (Part("quest", "objectives", "rows", ref=2),),
                index="i",
                key="id",
            ),
        ),
    }
    for reason, rows in bad.items():
        with pytest.raises(LinkError, match=reason):
            links.check(rows)
