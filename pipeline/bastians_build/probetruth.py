"""Ground-truth checks against a Bastians_Probe dump (roadmap B3.8, the probe-dump part).

The dump the owner copies with tools/probe_import.py carries, besides the P3 map corners the
transform table is built from, three kinds of in-game measurements that check the built world:

- **P4 landmarks and P7 taxi-map positions**: the player's map position (uiMapID, map fraction)
  together with `UnitPosition` in world yards (x, y, z, instance). Each pair checks the transform
  of that map: the
  measured world point is converted back to map fractions through the transform the build used,
  and the distance to the map position the client reported is the error, in map percent.
- **P7 taxi maps**: `C_TaxiMap.GetAllTaxiNodes(mapID)` lists every reachable node with its position
  as a fraction of the map the player stands on, beyond 0..1 for nodes outside it (measured
  20.10.2026). Each node checks the flight master of the same id: its name, and its place through
  the map's transform in world yards against the record's `wx`, `wy` (tolerance NODE_YARDS); without
  a transform, the record's spawn on that map in map percent.
- **P4 targets** (since 21.10.2026, the B4.4 spot check): a landmark recorded with something
  targeted carries the target's kind, id and name from its GUID. An NPC checks the world's `npc`
  record of that id, a game object the `object` record or, failing that, the `node` record of that
  id (retail gather nodes carry the object id): a spawn on the player's map within TOLERANCE_PCT of
  where the player stood, and the name.
- **P2 quest log**: every quest in the log checks that the world has a quest of that id with the
  same title.
- **P7 flights**: measured durations, reported for route.md (no status: the packs carry none).

Like groundtruth.py, this never fails a build: the report lists every row that is not ok. Rows the
dump cannot support (no world position, no map, a header line) are `unusable` and counted apart.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from bastians_build.coords import world_to_map
from bastians_build.model import World
from bastians_build.sources.probe import ProbeDump, Transform

TOLERANCE_PCT = 1.0
NODE_YARDS = 60.0  # a taxi node marker against the flight master's measured place
NODE_STATUSES = ("ok", "off", "name differs", "no spawn on map", "missing node")


@dataclass(frozen=True)
class PointCheck:
    """One landmark or taxi-map position against the transform table."""

    label: str
    map: int | None
    status: str  # ok | off | no transform | unusable
    distance_pct: float | None = None
    note: str | None = None


@dataclass(frozen=True)
class NodeCheck:
    """One taxi node of a taxi map against the world's flight master of that id."""

    node_id: int
    name: str
    map: int
    status: str  # ok | off | name differs | no spawn on map | missing node
    distance_pct: float | None = None  # map percent, or yards when the note says so
    note: str | None = None


@dataclass(frozen=True)
class TargetCheck:
    """One landmark's target against the world record of that id (npc, object or node)."""

    label: str
    kind: str  # npc | object | node (the record type that answered, or the probe's kind)
    target_id: int | None
    name: str
    map: int | None
    status: str  # ok | off | name differs | no spawn on map | missing record | unusable
    distance_pct: float | None = None
    note: str | None = None


TARGET_STATUSES = ("ok", "off", "name differs", "no spawn on map", "missing record", "unusable")


@dataclass(frozen=True)
class QuestCheck:
    quest_id: int
    title: str
    status: str  # ok | name differs | missing quest
    note: str | None = None


@dataclass(frozen=True)
class FlightTime:
    to: str
    seconds: float
    from_map: int | None
    landed_map: int | None
    landed_at: str | None = (
        None  # the flight master nearest the landing position, with its distance
    )


@dataclass
class ProbeTruth:
    points: list[PointCheck] = field(default_factory=list)
    nodes: list[NodeCheck] = field(default_factory=list)
    quests: list[QuestCheck] = field(default_factory=list)
    flights: list[FlightTime] = field(default_factory=list)
    targets: list[TargetCheck] = field(default_factory=list)

    @property
    def empty(self) -> bool:
        return not (self.points or self.nodes or self.quests or self.flights or self.targets)


