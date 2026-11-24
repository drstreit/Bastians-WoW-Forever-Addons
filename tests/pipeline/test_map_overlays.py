"""The maps' overlays (R4.5 of plan-book-round4.md, W7): every explorable area's overlay of a map
from the client's tables, on the zone's record, so Bastian's Book draws a zone whole."""

import json
from pathlib import Path

from bastians_build.canon import Sources, merge_zones
from bastians_build.load import SourcePaths, load_sources
from bastians_build.model import World
from bastians_build.sources import clientdump


def dump(folder: Path, table: str, rows: list[dict], prefix: str = "f1") -> None:
    path = folder / f"{prefix}_{table}.json"
    path.write_text(json.dumps({"table": table, "rows": rows}), encoding="utf-8")


def overlay(id_: int, art: int, x: int, y: int, w: int, h: int, condition: int = 0) -> dict:
    return {
        "ID": id_,
        "UiMapArtID": art,
        "OffsetX": x,
        "OffsetY": y,
        "TextureWidth": w,
        "TextureHeight": h,
        "PlayerConditionID": condition,
    }


def tile(overlay_id: int, row: int, col: int, file: int, layer: int = 0) -> dict:
    return {
        "WorldMapOverlayID": overlay_id,
        "RowIndex": row,
        "ColIndex": col,
        "LayerIndex": layer,
        "FileDataID": file,
    }


def tables(folder: Path) -> None:
    dump(
        folder,
        "UiMapXMapArt",
        [
            {"UiMapID": 1420, "UiMapArtID": 2126, "PhaseID": 0},
            {"UiMapID": 1420, "UiMapArtID": 9999, "PhaseID": 7},  # a phase: never the map's art
            {"UiMapID": 1429, "UiMapArtID": 2200, "PhaseID": 0},
            {"UiMapID": 1436, "UiMapArtID": 2300, "PhaseID": 0},  # a map without any overlay
        ],
    )
    dump(
        folder,
        "WorldMapOverlay",
        [
            overlay(12, 2126, 584, 139, 256, 288),  # two tiles, one under the other
            overlay(11, 2126, 335, 139, 256, 256),
            overlay(13, 2126, 10, 10, 300, 200),  # two tiles side by side, one file missing
            overlay(14, 2126, 20, 20, 128, 128, condition=77),  # a phase the reader may not be in
            overlay(15, 2126, 30, 30, 0, 128),  # no size
            overlay(20, 2200, 5, 6, 100, 100),
            overlay(30, 9999, 1, 1, 64, 64),  # the phased art's
        ],
    )
    dump(
        folder,
        "WorldMapOverlayTile",
        [
            tile(12, 1, 0, 7958236),
            tile(12, 0, 0, 7958235),
            tile(11, 0, 0, 7958233),
            tile(11, 0, 0, 111, layer=1),  # another layer: left out
            tile(13, 0, 0, 500),
            tile(14, 0, 0, 600),
            tile(20, 0, 0, 700),
            tile(30, 0, 0, 800),
        ],
    )


def test_the_overlays_of_a_map_are_read_from_the_clients_tables(tmp_path: Path):
    tables(tmp_path)
    got = clientdump.read_map_overlays(tmp_path, "f1")
    # by the map, the overlays by their id, the files row by row
    assert got == {
        1420: [[335, 139, 256, 256, 7958233], [584, 139, 256, 288, 7958235, 7958236]],
        1429: [[5, 6, 100, 100, 700]],
    }
    assert 1436 not in got  # no overlay: no entry, never an empty list
    # the same tables twice give the same answer (deterministic builds)
    assert clientdump.read_map_overlays(tmp_path, "f1") == got


def test_a_zones_record_carries_its_overlays(tmp_path: Path):
    world = World(client="forever")
    s = Sources(client="forever")
    s.map_names = {1420: "Tirisfal Glades", 1436: "Westfall"}
    s.map_overlays = {1420: [[335, 139, 256, 256, 7958233]]}
    merge_zones(world, s)
    assert world.get("zone", 1420)["overlays"] == [[335, 139, 256, 256, 7958233]]
    assert "overlays" not in world.get("zone", 1436)  # unknown stays absent
    # the record holds a copy: the sources stay what the reader gave
    world.get("zone", 1420)["overlays"][0][0] = 0
    assert s.map_overlays[1420][0][0] == 335


def test_the_build_reads_them_with_the_maps_tables(tmp_path: Path):
    tables(tmp_path)
    dump(
        tmp_path,
        "UiMap",
        [{"ID": 1420, "Name_lang": "Tirisfal Glades", "Type": 3, "ParentUiMapID": 0}],
    )
    dump(tmp_path, "UiMapAssignment", [])
    s = load_sources("forever", SourcePaths(dumps=tmp_path, dump_prefix="f1"))
    assert s.map_overlays[1420][0] == [335, 139, 256, 256, 7958233]
    assert "clientdump WorldMapOverlay (f1)" in s.source_names
    # without the overlay tables the build goes on and the zones have none
    (tmp_path / "f1_WorldMapOverlay.json").unlink()
    s = load_sources("forever", SourcePaths(dumps=tmp_path, dump_prefix="f1"))
    assert s.map_overlays == {}
