"""A city's real plan from the client (docs/addons/map.md "City plans", ADR 0065): where one
walks, the gold passages, the water, the walls, and the houses from the placed model's rooms.

Everything here works on the plan grid: the minimap's tile pixels at 1024 a tile (0.52 yards a
pixel), cut to the place's measured area. `plan` reads the map data and the walk raster, `houses`
the model's groups, `masks` joins both into what the sheet draws. The numbers are the Stormwind
prototype's (08.11.2026, Forever 1.60.1.70862), kept as they were: Stormwind's tiles are rebuilt
byte for byte from them. Needs numpy and Pillow only; the painting side is `city_paint`.
"""

from __future__ import annotations

import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from . import draw as D
from .scene import ORIGIN, TILE_YARDS

N = 1024  # the plan's pixels per terrain tile
YPP = TILE_YARDS / N  # yards a plan pixel
PROTOTYPE_YPP = 0.433  # yards a pixel of Stormwind's sheet, as the prototype had it
SERVICE = {
    "vendor",
    "trainer",
    "innkeeper",
    "banker",
    "auctioneer",
    "repair",
    "flightmaster",
    "stablemaster",
    "battlemaster",
}
OPEN = 400  # square yards of open ground that make a district's group a street
COVER = 0.55  # share of a group's surface below another that makes it a room
INDOOR, LIT, OUTER = 0x2000, 0x40, 0x8  # a model group's flags: indoors, lit as outdoors, outdoors
ROOMS = ("ceiling", "indoor")  # the rules that make a group a room
KINDS = ("streets", "canyon")  # the ways to read a city's ground
SPAWN_ORDER = ("fdb", "eq", "capture", "questie")  # the sources whose place is taken first


@dataclass(frozen=True)
class Grid:
    """The plan's pixels: row 0 north, column 0 west, counted from the map's north-west corner."""

    row0: int
    col0: int
    height: int
    width: int

    def pix(self, wx, wy):
        """World yards -> (column, row), floats."""
        return (ORIGIN - wy) / YPP - self.col0 - 0.5, (ORIGIN - wx) / YPP - self.row0 - 0.5

    def tiles(self) -> tuple[int, int, int, int]:
        """The terrain tiles the grid lies in: x0, y0, x1, y1."""
        x1, y1 = (self.col0 + self.width - 1) // N, (self.row0 + self.height - 1) // N
        return self.col0 // N, self.row0 // N, x1, y1

    def origin(self) -> tuple[float, float]:
        """The north-west corner in the navmesh frame (east, south), yards."""
        return self.col0 * YPP, self.row0 * YPP


def grid_of(wx: tuple[float, float], wy: tuple[float, float]) -> Grid:
    """The plan grid of an area in world yards (wx south to north, wy east to west)."""
    return Grid(
        round((ORIGIN - wx[1]) / YPP),
        round((ORIGIN - wy[1]) / YPP),
        round((wx[1] - wx[0]) / YPP),
        round((wy[1] - wy[0]) / YPP),
    )


@dataclass(frozen=True)
class Frame:
    """The sheet: the place's Region (world yards) on `width` x `height` pixels."""

    wx: tuple[float, float]
    wy: tuple[float, float]
    width: int
    height: int

    @property
    def ypp(self) -> float:
        """Yards a pixel, cut to three places as the prototype had Stormwind's (0.433)."""
        return math.floor((self.wy[1] - self.wy[0]) / self.width * 1000) / 1000

    def affine(self, grid: Grid) -> np.ndarray:
        """Plan pixels -> sheet pixels."""

        def px(col):
            east = ORIGIN - (col + grid.col0 + 0.5) * YPP
            return (self.wy[1] - east) / (self.wy[1] - self.wy[0]) * self.width

        def py(row):
            north = ORIGIN - (row + grid.row0 + 0.5) * YPP
            return (self.wx[1] - north) / (self.wx[1] - self.wx[0]) * self.height

        return np.float32([[px(1) - px(0), 0, px(0)], [0, py(1) - py(0), py(0)]])

    def of_world(self, wx, wy):
        """World yards -> sheet pixel (x, y)."""
        x = (self.wy[1] - wy) / (self.wy[1] - self.wy[0]) * self.width
        y = (self.wx[1] - wx) / (self.wx[1] - self.wx[0]) * self.height
        return x, y


def _nan0(a, v=-1e9):
    return np.where(np.isnan(a), v, a)


def components(mask: np.ndarray) -> np.ndarray:
    """`draw.components` (the smallest index of each 4-connected part, -1 outside), by scipy
    where it is installed: the same labels, in seconds instead of minutes on a city's streets."""
    try:
        from scipy import ndimage
    except ImportError:
        return D.components(mask)
    lab, count = ndimage.label(mask)
    first = np.full(count + 1, -1, "i8")
    at = np.nonzero(lab.ravel())[0]
    values, where = np.unique(lab.ravel()[at], return_index=True)
    first[values] = at[where]
    return np.where(mask, first[lab], -1)