# ---------------------------------------------------------------------------------------------
# Reading the probe shapes: try() results are { ok, ret = { ... } } or { ok = false, err }
# ---------------------------------------------------------------------------------------------


def _ret(value: object, index: int = 1) -> object:
    """The n-th return of a probe `try()` record, or None when the call failed or gave nil."""
    if not isinstance(value, dict) or not value.get("ok"):
        return None
    ret = value.get("ret")
    if not isinstance(ret, dict | list):
        return None
    item = (
        ret.get(index) if isinstance(ret, dict) else (ret[index - 1] if len(ret) >= index else None)
    )
    return None if item == "<nil>" else item


def _number(value: object) -> float | None:
    return float(value) if isinstance(value, int | float) and not isinstance(value, bool) else None


def _position(entry: object) -> tuple[int, float, float, float, float] | None:
    """(uiMapID, mapX, mapY, wx, wy) of a probe playerPosition() record, or None."""
    if not isinstance(entry, dict):
        return None
    map_id, mx, my = entry.get("mapID"), _number(entry.get("mapX")), _number(entry.get("mapY"))
    up = entry.get("unitPosition")
    # UnitPosition returns x (north-south, the first world coordinate), y, z, instance: measured
    # 20.10.2026 on Forever (Goldshire -9474, 67.4 matches the Elwynn transform), not y, x as the
    # old wiki said
    wx, wy = _number(_ret(up, 1)), _number(_ret(up, 2))
    if not isinstance(map_id, int) or mx is None or my is None or wx is None or wy is None:
        return None
    return map_id, mx, my, wx, wy


