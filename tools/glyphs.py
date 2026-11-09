"""The suite's glyph set (styling round ST4, 23.10.2026): flat white shapes with a dark rim on a
transparent 64x64 ground, drawn from signed distance fields, so the set is reproducible and
GPL-clean.

The game tints a glyph with `SetVertexColor` (multiply), so the body is white and the rim dark grey:
the rim keeps a glyph readable on the map art and on light themes. A shape is a function
`(x, y) -> distance` in pixels, negative inside; the kit below builds shapes from primitives with
union, cut and intersection. `render(shape)` supersamples the edges 4x4 and returns BGRA bytes.

Used by `tools/make_media.py` (TGA files for the game) and `tools/glyph_sheet.py` (the preview).
"""

from __future__ import annotations

import itertools
import math
from collections.abc import Callable

Shape = Callable[[float, float], float]

SIZE = 64
SAMPLES = 4
RIM = 2.5  # pixels of dark rim around the white body
RIM_GREY = 0  # the rim's grey (0 = black); the body is 255


# ---------------------------------------------------------------------------------------------
# Primitives (distance in pixels, negative inside)
# ---------------------------------------------------------------------------------------------


def circle(cx: float, cy: float, r: float) -> Shape:
    return lambda x, y: math.hypot(x - cx, y - cy) - r


def ring(cx: float, cy: float, r: float, width: float) -> Shape:
    return lambda x, y: abs(math.hypot(x - cx, y - cy) - r) - width / 2


def box(x0: float, y0: float, x1: float, y1: float, radius: float = 0.0) -> Shape:
    """An axis-aligned box from (x0, y0) to (x1, y1), corners rounded by `radius`."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hw, hh = (x1 - x0) / 2 - radius, (y1 - y0) / 2 - radius

    def d(x: float, y: float) -> float:
        qx, qy = abs(x - cx) - hw, abs(y - cy) - hh
        outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
        return outside + min(max(qx, qy), 0.0) - radius

    return d


def capsule(ax: float, ay: float, bx: float, by: float, r: float) -> Shape:
    """A stroke from a to b with round ends, `r` its half width."""
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy or 1e-9

    def d(x: float, y: float) -> float:
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / length2))
        return math.hypot(x - ax - t * dx, y - ay - t * dy) - r

    return d


def polyline(points: list[tuple[float, float]], r: float) -> Shape:
    return union(*(capsule(*a, *b, r) for a, b in itertools.pairwise(points)))


def polygon(points: list[tuple[float, float]]) -> Shape:
    """A closed polygon (any simple shape), exact distance (Inigo Quilez's formula)."""
    pts = list(points)

    def d(x: float, y: float) -> float:
        best = (x - pts[0][0]) ** 2 + (y - pts[0][1]) ** 2
        sign = 1.0
        j = len(pts) - 1
        for i in range(len(pts)):
            vix, viy = pts[i]
            vjx, vjy = pts[j]
            ex, ey = vjx - vix, vjy - viy
            wx, wy = x - vix, y - viy
            t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey or 1e-9)))
            bx, by = wx - ex * t, wy - ey * t
            best = min(best, bx * bx + by * by)
            c1, c2, c3 = y >= viy, y < vjy, ex * wy > ey * wx
            if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
                sign = -sign
            j = i
        return sign * math.sqrt(best)

    return d


def regular(
    cx: float, cy: float, r: float, n: int, turn: float = -90.0
) -> list[tuple[float, float]]:
    """The corners of a regular n-gon, the first at `turn` degrees (-90 = top)."""
    return [
        (
            cx + r * math.cos(math.radians(turn + 360 * i / n)),
            cy + r * math.sin(math.radians(turn + 360 * i / n)),
        )
        for i in range(n)
    ]


def ellipse(cx: float, cy: float, a: float, b: float) -> Shape:
    """An axis-aligned ellipse; the distance to first order (the implicit value over its
    gradient), so the rim is even all round."""

    def d(x: float, y: float) -> float:
        u, v = (x - cx) / a, (y - cy) / b
        r = math.hypot(u, v)
        if r < 1e-9:
            return -min(a, b)
        grad = math.hypot(u / a, v / b) / r
        return (r - 1.0) / grad

    return d


def leaf(cx: float, cy: float, length: float, width: float, degrees: float) -> Shape:
    """A lens-shaped leaf centred at (cx, cy), `length` tip to tip, turned by `degrees`."""
    half_l, half_w = length / 2, width / 2
    radius = (half_l * half_l + half_w * half_w) / (2 * half_w)
    off = radius - half_w
    lens = intersect(circle(cx, cy - off, radius), circle(cx, cy + off, radius))
    return rotate(lens, cx, cy, degrees)


def star(cx: float, cy: float, outer: float, inner: float, points: int = 5) -> Shape:
    corners = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = math.radians(-90 + 180 * i / points)
        corners.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return polygon(corners)


def halfplane(nx: float, ny: float, offset: float) -> Shape:
    """Everything where nx*x + ny*y > offset is outside (n need not be unit length)."""
    n = math.hypot(nx, ny)
    return lambda x, y: (nx * x + ny * y - offset) / n


def rotate(shape: Shape, cx: float, cy: float, degrees: float) -> Shape:
    """The shape turned by `degrees` (clockwise on screen) around (cx, cy)."""
    a = math.radians(-degrees)
    ca, sa = math.cos(a), math.sin(a)

    def d(x: float, y: float) -> float:
        dx, dy = x - cx, y - cy
        return shape(cx + dx * ca - dy * sa, cy + dx * sa + dy * ca)

    return d


# ---------------------------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------------------------


def union(*shapes: Shape) -> Shape:
    return lambda x, y: min(s(x, y) for s in shapes)


def intersect(*shapes: Shape) -> Shape:
    return lambda x, y: max(s(x, y) for s in shapes)


def cut(shape: Shape, *holes: Shape, gap: float = 0.0) -> Shape:
    """The shape minus the holes; `gap` widens the holes (a groove that shows the ground)."""
    return lambda x, y: max(shape(x, y), *(gap - h(x, y) for h in holes))


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------


