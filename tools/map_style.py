"""The Bastian map's preview and cells (ADR 0027): reads the scene `clientdump mapdata` wrote and
draws it in the styles of pipeline/config/mapstyle.toml.

Usage: python tools/map_style.py --data .local/out/mapdata_forever/Azeroth --tiles 30,47,32,50
           [--style parchment|tolkien|modern|pencil|all] [--out .local/out/mapstyle_preview]
           [--listfile .local/listfile/community-listfile.csv]
           [--liquids .local/out/forever_LiquidType.json]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from mapstyle.render import STYLES, prepare, render  # noqa: E402
from mapstyle.scene import listfile_names, read_region  # noqa: E402


def liquid_names(path: Path) -> dict[int, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data["rows"] if isinstance(data, dict) and "rows" in data else data
    items = rows.items() if isinstance(rows, dict) else [(r["ID"], r) for r in rows]
    return {int(k): str(r.get("Name") or "") for k, r in items}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--data", type=Path, required=True)
    ap.add_argument("--tiles", help="x0,y0,x1,y1 (the preview's range; with --cells: only these)")
    ap.add_argument("--cells", type=int, metavar="CONTINENT", help="build the continent's cells")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument(
        "--areas",
        type=Path,
        help="the AreaTable dump (clientdump db2): the subzone names (with --names)",
    )
    ap.add_argument(
        "--names",
        metavar="CLIENT",
        help="write the subzone names for the Map (R27.6): --data is the mapdata root (its Azeroth "
        "and Kalimdor folders), --out the file, default addons/Bastians_Map/Generated/Names.lua",
    )
    ap.add_argument(
        "--labels",
        type=Path,
        help="with --names: the Blizzard map's labels.json (tools/map_blizzard.py labels): every "
        "style shows Blizzard's labels",
    )
    ap.add_argument("--emit", metavar="CLIENT", help="write the style addons' Generated folders")
    ap.add_argument("--build", default="", help="the client build the data came from (with --emit)")
    ap.add_argument("--style", default="all")
    ap.add_argument("--out", type=Path, default=ROOT / ".local" / "out" / "mapstyle_preview")
    ap.add_argument("--config", type=Path, default=ROOT / "pipeline" / "config" / "mapstyle.toml")
    ap.add_argument(
        "--listfile", type=Path, default=ROOT / ".local" / "listfile" / "community-listfile.csv"
    )
    ap.add_argument(
        "--liquids", type=Path, default=ROOT / ".local" / "out" / "forever_LiquidType.json"
    )
    args = ap.parse_args(argv)
    cfg = tomllib.loads(args.config.read_text(encoding="utf-8"))
    if args.emit:
        from mapstyle.emit import emit

        cells = args.data
        styles = list(STYLES) if args.style == "all" else [args.style]
        for gen in emit(cells, args.out, args.emit, args.build, styles):
            print(f"  {gen}")
        return 0
    if args.names:
        from mapstyle.labels import write_names

        if not (args.areas and args.areas.is_file()):
            print("error: --names needs --areas (the AreaTable dump)", file=sys.stderr)
            return 2
        out = args.out
        if out == ap.get_default("out"):
            out = ROOT / "addons" / "Bastians_Map" / "Generated" / "Names.lua"
        named = None
        if args.labels:
            raw = json.loads(args.labels.read_text(encoding="utf-8"))
            named = {int(c): rows for c, rows in raw.items()}
        counts = write_names(args.data, args.areas, out, args.names, args.build, named)
        print(f"names {counts} -> {out}")
        return 0
    if args.cells is not None:
        from mapstyle.cells import build, names_for

        out = args.out if args.out != ap.get_default("out") else ROOT / "build" / "mapstyle"
        names = names_for(
            args.listfile, args.data, args.data.parent / f"{args.data.name}_names.json"
        )
        styles = list(STYLES) if args.style == "all" else [args.style]
        only = tuple(int(v) for v in args.tiles.split(",")) if args.tiles else None
        t = time.perf_counter()
        result = build(
            args.data,
            args.cells,
            out,
            cfg,
            styles,
            names,
            liquid_names(args.liquids),
            args.workers,
            only,
        )
        print(f"{len(result['near'])} near cells, {time.perf_counter() - t:.0f} s -> {out}")
        return 0
    x0, y0, x1, y1 = (int(v) for v in args.tiles.split(","))
    t = time.perf_counter()
    region = read_region(args.data, x0, y0, x1, y1)
    ids = set(region.textures) | {int(f) for f in region.doodads["fdid"]}
    names = listfile_names(args.listfile, ids)
    prepared = prepare(region, names, liquid_names(args.liquids), cfg)
    took = time.perf_counter() - t
    print(f"scene {region.cols}x{region.rows} tiles, {prepared.w}x{prepared.h} drawn, {took:.1f} s")
    args.out.mkdir(parents=True, exist_ok=True)
    for style in STYLES if args.style == "all" else [args.style]:
        t = time.perf_counter()
        img = render(prepared, style, cfg)
        path = args.out / f"{args.data.name}_{args.tiles.replace(',', '_')}_{style}.png"
        img.save(path, optimize=True)
        print(f"  {style}: {path} ({time.perf_counter() - t:.1f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
