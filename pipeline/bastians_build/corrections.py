"""The correction table of the world graph's network (world-graph.md §6.1 step 4, data.md): what
the collision mesh gets wrong, authored per client in
``pipeline/config/nav_corrections_<client>.toml`` and applied to a local level before the network
is built.

- ``[[lift]]``: a lift (a moving game object, a gap in the mesh) between two ends in world yards
  ``[wx, wy, wz]``, with its ride and cycle in seconds.
- ``[[link]]``: a walkable connection the mesh misses (a ramp, stairs, a tunnel, a door), from
  ``a`` to ``b`` through optional inner ``points``.
- ``[[block]]``: forbidden ground: every way with an end within ``r`` yards of ``center``
  ``[wx, wy]`` goes (a gate, an invisible wall).

Each end of a lift or a link becomes a waypoint of its own, joined by a straight way to the
nearest waypoint that has ways (in 3D, within JOIN_YARDS): the height picks the right floor.
Besides the rows, a keyed waypoint (a dock, a zeppelin tower, an entrance) the mesh left without
any way joins its nearest connected waypoint within ORPHAN_YARDS the same way. Every change is
reported, so the build report shows what the table did.
"""

from __future__ import annotations

import itertools
import json
import math
import re
import statistics
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from .navnet import RUN_SPEED, LocalLevel, NavnetError, Way, Waypoint

JOIN_YARDS = 100.0  # a lift's or a link's end joins a waypoint within this (3D)
ORPHAN_YARDS = 40.0  # a keyed waypoint without ways joins a connected one within this (3D)
LINK_KINDS = frozenset({"ramp", "stairs", "tunnel", "door", "path"})


@dataclass
class Lift:
    name: str
    continent: int
    top: tuple[float, float, float]
    bottom: tuple[float, float, float]
    ride: float
    cycle: float | None
    verified: str | bool
    note: str = ""


@dataclass
class Link:
    name: str
    kind: str
    continent: int
    a: tuple[float, float, float]
    b: tuple[float, float, float]
    points: list[tuple[float, float, float]] = field(default_factory=list)
    oneway: bool = False
    verified: str | bool = False
    note: str = ""


@dataclass
class Block:
    name: str
    continent: int
    center: tuple[float, float]
    r: float
    verified: str | bool = False
    note: str = ""


@dataclass
class Corrections:
    lifts: list[Lift] = field(default_factory=list)
    links: list[Link] = field(default_factory=list)
    blocks: list[Block] = field(default_factory=list)


def _point(value, where: str, dims: int = 3) -> tuple:
    ok = isinstance(value, list) and len(value) == dims
    if not ok or not all(isinstance(v, int | float) and not isinstance(v, bool) for v in value):
        raise NavnetError(f"{where}: a point must be [{', '.join(['wx', 'wy', 'wz'][:dims])}]")
    return tuple(float(v) for v in value)


def _seconds(value, where: str, required: bool) -> float | None:
    if value is None and not required:
        return None
    if not isinstance(value, int | float) or isinstance(value, bool) or value <= 0:
        raise NavnetError(f"{where}: seconds must be a number > 0")
    return float(value)