def _items(value: object) -> list:
    """A Lua array that came through to_python as a list or a 1-based dict."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value[k] for k in sorted(k for k in value if isinstance(k, int))]
    return []


# ---------------------------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------------------------


def check_point(
    label: str, entry: object, transforms: dict[int, Transform], tolerance_pct: float
) -> PointCheck:
    pos = _position(entry)
    if pos is None:
        map_id = entry.get("mapID") if isinstance(entry, dict) else None
        return PointCheck(
            label,
            map_id if isinstance(map_id, int) else None,
            "unusable",
            note="no world or map position",
        )
    map_id, mx, my, wx, wy = pos
    t = transforms.get(map_id)
    if t is None:
        return PointCheck(label, map_id, "no transform")
    back = world_to_map(t, wx, wy)
    if back is None:
        return PointCheck(label, map_id, "no transform", note="degenerate transform")
    distance = math.hypot(back[0] - mx, back[1] - my) * 100
    status = "ok" if distance <= tolerance_pct else "off"
    note = (
        f"client {mx * 100:.1f}, {my * 100:.1f}; transform {back[0] * 100:.1f}, {back[1] * 100:.1f}"
    )
    return PointCheck(label, map_id, status, round(distance, 2), note)


def point_checks(
    dump: ProbeDump, transforms: dict[int, Transform], tolerance_pct: float = TOLERANCE_PCT
) -> list[PointCheck]:
    out: list[PointCheck] = []
    for i, entry in enumerate(_items(dump.results.get("P4")), start=1):
        label = entry.get("label") if isinstance(entry, dict) else None
        out.append(check_point(str(label or f"landmark {i}"), entry, transforms, tolerance_pct))
    p7 = dump.results.get("P7") or {}
    for i, entry in enumerate(_items(p7.get("opens") if isinstance(p7, dict) else None), start=1):
        position = entry.get("position") if isinstance(entry, dict) else None
        out.append(check_point(f"taxi map {i}", position, transforms, tolerance_pct))
    return out


def node_checks(
    dump: ProbeDump,
    world: World,
    tolerance_pct: float = TOLERANCE_PCT,
    transforms: dict[int, Transform] | None = None,
) -> list[NodeCheck]:
    flightpaths = world.records.get("flightpath", {})
    transforms = transforms or {}
    out: list[NodeCheck] = []
    p7 = dump.results.get("P7") or {}
    for entry in _items(p7.get("opens") if isinstance(p7, dict) else None):
        if not isinstance(entry, dict):
            continue
        position = entry.get("position")
        map_id = position.get("mapID") if isinstance(position, dict) else None
        if not isinstance(map_id, int):
            continue
        for node in _items(_ret(entry.get("modern"), 1)):
            if not isinstance(node, dict) or not isinstance(node.get("nodeID"), int):
                continue
            node_id, name = node["nodeID"], str(node.get("name") or "")
            pos = node.get("position") if isinstance(node.get("position"), dict) else {}
            nx, ny = _number(pos.get("x")), _number(pos.get("y"))
            rec = flightpaths.get(node_id)
            if rec is None:
                out.append(NodeCheck(node_id, name, map_id, "missing node"))
                continue
            if name and rec.get("name") and name != rec["name"]:
                out.append(
                    NodeCheck(node_id, name, map_id, "name differs", note=f"world: {rec['name']}")
                )
                continue
            t = transforms.get(map_id)
            rwx, rwy = _number(rec.get("wx")), _number(rec.get("wy"))
            if (
                t is not None
                and nx is not None
                and ny is not None
                and rwx is not None
                and rwy is not None
            ):
                wx = t.wx0 + nx * t.wx_dx + ny * t.wx_dy
                wy = t.wy0 + nx * t.wy_dx + ny * t.wy_dy
                yards = math.hypot(wx - rwx, wy - rwy)
                status = "ok" if yards <= NODE_YARDS else "off"
                note = f"{yards:.0f} yards; taxi map {wx:.0f}, {wy:.0f}; world {rwx:.0f}, {rwy:.0f}"
                out.append(NodeCheck(node_id, name, map_id, status, round(yards, 1), note))
                continue
            best = None
            for spawn in rec.get("spawns") or []:
                if (
                    spawn[0] != map_id
                    or spawn[1] is None
                    or spawn[2] is None
                    or nx is None
                    or ny is None
                ):
                    continue
                distance = math.hypot(spawn[1] - nx, spawn[2] - ny) * 100
                if best is None or distance < best:
                    best = distance
            if best is None:
                out.append(NodeCheck(node_id, name, map_id, "no spawn on map"))
                continue
            status = "ok" if best <= tolerance_pct else "off"
            out.append(NodeCheck(node_id, name, map_id, status, round(best, 2)))
    return out


RECORD_TYPES = {"npc": ("npc",), "object": ("object", "node"), "vehicle": ("npc",)}


def check_target(
    label: str, entry: object, world: World, tolerance_pct: float
) -> TargetCheck | None:
    """The landmark's target against the record of that id, or None without a target."""
    target = entry.get("target") if isinstance(entry, dict) else None
    if not isinstance(target, dict):
        return None
    kind = str(target.get("kind") or "?")
    target_id = target.get("id") if isinstance(target.get("id"), int) else None
    name = str(target.get("name") or "")
    map_id = entry.get("mapID")
    mx, my = _number(entry.get("mapX")), _number(entry.get("mapY"))
    types = RECORD_TYPES.get(kind)
    if types is None or target_id is None:
        return TargetCheck(label, kind, target_id, name, None, "unusable", note="not an entity")
    if not isinstance(map_id, int) or mx is None or my is None:
        return TargetCheck(label, kind, target_id, name, None, "unusable", note="no map position")
    rec, rec_type = None, kind
    for t in types:
        rec = world.records.get(t, {}).get(target_id)
        if rec is not None:
            rec_type = t
            break
    if rec is None:
        return TargetCheck(label, kind, target_id, name, map_id, "missing record")
    if name and rec.get("name") and name != rec["name"]:
        return TargetCheck(
            label, rec_type, target_id, name, map_id, "name differs", note=f"world: {rec['name']}"
        )
    best = None
    for spawn in rec.get("spawns") or []:
        if spawn[0] != map_id or spawn[1] is None or spawn[2] is None:
            continue
        distance = math.hypot(spawn[1] - mx, spawn[2] - my) * 100
        if best is None or distance < best[0]:
            best = (distance, spawn)
    if best is None:
        return TargetCheck(label, rec_type, target_id, name, map_id, "no spawn on map")
    distance, spawn = best
    status = "ok" if distance <= tolerance_pct else "off"
    note = f"player {mx * 100:.1f}, {my * 100:.1f}; pack {spawn[1] * 100:.1f}, {spawn[2] * 100:.1f}"
    if len(spawn) > 3 and spawn[3]:
        note += f" ({spawn[3]})"
    return TargetCheck(label, rec_type, target_id, name, map_id, status, round(distance, 2), note)


