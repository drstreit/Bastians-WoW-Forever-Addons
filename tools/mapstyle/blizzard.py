"""The Blizzard map as one seamless map (ADR 0036): the client's zone paintings, fully explored,
their lettering painted out and upscaled (tools/mapstyle/blizzard_clean.py, run in the ML
environment), placed by their UiMapAssignment frames and cut along the real zone borders.

- `Atlas` reads the client's map tables (clientdump db2 dumps) and assembles a painting with every
  explored-area overlay drawn in (`painting`).
- `far_image` paints a whole continent at FAR_PIXELS per ADT tile from the cleaned paintings (cities
  as their zones draw them), the open sea in the paintings' own sea tone with the continent
  painting's mottling, and the land no painting covers quilted from the paintings' own mountains
  around it; `blizzard_clean.py --far` blends the quilt's edge (LaMa) and upscales the image.
- `near_cell` paints one near cell at NEAR_PIXELS per tile from the cleaned paintings with the city
  plans; where no painting reaches it takes the upscaled far image, so cells meet without a seam.
- `labels` turns the readings (data/mapstyle/blizzard/<ui>.json) into place names in world yards,
  matched to their AreaTable ids where the name is the client's.

Rasters: row 0 is the north edge of tile row y0, column 0 the west edge of tile column x0
(scene.py)."""

from __future__ import annotations

import json
import re
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from functools import lru_cache
from itertools import combinations
from pathlib import Path

import numpy as np
from PIL import Image

from .cells import FAR_SPAN, NEAR_SPAN, tiles_of, write_rgba
from .draw import blur, grow, noise, shrink
from .scene import ORIGIN, TILE_YARDS, read_tile

NEAR_PIXELS = 256
FAR_PIXELS = 64
CHUNKS = 16  # area chunks per tile side
EDGE = 26  # painting pixels of torn border that fade out (on 1002 x 668)
SEA_EDGE = 160  # on the sea the painting dissolves over a wider band into ours
COAST = 14  # pixels at FAR_PIXELS (about 120 yards): how far out a painting keeps its own sea
MOTTLE = 0.5  # how much of the continent painting's sea variation shows
FEATHER = 3.0  # zone border softening, in pixels at FAR_PIXELS
CITY_PRIORITY = 0.02  # far: a city plan only where its zone's painting does not reach
ZONE = 3  # UiMap type of a zone (and of a capital's map)
CITY = (1453, 1454, 1455, 1456, 1457, 1458)  # the capitals' maps
CITY_ZONE = {1453: 1429, 1455: 1426, 1458: 1420, 1454: 1411, 1456: 1412, 1457: 1438}
TABLES = (
    "UiMap",
    "UiMapArt",
    "UiMapArtStyleLayer",
    "UiMapArtTile",
    "UiMapAssignment",
    "UiMapXMapArt",
    "WorldMapOverlay",
    "WorldMapOverlayTile",
    "AreaTable",
)


