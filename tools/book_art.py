"""The book's pictures (content/strategies/art/README.md): AHSync makes them with the image model
and hands them over in its export (`art/<page id>.jpg`); this turns each one into what ships:

- the game's texture: cut to 2:1 from the middle, 512 x 256, BLP2 with DXT1 and mipmaps (about
  85 KB), in `<packs>/Bastians_Data_Strategies/Generated/Art/<page id>.blp`;
- the website's picture: the same cut, 1024 x 512 JPEG (tools/diary_site.py).

Usage: python tools/book_art.py <art folder> [--packs build/data/packs]

Only pictures named after a page of content/strategies are taken. Deterministic: the same picture
gives the same bytes. Needs Pillow (the dev dependencies); the pipeline itself decodes no images.
"""

from __future__ import annotations

import argparse
import io
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content" / "strategies"
PACKS = ROOT / "build" / "data" / "packs"
ADDON = "Bastians_Data_Strategies"
ART_DIR = Path("Generated") / "Art"
SOURCES = (".jpg", ".png")
GAME_SIZE = (512, 256)
WEB_SIZE = (1024, 512)
JPEG_QUALITY = 84
TRIM = 0.04  # taken off each edge before the 2:1 cut
BLP_PALETTE = b"\0" * 1024  # unused by DXT, part of the BLP2 header


def page_ids(content: Path = CONTENT) -> set[str]:
    return {p.stem for p in content.glob("*/*.md") if p.parent.name != "art"}


def pictures(art: Path, ids: set[str]) -> dict[str, Path]:
    """page id -> its picture in `art` (the first of .jpg, .png)."""
    out: dict[str, Path] = {}
    if not art.is_dir():
        return out
    for path in sorted(art.iterdir()):
        if path.suffix.lower() in SOURCES and path.stem in ids and path.stem not in out:
            out[path.stem] = path
    return out


def cut(path: Path):
    """The picture cut to 2:1 from the middle, RGB, after TRIM of each edge is taken off (the
    sketchbook pages' dog-eared corners and the strips beside the page, 24.10.2026)."""
    from PIL import Image

    with Image.open(path) as im:
        im = im.convert("RGB")
        w, h = im.size
        dx, dy = round(w * TRIM), round(h * TRIM)
        im = im.crop((dx, dy, w - dx, h - dy))
        w, h = im.size
        if w >= 2 * h:
            left = (w - 2 * h) // 2
            return im.crop((left, 0, left + 2 * h, h))
        height = w // 2
        top = (h - height) // 2
        return im.crop((0, top, w, top + height))


def web_image(path: Path) -> bytes:
    """The website's picture: 1024 x 512 JPEG."""
    from PIL import Image

    out = io.BytesIO()
    cut(path).resize(WEB_SIZE, Image.Resampling.LANCZOS).save(out, "JPEG", quality=JPEG_QUALITY)
    return out.getvalue()


# ---- DXT1 and BLP2 ------------------------------------------------------------------------------


def _565(r: int, g: int, b: int) -> int:
    return ((r * 31 + 127) // 255) << 11 | ((g * 63 + 127) // 255) << 5 | ((b * 31 + 127) // 255)


def _rgb(c: int) -> tuple[int, int, int]:
    return (
        ((c >> 11) & 31) * 255 // 31,
        ((c >> 5) & 63) * 255 // 63,
        (c & 31) * 255 // 31,
    )


def dxt1_block(pixels: list[tuple[int, int, int]]) -> bytes:
    """One 4x4 block (16 RGB pixels, row by row): the box of its colours, inset by a sixteenth,
    as the two end colours; each pixel takes the nearest of the four."""
    lo = [min(p[i] for p in pixels) for i in range(3)]
    hi = [max(p[i] for p in pixels) for i in range(3)]
    inset = [(hi[i] - lo[i]) // 16 for i in range(3)]
    c0 = _565(*(hi[i] - inset[i] for i in range(3)))
    c1 = _565(*(lo[i] + inset[i] for i in range(3)))
    if c0 < c1:
        c0, c1 = c1, c0
    if c0 == c1:
        return struct.pack("<HHI", c0, c1, 0)
    a, b = _rgb(c0), _rgb(c1)
    palette = (
        a,
        b,
        tuple((2 * a[i] + b[i]) // 3 for i in range(3)),
        tuple((a[i] + 2 * b[i]) // 3 for i in range(3)),
    )
    bits = 0
    for n, (r, g, bl) in enumerate(pixels):
        best, index = 1 << 30, 0
        for k, (pr, pg, pb) in enumerate(palette):
            d = (r - pr) ** 2 + (g - pg) ** 2 + (bl - pb) ** 2
            if d < best:
                best, index = d, k
        bits |= index << (2 * n)
    return struct.pack("<HHI", c0, c1, bits)


def dxt1(image) -> bytes:
    """An RGB image as DXT1 blocks (edges repeated where the size is not a multiple of four)."""
    w, h = image.size
    px = image.load()
    out = bytearray()
    for by in range(0, max(h, 1), 4):
        for bx in range(0, max(w, 1), 4):
            block = [px[min(bx + x, w - 1), min(by + y, h - 1)] for y in range(4) for x in range(4)]
            out += dxt1_block(block)
    return bytes(out)


def blp_dxt1(image) -> bytes:
    """A BLP2 texture with DXT1 and the full mipmap chain (each level resized from the picture)."""
    from PIL import Image

    w, h = image.size
    levels = []
    lw, lh = w, h
    while True:
        level = image if (lw, lh) == (w, h) else image.resize((lw, lh), Image.Resampling.LANCZOS)
        levels.append(dxt1(level))
        if lw == 1 and lh == 1:
            break
        lw, lh = max(1, lw // 2), max(1, lh // 2)
    offsets, sizes, at = [], [], 1172
    for data in levels:
        offsets.append(at)
        sizes.append(len(data))
        at += len(data)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    # magic, type 1 (direct), encoding 2 (DXT), alpha depth 0, alpha encoding 0 (DXT1), mipmaps
    head = b"BLP2" + struct.pack("<I4B2I", 1, 2, 0, 0, 1, w, h)
    head += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + BLP_PALETTE
    return head + b"".join(levels)


def game_texture(path: Path) -> bytes:
    """The game's texture: 512 x 256 BLP2, DXT1 with mipmaps."""
    from PIL import Image

    return blp_dxt1(cut(path).resize(GAME_SIZE, Image.Resampling.LANCZOS))


# ---- installing ---------------------------------------------------------------------------------


def install(art: Path, packs: Path, ids: set[str] | None = None) -> list[str]:
    """Writes the game's textures of the pictures in `art` into `packs` (and removes those of
    pictures that are gone). -> the page ids with a texture."""
    ids = page_ids() if ids is None else ids
    found = pictures(art, ids)
    target = packs / ADDON / ART_DIR
    if target.is_dir():
        for old in target.glob("*.blp"):
            if old.stem not in found:
                old.unlink()
    for pid, src in found.items():
        dst = target / f"{pid}.blp"
        if dst.is_file() and dst.stat().st_mtime >= src.stat().st_mtime:
            continue  # made from this picture already
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_suffix(".tmp")
        tmp.write_bytes(game_texture(src))
        tmp.replace(dst)
    return sorted(found)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("art", type=Path, help="the folder of the pictures (the export's art/)")
    ap.add_argument("--packs", type=Path, default=PACKS)
    args = ap.parse_args(argv)
    done = install(args.art, args.packs)
    print(f"book art: {len(done)} pictures in {args.packs / ADDON / ART_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