def plan(r, walk: np.ndarray, zh: np.ndarray) -> dict[str, np.ndarray]:
    """The ground of a place: `r` is its map data (a `scene.Region` cut to the grid), `walk` and
    `zh` the walk raster's bits and its highest floor (`clientdump navmesh-walk`).

    -> water, paved (a structure's surface), wall, the walk masks, gate (the gold passages),
    height (above the street level) and top (the highest surface)."""
    ypp = r.yards_per_pixel
    h, w = r.ground.shape
    ground, surface, building = _nan0(r.ground), _nan0(r.surface), _nan0(r.building)
    top = np.maximum.reduce([ground, surface, building])
    paved = (building > -1e8) & (building >= ground - 0.5)
    water = (surface > -1e8) & (surface >= top - 0.5)

    # the street level: what is left when everything narrower than ~90 yards is taken away
    # (4 pixels = 2 yards, a square of 45 yards radius). A canal is no street level
    dry = D.fill_nan(np.where(water, np.nan, top).astype("f4"))
    small = dry[::4, ::4]

    def opened_by(radius: int, soft: float) -> np.ndarray:
        o = -D.min_filter(-D.min_filter(small, radius), radius)
        img = Image.fromarray(o.astype("f4"), mode="F").resize((w, h), Image.BILINEAR)
        return D.blur(np.asarray(img, dtype="f4"), soft)

    height = top - opened_by(22, 6)
    # masonry stands above what is left when everything narrower than ~24 yards is taken away
    narrow = top - opened_by(6, 3)

    # a building: under its top lies an indoor floor, and the top stands above the street.
    # A street over a cellar has an indoor face under it too: it is flat and wide. A roof slopes,
    # or is narrow enough to stand out of what is around it
    indoor = (r.floor == r.floor) & ((r.building - _nan0(r.floor, 1e9)) > 3)
    slope = D.slope(D.fill_nan(np.where(paved, top, np.nan).astype("f4")), ypp)
    steep = D.blur((slope > 8).astype("f4"), 5)
    stands = top - opened_by(11, 3)
    flat_street = (steep < 0.12) & (stands < 1.5)
    roof = indoor & (height > 2.0) & ~flat_street
    roof = D.shrink(D.grow(roof, 2), 2)  # closes the seams between a roof's parts
    roof = D.grow(D.shrink(roof, 2), 2)  # drops slivers
    labels = components(roof)
    ids, counts = np.unique(labels[labels >= 0], return_counts=True)
    roof[np.isin(labels, ids[counts < 40 / (ypp * ypp)])] = False  # under 40 square yards
    roof = D.smooth_mask(roof, 1.2)

    # walls and towers: tall masonry that is not a building
    wall = paved & ~roof & ~water & (narrow > 2.5)
    wall = D.grow(D.shrink(wall, 1), 1)
    wall = D.smooth_mask(wall, 0.8)

    any_walk = (walk & 7) != 0
    # A city may stand on a hidden ground sheet that the mesh walks too. A floor counts when it
    # is a street on a structure or open terrain, not the sheet under one: there the highest
    # walking floor is at terrain height and a structure stands far above it
    terrain = D.fill_nan(np.where(np.isnan(r.ground), np.nan, r.ground).astype("f4"))
    has_top = ~np.isnan(r.building)
    hidden = (
        any_walk
        & has_top
        & (np.nan_to_num(zh - terrain, nan=99.0) < 3)
        & (np.nan_to_num(r.building - zh, nan=0.0) > 6)
    )
    walkable = any_walk & ~hidden
    clear = np.nan_to_num(r.building - zh, nan=0.0)
    # an open street: nothing well above the floor, or something high and thin like an arch
    near_floor = np.abs(np.nan_to_num(zh - r.floor, nan=999.0)) < 3
    covered = walkable & near_floor & (clear > 4)
    covered = D.grow(D.shrink(covered, 1), 1)
    open_walk = walkable & ~covered

    gate = _passages(covered, open_walk, paved, water, walk, ypp)
    return {
        "water": water,
        "paved": paved,
        "wall": wall,
        "walk": walk,
        "zh": zh,
        "any_walk": any_walk,
        "walkable": walkable,
        "open_walk": open_walk,
        "covered": covered,
        "gate": gate,
        "height": height,
        "top": top,
        "building": r.building,
    }  # the driver adds zl, the walk raster's lowest floor, for a canyon city


