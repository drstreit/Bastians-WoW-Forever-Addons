"""The preview sheet of the glyph set for the owner's review (styling round ST4, 23.10.2026).

Usage: python tools/glyph_sheet.py [--out docs/architecture/mockups/icons.html]

Writes one HTML page with every glyph of `tools/glyphs.py` embedded as a PNG: large, at the sizes
the game draws them (24, 16, 14 px), tinted in the four planned themes (the page multiplies the
white body like `SetVertexColor` does), in context (a Browser row, map pins on parchment, minimap
buttons), with a ballot per glyph and three general questions. The page is `glyph_sheet.html`
with the glyphs filled in. Nothing in the addons changes before the owner's answers.
"""

from __future__ import annotations

import argparse
import base64
import json
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glyphs

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "docs" / "architecture" / "mockups" / "icons.html"
TEMPLATE = Path(__file__).resolve().parent / "glyph_sheet.html"


def png(pixels: list[tuple[int, int]]) -> bytes:
    """An RGBA PNG of a glyph (grey body and rim, alpha), deterministic."""
    size = glyphs.SIZE
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # no filter
        for x in range(size):
            grey, alpha = pixels[y * size + x]
            raw += bytes((grey, grey, grey, alpha))

    def chunk(kind: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def glyph_data() -> dict[str, dict[str, str]]:
    out = {}
    for kind, (_, what) in glyphs.GLYPHS.items():
        data = base64.b64encode(png(glyphs.draw(kind))).decode("ascii")
        out[kind] = {"src": "data:image/png;base64," + data, "what": what}
    return out


def page() -> str:
    template = TEMPLATE.read_text(encoding="utf-8")
    return template.replace("__GLYPHS__", json.dumps(glyph_data(), sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_name(args.out.name + ".tmp")
    tmp.write_text(page(), encoding="utf-8", newline="\n")
    tmp.replace(args.out)
    print(f"written: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
