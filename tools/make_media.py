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


def _tga(alphas: list[int]) -> bytes:
    """White pixels with the given alphas, as a 32-bit TGA of SIZE x SIZE."""
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *SIZE.to_bytes(2, "little"),
            *SIZE.to_bytes(2, "little"),
            32,
            0x28,
        ]
    )
    return header + b"".join(bytes((255, 255, 255, a)) for a in alphas)


def _coverage(inside) -> list[int]:
    """Alpha per pixel: the share of the 4x4 samples for which `inside(x, y)` holds."""
    out = []
    n = SAMPLES * SAMPLES
    for py in range(SIZE):
        for px in range(SIZE):
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


def draw_ring(width: float) -> bytes:
    """The disc's outline, `width` texels wide on the inside of its edge."""
    r = SIZE / 2
    inner = (r - width) ** 2
    return _tga(_coverage(lambda x, y: inner <= (x - r) ** 2 + (y - r) ** 2 <= r * r))


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


# A corner drawn d pixels wide shows the 32 texels of a quarter: a one-pixel line needs 32 / d
# texels. S for corners of about 4 px, M for 6 px, L for 10 px (the pills).
RING_WIDTHS = {"RingS.tga": 8.0, "RingM.tga": 5.33, "RingL.tga": 3.2}

# The icon set: Media/Glyphs/<kind>.tga, white with a
# dark rim, tinted by the theme at runtime (Icons.lua).
GLYPH_FILES = {
    f"Glyphs/{kind}.tga": (lambda kind=kind: glyphs.tga(glyphs.draw(kind)))
    for kind in glyphs.GLYPHS
}

# The tiles: Media/Tiles/<kind>.tga, the same symbols on a
# rounded tile in their category's colour, what the icons show since (Icons.lua).
TILE_FILES = {f"Tiles/{kind}.tga": (lambda kind=kind: glyphs.tile(kind)) for kind in glyphs.GLYPHS}

FILES = {
    "Arrow.tga": draw_arrow,
    "Disc.tga": draw_disc,
    "Ornament.tga": draw_ornament,
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
