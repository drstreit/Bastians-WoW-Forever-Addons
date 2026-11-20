"""The painted look of a city's sheet (docs/addons/map.md "The look on the sheet", owner
08.11.2026): on the game's painting, in this order, green ground and grass, painted water, every
tree and bush the client places, the walking ways with the gold passages, stone walls and hip
roofs on the real footprints; then through the upscaler that enlarged the painting, so what is
drawn carries its brushwork, the ways laid back on crisp.

`layers` brings the plan's masks (`city.masks`) onto the painting's pixels, `Painter` draws.
The numbers are the Stormwind prototype's look 6, kept as they were: Stormwind's tiles are
rebuilt byte for byte. Needs numpy and OpenCV, and for the brushwork torch and spandrel on a
GPU (the machine-learning venv, D:/bastians-ml/venv).
"""

from __future__ import annotations

import re
from pathlib import Path

import cv2
import numpy as np

from .city import PROTOTYPE_YPP, Frame, Grid

BANNER_PLANTS = (50, 60)  # pixels beside and below the title banner that stay free of plants
BANNER_WATER = (50, 80)  # a lake whose middle lies this near the banner is outside the city
MODEL = Path("D:/bastians-ml/models/RealESRGAN_x4plus_anime_6B.pth")

# every tree and bush the client places (world/.../trees/, bush/ ...; not lamps or helms:
# "streetlamp" holds "tree", "cloak" holds "oak", Orgrimmar's bone "spine" holds "pine")
BIG = re.compile(r"/trees/|tree|canopy|pine|oak|palm|willow", re.I)
SMALL = re.compile(r"bush|shrub|fern|/plants/", re.I)
NOT = re.compile(r"pumpkin|lamp|cloak|mushroom|spine", re.I)


def _tidy(f, close=0, min_area=0, hole=0):
    m = (f > 0.5).astype("u1")
    if close:
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close * 2 + 1, close * 2 + 1))
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, k)
    if min_area:
        _, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
        keep = st[:, cv2.CC_STAT_AREA] >= min_area
        keep[0] = False
        m = keep[lab].astype("u1")
    if hole:
        _, lab, st, _ = cv2.connectedComponentsWithStats(1 - m, connectivity=4)
        small = st[:, cv2.CC_STAT_AREA] < hole
        m = (m | small[lab]).astype("u1")
    return m > 0


def layers(water: np.ndarray, m: dict, drawn: np.ndarray, grid: Grid, frame: Frame) -> dict:
    """The real city as masks on the sheet's pixels, from the plan's water, `city.masks` and
    the drawn houses: houses, other (tall masses), walls, water, gate, ways (streets and
    passages as one clean, closed ribbon), green, and lab (the house label per pixel)."""
    a = frame.affine(grid)
    size = (frame.width, frame.height)
    # the numbers below are pixels of Stormwind's sheet; another sheet's are finer or coarser
    s = PROTOTYPE_YPP / frame.ypp

    def up(mask, sigma=0.0):
        f = cv2.warpAffine(mask.astype("f4"), a, size, flags=cv2.INTER_LINEAR)
        return cv2.GaussianBlur(f, (0, 0), sigma * s) if sigma else f

    def tidy(f, close=0, min_area=0, hole=0):
        return _tidy(f, round(close * s), round(min_area * s * s), round(hole * s * s))

    houses = tidy(up(drawn >= 0, 1.2))
    other = tidy(up(m["other"], 2.0), close=4, min_area=500) & ~houses
    walls = tidy(up(m["wall"], 5.0), min_area=600) & ~houses & ~other
    water = tidy(up(water, 3.0), min_area=300)
    gate = tidy(up(m["gate"], 2.0), min_area=200)
    ways = up(m["road"] | m["gate"], 4.5)
    ways = tidy(ways, close=9, min_area=9000, hole=2600) & ~houses & ~water | gate
    # no spurs: a way is at least 6 yards wide
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (round(6 * s) * 2 + 1,) * 2)
    ways = cv2.morphologyEx(ways.astype("u1"), cv2.MORPH_OPEN, k) > 0
    ways = ways | gate
    soft = cv2.GaussianBlur(ways.astype("f4"), (0, 0), 8.0 * s)
    ways = tidy(soft, min_area=9000) & ~water | gate
    green = tidy(up(m["green"], 6.0), min_area=2000) & ~ways & ~houses & ~water
    lab = cv2.warpAffine(drawn.astype("f4"), a, size, flags=cv2.INTER_NEAREST)
    out = {
        "houses": houses,
        "other": other,
        "walls": walls,
        "water": water,
        "gate": gate,
        "ways": ways,
        "green": green,
        "lab": lab.astype("i4"),
    }
    if "cliff" in m:  # a canyon city: the rock and its height above the floor, yards
        out["cliff"] = tidy(up(m["cliff"], 2.0)) & ~ways & ~houses & ~other & ~walls & ~water
        out["cave"] = tidy(up(m["cave"], 3.0), close=6, hole=2600) & ways
        out["rock"] = cv2.warpAffine(m["rock"], a, size, flags=cv2.INTER_LINEAR)
    return out