def _runs(ids: np.ndarray):
    """The slices of equal values in a sorted array."""
    start = 0
    for k in range(1, len(ids) + 1):
        if k == len(ids) or ids[k] != ids[start]:
            yield start, k
            start = k


def _passages(covered, open_walk, paved, water, walk, ypp: float) -> np.ndarray:
    """The gold passages: roofed walking ground that is a way through."""
    # a tunnel: roofed walking ground that meets the open streets at places more than 22 yards
    # apart
    span = 22 / ypp
    labels = components(covered)
    contact = covered & D.grow(open_walk & ~covered, 3)
    ys, xs = np.nonzero(contact)
    ids = labels[ys, xs]
    order = np.argsort(ids)
    ids, xs, ys = ids[order], xs[order], ys[order]
    tunnel_ids = []
    for a, b in _runs(ids):
        if max(xs[a:b].max() - xs[a:b].min(), ys[a:b].max() - ys[a:b].min()) > span:
            tunnel_ids.append(ids[a])
    tunnel = D.smooth_mask(np.isin(labels, tunnel_ids), 1.0)
    # gold is only a way through: the narrow parts of the roofed ground that reach an open
    # street. What is wider than about 17 yards is a hall; a door's short step into a hall does
    # not count
    wide = round(8.5 / ypp)
    core = D.grow(D.shrink(tunnel, wide), wide)
    narrow_parts = tunnel & ~D.grow(core, 2)
    part_labels = components(narrow_parts)
    # a way through joins two street areas that are walled apart; a hall's corridor reaches one
    streets_only = open_walk & ~covered & (paved | ((walk & 6) != 0)) & ~water
    streets_only = D.shrink(D.grow(streets_only, 5), 5) & ~covered
    area_labels = components(streets_only)
    aids, acounts = np.unique(area_labels[area_labels >= 0], return_counts=True)
    tiny = aids[acounts < 300 / (ypp * ypp)]
    area_labels = np.where(np.isin(area_labels, tiny), -1, area_labels)
    near_area = (-D.min_filter((-area_labels).astype("f4"), 4)).astype("i4")
    ys, xs = np.nonzero(narrow_parts)
    pairs = np.unique(np.column_stack((part_labels[ys, xs], near_area[ys, xs])), axis=0)
    pairs = pairs[pairs[:, 1] >= 0]
    parts, counts = np.unique(pairs[:, 0], return_counts=True)
    joining = set(parts[counts >= 2].tolist())
    touching = set(parts.tolist())
    ids = part_labels[ys, xs]
    order = np.argsort(ids)
    ids, xs, ys = ids[order], xs[order], ys[order]
    gate_ids = []
    for a, b in _runs(ids):
        px, py = xs[a:b].astype("f8"), ys[a:b].astype("f8")
        pid = int(ids[a])
        if len(px) <= 3:
            continue
        low, high = np.linalg.eigvalsh(np.cov(np.vstack((px, py))))
        ratio = float(np.sqrt(high / max(low, 1e-6)))
        length = 4 * float(np.sqrt(high)) * ypp  # yards along the part
        # a way through is short and straight; one that does not reach a second open street
        # (its far end opens into a covered district) must be plainly a corridor
        if 12 <= length <= 60 and (
            (pid in joining and ratio >= 3.0) or (pid in touching and ratio >= 5.0)
        ):
            gate_ids.append(ids[a])
    return D.smooth_mask(np.isin(part_labels, gate_ids), 1.0)


def read_meshes(path: Path, groups: list[dict]) -> dict[int, tuple[np.ndarray, np.ndarray]]:
    """A placement's `<unique>.bin` (`clientdump wmo-rooms`): group index -> vertices (world
    yards), triangles."""
    mesh = {}
    with path.open("rb") as raw:
        for g in groups:
            v = np.fromfile(raw, "<f4", g["nv"] * 3).reshape(-1, 3)
            t = np.fromfile(raw, "<i4", g["nt"] * 3).reshape(-1, 3)
            mesh[g["i"]] = (v, t)
    return mesh


