"""Overview textures for Bastians_Map_Art (map.md "Imagery pipeline", roadmap B8.5).

`tools/clientdump overview` stitches one map's minimap tiles into one DXT1 texture per `span` x
`span` cell of ADT tiles (`<Dir>_<cx>_<cy>.blp`, or `.tga`) and lists them in `<Dir>_overview.json`.
This module checks those files against the build config, copies them into
`Bastians_Map_Art/Generated/Tiles/<continent>_<cx>_<cy>.<ext>` (only when the bytes differ, stale
cells removed) and writes `Bastians_Map_Art/Generated/Overview.lua`: one `RegisterOverview` call
with the cells per continent (Map.db2 id) keyed `cx * grid + cy`, where `grid = 64 / span`. The
addon draws a cell at the world rectangle of its ADT block; levels 0-2 come from the texture's mips.
Nothing here decodes images: the header check reads the BLP2 or TGA dimensions only.
"""

from __future__ import annotations

import json
import re
import struct
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

from bastians_build.config import MapArtConfig
from bastians_build.emit import emit_call
from bastians_build.files import write_text
from bastians_build.mapart import CONTINENTS, GRID, MapArtError

SUFFIX = "_overview.json"
FORMATS = ("blp", "tga")
BLP_HEADER = 1172
OUTPUT = Path("Generated") / "Overview.lua"
TILES = Path("Generated") / "Tiles"
MASKS = Path("Generated") / "Masks"  # coast masks for the native tiles (one per coast tile)
#: The texture path prefix the addon hands to SetTexture (no extension: the client finds the file).
TEXTURE_PATH = "Interface\\AddOns\\{addon}\\Generated\\Tiles\\"
CELL_FILE = re.compile(r"^(\d+)_(\d+)_(\d+)\.(blp|tga)$")
MASK_FILE = re.compile(r"^(\d+)_(\d+)_(\d+)\.blp$")
MASK_PATH = "Interface\\AddOns\\{addon}\\Generated\\Masks\\"


@dataclass(frozen=True)
class Cell:
    x: int
    y: int
    file: Path  # the clientdump output file
    adts: int
    size: int

    @property
    def ext(self) -> str:
        return self.file.suffix[1:]


@dataclass(frozen=True)
class OverviewIndex:
    directory: str  # the map's WDT folder name
    map_id: int
    span: int
    pixels: int
    format: str
    mips: bool
    source_tiles: int
    alpha: str = "dxt1"  # clientdump --alpha; older indexes without the field were dxt1
    sea: str | None = (
        None  # clientdump --sea "rrggbb": the painted sea, opaque cells; None = transparent
    )
    tile_sea: dict[tuple[int, int], float] = field(default_factory=dict)  # (x, y) -> share of sea
    cells: list[Cell] = field(default_factory=list)
    masks: dict[tuple[int, int], Path] = field(default_factory=dict)  # coast tile -> mask file

    @property
    def size(self) -> int:
        return sum(c.size for c in self.cells)


@dataclass(frozen=True)
class OverviewResult:
    path: Path
    changed: bool
    counts: dict[int, int]  # continent -> cells
    size: int  # bytes of all cell textures and coast masks
    budget_kb: int | None
    copied: int
    removed: int
    masks: int = 0  # coast masks installed

    @property
    def over_budget(self) -> bool:
        return self.budget_kb is not None and self.size > self.budget_kb * 1024


# ---------------------------------------------------------------------------------------------
# Reading the clientdump output
# ---------------------------------------------------------------------------------------------


def texture_size(path: Path) -> tuple[int, int]:
    """Width and height from a BLP2 (DXT) or TGA header; MapArtError when the file is neither."""
    with path.open("rb") as fh:
        head = fh.read(BLP_HEADER)
    if path.suffix.lower() == ".blp":
        if len(head) < BLP_HEADER or head[:4] != b"BLP2":
            raise MapArtError(f"{path}: not a BLP2 file")
        encoding = head[8]
        if encoding != 2:
            raise MapArtError(f"{path}: BLP encoding {encoding} is not DXT (2)")
        width, height = struct.unpack_from("<II", head, 12)
        mip0 = struct.unpack_from("<I", head, 84)[0]
        if path.stat().st_size < BLP_HEADER + mip0:
            raise MapArtError(f"{path}: truncated (mip 0 needs {mip0} bytes)")
        return width, height
    if path.suffix.lower() == ".tga":
        if len(head) < 18 or head[2] != 2 or head[16] != 32:
            raise MapArtError(f"{path}: not an uncompressed 32-bit TGA")
        width, height = struct.unpack_from("<HH", head, 12)
        return width, height
    raise MapArtError(f"{path}: unknown texture format (expected .blp or .tga)")