def coverage(shape: Shape, px: int, py: int) -> tuple[int, int]:
    """(body, rim) samples of the pixel out of SAMPLES*SAMPLES."""
    d = shape(px + 0.5, py + 0.5)
    n = SAMPLES * SAMPLES
    if d < -1.0:
        return n, 0  # deep inside
    if d > RIM + 1.0:
        return 0, 0  # far outside
    if 1.0 < d < RIM - 1.0:
        return 0, n  # inside the rim band
    body = rim = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            v = shape(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
            if v < 0:
                body += 1
            elif v < RIM:
                rim += 1
    return body, rim


def render(shape: Shape) -> list[tuple[int, int]]:
    """(grey, alpha) per pixel, rows top to bottom."""
    out = []
    n = SAMPLES * SAMPLES
    for py in range(SIZE):
        for px in range(SIZE):
            body, rim = coverage(shape, px, py)
            alpha = round(255 * (body + rim) / n)
            grey = round((255 * body + RIM_GREY * rim) / (body + rim)) if body + rim else 0
            out.append((grey, alpha))
    return out


def tga(pixels: list[tuple[int, int]]) -> bytes:
    """32-bit uncompressed TGA, top-left origin (both clients read TGA addon textures)."""
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),  # uncompressed true-colour, no colour map
            *SIZE.to_bytes(2, "little"),
            *SIZE.to_bytes(2, "little"),
            32,  # bits per pixel
            0x28,  # 8 alpha bits, top-left origin
        ]
    )
    body = bytearray()
    for grey, alpha in pixels:
        body += bytes((grey, grey, grey, alpha))  # BGRA, grey: B = G = R
    return header + bytes(body)


# ---------------------------------------------------------------------------------------------
# The glyphs: kind -> (shape, what it stands for). Coordinates on the 64 px canvas, y down; the
# body stays inside 5..59 so the rim fits.
# ---------------------------------------------------------------------------------------------


def _quest() -> Shape:  # an available quest: "!"
    return union(capsule(32, 11, 32, 38, 6.5), circle(32, 52, 6.5))


def _quest_active() -> Shape:  # a quest in the log: "?"
    hook = cut(ring(32, 22, 12, 9), intersect(halfplane(1, 0, 32), halfplane(0, -1, -22)))
    return union(hook, capsule(32, 33, 32, 40, 4.5), circle(32, 52, 6))


def _done() -> Shape:
    return polyline([(13, 33), (26, 46), (51, 18)], 5.5)


def _waiting() -> Shape:  # a clock
    return union(ring(32, 32, 22, 6), capsule(32, 32, 32, 17, 3.2), capsule(32, 32, 42, 38, 3.2))


def _never() -> Shape:
    return union(capsule(16, 16, 48, 48, 5.5), capsule(48, 16, 16, 48, 5.5))


def _sword_upright() -> Shape:
    blade = polygon([(32, 2), (36, 9), (36, 40), (28, 40), (28, 9)])
    return union(blade, box(19, 40, 45, 45, 2.5), box(29.5, 45, 34.5, 54, 1.5), circle(32, 57, 3.8))


def _mob() -> Shape:  # a fight: two crossed swords
    sword = _sword_upright()
    front, back = rotate(sword, 32, 30, 38), rotate(sword, 32, 30, -38)
    return union(cut(back, front, gap=2.5), front)  # a gap where the front blade crosses


# The class weapons for "mob": Icons.lua picks one by the player's class.
def _mob_claw() -> Shape:  # druids, evokers: claw marks
    return union(
        capsule(23, 10, 13, 50, 4.2),
        capsule(36, 10, 27, 53, 4.6),
        capsule(50, 12, 41, 50, 4.2),
    )


def _mob_dagger() -> Shape:  # rogues, demon hunters
    blade = polygon([(32, 6), (36, 15), (35, 36), (29, 36), (28, 15)])
    dagger = union(blade, box(23, 36, 41, 40, 2), box(30, 40, 34, 50, 1), circle(32, 53, 3.2))
    return rotate(dagger, 32, 30, 40)


def _mob_bow() -> Shape:  # hunters: a bow with its string and an arrow
    limb = intersect(ring(46, 32, 26, 5), halfplane(1, 0, 30))
    string = capsule(30, 12, 30, 52, 1.2)
    arrow = union(
        capsule(12, 32, 52, 32, 1.8),
        polygon([(51, 26), (59, 32), (51, 38)]),
        polygon([(10, 26), (17, 32), (10, 38), (6, 38), (12, 32), (6, 26)]),
    )
    return union(limb, string, arrow)


def _mob_staff() -> Shape:  # mages, warlocks, priests, monks: a staff with an orb
    shaft = capsule(17, 55, 40, 22, 3.2)
    orb = cut(circle(45, 15, 9), circle(45, 15, 3.5))
    claws = union(capsule(38, 24, 36, 13, 2.2), capsule(40, 26, 52, 24, 2.2))
    return union(shaft, orb, claws)


def _mob_axe() -> Shape:  # shamans: an axe, the cutting edge round
    handle = capsule(26, 11, 26, 57, 3.4)
    head = union(box(24, 15, 40, 31, 2), intersect(circle(37, 23, 14), halfplane(-1, 0, -37)))
    return rotate(union(handle, head), 32, 32, 20)


def _mob_mace() -> Shape:  # paladins
    handle = capsule(32, 30, 32, 58, 3.4)
    head = union(circle(32, 20, 11), box(29, 4, 35, 36, 2), box(16, 17, 48, 23, 2))
    return rotate(union(handle, head), 32, 32, 30)


def _rare() -> Shape:
    return star(32, 34, 27, 11.5)


def _herb() -> Shape:  # a sprig: a stem with five leaves
    stem = polyline([(30, 57), (31, 44), (32, 30), (33, 14)], 2.4)
    leaves = union(
        leaf(34, 12, 18, 10, 0),
        leaf(21, 25, 22, 11, -35),
        leaf(44, 31, 22, 11, 35),
        leaf(19, 42, 20, 10, -55),
        leaf(43, 47, 20, 10, 55),
    )
    return union(stem, leaves)


def _mine() -> Shape:  # a pickaxe, the head top right
    head = intersect(ring(32, 46, 24, 7), halfplane(0, 1, 30))
    upright = union(head, capsule(32, 22, 32, 58, 4))
    return rotate(upright, 32, 38, 45)


