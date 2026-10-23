"""The continent parchment for the overview cells: the
art tables, the continent UiMap at home on a map, the art JSON with the transform, the file."""

import json
from pathlib import Path

import pytest

from bastians_build.mapart_art import (
    ArtError,
    art_json,
    art_layer,
    continent_art,
    read_art_tables,
    table_paths,
    write_art,
)
from bastians_build.sources import clientdump
from bastians_build.sources.probe import Transform

ROOT = Path(__file__).resolve().parents[2]
CLIENTDUMP = ROOT / "tests" / "fixtures" / "sources" / "clientdump"


def dump(path: Path, table: str, rows: list[dict]) -> None:
    path.write_text(json.dumps({"table": table, "rows": rows}), encoding="utf-8")


def write_tables(folder: Path, prefix: str = "t") -> dict[str, Path]:
    paths = table_paths(folder, prefix)
    dump(
        paths["UiMapXMapArt"],
        "UiMapXMapArt",
        [
            {"ID": 1, "PhaseID": 0, "UiMapArtID": 14, "UiMapID": 1415},
            {"ID": 2, "PhaseID": 7, "UiMapArtID": 99, "UiMapID": 1415},  # a phase: ignored
            {"ID": 3, "PhaseID": 0, "UiMapArtID": 15, "UiMapID": 1414},
        ],
    )
    dump(
        paths["UiMapArt"],
        "UiMapArt",
        [{"ID": 14, "UiMapArtStyleID": 5}, {"ID": 15, "UiMapArtStyleID": 6}],
    )
    dump(
        paths["UiMapArtStyleLayer"],
        "UiMapArtStyleLayer",
        [
            {
                "ID": 1,
                "LayerIndex": 0,
                "LayerWidth": 1002,
                "LayerHeight": 668,
                "TileWidth": 256,
                "TileHeight": 256,
                "UiMapArtStyleID": 5,
            },
            {
                "ID": 2,
                "LayerIndex": 1,
                "LayerWidth": 2004,
                "LayerHeight": 1336,
                "TileWidth": 256,
                "TileHeight": 256,
                "UiMapArtStyleID": 5,
            },
            {
                "ID": 3,
                "LayerIndex": 0,
                "LayerWidth": 0,
                "LayerHeight": 0,
                "TileWidth": 256,
                "TileHeight": 256,
                "UiMapArtStyleID": 6,
            },
        ],
    )
    dump(
        paths["UiMapArtTile"],
        "UiMapArtTile",
        [
            {
                "ID": 2,
                "RowIndex": 0,
                "ColIndex": 1,
                "LayerIndex": 0,
                "FileDataID": 2001,
                "UiMapArtID": 14,
            },
            {
                "ID": 1,
                "RowIndex": 0,
                "ColIndex": 0,
                "LayerIndex": 0,
                "FileDataID": 2000,
                "UiMapArtID": 14,
            },
            {
                "ID": 3,
                "RowIndex": 1,
                "ColIndex": 0,
                "LayerIndex": 0,
                "FileDataID": 2002,
                "UiMapArtID": 14,
            },
            {
                "ID": 4,
                "RowIndex": 0,
                "ColIndex": 0,
                "LayerIndex": 1,
                "FileDataID": 3000,
                "UiMapArtID": 14,
            },
            {
                "ID": 5,
                "RowIndex": 0,
                "ColIndex": 0,
                "LayerIndex": 0,
                "FileDataID": 0,
                "UiMapArtID": 14,
            },
            {
                "ID": 6,
                "RowIndex": 0,
                "ColIndex": 0,
                "LayerIndex": 0,
                "FileDataID": 4000,
                "UiMapArtID": 15,
            },
        ],
    )
    return paths


EK = Transform(1415, 0, 7466.6, 0, -23466.6, 16000, -35199.9, 0, True)


def test_art_tables_give_the_layer_0_art_of_a_ui_map(tmp_path):
    tables = read_art_tables(write_tables(tmp_path))
    assert tables.art_of == {1415: 14, 1414: 15}  # phase 0 only
    layer = art_layer(tables, 1415)
    assert layer is not None and (layer.layer_width, layer.layer_height) == (1002, 668)
    assert layer.tiles == ((0, 0, 2000), (0, 1, 2001), (1, 0, 2002))  # sorted, layer 0, no fdid 0
    assert art_layer(tables, 999) is None
    with pytest.raises(ArtError, match="empty layer"):
        art_layer(tables, 1414)


def test_art_json_carries_the_transform_and_the_file_is_deterministic(tmp_path):
    tables = read_art_tables(write_tables(tmp_path))
    data = art_json(art_layer(tables, 1415), EK)
    assert data["uiMapId"] == 1415 and data["tiles"] == [[0, 0, 2000], [0, 1, 2001], [1, 0, 2002]]
    assert (data["wx0"], data["wxDy"], data["wy0"], data["wyDx"]) == (
        7466.6,
        -23466.6,
        16000,
        -35199.9,
    )
    assert data["exact"] is True
    path = tmp_path / "Azeroth_art.json"
    assert write_art(path, data) is True
    assert write_art(path, data) is False  # unchanged
    assert json.loads(path.read_text(encoding="utf-8")) == data
    assert path.read_text(encoding="utf-8").index('"artId"') < path.read_text(
        encoding="utf-8"
    ).index('"tiles"')


def test_continent_homes_and_continent_art():
    maps = clientdump.read_maps(CLIENTDUMP / "Map.json")
    ui = clientdump.read_ui_maps(CLIENTDUMP / "UiMap.json")
    assign = clientdump.read_ui_map_assignments(CLIENTDUMP / "UiMapAssignment.json")
    homes = clientdump.continent_homes(assign, ui)
    assert homes[0] == 1415 and homes[1] == 1414  # the fixture's Azeroth continents
    assert set(homes) <= set(maps)


def test_continent_art_says_why_a_map_has_none(tmp_path):
    tables = read_art_tables(write_tables(tmp_path))
    homes = {0: 1415, 1: 1414, 530: 101}
    data, note = continent_art(0, tables, homes, {1415: EK})
    assert data is not None and note == "UiMap 1415, 3 art tiles (probe)"
    assert continent_art(0, tables, homes, {}) == (None, "no transform for UiMap 1415")
    # without a probe transform the UiMap's largest assignment on its home map places the art
    assign = clientdump.read_ui_map_assignments(CLIENTDUMP / "UiMapAssignment.json")
    data, note = continent_art(0, tables, homes, {}, assign, {0, 1})
    assert data is not None and note == "UiMap 1415, 3 art tiles (UiMapAssignment)"
    placed = clientdump.home_transform(1415, 0, assign, {0, 1})
    assert placed is not None and data["wx0"] == placed.wx0 and data["wyDx"] == placed.wy_dx
    assert clientdump.home_transform(1415, 530, assign, {0, 1}) is None
    assert continent_art(530, tables, homes, {}) == (None, "UiMap 101 has no map art")
    assert continent_art(571, tables, homes, {}) == (None, "no continent UiMap at home on this map")