def read_overview_index(path: Path) -> OverviewIndex:
    """Parse one `<Dir>_overview.json` and check every cell file next to it."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        raise MapArtError(f"{path}: {err}") from err
    for key in ("map", "mapId", "span", "pixels", "format", "cells"):
        if key not in raw:
            raise MapArtError(f"{path}: missing `{key}`")
    span, pixels, fmt = int(raw["span"]), int(raw["pixels"]), str(raw["format"])
    if span < 1 or GRID % span:
        raise MapArtError(f"{path}: span {span} does not divide {GRID}")
    if fmt not in FORMATS:
        raise MapArtError(f"{path}: format {fmt!r} is not one of {', '.join(FORMATS)}")
    grid = GRID // span
    cells: list[Cell] = []
    seen: set[tuple[int, int]] = set()
    for i, c in enumerate(raw["cells"]):
        try:
            x, y, name, adts = int(c["x"]), int(c["y"]), str(c["file"]), int(c["adts"])
        except (KeyError, TypeError, ValueError) as err:
            raise MapArtError(f"{path}: cell {i}: {err}") from err
        if not (0 <= x < grid and 0 <= y < grid):
            raise MapArtError(f"{path}: cell ({x}, {y}) is outside the {grid}x{grid} grid")
        if (x, y) in seen:
            raise MapArtError(f"{path}: cell ({x}, {y}) listed twice")
        seen.add((x, y))
        file = path.with_name(name)
        if not file.is_file():
            raise MapArtError(f"{path}: cell file {name} is missing")
        if file.suffix[1:].lower() != fmt:
            raise MapArtError(f"{path}: cell file {name} is not a .{fmt}")
        width, height = texture_size(file)
        if width != span * pixels or height != span * pixels:
            raise MapArtError(
                f"{file}: {width}x{height} px, expected {span * pixels} "
                f"(span {span} x pixels {pixels})"
            )
        if adts < 1 or adts > span * span:
            raise MapArtError(f"{path}: cell ({x}, {y}) has {adts} ADT tiles")
        cells.append(Cell(x=x, y=y, file=file, adts=adts, size=file.stat().st_size))
    if not cells:
        raise MapArtError(f"{path}: no cells")
    cells.sort(key=lambda c: (c.x, c.y))
    masks: dict[tuple[int, int], Path] = {}
    for entry in raw.get("masks") or []:
        x, y = int(entry[0]), int(entry[1])
        file = path.parent / "masks" / f"{raw['map']}_{x}_{y}.blp"
        if not file.is_file():
            raise MapArtError(f"{path}: mask file masks/{file.name} is missing")
        masks[(x, y)] = file
    return OverviewIndex(
        directory=str(raw["map"]),
        map_id=int(raw["mapId"]),
        span=span,
        pixels=pixels,
        format=fmt,
        mips=bool(raw.get("mips", False)),
        source_tiles=int(raw.get("sourceTiles", 0)),
        alpha=str(raw.get("alpha", "dxt1")),
        sea=str(raw["sea"]).lower() if raw.get("sea") else None,
        tile_sea={(int(t[0]), int(t[1])): float(t[2]) for t in raw.get("tiles") or []},
        cells=cells,
        masks=masks,
    )


def find_overview_indexes(folder: Path) -> dict[str, Path]:
    """`<Dir>_overview.json` files in a clientdump output folder, by map directory."""
    if not folder.is_dir():
        raise MapArtError(f"not a folder: {folder}")
    found = {p.name[: -len(SUFFIX)]: p for p in sorted(folder.glob(f"*{SUFFIX}")) if p.is_file()}
    if not found:
        raise MapArtError(f"no *{SUFFIX} files in {folder}")
    return found


def overview_tables(
    indexes: Mapping[str, Path],
    config: MapArtConfig,
    client: str,
    directories: Mapping[str, int] | None = None,
) -> dict[int, OverviewIndex]:
    """Continent (Map.db2 id) -> index, every index checked against the client's config."""
    known = dict(CONTINENTS)
    known.update(directories or {})
    pixels = config.pixels_for(client)
    out: dict[int, OverviewIndex] = {}
    for directory, path in sorted(indexes.items()):
        index = read_overview_index(path)
        continent = known.get(directory)
        if continent is None:
            raise MapArtError(
                f"{path}: map directory {directory!r} is no continent "
                f"(known: {', '.join(sorted(known))}; give --maps <Map.json> for others)"
            )
        if index.map_id != continent:
            raise MapArtError(f"{path}: mapId {index.map_id} but the Map table says {continent}")
        if (
            index.span != config.span
            or index.pixels != pixels
            or index.alpha != config.alpha
            or index.sea != config.sea
        ):
            sea = f" --sea {config.sea}" if config.sea else ""
            raise MapArtError(
                f"{path}: built with span {index.span}, {index.pixels} px per tile, alpha "
                f"{index.alpha} and sea {index.sea or 'transparent'}; the {client} config wants "
                f"span {config.span}, {pixels} px, {config.alpha} and sea "
                f"{config.sea or 'transparent'} "
                f"(rerun clientdump overview --span {config.span} --pixels {pixels} "
                f"--alpha {config.alpha}{sea})"
            )
        out[continent] = index
    return out


# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------


def cell_key(x: int, y: int, span: int) -> int:
    """The Lua table key of cell (x, y): column times the grid size plus row."""
    return x * (GRID // span) + y


def emit_overview(
    client: str, config: MapArtConfig, tables: Mapping[int, OverviewIndex], build: str | None = None
) -> str:
    """Overview.lua: `Bastians.Map.RegisterOverview({ client, span, pixels, path, continents })`."""
    span = config.span
    continents = {
        continent: [cell_key(c.x, c.y, span) for c in index.cells]
        for continent, index in sorted(tables.items())
    }
    info: dict[str, object] = {
        "client": client,
        "span": span,
        "grid": GRID // span,
        "pixels": config.pixels_for(client),
        "path": TEXTURE_PATH.format(addon=config.addon),
        "continents": continents,
    }
    if build:
        info["build"] = build
    masks = installed_masks(tables, config)
    if any(masks.values()):
        # the native layer masks these coast tiles' sea out (Tiles.lua); key = x * 64 + y
        info["masks"] = {
            c: sorted(x * GRID + y for x, y in keys) for c, keys in masks.items() if keys
        }
        info["maskPath"] = MASK_PATH.format(addon=config.addon)
    counts = ", ".join(f"continent {c}: {len(t.cells)} cells" for c, t in sorted(tables.items()))
    return emit_call(
        "Bastians.Map.RegisterOverview",
        [info],
        comment=f"overview textures for {client} ({counts}); key = cx * grid + cy, one texture per "
        f"{span}x{span} ADT cell",
    )


def installed_masks(
    tables: Mapping[int, OverviewIndex], config: MapArtConfig
) -> dict[int, dict[tuple[int, int], Path]]:
    """Per continent the coast masks whose tile stays in the native tile table (its sea share is
    below `skip_sea`; the all-sea tiles are left out of the table, `mapart.sea_tiles`)."""
    out: dict[int, dict[tuple[int, int], Path]] = {}
    for continent, index in tables.items():
        out[continent] = {
            key: file
            for key, file in sorted(index.masks.items())
            if index.tile_sea.get(key, 0.0) < config.skip_sea
        }
    return out


def _copy_if_changed(src: Path, dst: Path) -> bool:
    data = src.read_bytes()
    if dst.is_file() and dst.read_bytes() == data:
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(dst)
    return True


def install_overview(
    client: str,
    overview_dir: Path,
    out_dir: Path,
    config: MapArtConfig,
    *,
    directories: Mapping[str, int] | None = None,
    build: str | None = None,
    write: bool = True,
) -> OverviewResult:
    """Check the clientdump output, copy the cell textures into the addon and write Overview.lua."""
    tables = overview_tables(find_overview_indexes(overview_dir), config, client, directories)
    addon_dir = out_dir / config.addon
    tiles_dir = addon_dir / TILES
    masks_dir = addon_dir / MASKS
    wanted: dict[str, Path] = {}
    for continent, index in tables.items():
        for cell in index.cells:
            wanted[f"{continent}_{cell.x}_{cell.y}.{cell.ext}"] = cell.file
    wanted_masks = {
        f"{continent}_{x}_{y}.blp": file
        for continent, masks in installed_masks(tables, config).items()
        for (x, y), file in masks.items()
    }
    copied = removed = 0
    changed = False
    if write:
        for folder, files, pattern in (
            (tiles_dir, wanted, CELL_FILE),
            (masks_dir, wanted_masks, MASK_FILE),
        ):
            for name, src in sorted(files.items()):
                if _copy_if_changed(src, folder / name):
                    copied += 1
            if folder.is_dir():
                for stale in sorted(folder.iterdir()):
                    if pattern.match(stale.name) and stale.name not in files:
                        stale.unlink()
                        removed += 1
        changed = write_text(addon_dir / OUTPUT, emit_overview(client, config, tables, build))
    return OverviewResult(
        path=addon_dir / OUTPUT,
        changed=changed or copied > 0 or removed > 0,
        counts={c: len(t.cells) for c, t in tables.items()},
        size=sum(t.size for t in tables.values())
        + sum(f.stat().st_size for f in wanted_masks.values()),
        budget_kb=config.budget_kb,
        copied=copied,
        removed=removed,
        masks=len(wanted_masks),
    )
