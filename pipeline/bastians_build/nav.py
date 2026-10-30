"""The walk network (ADR 0025, route.md "Walk network"): the nodes the build knows (flight masters,
transport stops), the connector table (tunnels, bridges, gates, the inside of cities: what the
terrain cannot see), and the `nav` pack from the graphs `clientdump navgraph` wrote.

The pack holds one `navnet` record per continent: `nodes` "wx,wy;wx,wy;..." (world yards, 0.1),
`keys` { [node] = "flightpath:2" | "transport:id:stop" }, `edges` "a,b,len,swim;..." (1-based
nodes, yards), `paths` { [edge] = "wx,wy;..." } (the points between the two nodes). Strings keep
the file small; Route decodes a continent once, the paths only to draw a route. Deterministic.
"""

from __future__ import annotations

import json
import math
import re
import tomllib
from pathlib import Path

from bastians_build import __version__
from bastians_build.emit import HEADER, emit_pack

NAV_FIELDS = ["nodes", "keys", "edges", "paths"]
LINK_KINDS = frozenset({"tunnel", "bridge", "gate", "inside", "stairs", "path"})
KEYED = ("flightpath:", "transport:")
SNAP = 60  # yards a given node may move to reach walkable ground
LINK_SNAP = 40
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REF = re.compile(r"^(flightpath:\d+|transport:\d+:\d+)$")


class NavError(ValueError):
    pass


def num(value: float) -> str:
    """A coordinate or length to 0.1 yard, without a trailing zero."""
    text = f"{round(value, 1):.1f}"
    text = text[:-2] if text.endswith(".0") else text
    return "0" if text == "-0" else text


def nav_nodes(world) -> list[dict]:
    """The build's nodes with world yards: flight masters, the transport stops that have `world`
    points (a build without transforms has none; Route then joins them like the start) and the
    instance entrances."""
    out = []
    for fp_id, fp in sorted(world.records.get("flightpath", {}).items()):
        if (
            fp.get("continent") is not None
            and fp.get("wx") is not None
            and fp.get("wy") is not None
        ):
            node = {
                "id": f"flightpath:{fp_id}",
                "continent": fp["continent"],
                "wx": fp["wx"],
                "wy": fp["wy"],
            }
            if fp.get("wz") is not None:
                node["wz"] = fp["wz"]
            out.append(node)
    for t_id, t in sorted(world.records.get("transport", {}).items()):
        for i, w in enumerate(t.get("world") or [], 1):
            if w:
                out.append(
                    {"id": f"transport:{t_id}:{i}", "continent": w[0], "wx": w[1], "wy": w[2]}
                )
    # instance entrances from the places table (ADR 0026, W4): the world graph keys them
    for e_id, e in sorted(world.records.get("entrance", {}).items()):
        if e.get("continent") is not None and e.get("wx") is not None and e.get("wy") is not None:
            node = {
                "id": f"entrance:{e_id}",
                "continent": e["continent"],
                "wx": e["wx"],
                "wy": e["wy"],
            }
            if e.get("wz") is not None:
                node["wz"] = e["wz"]
            out.append(node)
    return out


def load_links(path: Path | None) -> list[dict]:
    """pipeline/config/nav_<client>.toml: `[[link]]` name, kind, continent, a, b (a point [wx, wy]
    or a node ref "flightpath:6" / "transport:3:1"), path (inner points, optional), verified."""
    if path is None or not path.is_file():
        return []
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    links, names = [], set()
    for i, raw in enumerate(data.get("link") or [], 1):
        where = f"{path.name} link {i}"
        name = raw.get("name")
        if not isinstance(name, str) or not SLUG.match(name) or name in names:
            raise NavError(f"{where}: name must be a unique lower-case slug, got {name!r}")
        names.add(name)
        if raw.get("kind") not in LINK_KINDS:
            raise NavError(f"{where}: kind must be one of {sorted(LINK_KINDS)}")
        if not isinstance(raw.get("continent"), int):
            raise NavError(f"{where}: continent (Map.db2 id) is required")
        ends = []
        for end in ("a", "b"):
            v = raw.get(end)
            if isinstance(v, str) and REF.match(v):
                ends.append(v)
            elif isinstance(v, list) and len(v) == 2 and all(isinstance(x, int | float) for x in v):
                ends.append([float(v[0]), float(v[1])])
            else:
                raise NavError(f"{where}: {end} must be [wx, wy] or a node ref")
        inner = raw.get("path") or []
        if not all(isinstance(p, list) and len(p) == 2 for p in inner):
            raise NavError(f"{where}: path must be a list of [wx, wy]")
        links.append(
            {
                "name": name,
                "kind": raw["kind"],
                "continent": raw["continent"],
                "a": ends[0],
                "b": ends[1],
                "path": [[float(p[0]), float(p[1])] for p in inner],
                "verified": bool(raw.get("verified", False)),
            }
        )
    return links