def houses(
    placement: dict,
    mesh: dict[int, tuple[np.ndarray, np.ndarray]],
    names: dict[int, str],
    grid: Grid,
    streets: set[str],
    npcs: list[dict],
    rooms: str = "ceiling",
) -> tuple[np.ndarray, np.ndarray, dict[int, dict]]:
    """The houses of a placed model (map.md "A house"): a group named after a district with open
    ground of its own, or with too little of its surface below another, is a street; every other
    group is a room, and rooms joined by a portal are one house. That is the rule `rooms`
    "ceiling", Stormwind's. With "indoor" a room is a group the client lights as indoors (flag
    0x2000 without 0x40): Orgrimmar's huts are stacked groups, each floor's ceiling is the next
    group's, so no group has a ceiling of its own.

    `names` is WMOAreaTable's name per group id, `streets` the district names, `npcs` the
    place's people (`npcs_of`). -> shell (where a group has a surface well above another: a
    roof over a floor), the house label per pixel (-1: none; of stacked rooms the smaller one),
    and per label its groups, names, area, doors, heights and residents."""
    h, w = grid.height, grid.width
    groups = placement["groups"]
    shell = np.zeros((h, w), bool)
    stats = {}
    for g in groups:
        v, t = mesh[g["i"]]
        if len(t) == 0:
            continue
        a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
        n = np.cross(b - a, c - a)
        flat = np.abs(n[:, 2]) / (np.linalg.norm(n, axis=1) + 1e-9) > 0.5
        idx = np.nonzero(flat)[0]
        if len(idx) == 0:
            continue
        col, row = grid.pix(v[:, 0], v[:, 1])
        x0, y0 = int(np.floor(col.min())) - 2, int(np.floor(row.min())) - 2
        gw, gh = int(np.ceil(col.max())) - x0 + 3, int(np.ceil(row.max())) - y0 + 3
        z = (a[:, 2] + b[:, 2] + c[:, 2]) / 3
        order = idx[np.argsort(z[idx])]
        hi, lo = Image.new("F", (gw, gh), float("nan")), Image.new("F", (gw, gh), float("nan"))
        dh, dl = ImageDraw.Draw(hi), ImageDraw.Draw(lo)

        def poly(k, t=t, col=col, row=row, x0=x0, y0=y0):
            return [(float(col[t[k, q]] - x0), float(row[t[k, q]] - y0)) for q in range(3)]

        for k in order:
            dh.polygon(poly(k), fill=float(z[k]))
        for k in order[::-1]:
            dl.polygon(poly(k), fill=float(z[k]))
        high, low = np.asarray(hi), np.asarray(lo)
        seen = ~np.isnan(high)
        tall = seen & ((high - low) > 3)
        stats[g["i"]] = {
            "cover": float(tall.sum() / max(1, seen.sum())),
            "open": float((seen & ~tall).sum() * YPP * YPP),
            "area": float(seen.sum() * YPP * YPP),
        }
        sy0, sx0 = max(0, y0), max(0, x0)
        sy1, sx1 = min(h, y0 + gh), min(w, x0 + gw)
        if sy1 > sy0 and sx1 > sx0:
            shell[sy0:sy1, sx0:sx1] |= tall[sy0 - y0 : sy1 - y0, sx0 - x0 : sx1 - x0]

    covered = set()
    for g in groups:
        s = stats.get(g["i"])
        if not s:
            continue
        if rooms == "indoor":
            room = bool(g["flags"] & INDOOR) and not g["flags"] & LIT
        else:
            street = names.get(g["id"], "") in streets and s["open"] >= OPEN
            room = not (street or s["cover"] < COVER)
        if room:
            covered.add(g["i"])
    parent = {i: i for i in covered}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    byi = {g["i"]: g for g in groups}
    for i in covered:
        for _portal, other, _side in byi[i]["portals"]:
            if other in covered:
                parent[find(i)] = find(other)
    rooms = defaultdict(list)
    for i in covered:
        rooms[find(i)].append(i)

    labels = np.full((h, w), -1, "i4")
    info: dict[int, dict] = {}
    # small first: of stacked rooms the smaller one takes the pixel
    order = sorted(rooms.values(), key=lambda m: sum(stats[i]["area"] for i in m))
    for k, members in enumerate(order):
        img = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(img)
        for i in members:
            v, t = mesh[i]
            c, rr = grid.pix(v[:, 0], v[:, 1])
            for a, b, e in t:
                d.polygon(
                    [
                        (float(c[a]), float(rr[a])),
                        (float(c[b]), float(rr[b])),
                        (float(c[e]), float(rr[e])),
                    ],
                    fill=255,
                )
        m = np.asarray(img) > 0
        labels[m & (labels < 0)] = k
        doors = []
        for i in members:
            for portal, other, _side in byi[i]["portals"]:
                if other not in covered:
                    doors.append(np.array(placement["portals"][portal]).mean(axis=0).tolist())
        named = Counter(names.get(byi[i]["id"], "") for i in members)
        ys, xs = np.nonzero(m)
        zs = [mesh[i][0][:, 2] for i in members]
        info[k] = {
            "groups": sorted(byi[i]["id"] for i in members),
            "names": [n for n, _ in named.most_common() if n],
            "area": float(m.sum() * YPP * YPP),
            "doors": doors,
            "zmax": float(max(z.max() for z in zs)),
            "zmin": float(min(z.min() for z in zs)),
            "zmed": float(np.median(np.concatenate(zs))),
            "cx": float(xs.mean()) if len(xs) else 0,
            "cy": float(ys.mean()) if len(ys) else 0,
            "residents": [],
        }

    reach = round(4 / YPP)  # an NPC up to 4 yards outside a house is at its door
    for n in npcs:
        c, rr = grid.pix(n["wx"], n["wy"])
        i, j = round(rr), round(c)
        if not (0 <= i < h and 0 <= j < w):
            continue
        lab = int(labels[i, j])
        if lab < 0:
            win = labels[max(0, i - reach) : i + reach + 1, max(0, j - reach) : j + reach + 1]
            if (win >= 0).any():
                vals, cnt = np.unique(win[win >= 0], return_counts=True)
                lab = int(vals[cnt.argmax()])
        if lab >= 0:
            useful = bool(SERVICE & set(n["flags"]) or "questgiver" in n["flags"])
            info[lab]["residents"].append({**n, "useful": useful})
    return shell, labels, info


