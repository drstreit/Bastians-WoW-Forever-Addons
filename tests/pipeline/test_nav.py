"""The walk network pack (route.md "Walk network", ADR 0025): the nodes the build hands to the
graph, the connector table, the pack from navgraph's JSON (golden, deterministic), and the stub."""

import json
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.model import World
from bastians_build.nav import (
    NavError,
    emit_nav,
    graph_nodes,
    load_links,
    nav_nodes,
    navnet,
    num,
    read_graphs,
)

ROOT = Path(__file__).resolve().parents[2]
MINI = ROOT / "tests" / "fixtures" / "nav-mini"
GOLDEN = ROOT / "tests" / "fixtures" / "addons" / "Bastians_Data_Nav" / "Generated" / "Nav.lua"
HINT = (
    "regenerate with: python -m bastians_build nav --client forever "
    "--graphs tests/fixtures/nav-mini "
    "--nodes tests/fixtures/nav-mini/nodes.json --links tests/fixtures/nav-mini/links.toml "
    "--out tests/fixtures/addons"
)


def mini():
    graphs, build = read_graphs(MINI)
    given = json.loads((MINI / "nodes.json").read_text(encoding="utf-8"))
    return graphs, build, given, load_links(MINI / "links.toml")


def test_numbers_keep_a_tenth_of_a_yard():
    assert [num(v) for v in (800.0, 1000.24, -0.04, -12.35, 3.0)] == [
        "800",
        "1000.2",
        "0",
        "-12.3",
        "3",
    ]


def test_the_build_hands_flight_masters_with_height_and_transport_stops():
    world = World(client="forever")
    world.add("flightpath", 6, {"continent": 0, "wx": -4821.78, "wy": -1155.44, "wz": 501.7})
    world.add("flightpath", 7, {"continent": 0, "wx": 1.0, "wy": 2.0})
    world.add("flightpath", 8, {"continent": None, "wx": 1.0, "wy": 2.0})  # unknown: not a node
    world.add("transport", 3, {"world": [[0, 10.0, 20.0], [369, 5.0, 6.0]]})
    world.add("transport", 4, {"world": None})  # no transforms in that build
    world.add("entrance", "36-1", {"continent": 0, "wx": -11208.7, "wy": 1675.9, "wz": 24.6})
    nodes = nav_nodes(world)
    assert [n["id"] for n in nodes] == [
        "flightpath:6",
        "flightpath:7",
        "transport:3:1",
        "transport:3:2",
        "entrance:36-1",
    ]
    assert nodes[-1]["wz"] == 24.6
    assert nodes[0]["wz"] == 501.7 and "wz" not in nodes[1]
    given = graph_nodes(nodes, [], 0)
    assert [n["id"] for n in given] == ["flightpath:6", "flightpath:7", "transport:3:1"]
    assert given[0]["wz"] == 501.7 and given[0]["snap"] == 60


def test_connector_ends_become_nodes_and_bad_rows_are_refused(tmp_path):
    _, _, given, links = mini()
    assert [link["name"] for link in links] == ["fixture-tunnel", "fixture-gate"]
    nodes = graph_nodes(given, links, 530)
    assert [n["id"] for n in nodes][-2:] == ["link:fixture-tunnel:a", "link:fixture-tunnel:b"]
    assert nodes[-1]["snap"] == 40
    bad = tmp_path / "nav.toml"
    for row, message in (
        ('name = "Bad Name"\nkind = "gate"\ncontinent = 0\na = [0, 0]\nb = [1, 1]', "slug"),
        ('name = "x"\nkind = "teleport"\ncontinent = 0\na = [0, 0]\nb = [1, 1]', "kind"),
        ('name = "x"\nkind = "gate"\na = [0, 0]\nb = [1, 1]', "continent"),
        ('name = "x"\nkind = "gate"\ncontinent = 0\na = "npc:5"\nb = [1, 1]', "node ref"),
    ):
        bad.write_text("[[link]]\n" + row + "\n", encoding="utf-8")
        with pytest.raises(NavError, match=message):
            load_links(bad)
    assert load_links(tmp_path / "missing.toml") == []


