"""The painted look of a city's sheet (docs/addons/map.md "The look on the sheet", ADR 0065):
builds `<sheets>/<ui>.png` for a place of tools/cities.toml that has a `[place.painted]` table,
from the game's painting and the client's own geometry.

Usage: python tools/city_look.py <ui map id> [--local <checkout>/.local] [--install <client>]
           [--sheets D:/bastians-ml/cities] [--paintings D:/bastians-ml/out] [--world <World.lua>]
           [--fresh] [--repaint] [--against <Bastians_Map_Art>] [--out <file.png>]

Steps, each printed with what it measured:

1. extract   the place's map data at 1024 pixels a tile, its walk raster, the rooms of the models
             placed there and WMOAreaTable (`clientdump`), the models' file names (the listfile).
             Kept in `<local>/cityplan/<ui>/`; `--fresh` reads the client again.
2. plan      where one walks, water, walls, gold passages (`mapstyle.city.plan`)
3. houses    the placed model's rooms as houses (`mapstyle.city.houses`, `masks`)
4. paint     the look on the painting (`mapstyle.city_paint`); `--repaint` does only this,
             on the plan and houses kept from the last run

`--against` cuts the sheet as tools/city_sheet.py does and holds the tiles against the ones in
that addon folder, byte for byte: the proof that a rebuilt sheet is the tested one. It writes no
tile. Cutting and the manifest stay with tools/city_sheet.py, which takes the sheet when the
place's `look` is "painted".

Run it with the machine-learning venv (D:/bastians-ml/venv: numpy, OpenCV, Pillow, torch,
spandrel, a GPU) and a built clientdump; the game may run. Deterministic on one machine: the same
client build and painting give the same bytes (Stormwind, 17.11.2026: 12 of 12 tiles as tested).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
CLIENT = "forever"


class LookError(Exception):
    pass


def sheet_tool():
    spec = importlib.util.spec_from_file_location(
        "city_sheet", Path(__file__).with_name("city_sheet.py")
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("city_sheet", module)
    spec.loader.exec_module(module)
    return module


def newest(folder: Path, table: str) -> Path:
    """The dump of `table` of the highest Forever build in the folder (f<build>_<table>.json)."""
    found = []
    for path in folder.glob(f"f*_{table}.json"):
        match = re.fullmatch(rf"f(\d+)_{table}\.json", path.name)
        if match:
            found.append((int(match.group(1)), path))
    if not found:
        raise LookError(f"no f<build>_{table}.json in {folder}")
    return max(found)[1]


def continent(local: Path, map_id: int) -> tuple[str, int]:
    """The map's Directory and its WDT's FileDataID, from the newest Map dump."""
    rows = json.loads(newest(local / "out", "Map").read_text(encoding="utf-8"))["rows"]
    row = next((r for r in rows if r["ID"] == map_id), None)
    if not row or not row.get("WdtFileDataID"):
        raise LookError(f"map {map_id} has no WDT in the Map dump")
    return row["Directory"], int(row["WdtFileDataID"])


def area_of(place: dict) -> tuple[tuple[float, float], tuple[float, float]]:
    """The measured part of the sheet in world yards: the look's own area, else the Region."""
    look = place["painted"]
    wx = tuple(look["area_wx"]) if "area_wx" in look else place["wx"]
    wy = tuple(look["area_wy"]) if "area_wy" in look else place["wy"]
    return wx, wy


def look_problems(look: dict, width: int | None = None, height: int | None = None) -> list[str]:
    """What is wrong with a place's `painted` table; `width` and `height` are the painting's."""
    from mapstyle.city import KINDS, ROOMS

    problems = []
    if look.get("kind", "streets") not in KINDS:
        problems.append(f"kind is none of {KINDS}")
    if look.get("rooms", "ceiling") not in ROOMS:
        problems.append(f"rooms is none of {ROOMS}")
    if not look.get("streets"):
        problems.append("no streets: the names of the model's groups that are districts")
    if not look.get("district"):
        problems.append("no district: a roof takes the colour of the nearest one")
    for d in look.get("district", []):
        if len(d.get("at", [])) != 2 or len(d.get("roof", [])) != 3:
            problems.append(f"district {d.get('name')}: at is x, y and roof is r, g, b")
    boxes = look.get("banner") or []
    boxes = [boxes] if boxes and not isinstance(boxes[0], list) else boxes
    for box in [*boxes, *look.get("keep", [])]:
        inside = width is None or (0 <= box[0] < box[2] <= width and 0 <= box[1] < box[3] <= height)
        if len(box) != 4 or not inside:
            problems.append(f"box {box} is not x0, y0, x1, y1 on the painting")
    for key in ("water_fade", "green_fade"):
        for term in look.get(key, []):
            if len(term) != 3 or term[0] not in ("left", "right", "top", "bottom"):
                problems.append(f"{key}: {term} is not [side, at, width]")
    return problems