def _regular(mask: np.ndarray, boxes: bool = True) -> np.ndarray:
    """A small room as its best-fitting rotated rectangle when it fills one, one yard wider each
    side; else closed, without pillars. Without `boxes` always the latter: a six-sided hut
    fills a rectangle too."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    if len(xs) < 20:
        return mask
    best = None
    for ang in range(0, 90, 2):
        t = np.radians(ang)
        u = xs * np.cos(t) + ys * np.sin(t)
        v = -xs * np.sin(t) + ys * np.cos(t)
        area = (u.max() - u.min() + 1) * (v.max() - v.min() + 1)
        if best is None or area < best[0]:
            best = (area, t, u.min(), u.max(), v.min(), v.max())
    area, t, u0, u1, v0, v1 = best
    yard = 1 / YPP
    if boxes and len(xs) / area >= 0.72 and len(xs) * YPP * YPP < 900:
        corners = [
            (u0 - yard, v0 - yard),
            (u1 + yard, v0 - yard),
            (u1 + yard, v1 + yard),
            (u0 - yard, v1 + yard),
        ]
        poly = [(u * np.cos(t) - v * np.sin(t), u * np.sin(t) + v * np.cos(t)) for u, v in corners]
        img = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img).polygon(poly, fill=255)
        return np.asarray(img) > 0
    x0, y0 = max(0, xs.min() - 12), max(0, ys.min() - 12)
    crop = mask[y0 : ys.max() + 13, x0 : xs.max() + 13]
    closed = D.grow(D.shrink(D.grow(crop, 6), 6), 2)
    out = np.zeros_like(mask)
    out[y0 : y0 + closed.shape[0], x0 : x0 + closed.shape[1]] = closed
    return out


def masks(
    p: dict[str, np.ndarray],
    shell: np.ndarray,
    labels: np.ndarray,
    info: dict[int, dict],
    districts: set[str],
) -> tuple[np.ndarray, dict[int, str], dict[str, np.ndarray]]:
    """What the sheet draws, from the plan `p` and the houses: the drawn footprint's house label
    per pixel (-1: none), each house's status (`house`, `underground`, `passage`), and the masks
    house, other (tall masses without a room), road, wall, green and gate.

    `districts` are the names that make no landmark: a hall over 900 square yards without a
    landmark's name draws no roof where an open street runs, and loses its thin arms."""
    water, paved, walk, zh = p["water"], p["paved"], p["walk"], p["zh"]
    open_walk, gate, height = p["open_walk"], p["gate"], p["height"]
    wet = D.grow(water, 1)
    # streets first: a room lying under a street is a cellar and draws no roof
    road0 = open_walk & (paved | ((walk & 2) != 0) | ((walk & 4) != 0)) & ~water
    road0 = D.shrink(D.grow(road0, 6), 6) & ~water

    drawn = np.full(labels.shape, -1, "i4")
    gate_near = D.grow(gate, 3)
    status: dict[int, str] = {}
    ids, counts = np.unique(labels[labels >= 0], return_counts=True)
    for k in ids[np.argsort(-counts)]:  # small last: they stay on top
        m = labels == k
        inf = info[int(k)]
        useful = any(r["useful"] for r in inf["residents"])
        ys, xs = np.nonzero(m)
        y0, y1 = max(0, ys.min() - 30), ys.max() + 31
        x0, x1 = max(0, xs.min() - 30), xs.max() + 31
        crop = m[y0:y1, x0:x1]
        ring = D.grow(crop, 24) & ~D.grow(crop, 3) & road0[y0:y1, x0:x1]
        near = zh[y0:y1, x0:x1][ring]
        near = near[~np.isnan(near)]
        street_z = float(np.median(near)) if len(near) else inf["zmed"]
        inf["street"] = street_z
        over = (m & (road0 | water)).sum() > 0.55 * m.sum()
        below = inf["zmax"] < street_z + 2 or inf["zmed"] < street_z - 5
        if below or (over and inf["zmin"] < street_z - 8):
            status[int(k)] = "underground"
            continue
        by_gate = (m & gate_near).sum()
        if by_gate > 0.45 * m.sum() or (not useful and by_gate > 0.1 * m.sum()):
            status[int(k)] = "passage"
            continue
        # only what stands above the street is a building seen from above; a cellar's reach
        # under a street is not
        up = m & (p["top"] > street_z + 3)
        if up.sum() < 0.3 * m.sum():
            status[int(k)] = "underground"
            continue
        if up.sum() < 0.85 * m.sum():
            m = D.shrink(D.grow(up, 3), 3)
        landmark = bool(inf["names"]) and inf["names"][0] not in districts
        if not landmark and m.sum() * YPP * YPP > 900:
            m = D.grow(D.shrink(m & ~D.grow(road0, 1), 6), 6)
        shape = _regular(m)
        if int(m.sum()) * YPP * YPP > 900:
            shape = D.smooth_mask(shape, 3.0)
        drawn[shape & (drawn < 0) | m & (drawn < 0)] = k
        status[int(k)] = "house"
    house = drawn >= 0

    # other tall masses: facades without a room, towers, roofs of what has no interior. Not the
    # city walls
    wall0 = p["wall"]
    walked = D.grow(open_walk & ~wall0, 1)
    other = shell & ~wet & (height > 2.0) & ~walked & ~D.grow(wall0, 3) & ~house
    other = D.grow(D.shrink(other, 2), 2)
    comp = components(other)
    oid, ocount = np.unique(comp[comp >= 0], return_counts=True)
    other[np.isin(comp, oid[ocount < 30 / (YPP * YPP)])] = False
    other = D.shrink(D.grow(other, 7), 7) & ~house & ~wet
    holes = components(~other)
    hole_ids, hole_n = np.unique(holes[holes >= 0], return_counts=True)
    other[np.isin(holes, hole_ids[hole_n < 300 / (YPP * YPP)])] = True
    other = D.smooth_mask(other, 3.0) & ~house
    roof_soft = D.smooth_mask(house, 0.8) | other

    # streets: smoothed so the navmesh's polygon edges do not show, small islands in a plaza
    # filled
    road = D.smooth_mask(road0, 2.4) & ~water & ~roof_soft
    gaps = components(~road & ~water & ~roof_soft)
    gap_ids, gap_n = np.unique(gaps[gaps >= 0], return_counts=True)
    road[np.isin(gaps, gap_ids[gap_n < 450 / (YPP * YPP)])] = True

    wall = wall0 & ~road & ~roof_soft
    wall = D.grow(D.shrink(wall, 1), 1)
    wall = D.smooth_mask(wall, 1.8)

    # ground: what one can walk on is green. Soft: the navmesh's 16-yard steps must not show
    hidden_pit = p["any_walk"] & ~paved & (np.nan_to_num(height, nan=0.0) < -10)
    green = open_walk & ~paved & ~hidden_pit & ((walk & 3) != 0) & ~water
    green = (D.blur(green.astype("f4"), 7) > 0.5) & ~road & ~water

    out = {
        "house": house,
        "other": other,
        "road": road,
        "wall": wall,
        "green": green,
        "gate": D.smooth_mask(gate, 1.0) & ~water,
    }
    return drawn, status, out


