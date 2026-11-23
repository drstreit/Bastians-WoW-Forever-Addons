"""The City & dungeon map's art (docs/addons/map.md "City plans", ADR 0065): cuts each place's
sheet into the textures the game loads and writes the manifest the window reads.

Usage: python tools/city_sheet.py [<ui map id> ...] [--sheets D:/bastians-ml/cities]
           [--paintings D:/bastians-ml/out] [--addon addons/Bastians_Map_Art] [--dumps .local/out]

The places are tools/cities.toml. Without an id every place is built; with ids only those, and
the others keep the tiles they have. The manifest always lists every place that has its tiles,
so building one place never drops another (until 17.11.2026 the manifest held only the place
just built). A place's picture is its finished sheet `<sheets>/<ui>.png` (look "painted") or the
game's cleaned, enlarged painting `<paintings>/<ui>_x4.png` (look "painting"); a place whose
picture is not on this machine keeps its tiles. The registry's world bounds are held against the
newest UiMapAssignment dump in --dumps: another Region refuses the build (a redrawn city).

A sheet is padded to whole 1024 pixel tiles by repeating its edge (the padding is never shown; it
keeps the mipmaps clean), each tile becomes `Generated/Cities/<ui>_<row>_<col>.blp`. Deterministic:
the same picture gives the same bytes. Needs Pillow (the dev dependencies).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons" / "Bastians_Map_Art"
REGISTRY = Path(__file__).with_name("cities.toml")
SHEETS = Path("D:/bastians-ml/cities")  # the finished sheets, <ui>.png
PAINTINGS = Path("D:/bastians-ml/out")  # the cleaned, enlarged paintings, <ui>_x4.png (ADR 0036)
LOOKS = ("painted", "painting")
TILE = 1024
REGION_SLACK = 0.01  # yards a registry bound may differ from the dump's


class CityError(Exception):
    pass


def places(registry: Path = REGISTRY) -> dict[int, dict]:
    """The registry: UiMap id -> name, continent, wx, wy (UiMapAssignment's Region, world yards:
    wx south to north, wy east to west), look, seed (a walked point, or None), painted (what
    tools/city_look.py needs to build the painted sheet, or None) and ground (the world map draws
    the sheet cut out to the city's plan, tools/city_ground.py)."""
    out: dict[int, dict] = {}
    for row in tomllib.loads(registry.read_text(encoding="utf-8")).get("place", []):
        if row.get("look") not in LOOKS:
            raise CityError(f"{registry.name}: place {row.get('ui')} has no look of {LOOKS}")
        if row["ui"] in out:
            raise CityError(f"{registry.name}: place {row['ui']} is listed twice")
        out[row["ui"]] = {
            "name": row["name"],
            "continent": row["continent"],
            "wx": (float(row["wx"][0]), float(row["wx"][1])),
            "wy": (float(row["wy"][0]), float(row["wy"][1])),
            "look": row["look"],
            "seed": tuple(row["seed"]) if row.get("seed") else None,
            "painted": row.get("painted"),
            "ground": bool(row.get("ground", False)),
        }
    return out


PLACES = places()


def picture_of(ui: int, look: str, sheets: Path, paintings: Path) -> Path | None:
    """The place's picture on this machine, or None."""
    path = sheets / f"{ui}.png" if look == "painted" else paintings / f"{ui}_x4.png"
    return path if path.is_file() else None


def newest_dump(dumps: Path) -> Path | None:
    """The UiMapAssignment dump of the highest Forever build in the folder (f<build>_...)."""
    found = []
    for path in dumps.glob("f*_UiMapAssignment.json"):
        match = re.fullmatch(r"f(\d+)_UiMapAssignment\.json", path.name)
        if match:
            found.append((int(match.group(1)), path))
    return max(found)[1] if found else None


def region_problems(listed: dict[int, dict], dump: Path) -> list[str]:
    """Where the registry's bounds are not the dump's Region of that UiMap."""
    regions: dict[int, list[list[float]]] = {}
    for row in json.loads(dump.read_text(encoding="utf-8"))["rows"]:
        regions.setdefault(row["UiMapID"], []).append([*row["Region"], row["MapID"]])
    problems = []
    for ui, place in sorted(listed.items()):
        rows = regions.get(ui, [])
        if len(rows) != 1:
            problems.append(f"{ui} {place['name']}: {len(rows)} assignments in {dump.name}")
            continue
        x0, y0, _, x1, y1, _, continent = rows[0]
        ours = (*place["wx"], *place["wy"])
        if continent != place["continent"] or any(
            abs(a - b) > REGION_SLACK for a, b in zip(ours, (x0, x1, y0, y1), strict=True)
        ):
            problems.append(
                f"{ui} {place['name']}: the registry says map {place['continent']}, wx "
                f"{place['wx']}, wy {place['wy']}; {dump.name} says map {continent}, wx "
                f"({x0}, {x1}), wy ({y0}, {y1})"
            )
    return problems


def blp_dxt1(image) -> bytes:
    """book_art's writer: BLP2, DXT1, the full mipmap chain."""
    spec = importlib.util.spec_from_file_location(
        "book_art", Path(__file__).with_name("book_art.py")
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("book_art", module)
    spec.loader.exec_module(module)
    return module.blp_dxt1(image)


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_bytes(data)
    temp.replace(path)


def grid(width: int, height: int) -> tuple[int, int]:
    """Rows and columns of whole tiles that hold the picture."""
    return -(-height // TILE), -(-width // TILE)


def tiles(sheet):
    """The picture padded by repeating its edge, cut: yields (row, col, tile)."""
    from PIL import Image

    width, height = sheet.size
    rows, cols = grid(width, height)
    padded = Image.new("RGB", (cols * TILE, rows * TILE))
    padded.paste(sheet, (0, 0))
    if cols * TILE > width:
        strip = sheet.crop((width - 1, 0, width, height)).resize((cols * TILE - width, height))
        padded.paste(strip, (width, 0))
    if rows * TILE > height:
        edge = padded.crop((0, height - 1, cols * TILE, height))
        strip = edge.resize((cols * TILE, rows * TILE - height))
        padded.paste(strip, (0, height))
    for row in range(rows):
        for col in range(cols):
            x, y = col * TILE, row * TILE
            yield row, col, padded.crop((x, y, x + TILE, y + TILE))


def lua_number(value: float) -> str:
    return f"{value:.3f}".rstrip("0").rstrip(".")


def manifest(sheets: list[dict]) -> str:
    """Generated/Cities.lua: the places, sorted by UiMap id."""
    out = [
        "-- GENERATED by tools/city_sheet.py, do not edit",
        "local B = Bastians or {}",
        "Bastians = B",
        "B.Map = B.Map or {}",
        "B.Map.cities = {",
    ]
    for s in sorted(sheets, key=lambda item: item["ui"]):
        path = f"Interface\\\\AddOns\\\\Bastians_Map_Art\\\\Generated\\\\Cities\\\\{s['ui']}_"
        ground = ""
        if s.get("ground"):
            listed = ", ".join(f'"{row}_{col}"' for row, col in s["ground"])
            ground = f", ground = {{ {listed} }}"
        out.append(
            f'  {{ ui = {s["ui"]}, name = "{s["name"]}", continent = {s["continent"]}, '
            f"wx = {{ {lua_number(s['wx'][0])}, {lua_number(s['wx'][1])} }}, "
            f"wy = {{ {lua_number(s['wy'][0])}, {lua_number(s['wy'][1])} }}, "
            f"w = {s['w']}, h = {s['h']}, rows = {s['rows']}, cols = {s['cols']}, "
            f'path = "{path}"{ground} }},'
        )
    out.append("}")
    return "\n".join(out) + "\n"


MANIFEST_ROW = re.compile(
    r"\{ ui = (\d+), .*? w = (\d+), h = (\d+), rows = (\d+), cols = (\d+), path = "
)


def ground_file(addon: Path, ui: int, row: int, col: int) -> Path:
    """A tile's mask for the world map (tools/city_ground.py writes it): white, the alpha is the
    city's plan."""
    return addon / "Generated" / "Cities" / f"{ui}_{row}_{col}_ground.tga"


def ground_of(ui: int, place: dict, rows: int, cols: int, addon: Path | None) -> list:
    """The tiles of a place the world map draws, (row, col): those with a mask, for a place the
    registry marks `ground`. Empty for every other place, or without masks."""
    if not (place.get("ground") and addon):
        return []
    return [
        (row, col)
        for row in range(rows)
        for col in range(cols)
        if ground_file(addon, ui, row, col).is_file()
    ]


def entry_of(ui: int, place: dict, width: int, height: int, addon: Path | None = None) -> dict:
    rows, cols = grid(width, height)
    fields = {key: place[key] for key in ("name", "continent", "wx", "wy")}
    entry = {"ui": ui, **fields, "w": width, "h": height, "rows": rows, "cols": cols}
    ground = ground_of(ui, place, rows, cols, addon)
    if ground:
        entry["ground"] = ground
    return entry


def build(ui: int, picture: Path, addon: Path, listed: dict[int, dict] | None = None) -> dict:
    """Writes one place's tiles and returns its manifest entry."""
    from PIL import Image

    place = (listed or PLACES)[ui]
    with Image.open(picture) as image:
        sheet = image.convert("RGB")
    for row, col, tile in tiles(sheet):
        atomic_write(addon / "Generated" / "Cities" / f"{ui}_{row}_{col}.blp", blp_dxt1(tile))
    return entry_of(ui, place, *sheet.size, addon)


def kept(ui: int, place: dict, addon: Path) -> dict | None:
    """The entry of a place that is not built now: its size from the manifest that is there, if
    every one of its tiles is there too. Else None: a place without its tiles is not listed."""
    path = addon / "Generated" / "Cities.lua"
    if not path.is_file():
        return None
    for match in MANIFEST_ROW.finditer(path.read_text(encoding="utf-8")):
        found, width, height, rows, cols = (int(value) for value in match.groups())
        if found != ui:
            continue
        there = all(
            (addon / "Generated" / "Cities" / f"{ui}_{row}_{col}.blp").is_file()
            for row in range(rows)
            for col in range(cols)
        )
        return entry_of(ui, place, width, height, addon) if there else None
    return None


def relist(addon: Path, listed: dict[int, dict] | None = None) -> list[dict]:
    """Writes the manifest again from the tiles there, building nothing (tools/city_ground.py,
    after its masks). -> the entries."""
    entries = []
    for ui, place in sorted((listed or PLACES).items()):
        entry = kept(ui, place, addon)
        if entry:
            entries.append(entry)
    atomic_write(addon / "Generated" / "Cities.lua", manifest(entries).encode("utf-8"))
    return entries


def run(
    wanted: list[int],
    addon: Path,
    sheets: Path,
    paintings: Path,
    listed: dict[int, dict] | None = None,
) -> tuple[list[dict], list[str]]:
    """Builds the wanted places (all when none is named), keeps the others' tiles and writes the
    manifest of every place that has its tiles. -> the entries, and one line per place."""
    listed = listed or PLACES
    entries, lines = [], []
    for ui, place in sorted(listed.items()):
        picture = picture_of(ui, place["look"], sheets, paintings)
        if (not wanted or ui in wanted) and picture:
            entry = build(ui, picture, addon, listed)
            lines.append(
                f"{ui} {place['name']}: built from {picture.as_posix()} ({place['look']}), "
                f"{entry['rows'] * entry['cols']} tiles, {entry['w']} x {entry['h']}"
            )
        else:
            entry = kept(ui, place, addon)
            why = "not asked for" if picture else "its picture is not on this machine"
            lines.append(
                f"{ui} {place['name']}: {'kept its tiles' if entry else 'NO TILES'} ({why})"
            )
        if entry:
            entries.append(entry)
    atomic_write(addon / "Generated" / "Cities.lua", manifest(entries).encode("utf-8"))
    return entries, lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ui", type=int, nargs="*")
    parser.add_argument("--sheets", type=Path, default=SHEETS)
    parser.add_argument("--paintings", type=Path, default=PAINTINGS)
    parser.add_argument("--addon", type=Path, default=ADDON)
    parser.add_argument("--dumps", type=Path, default=ROOT / ".local" / "out")
    args = parser.parse_args()
    unknown = sorted(set(args.ui) - set(PLACES))
    if unknown:
        parser.error(f"not in {REGISTRY.name}: {unknown}")
    dump = newest_dump(args.dumps) if args.dumps.is_dir() else None
    if dump:
        problems = region_problems(PLACES, dump)
        if problems:
            print("the registry's bounds are not the client's:\n  " + "\n  ".join(problems))
            return 1
        print(f"bounds: as {dump.name}")
    else:
        print(f"bounds: not checked, no UiMapAssignment dump in {args.dumps}")
    entries, lines = run(args.ui, args.addon, args.sheets, args.paintings)
    print("\n".join(lines))
    missing = sorted(set(PLACES) - {entry["ui"] for entry in entries})
    if missing:
        print(f"without tiles, so not on the map: {missing}")
        return 1
    print("new files need a full restart of the game (CLAUDE.md section 12)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
