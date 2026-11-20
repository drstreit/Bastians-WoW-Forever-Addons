"""Each city's picture against the real ground (docs/addons/map.md "Each painting against the real
ground", ADR 0065): the walk mesh, rastered onto the picture through the place's UiMap bounds.

Usage: python tools/city_fit.py [<ui map id> ...] --out <folder>
           [--meshes .local/out/navmesh_forever] [--clientdump <exe>]
           [--sheets D:/bastians-ml/cities] [--paintings D:/bastians-ml/out]

Writes `<out>/<ui>_fit.jpg` per place: the picture with where one walks tinted (green ground, white
road, pink indoors, blue water), to be read by eye: the tint lies on the painted ways, or the
picture does not fit. Prints the share of the picture one can walk on. A place's `seed` in
tools/cities.toml (a walked point, its flight master) keeps only the ground one reaches from there:
a city may stand over ground nobody walks. Opens no client; needs the walk mesh
(`tools/nav_build.py --navmesh`), a built clientdump, numpy and Pillow.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MID = 32 * 1600 / 3  # the navmesh frame: east = MID - wy, south = MID - wx (client-extraction.md)
MESHES = {0: "Azeroth", 1: "Kalimdor"}  # the continent's Map.db2 Directory
WIDTH = 2004  # pixels of the picture the fit is drawn on (half the sheet's)
TINTS = (  # the walk raster's bits (NavmeshView.Walk) and their colours
    (1, (40, 200, 60)),  # ground
    (2, (255, 255, 255)),  # road
    (4, (255, 60, 200)),  # indoors
    (24, (40, 120, 255)),  # shallow and deep water
)


def sheet_tool():
    spec = importlib.util.spec_from_file_location(
        "city_sheet", Path(__file__).with_name("city_sheet.py")
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("city_sheet", module)
    spec.loader.exec_module(module)
    return module


def walk_command(exe: Path, mesh: Path, raw: Path, place: dict, width: int, height: int) -> list:
    """The clientdump call that rasters the place's walk mesh onto a width x height picture."""
    (_, wx1), (wy0, wy1) = place["wx"], place["wy"]
    cmd = [str(exe), "navmesh-walk", "--mesh", str(mesh), "--out", str(raw)]
    cmd += ["--origin", f"{MID - wy1},{MID - wx1}", "--size", f"{width},{height}"]
    cmd += ["--ppy", repr(width / (wy1 - wy0))]
    if place.get("seed"):
        sx, sy, sz = place["seed"]
        cmd += ["--seed", f"{MID - sy},{sz},{MID - sx}"]
    return cmd


def tinted(picture, walk):
    """The picture with the walk raster's bits laid over it, half see-through."""
    import numpy as np

    out = np.asarray(picture, dtype="f4").copy()
    for bits, colour in TINTS:
        mask = (walk & bits) != 0
        out[mask] = out[mask] * 0.45 + np.array(colour, "f4") * 0.55
    return out.astype("u1")


def main() -> int:
    import numpy as np
    from PIL import Image

    cs = sheet_tool()
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ui", type=int, nargs="*")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--meshes", type=Path, default=ROOT / ".local" / "out" / "navmesh_forever")
    parser.add_argument("--sheets", type=Path, default=cs.SHEETS)
    parser.add_argument("--paintings", type=Path, default=cs.PAINTINGS)
    parser.add_argument(
        "--clientdump",
        type=Path,
        default=ROOT / "tools" / "clientdump" / "bin" / "Release" / "net10.0" / "clientdump.exe",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    failed = 0
    for ui, place in sorted(cs.PLACES.items()):
        if args.ui and ui not in args.ui:
            continue
        picture = cs.picture_of(ui, place["look"], args.sheets, args.paintings)
        mesh = args.meshes / f"{MESHES[place['continent']]}.navmesh"
        if not (picture and mesh.is_file()):
            lacks = f"mesh {mesh.name}" if picture else "picture"
            print(f"{ui} {place['name']}: skipped, no {lacks}")
            failed += 1
            continue
        with Image.open(picture) as image:
            height = round(WIDTH * image.size[1] / image.size[0])
            small = image.convert("RGB").resize((WIDTH, height), Image.LANCZOS)
        with tempfile.TemporaryDirectory(prefix="bastians-fit-") as tmp:
            raw = Path(tmp) / "walk.bin"
            cmd = walk_command(args.clientdump, mesh, raw, place, WIDTH, height)
            done = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if done.returncode != 0 or not raw.is_file():
                print(f"{ui} {place['name']}: clientdump failed: {done.stderr.strip()[-300:]}")
                failed += 1
                continue
            walk = np.fromfile(raw, "u1").reshape(height, WIDTH)
        target = args.out / f"{ui}_fit.jpg"
        Image.fromarray(tinted(small, walk)).save(target, quality=85)
        share = float((walk != 0).mean())
        print(f"{ui} {place['name']}: {share:.0%} of the picture is walked on -> {target}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