def read_corrections(path: Path) -> Corrections:
    """The table, validated; a missing file is an empty table."""
    if not path.is_file():
        return Corrections()
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    out, names = Corrections(), set()

    def common(row: dict, section: str) -> tuple[str, int]:
        name = row.get("name")
        where = f"{path.name} [[{section}]] {name}"
        if not isinstance(name, str) or not name or name in names:
            raise NavnetError(f"{where}: name missing or twice")
        names.add(name)
        if not isinstance(row.get("continent"), int):
            raise NavnetError(f"{where}: continent must be a Map.db2 id")
        return where, row["continent"]

    for row in raw.get("lift") or []:
        where, continent = common(row, "lift")
        top, bottom = _point(row.get("top"), where), _point(row.get("bottom"), where)
        if top[2] <= bottom[2]:
            raise NavnetError(f"{where}: the top must be higher than the bottom")
        out.lifts.append(
            Lift(
                row["name"],
                continent,
                top,
                bottom,
                _seconds(row.get("ride"), f"{where} ride", True),
                _seconds(row.get("cycle"), f"{where} cycle", False),
                row.get("verified", False),
                str(row.get("note") or ""),
            )
        )
    for row in raw.get("link") or []:
        where, continent = common(row, "link")
        if row.get("kind") not in LINK_KINDS:
            raise NavnetError(f"{where}: kind must be one of {sorted(LINK_KINDS)}")
        out.links.append(
            Link(
                row["name"],
                row["kind"],
                continent,
                _point(row.get("a"), where),
                _point(row.get("b"), where),
                [_point(p, where) for p in row.get("points") or []],
                bool(row.get("oneway", False)),
                row.get("verified", False),
                str(row.get("note") or ""),
            )
        )
    for row in raw.get("block") or []:
        where, continent = common(row, "block")
        r = row.get("r")
        if not isinstance(r, int | float) or isinstance(r, bool) or r <= 0:
            raise NavnetError(f"{where}: r must be yards > 0")
        out.blocks.append(
            Block(
                row["name"],
                continent,
                _point(row.get("center"), where, 2),
                float(r),
                row.get("verified", False),
                str(row.get("note") or ""),
            )
        )
    return out


def _length(points: list[tuple[float, float, float]]) -> float:
    return sum(math.dist(p, q) for p, q in itertools.pairwise(points))


def _straight(a: Waypoint, b: Waypoint, area: int | None) -> Way:
    """A straight way between two waypoints, its facts from the 3D distance."""
    dz = b.z - a.z
    facts = {
        "len": round(math.dist((a.x, a.y, a.z), (b.x, b.y, b.z)), 1),
        "road": 0.0,
        "swim": 0.0,
        "up": round(max(dz, 0.0), 1),
        "down": round(max(-dz, 0.0), 1),
        "indoor": 0.0,
    }
    return Way(a.id, b.id, facts, False, area, [])


class _Editor:
    """Adds waypoints and ways to one local level; finds the connected waypoints."""

    def __init__(self, level: LocalLevel):
        self.level = level
        self.next_id = max((w.id for w in level.waypoints), default=0) + 1
        self.by_id = {w.id: w for w in level.waypoints}
        self.connected = {w.a for w in level.ways} | {w.b for w in level.ways}

    def nearest(
        self, p: tuple[float, float, float], within: float
    ) -> tuple[Waypoint | None, float]:
        best, best_d = None, within
        for wid in sorted(self.connected):
            w = self.by_id[wid]
            d = math.dist((w.x, w.y, w.z), p)
            if d <= best_d:
                best, best_d = w, d
        return best, best_d

    def add_way(self, way: Way) -> None:
        self.level.ways.append(way)
        self.connected |= {way.a, way.b}

    def nearest_flat(self, p: tuple, within: float) -> tuple[Waypoint | None, float]:
        """The nearest connected waypoint in the plane: for a point without a height."""
        best, best_d = None, within
        for wid in sorted(self.connected):
            w = self.by_id[wid]
            d = math.dist((w.x, w.y), (p[0], p[1]))
            if d <= best_d:
                best, best_d = w, d
        return best, best_d

    def end(self, p: tuple, where: str) -> Waypoint:
        """A new waypoint at p, joined to the nearest connected one; a point without a height (a
        captured walk) takes the height of the waypoint it joins."""
        if len(p) < 3 or p[2] is None:
            near, d = self.nearest_flat(p, JOIN_YARDS)
            if near is None:
                raise NavnetError(
                    f"{where}: no waypoint with ways within {JOIN_YARDS:.0f} yards of {p[:2]}"
                )
            p = (p[0], p[1], near.z)
        near, d = self.nearest(p, JOIN_YARDS)
        if near is None:
            raise NavnetError(
                f"{where}: no waypoint with ways within {JOIN_YARDS:.0f} yards of {p}"
            )
        w = Waypoint(self.next_id, p[0], p[1], p[2], "door", None, near.area)
        self.next_id += 1
        self.level.waypoints.append(w)
        self.by_id[w.id] = w
        if d > 0.5:
            self.add_way(_straight(near, w, near.area))
        else:
            self.connected.add(w.id)
        return w