def test_the_record_holds_nodes_keys_edges_and_paths():
    graphs, _, given, links = mini()
    nodes, keys, edges, paths = navnet(graphs[530], given, links, 530)
    # navgraph's four nodes, the tunnel's far end it dropped, the dropped flight master by its ref
    assert nodes == "0,0;800,0;800,1000;0,1000;0,2000;900,-500"
    assert keys == {1: "flightpath:900", 6: "flightpath:901"}
    assert edges.split(";") == [
        "1,2,800,0",
        "2,3,1000,100",
        "3,4,800,0",
        "4,5,1000.2,0",
        "1,6,1029.6,0",
    ]
    assert paths == {1: "400,-20", 2: "820,500", 4: "-10,1500"}
    unknown = [{**links[1], "b": "flightpath:999"}]
    with pytest.raises(NavError, match="flightpath:999"):
        navnet(graphs[530], given, unknown, 530)


def test_committed_golden_nav_pack_matches_a_fresh_build(tmp_path):
    """The Lua tests load exactly what the generator produces (data.md acceptance 1)."""
    graphs, build, given, links = mini()
    text = emit_nav(graphs, given, links, "forever", build)
    assert text == emit_nav(graphs, given, links, "forever", build)  # deterministic
    assert GOLDEN.is_file(), HINT
    assert text == GOLDEN.read_text(encoding="utf-8"), HINT
    out = tmp_path / "addons"
    args = [
        "nav",
        "--client",
        "forever",
        "--graphs",
        str(MINI),
        "--nodes",
        str(MINI / "nodes.json"),
        "--links",
        str(MINI / "links.toml"),
        "--navnet",
        str(tmp_path / "no-levels"),
        "--out",
        str(out),
    ]
    assert main(args) == 0
    assert (out / "Bastians_Data_Nav" / "Generated" / "Nav.lua").read_text(encoding="utf-8") == text


def test_without_graphs_the_pack_is_a_stub(tmp_path, capsys):
    out = tmp_path / "addons"
    assert (
        main(
            [
                "nav",
                "--client",
                "retail",
                "--graphs",
                str(tmp_path / "none"),
                "--navnet",
                str(tmp_path / "none"),
                "--out",
                str(out),
            ]
        )
        == 0
    )
    text = (out / "Bastians_Data_Nav" / "Generated" / "Nav.lua").read_text(encoding="utf-8")
    assert "RegisterPack" not in text and "no walk network in this retail build" in text
    assert "wrote the stub" in capsys.readouterr().out


def test_local_levels_add_the_world_graph_record(tmp_path):
    """ADR 0026, W3b: with clientdump navnet's local levels the pack carries `graph` per continent,
    beside the ADR 0025 network Route still reads until W8."""
    out = tmp_path / "addons"
    report = tmp_path / "build"
    report.mkdir()
    (report / "nav-nodes-forever.json").write_text(
        '[{"id": "flightpath:2", "continent": 0, "wx": 100, "wy": 300}]', encoding="utf-8"
    )
    (report / "nav-taxi-forever.json").write_text(
        '[{"id": 12, "from": 6, "to": 2, "continent": 0, "length": 6310.0}]', encoding="utf-8"
    )
    navnet = Path(__file__).resolve().parents[1] / "fixtures" / "navnet-mini"
    args = [
        "nav",
        "--client",
        "forever",
        "--graphs",
        str(tmp_path / "none"),
        "--nodes",
        str(report / "nav-nodes-forever.json"),
        "--links",
        str(MINI / "links.toml"),
        "--navnet",
        str(navnet),
        "--corrections",
        str(tmp_path / "no-corrections.toml"),  # the shipped rows lie off the fixture's level
        "--out",
        str(out),
    ]
    assert main(args) == 0
    text = (out / "Bastians_Data_Nav" / "Generated" / "Nav.lua").read_text(encoding="utf-8")
    assert "graph = {" in text and '"1,4"' in text  # the west cluster's waypoint range
    assert "6 waypoints, 7 ways" in text.splitlines()[1]
    # the taxi path's nodes: 6 is no known flight master here, so the path is left out
    assert 'taxi = ""' in text