def _parts(mask: np.ndarray):
    """The 4-connected parts of a mask: yields each part's (rows, columns) box and the part
    inside it."""
    lab = components(mask)
    ys, xs = np.nonzero(lab >= 0)
    ids = lab[ys, xs]
    order = np.argsort(ids, kind="stable")
    ids, ys, xs = ids[order], ys[order], xs[order]
    for a, b in _runs(ids):
        box = (slice(ys[a:b].min(), ys[a:b].max() + 1), slice(xs[a:b].min(), xs[a:b].max() + 1))
        yield box, lab[box] == ids[a]


def footprint(placement: dict, mesh: dict, grid: Grid, pick) -> np.ndarray:
    """Where the groups of the model that `pick(group)` takes lie, seen from above."""
    img = Image.new("L", (grid.width, grid.height), 0)
    d = ImageDraw.Draw(img)
    for g in placement["groups"]:
        if not pick(g):
            continue
        v, t = mesh[g["i"]]
        c, rr = grid.pix(v[:, 0], v[:, 1])
        for tri in t:
            d.polygon([(float(c[k]), float(rr[k])) for k in tri], fill=255)
    return np.asarray(img) > 0


def _window(mask: np.ndarray, ys: slice, xs: slice, pad: int) -> np.ndarray:
    """The mask in a box grown by `pad` pixels; false where the box leaves the array."""
    h, w = mask.shape
    y0, x0 = ys.start - pad, xs.start - pad
    out = np.zeros((ys.stop + pad - y0, xs.stop + pad - x0), bool)
    sy, sx = slice(max(0, y0), min(h, ys.stop + pad)), slice(max(0, x0), min(w, xs.stop + pad))
    out[sy.start - y0 : sy.stop - y0, sx.start - x0 : sx.stop - x0] = mask[sy, sx]
    return out