def graph_nodes(given: list[dict], links: list[dict], continent: int) -> list[dict]:
    """The nodes.json `clientdump navgraph` reads for one continent: the build's nodes, then the
    connector ends given as points."""
    out = [
        {"id": n["id"], "wx": n["wx"], "wy": n["wy"], "snap": SNAP}
        | ({"wz": n["wz"]} if n.get("wz") is not None else {})
        for n in given
        if n["continent"] == continent and n["id"].startswith(KEYED)  # entrances: navnet only
    ]
    for link in links:
        if link["continent"] != continent:
            continue
        for end in ("a", "b"):
            if isinstance(link[end], list):
                wx, wy = link[end]
                out.append(
                    {"id": f"link:{link['name']}:{end}", "wx": wx, "wy": wy, "snap": LINK_SNAP}
                )
    return out


def _dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def navnet(graph: dict, given: list[dict], links: list[dict], continent: int) -> list:
    """One continent's record from navgraph's JSON plus the connectors. A connector end that is a
    node ref, or that navgraph dropped (no walkable ground near it: inside a city in a building),
    becomes a node of its own at its given place."""
    nodes = [(n["id"], float(n["wx"]), float(n["wy"])) for n in graph["nodes"]]
    index = {nid: i for i, (nid, _, _) in enumerate(nodes)}
    where = {
        n["id"]: (float(n["wx"]), float(n["wy"])) for n in given if n["continent"] == continent
    }
    edges = [
        (e["a"], e["b"], float(e["len"]), float(e["swim"]), [tuple(p) for p in e.get("pts") or []])
        for e in graph["edges"]
    ]

    def node_for(link: dict, end: str) -> int:
        v = link[end]
        nid = v if isinstance(v, str) else f"link:{link['name']}:{end}"
        if nid not in index:
            if isinstance(v, list):
                pos = (v[0], v[1])
            elif nid in where:
                pos = where[nid]
            else:
                raise NavError(f"link {link['name']}: {nid} is not a node of continent {continent}")
            index[nid] = len(nodes)
            nodes.append((nid, pos[0], pos[1]))
        return index[nid]

    for link in links:
        if link["continent"] != continent:
            continue
        a, b = node_for(link, "a"), node_for(link, "b")
        pts = [(p[0], p[1]) for p in link["path"]]
        line = [nodes[a][1:], *pts, nodes[b][1:]]
        length = sum(_dist(line[i], line[i + 1]) for i in range(len(line) - 1))
        edges.append((a, b, length, 0.0, pts))
    node_text = ";".join(f"{num(wx)},{num(wy)}" for _, wx, wy in nodes)
    keys = {i + 1: nid for i, (nid, _, _) in enumerate(nodes) if nid.startswith(KEYED)}
    edge_text = ";".join(
        f"{a + 1},{b + 1},{num(length)},{num(swim)}" for a, b, length, swim, _ in edges
    )
    paths = {
        i + 1: ";".join(f"{num(x)},{num(y)}" for x, y in pts)
        for i, (_, _, _, _, pts) in enumerate(edges)
        if pts
    }
    return [node_text, keys, edge_text, paths]


def nav_pack(
    graphs: dict[int, dict], given: list[dict], links: list[dict], client: str, build: str
) -> dict:
    return {
        "version": __version__,
        "build": build,
        "client": client,
        "sources": ["client terrain (clientdump navgraph)", "nav connectors"],
        "schema": {"navnet": NAV_FIELDS},
        "navnet": {c: navnet(graphs[c], given, links, c) for c in sorted(graphs)},
        "names": {},
        "index": {},
    }


def emit_nav(
    graphs: dict[int, dict], given: list[dict], links: list[dict], client: str, build: str
) -> str:
    pack = nav_pack(graphs, given, links, client, build)
    counts = ", ".join(
        f"{c}: {graphs[c]['nodes'].__len__()} nodes, {len(graphs[c]['edges'])} edges"
        for c in sorted(graphs)
    )
    return emit_pack("nav", pack, comment=f"pack nav for {client}, build {build}; {counts}")


def stub(client: str) -> str:
    """Nav.lua when no graph was built: the TOC's file exists, it registers nothing."""
    return f"{HEADER}\n-- pack nav: no walk network in this {client} build (optional pack)\n"


def read_graphs(folder: Path) -> tuple[dict[int, dict], str | None]:
    """`<continent>.json` from tools/nav_build.py and its meta.json (the client build)."""
    graphs = {}
    for path in sorted(folder.glob("*.json")):
        if path.stem.isdigit():
            graphs[int(path.stem)] = json.loads(path.read_text(encoding="utf-8"))
    meta_path = folder / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.is_file() else {}
    return graphs, meta.get("build")
