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


def _ledger() -> Shape:  # a closed book with a coin on its cover: Bastian's Gold Rumours
    cover = box(12, 6, 54, 58, 5)
    spine = box(12, 6, 20, 58, 3)
    book = cut(cover, capsule(20.5, 9, 20.5, 55, 1.0))
    coin = cut(circle(38, 32, 10), ring(38, 32, 6, 2.0))
    return union(cut(book, circle(38, 32, 10), gap=2.2), coin, spine)


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
}


def draw(kind: str) -> list[tuple[int, int]]:
    make, _ = GLYPHS[kind]
    return render(make())
