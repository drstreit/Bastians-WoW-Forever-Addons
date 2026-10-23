"""The CurseForge avatars: the suite's symbol, the
Data project's icon and one icon per app for the project page, in the family colours.

Usage: python tools/project_icons.py [--out site/media]

Drawn from the suite's own glyph shapes (tools/glyphs.py), rendered sharp at 512 px, coloured with
the Dark teal theme's tokens (pipeline/config/themes/teal.toml). Each app has one theme colour:
its icon is that colour's ground in a rounded frame, the glyph in white with a dark rim and the
suite's B on a tab in the corner. The suite's symbol is the B in the middle of a ring that carries
the bundle's eight app icons, each app's colour running half way to its neighbours. Same input,
same pixels. Needs Pillow (the dev extra).
"""

from __future__ import annotations

import argparse
import colorsys
import math
import sys
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glyphs as G

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "media"  # the website shows them; CurseForge takes two of them
S = 512  # the avatar's side
WHITE = (255, 255, 255)

# the Dark teal theme's tokens (pipeline/config/themes/teal.toml)
TEAL = {
    "bg": "#14110f",
    "header": "#1f1d1b",
    "accent": "#0cd29d",
    "gold": "#ffd100",
    "good": "#4de666",
    "rare": "#a335ee",
    "path": "#4dccff",
    "sea": "#b8a380",
    "coinCopper": "#eda55f",
    "coinSilver": "#c7c7cf",
    "bad": "#e64d4d",
}


def map_art() -> G.Shape:
    """The folded map with a painter's star in its corner: the map's art."""
    return G.union(G.cut(G.GLYPHS["zone"][0](), G.circle(47, 15, 13)), G.star(47, 15, 11, 4.6, 4))


def monogram() -> G.Shape:
    """The suite's B in the glyphs' stroke: the stem, two bowls, three bars."""
    stem = G.capsule(19, 12, 19, 52, 5)
    top = G.intersect(G.ring(30, 22, 10, 9), G.halfplane(-1, 0, -30))
    bottom = G.intersect(G.ring(31, 41.5, 11, 9), G.halfplane(-1, 0, -31))
    bars = G.union(
        G.capsule(19, 12, 30, 12, 4.5),
        G.capsule(19, 32, 31, 32, 4.5),
        G.capsule(19, 52, 31, 52, 4.5),
    )
    return G.union(stem, top, bottom, bars)


def glyph(kind: str) -> Callable[[], G.Shape]:
    return G.GLYPHS[kind][0]


# file name, project or app, its shape, its theme colour; Core first, the ring's order
APPS: list[tuple[str, Callable[[], G.Shape], str]] = [
    ("bastians-core", glyph("settings"), "accent"),
    ("bastians-quests", glyph("quest"), "gold"),
    ("bastians-map", glyph("zone"), "good"),
    ("bastians-map-art", map_art, "sea"),
    ("bastians-browser", glyph("trainer"), "rare"),
    ("bastians-gold", glyph("gold"), "coinCopper"),
    ("bastians-route", glyph("route"), "path"),
    ("bastians-strategies", glyph("ledger"), "bad"),
]
DATA = ("bastians-data", glyph("item"), "coinSilver")


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def mix(a: str, b: str, t: float) -> tuple[int, int, int]:
    x, y = rgb(a), rgb(b)
    return (
        round(x[0] + (y[0] - x[0]) * t),
        round(x[1] + (y[1] - x[1]) * t),
        round(x[2] + (y[2] - x[2]) * t),
    )


def deep(col: str, t: float) -> tuple[int, int, int]:
    """`col` darkened by `t` towards the theme's ground; yellows turn towards amber on the way, as
    a darkened yellow goes olive otherwise."""
    r, g, b = (c / 255 for c in rgb(col))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b)
    if 0.11 < h < 0.19:
        h -= 0.035 * t
    r, g, b = colorsys.hsv_to_rgb(h, sat, v * (1 - t))
    ground = rgb(TEAL["bg"])
    k = t * 0.35
    return (
        round(r * 255 * (1 - k) + ground[0] * k),
        round(g * 255 * (1 - k) + ground[1] * k),
        round(b * 255 * (1 - k) + ground[2] * k),
    )


def radial(c_in, c_out, cy: float, power: float) -> Image.Image:
    """A soft radial ground from a 64 x 64 grid scaled up: smooth and deterministic."""
    n = 64
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            d = min(1.0, math.hypot((x + 0.5) / n - 0.5, (y + 0.5) / n - cy) / 0.75) ** power
            px[x, y] = tuple(round(c_in[i] + (c_out[i] - c_in[i]) * d) for i in range(3))
    return small.resize((S, S), Image.BICUBIC)


_masks: dict = {}