def apply_corrections(level: LocalLevel, table: Corrections) -> list[str]:
    """Applies the rows of this level's continent and joins the orphaned keyed waypoints; returns
    one report line per change."""
    report: list[str] = []
    c = level.continent
    by_id = {w.id: w for w in level.waypoints}
    for block in (b for b in table.blocks if b.continent == c):
        before = len(level.ways)
        cx, cy = block.center
        inside = {w.id for w in by_id.values() if math.hypot(w.x - cx, w.y - cy) <= block.r}
        level.ways = [w for w in level.ways if w.a not in inside and w.b not in inside]
        report.append(f"block {block.name}: {before - len(level.ways)} ways removed")
    edit = _Editor(level)
    for w in sorted(level.waypoints, key=lambda w: w.id):
        if w.key and w.id not in edit.connected:
            near, d = edit.nearest((w.x, w.y, w.z), ORPHAN_YARDS)
            if near is None:
                report.append(
                    f"orphan {w.key}: no connected waypoint within {ORPHAN_YARDS:.0f} yards"
                )
                continue
            edit.add_way(_straight(near, w, near.area))
            report.append(f"orphan {w.key}: joined by {d:.0f} yards")
    for lift in (x for x in table.lifts if x.continent == c):
        where = f"lift {lift.name}"
        top, bottom = edit.end(lift.top, f"{where} top"), edit.end(lift.bottom, f"{where} bottom")
        seconds = lift.ride + (lift.cycle / 2 if lift.cycle else 0.0)
        # timed as indoor yards at walking speed, so a mount never shortens a lift
        yards = round(seconds * RUN_SPEED, 1)
        rise = round(lift.top[2] - lift.bottom[2], 1)
        for a, b, up, down in ((bottom, top, rise, 0.0), (top, bottom, 0.0, rise)):
            facts = {
                "len": yards,
                "road": 0.0,
                "swim": 0.0,
                "up": up,
                "down": down,
                "indoor": yards,
            }
            edit.add_way(Way(a.id, b.id, facts, True, a.area, []))
        report.append(f"lift {lift.name}: {rise:.0f} yards, {seconds:.0f} s with the wait")
    for link in (x for x in table.links if x.continent == c):
        where = f"link {link.name}"
        a, b = edit.end(link.a, f"{where} a"), edit.end(link.b, f"{where} b")
        # a captured walk's points have no height: between the ends', in a straight line
        inner = []
        for i, q in enumerate(link.points):
            if len(q) < 3 or q[2] is None:
                t = (i + 1) / (len(link.points) + 1)
                inner.append((q[0], q[1], round(a.z + (b.z - a.z) * t, 1)))
            else:
                inner.append(q)
        points = [(a.x, a.y, a.z), *inner, (b.x, b.y, b.z)]
        length = round(_length(points), 1)
        climb = sum(max(q[2] - p[2], 0.0) for p, q in itertools.pairwise(points))
        drop = sum(max(p[2] - q[2], 0.0) for p, q in itertools.pairwise(points))
        facts = {
            "len": length,
            "road": 0.0,
            "swim": 0.0,
            "up": round(climb, 1),
            "down": round(drop, 1),
            "indoor": length if link.kind in ("tunnel", "stairs", "door") else 0.0,
        }
        edit.add_way(Way(a.id, b.id, facts, link.oneway, a.area, inner))
        report.append(f"link {link.name}: {link.kind}, {length:.0f} yards")
    return report


# ---------------------------------------------------------------------------------------------
# Captured walks (world-graph.md §9, W11): the learned walks of the players' saved variables, as
# tools/capture_import.py writes them (positions and times, never names). A walk becomes a link
# for everyone when at least `agree` independent captures hold a walk with both ends in the same
# 30-yard cells of the same continent.
# ---------------------------------------------------------------------------------------------