def _treasure() -> Shape:  # a chest
    lid = box(10, 14, 54, 30, 7)
    body = box(10, 31, 54, 54, 3)
    chest = cut(union(lid, body), box(10, 28.5, 54, 31.5), gap=0.0)
    return cut(chest, box(28, 25, 36, 37, 1.5), gap=0.0)


def _fish() -> Shape:
    body = intersect(circle(30, 52, 27), circle(30, 12, 27))
    tail = polygon([(46, 32), (58, 19), (58, 45)])
    return cut(union(body, tail), circle(17, 29, 3.2))


def _zone() -> Shape:  # a folded map
    sheet = polygon([(7, 15), (24, 9), (40, 15), (57, 9), (57, 49), (40, 55), (24, 49), (7, 55)])
    return cut(sheet, capsule(24, 9, 24, 49, 1.2), capsule(40, 15, 40, 55, 1.2))


def _trainer() -> Shape:  # an open book with writing
    left = polygon([(6, 14), (30, 19), (30, 54), (6, 48)])
    right = polygon([(34, 19), (58, 14), (58, 48), (34, 54)])
    lines = []
    for k in range(4):
        dy = 9 + k * 8
        lines.append(capsule(10, 14 + dy, 26, 17 + dy, 1.1))
        lines.append(capsule(38, 17 + dy, 54, 14 + dy, 1.1))
    return cut(union(left, right), *lines)


def _vendor() -> Shape:  # a sack tied with a string
    sack = union(
        circle(32, 41, 18), box(25, 17, 39, 29, 2), polygon([(20, 8), (44, 8), (37, 18), (27, 18)])
    )
    tied = cut(sack, box(22, 20, 42, 23))
    string = union(
        capsule(23, 21.5, 41, 21.5, 1.3),  # round the neck
        ring(45, 18, 4, 2.2),  # the bow's loop
        capsule(42, 23, 47, 33, 1.4),  # the loose end
    )
    return union(tied, string)


def _service() -> Shape:  # a speech bubble
    return union(box(7, 10, 57, 44, 9), polygon([(16, 40), (30, 40), (13, 56)]))


def _innkeeper() -> Shape:  # a mug with foam
    mug = box(12, 20, 42, 56, 4)
    handle = intersect(ring(43, 38, 9, 5), halfplane(-1, 0, -42))
    foam = union(circle(18, 18, 6), circle(27, 15, 7), circle(37, 18, 6))
    return union(mug, handle, foam)


def _flight() -> Shape:  # a winged boot, as Blizzard draws the flight master (owner's ballot)
    boot = polygon([(26, 14), (40, 14), (40, 38), (55, 44), (58, 52), (56, 57), (24, 57), (25, 40)])
    boot = cut(boot, capsule(25, 47, 57, 47, 1.0), capsule(27, 20, 39, 20, 1.0))
    wing = union(
        capsule(25, 22, 10, 9, 3.2),
        capsule(25, 27, 8, 18, 3.0),
        capsule(25, 32, 9, 27, 2.8),
        capsule(25, 36, 12, 35, 2.6),
    )
    return union(cut(wing, boot, gap=2.5), boot)


def _banker() -> Shape:  # a bank: roof, columns, base
    roof = polygon([(6, 24), (32, 8), (58, 24)])
    base = box(6, 50, 58, 57, 1.5)
    cols = [box(x, 28, x + 7, 47, 1) for x in (10, 21, 36, 47)]
    return union(roof, base, *cols)


def _auctioneer() -> Shape:  # a gavel and its block
    head = rotate(box(12, 15, 40, 31, 3), 26, 23, -45)
    handle = capsule(30, 27, 52, 49, 3.6)
    block = box(8, 50, 34, 57, 2)
    return union(head, handle, block)


def _repair() -> Shape:  # an anvil
    return polygon(
        [
            (6, 18),
            (46, 18),
            (59, 13),
            (55, 24),
            (44, 28),
            (39, 33),
            (39, 41),
            (48, 49),
            (48, 55),
            (16, 55),
            (16, 49),
            (25, 41),
            (25, 33),
            (19, 28),
            (8, 27),
        ]
    )


def _item() -> Shape:  # a cube
    hexagon = polygon(regular(32, 32, 26, 6, -90))
    return cut(
        hexagon,
        capsule(32, 32, 32, 58, 1.4),
        capsule(32, 32, 9.5, 19, 1.4),
        capsule(32, 32, 54.5, 19, 1.4),
    )


def _gold() -> Shape:  # a small stack of gold: coins and one standing
    stack = union(*(box(8, y, 36, y + 6, 3) for y in (51, 44, 37, 30)), ellipse(22, 28, 14, 5))
    stack = cut(stack, *(capsule(9, y, 35, y, 0.6) for y in (44, 37, 30)))
    coin = cut(circle(43, 39, 15), ring(43, 39, 10, 2.4))
    return union(cut(stack, circle(43, 39, 15), gap=2.5), coin)


def _route() -> Shape:  # a start dot, a dotted path, the goal's pin
    pin = cut(
        union(circle(46, 17, 9.5), polygon([(37.5, 20), (54.5, 20), (46, 34)])), circle(46, 17, 3.5)
    )
    dots = [circle(x, y, 3.4) for x, y in ((22, 43), (29, 37), (36, 32))]
    return union(circle(13, 50, 6), *dots, pin)


def _spot() -> Shape:  # a map pin
    return cut(
        union(circle(32, 24, 17), polygon([(16.5, 30), (47.5, 30), (32, 58)])), circle(32, 24, 6.5)
    )


def _other() -> Shape:
    return circle(32, 32, 13)


def _hide() -> Shape:  # an eye, struck through
    eye = cut(intersect(circle(32, 50, 32), circle(32, 14, 32)), circle(32, 32, 9.5))
    slash = capsule(10, 54, 54, 10, 2.8)
    return union(cut(eye, slash, gap=2.5), slash)


def _voice() -> Shape:  # a speaker with two waves
    speaker = polygon([(8, 25), (18, 25), (31, 13), (31, 51), (18, 39), (8, 39)])
    waves = intersect(union(ring(31, 32, 12, 4.5), ring(31, 32, 22, 4.5)), halfplane(-1, 0, -38))
    return union(speaker, waves)


def _open() -> Shape:  # a magnifier: look it up
    return union(ring(27, 27, 15, 6.5), capsule(38, 38, 54, 54, 5))


