"""The world graph's network pack (ADR 0026, W3b; data.md "The build in two halves").

In: the local level `clientdump navnet` writes per continent (waypoints, ways with their facts and
bends, anchors), the danger points the data build writes (hostile spawns and guards in world
yards) and the client's taxi paths. Out: the `graph` record of the nav pack per continent:

- waypoints numbered contiguously per cluster (a cluster is a block of 2 x 2 ADT tiles,
  coordinates.md "Clusters"), so a cluster is a range of waypoint numbers;
- per cluster one string of waypoints, one of the ways that start in it, one of their bends;
- the region level: per cluster the best path between each pair of its region nodes (its borders
  and its keyed nodes) for each base profile (`fastest`, `noswim`), as summed facts;
- the keys (waypoint -> taxinode / transport stop / entrance), the anchors per thing type and the
  taxi paths of the continent.

Ways store facts, not seconds (world-graph.md §3.4): the profiles here only choose which path the
region level keeps; the runtime turns facts into seconds with the character's speeds. `safe`
depends on the character's level and is a runtime profile (25.10.2026).
Pure and deterministic: same inputs, same strings.
"""

from __future__ import annotations

import heapq
import json
import math
from dataclasses import dataclass, field
from itertools import pairwise
from pathlib import Path

TILE = 1600 / 3  # yards per ADT tile (coordinates.md)
CLUSTER_TILES = 2
RUN_SPEED = 7.0  # yards a second on foot (the runtime uses the character's)
SWIM_SPEED = 4.7  # as Route's planner (route.md)
ROAD_BONUS = 0.9  # a road yard costs this much of an open yard: paths keep to roads
NOSWIM_FACTOR = 20.0  # noswim: a swum yard costs this many times more
AGGRO = 20.0  # yards from a way within which a hostile spawn counts as its danger
DOMINATED = 0.01  # a region edge a -> b goes when a -> m -> b is at most this much slower
BEND_TOLERANCE = 2.0  # yards: the bends are for drawing (Douglas-Peucker, 2D)
KINDS = {"road": "r", "ground": "g", "node": "n", "door": "d"}
PROFILES = ("f", "n")  # fastest, noswim
FACTS = ("len", "road", "swim", "up", "down", "indoor")
LOCAL_VERSION = 1
JOIN_CELLS = 32 * 32  # cells of a cluster in the join field, 33 yards each


class NavnetError(ValueError):
    pass


def num(value: float) -> str:
    """A coordinate or length to 0.1 yard, without a trailing zero."""
    text = f"{round(value, 1):.1f}"
    text = text[:-2] if text.endswith(".0") else text
    return "0" if text == "-0" else text


def yd(value: float) -> str:
    """Whole yards (the pack's precision since the first real build, 25.10.2026)."""
    text = str(round(value))
    return "0" if text == "-0" else text


