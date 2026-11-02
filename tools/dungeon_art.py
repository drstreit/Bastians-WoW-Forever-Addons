"""Santiago Reyes' dungeon maps (ADR 0048, data.md "Dungeons"): his "Atlas of Azeroth: Forever"
pictures, used in the suite with his permission (02.11.2026), turned into what Core ships:

- the portfolio banner under each map cut off (his signature inside the map stays), the map scaled
  to 1024 x 682 (the art's 3:2) and laid on a 4 x 3 grid of 256 px tiles, the empty part of the
  last row filled with the map's bottom line (no dark seam in the smaller mipmaps);
- each tile a BLP2 texture with DXT1 and mipmaps (tools/book_art.py), in
  `addons/Bastians_Core/Media/Dungeons/<key>_<1..12>.blp`, the way Scenery.FloorArt reads an art
  prefix (`floor.art .. index`).

Usage: python tools/dungeon_art.py [--art .local/dungeon-art/santiago] [--out <Media/Dungeons>]

The originals stay in `.local` (private): the shipped tiles are the only copy in the repository.
The keys are the `art` names of pipeline/config/dungeon_art.toml. Deterministic: the same picture
gives the same bytes. Needs Pillow (the dev dependencies).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from book_art import blp_dxt1

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / ".local" / "dungeon-art" / "santiago"
OUT = ROOT / "addons" / "Bastians_Core" / "Media" / "Dungeons"

# key -> his file (ArtStation, "Dungeons | World of Warcraft Forever | Fan-made"; owner's download
# 02.11.2026). The Wetlands as his "Version 2.0".
MAPS = {
    "dalaran_sewers": "santiago-reyes-dalaranc-f.webp",
    "dalaran_city": "santiago-reyes-dalaran-f.webp",
    "wetlands": "santiago-reyes-esw2-f.webp",
    "thanes": "santiago-reyes-hot-f.webp",
    "lordaeron": "santiago-reyes-lordaeron-f.webp",
}
SOURCE_SIZE = (1276, 953)
BANNER_TOP = 850  # the blue portfolio banner starts at 851-859 (measured 02.11.2026)
MAP_W, MAP_H = 1024, 682
TILE, COLS, ROWS = 256, 4, 3


def tiles(path: Path) -> list:
    """The map's 12 tiles (RGB, 256 x 256) in reading order."""
    from PIL import Image

    image = Image.open(path).convert("RGB")
    if image.size != SOURCE_SIZE:
        raise SystemExit(f"{path.name}: {image.size}, expected {SOURCE_SIZE}")
    plate = image.crop((0, 0, SOURCE_SIZE[0], BANNER_TOP))
    plate = plate.resize((MAP_W, MAP_H), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (TILE * COLS, TILE * ROWS))
    canvas.paste(plate, (0, 0))
    bottom = plate.crop((0, MAP_H - 1, MAP_W, MAP_H))
    for y in range(MAP_H, TILE * ROWS):
        canvas.paste(bottom, (0, y))
    return [
        canvas.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE))
        for r in range(ROWS)
        for c in range(COLS)
    ]


def write_atomic(path: Path, data: bytes) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def build(art: Path, out: Path) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    written = []
    for key, name in MAPS.items():
        source = art / name
        if not source.is_file():
            raise SystemExit(f"missing {source}")
        for i, tile in enumerate(tiles(source), 1):
            path = out / f"{key}_{i}.blp"
            write_atomic(path, blp_dxt1(tile))
            written.append(path)
        print(f"{key}: {COLS * ROWS} tiles from {name}")
    return written


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--art", type=Path, default=ART, help="his pictures (default: %(default)s)")
    p.add_argument("--out", type=Path, default=OUT, help="the tiles (default: %(default)s)")
    args = p.parse_args(argv)
    build(args.art, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
