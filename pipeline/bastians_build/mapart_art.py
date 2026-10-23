"""Continent parchment for the overview cells.

The stitcher paints Blizzard's continent map art (the parchment with the sea names) into every
pixel of a cell that the minimap tiles leave empty, so the inside of a cell matches the zone art
the Map draws around it. This module finds that art and its world placement:

- `UiMapXMapArt` (phase 0) -> `UiMapArt` -> `UiMapArtStyleLayer` (layer 0: layer and tile size)
  and `UiMapArtTile` (layer 0: row, column, FileDataID), dumped with `clientdump db2`;
- the continent UiMap at home on a Map.db2 map (`clientdump.continent_homes`);
- the transform of that UiMap (map fraction -> world yards, coordinates.md), the same one the
  addon uses, so the stitched parchment and the drawn zone art meet without a seam.

`<Dir>_art.json` next to the overview index is what `clientdump overview --art` reads.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from bastians_build.files import write_text
from bastians_build.sources import clientdump
from bastians_build.sources.probe import Transform


class ArtError(ValueError):
    """A map-art table that cannot be used."""


@dataclass(frozen=True)
class ArtLayer:
    ui_map_id: int
    art_id: int
    layer_width: int
    layer_height: int
    tile_width: int
    tile_height: int
    tiles: tuple[tuple[int, int, int], ...]  # (row, column, FileDataID) of layer 0, row-major


@dataclass(frozen=True)
class ArtTables:
    art_of: dict[int, int]  # UiMapID -> UiMapArtID (phase 0)
    style_of: dict[int, int]  # UiMapArtID -> UiMapArtStyleID
    layers: dict[int, dict]  # UiMapArtStyleID -> the layer-0 row
    tiles: dict[int, list[tuple[int, int, int]]]  # UiMapArtID -> (row, col, fdid) of layer 0


TABLES = ("UiMapXMapArt", "UiMapArt", "UiMapArtStyleLayer", "UiMapArtTile")


def table_paths(dumps: Path, prefix: str) -> dict[str, Path]:
    return {name: dumps / f"{prefix}_{name}.json" for name in TABLES}


def read_art_tables(paths: Mapping[str, Path]) -> ArtTables:
    """The four tables from clientdump JSON dumps (`table_paths`)."""
    rows = {name: clientdump._rows(paths[name], name) for name in TABLES}
    art_of: dict[int, int] = {}
    for row in rows["UiMapXMapArt"]:
        if int(row.get("PhaseID") or 0) == 0 and row.get("UiMapID") not in art_of:
            art_of[int(row["UiMapID"])] = int(row["UiMapArtID"])
    style_of = {int(r["ID"]): int(r["UiMapArtStyleID"]) for r in rows["UiMapArt"]}
    layers = {
        int(r["UiMapArtStyleID"]): r
        for r in rows["UiMapArtStyleLayer"]
        if int(r.get("LayerIndex") or 0) == 0
    }
    tiles: dict[int, list[tuple[int, int, int]]] = {}
    for r in rows["UiMapArtTile"]:
        if int(r.get("LayerIndex") or 0) != 0:
            continue
        fdid = int(r.get("FileDataID") or 0)
        if fdid <= 0:
            continue
        tiles.setdefault(int(r["UiMapArtID"]), []).append(
            (int(r["RowIndex"]), int(r["ColIndex"]), fdid)
        )
    for lst in tiles.values():
        lst.sort()
    return ArtTables(art_of, style_of, layers, tiles)


def art_layer(tables: ArtTables, ui_map_id: int) -> ArtLayer | None:
    """The layer-0 art of a UiMap, or None when the tables have none for it."""
    art_id = tables.art_of.get(ui_map_id)
    style = art_id is not None and tables.style_of.get(art_id)
    layer = style and tables.layers.get(style)
    tiles = art_id is not None and tables.tiles.get(art_id)
    if not (layer and tiles):
        return None
    width, height = int(layer["LayerWidth"]), int(layer["LayerHeight"])
    tile_w, tile_h = int(layer["TileWidth"]), int(layer["TileHeight"])
    if width <= 0 or height <= 0 or tile_w <= 0 or tile_h <= 0:
        raise ArtError(f"UiMap {ui_map_id}: art style {style} has an empty layer")
    return ArtLayer(ui_map_id, art_id, width, height, tile_w, tile_h, tuple(tiles))


def art_json(layer: ArtLayer, transform: Transform) -> dict:
    """What `clientdump overview --art` reads: the layer, its tiles and the fraction -> world
    affine map (wx = wx0 + fx * wx_dx + fy * wx_dy, wy likewise)."""
    return {
        "uiMapId": layer.ui_map_id,
        "artId": layer.art_id,
        "layerWidth": layer.layer_width,
        "layerHeight": layer.layer_height,
        "tileWidth": layer.tile_width,
        "tileHeight": layer.tile_height,
        "tiles": [list(t) for t in layer.tiles],
        "wx0": transform.wx0,
        "wxDx": transform.wx_dx,
        "wxDy": transform.wx_dy,
        "wy0": transform.wy0,
        "wyDx": transform.wy_dx,
        "wyDy": transform.wy_dy,
        "exact": transform.exact,
    }


def write_art(path: Path, data: dict) -> bool:
    """Deterministic, atomic (files.write_text); True when the file changed."""
    return write_text(path, json.dumps(data, indent=1, sort_keys=True) + "\n")


def continent_art(
    map_id: int,
    tables: ArtTables,
    homes: Mapping[int, int],
    transforms: Mapping[int, Transform],
    assignments: list[clientdump.Assignment] | None = None,
    continents=None,
) -> tuple[dict | None, str]:
    """The art JSON for a Map.db2 continent, or (None, why) when the map has no continent UiMap,
    that UiMap has no art, or nothing places it. `transforms` (the probe's, what the addon draws
    with) win; else the UiMap's largest assignment on the map (`clientdump.home_transform`)."""
    ui_map_id = homes.get(map_id)
    if ui_map_id is None:
        return None, "no continent UiMap at home on this map"
    layer = art_layer(tables, ui_map_id)
    if layer is None:
        return None, f"UiMap {ui_map_id} has no map art"
    transform = transforms.get(ui_map_id)
    source = "probe"
    if transform is None and assignments:
        transform = clientdump.home_transform(ui_map_id, map_id, assignments, continents)
        source = "UiMapAssignment"
    if transform is None:
        return None, f"no transform for UiMap {ui_map_id}"
    return art_json(layer, transform), f"UiMap {ui_map_id}, {len(layer.tiles)} art tiles ({source})"
