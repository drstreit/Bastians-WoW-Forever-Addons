"""The suite's own small textures, drawn here so they are reproducible.

Usage: python tools/make_media.py [--check]

Writes into `addons/Bastians_Core/Media/`: `Arrow.tga`, a 64x64 arrow with a shaft, pointing right
(east), white with a dark rim on a transparent ground, so `SetVertexColor` tints it and
`SetRotation` turns it; and the round corners of the kit (ST3, "round corners
against the Excel sheet charm"): `Disc.tga`, a white disc filling the 64x64 square, whose quarters
are the corners of a rounded fill, and `RingS.tga`, `RingM.tga`, `RingL.tga`, the disc's outline in
three line weights, so a corner drawn 4, 6 or 10 pixels wide keeps a line of about one pixel.
32-bit uncompressed TGA, top-left origin (both clients read TGA addon textures). The edges are 4x4
supersampled. `--check` exits 1 when a file on disk differs from what this script draws.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glyphs  # tools/glyphs.py, the suite's icon set

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "addons" / "Bastians_Core" / "Media"
SIZE = 64
SAMPLES = 4
RIM = 2.5  # pixels of dark rim around the white body


def _inside_arrow(x: float, y: float) -> float:
    """Signed distance-ish: > 0 inside the arrow body, in pixels from the nearest edge (capped)."""
    cy = SIZE / 2
    # the shaft: x 6..38, y cy-7..cy+7
    shaft = min(x - 6, 38 - x, y - (cy - 7), (cy + 7) - y)
    # the head: a triangle with the tip at (60, cy) and the back edge at x = 30, y cy-24..cy+24
    tip_x, back_x, half = 60.0, 30.0, 24.0
    if back_x - RIM - 1 <= x <= tip_x + RIM + 1:  # a little beyond, for the rim
        allowed = half * (tip_x - x) / (tip_x - back_x)
        # distance to the slanted edges, scaled to pixels along the normal
        slope = half / (tip_x - back_x)
        norm = (1 + slope * slope) ** 0.5
        head = min((allowed - abs(y - cy)) / norm, x - back_x)
    else:
        head = -1e9
    return max(shaft, head)


def draw_arrow() -> bytes:
    """The TGA bytes of the arrow."""
    pixels = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            body = rim = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = px + (sx + 0.5) / SAMPLES
                    y = py + (sy + 0.5) / SAMPLES
                    d = _inside_arrow(x, y)
                    if d > 0:
                        body += 1
                    elif d > -RIM:
                        rim += 1
            n = SAMPLES * SAMPLES
            alpha = round(255 * (body + rim) / n)
            white = round(255 * body / max(1, body + rim)) if body + rim else 0
            pixels += bytes((white, white, white, alpha))  # BGRA, grey: B = G = R
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),  # uncompressed true-colour, no colour map
            *SIZE.to_bytes(2, "little"),
            *SIZE.to_bytes(2, "little"),
            32,  # bits per pixel
            0x28,  # 8 alpha bits, top-left origin
        ]
    )
    return header + bytes(pixels)


def _tga(alphas: list[int], size: int = SIZE) -> bytes:
    """White pixels with the given alphas, as a 32-bit TGA of size x size."""
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *size.to_bytes(2, "little"),
            *size.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + b"".join(bytes((255, 255, 255, a)) for a in alphas)


def _coverage(inside, size: int = SIZE) -> list[int]:
    """Alpha per pixel: the share of the 4x4 samples for which `inside(x, y)` holds."""
    out = []
    n = SAMPLES * SAMPLES
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    if inside(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES):
                        hits += 1
            out.append(round(255 * hits / n))
    return out


def draw_disc() -> bytes:
    """A white disc touching all four sides: its quarters are the corners of a rounded fill."""
    r = SIZE / 2
    return _tga(_coverage(lambda x, y: (x - r) ** 2 + (y - r) ** 2 <= r * r))


def draw_glow() -> bytes:
    """A soft disc for the glow behind the dossier's plate (ADR 0038): the alpha falls from
    the centre to the edge with the square of the distance."""
    r = SIZE / 2
    out = []
    for py in range(SIZE):
        for px in range(SIZE):
            d = ((px + 0.5 - r) ** 2 + (py + 0.5 - r) ** 2) ** 0.5 / r
            out.append(round(255 * max(0.0, 1 - d) ** 2))
    return _tga(out)


def draw_ring(width: float) -> bytes:
    """The disc's outline, `width` texels wide on the inside of its edge."""
    r = SIZE / 2
    inner = (r - width) ** 2
    return _tga(_coverage(lambda x, y: inner <= (x - r) ** 2 + (y - r) ** 2 <= r * r))


