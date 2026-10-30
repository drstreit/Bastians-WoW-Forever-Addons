"""Coordinate frames of the pipeline (coordinates.md): map percent, map fraction, world yards.

Canonical storage is ``(uiMapID, x, y)`` as fractions 0..1 with a ``src``. World yards convert to
map fractions through the per-uiMapID affine transforms (probe P3 > client files > measured fits);
a point outside every known map of its continent cannot be placed and is dropped with a reason.
"""

from __future__ import annotations

from dataclasses import dataclass

from bastians_build.sources.probe import Transform

# CMaNGOS map ids -> continent as the client's C_Map world positions report it (assumed: both
# instance ids; verified against probe P4 landmarks before launch)
CMANGOS_CONTINENT = {0: 0, 1: 1}
PARENT_RATIO = 8  # a containing map this many times larger than the smallest is a parent map


@dataclass(frozen=True)
class Spawn:
    """A placed point: map fractions with their source, and the height in world yards when the
    source has one (CMaNGOS, TaxiNodes; ADR 0026: the graph's places carry `wz`)."""

    ui_map_id: int
    x: float
    y: float
    src: str
    wz: float | None = None
    r: float | None = (
        None  # the area's radius in yards where the thing roams (W5: CMaNGOS spawndist)
    )

    def row(self) -> list:
        row = [self.ui_map_id, round(self.x, 4), round(self.y, 4), self.src]
        if self.wz is not None or self.r:
            row.append(None if self.wz is None else round(self.wz, 1))
        if self.r:
            row.append(round(self.r, 1))
        return row


def pct_to_fraction(ui_map_id: int, x_pct: float, y_pct: float, src: str) -> Spawn:
    return Spawn(ui_map_id, round(x_pct / 100, 4), round(y_pct / 100, 4), src)


def world_to_map(t: Transform, wx: float, wy: float) -> tuple[float, float] | None:
    """Invert world = origin + fractions * matrix; None when the transform is degenerate."""
    det = t.wx_dx * t.wy_dy - t.wx_dy * t.wy_dx
    if det == 0:
        return None
    dx, dy = wx - t.wx0, wy - t.wy0
    x = (dx * t.wy_dy - dy * t.wx_dy) / det
    y = (dy * t.wx_dx - dx * t.wy_dx) / det
    return x, y


def _area(t: Transform) -> float:
    return abs(t.wx_dx * t.wy_dy - t.wx_dy * t.wy_dx)


def best_map(
    transforms: dict[int, Transform], continent: int, wx: float, wy: float, slack: float = 0.0
) -> tuple[int, float, float] | None:
    """The containing map of the continent in which the point lies most centrally: (uiMapID, x, y)
    or None.

    Zone rectangles overlap their neighbours, so the smallest containing rectangle is often the
    neighbour (54 of 71 Forever flight masters right); the one where the point is nearest the
    centre is right for 63 (measured 20.10.2026, coordinates.md). A containing map more than
    PARENT_RATIO times larger than the smallest one is a parent (the continent map) and is only
    taken when nothing else contains the point. Centrality is rounded to a tenth, the smaller area
    breaks ties, then the lower id.
    """
    candidates = []
    for ui_map_id, t in transforms.items():
        if t.continent != continent:
            continue
        pos = world_to_map(t, wx, wy)
        if pos is None:
            continue
        x, y = pos
        if -slack <= x <= 1 + slack and -slack <= y <= 1 + slack:
            candidates.append((_area(t), ui_map_id, x, y))
    if not candidates:
        return None
    smallest = min(c[0] for c in candidates)
    zones = [c for c in candidates if c[0] <= smallest * PARENT_RATIO] or candidates
    _, ui_map_id, x, y = min(
        zones, key=lambda c: (round(max(abs(c[2] - 0.5), abs(c[3] - 0.5)), 1), c[0], c[1])
    )
    return ui_map_id, x, y


def named_map(
    transforms: dict[int, Transform],
    names: dict[int, str],
    continent: int,
    wx: float,
    wy: float,
    parts: list[str],
) -> tuple[int, float, float] | None:
    """The map a place's own name gives, when that map contains the point: (uiMapID, x, y) or
    None.

    TaxiNodes names read "Tarren Mill, Hillsbrad": the place, then its zone, and the client's
    UiMap names start with those words ("Hillsbrad Foothills"). The parts are tried in order, so
    a capital ("Stormwind, Elwynn") lands on its city map and not on the zone around it. Among
    several named maps containing the point the smallest wins. Measured 20.10.2026 on the 74
    Forever nodes with a faction bit: 12 differ from `best_map`, all 12 right by name, 7 of them
    zone misses of the rectangle rule (coordinates.md).
    """
    for part in parts:
        want = part.strip()
        if not want:
            continue
        candidates = []
        for ui_map_id, t in transforms.items():
            if t.continent != continent:
                continue
            name = names.get(ui_map_id, "")
            if not (name == want or name.startswith(want + " ")):
                continue
            pos = world_to_map(t, wx, wy)
            if pos is None:
                continue
            x, y = pos
            if 0 <= x <= 1 and 0 <= y <= 1:
                candidates.append((_area(t), ui_map_id, x, y))
        if candidates:
            _, ui_map_id, x, y = min(candidates)
            return ui_map_id, x, y
    return None


def place_world_point(
    transforms: dict[int, Transform],
    cmangos_map: int,
    wx: float,
    wy: float,
    src: str,
    wz: float | None = None,
    r: float | None = None,
) -> Spawn | None:
    """A CMaNGOS world position -> the zone map containing it (with the height), or None."""
    continent = CMANGOS_CONTINENT.get(cmangos_map)
    if continent is None:
        return None
    hit = best_map(transforms, continent, wx, wy)
    if hit is None:
        return None
    ui_map_id, x, y = hit
    return Spawn(ui_map_id, round(x, 4), round(y, 4), src, wz, r)
