"""The addons' icons in the game's AddOns list, from the website art.

Usage: python tools/make_icons.py [--check]

Reads the owner's icons `site/media/bastians-<name>.png` (512 x 512), or for an app without
website art the suite's tile of a glyph (`GLYPH_ICONS`, tools/glyphs.py), and writes each addon's
`Icon.tga` (64 x 64, 32-bit uncompressed, top-left origin), which its TOC names with
`## IconTexture: Interface\\AddOns\\<addon>\\Icon`. The data packs carry the Data icon, the
developer probe the suite's. `--check` exits 1 when a file on disk differs from what this script
writes (tools/check_toc.py checks that every TOC names an icon that exists).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glyphs  # tools/glyphs.py, the suite's icon set

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
ART = ROOT / "site" / "media"
SIZE = 64

ICONS = {
    "Bastians_Core": "core",
    "Bastians_Browser": "browser",
    "Bastians_Data": "data",
    "Bastians_Data_Items": "data",
    "Bastians_Data_Market": "data",
    "Bastians_Data_Nav": "data",
    "Bastians_Data_Quests": "data",
    "Bastians_Data_Strategies": "data",
    "Bastians_Data_Text_enUS": "data",
    "Bastians_Data_Text_deDE": "data",  # the game data in other languages (ADR 0033)
    "Bastians_Data_Text_frFR": "data",
    "Bastians_Data_Text_esES": "data",
    "Bastians_Data_Text_koKR": "data",
    "Bastians_Data_Text_zhCN": "data",
    "Bastians_Data_Text_zhTW": "data",
    "Bastians_Data_World": "data",
    "Bastians_Gold": "gold",
    "Bastians_Map": "map",
    "Bastians_Map_Art": "map-art",
    "Bastians_Map_Blizzard": "map-blizzard",  # ADR 0036: tools/mapstyle/icon.py, gold frame
    "Bastians_Map_Modern": "map-modern",  # the style addons (ADR 0027): tools/mapstyle/icon.py
    "Bastians_Map_Parchment": "map-parchment",
    "Bastians_Map_Pencil": "map-pencil",
    "Bastians_Probe": "suite-black",  # the developer probe: the whole suite
    "Bastians_Quests": "quests",
    "Bastians_Route": "route",
    "Bastians_Strategies": "strategies",
    "Bastians_TalesSpike": "suite-black",  # developer-only like the probe (T1, 27.10.2026)
}
# apps without website art wear the tile of a glyph (owner's style of the icons, R25.38)
GLYPH_ICONS = {
    "Bastians_Notes": "note",
    "Bastians_Library": "ledger",  # until the Library has website art (L3, 28.10.2026)
}


def tga(art: Path) -> bytes:
    """The art scaled to SIZE x SIZE as a 32-bit TGA (pixels BGRA, rows from the top)."""
    image = Image.open(art).convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    header = bytes(
        [
            *(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            *SIZE.to_bytes(2, "little"),
            *SIZE.to_bytes(2, "little"),
            32,
            0x28,  # 8 alpha bits, top-left origin
        ]
    )
    r, g, b, a = image.split()
    return header + Image.merge("RGBA", (b, g, r, a)).tobytes()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when an icon is not current")
    args = parser.parse_args(argv)
    stale = []
    sources = [
        (addon, lambda name=name: tga(ART / f"bastians-{name}.png"))
        for addon, name in ICONS.items()
    ]
    sources += [(addon, lambda kind=kind: glyphs.tile(kind)) for addon, kind in GLYPH_ICONS.items()]
    for addon, draw in sorted(sources):
        if not (ADDONS / addon).is_dir():
            continue  # a private addon the public snapshot leaves out (the Library, 29.10.2026)
        data = draw()
        target = ADDONS / addon / "Icon.tga"
        if target.is_file() and target.read_bytes() == data:
            continue
        if args.check:
            stale.append(str(target.relative_to(ROOT)))
            continue
        tmp = target.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(target)
        print(f"written: {target.relative_to(ROOT)}")
    for path in stale:
        print(f"not current: {path}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