def _copy() -> Shape:  # two sheets
    back = box(8, 8, 40, 44, 4)
    front = box(22, 20, 56, 56, 4)
    return union(cut(back, box(22, 20, 56, 56, 4), gap=3.0), front)


def _waypoint() -> Shape:  # a flag on a pole
    return union(capsule(15, 8, 15, 56, 3.2), polygon([(18, 9), (54, 17), (18, 33)]))


def _settings() -> Shape:  # a gear
    teeth = union(*(rotate(box(27, 4, 37, 60, 2), 32, 32, a) for a in (0, 45, 90, 135)))
    gear = union(circle(32, 32, 20), intersect(teeth, circle(32, 32, 27)))
    return cut(gear, circle(32, 32, 8))


# ---- the Strategies book's plates and its button (SB, 23.10.2026) --------------------------


def _cloth() -> Shape:  # a stack of folded cloth, three layers, each with its fold
    layers = [box(6, 40, 58, 56, 6), box(10, 25, 54, 41, 6), box(14, 10, 50, 26, 6)]
    body = cut(union(*layers), capsule(9, 40.5, 55, 40.5, 1.0), capsule(13, 25.5, 51, 25.5, 1.0))
    folds = [capsule(x, y0, x, y1, 0.9) for x, y0, y1 in ((22, 44, 53), (26, 29, 38), (30, 13, 23))]
    return cut(body, *folds)


def _bandage() -> Shape:  # a sticking plaster: a diagonal band, its pad, the air holes
    band = capsule(17, 47, 47, 17, 10)
    body = cut(band, rotate(box(24, 25, 40, 39, 2.5), 32, 32, 45), gap=2.0)
    body = union(body, rotate(box(26, 27, 38, 37, 2), 32, 32, 45))
    holes = [circle(x, y, 1.5) for x, y in ((18, 41), (23, 46), (41, 18), (46, 23))]
    return cut(body, *holes)


def _keep() -> Shape:  # a tower with battlements, a door and two windows
    body = union(box(14, 18, 50, 58, 2), *(box(x, 8, x + 8, 20, 1) for x in (14, 28, 42)))
    door = union(box(26, 42, 38, 58, 0.5), circle(32, 42, 6))
    return cut(body, door, box(20, 26, 25, 33, 1), box(39, 26, 44, 33, 1))


def _arrow() -> Shape:  # a fat arrow to the right: the flow plates' steps
    return union(box(6, 25, 40, 39, 3), polygon([(36, 12), (58, 32), (36, 52)]))


def _leather() -> Shape:  # a stretched hide
    pts = [(10, 14), (22, 8), (32, 13), (42, 8), (54, 14), (50, 30), (56, 48), (42, 56), (32, 51)]
    pts += [(22, 56), (8, 48), (14, 30)]
    return cut(polygon(pts), circle(32, 31, 3))


def _chain() -> Shape:  # a quest chain: two links, one through the other
    a = cut(capsule(17, 40, 31, 26, 9), capsule(17, 40, 31, 26, 4.5))
    b = cut(capsule(33, 38, 47, 24, 9), capsule(33, 38, 47, 24, 4.5))
    return union(cut(a, b, gap=2.4), b)


def _object() -> Shape:  # a game object: a crate with a brace
    frame = cut(box(9, 9, 55, 55, 4), box(15, 15, 49, 49, 1))
    brace = intersect(capsule(15, 49, 49, 15, 4), box(14, 14, 50, 50))
    return union(frame, brace)


def _grave() -> Shape:  # a gravestone with a cross on a mound: the place of death (R26.8)
    stone = union(box(17, 24, 47, 52, 2), circle(32, 24, 15))
    cross = union(box(29.5, 15, 34.5, 42, 1), box(23, 22, 41, 27, 1))
    return union(cut(stone, cross), box(9, 52, 55, 58, 3))


def _note() -> Shape:  # a sheet with a folded corner and three lines: Bastian's Notes
    sheet = polygon([(14, 6), (40, 6), (52, 18), (52, 58), (14, 58)])
    fold = polygon([(40, 6), (40, 18), (52, 18)])
    lines = [capsule(21, y, 45, y, 1.6) for y in (28, 38, 48)]
    return union(cut(sheet, fold, *lines), fold)


def _buttons() -> Shape:  # four round buttons in a frame: the minimap buttons' box (28.10.2026)
    frame = cut(box(6, 6, 58, 58, 9), box(11, 11, 53, 53, 6))
    dots = [circle(x, y, 8.5) for x, y in ((23, 23), (41, 23), (23, 41), (41, 41))]
    return union(frame, *dots)


def _ledger() -> Shape:  # a closed book with a coin on its cover: Bastian's Gold Adventures
    cover = box(12, 6, 54, 58, 5)
    spine = box(12, 6, 20, 58, 3)
    book = cut(cover, capsule(20.5, 9, 20.5, 55, 1.0))
    coin = cut(circle(38, 32, 10), ring(38, 32, 6, 2.0))
    return union(cut(book, circle(38, 32, 10), gap=2.2), coin, spine)


def _tale() -> Shape:  # a closed book, its ribbon hanging out below: Bastian's Library (28.10.2026)
    cover = box(12, 7, 52, 50, 5)
    book = cut(cover, capsule(20.5, 10, 20.5, 47, 1.0), box(26, 16, 46, 26, 2), gap=0)
    title = cut(box(26, 16, 46, 26, 2), box(29, 19, 43, 23, 1))
    ribbon = polygon([(36, 46), (44, 46), (44, 57), (40, 53), (36, 57)])
    return union(cut(book, box(34, 44, 46, 52), gap=0), title, ribbon)


def _play() -> Shape:  # the Orbiter's hub (voice.md, 01.11.2026): a triangle to the right
    return polygon([(18, 10), (54, 32), (18, 54)])


def _pause() -> Shape:  # two bars
    return union(box(15, 11, 27, 53, 2.5), box(37, 11, 49, 53, 2.5))


def _stop() -> Shape:  # a square
    return box(14, 14, 50, 50, 4)


def _replay() -> Shape:  # a bar and a triangle to the left: back to the start
    return union(box(11, 11, 19, 53, 2), polygon([(53, 10), (22, 32), (53, 54)]))


