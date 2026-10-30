"""The Bastian map's renderer (ADR 0027): one prepared scene (the layers at the drawing resolution),
drawn by the rules of a style from pipeline/config/mapstyle.toml. Every style reads the same scene;
nothing here is random but the seeded noise, so the same inputs give the same image."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw

from . import draw as D
from .scene import Region, classify

TREE_KINDS = ("tree", "bush", "rock", "fence")


@dataclass
class Prepared:
    h: int
    w: int
    s: int
    ypp: float  # yards per drawn pixel
    z: np.ndarray
    shade: np.ndarray  # 0..1
    slope: np.ndarray  # degrees
    water: np.ndarray  # bool, smooth
    depth: np.ndarray  # yards below the surface, 0 on land
    lava: np.ndarray
    slime: np.ndarray
    classes: dict[str, np.ndarray]  # ground class -> weight 0..1
    road: np.ndarray  # bool
    roof: np.ndarray  # bool
    roof_shade: np.ndarray  # 0..1, from the WMO tops: each roof's own slopes
    roof_lines: np.ndarray  # bool: eaves, ridges and walls (steps in the WMO tops)
    roof_tone: np.ndarray  # -1..1 per building (a part of the roofs between the lines), 0 elsewhere
    structure: np.ndarray  # bool: bridges, walls, docks (WMO faces near the ground)
    fence: np.ndarray  # bool: M2 collision above the ground
    things: dict[str, np.ndarray]  # kind -> rows of (row, col, radius px)
    seed: int
    r0: int = 0  # the world raster's row and column of pixel (0, 0) at the drawing resolution
    c0: int = 0

    def noise(self, cell: float, salt: int, octaves: int = 3) -> np.ndarray:
        return D.noise(self.h, self.w, self.r0, self.c0, cell, self.seed * 1000 + salt, octaves)

    def hatch(self, angle: float, spacing: float, salt: int, wobble: float = 0.6) -> np.ndarray:
        return D.hatch(
            self.h, self.w, self.r0, self.c0, angle, spacing, self.seed * 1000 + salt, wobble
        )


def prepare(
    region: Region, names: dict[int, str], liquid_names: dict[int, str], cfg: dict
) -> Prepared:
    s = int(cfg["render"]["supersample"])
    ypp = region.yards_per_pixel / s
    ground = D.fill_nan(region.ground)
    z = D.upscale(ground, s)
    h, w = z.shape

    # liquids by class; a liquid counts where its surface lies above the ground
    lclass = {lid: classify(name.lower(), cfg["liquids"]) for lid, name in liquid_names.items()}
    surface = np.where(np.isnan(region.surface), -1e9, region.surface)
    # open sea where the map has no tile
    wet = ((region.liquid > 0) & (surface > ground - 0.3)) | ~region.present
    kinds = np.vectorize(lambda v: lclass.get(int(v)) or "water", otypes=[object])(region.liquid)
    lava = D.upscale((wet & (kinds == "lava")).astype("f4"), s) > 0.5
    slime = D.upscale((wet & (kinds == "slime")).astype("f4"), s) > 0.5
    water_f = D.upscale((wet & (kinds != "lava") & (kinds != "slime")).astype("f4"), s)
    water = D.blur(water_f, 1.5 * s) > 0.5
    below = np.where(~region.present, 40, np.where(wet, surface - ground, 0))
    depth = np.where(water, np.clip(D.upscale(below, s), 0, 40), 0)

    # ground classes by texture name
    classes: dict[str, np.ndarray] = {}
    for fdid, weights in region.textures.items():
        cls = classify(names.get(fdid, ""), cfg["ground"]) or "grass"
        classes[cls] = classes.get(cls, 0) + weights.astype("f4") / 255
    classes = {k: D.blur(D.upscale(np.clip(v, 0, 1), s), s) for k, v in classes.items()}
    road = D.blur(classes.get("road", np.zeros((h, w), "f4")), 1.5 * s) > 0.35

    # buildings: where a WMO has an indoor face, its top is a roof (the navmesh's indoor areas, ADR
    # 0026); the other WMO tops are streets, squares, bridges and docks
    floor = np.fmax(ground, np.where(np.isnan(region.surface), -1e9, region.surface))
    has = ~np.isnan(region.building)
    # a roof lies where an indoor WMO group's lowest face (the floor) is well under the highest
    # face over the pixel; an indoor floor that is the top itself is open to the sky (Orgrimmar's
    # streets, a courtyard) and counts as pavement
    covered = ~np.isnan(region.floor) & (
        (region.building - region.floor) > cfg["buildings"]["roof_above"]
    )
    roof = D.upscale(covered.astype("f4"), s, True) > 0.5
    roof = D.smooth_mask(roof, 0.5 * s)
    structure = D.upscale((has & (region.building > floor - 1)).astype("f4"), s, True) > 0.5
    # each roof's form: shaded from the tops, a line where the top steps (eave, ridge, wall)
    top = D.upscale(D.fill_nan(region.building), s)
    roof_shade = D.hillshade(top, ypp, 1.0)
    gy, gx = np.gradient(top, ypp)
    roof_lines = (np.hypot(gx, gy) > cfg["buildings"]["step"]) & D.grow(roof | structure, 0.5 * s)
    # one tone per building: the parts of the roofs between the lines, lighter or darker
    base_top = D.fill_nan(region.building)
    by, bx = np.gradient(base_top, region.yards_per_pixel)
    parts = D.components(covered & (np.hypot(bx, by) <= cfg["buildings"]["step"]))
    # the part's tone comes from its first pixel in world rows and columns, so a building that two
    # cells draw gets the same tone in both
    w0 = parts.shape[1]
    first_r, first_c = parts // w0 + region.row0, parts % w0 + region.col0
    tone = np.where(parts >= 0, D._hash(first_c, first_r, 7) * 2 - 1, 0.0).astype("f4")
    roof_tone = D.upscale(tone, s, True)
    fence = D.upscale(((region.object - ground) > 0.4).astype("f4"), s, True) > 0.5

    # trees, bushes, rocks, fences as points
    d = region.doodads
    row, col = region.pixel_of(d["wx"].astype("f8"), d["wy"].astype("f8"))
    kind = np.array(
        [classify(names.get(int(f), ""), cfg["models"]) for f in d["fdid"]], dtype=object
    )
    radius = d["radius"].astype("f4").copy()
    # a thing under a roof (a potted tree in a hall, a crate in a shop) is not seen from above
    ri = np.clip(np.round(row).astype(int), 0, region.ground.shape[0] - 1)
    ci = np.clip(np.round(col).astype(int), 0, region.ground.shape[1] - 1)
    over = region.building[ri, ci] - d["wz"]
    kind[np.nan_to_num(over, nan=-1e9) > cfg["buildings"]["under_roof"]] = None
    unnamed = np.array(
        [("/unknown/" in names.get(int(f), "/unknown/")) for f in d["fdid"]], dtype=bool
    )
    big = unnamed & (d["height"] >= cfg["unnamed"]["tree_min_height"])
    kind[big] = "tree"
    radius[big] *= cfg["unnamed"]["crown_share"]
    things = {}
    for k in TREE_KINDS:
        m = kind == k
        things[k] = (
            np.stack([(row[m] + 0.5) * s, (col[m] + 0.5) * s, radius[m] / ypp], axis=1)
            if m.any()
            else np.zeros((0, 3))
        )

    return Prepared(
        h,
        w,
        s,
        ypp,
        z,
        D.hillshade(z, ypp),
        D.slope(z, ypp),
        water,
        depth,
        lava,
        slime,
        classes,
        road,
        roof,
        roof_shade,
        roof_lines,
        roof_tone,
        structure & ~roof,
        fence,
        things,
        int(cfg["render"]["seed"]),
        region.row0 * s,
        region.col0 * s,
    )


def ground_colour(p: Prepared, palette: dict[str, str], base: np.ndarray) -> np.ndarray:
    """The ground classes' colours blended by their weights over `base`."""
    img = np.broadcast_to(base, (p.h, p.w, 3)).copy()
    total = np.zeros((p.h, p.w), "f4")
    acc = np.zeros((p.h, p.w, 3), "f4")
    for cls, weight in p.classes.items():
        colour = palette.get(cls)
        if colour:
            acc += weight[..., None] * D.rgb(colour)
            total += weight
    known = total > 0.01
    img[known] = acc[known] / total[known][..., None]
    return img


