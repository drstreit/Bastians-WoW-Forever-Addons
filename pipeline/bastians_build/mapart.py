"""Minimap tile table (map.md "Imagery pipeline", ADR 0007).

The clientdump tile lists (`<MapDirectory>_tiles.txt`, one `x<TAB>y<TAB>fileDataID` line per ADT
tile, read from the WDT MAID chunk; client-extraction.md) become
`Bastians_Map/Generated/MinimapTiles.lua`: per continent its map directory and one table keyed
`x * 64 + y` with the minimap texture's FileDataID. The addon draws the native textures by the path
`World\\Minimaps\\<directory>\\map<x>_<y>` and falls back to the id (Tiles.lua; the path form is
what P5 proved on Forever, forever-api.md); nothing is extracted or shipped. The overview cells
for `Bastians_Map_Art` are overview.py (roadmap B8.5).
"""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import TypedDict

from bastians_build.emit import emit_call
from bastians_build.files import write_text

#: Map directory (the WDT folder name) -> continent index (as `Bastians.Coords.CONTINENT_MAPS`).
CONTINENTS: dict[str, int] = {"Azeroth": 0, "Kalimdor": 1}
GRID = 64  # ADT tiles per axis
SUFFIX = "_tiles.txt"
OUTPUT = Path("Bastians_Map") / "Generated" / "MinimapTiles.lua"
ROOT = Path(__file__).resolve().parents[2]


class MapArtError(ValueError):
    """A tile list that cannot be used."""


class ContinentTiles(TypedDict):
    """One continent in the generated table: its map directory and the tiles by `x * 64 + y`."""

    directory: str
    tiles: dict[int, int]


def refuse_fixture_into_addons(source: Path, out_dir: Path, what: str = "tile lists") -> None:
    """A test fixture must never land in the repo's `addons/` folder (the dev install links it).

    Seen 21.10.2026: the golden `tests/fixtures/mapart` was emitted with the default `--out addons`,
    the game then drew exactly one native tile (the fixture's single real id) for a whole evening.
    """
    try:
        under_tests = source.resolve().is_relative_to(ROOT / "tests")
        into_addons = out_dir.resolve() == (ROOT / "addons").resolve()
    except OSError:
        return
    if under_tests and into_addons:
        raise MapArtError(
            f"refusing to write the test fixture {what} from {source} into {out_dir}: "
            "the dev install links addons/; give --out <some other folder>"
        )


def tile_key(x: int, y: int) -> int:
    """The Lua table key of tile (x, y): column times 64 plus row (Tiles.lua uses the same)."""
    return x * GRID + y


def read_tile_list(path: Path) -> dict[tuple[int, int], int]:
    """Parse one clientdump list: `x<TAB>y<TAB>fileDataID` per line, blank lines and `#` ignored."""
    tiles: dict[tuple[int, int], int] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t") if "\t" in line else line.split()
        if len(parts) != 3:
            raise MapArtError(f"{path}:{number}: expected 'x<TAB>y<TAB>fileDataID', got {raw!r}")
        try:
            x, y, fdid = (int(p) for p in parts)
        except ValueError as err:
            raise MapArtError(f"{path}:{number}: not integers: {raw!r}") from err
        if not (0 <= x < GRID and 0 <= y < GRID):
            raise MapArtError(f"{path}:{number}: tile ({x}, {y}) is outside the {GRID}x{GRID} grid")
        if fdid <= 0:
            raise MapArtError(f"{path}:{number}: FileDataID must be positive, got {fdid}")
        if (x, y) in tiles:
            raise MapArtError(f"{path}:{number}: tile ({x}, {y}) listed twice")
        tiles[(x, y)] = fdid
    if not tiles:
        raise MapArtError(f"{path}: no tiles")
    return tiles


def find_tile_lists(folder: Path) -> dict[str, Path]:
    """`<MapDirectory>_tiles.txt` files in a clientdump output folder, by map directory."""
    if not folder.is_dir():
        raise MapArtError(f"not a folder: {folder}")
    found = {p.name[: -len(SUFFIX)]: p for p in sorted(folder.glob(f"*{SUFFIX}")) if p.is_file()}
    if not found:
        raise MapArtError(f"no *{SUFFIX} files in {folder}")
    return found