def _orbit() -> Shape:  # two orbits around a hub, a moon on the outer one: Bastian's Orbiter
    return union(
        circle(32, 32, 7), ring(32, 32, 15, 3.0), ring(32, 32, 25, 3.0), circle(48, 15, 5.5)
    )


# ---- the action pictograms of the widget set (ADR 0046 E4, 01.11.2026: "created by us") -----


def _bookmark() -> Shape:  # a ribbon
    return polygon([(18, 6), (46, 6), (46, 58), (32, 46), (18, 58)])


def _lock() -> Shape:  # a padlock
    body = box(14, 28, 50, 58, 5)
    shackle = intersect(ring(32, 27, 11, 5.5), halfplane(0, 1, 28))
    hole = union(circle(32, 41, 3.6), box(30.4, 41, 33.6, 50, 1))
    return union(cut(body, hole), shackle)


def _close() -> Shape:  # a cross
    return union(capsule(15, 15, 49, 49, 4.5), capsule(49, 15, 15, 49, 4.5))


def _filter() -> Shape:  # a funnel
    return polygon([(8, 10), (56, 10), (37, 32), (37, 54), (27, 48), (27, 32)])


def _clear() -> Shape:  # a cross in a disc: empty the box
    return cut(circle(32, 32, 24), capsule(22, 22, 42, 42, 3.4), capsule(42, 22, 22, 42, 3.4))


def _invite() -> Shape:  # a person and a plus
    person = union(circle(24, 20, 9), intersect(circle(24, 60, 17), halfplane(0, 1, 56)))
    plus = union(capsule(48, 14, 48, 30, 2.8), capsule(40, 22, 56, 22, 2.8))
    return union(person, plus)


def _more() -> Shape:  # three dots
    return union(circle(14, 32, 6), circle(32, 32, 6), circle(50, 32, 6))


def _plus() -> Shape:
    return union(capsule(32, 10, 32, 54, 4.5), capsule(10, 32, 54, 32, 4.5))


def _junk() -> Shape:  # a bin with its lid
    lid = union(box(12, 12, 52, 18, 2), box(26, 6, 38, 13, 2))
    body = polygon([(16, 21), (48, 21), (45, 58), (19, 58)])
    slots = [capsule(x, 28, x, 51, 1.4) for x in (26, 38)]
    return union(lid, cut(body, *slots))


def _back() -> Shape:  # a chevron to the left
    return polyline([(40, 10), (18, 32), (40, 54)], 4.5)


def _track() -> Shape:  # an eye with its pupil
    eye = intersect(circle(32, 50, 32), circle(32, 14, 32))
    return union(cut(eye, circle(32, 32, 9.5)), circle(32, 32, 5))


def _share() -> Shape:  # three nodes joined
    nodes = union(circle(48, 14, 7), circle(16, 32, 7), circle(48, 50, 7))
    lines = union(capsule(16, 32, 48, 14, 2.6), capsule(16, 32, 48, 50, 2.6))
    return union(nodes, lines)


def _dock() -> Shape:  # two panes side by side
    return union(box(6, 12, 29, 52, 3), box(35, 12, 58, 52, 3))


def _undock() -> Shape:  # a pane and an arrow out of it
    arrow = union(capsule(38, 26, 56, 8, 3.2), polyline([(44, 8), (56, 8), (56, 20)], 3.2))
    return union(box(6, 22, 36, 58, 3), arrow)


def _quiet() -> Shape:  # a bell, struck through
    bell = union(intersect(circle(32, 30, 17), halfplane(0, 1, 30)), box(15, 30, 49, 45, 2))
    bell = union(bell, circle(32, 51, 5))
    slash = capsule(10, 54, 54, 10, 2.8)
    return union(cut(bell, slash, gap=2.5), slash)


def _layers() -> Shape:  # three layers stacked
    top = polygon([(32, 10), (56, 23), (32, 36), (8, 23)])
    mids = [polyline([(8, y), (32, y + 12), (56, y)], 3.2) for y in (33, 43)]
    return union(top, *mids)


def _scan() -> Shape:  # four corner brackets and a line: a scan
    corners = [
        polyline([(8, 22), (8, 8), (22, 8)], 3.2),
        polyline([(42, 8), (56, 8), (56, 22)], 3.2),
        polyline([(56, 42), (56, 56), (42, 56)], 3.2),
        polyline([(22, 56), (8, 56), (8, 42)], 3.2),
    ]
    return union(capsule(16, 32, 48, 32, 2.4), *corners)


def _rename() -> Shape:  # a pencil
    pencil = union(box(26, 6, 38, 44, 2), polygon([(26, 44), (38, 44), (32, 57)]))
    return rotate(cut(pencil, capsule(26, 14, 38, 14, 1.0)), 32, 32, 45)


def _remove() -> Shape:  # a minus in a disc
    return cut(circle(32, 32, 24), capsule(18, 32, 46, 32, 3.6))


def _help() -> Shape:  # a question mark
    hook = cut(ring(32, 23, 11, 6), box(10, 23, 32, 44))
    return union(hook, capsule(32, 30, 32, 43, 3), circle(32, 53, 4))


# ---- the app marks:
# one pictogram per app, on its coloured tile the app's minimap button, feed, compartment entry,
# hub page and TOC icon. Strategies keeps `ledger`, the Orbiter `orbit`, the Library `tale`.


def _half_disc(cx: float, cy: float, r: float, lower: bool) -> Shape:
    """The lower (or upper) half of a disc, cut along y = cy."""
    return intersect(circle(cx, cy, r), halfplane(0, -1 if lower else 1, -cy if lower else cy))