def _compact(mask: np.ndarray, low: float, high: float, test) -> np.ndarray:
    """The parts of a mask between `low` and `high` square yards that fill half their box or
    more and pass `test(part in a window 6 pixels wider, rows, columns)`."""
    out = np.zeros(mask.shape, bool)
    for (ys, xs), part in _parts(mask):
        area = part.sum() * YPP * YPP
        if low <= area <= high and part.sum() >= 0.5 * part.size and test(np.pad(part, 6), ys, xs):
            out[ys, xs] |= part
    return out


def canyon_masks(
    p: dict[str, np.ndarray],
    labels: np.ndarray,
    info: dict[int, dict],
    districts: set[str],
    outer: np.ndarray,
    cave: np.ndarray,
) -> tuple[np.ndarray, dict[int, str], dict[str, np.ndarray]]:
    """What the sheet draws of a city cut into rock (Orgrimmar; map.md "A canyon city"): the
    whole place is one model, its floor is what the walk mesh walks on it, and what stands above
    that floor is a house, a hut one cannot enter, a gate or the canyon's wall.

    `p` is the plan with `zl`, the walk raster's lowest floor. `districts` are the names that
    make no landmark, `outer` is where the model's outdoor groups stand (the gates), `cave` where
    the groups of its districts under the rock lie (`footprint`). -> as `masks`: the drawn
    houses, their status, and the masks house, other (huts one cannot enter), road, wall (the
    gates), green (none), gate (the gate tunnels), and besides water (the ponds inside), cave
    (the ways under the rock), cliff (the rock) and rock (its height above the floor, yards)."""
    walk, zh, paved = p["walk"], p["zh"], p["paved"]
    shape = labels.shape
    building = np.nan_to_num(p["building"], nan=-1e9)
    # the city's floor: walked on the model or on a road, closed over posts and crates, and in
    # one piece (a cave of another model nearby is walked indoors too)
    floor = D.shrink(D.grow((walk & 6) != 0, 4), 4)
    lab = components(floor)
    ids, counts = np.unique(lab[lab >= 0], return_counts=True)
    floor = lab == ids[counts.argmax()]
    floor0 = floor & ((walk & 6) != 0)
    level = D.fill_nan(np.where(floor0, zh, np.nan).astype("f4"))  # the floor's height, spread
    above = building - level
    roomed = labels >= 0

    drawn = np.full(shape, -1, "i4")
    tunnels = np.zeros(shape, bool)
    status: dict[int, str] = {}
    ids, counts = np.unique(labels[roomed], return_counts=True)
    for k in ids[np.argsort(-counts)]:  # small last: they stay on top
        m = labels == k
        inf = info[int(k)]
        # a room in a district under the rock draws no roof. How far the model stands above a
        # room does not tell: the canyon's walls lean over the huts at their foot (the inn has
        # 43 yards of rock above it, the auction house 48; measured 17.11.2026)
        if (m & cave).sum() > 0.5 * m.sum():
            status[int(k)] = "underground"
            continue
        # a way through: doors more than 22 yards apart, no landmark's name, and at most one
        # person of use inside (a gate has its guard)
        doors = np.array([d[:2] for d in inf["doors"]], "f8").reshape(-1, 2)
        apart = 0.0
        if len(doors) > 1:
            apart = float(np.sqrt(((doors[:, None] - doors[None]) ** 2).sum(-1)).max())
        landmark = bool(inf["names"]) and inf["names"][0] not in districts
        if apart > 22 and not landmark and sum(r["useful"] for r in inf["residents"]) <= 1:
            status[int(k)] = "passage"
            tunnels |= m
            continue
        shape_k = _regular(m, boxes=False)
        if int(m.sum()) * YPP * YPP > 900:
            shape_k = D.smooth_mask(shape_k, 3.0)
        drawn[shape_k & (drawn < 0) | m & (drawn < 0)] = k
        status[int(k)] = "house"
    house = drawn >= 0
    house_soft = D.smooth_mask(house, 0.8)
    gate = D.smooth_mask(D.shrink(D.grow(tunnels, 4), 4), 1.0) & ~house_soft

    # the ponds inside: water with the floor around it, not the river and the sea outside
    inside = D.grow(floor | house, round(25 / YPP))
    water = np.zeros(shape, bool)
    for box, part in _parts(p["water"]):
        if (part & inside[box]).sum() > 0.5 * part.sum():
            water[box] |= part

    road = (D.smooth_mask(floor, 2.4) & ~water & ~house_soft) | gate
    # what stands above the floor: the gates, huts one cannot enter, the canyon's wall
    mass = paved & ~road & ~house_soft & ~water & (above > 3)
    wall = D.smooth_mask(D.grow(D.shrink(mass & outer, 2), 2), 1.8) & ~road & ~house_soft
    # a hut one cannot enter: low, at least 5 yards wide, compact, with the floor around it
    ground = D.grow(road | house, 2)

    def stands_free(wide: np.ndarray, ys: slice, xs: slice) -> bool:
        rim = D.grow(wide, 4) & ~wide
        return (rim & _window(ground, ys, xs, 6)).sum() >= 0.6 * rim.sum()

    low = D.grow(D.shrink(mass & ~wall & (above < 45), 5), 5)
    other = D.smooth_mask(_compact(low, 50, 1800, stands_free), 3.0) & ~house_soft
    cliff = mass & ~wall & ~other

    # the ways under the rock: a cave district's lowest floor with the model 8 yards or more
    # above it (the rock over the cave is walked in places too, so the highest floor does not
    # tell), closed. The Cleft of Shadow is open to the sky in its middle: what of the district's
    # floor the shadow encloses lies in it too
    deep = np.where(floor0, building - np.nan_to_num(p["zl"], nan=1e9), 0.0)
    under = D.shrink(D.grow(cave & road & (deep > 8), 8), 8)
    for box, part in _parts(road & ~under):
        if not (part & ~cave[box]).any():
            under[box] |= part
    out = {
        "house": house,
        "other": other,
        "road": road,
        "wall": wall,
        "green": np.zeros(shape, bool),
        "gate": gate,
        "water": water,
        "cave": D.smooth_mask(under, 2.0) & road,
        "cliff": cliff,
        "rock": np.where(paved, np.clip(above, 0, 150), 0).astype("f4"),
    }
    return drawn, status, out