def _rows(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["rows"]


@dataclass
class Atlas:
    """The client's world map tables, reduced to what the painter needs (picklable)."""

    uimaps: dict[int, dict]
    art_of: dict[int, int]
    layer_of: dict[int, dict]  # UiMapArtID -> its layer-0 row
    art_tiles: dict[int, list[tuple[int, int, int]]]
    overlays: dict[int, list[dict]]
    overlay_tiles: dict[int, list[tuple[int, int, int]]]
    frames: dict[int, tuple[float, ...]]  # ui -> minx, miny, maxx, maxy, u0, v0, u1, v1
    map_of: dict[int, int]  # ui -> Map.db2 id
    zone_of_area: dict[int, int]  # AreaTable id -> zone UiMap (the area or an ancestor)
    areas: dict[int, tuple[str, int, int]]  # id -> name, parent, continent

    @classmethod
    def load(cls, dumps: Path, prefix: str) -> Atlas:
        t = {name: _rows(dumps / f"{prefix}_{name}.json") for name in TABLES}
        uimaps = {r["ID"]: r for r in t["UiMap"]}
        art_of: dict[int, int] = {}
        for r in t["UiMapXMapArt"]:
            if not r.get("PhaseID"):
                art_of.setdefault(r["UiMapID"], r["UiMapArtID"])
        style_of = {r["ID"]: r["UiMapArtStyleID"] for r in t["UiMapArt"]}
        layers = {r["UiMapArtStyleID"]: r for r in t["UiMapArtStyleLayer"] if not r["LayerIndex"]}
        layer_of = {a: layers[s] for a, s in style_of.items() if s in layers}
        art_tiles: dict[int, list] = {}
        for r in t["UiMapArtTile"]:
            if not r["LayerIndex"] and r["FileDataID"]:
                art_tiles.setdefault(r["UiMapArtID"], []).append(
                    (r["RowIndex"], r["ColIndex"], r["FileDataID"])
                )
        overlays: dict[int, list] = {}
        for r in t["WorldMapOverlay"]:
            overlays.setdefault(r["UiMapArtID"], []).append(
                {k: r[k] for k in ("ID", "OffsetX", "OffsetY", "TextureWidth", "TextureHeight")}
            )
        overlay_tiles: dict[int, list] = {}
        for r in t["WorldMapOverlayTile"]:
            if not r["LayerIndex"] and r["FileDataID"]:
                overlay_tiles.setdefault(r["WorldMapOverlayID"], []).append(
                    (r["RowIndex"], r["ColIndex"], r["FileDataID"])
                )
        frames: dict[int, tuple[float, ...]] = {}
        map_of: dict[int, int] = {}
        zone_area: dict[int, int] = {}
        for r in sorted(t["UiMapAssignment"], key=lambda r: (r["UiMapID"], r["OrderIndex"])):
            ui = r["UiMapID"]
            if ui in frames:
                continue
            reg = r["Region"]
            (u0, v0), (u1, v1) = r["UiMin"], r["UiMax"]
            frames[ui] = (reg[0], reg[1], reg[3], reg[4], u0, v0, u1, v1)
            map_of[ui] = r["MapID"]
            if r["AreaID"] and uimaps.get(ui, {}).get("Type") == ZONE:
                zone_area[r["AreaID"]] = ui
        areas = {
            r["ID"]: (r["AreaName_lang"], r["ParentAreaID"], r["ContinentID"])
            for r in t["AreaTable"]
        }
        zone_of_area: dict[int, int] = {}
        for area in areas:
            a, hops = area, 0
            while a and hops < 8:
                if a in zone_area:
                    zone_of_area[area] = zone_area[a]
                    break
                a = areas.get(a, ("", 0, 0))[1]
                hops += 1
        return cls(
            uimaps,
            art_of,
            layer_of,
            art_tiles,
            overlays,
            overlay_tiles,
            frames,
            map_of,
            zone_of_area,
            areas,
        )

    def zones(self, continent: int) -> list[int]:
        """The zone and city maps with a painting on a continent."""
        return sorted(
            ui
            for ui, r in self.uimaps.items()
            if r["Type"] == ZONE and ui in self.art_of and self.map_of.get(ui) == continent
        )

    def painting(self, ui: int, textures: Path, explored: bool = True) -> Image.Image:
        """Blizzard's painting of a map with every explored-area overlay drawn in."""
        art = self.art_of[ui]
        lay = self.layer_of[art]
        w, h = lay["LayerWidth"], lay["LayerHeight"]
        tw, th = lay["TileWidth"], lay["TileHeight"]
        img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
        for row, col, fdid in self.art_tiles[art]:
            img.paste(Image.open(textures / f"{fdid}.png").convert("RGBA"), (col * tw, row * th))
        if explored:
            for o in self.overlays.get(art, []):
                for row, col, fdid in self.overlay_tiles.get(o["ID"], []):
                    tile = Image.open(textures / f"{fdid}.png").convert("RGBA")
                    x, y = o["OffsetX"] + col * 256, o["OffsetY"] + row * 256
                    cw = min(tile.width, o["OffsetX"] + o["TextureWidth"] - x)
                    ch = min(tile.height, o["OffsetY"] + o["TextureHeight"] - y)
                    if cw > 0 and ch > 0:
                        img.alpha_composite(tile.crop((0, 0, cw, ch)), (x, y))
        return img.convert("RGB")

    def fdids(self) -> list[int]:
        """Every texture the paintings and overlays use (for clientdump textures)."""
        out = {f for tiles in self.art_tiles.values() for _, _, f in tiles}
        out |= {f for tiles in self.overlay_tiles.values() for _, _, f in tiles}
        return sorted(out)


# --- rasters -----------------------------------------------------------------------------------


@dataclass(frozen=True)
class Rect:
    """Tiles x0..x1, y0..y1 (inclusive) at n pixels per tile."""

    x0: int
    y0: int
    x1: int
    y1: int
    n: int

    @property
    def h(self) -> int:
        return (self.y1 - self.y0 + 1) * self.n

    @property
    def w(self) -> int:
        return (self.x1 - self.x0 + 1) * self.n

    @property
    def ypp(self) -> float:
        return TILE_YARDS / self.n

    @property
    def row0(self) -> int:
        return self.y0 * self.n

    @property
    def col0(self) -> int:
        return self.x0 * self.n


def continent_rect(folder: Path, n: int, margin: int = 1) -> Rect:
    xy = tiles_of(folder)
    xs, ys = [x for x, _ in xy], [y for _, y in xy]
    return Rect(min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin, n)


def ground(folder: Path, rect: Rect, atlas: Atlas) -> tuple[np.ndarray, np.ndarray]:
    """(owner, sea) at the rect's pixels: the zone UiMap each pixel belongs to (0 = none), and
    whether it is water or outside every tile (open sea)."""
    have = set(tiles_of(folder))
    cols, rows = rect.x1 - rect.x0 + 1, rect.y1 - rect.y0 + 1
    owner_chunks = np.zeros((rows * CHUNKS, cols * CHUNKS), "i4")
    sea = np.ones((rect.h, rect.w), bool)
    zone = np.vectorize(lambda a: atlas.zone_of_area.get(int(a), 0), otypes=["i4"])
    for tx in range(rect.x0, rect.x1 + 1):
        for ty in range(rect.y0, rect.y1 + 1):
            if (tx, ty) not in have:
                continue
            t = read_tile(folder / f"{tx}_{ty}.bmd.gz")
            r, c = ty - rect.y0, tx - rect.x0
            owner_chunks[r * CHUNKS : (r + 1) * CHUNKS, c * CHUNKS : (c + 1) * CHUNKS] = zone(
                t.area
            )
            wet = t.liquid > 0
            if t.n != rect.n:
                wet = (
                    np.asarray(
                        Image.fromarray(wet.astype("u1") * 255).resize(
                            (rect.n, rect.n), Image.Resampling.BILINEAR
                        )
                    )
                    > 127
                )
            sea[r * rect.n : (r + 1) * rect.n, c * rect.n : (c + 1) * rect.n] = wet
    s = max(1, rect.n // CHUNKS)
    owner = np.kron(owner_chunks, np.ones((s, s), "i4"))
    if owner.shape != sea.shape:  # fewer pixels than chunks: take every chunk's centre
        k = CHUNKS // rect.n
        owner = owner_chunks[k // 2 :: k, k // 2 :: k]
    return owner, sea


def sample(atlas: Atlas, ui: int, img: Image.Image, rect: Rect) -> tuple[np.ndarray, np.ndarray]:
    """The painting resampled onto the rect (axis-aligned affine), and every pixel's distance to
    the painting's edge in Blizzard's pixels (1002 x 668), negative outside."""
    minx, miny, maxx, maxy, u0, v0, u1, v1 = atlas.frames[ui]
    big_w, big_h = img.size
    ypp = rect.ypp
    ax = ypp / (maxy - miny) * (u1 - u0) * big_w
    bx = (u0 + (maxy - ORIGIN + (rect.col0 + 0.5) * ypp) / (maxy - miny) * (u1 - u0)) * big_w - 0.5
    ay = ypp / (maxx - minx) * (v1 - v0) * big_h
    by = (v0 + (maxx - ORIGIN + (rect.row0 + 0.5) * ypp) / (maxx - minx) * (v1 - v0)) * big_h - 0.5
    out = img.transform(
        (rect.w, rect.h),
        Image.Transform.AFFINE,
        (ax, 0, bx + 0.5, 0, ay, by + 0.5),
        Image.Resampling.BICUBIC,
    )
    cs, rs = np.arange(rect.w) * ax + bx, np.arange(rect.h) * ay + by
    dc, dr = np.minimum(cs, big_w - 1 - cs), np.minimum(rs, big_h - 1 - rs)
    d = np.minimum(dr[:, None], dc[None, :]) * (1002 / big_w)
    return np.asarray(out, dtype="f4") / 255, d.astype("f4")


def paint(
    atlas: Atlas, rect: Rect, owner: np.ndarray, sea: np.ndarray, get_painting, cities: bool
) -> tuple[np.ndarray, np.ndarray]:
    """The zones of the rect blended along their borders: (image, coverage 0..1)."""
    own = owner.copy()
    city_mask = {c: own == c for c in CITY if (own == c).any()}
    if not cities:
        for c, z in CITY_ZONE.items():
            own[own == c] = z
    jobs = [(int(ui), own == ui, 1.0) for ui in np.unique(own) if ui]
    if not cities:
        jobs += [(c, m, CITY_PRIORITY) for c, m in city_mask.items()]
    acc = np.zeros((rect.h, rect.w, 3), "f4")
    wsum = np.zeros((rect.h, rect.w), "f4")
    feather = FEATHER * rect.n / FAR_PIXELS
    # on the sea a painting keeps its shore (Blizzard's hatching along the coast) and fades into
    # the open sea further out, so its own sea does not stand as a rectangle in ours
    coast = np.clip(blur((~sea).astype("f4"), COAST * rect.n / FAR_PIXELS) * 4, 0, 1)
    for ui, mask, prio in jobs:
        if ui not in atlas.art_of or ui not in atlas.frames:
            continue
        px, d = sample(atlas, ui, get_painting(ui), rect)
        fade = np.where(
            sea,
            np.clip((d - 8) / SEA_EDGE, 0, 1) ** 2 * coast,
            np.clip((d - 8) / (EDGE - 8), 0, 1),
        )
        m = blur(mask.astype("f4"), feather) * fade * prio
        acc += px * m[..., None]
        wsum += m
    img = acc / np.maximum(wsum, 1e-6)[..., None]
    return img, np.clip(wsum * 1.5, 0, 1)


def sea_paint(rect: Rect, tone) -> np.ndarray:
    """The open sea: the paintings' sea tone with a parchment grain anchored at the world (the same
    at every resolution, so near and far cells agree)."""
    broad = noise(rect.h, rect.w, rect.row0, rect.col0, 400 / rect.ypp, 11, 3)
    fine = noise(rect.h, rect.w, rect.row0, rect.col0, 18 / rect.ypp, 12, 2)
    shade = 1 + 0.05 * broad + 0.025 * fine
    return np.asarray(tone, "f4")[None, None, :] * shade[..., None]


def diffuse(img: np.ndarray, have: np.ndarray, scales=(4, 12, 36, 108, 324)) -> np.ndarray:
    """Holes take the colour of what surrounds them, from fine to coarse (LaMa's start)."""
    out = img.copy()
    for r in scales:
        wb = blur(have, r)
        est = np.stack([blur(out[..., k] * have, r) for k in range(3)], -1)
        est = est / np.maximum(wb, 1e-6)[..., None]
        a = (1 - have)[..., None]
        out = np.where((wb > 1e-4)[..., None], out * (1 - a) + est * a, out)
        have = np.maximum(have, np.clip(wb * 4, 0, 1))
    return out


QUILT_BLOCK, QUILT_OVERLAP, QUILT_CANDIDATES, QUILT_REACH = 32, 10, 300, 480


def quilt(img: np.ndarray, gap: np.ndarray, source: np.ndarray, seed: int = 7) -> np.ndarray:
    """Fills `gap` by image quilting (Efros and Freeman 2001): block by block, a patch of the
    painted land near the block (`source`) whose overlap with what is already there matches best,
    joined along the cheapest seam. The paintings' own mountains continue into the gap without a
    repeat. Deterministic for a seed."""
    out = img.copy()
    filled = ~gap
    h, w = gap.shape
    b, ov = QUILT_BLOCK, QUILT_OVERLAP
    step = b - ov
    rng = np.random.default_rng(seed)
    ok = source.copy()
    ok[h - b :, :] = False
    ok[:, w - b :] = False
    # a source patch must lie wholly on painted land
    from .draw import box as box_mean

    whole = box_mean(source.astype("f4"), b // 2) > 0.999
    ok &= np.roll(np.roll(whole, -(b // 2), 0), -(b // 2), 1)
    sy, sx = np.nonzero(ok)
    if len(sy) == 0:
        return out
    guide = img  # the gap holds the surroundings' diffused colour: each patch should fit it
    blocks = [
        (y, x)
        for y in range(0, h - ov, step)
        for x in range(0, w - ov, step)
        if gap[y : min(h, y + b), x : min(w, x + b)].any()
    ]
    threshold = 0.3
    while blocks:
        # from the edge inward: the blocks that already know most of their surroundings first
        known_part = [filled[y : y + b, x : x + b].mean() for y, x in blocks]
        ready = [i for i, k in enumerate(known_part) if k >= threshold and k < 1]
        if not ready:
            if all(k >= 1 for k in known_part):
                break
            threshold = max(0.0, threshold - 0.1)
            if threshold == 0.0:
                ready = [i for i, k in enumerate(known_part) if k < 1]
            else:
                continue
        ready.sort(key=lambda i: -known_part[i])
        for i in ready:
            y, x = blocks[i]
            y1, x1 = min(h, y + b), min(w, x + b)
            known = filled[y:y1, x:x1]
            if known.all():
                continue
            near = (np.abs(sy - y) < QUILT_REACH) & (np.abs(sx - x) < QUILT_REACH)
            idx = np.nonzero(near)[0] if near.any() else np.arange(len(sy))
            pick = rng.choice(idx, size=min(QUILT_CANDIDATES, len(idx)), replace=False)
            target = out[y:y1, x:x1]
            want = guide[y:y1, x:x1][~known].mean(0)
            errs = []
            for j in pick:
                py, px = sy[j], sx[j]
                patch = img[py : py + (y1 - y), px : px + (x1 - x)]
                e = ((patch - target) ** 2).sum(-1)
                fit = float((e * known).sum() / max(1, known.sum()))
                tone = float(((patch[~known].mean(0) - want) ** 2).sum())
                errs.append((fit + 3.0 * tone, j))
            errs.sort()
            # a little randomness among the best few keeps the texture from repeating
            j = errs[int(rng.integers(0, min(4, len(errs))))][1]
            patch = img[sy[j] : sy[j] + (y1 - y), sx[j] : sx[j] + (x1 - x)]
            g = gap[y:y1, x:x1]
            take = g & ~known  # what is still empty takes the patch
            # into the quilted neighbours (never the paintings) it fades over the overlap
            alpha = take.astype("f4")
            ring = take
            for k in range(1, ov + 1):
                grown = grow(ring, 1)
                alpha[grown & ~ring & g & known] = 1 - k / (ov + 1)
                ring = grown
            region = out[y:y1, x:x1]
            region[:] = region * (1 - alpha[..., None]) + patch * alpha[..., None]
            filled[y:y1, x:x1] |= take
        blocks = [
            blk for blk in blocks if not filled[blk[0] : blk[0] + b, blk[1] : blk[1] + b].all()
        ]
    return out


def _painting_source(atlas: Atlas, textures: Path, clean: Path):
    cache: dict[int, Image.Image] = {}

    def get(ui: int) -> Image.Image:
        if ui not in cache:
            path = clean / f"{ui}_x4.png"
            cache[ui] = (
                Image.open(path).convert("RGB") if path.is_file() else atlas.painting(ui, textures)
            )
        return cache[ui]

    return get


# Blizzard's drawings in the sea ("blizzard has some art deko on the sea part of
# the map, maybe we can mirror that"): boxes in a painting's pixels (1002 x 668), each drawing
# placed where Blizzard drew it through the painting's frame. The continents' ship, sea serpent,
# compass roses, kraken and whale; Westfall's and Stranglethorn's compass roses and sea dragon,
# which the zone paintings' sea would otherwise lose to the coast fade.
SEA_ART = {
    1415: [
        (14, 428, 178, 628),
        (785, 450, 980, 655),
        (715, 88, 790, 162),
        (262, 165, 335, 212),
        (622, 540, 700, 590),
    ],
    1414: [
        (14, 425, 178, 628),
        (795, 450, 980, 655),
        (665, 500, 742, 572),
        (122, 147, 172, 197),
        (240, 275, 345, 325),
        (625, 38, 705, 90),
    ],
    1436: [(108, 88, 185, 162)],
    1434: [(100, 222, 180, 298), (785, 440, 980, 650)],
}
SEA_ART_FADE = 10  # painting pixels over which a drawing fades in from its box's edge
SEA_ART_GRAIN = 0.05  # differences from the parchment below this are its grain, not the drawing
SEA_ART_INK = 1.3  # the strokes a little stronger: the drawings are enlarged and soften
INK_TINT = np.array([0.8, 1.0, 1.25], "f4")  # blue darkened most: brown strokes, as Blizzard's
_art_cache: dict[int, Image.Image] = {}


def ink(crop: np.ndarray) -> np.ndarray:
    """A drawing's ink as a factor for the sea below it (1 = unchanged): only what is darker than
    the parchment around it (lighter fills would show the box as a pale patch), by its darkness
    alone in one brown ink (a torn edge's tints stay out), fading in from the box's edges."""
    bg = np.stack([blur(crop[..., k], 14) for k in range(3)], -1)
    lum = (crop / np.maximum(bg, 1e-3) - 1).mean(-1, keepdims=True)
    dev = np.minimum(lum + SEA_ART_GRAIN, 0) * SEA_ART_INK * INK_TINT
    h, w = crop.shape[:2]
    ramp_y = np.clip(np.minimum(np.arange(h), h - 1 - np.arange(h)) / SEA_ART_FADE, 0, 1)
    ramp_x = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / SEA_ART_FADE, 0, 1)
    return 1 + dev * (ramp_y[:, None] * ramp_x[None, :])[..., None]


def _sea_art_image(atlas: Atlas, ui: int, textures: Path) -> Image.Image:
    """A painting's sea drawings as ink factors over the whole painting (128 = unchanged), for
    `sample` to place them through the painting's frame."""
    if ui in _art_cache:
        return _art_cache[ui]
    explored = atlas.uimaps.get(ui, {}).get("Type") == ZONE
    src = np.asarray(atlas.painting(ui, textures, explored=explored), dtype="f4") / 255
    ratio = np.ones_like(src)
    for x0, y0, x1, y1 in SEA_ART.get(ui, []):
        ratio[y0:y1, x0:x1] = ink(src[y0:y1, x0:x1])
    img = Image.fromarray(np.clip(ratio * 128, 0, 255).astype("u1"))
    _art_cache[ui] = img
    return img


def sea_art(atlas: Atlas, continent: int, rect: Rect, textures: Path) -> np.ndarray:
    """The sea drawings' shading over the rect (1 where there is none), to multiply the sea by."""
    out = np.ones((rect.h, rect.w, 3), "f4")
    for ui in SEA_ART:
        if atlas.map_of.get(ui) != continent or ui not in atlas.art_of:
            continue
        px, d = sample(atlas, ui, _sea_art_image(atlas, ui, textures), rect)
        out *= np.where((d >= 0)[..., None], px * (255 / 128), 1.0)
    return out


def far_rect(atlas: Atlas, folder: Path, continent: int) -> Rect:
    """The continent's tiles plus one, widened to its continent painting's frame (Blizzard's sea
    drawings lie far out), within the map's 64 x 64 tiles."""
    base = continent_rect(folder, FAR_PIXELS)
    painted = [
        ui
        for ui, r in atlas.uimaps.items()
        if r["Type"] == 2 and atlas.map_of.get(ui) == continent and ui in SEA_ART
    ]
    if not painted:
        return base
    minx, miny, maxx, maxy, *_ = atlas.frames[painted[0]]
    tx0, tx1 = int((ORIGIN - maxy) // TILE_YARDS), int((ORIGIN - miny) // TILE_YARDS)
    ty0, ty1 = int((ORIGIN - maxx) // TILE_YARDS), int((ORIGIN - minx) // TILE_YARDS)
    return Rect(
        max(0, min(base.x0, tx0)),
        max(0, min(base.y0, ty0)),
        min(63, max(base.x1, tx1)),
        min(63, max(base.y1, ty1)),
        FAR_PIXELS,
    )


def continent_sea(atlas: Atlas, continent: int, textures: Path, rect: Rect):
    """(inside, colour) of the continent's own painting over the rect, blurred so only its sea's
    mottling stays (its letters and drawings melt away); None without a continent painting."""
    painted = [
        ui
        for ui, r in atlas.uimaps.items()
        if r["Type"] == 2
        and atlas.map_of.get(ui) == continent
        and ui in atlas.art_of
        and atlas.layer_of.get(atlas.art_of[ui], {}).get("LayerWidth") == 1002
    ]
    if not painted:
        return None
    ui = painted[0]
    px, d = sample(atlas, ui, atlas.painting(ui, textures, explored=False), rect)
    colour = np.stack([blur(px[..., k], 60 * rect.n / FAR_PIXELS) for k in range(3)], -1)
    # its own torn border fades out, so the mottling has no edge
    return np.clip((d - 40) / 200, 0, 1), colour


def far_image(
    atlas: Atlas, folder: Path, continent: int, textures: Path, clean: Path, work: Path
) -> Path:
    """The whole continent at FAR_PIXELS per tile from the cleaned paintings (cities as their
    zones draw them), the open sea painted, the land no painting covers left for LaMa: writes
    far_image.png, far_gaps.png (white = to fill) and far_image.json (rect, sea tone)."""
    rect = far_rect(atlas, folder, continent)
    owner, sea = ground(folder, rect, atlas)
    img, have = paint(atlas, rect, owner, sea, _painting_source(atlas, textures, clean), False)
    painted_sea = sea & (have > 0.9)
    # the paintings' open water, not the parchment their sea fades into: the bluish pixels
    painted_sea &= img[..., 2] > img[..., 0]
    tone = img[painted_sea].mean(0) if painted_sea.sum() > 1000 else np.array([0.52, 0.55, 0.55])
    water = sea_paint(rect, tone)
    mottle = continent_sea(atlas, continent, textures, rect)
    if mottle is not None:  # the continent painting's blue-grey mottling, in the zones' tone
        weight, colour = mottle
        open_sea = sea & (weight > 0.5)
        if open_sea.any():  # its sea's own variation around its sea's mean, not its land's
            shift = colour - colour[open_sea].mean(0)
            water = water + (shift * MOTTLE) * weight[..., None]
    land = ~sea
    water = water * sea_art(atlas, continent, rect, textures)  # Blizzard's drawings in the sea
    gap = np.where(sea[..., None], water, diffuse(img, have))
    out = img * have[..., None] + gap * (1 - have)[..., None]
    # land no painting covers: the neighbouring paintings' own mountains, quilted
    land_gap = land & (have < 0.5)
    if land_gap.any():
        source = land & (have > 0.95)
        out = quilt(out, land_gap, source)
    work.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype("u1")).save(work / "far_image.png")
    # LaMa only blends the quilt's edge with the paintings
    band = grow(land_gap, 4) & ~shrink(land_gap, 4)
    Image.fromarray((band * 255).astype("u1")).save(work / "far_gaps.png")
    (work / "far_image.json").write_text(
        json.dumps(
            {
                "rect": [rect.x0, rect.y0, rect.x1, rect.y1, rect.n],
                "sea_tone": [float(v) for v in tone],
            }
        ),
        encoding="utf-8",
    )
    return work / "far_image.png"


def far_cells(filled: Path, continent: int, out: Path) -> list[str]:
    """The far cells (FAR_SPAN tiles at FAR_PIXELS) cut from the filled far image; beyond it the
    sea's tone."""
    meta = json.loads((filled.parent / "far_image.json").read_text(encoding="utf-8"))
    x0, y0, x1, y1, n = meta["rect"]
    img = Image.open(filled).convert("RGB")
    tone = tuple(int(v * 255) for v in meta["sea_tone"])
    side = FAR_SPAN * n
    written = []
    for fx in range(x0 // FAR_SPAN, x1 // FAR_SPAN + 1):
        for fy in range(y0 // FAR_SPAN, y1 // FAR_SPAN + 1):
            left, top = (fx * FAR_SPAN - x0) * n, (fy * FAR_SPAN - y0) * n
            cell = Image.new("RGB", (side, side), tone)
            box = (
                max(0, left),
                max(0, top),
                min(img.width, left + side),
                min(img.height, top + side),
            )
            if box[2] > box[0] and box[3] > box[1]:
                cell.paste(img.crop(box), (box[0] - left, box[1] - top))
            path = out / "blizzard" / "far" / f"{continent}_{fx}_{fy}.rgba"
            path.parent.mkdir(parents=True, exist_ok=True)
            write_rgba(path, cell)
            written.append(str(path))
    return written


@lru_cache(maxsize=10)
def _clean(clean: str, ui: int) -> Image.Image:
    return Image.open(Path(clean) / f"{ui}_x4.png").convert("RGB")


def near_cell(job: dict) -> str | None:
    """One near cell: the cleaned paintings with the city plans; the gaps from the filled far image
    (upscaled four times by blizzard_clean.py, else enlarged plainly) and the sea's grain."""
    atlas: Atlas = job["atlas"]
    cx, cy, folder = job["cx"], job["cy"], Path(job["data"])
    path = Path(job["out"]) / "blizzard" / "near" / f"{job['continent']}_{cx}_{cy}.rgba"
    if not job.get("force") and path.is_file():
        return None
    margin = 1  # one tile around, so the borders blur with their neighbours
    rect = Rect(
        cx * NEAR_SPAN - margin,
        cy * NEAR_SPAN - margin,
        cx * NEAR_SPAN + NEAR_SPAN - 1 + margin,
        cy * NEAR_SPAN + NEAR_SPAN - 1 + margin,
        NEAR_PIXELS,
    )
    owner, sea = ground(folder, rect, atlas)
    clean = job["clean"]

    def get(ui):
        if (Path(clean) / f"{ui}_x4.png").is_file():
            return _clean(clean, ui)
        return atlas.painting(ui, Path(job["textures"]))

    img, have = paint(atlas, rect, owner, sea, get, cities=True)
    meta = job["far_meta"]
    fx0, fy0, _, _, fn = meta["rect"]
    s = NEAR_PIXELS // fn
    big = Path(job["far_x4"])
    if big.is_file() and s == 4:
        far = np.load(big, mmap_mode="r")
        top, left = (rect.y0 - fy0) * NEAR_PIXELS, (rect.x0 - fx0) * NEAR_PIXELS
        base = np.empty((rect.h, rect.w, 3), "f4")
        base[:] = np.asarray(meta["sea_tone"], "f4")
        t0, l0 = max(0, top), max(0, left)
        t1, l1 = min(far.shape[0], top + rect.h), min(far.shape[1], left + rect.w)
        if t1 > t0 and l1 > l0:
            base[t0 - top : t1 - top, l0 - left : l1 - left] = far[t0:t1, l0:l1] / 255
    else:
        small = Image.open(job["far"]).convert("RGB")
        left, top = (rect.x0 - fx0) * fn, (rect.y0 - fy0) * fn
        base = small.crop((left, top, left + rect.w // s, top + rect.h // s)).resize(
            (rect.w, rect.h), Image.Resampling.BICUBIC
        )
        base = np.asarray(base, dtype="f4") / 255
    # the sea as the far image has it (the mottling included), with the grain at this scale
    tone = np.asarray(meta["sea_tone"], "f4")
    gap = np.where(sea[..., None], base + (sea_paint(rect, tone) - tone), base)
    out = img * have[..., None] + gap * (1 - have)[..., None]
    m = margin * NEAR_PIXELS
    side = NEAR_SPAN * NEAR_PIXELS
    cell = Image.fromarray((np.clip(out, 0, 1) * 255).astype("u1")).crop((m, m, m + side, m + side))
    path.parent.mkdir(parents=True, exist_ok=True)
    write_rgba(path, cell)
    return str(path)


def build(
    atlas: Atlas,
    folder: Path,
    continent: int,
    textures: Path,
    clean: Path,
    out: Path,
    workers: int,
    only: tuple[int, int, int, int] | None = None,
    force: bool = False,
) -> dict:
    """Step 1 writes the far image and its gap mask (blizzard/work_<continent>/);
    blizzard_clean.py --far fills the gaps with LaMa (far_filled.png) and upscales the result
    (far_x4.npy). Step 2, the same call again, cuts the far cells from the filled image and
    paints every near cell (or those of the tiles `only`)."""
    work = out / "blizzard" / f"work_{continent}"
    filled = work / "far_filled.png"
    if force or not (work / "far_image.png").is_file():
        far_image(atlas, folder, continent, textures, clean, work)
    if not filled.is_file():
        print(f"far image written; fill it: blizzard_clean.py --far {work}")
        return {"near": [], "far": []}
    far_written = far_cells(filled, continent, out)
    meta = json.loads((work / "far_image.json").read_text(encoding="utf-8"))
    cells = sorted({(x // NEAR_SPAN, y // NEAR_SPAN) for x, y in tiles_of(folder)})
    if only:
        x0, y0, x1, y1 = only
        cells = [
            c
            for c in cells
            if x0 // NEAR_SPAN <= c[0] <= x1 // NEAR_SPAN
            and y0 // NEAR_SPAN <= c[1] <= y1 // NEAR_SPAN
        ]
    jobs = [
        {
            "atlas": atlas,
            "cx": cx,
            "cy": cy,
            "data": str(folder),
            "out": str(out),
            "continent": continent,
            "clean": str(clean),
            "textures": str(textures),
            "far": str(filled),
            "far_x4": str(work / "far_x4.npy"),
            "far_meta": meta,
            "force": force,
        }
        for cx, cy in cells
    ]
    done = 0
    if workers > 1:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            for _ in pool.map(near_cell, jobs):
                done += 1
                if done % 10 == 0 or done == len(jobs):
                    print(f"  {done}/{len(jobs)} near cells", flush=True)
    else:
        for job in jobs:
            near_cell(job)
    return {"near": cells, "far": far_written}


# --- labels ------------------------------------------------------------------------------------

KIND_LEVEL = {"sea": 0, "city": 1, "place": 2}  # the zoom level a label shows from
CITY_PLACE_LEVEL = 3  # a city plan's districts: with the near cells


def _norm(s: str) -> str:
    s = re.sub(r"^the\s+", "", s.lower())
    return re.sub(r"[^a-z0-9]", "", s)


def lines_of(text: str, boxes: list[list[int]]) -> list[str]:
    """Blizzard's line breaks: as many lines as rows of boxes (a tall single box holds two),
    words split to match the rows' widths."""
    rows: list[list[float]] = []
    for b in sorted(boxes, key=lambda b: (b[1] + b[3]) / 2):
        cy = (b[1] + b[3]) / 2
        if rows and abs(rows[-1][0] - cy) < 6:
            rows[-1][1] += b[2] - b[0]
        else:
            rows.append([cy, b[2] - b[0]])
    words = text.split()
    if len(rows) == 1 and len(words) > 1 and (boxes[0][3] - boxes[0][1]) > 22:
        rows = [[0, 1.0], [1, 1.0]]  # two lines in one box (Sentinel Hill)
    k = min(len(rows), len(words))
    if k <= 1:
        return [text]
    want = np.array([r[1] for r in rows[:k]], float)
    want /= want.sum()
    best: tuple[float, list[str]] | None = None
    for cuts in combinations(range(1, len(words)), k - 1):
        bounds = zip((0, *cuts), (*cuts, len(words)), strict=True)
        parts = [" ".join(words[a:b]) for a, b in bounds]
        got = np.array([len(p) for p in parts], float)
        err = float(np.abs(got / got.sum() - want).sum())
        if best is None or err < best[0]:
            best = (err, parts)
    return best[1] if best else [text]


def labels(atlas: Atlas, readings: Path, folder: Path, continent: int) -> list[dict]:
    """The place, city and sea names of a continent's paintings in world yards: text (with
    Blizzard's line breaks), kind, wx, wy, the line height in yards, the AreaTable id when the
    name is the client's, and the zoom level it shows from."""
    by_name: dict[str, list[int]] = {}
    for area, (name, _, cont) in atlas.areas.items():
        if cont == continent:
            by_name.setdefault(_norm(name), []).append(area)
    rect = continent_rect(folder, CHUNKS, 0)
    owner, _ = ground(folder, rect, atlas)
    found: dict[str, dict] = {}
    for ui in atlas.zones(continent):
        path = readings / f"{ui}.json"
        if not path.is_file():
            continue
        minx, miny, maxx, maxy, *_ = atlas.frames[ui]
        for lab in json.loads(path.read_text(encoding="utf-8"))["labels"]:
            kind = lab["kind"]
            if kind == "neighbour" or (kind == "city" and ui in CITY):
                continue  # neighbours name themselves; a city plan's title: its zone's banner
            bs = lab["boxes"]
            x0, y0 = min(b[0] for b in bs), min(b[1] for b in bs)
            x1, y1 = max(b[2] for b in bs), max(b[3] for b in bs)
            lines = lines_of(lab["text"], bs)
            wy = maxy - (x0 + x1) / 2 / 1002 * (maxy - miny)
            wx = maxx - (y0 + y1) / 2 / 668 * (maxx - minx)
            height = (y1 - y0) / len(lines) / 668 * (maxx - minx)
            cands = by_name.get(_norm(lab["text"]), [])
            area = next((a for a in cands if atlas.zone_of_area.get(a) == ui), None)
            if area is None and cands:
                area = cands[0]
            if (
                area is None
            ):  # Blizzard shortened it on the painting (Northshire for Northshire Valley)
                key = _norm(lab["text"])
                area = next(
                    (
                        a
                        for a, (name, _, cont) in sorted(atlas.areas.items())
                        if cont == continent
                        and atlas.zone_of_area.get(a) == ui
                        and len(key) >= 5
                        and (_norm(name).startswith(key) or key.startswith(_norm(name)))
                    ),
                    None,
                )
            r = int((ORIGIN - wx) / rect.ypp) - rect.row0
            c = int((ORIGIN - wy) / rect.ypp) - rect.col0
            inside = 0 <= r < owner.shape[0] and 0 <= c < owner.shape[1] and owner[r, c] == ui
            level = CITY_PLACE_LEVEL if ui in CITY else KIND_LEVEL[kind]
            entry = {
                "text": "\n".join(lines),
                "kind": kind,
                "wx": round(wx, 1),
                "wy": round(wy, 1),
                "height": round(height, 1),
                "area": area,
                "level": level,
                "ui": ui,
                "inside": bool(inside),
            }
            key = str(area) if area else _norm(lab["text"])
            old = found.get(key)
            # a place two paintings name (Blackrock Mountain): the painting it lies in wins
            if old is None or (entry["inside"] and not old["inside"]):
                found[key] = entry
    return sorted(found.values(), key=lambda e: (e["level"], -e["height"], e["text"]))