def target_checks(
    dump: ProbeDump, world: World, tolerance_pct: float = TOLERANCE_PCT
) -> list[TargetCheck]:
    out: list[TargetCheck] = []
    for i, entry in enumerate(_items(dump.results.get("P4")), start=1):
        label = entry.get("label") if isinstance(entry, dict) else None
        check = check_target(str(label or f"landmark {i}"), entry, world, tolerance_pct)
        if check is not None:
            out.append(check)
    return out


def quest_checks(dump: ProbeDump, world: World) -> list[QuestCheck]:
    quests = world.records.get("quest", {})
    p2 = dump.results.get("P2") or {}
    seen: set[int] = set()
    out: list[QuestCheck] = []
    for entry in _items(p2.get("modern") if isinstance(p2, dict) else None):
        info = _ret(entry.get("info"), 1) if isinstance(entry, dict) else None
        if not isinstance(info, dict) or info.get("isHeader"):
            continue
        quest_id, title = info.get("questID"), str(info.get("title") or "")
        if not isinstance(quest_id, int) or quest_id == 0 or quest_id in seen:
            continue
        seen.add(quest_id)
        rec = quests.get(quest_id)
        if rec is None:
            out.append(QuestCheck(quest_id, title, "missing quest"))
        elif title and rec.get("name") != title:
            out.append(
                QuestCheck(quest_id, title, "name differs", note=f"world: {rec.get('name')}")
            )
        else:
            out.append(QuestCheck(quest_id, title, "ok"))
    return out


def nearest_flight_master(world: World, wx: float, wy: float) -> tuple[str, float] | None:
    """Name and distance in yards of the flight master nearest a world point."""
    best: tuple[str, float] | None = None
    for rec in world.records.get("flightpath", {}).values():
        rwx, rwy = _number(rec.get("wx")), _number(rec.get("wy"))
        if rwx is None or rwy is None:
            continue
        yards = math.hypot(wx - rwx, wy - rwy)
        if best is None or yards < best[1]:
            best = (str(rec.get("name") or "?"), yards)
    return best


def flight_times(
    dump: ProbeDump, world: World | None = None, transforms: dict[int, Transform] | None = None
) -> list[FlightTime]:
    """Measured flights; the probe's UnitOnTaxi poller records no destination name, so the landing
    position names the nearest flight master when the world is given."""
    p7 = dump.results.get("P7") or {}
    out: list[FlightTime] = []
    for flight in _items(p7.get("flights") if isinstance(p7, dict) else None):
        if not isinstance(flight, dict) or _number(flight.get("seconds")) is None:
            continue
        src = flight.get("from") if isinstance(flight.get("from"), dict) else {}
        dst = flight.get("landed") if isinstance(flight.get("landed"), dict) else {}
        near = None
        pos = _position(dst) if world is not None else None
        if pos is not None:
            near = nearest_flight_master(world, pos[3], pos[4])
        landed_at = f"{near[0]} ({near[1]:.0f} yards)" if near else None
        to = flight.get("to") or (near[0] if near else None) or "?"
        out.append(
            FlightTime(
                str(to),
                round(float(flight["seconds"]), 1),
                src.get("mapID") if isinstance(src.get("mapID"), int) else None,
                dst.get("mapID") if isinstance(dst.get("mapID"), int) else None,
                landed_at,
            )
        )
    return out