def directories_from_maps(maps_json: Path) -> dict[str, int]:
    """Map directory -> Map.db2 id for every map in a clientdump Map dump: with it, the tile list
    of any world continent (Outland, Northrend, Zephras Isle, ...) finds its continent id."""
    from bastians_build.sources.clientdump import read_maps

    return {row.directory: map_id for map_id, row in read_maps(maps_json).items() if row.directory}


def tile_tables(
    lists: Mapping[str, Path],
    directories: Mapping[str, int] | None = None,
    skip: Mapping[str, set[tuple[int, int]]] | None = None,
) -> dict[int, ContinentTiles]:
    """Continent (Map.db2 id) -> { directory, tiles = { x * 64 + y: fileDataID } } for every
     known map directory. `skip` lists per directory the tiles the table leaves out: all-sea tiles
     (`sea_tiles`), so at close zoom the parchment cell shows instead of Blizzard's black water
    ."""
    known = dict(CONTINENTS)
    known.update(directories or {})
    tables: dict[int, ContinentTiles] = {}
    for directory, path in sorted(lists.items()):
        continent = known.get(directory)
        if continent is None:
            raise MapArtError(
                f"{path}: map directory {directory!r} is no continent "
                f"(known: {', '.join(sorted(known))}; give --maps <Map.json> for others)"
            )
        tiles = read_tile_list(path)
        for key in (skip or {}).get(directory, ()):
            tiles.pop(key, None)
        tables[continent] = {
            "directory": directory,
            "tiles": {tile_key(x, y): fdid for (x, y), fdid in sorted(tiles.items())},
        }
    return tables


def emit_tiles(client: str, tables: Mapping[int, ContinentTiles]) -> str:
    """MinimapTiles.lua: `Bastians.Map.RegisterTiles({ client, continents = { [c] = { directory,
    tiles = {...} } } })`."""
    counts = ", ".join(
        f"continent {c}: {len(t['tiles'])} tiles ({t['directory']})"
        for c, t in sorted(tables.items())
    )
    return emit_call(
        "Bastians.Map.RegisterTiles",
        [{"client": client, "continents": dict(sorted(tables.items()))}],
        comment=f"minimap tiles for {client} ({counts}); tiles key = x * 64 + y, "
        "value = FileDataID; the texture path is World\\\\Minimaps\\\\<directory>\\\\map<x>_<y>",
    )


def sea_tiles(overview_dir: Path | None, threshold: float) -> dict[str, set[tuple[int, int]]]:
    """Per map directory the tiles whose sea share in the overview index reaches `threshold`:
    the native layer leaves them out. Empty without an overview folder or without `tiles` in
    the indexes (stitched before 22.10.2026)."""
    if overview_dir is None or not overview_dir.is_dir():
        return {}
    from bastians_build.overview import find_overview_indexes, read_overview_index

    out: dict[str, set[tuple[int, int]]] = {}
    for directory, path in find_overview_indexes(overview_dir).items():
        index = read_overview_index(path)
        skip = {key for key, share in index.tile_sea.items() if share >= threshold}
        if skip:
            out[directory] = skip
    return out


def build_tiles(
    client: str,
    tiles_dir: Path,
    out_dir: Path,
    *,
    write: bool = True,
    maps_json: Path | None = None,
    skip: Mapping[str, set[tuple[int, int]]] | None = None,
) -> tuple[Path, bool, dict[int, int]]:
    """Read every tile list in `tiles_dir` and write the Lua table.

    Returns the output path, whether it changed, and the tile count per continent.
    """
    if write:
        refuse_fixture_into_addons(tiles_dir, out_dir)
    directories = directories_from_maps(maps_json) if maps_json else None
    tables = tile_tables(find_tile_lists(tiles_dir), directories, skip)
    path = out_dir / OUTPUT
    changed = write_text(path, emit_tiles(client, tables)) if write else False
    return path, changed, {c: len(t["tiles"]) for c, t in tables.items()}
