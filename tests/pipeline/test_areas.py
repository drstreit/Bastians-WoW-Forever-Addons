"""Areas (data.md "Areas: the subzones as places"): the navmesh area block, the centres and radii,
the `area` records and their wiring into a build (written into tmp dirs only)."""

import dataclasses
import json
import math
import struct
import zlib
from pathlib import Path

import pytest

from bastians_build.areas import (
    CHUNK,
    AreasError,
    add_areas,
    area_place,
    chunk_centre,
    read_area_block,
    read_navmesh_dir,
)
from bastians_build.canon import build_world
from bastians_build.config import load_config
from bastians_build.load import SourcePaths, load_sources
from bastians_build.model import World
from bastians_build.pack import pack_table
from bastians_build.sources.clientdump import AreaRow
from bastians_build.sources.probe import Transform


def navmesh_bytes(map_id: int, tiles: dict[tuple[int, int], dict[int, int]], version=2) -> bytes:
    """A navmesh file as tools/clientdump/Navmesh.cs writes it, without Recast tiles: per ADT
    tile (x, y) the chunk index (cy * 16 + cx) -> AreaTable id."""
    build = b"1.60.1.test"
    head = b"BNAV" + struct.pack("<Ii", version, map_id) + bytes([len(build)]) + build
    head += struct.pack("<7f2i", 0.53, 0.27, 1.6, 0.53, 1.6, 55.0, 1.6, 4, 250)  # settings
    head += struct.pack("<5f2i", 0, 0, 0, 133.3, 133.3, 65536, 65536)  # Detour parameters
    head += struct.pack("<i", 0)  # no Recast tile blocks
    if version < 2:
        return head
    raw = b""
    for (x, y), ids in tiles.items():
        raw += struct.pack("<ii", x, y)
        raw += struct.pack("<256I", *(ids.get(i, 0) for i in range(256)))
    block = zlib.compress(raw)
    offset = len(head) + 12
    return head + struct.pack("<iii", len(tiles), offset, len(block)) + block


def chunk(cx: int, cy: int) -> int:
    return cy * 16 + cx


# three ADT tiles of Elwynn Forest: (32, 49), (33, 49), (32, 50)
LAKE = 18
RING = 87
SMALL = 9
TILES = {
    # Crystal Lake: a 2 x 2 block of chunks in the tile's corner
    (32, 49): {chunk(0, 0): LAKE, chunk(1, 0): LAKE, chunk(0, 1): LAKE, chunk(1, 1): LAKE},
    # the ring: the border of a 5 x 5 square, its hollow middle carries no id
    (33, 49): {
        chunk(cx, cy): RING for cx in range(5) for cy in range(5) if cx in (0, 4) or cy in (0, 4)
    },
    # one chunk alone, and a chunk of the zone itself (Elwynn Forest, area 12)
    (32, 50): {chunk(8, 8): SMALL, chunk(9, 9): 12},
}


@pytest.fixture
def navmesh(tmp_path: Path) -> Path:
    path = tmp_path / "Azeroth.navmesh"
    path.write_bytes(navmesh_bytes(0, TILES))
    return path


def test_chunk_centres_follow_the_world_frame():
    # tile (32, 32), chunk (0, 0) lies half a chunk off the world origin: north-west of it
    wx, wy = chunk_centre(32, 32, 0, 0)
    assert wx == pytest.approx(-CHUNK / 2) and wy == pytest.approx(-CHUNK / 2)
    # x grows west (wy falls), y grows south (wx falls)
    assert chunk_centre(33, 32, 0, 0)[1] < wy and chunk_centre(32, 33, 0, 0)[0] < wx


def test_the_area_block_gives_every_chunk_of_an_area(navmesh: Path):
    block = read_area_block(navmesh)
    assert block.map_id == 0 and block.version == 2 and block.build == "1.60.1.test"
    assert len(block.chunks[LAKE]) == 4
    assert len(block.chunks[RING]) == 16
    assert len(block.chunks[SMALL]) == 1 and len(block.chunks[12]) == 1
    assert block.chunks[LAKE][0] == chunk_centre(32, 49, 0, 0)
    # inside Elwynn Forest (wx -10254..-7940, wy -1935..1535)
    wx, wy = block.chunks[LAKE][0]
    assert -10254 < wx < -7940 and -1935 < wy < 1535


def test_centre_is_a_chunk_of_the_area_and_the_radius_covers_its_chunks(navmesh: Path):
    block = read_area_block(navmesh)
    lake = area_place(block.chunks[LAKE])
    # the four chunks are equally near their mean: the tie goes to the lowest wx, then wy
    want = min(block.chunks[LAKE])
    assert (lake.wx, lake.wy) == (round(want[0], 1), round(want[1], 1))
    assert lake.chunks == 4
    assert lake.r == round(CHUNK * math.sqrt(4 / math.pi), 1)  # a disc as large as 4 chunks
    ring = area_place(block.chunks[RING])
    # the mean lies in the hollow middle (chunk 2, 2), which is no chunk of the ring
    hollow = chunk_centre(33, 49, 2, 2)
    assert (ring.wx, ring.wy) != (round(hollow[0], 1), round(hollow[1], 1))
    assert (ring.wx, ring.wy) in {(round(x, 1), round(y, 1)) for x, y in block.chunks[RING]}
    assert math.dist((ring.wx, ring.wy), hollow) == pytest.approx(2 * CHUNK, abs=0.1)
    assert ring.r == round(CHUNK * math.sqrt(16 / math.pi), 1)
    small = area_place(block.chunks[SMALL])
    assert small.r == round(CHUNK, 1)  # never below one chunk
    assert (small.wx, small.wy) == tuple(round(v, 1) for v in chunk_centre(32, 50, 8, 8))