CAPTURE_YARDS = 30.0  # two walks with both ends this close are the same stretch


def _near(p, q) -> bool:
    return math.dist((p[0], p[1]), (q[0], q[1])) <= CAPTURE_YARDS


def read_captures(folder: Path) -> list[dict]:
    """Every capture file of the folder, oldest name first; a missing folder is none."""
    if not folder.is_dir():
        return []
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(folder.glob("*.json"))]


def captured_links(folder: Path, agree: int = 2) -> list[Link]:
    """The links the captures agree on: the walk with the most points of each group stands for
    it; a link's points carry no height (the editor takes the ends' heights)."""
    groups: list[dict] = []
    for n, cap in enumerate(read_captures(folder)):
        for walk in cap.get("walk") or []:
            pts = walk.get("points") or []
            if len(pts) < 2 or not isinstance(walk.get("map"), int):
                continue
            a, b = pts[0], pts[-1]
            g = next(
                (
                    g
                    for g in groups
                    if g["map"] == walk["map"]
                    and (
                        (_near(a, g["a"]) and _near(b, g["b"]))
                        or (_near(a, g["b"]) and _near(b, g["a"]))
                    )
                ),
                None,
            )
            if g is None:
                g = {"map": walk["map"], "a": a, "b": b, "files": set(), "best": pts}
                groups.append(g)
            g["files"].add(n)
            if len(pts) > len(g["best"]):
                g["best"] = pts
    out = []
    groups.sort(key=lambda g: (g["map"], g["a"][0], g["a"][1], g["b"][0], g["b"][1]))
    for i, g in enumerate(groups):
        if len(g["files"]) < agree:
            continue
        pts = [(float(p[0]), float(p[1]), None) for p in g["best"]]
        out.append(
            Link(
                name=f"captured-{g['map']}-{i + 1}",
                kind="path",
                continent=g["map"],
                a=pts[0],
                b=pts[-1],
                points=pts[1:-1],
                oneway=False,
                verified=f"{len(g['files'])} captures",
                note="a walk the players took where the mesh had no way",
            )
        )
    return out


TAXI_REF = re.compile(r"taxinode:(\d+)>taxinode:(\d+)")


def captured_taxi_times(folder: Path, agree: int = 2) -> dict[tuple[int, int], int]:
    """The flight times the captures agree on: per pair of taxi nodes the median over `agree` or
    more captures that timed it, whole seconds. The nav pack carries them as the flight's fourth
    field; a time this player learned still wins at runtime."""
    samples: dict[tuple[int, int], list[float]] = {}
    for cap in read_captures(folder):
        for ref, seconds in (cap.get("taxi") or {}).items():
            m = TAXI_REF.fullmatch(str(ref))
            if m and isinstance(seconds, int | float) and seconds > 0:
                samples.setdefault((int(m[1]), int(m[2])), []).append(float(seconds))
    return {
        pair: round(statistics.median(v)) for pair, v in sorted(samples.items()) if len(v) >= agree
    }


def captured_ride_waits(folder: Path) -> dict[str, tuple[int, int, int]]:
    """Per transport (`transport:<id>`) the median wait at a dock over every capture, as (median
    seconds, samples, captures). The pack keeps the vessel's loop: a wait is one arrival's luck and
    averages to half the loop, so the build only reports the median against it (a median far off
    says the loop row is wrong)."""
    samples: dict[str, list[float]] = {}
    files: dict[str, set[int]] = {}
    for n, cap in enumerate(read_captures(folder)):
        for ref, waits in (cap.get("ride") or {}).items():
            good = [float(w) for w in waits if isinstance(w, int | float) and w > 0]
            if good and str(ref).startswith("transport:"):
                samples.setdefault(str(ref), []).extend(good)
                files.setdefault(str(ref), set()).add(n)
    return {
        ref: (round(statistics.median(v)), len(v), len(files[ref]))
        for ref, v in sorted(samples.items())
    }