def plants(doodads: np.ndarray, frame: Frame) -> dict[str, np.ndarray]:
    """The placed models (`scene.Region.doodads`) on the sheet: x, y, radius, height, file."""
    x, y = frame.of_world(doodads["wx"], doodads["wy"])
    return {
        "x": x.astype("f4"),
        "y": y.astype("f4"),
        "r": doodads["radius"],
        "h": doodads["height"],
        "fd": doodads["fdid"],
    }


def blur(a, s):
    return cv2.GaussianBlur(a.astype("f4"), (0, 0), s)


def grow(m, r):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (r * 2 + 1, r * 2 + 1))
    return cv2.dilate(m.astype("u1"), k) > 0


def shrink(m, r):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (r * 2 + 1, r * 2 + 1))
    return cv2.erode(m.astype("u1"), k) > 0


def mix(a, b, t):
    t = t[..., None] if getattr(t, "ndim", 0) == 2 else t
    return a * (1 - t) + b * t


def col(*c):
    return np.array(c, "f4")


def shade(h, sx=-0.7, sy=-0.7, k=1.0):
    gx = cv2.Sobel(h, cv2.CV_32F, 1, 0, ksize=3) / 8 * k
    gy = cv2.Sobel(h, cv2.CV_32F, 0, 1, ksize=3) / 8 * k
    n = np.sqrt(gx**2 + gy**2 + 1)
    return ((-gx * sx - gy * sy + 0.65) / n / np.sqrt(sx**2 + sy**2 + 0.65**2)).clip(0, 1)


