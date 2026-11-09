"""The seamless Blizzard map (ADR 0036): the build steps around tools/mapstyle/blizzard.py.

  textures   the FileDataIDs of every painting and overlay tile, for `clientdump textures --list`
  paintings  Blizzard's paintings, fully explored, as PNG (the input of blizzard_clean.py)
  cells      a continent's far and near cells from the cleaned paintings (then `clientdump blp`
             and `map_style.py --emit forever --style blizzard`)
  world      the story map's picture from the filled far images (ADR 0057), --out as `cells`
  labels     the continents' and Zephras Isle's names with their AreaTable match
             -> <out>/blizzard/labels.json

Usage: python tools/map_blizzard.py <step> --dumps .local/out --prefix f70685
           [--textures .local/out/worldmap_f70685] [--clean D:/bastians-ml/out]
           [--data .local/out/mapdata_forever/Azeroth --continent 0] [--out <dir>]
           [--tiles x0,y0,x1,y1] [--workers 8] [--force]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from mapstyle.blizzard import Atlas, build, labels, world_image  # noqa: E402

READINGS = ROOT / "data" / "mapstyle" / "blizzard"
# mapdata folders -> Map.db2 ids: the continents and Zephras Isle
CONTINENTS = {"Azeroth": 0, "Kalimdor": 1, "2991": 2991}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("step", choices=("textures", "paintings", "cells", "labels", "world"))
    ap.add_argument("--dumps", type=Path, default=ROOT / ".local" / "out")
    ap.add_argument("--prefix", default="f70685")
    ap.add_argument("--textures", type=Path, default=ROOT / ".local" / "out" / "worldmap_f70685")
    ap.add_argument("--clean", type=Path, default=Path("D:/bastians-ml/out"))
    ap.add_argument("--data", type=Path, help="the continent's mapdata folder")
    ap.add_argument("--continent", type=int, default=0)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--tiles", help="x0,y0,x1,y1: only the near cells of these tiles")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--force", action="store_true", help="redraw near cells already drawn")
    args = ap.parse_args(argv)
    if args.step == "world":
        # the story map's picture (ADR 0057): --out is the folder holding work_0 and work_1
        out = ROOT / "content" / "strategies" / "art" / "front" / "world.jpg"
        print(world_image(args.out / "blizzard", out))
        return 0
    atlas = Atlas.load(args.dumps, args.prefix)
    if args.step == "textures":
        out = args.out or ROOT / ".local" / "out" / f"worldmap_{args.prefix}.txt"
        out.write_text("\n".join(str(f) for f in atlas.fdids()) + "\n", encoding="utf-8")
        print(f"{len(atlas.fdids())} textures -> {out}")
        return 0
    if args.step == "paintings":
        out = args.out or ROOT / ".local" / "out" / f"paintings_{args.prefix}"
        out.mkdir(parents=True, exist_ok=True)
        n = 0
        for continent in CONTINENTS.values():
            for ui in atlas.zones(continent):
                atlas.painting(ui, args.textures).save(out / f"{ui}.png")
                n += 1
        print(f"{n} paintings -> {out}")
        return 0
    if not (args.data and args.data.is_dir()):
        print("error: --data must be the continent's mapdata folder", file=sys.stderr)
        return 2
    if args.step == "labels":
        # --data is the mapdata root (its Azeroth, Kalimdor and 2991 folders); writes labels.json
        # beside the cells for map_style.py --emit
        out = (args.out or ROOT / "build" / "mapstyle" / "forever") / "blizzard" / "labels.json"
        found = {}
        for name, continent in CONTINENTS.items():
            if not (args.data / name).is_dir():
                continue
            found[continent] = labels(atlas, READINGS, args.data / name, continent)
            unmatched = [
                e["text"] for e in found[continent] if not e["area"] and e["kind"] != "sea"
            ]
            count = len(found[continent])
            print(f"continent {continent}: {count} names, not in AreaTable: {unmatched}")
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(found, indent=1, ensure_ascii=False), encoding="utf-8")
        print(f"-> {out}")
        return 0
    out = args.out or ROOT / "build" / "mapstyle" / "forever"
    only = tuple(int(v) for v in args.tiles.split(",")) if args.tiles else None
    t = time.perf_counter()
    result = build(
        atlas,
        args.data,
        args.continent,
        args.textures,
        args.clean,
        out,
        args.workers,
        only,
        args.force,
    )
    print(
        f"{len(result['far'])} far, {len(result['near'])} near cells, "
        f"{time.perf_counter() - t:.0f} s -> {out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