def check_probe(
    dump: ProbeDump,
    world: World,
    transforms: dict[int, Transform] | None,
    tolerance_pct: float = TOLERANCE_PCT,
) -> ProbeTruth:
    return ProbeTruth(
        points=point_checks(dump, transforms or {}, tolerance_pct),
        nodes=node_checks(dump, world, tolerance_pct, transforms),
        quests=quest_checks(dump, world),
        targets=target_checks(dump, world, tolerance_pct),
        flights=flight_times(dump, world, transforms),
    )


# ---------------------------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------------------------


def _counts(rows, statuses: tuple[str, ...]) -> str:
    counts = {s: 0 for s in statuses}
    for r in rows:
        counts[r.status] = counts.get(r.status, 0) + 1
    return ", ".join(f"{n} {s}" for s, n in counts.items())


def render_probe_section(truth: ProbeTruth, tolerance_pct: float = TOLERANCE_PCT) -> list[str]:
    """Markdown lines for the build report: counts per check and every row that is not ok."""
    lines = ["## Probe ground truth", ""]
    if truth.empty:
        lines += ["The probe dump holds no P2, P4 or P7 measurements.", ""]
        return lines
    lines.append(
        f"Tolerance {tolerance_pct:g} map percent. "
        "Positions (P4 landmarks, P7 taxi maps) against the "
        f"transform table: {len(truth.points)} checked, "
        f"{_counts(truth.points, ('ok', 'off', 'no transform', 'unusable'))}. "
        f"Taxi nodes against the flight masters ({NODE_YARDS:g} yards through the transforms): "
        f"{len(truth.nodes)} checked, "
        f"{_counts(truth.nodes, NODE_STATUSES)}. "
        f"Quests in the log: {len(truth.quests)} checked, "
        f"{_counts(truth.quests, ('ok', 'name differs', 'missing quest'))}. "
        f"Targets at landmarks against the pack records: {len(truth.targets)} checked, "
        f"{_counts(truth.targets, TARGET_STATUSES)}."
    )
    lines.append("")
    bad_points = [p for p in truth.points if p.status != "ok"]
    if bad_points:
        lines += ["| Position | Map | Status | Distance (%) | Note |", "|---|---|---|---|---|"]
        for p in bad_points:
            distance = f"{p.distance_pct:.2f}" if p.distance_pct is not None else "-"
            lines.append(
                f"| {p.label} | {p.map or '-'} | {p.status} | {distance} | {p.note or ''} |"
            )
        lines.append("")
    bad_nodes = [n for n in truth.nodes if n.status != "ok"]
    if bad_nodes:
        lines += ["| Taxi node | Map | Status | Distance | Note |", "|---|---|---|---|---|"]
        for n in bad_nodes:
            distance = f"{n.distance_pct:.2f}" if n.distance_pct is not None else "-"
            lines.append(
                f"| {n.name} ({n.node_id}) | {n.map} | {n.status} | {distance} | {n.note or ''} |"
            )
        lines.append("")
    bad_targets = [t for t in truth.targets if t.status != "ok"]
    if bad_targets:
        lines += [
            "| Target | Landmark | Map | Status | Distance (%) | Note |",
            "|---|---|---|---|---|---|",
        ]
        for t in bad_targets:
            distance = f"{t.distance_pct:.2f}" if t.distance_pct is not None else "-"
            lines.append(
                f"| {t.kind} {t.target_id if t.target_id is not None else '?'} {t.name} | "
                f"{t.label} | {t.map or '-'} | {t.status} | {distance} | {t.note or ''} |"
            )
        lines.append("")
    bad_quests = [q for q in truth.quests if q.status != "ok"]
    if bad_quests:
        lines += ["| Quest | Status | Note |", "|---|---|---|"]
        for q in bad_quests:
            lines.append(f"| {q.title} ({q.quest_id}) | {q.status} | {q.note or ''} |")
        lines.append("")
    if truth.flights:
        lines += [
            "| Flight to | Seconds | From map | Landed map | Landed at |",
            "|---|---|---|---|---|",
        ]
        for f in truth.flights:
            lines.append(
                f"| {f.to} | {f.seconds:.1f} | {f.from_map or '-'} | {f.landed_map or '-'} | "
                f"{f.landed_at or '-'} |"
            )
        lines.append("")
    return lines