def fade(terms: list, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """Where a drawn ground dissolves into the painting: the product of its terms, each
    [side, at, width] in sheet pixels (0 at `at`, 1 from `width` pixels further inside)."""
    out = None
    for side, at, width in terms:
        d = {"left": xs - at, "right": at - xs, "top": ys - at, "bottom": at - ys}[side]
        t = np.clip(d / width, 0, 1)
        out = t if out is None else out * t
    return np.ones(xs.shape, "f4") if out is None else out.astype("f4")


def _near(box, margin, x, y):
    """Whether x, y lie in the box [x0, y0, x1, y1] grown by (beside, above and below)."""
    x0, y0, x1, y1 = box
    return (x > x0 - margin[0]) & (x < x1 + margin[0]) & (y < y1 + margin[1]) & (y > y0 - margin[1])


class Painter:
    """One sheet. `base` is the painting (float RGB, 0..1), `lay` the city on its pixels
    (`layers`), `placed` the models (`plants`), `names` their file names by FileDataID,
    `look` the place's `painted` table of tools/cities.toml."""

    def __init__(self, base, lay: dict, placed: dict, names: dict, look: dict, ypp: float):
        self.base = base
        self.h, self.w = lay["ways"].shape
        h, w = self.h, self.w
        self.ypp = ypp
        self.model = None
        banner = look.get("banner") or []  # one box or several: the title and the crest
        banner = [banner] if banner and not isinstance(banner[0], list) else banner
        self.ways, self.gate, self.walls = lay["ways"], lay["gate"], lay["walls"]
        self.houses, self.other, self.green = lay["houses"], lay["other"], lay["green"]
        houses, other, walls, ways = self.houses, self.other, self.walls, self.ways

        n, cc, _, cent = cv2.connectedComponentsWithStats(lay["water"].astype("u1"), connectivity=8)
        keep = np.ones(n, bool)
        keep[0] = False
        for box in banner:  # lakes behind the banner are outside the city
            keep[_near(box, BANNER_WATER, cent[:, 0], cent[:, 1])] = False
        self.water = water = keep[cc] & ~ways
        self.city = houses | other | walls | ways | water
        self.ys, self.xs = ys, xs = np.mgrid[0:h, 0:w]
        self.wfade = fade(
            look.get("water_fade", []), xs, ys
        )  # the sea dissolves into the painting's
        self.gfade = fade(look.get("green_fade", []), xs, ys)
        boxed = np.zeros((h, w), bool)
        for x0, y0, x1, y1 in banner:
            boxed |= (xs > x0) & (xs <= x1) & (ys >= y0) & (ys < y1)
        self.banner = 1 - blur(boxed.astype("f4"), 40)
        self.near_city = blur(grow(houses | other | walls | ways, 40), 60) > 0.25
        self.keep = np.zeros((h, w), bool)
        for x0, y0, x1, y1 in look.get("keep", []):
            self.keep[y0:y1, x0:x1] = True
        self.paint = blur(base, 26)
        self.cliff, self.rock_height, self.cave = lay.get("cliff"), lay.get("rock"), lay.get("cave")
        self.stone = col(*look.get("stone", (0.68, 0.64, 0.58)))
        self.way_tone = col(*look.get("ways", (0.90, 0.83, 0.66)))
        self.inside_only = look.get("plants") == "inside"

        # rooms and small roofs: each its own hip roof
        _, cl = self.voronoi(82, 7)
        regions = np.where(houses, lay["lab"], -1)
        regions = np.where(other, 100000 + cl, regions)
        self.roof = roof = houses | other
        edge_x = regions != np.roll(regions, 1, axis=1)
        edge_y = regions != np.roll(regions, 1, axis=0)
        src = (roof & ~(edge_x | edge_y)).astype("u1")
        self.rd = rd = cv2.distanceTransform(src, cv2.DIST_L2, 5).astype("f4")
        cap = 44.0
        self.rh = np.minimum(rd, cap)
        ridge = (rd >= cv2.dilate(rd, np.ones((3, 3), "u1")) - 0.02) & (rd > 5) & (rd < cap)
        self.ridge = grow(ridge, 1)
        ids = np.unique(regions)
        r2 = np.random.default_rng(5)
        r2.random(len(ids))  # the prototype drew a table here first; the roofs' tones follow it
        jv = r2.random(len(ids), dtype="f4")
        self.house_jit = jv[np.searchsorted(ids, regions)]
        self.wall_d = cv2.distanceTransform(walls.astype("u1"), cv2.DIST_L2, 5).astype("f4")
        # the district of every roof: nearest of the painting's own names
        districts = look["district"]
        _, comp_r, _, cent_r = cv2.connectedComponentsWithStats(roof.astype("u1"), connectivity=4)
        dx = np.array([d["at"][0] for d in districts], "f4")
        dy = np.array([d["at"][1] for d in districts], "f4")
        nearest = np.argmin((cent_r[:, 0, None] - dx) ** 2 + (cent_r[:, 1, None] - dy) ** 2, axis=1)
        self.roof_dist = nearest[comp_r]
        self.roof_lut = np.array([d["roof"] for d in districts], "f4")

        self.cob_d, cob_l = self.voronoi(9, 11)
        cob_rand = np.random.default_rng(3).random(h * w // 40, dtype="f4")
        self.cob_jit = cob_rand[cob_l % len(cob_rand)]
        self.way_inner = cv2.distanceTransform(ways.astype("u1"), cv2.DIST_L2, 5).astype("f4")
        self.sea_d = cv2.distanceTransform(water.astype("u1"), cv2.DIST_L2, 5).astype("f4")
        self.grain = self.noise(5, 2, 21)
        self.broad = self.noise(240, 3, 22)
        self.mid = self.noise(30, 3, 23)
        lum = blur(base.mean(2), 40)
        self.tie = (lum / lum.mean()) ** 0.55

        self.trees, self.counts = self.pick_plants(placed, names, banner)

    def voronoi(self, spacing, seed):
        r = np.random.default_rng(seed)
        n = int(self.w * self.h / spacing**2)
        src = np.ones((self.h, self.w), "u1")
        src[r.integers(0, self.h, n), r.integers(0, self.w, n)] = 0
        d, lab = cv2.distanceTransformWithLabels(
            src, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL
        )
        return d.astype("f4"), lab.astype("i4")

    def noise(self, cell, octaves=3, seed=0):
        h, w = self.h, self.w
        r = np.random.default_rng(seed)
        out, amp, tot = np.zeros((h, w), "f4"), 1.0, 0.0
        for i in range(octaves):
            c = max(1, cell / 2**i)
            n = r.random((int(h / c) + 3, int(w / c) + 3), dtype="f4")
            out += amp * cv2.resize(n, (w, h), interpolation=cv2.INTER_CUBIC)
            tot += amp
            amp *= 0.5
        return np.clip(out / tot, 0, 1)

    def pick_plants(self, placed, names, banner):
        """Every tree and bush the client places here: (x, y, radius, height, kind), north
        first. Forever's new trees have no file name: tall ones are trees, their box holds the
        widest branch."""
        out = []
        counts = {"tree": 0, "bush": 0, "unnamed_tree": 0, "skipped_banner": 0}
        for x, y, r, h, f in zip(
            placed["x"], placed["y"], placed["r"], placed["h"], placed["fd"], strict=True
        ):
            name = names.get(str(int(f)), "")
            if NOT.search(name) or not (0 <= x < self.w and 0 <= y < self.h):
                continue
            rad = float(r)
            if "/unknown/" in name:
                if h < 20:
                    continue
                kind, rad, tag = "tree", rad * 0.35, "unnamed_tree"
            elif BIG.search(name):
                kind, tag = "tree", "tree"
            elif SMALL.search(name):
                kind, tag = "bush", "bush"
            else:
                continue
            if any(_near(box, BANNER_PLANTS, x, y) for box in banner):
                counts["skipped_banner"] += 1
                continue
            if self.inside_only and not self.near_city[int(y), int(x)]:
                counts["skipped_outside"] = counts.get("skipped_outside", 0) + 1
                continue
            counts[tag] += 1
            out.append((float(x), float(y), rad, float(h), kind))
        out.sort(key=lambda t: t[1])
        return out, counts

    def cast(self, out, mask, dx, dy, s, amount, tint=None):
        tint = col(0.12, 0.07, 0.04) if tint is None else tint
        m = cv2.warpAffine(
            mask.astype("f4"), np.float32([[1, 0, dx], [0, 1, dy]]), (self.w, self.h)
        )
        return mix(out, out * tint * 2.2, blur(m, s) * amount * (~mask))

    def draw_trees(self, out, seed=17):
        """Each plant at its place, its crown from the model's own radius, larger than life: a
        map symbol; bushes low and small."""
        h, w = self.h, self.w
        r = np.random.default_rng(seed)
        can = np.zeros((h, w), "f4")
        tone = np.zeros((h, w), "f4")
        for x, y, rad, _height, kind in self.trees:
            if kind == "tree":
                yards = np.clip(rad, 3.0, 11.0) * 1.6
            else:
                yards = np.clip(rad, 1.5, 4.0) * 1.35
            full = yards / self.ypp
            v = float(r.uniform(0.0, 1.0))
            for i in range(4 if kind == "tree" else 2):
                R = float(full * r.uniform(0.55, 0.85))
                ang, far = r.uniform(0, 6.28), full * r.uniform(0.1, 0.42) * (i > 0)
                ox, oy = np.cos(ang) * far, np.sin(ang) * far
                x0, x1 = int(max(0, x + ox - R - 2)), int(min(w, x + ox + R + 3))
                y0, y1 = int(max(0, y + oy - R - 2)), int(min(h, y + oy + R + 3))
                if x1 <= x0 or y1 <= y0:
                    continue
                yy, xx = np.mgrid[y0:y1, x0:x1]
                q = np.sqrt(np.clip(1 - ((xx - x - ox) ** 2 + (yy - y - oy) ** 2) / R**2, 0, 1))
                q = q * R * (1.0 if kind == "tree" else 0.6)
                top = q > can[y0:y1, x0:x1]
                can[y0:y1, x0:x1] = np.where(top, q, can[y0:y1, x0:x1])
                tone[y0:y1, x0:x1] = np.where(top & (q > 0), v, tone[y0:y1, x0:x1])
        leaf = can * (0.86 + self.mid * 0.3 + (self.grain - 0.5) * 0.25)
        mask = (can > 0.2) & ~self.water
        s = shade(blur(leaf, 0.7), k=1.5)
        dark, lit = col(0.08, 0.20, 0.08), col(0.50, 0.66, 0.22)
        t = np.clip(s * 1.25 - 0.16 + (self.grain - 0.5) * 0.45 + (tone - 0.5) * 0.28, 0, 1)
        ones = np.ones((h, w, 1), "f4")
        c = mix(dark[None, None] * ones, lit[None, None] * ones, t)
        out = self.cast(out, mask, 5, 7, 4, 0.75)
        out = mix(out, c, blur(mask, 0.8))
        rim = blur(mask, 0.7) * (1 - blur(shrink(mask, 2), 0.7))
        return mix(out, col(0.05, 0.12, 0.05), rim * 0.8)

    def lay_ways(self, out, fill, line, width=4):
        """The ways: a clean ribbon with a crisp inked edge, and the gold passages over it."""
        gold, gold_line = col(0.95, 0.74, 0.24), col(0.36, 0.22, 0.05)
        a = blur(self.ways, 1.0)
        edge = blur(grow(self.ways, width), 1.0)
        out = mix(out, line, edge)
        out = mix(out, fill, a)
        if self.cave is not None:  # the ways under the rock lie in its shadow
            out = mix(out, fill * col(0.60, 0.52, 0.72), blur(self.cave, 3.0) * a)
        ga = blur(self.gate, 1.0)
        out = mix(out, gold_line, blur(grow(self.gate, 3), 1.0))
        return mix(out, gold, ga)

    def cobbles(self, light=1.0):
        bright = (1 - np.clip(self.cob_d / 5.0, 0, 1)) ** 0.6
        c = self.way_tone[None, None] * (0.965 + 0.06 * self.cob_jit[..., None])
        c = c * (0.955 + 0.07 * bright[..., None]) * light
        centre = np.clip(self.way_inner / 40, 0, 1)
        return c * (0.98 + 0.05 * centre[..., None])

    def painted_water(self):
        ones = np.ones((self.h, self.w, 1), "f4")
        sea_d, mid, ys = self.sea_d, self.mid, self.ys
        deep = col(0.08, 0.32, 0.42)[None, None]
        shal = col(0.27, 0.58, 0.62)[None, None]
        t = np.clip(sea_d / 80, 0, 1)
        c = mix(shal * ones, deep * ones, np.clip(t + (mid - 0.5) * 0.5, 0, 1))
        shim = (0.5 + 0.5 * np.sin((ys + mid * 70) * 2 * np.pi / 26)) ** 12 * np.clip(
            sea_d / 30, 0, 1
        )
        c = c + shim[..., None] * col(0.16, 0.22, 0.22)
        foam = (0.5 + 0.5 * np.sin(sea_d * 2 * np.pi / 15 + mid * 3)) ** 8
        foam = foam * np.clip(1 - sea_d / 34, 0, 1)
        return np.clip(c + foam[..., None] * col(0.26, 0.30, 0.26), 0, 1)

    def forest(self):
        """The dark green between the trees: texture, not placed trees."""
        ones = np.ones((self.h, self.w, 1), "f4")
        count = self.h * self.w // 300
        d, lab = self.voronoi(22, 31)
        canopy = np.sqrt(np.clip(1 - (d / 19) ** 2, 0, 1)) * 12
        s = shade(blur(canopy, 0.8), k=1.4)
        r = np.random.default_rng(4).random(count, dtype="f4")[lab % count]
        dark, lit = col(0.06, 0.19, 0.09), col(0.38, 0.55, 0.17)
        t = np.clip(s * 1.1 - 0.14 + (r - 0.5) * 0.25 + (self.mid - 0.5) * 0.7, 0, 1)
        return mix(dark[None, None] * ones, lit[None, None] * ones, t) * 0.82

    def rock(self, out):
        """A canyon city's rock: boulders lit from the north-west over the model's own relief
        above the floor, with a line every few yards of height. It dissolves into the parchment
        between 22 and 60 yards from what is drawn, and never lies on the title or the crest."""
        ones = np.ones((self.h, self.w, 1), "f4")
        height = blur(self.rock_height, 2.5)
        relief = shade(height / self.ypp, k=0.3)
        count = self.h * self.w // 500
        d, lab = self.voronoi(34, 41)
        boulders = shade(blur(np.sqrt(np.clip(1 - (d / 30) ** 2, 0, 1)) * 9, 0.8), k=1.3)
        facet = np.random.default_rng(6).random(count, dtype="f4")[lab % count]
        t = 0.55 * relief + 0.6 * boulders - 0.14 + (facet - 0.5) * 0.22 + (self.mid - 0.5) * 0.3
        dark, lit = col(0.24, 0.10, 0.06)[None, None], col(0.76, 0.47, 0.27)[None, None]
        c = mix(dark * ones, lit * ones, np.clip(t, 0, 1))
        strata = (0.5 + 0.5 * np.sin(height * 2 * np.pi / 8 + self.mid * 3)) ** 6
        c = c * (1 - 0.22 * strata[..., None])
        c = mix(c, self.paint, 0.1)  # the painting's own colour stays in the rock
        drawn = self.ways | self.houses | self.other | self.walls | self.water
        away = cv2.distanceTransform((~drawn).astype("u1"), cv2.DIST_L2, 5)
        reach = np.clip(1.6 * (1 - away / (60 / self.ypp)), 0, 1)  # whole for 22 yards
        reach = reach * reach * (3 - 2 * reach)
        return mix(out, c, reach * blur(self.cliff, 12.0) * self.banner * 0.97)

    def battlements(self, out, stone, ink):
        xs, ys, walls = self.xs, self.ys, self.walls
        s = shade(blur(np.minimum(self.wall_d, 14.0), 1.0), k=1.3)
        tex = 0.5 + 0.5 * np.sin(xs * 2 * np.pi / 15) * np.sin(ys * 2 * np.pi / 9)
        c = stone * (0.62 + 0.55 * s)[..., None] * (0.92 + 0.13 * tex)[..., None]
        out = mix(out, c, blur(walls, 1.0))
        band = walls & ~shrink(walls, 5)
        crenel = band & (((xs + ys) // 15) % 2 == 0)
        out = mix(out, ink, crenel.astype("f4") * 0.75)
        return mix(out, ink, blur(grow(walls, 2), 0.6) * (1 - blur(walls, 0.6)))

    def roof_tone(self):
        c = self.roof_lut[self.roof_dist] * (0.8 + 0.42 * self.house_jit[..., None])
        return mix(c, self.paint * 0.9, 0.22)  # the painting's own colour stays in every roof

    def painted_roofs(self, out, tone):
        rd, roof, mid = self.rd, self.roof, self.mid
        s = shade(blur(self.rh, 0.7), k=1.6)
        courses = (0.5 + 0.5 * np.sin(rd * 2 * np.pi / 7)) ** 2
        across = 0.5 + 0.5 * np.sin((self.xs - self.ys + rd * 2) * 2 * np.pi / 13)
        c = tone * (0.46 + 0.86 * s)[..., None] * (0.85 + 0.2 * courses[..., None])
        c = c * (0.96 + 0.06 * across[..., None])
        c = c * (0.9 + 0.2 * mid[..., None])
        out = mix(out, c, blur(roof, 0.8))
        out = mix(out, col(0.96, 0.84, 0.56), self.ridge.astype("f4") * 0.45 * roof)
        line = blur(grow(roof, 2), 0.6) * (1 - blur(roof, 0.6))
        return mix(out, col(0.11, 0.07, 0.05), line)

    def painterly(self, img, factor=2, tile=512, ov=24):
        """Through the same upscaler that enlarged Blizzard's painting, so what we drew carries
        its brushwork."""
        import spandrel
        import torch

        if self.model is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
            self.model = spandrel.ModelLoader().load_from_file(str(MODEL)).model.eval().to(device)
            self.device = device
        h, w = self.h, self.w
        small = cv2.resize(
            np.clip(img, 0, 1).astype("f4"),
            (w // factor, h // factor),
            interpolation=cv2.INTER_AREA,
        )
        sh, sw = small.shape[:2]
        big = np.zeros((sh * 4, sw * 4, 3), "f4")
        step = tile - 2 * ov
        with torch.no_grad():
            for y in range(0, sh, step):
                for x in range(0, sw, step):
                    y0, x0 = max(0, y - ov), max(0, x - ov)
                    y1, x1 = min(sh, y + step + ov), min(sw, x + step + ov)
                    part = small[y0:y1, x0:x1].transpose(2, 0, 1)[None]
                    t = torch.from_numpy(part).to(self.device)
                    o = self.model(t).clamp(0, 1)[0].cpu().numpy().transpose(1, 2, 0)
                    a, b = (y - y0) * 4, (x - x0) * 4
                    ey, ex = min(step * 4, o.shape[0] - a), min(step * 4, o.shape[1] - b)
                    big[y * 4 : y * 4 + ey, x * 4 : x * 4 + ex] = o[a : a + ey, b : b + ex]
        return cv2.resize(big, (w, h), interpolation=cv2.INTER_AREA)

    def finish(self, full, tie=0.7):
        """The scene gets the brushwork and the parchment's mottling. The ways go back on
        crisp."""
        p = self.painterly(full)
        p = p * (1 + (self.tie[..., None] - 1) * tie)
        a = blur(grow(self.ways, 4), 0.8)
        return np.clip(mix(p, full, a), 0, 1)

    def sheet(self) -> np.ndarray:
        """The painted sheet, float RGB in 0..1."""
        ones = np.ones((self.h, self.w, 1), "f4")
        water, roof, walls = self.water, self.roof, self.walls
        mid, grain = self.mid, self.grain
        out = self.base.copy() * (0.9 + 0.06 * self.broad[..., None])
        if self.cliff is not None:
            # the painting's own drawing of the city goes where the real one is drawn: its huts
            # stand elsewhere, and no forest covers them as around Stormwind
            around = blur(grow(self.city, 130), 45) * (1 - blur(self.keep, 8.0))
            out = mix(out, blur(self.base, 110), around * 0.97)
            out = self.rock(out)
        else:
            # the land around the city, fading into the parchment
            around = blur(self.near_city, 90)
            around_m = np.clip(around * 1.5 - 0.15, 0, 1) * (1 - blur(self.city, 2))
            around_m = around_m * self.gfade * self.banner
            out = mix(out, self.forest(), around_m * 0.92 * (~water))
            dark, lit = col(0.28, 0.44, 0.15)[None, None], col(0.58, 0.68, 0.24)[None, None]
            grass = mix(dark * ones, lit * ones, np.clip(mid + (grain - 0.5) * 0.7, 0, 1))
            out = mix(out, grass, blur(self.green, 4) * self.gfade)
        out = mix(out, self.painted_water(), blur(water, 1.5) * self.wfade)
        shore = blur(grow(water, 6), 1) * (1 - blur(water, 1)) * 0.85 * self.wfade
        out = mix(out, col(0.76, 0.66, 0.42), shore)
        out = self.draw_trees(out)
        out = self.lay_ways(out, self.cobbles(), col(0.27, 0.18, 0.10))
        out = self.cast(out, roof | walls, 10, 14, 6, 0.72)
        out = self.battlements(out, self.stone, col(0.14, 0.10, 0.08))
        out = self.painted_roofs(out, self.roof_tone())
        out = mix(out, col(0.98, 0.78, 0.26), blur(self.gate, 1.0))
        if self.keep.any():  # the painting's own scroll lies on what is drawn
            under = self.base * (0.9 + 0.06 * self.broad[..., None])
            out = mix(out, under, blur(self.keep, 3.0))
        return self.finish(np.clip(out, 0, 1))
