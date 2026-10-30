"""The style addons' icons (ADR 0027): the suite's map icon (a folded map on a framed tile with the
"B" badge, site/media/bastians-map.png) with the folded map showing a piece of Elwynn in the style
itself, and the frame in the style's own colour, so the three addons tell apart at a glance.

Usage: python -m mapstyle.icon <preview folder>  (run from tools/)
writes site/media/bastians-map-<style>.png.
The art is committed; tools/make_icons.py turns it into each addon's Icon.tga."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SIZE = 512
FRAMES = {"modern": "7fb6f0", "pencil": "f0a060", "parchment": "e6cf98"}
CROP = (384, 576, 640, 832)  # Goldshire's crossing in the Elwynn preview
# the folded map: three panels, as the suite's map glyph
PANELS = [
    [(138, 198), (212, 172), (212, 344), (138, 372)],
    [(220, 150), (292, 182), (292, 370), (220, 340)],
    [(300, 180), (374, 150), (374, 332), (300, 362)],
]


def _rgb(hexcode: str) -> tuple[int, int, int]:
    return tuple(int(hexcode[i : i + 2], 16) for i in (0, 2, 4))


def icon(preview: Path, frame: str) -> Image.Image:
    fr = _rgb(frame)
    bg = tuple(int(c * 0.22) for c in fr)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.rounded_rectangle(
        (20, 20, SIZE - 20, SIZE - 20), radius=64, fill=(*bg, 255), outline=(*fr, 255), width=10
    )
    piece = (
        Image.open(preview).convert("RGB").crop(CROP).resize((240, 240), Image.Resampling.LANCZOS)
    )
    for i, panel in enumerate(PANELS):
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).polygon(panel, fill=255)
        layer = Image.new("RGB", (SIZE, SIZE))
        layer.paste(piece, (136, 140))
        if i == 1:  # the middle panel lies in the fold's shadow
            layer = Image.eval(layer, lambda v: int(v * 0.8))
        img.paste(layer, (0, 0), mask)
    for panel in PANELS:
        dr.line([*panel, panel[0]], fill=(16, 14, 12, 255), width=10, joint="curve")
    dr.rounded_rectangle(
        (376, 376, 470, 470), radius=18, fill=(*bg, 255), outline=(*fr, 255), width=6
    )
    font = ImageFont.truetype("segoeuib.ttf", 58)
    dr.text((423, 421), "B", font=font, fill=(*fr, 255), anchor="mm")
    return img


def main(argv: list[str]) -> int:
    folder = Path(argv[0]) if argv else ROOT / ".local" / "out" / "mapstyle_preview"
    for style, frame in FRAMES.items():
        out = ROOT / "site" / "media" / f"bastians-map-{style}.png"
        icon(folder / f"Azeroth_30_47_32_50_{style}.png", frame).save(out, optimize=True)
        print(f"written: {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