def test_a_version_1_navmesh_has_no_area_block_and_junk_is_refused(tmp_path: Path):
    old = tmp_path / "old.navmesh"
    old.write_bytes(navmesh_bytes(1, {}, version=1))
    block = read_area_block(old)
    assert block.version == 1 and block.chunks == {} and block.map_id == 1
    junk = tmp_path / "junk.navmesh"
    junk.write_bytes(b"NOPE" + bytes(40))
    with pytest.raises(AreasError, match="not a navmesh"):
        read_area_block(junk)
    cut = tmp_path / "cut.navmesh"
    cut.write_bytes(navmesh_bytes(0, TILES)[:-10])
    with pytest.raises(AreasError, match="cut short"):
        read_area_block(cut)


# Elwynn Forest (uiMap 1429) as the transform table would give it: map fractions -> world yards
ELWYNN = Transform(1429, 0, -7939.6, 0.0, -2314.6, 1535.4, -3470.8, 0.0, True)
TABLE = {
    12: AreaRow(12, "Elwynn Forest", 0, 0),
    LAKE: AreaRow(LAKE, "Crystal Lake", 12, 0),
    RING: AreaRow(RING, "Goldshire", 12, 0),
    SMALL: AreaRow(SMALL, "Northshire Valley", 6170, 0),
    6170: AreaRow(6170, "Northshire", 12, 0),
}


def test_areas_become_records_with_their_zone_and_map_place(navmesh: Path):
    world = World(client="forever")
    world.area_to_map = {12: 1429}
    added = add_areas(world, [read_area_block(navmesh)], TABLE, {1429: ELWYNN})
    assert added == 3 and world.count("area") == 3
    lake = world.get("area", LAKE)
    assert lake["name"] == "Crystal Lake" and lake["zone"] == 1429 and lake["continent"] == 0
    assert lake["src"] == "client" and lake["chunks"] == 4 and lake["r"] > CHUNK
    (spawn,) = lake["spawns"]
    assert spawn[0] == 1429 and spawn[3] == "client" and 0 <= spawn[1] <= 1 and 0 <= spawn[2] <= 1
    # Northshire Valley's parent is a subzone: the chain leads up to Elwynn Forest
    assert world.get("area", SMALL)["zone"] == 1429
    assert world.get("area", 12) is None  # a zone stays a zone
    (note,) = [n for n in world.notes if n.startswith("areas:")]
    assert "3 from the navmesh area blocks of maps [0]" in note and "1 zones" in note


def test_without_area_to_map_the_assignment_or_the_rectangle_gives_the_zone(navmesh: Path):
    block = read_area_block(navmesh)
    world = World(client="retail")
    add_areas(world, [block], TABLE, {37: dataclasses.replace(ELWYNN, ui_map_id=37)}, {12: [37]})
    assert world.get("area", LAKE)["zone"] == 37
    world = World(client="retail")
    add_areas(world, [block], TABLE, {1429: ELWYNN})  # no table: the containing rectangle
    assert world.get("area", LAKE)["zone"] == 1429
    world = World(client="retail")
    add_areas(world, [block], TABLE, {})  # no transforms: no zone, no map place, never guessed
    lake = world.get("area", LAKE)
    assert lake["zone"] is None and "spawns" not in lake and lake["wx"] < 0
    assert any("3 without a zone" in n and "3 without a map place" in n for n in world.notes)


def area_table_json(rows: dict[int, AreaRow]) -> str:
    return json.dumps(
        {
            "table": "AreaTable",
            "build": "1.60.1.test",
            "rows": [
                {"ID": r.id, "AreaName_lang": r.name, "ParentAreaID": r.parent, "ContinentID": 0}
                for r in rows.values()
            ],
        }
    )


def test_a_build_reads_the_navmesh_folder_and_reports_the_areas(tmp_path: Path):
    dumps = tmp_path / "out"
    (dumps / "navmesh_forever").mkdir(parents=True)
    (dumps / "navmesh_forever" / "Azeroth.navmesh").write_bytes(navmesh_bytes(0, TILES))
    (dumps / "beta_AreaTable.json").write_bytes(area_table_json(TABLE).encode("utf-8"))
    s = load_sources("forever", SourcePaths(dumps=dumps))
    assert len(read_navmesh_dir(dumps / "navmesh_forever")) == 1
    assert any(n.startswith("clientdump navmesh area blocks") for n in s.source_names)
    world = build_world(s)
    assert world.count("area") == 3
    assert any(n.startswith("areas: 3 from the navmesh") for n in world.notes)
    pack = pack_table(world, load_config().packs["world"])
    assert pack["names"]["area"][LAKE] == "Crystal Lake"
    assert set(pack["area"]) == {LAKE, RING, SMALL}


def test_a_build_without_navmesh_has_no_areas_and_says_so(tmp_path: Path):
    dumps = tmp_path / "out"
    dumps.mkdir()
    (dumps / "beta_AreaTable.json").write_bytes(area_table_json(TABLE).encode("utf-8"))
    world = build_world(load_sources("forever", SourcePaths(dumps=dumps)))
    assert world.count("area") == 0
    assert any(n.startswith("areas: no navmesh files in") for n in world.notes)