# a record of the world pack: [id] = [=[{ ... }]=]
_RECORD = re.compile(r"\[(\d+)\] = \[=\[(\{.*?\})\]=\]", re.S)
_TOKEN = re.compile(r'\s*(?:([{},])|"((?:[^"\\]|\\.)*)"|(-?[\d.]+(?:e-?\d+)?)|(nil|true|false))')


def lua_value(text: str):
    """A Lua table literal of positional values (tables, strings, numbers, nil, booleans) as
    Python lists: the world pack's records."""
    pos = 0

    def value():
        nonlocal pos
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"no value at {pos}: {text[pos : pos + 30]!r}")
        pos = m.end()
        brace, string, number, word = m.groups()
        if brace == "{":
            items = []
            while True:
                m = _TOKEN.match(text, pos)
                if m and m.group(1) == "}":
                    pos = m.end()
                    return items
                items.append(value())
                m = _TOKEN.match(text, pos)
                if m and m.group(1) == ",":
                    pos = m.end()
        if brace:
            raise ValueError(f"unexpected {brace} at {pos}")
        if string is not None:
            return re.sub(r"\\(.)", r"\1", string)
        if number is not None:
            return float(number) if any(ch in number for ch in ".e") else int(number)
        return {"nil": None, "true": True, "false": False}[word]

    return value()


def npcs_of(world_lua: str, ui: int, wx: tuple[float, float], wy: tuple[float, float]) -> list:
    """The place's NPCs from the world pack (`Bastians_Data_World/Generated/World.lua`): id,
    name, sub, flags and the world position of the first spawn on the UiMap, a measured source
    before a Classic one."""
    section = world_lua[world_lua.find("\n    npc = {") : world_lua.find("\n    object = {")]
    out = []
    for m in _RECORD.finditer(section):
        if f"{{ {ui}," not in m.group(2):
            continue
        t = lua_value(m.group(2))
        spawns = [s for s in (t[7] or []) if s[0] == ui]
        if not spawns:
            continue
        spawns.sort(key=lambda s: 0 if s[3] in SPAWN_ORDER else 1)
        s = spawns[0]
        out.append(
            {
                "id": int(m.group(1)),
                "name": t[0],
                "sub": t[1],
                "flags": list(t[5] or []),
                "wx": wx[1] - s[2] * (wx[1] - wx[0]),
                "wy": wy[1] - s[1] * (wy[1] - wy[0]),
                "wz": s[4] if len(s) > 4 else None,
                "src": s[3],
            }
        )
    return out
