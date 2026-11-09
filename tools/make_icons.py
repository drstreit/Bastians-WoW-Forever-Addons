"""The addons' icons in the game's AddOns list: the app marks on their tiles (plan-second-wave.md
S1, 01.11.2026; before: the website art, ).

Usage: python tools/make_icons.py [--check]

Draws for every app the tile of its app mark (`GLYPH_ICONS`, tools/glyphs.py: the same pictogram
as its minimap button and feed), and for the map style addons and the developer addons the
owner's art `site/media/bastians-<name>.png` (512 x 512, `ICONS`), and writes each addon's
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
    "Bastians_Map_Art": "map-art",
    "Bastians_Map_Blizzard": "map-blizzard",  # ADR 0036: tools/mapstyle/icon.py, gold frame
    "Bastians_Map_Modern": "map-modern",  # the style addons (ADR 0027): tools/mapstyle/icon.py
    "Bastians_Map_Parchment": "map-parchment",
    "Bastians_Map_Pencil": "map-pencil",
    "Bastians_Probe": "suite-black",  # the developer probe: the whole suite
    "Bastians_TalesSpike": "suite-black",  # developer-only like the probe (T1, 27.10.2026)
    "Bastians_ChatSpike": "suite-black",  # developer-only like the probe (CH0, 31.10.2026)
}
# every app wears the tile of its app mark (plan-second-wave.md S1; the kinds of B.APPS' `icon`)
GLYPH_ICONS = {
    "Bastians_Core": "app_suite",
    "Bastians_Quests": "app_quests",
    "Bastians_Map": "app_map",
    "Bastians_Browser": "app_browser",
    "Bastians_Gold": "app_gold",
    "Bastians_Route": "app_route",
    "Bastians_Strategies": "ledger",
    "Bastians_Notes": "app_notes",
    "Bastians_Alts": "app_alts",
    "Bastians_Helpers": "app_helpers",
    "Bastians_Voice": "orbit",  # Bastian's Orbiter
    "Bastians_Chat": "app_chat",
    "Bastians_Gestures": "app_gestures",
    "Bastians_Courtesy": "app_courtesy",
    "Bastians_Campfire": "app_campfire",
    "Bastians_Library": "tale",
    **{
        f"Bastians_Data{suffix}": "app_data"
        for suffix in (
            "",
            "_Items",
            "_Market",
            "_Nav",
            "_Quests",
            "_Strategies",
            "_World",
            "_Text_enUS",
            "_Text_deDE",
            "_Text_frFR",
            "_Text_esES",
            "_Text_koKR",
            "_Text_zhCN",
            "_Text_zhTW",
        )
    },
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