RING_XL = 256


def draw_ring_xl() -> bytes:
    """A big ring for the Orbiter's orbits (voice.md, 01.11.2026): 256 x 256, a 2 texel line, so a
    circle of 200 to 400 px keeps a line of about one or two pixels."""
    r = RING_XL / 2
    inner = (r - 2.0) ** 2
    return _tga(
        _coverage(lambda x, y: inner <= (x - r) ** 2 + (y - r) ** 2 <= r * r, RING_XL), RING_XL
    )


ORN_W, ORN_H = 256, 16


def draw_ornament() -> bytes:
    """The Azeroth skin's rule under a section title (ADR 0034): a line fading out at both ends,
    a diamond in the middle and a dot on each side of it, white, 256 x 16."""
    cx, cy = ORN_W / 2, ORN_H / 2

    def inside(x: float, y: float) -> float:
        if abs(x - cx) / 6.5 + abs(y - cy) / 5.5 <= 1:  # the diamond
            return 1.0
        for dx in (-13.0, 13.0):  # the dots
            if (x - cx - dx) ** 2 + (y - cy) ** 2 <= 2.2**2:
                return 1.0
        if abs(y - cy) <= 0.75 and abs(x - cx) >= 17:  # the line, fading towards the ends
            return max(0.0, min(1.0, (ORN_W / 2 - abs(x - cx)) / (ORN_W * 0.3)))
        return 0.0

    n = SAMPLES * SAMPLES
    alphas = []
    for py in range(ORN_H):
        for px in range(ORN_W):
            total = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    total += inside(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
            alphas.append(round(255 * total / n))
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *ORN_W.to_bytes(2, "little"),
            *ORN_H.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + b"".join(bytes((255, 255, 255, a)) for a in alphas)


PARCH = 256  # the parchment's side, texels; it tiles


def _lattice(n: int, seed: int) -> list[list[float]]:
    """An n x n grid of values 0..1 from a fixed linear congruential sequence (reproducible)."""
    state = seed
    grid = []
    for _ in range(n):
        row = []
        for _ in range(n):
            state = (state * 1103515245 + 12345) % 2**31
            row.append(state / 2**31)
        grid.append(row)
    return grid


def _noise(x: float, y: float, grid: list[list[float]]) -> float:
    """Value noise over a periodic grid (smoothstep between its corners): it tiles."""
    n = len(grid)
    x0, y0 = int(x) % n, int(y) % n
    x1, y1 = (x0 + 1) % n, (y0 + 1) % n
    fx, fy = x - int(x), y - int(y)
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * sx
    bottom = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * sx
    return top + (bottom - top) * sy


def draw_parchment() -> bytes:
    """The Azeroth look's ground inside the game's frames: a warm
    parchment, 256 x 256, tileable: four octaves of periodic value noise for the cloudy stain
    and a fine fifth for the grain, opaque, as a 32-bit TGA (BGRA, top-left origin)."""
    octaves = [(4, 0.45, 7), (8, 0.25, 11), (16, 0.15, 13), (32, 0.08, 17)]
    grids = [(cells, weight, _lattice(cells, seed)) for cells, weight, seed in octaves]
    grain = _lattice(128, 23)
    base = (0.88, 0.74, 0.50)  # the parchment's light colour
    stain = (0.52, 0.34, 0.15)  # its darkest stain
    pixels = bytearray()
    for py in range(PARCH):
        for px in range(PARCH):
            v = 0.0
            for cells, weight, grid in grids:
                v += weight * _noise(px * cells / PARCH, py * cells / PARCH, grid)
            g = _noise(px * 128 / PARCH, py * 128 / PARCH, grain)
            t = min(1.0, max(0.0, (v - 0.35) * 1.1 + (g - 0.5) * 0.12))
            rgb = [base[i] + (stain[i] - base[i]) * t * 0.85 for i in range(3)]
            r, gg, b = (round(255 * c) for c in rgb)
            pixels += bytes((b, gg, r, 255))
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *PARCH.to_bytes(2, "little"),
            *PARCH.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + bytes(pixels)


def _tga_wh(alphas: list[int], width: int, height: int) -> bytes:
    """White pixels with the given alphas, as a 32-bit TGA of width x height (top-left origin)."""
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *width.to_bytes(2, "little"),
            *height.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + b"".join(bytes((255, 255, 255, a)) for a in alphas)


def draw_folio_shadow() -> bytes:
    """Bastian's Book's soft shadow under a card (ADR 0081): a 64 x 64 square whose alpha falls
    from the centre to every edge (the square of a smoothstep), drawn as nine pieces around a
    card: the quarters its corners, the middle row and column its sides."""
    r = SIZE / 2
    out = []
    for py in range(SIZE):
        for px in range(SIZE):
            d = min(1.0, ((px + 0.5 - r) ** 2 + (py + 0.5 - r) ** 2) ** 0.5 / r)
            t = 1 - d
            out.append(round(255 * (t * t * (3 - 2 * t)) ** 2))
    return _tga(out)


def draw_fade() -> bytes:
    """A vertical fade, clear at the top and full at the bottom (a smoothstep): the dark ground the
    book's hero lays its words on (ADR 0081)."""
    out = []
    for py in range(SIZE):
        t = (py + 0.5) / SIZE
        a = round(255 * t * t * (3 - 2 * t))
        out.extend([a] * SIZE)
    return _tga(out)


DECKLE_W, DECKLE_H = 256, 32


def draw_deckle() -> bytes:
    """A torn paper edge, 256 x 32 (ADR 0081): opaque below a ragged line, clear above it, the line
    a sum of periodic value noise; at the right end the tear runs higher, a corner torn away. Laid
    over the foot of a picture in the paper's colour, the picture seems torn out of the page."""
    coarse, fine = _lattice(16, 29), _lattice(64, 31)

    def line(x: float) -> float:
        y = 18 + 7 * (_noise(x * 16 / DECKLE_W, 0.5, coarse) - 0.5)
        y += 3 * (_noise(x * 64 / DECKLE_W, 0.5, fine) - 0.5)
        corner = max(0.0, (x - DECKLE_W * 0.86) / (DECKLE_W * 0.14))
        return y - 14 * corner * corner

    out = []
    n = SAMPLES * SAMPLES
    for py in range(DECKLE_H):
        for px in range(DECKLE_W):
            hits = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x, y = px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES
                    if y >= line(x):
                        hits += 1
            out.append(round(255 * hits / n))
    return _tga_wh(out, DECKLE_W, DECKLE_H)


# A corner drawn d pixels wide shows the 32 texels of a quarter: a one-pixel line needs 32 / d
# texels. S for corners of about 4 px, M for 6 px, L for 10 px (the pills).
RING_WIDTHS = {"RingS.tga": 8.0, "RingM.tga": 5.33, "RingL.tga": 3.2}

# The icon set: Media/Glyphs/<kind>.tga, white with a
# dark rim, tinted by the theme at runtime (Icons.lua).
GLYPH_FILES = {
    f"Glyphs/{kind}.tga": (lambda kind=kind: glyphs.tga(glyphs.draw(kind)))
    for kind in glyphs.GLYPHS
}

CREST = 128


def _crest_inside(x: float, y: float) -> bool:
    """Bastian's crest on a 40 x 40 field (the concept board's): a coin's two rings, a shovel."""
    d = ((x - 20) ** 2 + (y - 20) ** 2) ** 0.5
    if abs(d - 15.5) <= 1.3 or abs(d - 12) <= 0.5:
        return True

    def capsule(ax: float, ay: float, bx: float, by: float, r: float) -> bool:
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
        return (x - ax - t * vx) ** 2 + (y - ay - t * vy) ** 2 <= r * r

    if capsule(16.6, 9.5, 23.4, 9.5, 1.3) or capsule(20, 9.5, 20, 22.5, 1.3):
        return True
    blade = (
        (15.2, 22.2), (24.8, 22.2), (23.4, 28.4), (21.7, 29.525), (20, 29.9), (18.3, 29.525),
        (16.6, 28.4),
    )  # fmt: skip
    inside = False
    j = len(blade) - 1
    for i, (xi, yi) in enumerate(blade):
        xj, yj = blade[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def draw_crest() -> bytes:
    """Bastian's crest, a shovel on a coin: white on a
    transparent ground, 128 x 128, tinted in the book's gold."""
    k = 40 / CREST
    return _tga(_coverage(lambda x, y: _crest_inside(x * k, y * k), CREST), CREST)


# the portrait's colours: the book's table and gold (pipeline/config/themes: folioBar, folioGold)
CREST_GROUND = (0x1A, 0x14, 0x0F)
CREST_GOLD = (0xD8, 0xA4, 0x41)
CREST_PORTRAIT_SCALE = 0.74  # the game's ring covers the square's corners and rim


def draw_crest_portrait() -> bytes:
    """The crest for the round portrait of the game's own window frame (the WoW look): the gold
    crest on the table's dark, filling the square; the game cuts it round. In colour, since a
    portrait cannot be tinted."""
    k = 40 / CREST
    off = (1 - CREST_PORTRAIT_SCALE) / 2 * 40
    alphas = _coverage(
        lambda x, y: _crest_inside(
            (x * k - off) / CREST_PORTRAIT_SCALE, (y * k - off) / CREST_PORTRAIT_SCALE
        ),
        CREST,
    )
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *CREST.to_bytes(2, "little"),
            *CREST.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    pixels = bytearray()
    for a in alphas:
        r, g, b = (
            round(CREST_GROUND[i] + (CREST_GOLD[i] - CREST_GROUND[i]) * a / 255) for i in range(3)
        )
        pixels += bytes((b, g, r, 255))  # TGA stores blue, green, red
    return header + bytes(pixels)


# The tiles: Media/Tiles/<kind>.tga, the same symbols on a
# rounded tile in their category's colour, what the icons show since (Icons.lua).
TILE_FILES = {f"Tiles/{kind}.tga": (lambda kind=kind: glyphs.tile(kind)) for kind in glyphs.GLYPHS}

FILES = {
    "Arrow.tga": draw_arrow,
    "Disc.tga": draw_disc,
    "Glow.tga": draw_glow,
    "Ornament.tga": draw_ornament,
    "Parchment.tga": draw_parchment,
    "RingXL.tga": draw_ring_xl,
    "FolioShadow.tga": draw_folio_shadow,
    "Fade.tga": draw_fade,
    "Deckle.tga": draw_deckle,
    "Crest.tga": draw_crest,
    "CrestPortrait.tga": draw_crest_portrait,
    **{name: (lambda w=w: draw_ring(w)) for name, w in RING_WIDTHS.items()},
    **GLYPH_FILES,
    **TILE_FILES,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    status = 0
    for name, draw in FILES.items():
        target = MEDIA / name
        data = draw()
        if args.check:
            if not target.is_file() or target.read_bytes() != data:
                print(f"differs: {target}")
                status = 1
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_bytes(data)
        tmp.replace(target)
        print(f"written: {target}")
    return status


if __name__ == "__main__":
    sys.exit(main())