def walk_command(exe: Path, mesh: Path, raw: Path, grid, seed) -> list[str]:
    """The clientdump call that rasters the walk mesh onto the plan grid. The origin has four
    decimals, as the prototype passed it: the raster is the same to the bit only then."""
    from mapstyle.city import YPP
    from mapstyle.scene import ORIGIN

    east, south = grid.origin()
    cmd = [str(exe), "navmesh-walk", "--mesh", str(mesh), "--out", str(raw)]
    cmd += ["--origin", f"{east:.4f},{south:.4f}", "--size", f"{grid.width},{grid.height}"]
    cmd += ["--ppy", repr(1 / YPP)]
    if seed:
        sx, sy, sz = seed
        cmd += ["--seed", f"{ORIGIN - sy},{sz},{ORIGIN - sx}"]
    return cmd


def run(cmd: list[str], cwd: Path) -> str:
    done = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, check=False)
    if done.returncode != 0:
        tail = (done.stderr.strip() or done.stdout.strip())[-400:]
        raise LookError(f"{Path(cmd[0]).name} {cmd[1]} failed: {tail}")
    lines = done.stdout.strip().splitlines()
    return lines[-1] if lines else ""


def extract(place: dict, grid, work: Path, local: Path, install: Path, exe: Path, fresh: bool):
    """Step 1: what the client holds about the place, into `work`. -> the map's Directory."""
    directory, wdt = continent(local, place["continent"])
    checkout = local.parent
    x0, y0, x1, y1 = grid.tiles()
    common = ["--install", str(install), "--map", directory, "--wdt-fdid", str(wdt)]
    tiles = [work / "mapdata" / directory / f"{x}_{y}.bmd.gz" for x in range(x0, x1 + 1)
             for y in range(y0, y1 + 1)]  # fmt: skip
    if fresh or not all(t.is_file() for t in tiles):
        cmd = [str(exe), "mapdata", *common, "--out", str(work / "mapdata")]
        cmd += ["--tiles", f"{x0},{y0},{x1},{y1}", "--pixels", "1024"]
        print("  " + run(cmd, checkout))
    rooms = work / "rooms"
    if fresh or not (rooms / "rooms.json").is_file():
        cmd = [str(exe), "wmo-rooms", *common, "--out", str(rooms)]
        cmd += ["--tiles", f"{x0 - 1},{y0 - 1},{x1 + 1},{y1 + 1}"]
        print("  " + run(cmd, checkout))
    table = work.parent / "WMOAreaTable.json"
    if fresh or not table.is_file():
        cmd = [str(exe), "db2", "--install", str(install), "--table", "WMOAreaTable"]
        cmd += ["--out", str(table)]
        print("  " + run(cmd, checkout))
    raw = work / "walk.bin"
    if fresh or not raw.is_file():
        mesh = local / "out" / f"navmesh_{CLIENT}" / f"{directory}.navmesh"
        if not mesh.is_file():
            raise LookError(f"{mesh} missing: build the walk mesh (tools/nav_build.py --navmesh)")
        print("  " + run(walk_command(exe, mesh, raw, grid, place["seed"]), checkout))
    return directory


def model_names(doodads, work: Path, listfile: Path, fresh: bool) -> dict[str, str]:
    """The file names of the place's models, by FileDataID (a string), kept in the work folder."""
    from mapstyle.scene import listfile_names

    cache = work / "names.json"
    if cache.is_file() and not fresh:
        return json.loads(cache.read_text(encoding="utf-8"))
    if not listfile.is_file():
        raise LookError(f"{listfile} missing: the trees are told by their file names")
    ids = {int(f) for f in doodads["fdid"]}
    names = {str(k): v for k, v in sorted(listfile_names(listfile, ids).items())}
    cache.write_text(json.dumps(names, sort_keys=True), encoding="utf-8")
    return names


def placement_of(rooms: Path, wmo: int | None) -> dict:
    """The placed model whose rooms are the houses: the one with the look's `wmo` (WMOAreaTable's
    WMOID), of several the one with the most geometry; without `wmo` the largest placed."""
    placed = json.loads((rooms / "rooms.json").read_text(encoding="utf-8"))["placements"]
    wanted = [p for p in placed if wmo is None or p["wmoId"] == wmo]
    if not wanted:
        raise LookError(f"no placement with WMOID {wmo} in {rooms}")
    return max(wanted, key=lambda p: (rooms / f"{p['unique']}.bin").stat().st_size)