def simplify(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    """Douglas-Peucker on 2D points, keeping both ends."""
    if len(points) < 3:
        return list(points)
    (ax, ay), (bx, by) = points[0], points[-1]
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    far, worst = 0, -1.0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        if length == 0:
            d = math.hypot(px - ax, py - ay)
        else:
            d = abs(dy * (px - ax) - dx * (py - ay)) / length
        if d > worst:
            far, worst = i, d
    if worst <= tolerance:
        return [points[0], points[-1]]
    left = simplify(points[: far + 1], tolerance)
    return left[:-1] + simplify(points[far:], tolerance)


def tile_of(wx: float, wy: float) -> tuple[int, int]:
    """(tx, ty) of the ADT tile holding the point: tx grows east (falling wy), ty south."""
    return math.floor(32 - wy / TILE), math.floor(32 - wx / TILE)


def cluster_of(wx: float, wy: float) -> int:
    tx, ty = tile_of(wx, wy)
    return (tx // CLUSTER_TILES) * 32 + ty // CLUSTER_TILES


# --- the local level ------------------------------------------------------------------------


@dataclass
class Waypoint:
    id: int
    x: float
    y: float
    z: float
    kind: str
    key: str | None
    area: int | None


@dataclass
class Way:
    a: int
    b: int
    facts: dict[str, float]
    oneway: bool
    area: int | None
    points: list[tuple[float, float, float]]
    danger: int | None = None  # the highest level of hostile spawns along it; None: none
    elite: bool = False
    guards: str = ""  # the factions whose guards stand along it: "", "A", "H", "AH"


@dataclass
class Anchor:
    ref: str
    i: int
    wp: int
    len: float


@dataclass
class LocalLevel:
    client: str
    build: str
    continent: int
    waypoints: list[Waypoint]
    ways: list[Way]
    anchors: list[Anchor]
    unanchored: list[dict] = field(default_factory=list)
    join: list[int] = field(default_factory=list)  # flat col, row, waypoint id


def _xyz(p, where: str) -> tuple[float, float, float]:
    if not (isinstance(p, list) and len(p) == 3 and all(isinstance(v, int | float) for v in p)):
        raise NavnetError(f"{where}: a point must be [x, y, z]")
    return float(p[0]), float(p[1]), float(p[2])


def read_local(path: Path) -> LocalLevel:
    """The JSON `clientdump navnet` writes, validated against the interface (data.md)."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    if raw.get("version") != LOCAL_VERSION:
        raise NavnetError(f"{path.name}: version {raw.get('version')!r}, expected {LOCAL_VERSION}")
    waypoints, ids = [], set()
    for w in raw.get("waypoints") or []:
        where = f"{path.name} waypoint {w.get('id')}"
        if not isinstance(w.get("id"), int) or w["id"] in ids:
            raise NavnetError(f"{where}: id missing or twice")
        if w.get("kind") not in KINDS:
            raise NavnetError(f"{where}: kind {w.get('kind')!r}")
        x, y, z = _xyz([w.get("x"), w.get("y"), w.get("z")], where)
        ids.add(w["id"])
        key = w.get("key")
        if isinstance(key, str) and key.startswith("flightpath:"):
            key = "taxinode:" + key[len("flightpath:") :]  # the data build's nodes (ADR 0025 names)
        waypoints.append(Waypoint(w["id"], x, y, z, w["kind"], key, w.get("area")))
    ways = []
    for n, e in enumerate(raw.get("ways") or [], 1):
        where = f"{path.name} way {n}"
        if e.get("a") not in ids or e.get("b") not in ids or e["a"] == e["b"]:
            raise NavnetError(f"{where}: a and b must be two known waypoints")
        facts = {}
        for f in FACTS:
            v = e.get(f)
            if not isinstance(v, int | float) or v < 0:
                raise NavnetError(f"{where}: {f} must be a number of yards >= 0")
            facts[f] = float(v)
        points = [_xyz(p, where) for p in e.get("points") or []]
        ways.append(Way(e["a"], e["b"], facts, bool(e.get("oneway")), e.get("area"), points))
    anchors = []
    for a in raw.get("anchors") or []:
        if a.get("wp") not in ids or not isinstance(a.get("ref"), str):
            raise NavnetError(f"{path.name} anchor {a.get('ref')}: unknown waypoint")
        anchors.append(Anchor(a["ref"], int(a.get("i") or 1), a["wp"], float(a.get("len") or 0)))
    return LocalLevel(
        str(raw.get("client")),
        str(raw.get("build")),
        int(raw.get("continent")),
        waypoints,
        ways,
        anchors,
        list(raw.get("unanchored") or []),
        [int(v) for v in raw.get("join") or []],
    )


# --- danger ---------------------------------------------------------------------------------

RANKS = frozenset({"elite", "rareelite", "boss", "rare"})


def _flags(rec: dict) -> list[str]:
    flags = rec.get("flags")
    if flags is None:
        return []
    return [flags] if isinstance(flags, str) else list(flags)


def _world(transforms: dict, spawn: list) -> tuple[int, float, float] | None:
    t = transforms.get(spawn[0])
    if t is None:
        return None
    x, y = spawn[1], spawn[2]
    return t.continent, t.wx0 + x * t.wx_dx + y * t.wx_dy, t.wy0 + x * t.wy_dx + y * t.wy_dy


def danger_points(world, transforms: dict | None) -> dict:
    """Hostile spawns (an NPC without a service, a faction or a quest to give, with a level: the
    Monsters rule of data.md) and guards (an NPC of a faction whose name or subname says Guard),
    in world yards per continent: {"hostile": [[c, wx, wy, level, elite]], "guards": [[c, wx, wy,
    "A"|"H"]]}. Without transforms no spawn has a world position: both lists are empty."""
    hostile, guards = [], []
    if not transforms:
        return {"hostile": hostile, "guards": guards}
    for _, rec in sorted(world.records.get("npc", {}).items()):
        flags = _flags(rec)
        services = [f for f in flags if f not in RANKS]
        text = f"{rec.get('name') or ''} {rec.get('subname') or ''}"
        side = rec.get("faction")
        is_guard = side in ("A", "H") and "Guard" in text
        # hostile: the client's FactionTemplate says so where known (neutral beasts and
        # critters are no danger, R26.5); unknown keeps the Monsters rule
        known = rec.get("hostile")
        is_hostile = rec.get("level") and not side and not services and known is not False
        if not (is_guard or is_hostile):
            continue
        for spawn in rec.get("spawns") or []:
            w = _world(transforms, spawn)
            if w is None:
                continue
            c, wx, wy = w
            if is_guard:
                guards.append([c, round(wx, 1), round(wy, 1), side])
            else:
                elite = any(f in RANKS for f in flags)
                hostile.append([c, round(wx, 1), round(wy, 1), int(rec["level"]), elite])
    return {"hostile": hostile, "guards": guards}


def tdb_danger(tdb) -> dict:
    """The hostile spawns and guards of TrinityCore's retail database (sources/tdb.py), in the
    shape of danger_points; the positions are world yards already, the map id is the continent.
    A creature that scales counts at the lowest level of its band (retail creatures scale with the
    player inside it, so only a character below the band meets a stronger one); an elite counts as
    in the Monsters rule."""
    hostile, guards = [], []
    if tdb is None:
        return {"hostile": hostile, "guards": guards}
    for sp in tdb.spawns:
        c = tdb.creatures.get(sp.entry)
        if c is None:
            continue
        text = f"{c.name or ''} {c.subname or ''}"
        if c.side and "Guard" in text:
            guards.append([sp.map_id, round(sp.x, 1), round(sp.y, 1), c.side])
        elif c.hostile and c.level and not c.services:
            elite = c.rank in RANKS
            hostile.append([sp.map_id, round(sp.x, 1), round(sp.y, 1), int(c.level), elite])
    return {"hostile": hostile, "guards": guards}


def _seg_dist(px: float, py: float, a: tuple, b: tuple) -> float:
    ax, ay, bx, by = a[0], a[1], b[0], b[1]
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def apply_danger(level: LocalLevel, danger: dict) -> None:
    """Each way's danger (highest hostile level within AGGRO yards), elite flag and guards."""
    cell = 64.0
    grid: dict[tuple[int, int], list] = {}
    for c, wx, wy, lvl, elite in danger.get("hostile") or []:
        if c == level.continent:
            grid.setdefault((math.floor(wx / cell), math.floor(wy / cell)), []).append(
                ("h", wx, wy, lvl, elite)
            )
    for c, wx, wy, side in danger.get("guards") or []:
        if c == level.continent:
            grid.setdefault((math.floor(wx / cell), math.floor(wy / cell)), []).append(
                ("g", wx, wy, side, False)
            )
    by_id = {w.id: w for w in level.waypoints}
    for way in level.ways:
        a, b = by_id[way.a], by_id[way.b]
        pts = [(a.x, a.y, a.z), *way.points, (b.x, b.y, b.z)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        seen, sides = set(), set()
        for gx in range(
            math.floor((min(xs) - AGGRO) / cell), math.floor((max(xs) + AGGRO) / cell) + 1
        ):
            for gy in range(
                math.floor((min(ys) - AGGRO) / cell), math.floor((max(ys) + AGGRO) / cell) + 1
            ):
                for item in grid.get((gx, gy), ()):
                    if id(item) in seen:
                        continue
                    seen.add(id(item))
                    kind, px, py, value, elite = item
                    near = any(_seg_dist(px, py, p, q) <= AGGRO for p, q in pairwise(pts))
                    if not near:
                        continue
                    if kind == "g":
                        sides.add(value)
                    else:
                        if way.danger is None or value > way.danger:
                            way.danger = value
                        way.elite = way.elite or elite
        way.guards = "".join(sorted(sides))


# --- the network ----------------------------------------------------------------------------


def _cost(facts: dict[str, float], profile: str) -> float:
    swim = facts["swim"]
    road = min(facts["road"], facts["len"] - swim)
    ground = max(facts["len"] - swim - road, 0.0)
    walk = (ground + road * ROAD_BONUS) / RUN_SPEED
    swim_s = swim / SWIM_SPEED * (NOSWIM_FACTOR if profile == "n" else 1.0)
    return walk + swim_s


@dataclass
class Network:
    level: LocalLevel
    order: list[Waypoint]  # waypoints by number - 1
    number: dict[int, int]  # local id -> number (1-based)
    clusters: dict[int, tuple[int, int]]  # cluster key -> (first, last) numbers
    cluster_of_wp: dict[int, int]  # number -> cluster key
    region_nodes: dict[int, list[int]]  # cluster key -> numbers of its region nodes
    region: list[tuple]  # (a, b, profile, facts, danger, elite, guards)


def build_network(level: LocalLevel) -> Network:
    keyed = []
    for w in level.waypoints:
        keyed.append((cluster_of(w.x, w.y), w.id, w))
    keyed.sort(key=lambda t: (t[0], t[1]))
    order = [t[2] for t in keyed]
    number = {w.id: n for n, w in enumerate(order, 1)}
    cluster_of_wp = {number[w.id]: c for c, _, w in keyed}
    clusters: dict[int, tuple[int, int]] = {}
    for n, c in sorted(cluster_of_wp.items()):
        first, _last = clusters.get(c, (n, n))
        clusters[c] = (first, n)
    # adjacency over directed ways (a oneway way only a -> b)
    adj: dict[int, list[tuple[int, Way]]] = {}
    borders: dict[int, set[int]] = {}
    for way in level.ways:
        a, b = number[way.a], number[way.b]
        adj.setdefault(a, []).append((b, way))
        if not way.oneway:
            adj.setdefault(b, []).append((a, way))
        ca, cb = cluster_of_wp[a], cluster_of_wp[b]
        if ca != cb:
            borders.setdefault(ca, set()).add(a)
            borders.setdefault(cb, set()).add(b)
    region_nodes: dict[int, list[int]] = {}
    for c in clusters:
        first, last = clusters[c]
        nodes = set(borders.get(c, ()))
        nodes |= {n for n in range(first, last + 1) if order[n - 1].kind == "node"}
        region_nodes[c] = sorted(nodes)
    region = []
    for c in sorted(clusters):
        nodes = region_nodes[c]
        kept_f: dict[tuple[int, int], tuple] = {}
        for profile in PROFILES:
            best = {src: _dijkstra(src, c, adj, cluster_of_wp, profile) for src in nodes}
            for src in nodes:
                for dst in nodes:
                    if dst == src or dst not in best[src]:
                        continue
                    cost, value = best[src][dst]
                    if _dominated(src, dst, cost, nodes, best):
                        continue
                    facts, danger, elite, guards = value
                    if profile == "f":
                        kept_f[(src, dst)] = facts
                    elif kept_f.get((src, dst)) == facts:
                        continue  # the same path as fastest's: the runtime uses that one
                    region.append((src, dst, profile, facts, danger, elite, guards))
    return Network(level, order, number, clusters, cluster_of_wp, region_nodes, region)


def _dominated(src: int, dst: int, cost: float, nodes: list[int], best: dict) -> bool:
    """Whether a path through another region node is at most DOMINATED slower: the search chains
    region edges inside a cluster, so the edge adds nothing worth its bytes."""
    limit = cost * (1 + DOMINATED) + 1e-9
    for mid in nodes:
        if mid in (src, dst):
            continue
        first = best[src].get(mid)
        if first is None or first[0] >= limit:
            continue
        second = best[mid].get(dst)
        if second is not None and first[0] + second[0] <= limit:
            return True
    return False


def _dijkstra(src, cluster, adj, cluster_of_wp, profile):
    """Best paths from src inside one cluster: number -> (cost, (facts, danger, elite, guards))."""
    zero = (dict.fromkeys(FACTS, 0.0), None, False, "")
    best = {src: (0.0, zero)}
    heap = [(0.0, src)]
    while heap:
        cost, n = heapq.heappop(heap)
        if cost > best[n][0]:
            continue
        for m, way in adj.get(n, ()):
            if cluster_of_wp[m] != cluster:
                continue
            new = cost + _cost(way.facts, profile)
            if m not in best or new < best[m][0] - 1e-9:
                facts0, danger0, elite0, guards0 = best[n][1]
                facts = {f: facts0[f] + way.facts[f] for f in FACTS}
                danger = danger0 if way.danger is None else max(danger0 or 0, way.danger)
                guards = "".join(sorted(set(guards0) | set(way.guards)))
                best[m] = (new, (facts, danger, elite0 or way.elite, guards))
                heapq.heappush(heap, (new, m))
    return best


# --- the build's side files and the pack ----------------------------------------------------


def taxi_rows(taxi_paths) -> list[dict]:
    """The client's taxi paths for build/nav-taxi-<client>.json (no points: the pack needs none)."""
    return [
        {
            "id": p.id,
            "from": p.from_node,
            "to": p.to_node,
            "continent": p.continent,
            "length": p.length,
        }
        for p in taxi_paths
    ]


@dataclass(frozen=True)
class TaxiRow:
    id: int
    from_node: int
    to_node: int
    continent: int | None
    length: float


def read_taxi_rows(path: Path) -> list[TaxiRow]:
    rows = json.loads(path.read_text(encoding="utf-8"))
    return [TaxiRow(r["id"], r["from"], r["to"], r["continent"], r["length"]) for r in rows]


def _join_text(net: Network) -> dict[int, str]:
    """The join field per cluster (route.md "The join"): the 32 x 32 cells row by row, a cell's
    value its waypoint's place in the cluster (1 = the first) or 0, runs as "value*count"."""
    grids: dict[int, list[int]] = {}
    field_ = net.level.join
    for i in range(0, len(field_), 3):
        col, row, wp = field_[i], field_[i + 1], field_[i + 2]
        n = net.number.get(wp)
        if n is None:
            continue
        key = (col // 32) * 32 + row // 32
        first, last = net.clusters.get(key, (0, -1))
        if not first <= n <= last:
            continue  # a waypoint the cluster does not own: the runtime keeps the straight line
        grids.setdefault(key, [0] * JOIN_CELLS)[(row % 32) * 32 + col % 32] = n - first + 1
    out = {}
    for key, grid in sorted(grids.items()):
        runs, value, count = [], grid[0], 0
        for v in [*grid, -1]:
            if v == value:
                count += 1
                continue
            runs.append(str(value) if count == 1 else f"{value}*{count}")
            value, count = v, 1
        out[key] = ",".join(runs)
    return out


def read_levels(folder: Path) -> dict[int, LocalLevel]:
    """`<continent>.json` local levels of `clientdump navnet` (tools/nav_build.py --navmesh)."""
    levels = {}
    for path in sorted(folder.glob("*.json")):
        if path.stem.isdigit():
            level = read_local(path)
            if level.continent != int(path.stem):
                raise NavnetError(f"{path.name}: continent {level.continent} in the file")
            levels[level.continent] = level
    return levels


def graph_records(
    levels: dict[int, LocalLevel],
    danger: dict | None,
    taxi,
    taxi_nodes: set[int] | None,
    taxi_times: dict[tuple[int, int], int] | None = None,
) -> dict[int, dict]:
    out = {}
    for continent, level in sorted(levels.items()):
        if danger:
            apply_danger(level, danger)
        out[continent] = graph_record(build_network(level), taxi, taxi_nodes, taxi_times)
    return out


# --- the pack strings -----------------------------------------------------------------------


def _facts_text(facts: dict[str, float]) -> str:
    return ",".join(yd(facts[f]) for f in FACTS)


REGION_FACTS = ("len", "road", "swim", "indoor")  # what the runtime needs to time a region edge


def _way_flags(oneway: bool, elite: bool, guards: str) -> str:
    return ("o" if oneway else "") + ("e" if elite else "") + guards


def _opt(value) -> str:
    return "" if value is None else str(value)


def graph_record(
    net: Network,
    taxi_paths=(),
    taxi_nodes: dict | None = None,
    taxi_times: dict[tuple[int, int], int] | None = None,
) -> dict:
    """The `graph` record of one continent (data.md "The nav pack"); `taxi_times` are the
    flight times the players' captures agree on (corrections.captured_taxi_times), the flight's
    fourth field."""
    level = net.level
    wp_text: dict[int, list[str]] = {}
    for n, w in enumerate(net.order, 1):
        c = net.cluster_of_wp[n]
        wp_text.setdefault(c, []).append(
            f"{yd(w.x)},{yd(w.y)},{yd(w.z)},{KINDS[w.kind]},{_opt(w.area)}"
        )
    ways_text: dict[int, list[str]] = {}
    bends_text: dict[int, list[str]] = {}
    rows = []
    for way in level.ways:
        a, b = net.number[way.a], net.number[way.b]
        rows.append((a, b, way))
    rows.sort(key=lambda r: (r[0], r[1]))
    links: dict[int, list[tuple[int, int, str]]] = {}
    for a, b, way in rows:
        c = net.cluster_of_wp[a]
        text = (
            f"{a},{b},{_facts_text(way.facts)},{_opt(way.area)},{_opt(way.danger)},"
            f"{_way_flags(way.oneway, way.elite, way.guards)}"
        )
        ways_text.setdefault(c, []).append(text)
        cb = net.cluster_of_wp[b]
        if cb != c:
            # a link is listed in the cluster it leaves, both ways (the reverse with up and down
            # swapped), so a search decodes only the clusters it crosses (25.10.2026)
            links.setdefault(c, []).append((a, b, text))
            if not way.oneway:
                back = dict(way.facts, up=way.facts["down"], down=way.facts["up"])
                links.setdefault(cb, []).append(
                    (
                        b,
                        a,
                        f"{b},{a},{_facts_text(back)},{_opt(way.area)},{_opt(way.danger)},"
                        f"{_way_flags(False, way.elite, way.guards)}",
                    )
                )
        wa, wb = net.order[a - 1], net.order[b - 1]
        line = simplify(
            [(wa.x, wa.y), *((p[0], p[1]) for p in way.points), (wb.x, wb.y)], BEND_TOLERANCE
        )
        bends_text.setdefault(c, []).append(":".join(f"{yd(x)},{yd(y)}" for x, y in line[1:-1]))
    region: dict[int, list[str]] = {}
    for a, b, p, facts, danger, elite, guards in sorted(
        net.region, key=lambda r: (r[0], r[1], r[2])
    ):
        region.setdefault(net.cluster_of_wp[a], []).append(
            f"{a},{b},{p},{','.join(yd(facts[f]) for f in REGION_FACTS)},{_opt(danger)},"
            f"{_way_flags(False, elite, guards)}"
        )
    keys = {n: w.key for n, w in enumerate(net.order, 1) if w.key}
    anchors: dict[str, list[str]] = {}
    for an in sorted(level.anchors, key=lambda a: (a.ref, a.i)):
        typ, _, rid = an.ref.partition(":")
        anchors.setdefault(typ, []).append(f"{rid},{an.i},{net.number[an.wp]},{yd(an.len)}")
    join = _join_text(net)
    times = taxi_times or {}
    taxi = [
        f"{p.from_node},{p.to_node},{yd(p.length)}"
        + (f",{times[p.from_node, p.to_node]}" if (p.from_node, p.to_node) in times else "")
        for p in sorted(taxi_paths, key=lambda p: p.id)
        if p.continent == level.continent
        and p.length > 0
        and (taxi_nodes is None or (p.from_node in taxi_nodes and p.to_node in taxi_nodes))
    ]
    return {
        "version": 1,
        "clusters": {c: f"{first},{last}" for c, (first, last) in sorted(net.clusters.items())},
        "wp": {c: ";".join(v) for c, v in sorted(wp_text.items())},
        "ways": {c: ";".join(v) for c, v in sorted(ways_text.items())},
        "bends": {c: "|".join(v) for c, v in sorted(bends_text.items())},
        "region": {c: ";".join(v) for c, v in sorted(region.items())},
        "links": {
            c: ";".join(t for _, _, t in sorted(v, key=lambda r: (r[0], r[1])))
            for c, v in sorted(links.items())
        },
        "keys": dict(sorted(keys.items())),
        "anchors": {t: ";".join(v) for t, v in sorted(anchors.items())},
        "taxi": ";".join(taxi),
        **({"join": join} if join else {}),
    }