def masks(make: Callable[[], G.Shape], size: int) -> tuple[Image.Image, Image.Image]:
    """(body, body and rim) coverage of a 64-unit shape drawn `size` px wide; the anti-aliasing
    comes from the distance (one sample a pixel, the distance in output pixels)."""
    key = (make, size)
    if key in _masks:
        return _masks[key]
    shape = make()
    k = 64 / size
    rim = G.RIM / k
    body = bytearray(size * size)
    outer = bytearray(size * size)
    for py in range(size):
        v = (py + 0.5) * k
        row = py * size
        for px in range(size):
            d = shape((px + 0.5) * k, v) / k
            if d > rim + 1:
                continue
            body[row + px] = round(255 * min(1.0, max(0.0, 0.5 - d)))
            outer[row + px] = round(255 * min(1.0, max(0.0, 0.5 - (d - rim))))
    _masks[key] = (
        Image.frombytes("L", (size, size), bytes(body)),
        Image.frombytes("L", (size, size), bytes(outer)),
    )
    return _masks[key]


def paste_glyph(img, make, size, at, body, rim=None, shadow=None) -> None:
    """The glyph at `at` (top left): an optional soft shadow (dx, dy, blur, alpha), the dark rim,
    the body."""
    inner, outer = masks(make, size)
    if shadow:
        dx, dy, blur, alpha = shadow
        sh = Image.new("L", (S, S), 0)
        sh.paste(outer, (at[0] + dx, at[1] + dy))
        sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda a: a * alpha // 255)
        img.paste((0, 0, 0), (0, 0), sh)
    if rim is not None:
        img.paste(Image.new("RGB", (size, size), rim), at, outer)
    img.paste(Image.new("RGB", (size, size), body), at, inner)


def app_icon(make: Callable[[], G.Shape], colour: str) -> Image.Image:
    """An app's (or Data's) icon: its colour's ground, the frame, the glyph, the suite's B."""
    col = TEAL[colour]
    img = radial(deep(col, 0.42), deep(col, 0.8), cy=0.38, power=1.3)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        (22, 22, S - 23, S - 23), radius=64, outline=mix(col, "#ffffff", 0.35), width=8
    )
    paste_glyph(
        img, make, 288, ((S - 288) // 2,) * 2, WHITE, mix(col, TEAL["bg"], 0.85), (0, 12, 18, 150)
    )
    d.rounded_rectangle(
        (S - 132, S - 132, S - 40, S - 40),
        radius=22,
        fill=mix(col, TEAL["bg"], 0.88),
        outline=mix(col, "#ffffff", 0.35),
        width=4,
    )
    paste_glyph(img, monogram, 64, (S - 118, S - 118), mix(col, "#ffffff", 0.55))
    return img


def suite_icon() -> Image.Image:
    """The suite's symbol: the B in the middle, the eight app icons as tiles on a ring."""
    ground = TEAL["bg"]
    img = radial(mix(TEAL["header"], "#ffffff", 0.04), rgb(ground), cy=0.45, power=1.4)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        (22, 22, S - 23, S - 23), radius=64, outline=mix(ground, "#ffffff", 0.22), width=8
    )
    c, r, tile = S // 2, 166, 98
    step = 360 / len(APPS)
    for i, (_, _, colour) in enumerate(APPS):
        a = -90 + i * step
        d.arc(
            (c - r, c - r, c + r, c + r),
            a - step / 2,
            a + step / 2,
            fill=rgb(TEAL[colour]),
            width=14,
        )
    for i, (_, make, colour) in enumerate(APPS):
        a = math.radians(-90 + i * step)
        x = round(c + r * math.cos(a) - tile / 2)
        y = round(c + r * math.sin(a) - tile / 2)
        col = TEAL[colour]
        sh = Image.new("L", (S, S), 0)
        ImageDraw.Draw(sh).rounded_rectangle(
            (x, y + 6, x + tile, y + tile + 6), radius=20, fill=150
        )
        img.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(8)))
        d.rounded_rectangle(
            (x, y, x + tile, y + tile),
            radius=20,
            fill=deep(col, 0.45),
            outline=mix(col, "#ffffff", 0.4),
            width=4,
        )
        g = 62
        paste_glyph(
            img, make, g, (x + (tile - g) // 2, y + (tile - g) // 2), WHITE, deep(col, 0.85)
        )
    paste_glyph(img, monogram, 172, ((S - 172) // 2,) * 2, WHITE, rgb(ground), (0, 8, 14, 160))
    return img


def icons() -> dict[str, Callable[[], Image.Image]]:
    """File name -> renderer, the two projects' avatars first."""
    out: dict[str, Callable[[], Image.Image]] = {
        "bastians-suite": suite_icon,
        DATA[0]: lambda: app_icon(DATA[1], DATA[2]),
    }
    for name, make, colour in APPS:
        out[name] = lambda make=make, colour=colour: app_icon(make, colour)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    for name, render in icons().items():
        path = args.out / f"{name}.png"
        tmp = path.with_name(path.name + ".tmp")
        render().save(tmp, format="PNG", optimize=True)
        tmp.replace(path)
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