def _things_layer(p: Prepared, paint) -> np.ndarray:
    """Calls paint(draw, kind, row, col, radius) for every thing; trees last, on top."""
    layer = Image.new("RGBA", (p.w, p.h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    for kind in ("fence", "rock", "bush", "tree"):
        for r, c, rad in p.things.get(kind, ()):
            paint(dr, kind, float(r), float(c), float(rad))
    return np.asarray(layer).astype("f4") / 255


def _over(img: np.ndarray, layer: np.ndarray) -> np.ndarray:
    return D.mix(img, layer[..., :3], layer[..., 3])


def _c255(hexcode: str, a: int = 255) -> tuple[int, int, int, int]:
    return (*(int(hexcode[i : i + 2], 16) for i in (0, 2, 4)), a)


def _crown(p: Prepared, rad: float, lo: float, hi: float) -> float:
    """A crown's drawn radius: the model's own, kept between lo and hi yards."""
    return max(lo, min(hi, rad * p.ypp)) / p.ypp


# --------------------------------------------------------------------------------------------
# Parchment and ink: Blizzard's palette, inked outlines, every tree
# --------------------------------------------------------------------------------------------


def parchment(p: Prepared, st: dict) -> np.ndarray:
    paper = D.rgb(st["paper"])
    img = ground_colour(p, st["ground"], paper)
    img = D.mix(img, paper, 0.35)  # the ground's colours lie thin on the paper
    lit = np.clip((p.shade - 0.55) * 2.2, 0, 1)  # the slopes facing the light, a little brighter
    dim = np.clip((0.75 - p.shade) * 1.6, 0, 1)  # the others in a warm brown, not grey
    img = D.mix(img, D.rgb(st["shade"]), dim * st["relief"])
    img = D.mix(img, D.rgb(st["light"]), lit * st["relief"] * 0.5)
    # water by depth, an inked coast and ripple lines along it
    deep = np.clip(p.depth / 12, 0, 1)
    water = D.rgb(st["water"]) * (1 - deep[..., None]) + D.rgb(st["water_deep"]) * deep[..., None]
    img = np.where(p.water[..., None], water, img)
    img = D.mix(img, D.rgb(st["lava"]), p.lava)
    img = D.mix(img, D.rgb(st["slime"]), p.slime)
    ink = D.rgb(st["ink"])
    cw = st["coast_width"] / p.ypp
    land = ~p.water
    for i in range(1, int(st["ripples"]) + 1):
        band = (
            D.edge(land, cw * (1 + i * 2.2), outside=True)
            & ~D.edge(land, cw * (i * 2.2), outside=True)
            & p.water
        )
        img = D.mix(img, ink, band * (0.28 / i))
    img = D.mix(img, ink, D.edge(p.water, cw, outside=False) * 0.85)
    # roads with inked edges
    img = D.mix(img, D.rgb(st["road"]), p.road * 0.9)
    img = D.mix(img, D.rgb(st["road_edge"]), D.edge(p.road, 0.8 * p.s) * 0.7)
    # streets, bridges and docks; then roofs with a shadow to the south-east
    img = D.mix(img, D.rgb(st["road"]), p.structure * 0.8)
    img = D.mix(img, ink, D.edge(p.structure, 0.6 * p.s) * 0.5)
    k = max(1, round(2.5 / p.ypp))
    shadow = np.zeros_like(p.roof)
    shadow[k:, k:] = p.roof[:-k, :-k]
    img = D.mix(img, ink, (shadow & ~p.roof) * st["shadow"])
    tint = 1 + st["roof_vary"] * p.roof_tone[..., None]
    img = np.where(
        p.roof[..., None], D.rgb(st["roof"]) * tint * (0.55 + 0.45 * p.roof_shade[..., None]), img
    )
    img = D.mix(img, D.rgb(st["roof_edge"]), D.edge(p.roof, 0.7 * p.s, outside=False))
    img = D.mix(img, D.rgb(st["roof_edge"]), p.roof_lines * 0.9)
    roofs = img.copy()
    img = D.mix(img, ink, p.fence * 0.6)

    def paint(dr, kind, r, c, rad):
        if kind == "tree":
            q = _crown(p, rad, 2.5, 7.0)
            o = q * 0.35
            dr.ellipse((c - q + o, r - q + o, c + q + o, r + q + o), fill=_c255(st["ink"], 70))
            dr.ellipse(
                (c - q, r - q, c + q, r + q),
                fill=_c255(st["tree"]),
                outline=_c255(st["tree_dark"]),
                width=max(1, p.s),
            )
            dr.ellipse(
                (c - q * 0.55, r - q * 0.75, c + q * 0.1, r - q * 0.1), fill=_c255(st["bush"], 150)
            )
        elif kind == "bush":
            q = _crown(p, rad, 1.0, 2.5)
            dr.ellipse(
                (c - q, r - q, c + q, r + q),
                fill=_c255(st["bush"]),
                outline=_c255(st["tree_dark"], 160),
            )
        elif kind == "rock":
            q = _crown(p, rad, 1.0, 4.0)
            dr.ellipse(
                (c - q, r - q * 0.7, c + q, r + q * 0.7),
                fill=_c255("a89c88"),
                outline=_c255(st["ink"], 180),
            )

    img = _over(img, _things_layer(p, paint))
    img = np.where(p.roof[..., None], roofs, img)  # trees in courtyards stay under the roofs
    grain = p.noise(3 * p.s, 1, 2)
    return img * (1 + st["grain"] * grain[..., None])


# --------------------------------------------------------------------------------------------
# Modern: a road map as the phone shows it: clear colours, strong water, white roads with a casing
# --------------------------------------------------------------------------------------------


def _density(p: Prepared, kinds: tuple[str, ...], radius_yards: float) -> np.ndarray:
    """Things per square of `radius_yards`, smoothed."""
    count = np.zeros((p.h, p.w), "f4")
    for kind in kinds:
        t = p.things.get(kind, np.zeros((0, 3)))
        if len(t):
            rr = np.clip(t[:, 0].astype(int), 0, p.h - 1)
            cc = np.clip(t[:, 1].astype(int), 0, p.w - 1)
            np.add.at(count, (rr, cc), 1.0)
    r = radius_yards / p.ypp
    return D.blur(count, r) * (2 * r) ** 2


def modern(p: Prepared, st: dict) -> np.ndarray:
    img = ground_colour(p, st["ground"], D.rgb(st["land"]))
    wood = D.smooth_mask(_density(p, ("tree",), 20) > st["wood_from"], 8 / p.ypp)
    img = np.where(wood[..., None], D.rgb(st["forest"]), img)
    img = D.mix(img, D.rgb(st["forest_edge"]), D.edge(wood, 0.7 * p.s, outside=False) * 0.8)
    lit = np.clip((p.shade - 0.6) * 2.5, 0, 1)
    dim = np.clip((0.72 - p.shade) * 1.8, 0, 1)
    img = D.mix(img, D.rgb(st["shade"]), dim * st["relief"])
    img = D.mix(img, D.rgb("ffffff"), lit * st["relief"] * 0.6)
    img = np.where(p.water[..., None], D.rgb(st["water"]), img)
    img = D.mix(img, D.rgb(st["water_edge"]), D.edge(p.water, 0.9 * p.s, outside=False))
    img = D.mix(img, D.rgb(st["lava"]), p.lava)
    img = D.mix(img, D.rgb(st["slime"]), p.slime)

    def paint(dr, kind, r, c, rad):
        if kind == "tree":
            q = _crown(p, rad, 2.0, 5.0)
            dr.ellipse((c - q, r - q, c + q, r + q), fill=_c255(st["tree"], 210))
        elif kind == "bush":
            q = _crown(p, rad, 0.8, 1.8)
            dr.ellipse((c - q, r - q, c + q, r + q), fill=_c255(st["tree"], 120))

    img = _over(img, _things_layer(p, paint))
    paved = p.road | p.structure
    img = D.mix(img, D.rgb(st["road_edge"]), D.grow(paved, 1.0 * p.s))
    img = np.where(p.structure[..., None], D.rgb(st["square"]), img)
    img = np.where(p.road[..., None], D.rgb(st["road"]), img)
    k = max(1, round(1.5 / p.ypp))
    shadow = np.zeros_like(p.roof)
    shadow[k:, k:] = p.roof[:-k, :-k]
    img = D.mix(img, D.rgb(st["building_edge"]), (shadow & ~p.roof) * 0.6)
    tint = 1 + st["roof_vary"] * p.roof_tone[..., None]
    img = np.where(
        p.roof[..., None], D.rgb(st["building"]) * tint * (0.8 + 0.2 * p.roof_shade[..., None]), img
    )
    img = D.mix(img, D.rgb(st["building_edge"]), D.edge(p.roof, 0.7 * p.s, outside=False))
    img = D.mix(img, D.rgb(st["building_edge"]), p.roof_lines * 0.7)
    img = D.mix(img, D.rgb(st["building_edge"]), p.fence * 0.5)
    return img


# --------------------------------------------------------------------------------------------
# Bastian's coloured pencil: strong colour laid in strokes, the paper white through the tooth,
# outlines in a darker pencil of the same colour, shadows as denser strokes
# --------------------------------------------------------------------------------------------


def _layer(p: Prepared, angle: float, spacing: float, salt: int, wobble: float = 1.0) -> np.ndarray:
    return p.hatch(angle, spacing, salt, wobble)


def pencil(p: Prepared, st: dict) -> np.ndarray:
    paper = D.rgb(st["paper"])
    sp = st["stroke_spacing"] / p.ypp
    a = st["stroke_angle"]
    tooth = p.noise(2.5 * p.s, 5, 2) * 0.5 + 0.5  # high spots take the pencil
    press = 0.8 + 0.2 * p.noise(30 * p.s, 6, 2)  # the hand presses unevenly

    def lay(colour: np.ndarray, where: np.ndarray, strength: float, angle: float, salt: int):
        strokes = _layer(p, angle, sp, salt)
        cover = np.clip((0.62 + 0.38 * strokes) * press * strength, 0, 1)
        cover *= np.clip((tooth - st["tooth"]) * 4, 0, 1)  # the paper's white in the hollows
        w = where[..., None] if where.ndim == 2 else where
        return colour, cover[..., None] * w

    img = np.broadcast_to(paper, (p.h, p.w, 3)).copy()

    def put(colour, where, strength, angle, salt):
        nonlocal img
        col, cover = lay(colour, where, strength, angle, salt)
        img = (
            img * (1 - cover) + (img * col) ** 0.35 * col**0.65 * cover
        )  # layers glaze, mostly opaque

    # the ground, then shadows as a second layer of the same colour, cross-hatched
    ground = ground_colour(p, st["ground"], D.rgb(st["ground"]["grass"]))
    land = (~p.water).astype("f4")
    put(ground, land, 1.2, a, 7)
    away = np.clip((0.7 - p.shade) * 2.2, 0, 1)
    put(ground * 0.62, land * away * st["relief"], 1.0, a + 65, 8)
    lit = np.clip((p.shade - 0.62) * 3, 0, 1)
    img = D.mix(img, paper, lit[..., None] * land[..., None] * 0.35)
    # water: deep blue along the shore, lighter in the middle, white glints
    shore = D.blur(D.edge(p.water, 4 * p.s, outside=False).astype("f4"), 2 * p.s)
    put(D.rgb(st["water_light"]), p.water.astype("f4"), 1.0, a - 10, 9)
    put(D.rgb(st["water"]), p.water * np.clip(shore * 1.6 + p.depth / 20, 0, 1), 1.0, a + 20, 10)
    glint = np.clip((_layer(p, a - 10, sp * 6, 11) - 0.85) * 6, 0, 1) * p.water
    img = D.mix(img, paper, glint * 0.6)
    put(D.rgb(st["lava"]), p.lava.astype("f4"), 1.0, a, 12)
    put(D.rgb(st["slime"]), p.slime.astype("f4"), 1.0, a, 13)
    # roads and squares, roofs; each outlined in a darker pencil of its colour
    paved = p.road | p.structure
    put(D.rgb(st["road"]), paved.astype("f4"), 1.0, a + 90, 14)
    tint = 1 + st["roof_vary"] * p.roof_tone[..., None]
    put(np.clip(D.rgb(st["roof"]) * tint, 0, 1), p.roof.astype("f4"), 1.1, a, 15)
    put(D.rgb(st["roof"]) * 0.55, (p.roof & (p.roof_shade < 0.6)).astype("f4"), 1.0, a + 65, 19)
    k = max(1, round(2.0 / p.ypp))
    shadow = np.zeros_like(p.roof)
    shadow[k:, k:] = p.roof[:-k, :-k]
    put(ground * 0.5, (shadow & ~p.roof).astype("f4"), 1.0, a + 65, 16)
    wobble = np.clip(0.7 + 0.5 * p.noise(8 * p.s, 17, 2), 0, 1)
    for mask, colour, width in (
        (p.water, st["water_line"], 0.9),
        (paved, st["road_line"], 0.6),
        (p.roof, st["roof_line"], 0.8),
    ):
        line = (
            D.edge(mask, width * p.s, outside=False)
            if mask is not paved
            else D.edge(mask, width * p.s)
        )
        img = D.mix(img, D.rgb(colour), line * wobble * np.clip(tooth + 0.3, 0, 1))
    img = D.mix(img, D.rgb(st["roof_line"]), p.roof_lines * np.clip(wobble + 0.2, 0, 1))
    img = D.mix(img, D.rgb(st["road_line"]), p.fence * 0.6)

    def paint(dr, kind, r, c, rad):
        if kind == "tree":
            q = _crown(p, rad, 2.5, 7.0)
            o = q * 0.45
            dr.ellipse(
                (c - q + o, r - q * 0.6 + o, c + q + o, r + q * 0.6 + o),
                fill=_c255(st["tree_shadow"], 110),
            )
            dr.ellipse((c - q, r - q, c + q, r + q), fill=_c255(st["tree"], 235))
            j = [(D.point_hash(r + p.r0, c + p.c0, 18 + i) - 0.5) * q * 0.25 for i in (0, 1)]
            dr.ellipse(
                (c - q * 0.55 + j[0], r - q * 0.7 + j[1], c + q * 0.25, r + q * 0.05),
                fill=_c255(st["tree_light"], 200),
            )
            dr.arc(
                (c - q, r - q, c + q, r + q),
                -60,
                150,
                fill=_c255(st["tree_line"], 230),
                width=max(1, p.s),
            )
        elif kind == "bush":
            q = _crown(p, rad, 1.0, 2.5)
            dr.ellipse(
                (c - q, r - q, c + q, r + q),
                fill=_c255(st["tree_light"], 200),
                outline=_c255(st["tree"], 200),
            )
        elif kind == "rock":
            q = _crown(p, rad, 1.0, 3.5)
            dr.ellipse(
                (c - q, r - q * 0.7, c + q, r + q * 0.7),
                fill=_c255("b0a698", 220),
                outline=_c255(st["road_line"], 200),
            )

    roofs = img.copy()
    trees = _things_layer(p, paint)
    trees[..., 3] *= np.clip(tooth + 0.35, 0, 1)  # the crowns too show the paper's tooth
    return np.where(p.roof[..., None], roofs, _over(img, trees))


STYLES = {"modern": modern, "pencil": pencil, "parchment": parchment}


def style_config(cfg: dict, style: str) -> dict:
    """The style's table; one with `base` takes that style's values and changes some."""
    st = cfg["style"][style]
    base = st.get("base")
    if not base:
        return st
    out = {**cfg["style"][base], **st}
    out["ground"] = {**cfg["style"][base].get("ground", {}), **st.get("ground", {})}
    return out


def render(p: Prepared, style: str, cfg: dict) -> Image.Image:
    img = STYLES[style](p, style_config(cfg, style))
    return D.to_image(img, p.s)