def group_names(table: Path, wmo: int) -> dict[int, str]:
    """WMOAreaTable: the name of each group of the model."""
    rows = json.loads(table.read_text(encoding="utf-8"))["rows"]
    return {r["WMOGroupID"]: r["AreaName_lang"] for r in rows
            if r["WMOID"] == wmo and r["AreaName_lang"]}  # fmt: skip


def build(ui: int, place: dict, args, note=print):
    """Steps 2 to 4 for an extracted place. -> the sheet as u8 BGR, and what was measured."""
    import cv2
    import numpy as np
    from mapstyle import city, city_paint
    from mapstyle.scene import read_region

    look = place["painted"]
    work = args.local / "cityplan" / str(ui)
    painting = args.paintings / f"{ui}_x4.png"
    image = cv2.imread(str(painting))
    if image is None:
        raise LookError(f"{painting} missing: the game's painting (tools/map_blizzard.py)")
    problems = look_problems(look, image.shape[1], image.shape[0])
    if problems:
        raise LookError(f"[place.painted] of {ui}: " + "; ".join(problems))
    grid = city.grid_of(*area_of(place))
    directory, _ = continent(args.local, place["continent"])
    x0, y0, x1, y1 = grid.tiles()
    region = read_region(work / "mapdata" / directory, x0, y0, x1, y1).crop(
        grid.row0 - y0 * city.N, grid.col0 - x0 * city.N, grid.height, grid.width
    )
    shape = (grid.height, grid.width)
    measured: dict = {"grid": [grid.row0, grid.col0, grid.height, grid.width]}

    cache = work / "plan.npz"
    if args.repaint and cache.is_file():
        kept = np.load(cache)
        water, drawn = kept["water"], kept["drawn"]
        masks = {k: kept[k] for k in kept.files if k not in ("water", "drawn")}
        measured = json.loads((work / "measured.json").read_text(encoding="utf-8"))
        note("  plan and houses: as kept in " + cache.name)
    else:
        walk = np.fromfile(work / "walk.bin", dtype="u1").reshape(shape)
        zh = np.fromfile(work / "walk.bin.high", dtype="f4").reshape(shape)
        t = time.perf_counter()
        p = city.plan(region, walk, zh)
        p["zl"] = np.fromfile(work / "walk.bin.low", dtype="f4").reshape(shape)
        water = p["water"]
        keys = ("water", "paved", "wall", "open_walk", "gate")
        measured["plan"] = {k: int(p[k].sum()) for k in keys}
        note(f"  plan: {measured['plan']} pixels, {time.perf_counter() - t:.0f} s")

        t = time.perf_counter()
        placement = placement_of(work / "rooms", look.get("wmo"))
        mesh = city.read_meshes(work / "rooms" / f"{placement['unique']}.bin", placement["groups"])
        names = group_names(work.parent / "WMOAreaTable.json", placement["wmoId"])
        world = args.world.read_text(encoding="utf-8", errors="replace") if args.world else ""
        npcs = city.npcs_of(world, ui, place["wx"], place["wy"]) if world else []
        if not npcs:
            note("  no world pack (--world): the houses are read without their people")
        shell, labels, info = city.houses(
            placement, mesh, names, grid, set(look["streets"]), npcs, look.get("rooms", "ceiling")
        )
        if look.get("kind", "streets") == "canyon":
            caves = set(look.get("caves", []))
            outer = city.footprint(placement, mesh, grid, lambda g: g["flags"] & city.OUTER)
            cave = city.footprint(placement, mesh, grid, lambda g: names.get(g["id"]) in caves)
            districts = set(look["streets"])
            drawn, status, masks = city.canyon_masks(p, labels, info, districts, outer, cave)
            water = masks.pop("water")
        else:
            districts = set(look.get("districts", look["streets"]))
            drawn, status, masks = city.masks(p, shell, labels, info, districts)
        counts = {s: list(status.values()).count(s) for s in ("house", "underground", "passage")}
        measured["model"] = {
            "unique": placement["unique"],
            "wmo": placement["wmoId"],
            "groups": len(placement["groups"]),
            "named": sum(1 for g in placement["groups"] if g["id"] in names),
        }
        measured["npcs"] = len(npcs)
        measured["houses"] = counts
        note(f"  houses: model {measured['model']}, {len(npcs)} NPCs, {counts}, "
             f"{time.perf_counter() - t:.0f} s")  # fmt: skip
        np.save(work / "house_drawn.npy", drawn)
        (work / "house_status.json").write_text(json.dumps(status), encoding="utf-8")
        (work / "houses.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
        np.savez_compressed(cache, water=water, drawn=drawn, **masks)

    t = time.perf_counter()
    base = image[..., ::-1].astype("f4") / 255
    frame = city_paint.Frame(place["wx"], place["wy"], base.shape[1], base.shape[0])
    lay = city_paint.layers(water, masks, drawn, grid, frame)
    measured["sheet"] = {k: int(v.sum()) for k, v in lay.items() if k != "lab"}
    placed = city_paint.plants(region.doodads, frame)
    listfile = args.local / "listfile" / "community-listfile.csv"
    painter = city_paint.Painter(
        base, lay, placed, model_names(region.doodads, work, listfile, args.fresh), look, frame.ypp
    )
    measured["plants"] = painter.counts
    note(f"  sheet: {measured['sheet']} pixels; plants {painter.counts}")
    out = painter.sheet()
    note(f"  paint: {base.shape[1]} x {base.shape[0]}, {frame.ypp} yards a pixel, on "
         f"{painter.device}, {time.perf_counter() - t:.0f} s")  # fmt: skip
    (work / "measured.json").write_text(json.dumps(measured, indent=1), encoding="utf-8")
    return (np.clip(out, 0, 1)[..., ::-1] * 255).astype("u1"), measured


def against(sheet_png: Path, ui: int, addon: Path) -> tuple[int, int]:
    """The sheet cut as tools/city_sheet.py cuts it, against the tiles in the addon folder.
    -> tiles that are the same bytes, tiles."""
    from PIL import Image

    cs = sheet_tool()
    same = total = 0
    with Image.open(sheet_png) as image:
        sheet = image.convert("RGB")
    for row, col, tile in cs.tiles(sheet):
        there = addon / "Generated" / "Cities" / f"{ui}_{row}_{col}.blp"
        total += 1
        same += there.is_file() and there.read_bytes() == cs.blp_dxt1(tile)
    return same, total


def main() -> int:
    cs = sheet_tool()
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ui", type=int)
    parser.add_argument("--local", type=Path, default=ROOT / ".local")
    parser.add_argument("--install", type=Path, help="the client folder (default: install.toml)")
    parser.add_argument("--sheets", type=Path, default=cs.SHEETS)
    parser.add_argument("--paintings", type=Path, default=cs.PAINTINGS)
    parser.add_argument("--world", type=Path, help="the world pack's World.lua (the NPCs)")
    parser.add_argument("--fresh", action="store_true", help="read the client again")
    parser.add_argument("--repaint", action="store_true", help="paint the kept plan and houses")
    parser.add_argument("--against", type=Path, help="hold the tiles against this Map Art folder")
    parser.add_argument("--out", type=Path, help="the sheet's file (default <sheets>/<ui>.png)")
    args = parser.parse_args()
    place = cs.PLACES.get(args.ui)
    if not place:
        parser.error(f"not in {cs.REGISTRY.name}: {args.ui}")
    if not place.get("painted"):
        parser.error(
            f"{args.ui} {place['name']} has no [place.painted] table in {cs.REGISTRY.name}"
        )
    if args.world is None:
        world = args.local.parent / "addons" / "Bastians_Data_World" / "Generated" / "World.lua"
        args.world = world if world.is_file() else None
    try:
        from mapstyle import city

        install = args.install
        if install is None:
            config = tomllib.loads((args.local / "install.toml").read_text(encoding="utf-8"))
            install = Path(config["clients"][CLIENT])
        exe = args.local.parent / "tools" / "clientdump" / "bin" / "Release" / "net10.0"
        exe = exe / "clientdump.exe"
        work = args.local / "cityplan" / str(args.ui)
        work.mkdir(parents=True, exist_ok=True)
        grid = city.grid_of(*area_of(place))
        print(f"{args.ui} {place['name']}: plan {grid.width} x {grid.height} pixels, tiles "
              f"{grid.tiles()}, in {work}")  # fmt: skip
        extract(place, grid, work, args.local, install, exe, args.fresh)
        image, _ = build(args.ui, place, args)
    except LookError as error:
        print(f"error: {error}")
        return 1
    import cv2

    target = args.out or args.sheets / f"{args.ui}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_name(target.stem + ".tmp.png")
    cv2.imwrite(str(temp), image)
    temp.replace(target)
    print(f"-> {target.as_posix()}")
    if args.against:
        same, total = against(target, args.ui, args.against)
        print(f"against {args.against.as_posix()}: {same} of {total} tiles are the same bytes")
        return 0 if same == total else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