def _quad(p0, c, p1, n: int = 7) -> list[tuple[float, float]]:
    """Points along a quadratic Bezier curve."""
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(
            (
                (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
                (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1],
            )
        )
    return pts


def _app_suite() -> Shape:  # the suite: a compass star in a ring, the needle's eye a hole
    star_ = polygon([(32, 9), (37, 27), (55, 32), (37, 37), (32, 55), (27, 37), (9, 32), (27, 27)])
    return cut(union(ring(32, 32, 24.5, 4), star_), circle(32, 32, 4))


def _app_quests() -> Shape:  # Quests: a scroll with the quest's mark
    scroll = union(box(19, 12, 45, 52, 3), box(13, 8, 51, 17, 4.5), box(13, 47, 51, 56, 4.5))
    return cut(scroll, box(29.5, 21, 34.5, 36, 2.5), circle(32, 41.5, 3))


def _app_map() -> Shape:  # Map: a pin standing on the land
    land = polyline(_quad((9, 51), (20, 43), (32, 51)) + _quad((32, 51), (44, 59), (55, 51))[1:], 2)
    pin = cut(union(circle(32, 21, 13), polygon([(20, 26), (44, 26), (32, 45)])), circle(32, 21, 5))
    return union(cut(land, pin, gap=2.5), pin)


def _app_browser() -> Shape:  # Browser: a page under a lens
    page = cut(box(12, 8, 44, 50, 3), box(18, 16, 38, 19), box(18, 23, 38, 26), box(18, 30, 30, 33))
    lens = union(ring(42, 42, 8, 4), capsule(48, 48, 55.5, 55.5, 2.75))
    return union(cut(page, circle(42, 42, 10), gap=2.5), lens)


def _app_gold() -> Shape:  # Gold: a balance
    frame = union(box(30, 10, 34, 52, 1), box(20, 50, 44, 56, 2), box(10, 15, 54, 19, 1))
    strings = union(capsule(14, 19, 14, 36, 1), capsule(50, 19, 50, 36, 1))
    pans = union(_half_disc(14, 36, 9, True), _half_disc(50, 36, 9, True))
    return union(frame, strings, pans)


def _app_route() -> Shape:  # Route: a signpost with two arms
    post = box(30, 6, 35, 58, 1)
    left = polygon([(6, 21), (15, 12), (46, 12), (46, 30), (15, 30)])
    right = polygon([(58, 42), (49, 33), (18, 33), (18, 51), (49, 51)])
    return cut(union(post, left, right), box(19, 19.5, 39, 22.5), box(25, 40.5, 45, 43.5))


def _app_notes() -> Shape:  # Notes: a sheet and a quill
    sheet = cut(
        polygon([(14, 10), (36, 10), (44, 18), (44, 54), (14, 54)]),
        box(20, 24, 34, 27),
        box(20, 32, 30, 35),
    )
    quill = polygon([(24, 56), (50, 12), (57, 17), (31, 58), (23, 58.5)])
    return union(cut(sheet, quill, gap=2.5), quill)


def _app_alts() -> Shape:  # Alts: two characters, one behind the other
    back = union(circle(43, 18, 8), _half_disc(43, 48, 14, False))
    front = union(circle(24, 23, 10), _half_disc(24, 56, 18, False))
    return union(cut(back, front, gap=2.5), front)


def _app_helpers() -> Shape:  # Helpers: a wrench
    wrench = union(capsule(14, 50, 36, 28, 5), circle(42, 22, 14))
    return cut(wrench, polygon([(45, 6), (60, 6), (52, 22), (44, 16)]))


def _app_chat() -> Shape:  # Chat: two speech bubbles in conversation
    back = union(box(22, 5, 56, 33, 8), polygon([(46, 31), (52, 42), (38, 31)]))
    front = union(box(8, 22, 42, 50, 8), polygon([(24, 50), (12, 58), (17, 50)]))
    dots = [circle(x, 32, 2.6) for x in (18, 25, 32)]
    return union(cut(back, front, gap=2.5), cut(front, *dots))


def _app_gestures() -> Shape:  # Gestures: a waving hand
    fingers = union(
        box(20, 11, 27.5, 38, 3.75),
        box(29.5, 6, 37, 37, 3.75),
        box(39, 9, 46.5, 38, 3.75),
        box(48, 16, 55.5, 39, 3.75),
    )
    thumb = capsule(12, 27, 25, 42, 4.5)
    return union(fingers, thumb, box(20, 30, 55.5, 58, 10))


def _app_courtesy() -> Shape:  # Courtesy: a speech bubble with a heart, the centre of its ring
    bubble = union(box(7, 9, 57, 47, 13), polygon([(16, 42), (15, 59), (33, 45)]))
    heart = union(
        circle(25.5, 22.5, 7),
        circle(38.5, 22.5, 7),
        polygon([(19.3, 26), (32, 40), (44.7, 26), (32, 18)]),
    )
    return cut(bubble, heart)


def _app_data() -> Shape:  # Data: a database cylinder
    body = union(box(12, 16, 52, 48), ellipse(32, 48, 20, 7), ellipse(32, 16, 20, 7))
    grooves = []
    for cy in (30, 41):
        e = ellipse(32, cy, 20, 7)
        grooves.append(intersect(lambda x, y, e=e: abs(e(x, y)) - 1.5, halfplane(0, -1, -cy)))
    return cut(body, *grooves)


def _campfire() -> Shape:  # Campfire: a flame with its inner tongue over two crossed logs
    flame = union(circle(32, 34, 12.5), polygon([(19.6, 34), (31.5, 7), (44.4, 34)]))
    tongue = union(circle(32, 37, 5.2), polygon([(26.9, 37), (33, 22), (37.1, 37)]))
    logs = union(
        rotate(box(10, 44, 54, 52, 1.6), 32, 48, -11), rotate(box(10, 44, 54, 52, 1.6), 32, 48, 11)
    )
    return union(cut(flame, tongue, gap=0.0), cut(logs, flame, gap=2.5))


def _flame_points(chains: list[list[tuple[float, float]]]) -> list[tuple[float, float]]:
    """A closed outline from smooth chains: each chain is a Catmull-Rom curve between two sharp
    points (a flame's tips and notches stay sharp, its flanks stay round)."""
    out: list[tuple[float, float]] = []
    for chain in chains:
        pts = [chain[0], *chain, chain[-1]]
        for i in range(1, len(pts) - 2):
            p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
            for step in range(8):
                t = step / 8
                out.append(
                    (
                        0.5
                        * (
                            2 * p1[0]
                            + (p2[0] - p0[0]) * t
                            + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t * t
                            + (3 * p1[0] - p0[0] - 3 * p2[0] + p3[0]) * t * t * t
                        ),
                        0.5
                        * (
                            2 * p1[1]
                            + (p2[1] - p0[1]) * t
                            + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t * t
                            + (3 * p1[1] - p0[1] - 3 * p2[1] + p3[1]) * t * t * t
                        ),
                    )
                )
    return out


def _flame() -> Shape:  # Campfire's flame: a leaning tip, a small lick on the left, a round belly
    return polygon(
        _flame_points(
            [
                [(37, 7), (44, 17), (52, 29), (54, 41), (47, 52), (32, 58)],
                [(32, 58), (19, 55), (11, 46), (10, 35), (17, 20)],
                [(17, 20), (20, 27), (25, 31)],
                [(25, 31), (31, 22), (37, 7)],
            ]
        )
    )


def _flame_heart() -> Shape:  # the flame's inner tongue, drawn over `flame` in its own colour
    return polygon(
        _flame_points(
            [
                [(35, 27), (41, 36), (44, 45), (39, 52), (31, 54)],
                [(31, 54), (23, 52), (20, 45), (24, 37), (28, 37)],
                [(28, 37), (32, 34), (35, 27)],
            ]
        )
    )


def _flame_ring() -> Shape:  # the thin ring around the flame that runs down with the warmth
    return cut(circle(32, 32, 27), circle(32, 32, 24), gap=0.0)


GLYPHS: dict[str, tuple[Callable[[], Shape], str]] = {
    "quest": (_quest, "available quest"),
    "questActive": (_quest_active, "quest in the log; Track"),
    "done": (_done, "done"),
    "waiting": (_waiting, "waiting, in progress"),
    "never": (_never, "not for this character"),
    "mob": (_mob, "hostile creature: a fight (crossed swords)"),
    "mob_claw": (_mob_claw, "hostile creature for druids and evokers"),
    "mob_dagger": (_mob_dagger, "hostile creature for rogues and demon hunters"),
    "mob_bow": (_mob_bow, "hostile creature for hunters"),
    "mob_staff": (_mob_staff, "hostile creature for mages, warlocks, priests, monks"),
    "mob_axe": (_mob_axe, "hostile creature for shamans"),
    "mob_mace": (_mob_mace, "hostile creature for paladins"),
    "rare": (_rare, "rare creature"),
    "herb": (_herb, "herb node"),
    "mine": (_mine, "mining node"),
    "treasure": (_treasure, "chest, treasure"),
    "fish": (_fish, "fishing pool"),
    "zone": (_zone, "zone; Show on map"),
    "trainer": (_trainer, "trainer; the Strategies book"),
    "vendor": (_vendor, "vendor"),
    "service": (_service, "other service, gossip"),
    "innkeeper": (_innkeeper, "innkeeper"),
    "flight": (_flight, "flight master"),
    "banker": (_banker, "banker"),
    "auctioneer": (_auctioneer, "auctioneer"),
    "repair": (_repair, "repair, smith"),
    "item": (_item, "item without its own icon"),
    "gold": (_gold, "price, gold"),
    "route": (_route, "Route here (instead of the horse)"),
    "spot": (_spot, "farm spot, waypoint pin"),
    "other": (_other, "anything else"),
    "hide": (_hide, "hide from Do here"),
    "voice": (_voice, "play the voice line (new)"),
    "open": (_open, "open in the Browser, search (new)"),
    "copy": (_copy, "copy /way (new)"),
    "waypoint": (_waypoint, "TomTom waypoint (new)"),
    "settings": (_settings, "settings, the suite's button (new)"),
    "cloth": (_cloth, "cloth (the book's plates)"),
    "bandage": (_bandage, "a bandage (the book's plates)"),
    "keep": (_keep, "a keep, a landmark (the book's plates)"),
    "arrow": (_arrow, "the next step (the book's flow plates)"),
    "leather": (_leather, "leather, a hide (the book's plates)"),
    "ledger": (_ledger, "Bastian's Strategies, the book"),
    "tale": (_tale, "Bastian's Library, a tale's journal (new, 28.10.2026)"),
    "chain": (_chain, "a quest chain (new, 25.10.2026)"),
    "object": (_object, "a game object (new, 25.10.2026)"),
    "grave": (_grave, "the place of death, the corpse (new, 26.10.2026)"),
    "note": (_note, "a note, Bastian's Notes (new, 26.10.2026)"),
    "buttons": (_buttons, "the box of the minimap buttons (new, 28.10.2026)"),
    "play": (_play, "play (the Orbiter's hub, 01.11.2026)"),
    "pause": (_pause, "pause (the Orbiter's hub)"),
    "stop": (_stop, "stop (the Orbiter's hub)"),
    "replay": (_replay, "back to the start (the Orbiter's hub)"),
    "orbit": (_orbit, "Bastian's Orbiter (its icon and minimap button)"),
    # the action pictograms of the widget set (ADR 0046, 01.11.2026)
    "bookmark": (_bookmark, "bookmark a page"),
    "lock": (_lock, "lock a window in place"),
    "close": (_close, "close"),
    "filter": (_filter, "filter the rows"),
    "clear": (_clear, "clear a box"),
    "invite": (_invite, "invite to the group"),
    "more": (_more, "more (a menu)"),
    "plus": (_plus, "new: a tab, a conversation, a list"),
    "junk": (_junk, "the junk, remove"),
    "back": (_back, "back"),
    "track": (_track, "track a quest"),
    "share": (_share, "share with the group"),
    "dock": (_dock, "dock two windows"),
    "undock": (_undock, "undock, own window"),
    "quiet": (_quiet, "quiet a tab"),
    "layers": (_layers, "the map's layers"),
    "scan": (_scan, "scan the auction house"),
    "rename": (_rename, "rename"),
    "remove": (_remove, "remove from a list"),
    "help": (_help, "help, the syntax"),
    # the app marks (plan-second-wave.md S1, 01.11.2026)
    "app_suite": (
        _app_suite,
        "the suite: its minimap button, launcher, compartment entry, Core's icon",
    ),
    "app_quests": (_app_quests, "Bastian's Quests"),
    "app_map": (_app_map, "Bastian's Map"),
    "app_browser": (_app_browser, "Bastian's Browser"),
    "app_gold": (_app_gold, "Bastian's Gold"),
    "app_route": (_app_route, "Bastian's Route"),
    "app_notes": (_app_notes, "Bastian's Notes"),
    "app_alts": (_app_alts, "Bastian's Alts"),
    "app_helpers": (_app_helpers, "Bastian's Helpers"),
    "app_chat": (_app_chat, "Bastian's Chat"),
    "app_gestures": (_app_gestures, "Bastian's Gestures"),
    "app_courtesy": (_app_courtesy, "Bastian's Courtesy, the centre of its ring"),
    "app_data": (_app_data, "Bastian's Data and its packs"),
    # the campfire (plan-second-wave.md S5, 02.11.2026): a fire's pin and wedge, the app's mark
    "campfire": (_campfire, "a campfire: a shared fire, the camp ring"),
    "app_campfire": (_campfire, "Bastian's Campfire"),
    # the flame on screen
    "flame": (_flame, "the flame on screen, its outer layer"),
    "flame_heart": (_flame_heart, "the flame's inner tongue"),
    "flame_ring": (_flame_ring, "the ring that runs down with the warmth"),
}

# ---------------------------------------------------------------------------------------------
# The tiles: every symbol in the style of the addon icons, a
# rounded tile in its category's colour (a dark fill, a bright edge) with the white symbol. The
# colours are baked: an inline icon in text has one texture, so the theme cannot tint a tile.
# ---------------------------------------------------------------------------------------------

TILE_SCALE = 0.66  # the symbol's size on the tile
TILE_EDGE = 3.0  # pixels of the bright edge

# category colours (0..1), close to the addon icons: quests gold, map green, route blue, ...
_GOLD, _AMBER = (0.93, 0.72, 0.18), (0.96, 0.55, 0.20)
_GREEN, _RED, _GREY = (0.36, 0.78, 0.42), (0.86, 0.32, 0.30), (0.55, 0.58, 0.60)
_BLUE, _TEAL, _PURPLE = (0.40, 0.74, 0.95), (0.30, 0.78, 0.72), (0.66, 0.50, 0.92)
_BROWN, _PINK = (0.82, 0.56, 0.30), (0.88, 0.45, 0.58)
TILE_COLOR: dict[str, tuple[float, float, float]] = {
    "quest": _GOLD,
    "questActive": _GOLD,
    "chain": _AMBER,
    "done": _GREEN,
    "waiting": _GREY,
    "never": _RED,
    **{
        k: _RED
        for k in ("mob", "mob_claw", "mob_dagger", "mob_bow", "mob_staff", "mob_axe", "mob_mace")
    },
    "rare": _PURPLE,
    "herb": _GREEN,
    "mine": _BROWN,
    "treasure": _BROWN,
    "object": _BROWN,
    "fish": _BLUE,
    "zone": _GREEN,
    "route": _BLUE,
    "waypoint": _BLUE,
    "spot": _BLUE,
    "flight": _BLUE,
    **{k: _TEAL for k in ("trainer", "vendor", "service", "innkeeper", "repair")},
    "banker": _GOLD,
    "auctioneer": _GOLD,
    "gold": _GOLD,
    "item": _PURPLE,
    "ledger": _PINK,
    "tale": _BROWN,
    "leather": _BROWN,
    "grave": _GREY,
    "note": _AMBER,
    "buttons": _TEAL,
    "play": _TEAL,
    "pause": _TEAL,
    "stop": _TEAL,
    "replay": _TEAL,
    "orbit": _PURPLE,
    # the app marks: the tile colours of the approved icon sheet (01.11.2026)
    "app_suite": _TEAL,
    "app_quests": _GOLD,
    "app_map": _GREEN,
    "app_browser": _BLUE,
    "app_gold": _GOLD,
    "app_route": _TEAL,
    "app_notes": _GOLD,
    "app_alts": _BLUE,
    "app_helpers": _GREY,
    "app_chat": _TEAL,
    "app_gestures": _GREEN,
    "app_courtesy": _PINK,
    "app_data": _GREY,
    "campfire": _AMBER,
    "app_campfire": _AMBER,
    "flame": _AMBER,
    "flame_heart": _AMBER,
    "flame_ring": _AMBER,
}


def tile(kind: str) -> bytes:
    """The kind's tile as a 32-bit TGA (BGRA, rows from the top), SIZE x SIZE."""
    make, _ = GLYPHS[kind]
    symbol = make()
    r, g, b = TILE_COLOR.get(kind, _GREY)
    s = TILE_SCALE
    outer = box(2, 2, SIZE - 2, SIZE - 2, 12)
    inner = box(
        2 + TILE_EDGE, 2 + TILE_EDGE, SIZE - 2 - TILE_EDGE, SIZE - 2 - TILE_EDGE, 12 - TILE_EDGE
    )
    centre = SIZE / 2

    def sym(x: float, y: float) -> float:
        return symbol(centre + (x - centre) / s, centre + (y - centre) / s) * s

    fill = (r * 0.32 + 0.04, g * 0.32 + 0.04, b * 0.32 + 0.04)
    edge = (r, g, b)

    def colour_at(x: float, y: float) -> tuple[float, float, float, float]:
        if outer(x, y) >= 0:
            return 0.0, 0.0, 0.0, 0.0
        d = sym(x, y)
        if d < 0:
            return 1.0, 1.0, 1.0, 1.0  # the symbol
        if d < 1.5:
            return 0.0, 0.0, 0.0, 1.0  # its dark rim
        if inner(x, y) >= 0:
            return edge[0], edge[1], edge[2], 1.0
        return fill[0], fill[1], fill[2], 1.0

    n = SAMPLES * SAMPLES
    body = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            cx, cy = px + 0.5, py + 0.5
            near = abs(outer(cx, cy)) < 1.5 or abs(inner(cx, cy)) < 1.5 or -1.5 < sym(cx, cy) < 3.0
            if near:
                acc = [0.0, 0.0, 0.0, 0.0]
                for sy, sx in itertools.product(range(SAMPLES), range(SAMPLES)):
                    c = colour_at(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
                    for k in range(3):
                        acc[k] += c[k] * c[3]
                    acc[3] += c[3]
                a = acc[3] / n
                rgb = [acc[k] / acc[3] if acc[3] else 0.0 for k in range(3)]
            else:
                c = colour_at(cx, cy)
                rgb, a = list(c[:3]), c[3]
            body += bytes(
                (round(rgb[2] * 255), round(rgb[1] * 255), round(rgb[0] * 255), round(a * 255))
            )
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *SIZE.to_bytes(2, "little"),
            *SIZE.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + bytes(body)


def draw(kind: str) -> list[tuple[int, int]]:
    make, _ = GLYPHS[kind]
    return render(make())
