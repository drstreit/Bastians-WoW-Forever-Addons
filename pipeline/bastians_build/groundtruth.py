"""Ground-truth check (roadmap B3.8): measured NPC places against the built world.

`data/ground-truth/*.csv` holds places AHSync measured in the Forever beta (`npc_id, npc_name,
role, ui_map_id, x_pct, y_pct, seen_at`, map percent). For every row the nearest spawn of that NPC
on that map is found; within the tolerance (1 map percent) the row is `ok`, otherwise `off` with
the distance and the spawn's source, `no spawn on map` when the NPC has spawns elsewhere only,
`missing npc` when the world has no such NPC. The check never fails a build: the report lists every
row that is not ok with its reason (the acceptance criterion of B3.8).
"""

from __future__ import annotations

import csv
import math
from dataclasses import dataclass
from pathlib import Path

from bastians_build.model import World

TOLERANCE_PCT = 1.0


class GroundTruthError(ValueError):
    pass


@dataclass(frozen=True)
class TruthRow:
    npc_id: int
    name: str
    role: str | None
    map: int
    x: float  # map fraction
    y: float
    seen_at: str | None


@dataclass(frozen=True)
class Check:
    npc_id: int
    name: str
    map: int
    status: str  # ok | off | no spawn on map | missing npc
    distance_pct: float | None = None
    nearest: tuple[float, float, str | None] | None = None  # x, y, src of the nearest spawn


REQUIRED = ("npc_id", "ui_map_id", "x_pct", "y_pct")


def read_truth(path: Path) -> list[TruthRow]:
    if not path.is_file():
        raise GroundTruthError(f"not a file: {path}")
    rows: list[TruthRow] = []
    with path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise GroundTruthError(f"{path.name}: columns missing: {', '.join(missing)}")
        for number, raw in enumerate(reader, start=2):
            try:
                rows.append(
                    TruthRow(
                        npc_id=int(raw["npc_id"]),
                        name=(raw.get("npc_name") or "").strip() or f"npc {raw['npc_id']}",
                        role=(raw.get("role") or "").strip() or None,
                        map=int(raw["ui_map_id"]),
                        x=float(raw["x_pct"]) / 100,
                        y=float(raw["y_pct"]) / 100,
                        seen_at=(raw.get("seen_at") or "").strip() or None,
                    )
                )
            except (KeyError, ValueError) as err:
                raise GroundTruthError(f"{path.name}:{number}: bad row ({err})") from err
    return rows


def compare(
    world: World, rows: list[TruthRow], tolerance_pct: float = TOLERANCE_PCT
) -> list[Check]:
    npcs = world.records.get("npc", {})
    checks: list[Check] = []
    for row in rows:
        rec = npcs.get(row.npc_id)
        if rec is None:
            checks.append(Check(row.npc_id, row.name, row.map, "missing npc"))
            continue
        best = None
        for spawn in rec.get("spawns") or []:
            if spawn[0] != row.map or spawn[1] is None or spawn[2] is None:
                continue
            distance = math.hypot(spawn[1] - row.x, spawn[2] - row.y) * 100
            if best is None or distance < best[0]:
                best = (distance, spawn)
        if best is None:
            checks.append(Check(row.npc_id, row.name, row.map, "no spawn on map"))
            continue
        distance, spawn = best
        status = "ok" if distance <= tolerance_pct else "off"
        src = spawn[3] if len(spawn) > 3 else None
        checks.append(
            Check(
                row.npc_id, row.name, row.map, status, round(distance, 2), (spawn[1], spawn[2], src)
            )
        )
    return checks


def summary(checks: list[Check]) -> dict[str, int]:
    out = {"checked": len(checks), "ok": 0, "off": 0, "no spawn on map": 0, "missing npc": 0}
    for c in checks:
        out[c.status] += 1
    return out


def render_section(checks: list[Check], tolerance_pct: float = TOLERANCE_PCT) -> list[str]:
    """Markdown lines for the build report: the counts and every row that is not ok."""
    counts = summary(checks)
    lines = [
        "## Ground truth",
        "",
        f"{counts['checked']} measured places checked, tolerance {tolerance_pct:g} map percent: "
        f"{counts['ok']} ok, {counts['off']} off, "
        f"{counts['no spawn on map']} without a spawn on that "
        f"map, {counts['missing npc']} NPCs missing.",
        "",
    ]
    bad = [c for c in checks if c.status != "ok"]
    if bad:
        lines += [
            "| NPC | Map | Status | Distance (%) | Nearest spawn (src) |",
            "|---|---|---|---|---|",
        ]
        for c in sorted(bad, key=lambda c: (c.status, -(c.distance_pct or 0), c.npc_id)):
            nearest = (
                f"{c.nearest[0] * 100:.1f}, {c.nearest[1] * 100:.1f} ({c.nearest[2] or '?'})"
                if c.nearest
                else "-"
            )
            distance = f"{c.distance_pct:.2f}" if c.distance_pct is not None else "-"
            lines.append(
                f"| {c.name} ({c.npc_id}) | {c.map} | {c.status} | {distance} | {nearest} |"
            )
        lines.append("")
    return lines
