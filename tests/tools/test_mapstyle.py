"""tools/mapstyle (ADR 0027): a synthetic tile in clientdump's mapdata format is read back,
joined into a region, prepared and drawn in every style; the same scene gives the same image,
water is drawn as water and a building's interior as a roof, a tree stands where its model was
placed."""

import gzip
import struct
import tomllib
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("PIL")

from mapstyle.labels import CHUNK_YARDS  # noqa: E402
from mapstyle.render import STYLES, prepare, render  # noqa: E402
from mapstyle.scene import ORIGIN, TILE_YARDS, read_region, read_tile  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
N = 32
X, Y = 31, 48
TREE = 7001
GRASS = 9001


def tile_bytes(x: int = X, y: int = Y) -> bytes:
    """A hill in the west, a lake in the south-east, a house in the middle, one tree."""
    rows, cols = np.mgrid[0:N, 0:N].astype("f4")
    ground = (40 - cols).astype("f4")
    liquid = np.zeros((N, N), "u2")
    surface = np.full((N, N), np.nan, "f4")
    lake = (rows > 22) & (cols > 22)
    liquid[lake] = 1
    surface[lake] = ground[lake] + 3
    building = np.full((N, N), np.nan, "f4")
    interior = np.full((N, N), np.nan, "f4")
    house = (rows >= 14) & (rows < 18) & (cols >= 14) & (cols < 18)
    building[house] = ground[house] + 8
    interior[house] = ground[house] + 8
    floor = np.full((N, N), np.nan, "f4")
    floor[house] = ground[house] + 1
    # a yard flagged indoor but open to the sky: no roof
    yard = (rows >= 4) & (rows < 8) & (cols >= 14) & (cols < 18)
    building[yard] = interior[yard] = floor[yard] = ground[yard] + 0.5
    indoor = np.zeros((N, N), "u1")
    obj = np.full((N, N), np.nan, "f4")
    out = b"BMDT" + struct.pack("<Iiii", 3, x, y, N)
    for arr in (ground, liquid, surface, building, indoor, interior, floor, obj):
        out += arr.tobytes()
    out += np.zeros(256, "<u4").tobytes()
    out += struct.pack("<i", 1) + struct.pack("<I", GRASS) + np.full((N, N), 255, "u1").tobytes()
    # the tree at the centre of the north-west quarter of the tile, in world yards
    rx = (x + 0.25) * TILE_YARDS
    rz = (y + 0.25) * TILE_YARDS
    wx, wy = ORIGIN - rz, ORIGIN - rx
    out += struct.pack("<i", 1) + struct.pack("<I7f", TREE, wx, wy, 30.0, 1.0, 0.0, 5.0, 15.0)
    out += struct.pack("<i", 0)
    return gzip.compress(out, mtime=0)


@pytest.fixture
def scene(tmp_path: Path):
    folder = tmp_path / "Azeroth"
    folder.mkdir()
    (folder / f"{X}_{Y}.bmd.gz").write_bytes(tile_bytes())
    cfg = tomllib.loads(
        (ROOT / "pipeline" / "config" / "mapstyle.toml").read_text(encoding="utf-8")
    )
    names = {
        TREE: "world/azeroth/elwynn/passivedoodads/trees/elwynntree01.m2",
        GRASS: "tileset/elwynn/elwynngrassbase_s.blp",
    }
    region = read_region(folder, X, Y, X, Y)
    return prepare(region, names, {1: "Water"}, cfg), cfg, folder


def test_a_tile_reads_back_as_written(scene):
    _, _, folder = scene
    t = read_tile(folder / f"{X}_{Y}.bmd.gz")
    assert (t.x, t.y, t.n) == (X, Y, N)
    assert t.ground[0, 0] == 40 and t.liquid[30, 30] == 1 and np.isnan(t.surface[0, 0])
    assert list(t.textures) == [GRASS] and int(t.doodads["fdid"][0]) == TREE and len(t.wmos) == 0


def test_the_layers_land_where_the_data_puts_them(scene):
    p, _, _ = scene
    s = p.s
    assert p.water[30 * s, 30 * s] and not p.water[2 * s, 2 * s]
    assert p.roof[16 * s, 16 * s] and not p.roof[4 * s, 4 * s]
    assert not p.roof[6 * s, 16 * s] and p.structure[6 * s, 16 * s]  # the open yard is pavement
    (tree,) = p.things["tree"]
    assert abs(tree[0] - N * s / 4) < 1.5 and abs(tree[1] - N * s / 4) < 1.5
    assert set(p.classes) == {"grass"}


def test_every_style_draws_the_same_image_twice(scene):
    p, cfg, _ = scene
    for style in STYLES:
        a, b = render(p, style, cfg), render(p, style, cfg)
        assert a.size == (N, N) and a.tobytes() == b.tobytes(), style
    water = render(p, "modern", cfg).getpixel((30, 30))
    assert water[2] > water[0] + 40  # blue over red


def test_neighbouring_cells_meet_without_a_seam_and_are_emitted(tmp_path: Path):
    """Tiles 3 and 4 of a row lie in near cells 0 and 1: drawn apart, they continue each other."""
    from mapstyle.cells import build, read_rgba
    from mapstyle.emit import style_lua

    folder = tmp_path / "Azeroth"
    folder.mkdir()
    for x in (3, 4):
        (folder / f"{x}_0.bmd.gz").write_bytes(tile_bytes(x, 0))
    cfg = tomllib.loads(
        (ROOT / "pipeline" / "config" / "mapstyle.toml").read_text(encoding="utf-8")
    )
    names = {str(GRASS): "tileset/elwynn/elwynngrassbase_s.blp"}
    out = tmp_path / "cells"
    result = build(folder, 0, out, cfg, ["parchment"], names, {1: "Water"}, workers=1)
    assert result["near"] == [(0, 0), (1, 0)]
    a = np.asarray(read_rgba(out / "parchment" / "near" / "0_0_0.rgba")).astype(int)
    b = np.asarray(read_rgba(out / "parchment" / "near" / "0_1_0.rgba")).astype(int)
    # the last column of cell 0 and the first of cell 1 differ no more than two columns inside one
    rows = slice(0, N)  # the tiles' own rows (the rest of the cells is open sea)
    across = np.abs(a[rows, -1, :3] - b[rows, 0, :3]).mean()
    inside = np.abs(a[rows, -2, :3] - a[rows, -1, :3]).mean()
    assert across <= inside + 6
    assert len(result["far"]["parchment"]) == 1  # both near cells in far cell 0
    lua = style_lua("parchment", "forever", "test", {0: [(0, 0), (1, 0)]}, {0: [(0, 0)]})
    assert "[0] = { 0, 16 }" in lua and 'client = "forever"' in lua


def test_subzone_labels_sit_at_the_centre_of_their_largest_patch(tmp_path: Path):
    """labels.py: a subzone's name goes to the centre of its biggest connected patch of chunks;
    zones (no parent), unused areas and slivers get none. Since R27.6 (
    baked names neither scale nor hide) they are data for the Map, nothing is drawn into a cell."""
    from mapstyle.labels import Label, names_lua, place_labels

    names = {
        12: ("Elwynn Forest", 0),
        87: ("Goldshire", 12),
        9: ("Northshire UNUSED", 12),
        5: ("Sliver", 12),
        88: ('Mirror "Lake"', 12),
    }
    a = np.full((16, 16), 12, dtype=np.uint32)
    a[4:8, 4:8] = 87  # a 4 x 4 patch in tile (31, 48)
    a[0, 0] = 87  # a lone chunk far away: not the patch
    a[10, 10] = 5  # a sliver of one chunk: no name
    b = np.full((16, 16), 9, dtype=np.uint32)
    labels = place_labels({(31, 48): a, (32, 48): b}, names)
    assert [lb.text for lb in labels] == ["Goldshire"] and labels[0].chunks == 16
    # the patch's centre: chunk (6, 6) of tile (31, 48) in the raster, as world yards
    rx = (31 * 16 + 6) * CHUNK_YARDS
    rz = (48 * 16 + 6) * CHUNK_YARDS
    assert abs(labels[0].wx - (ORIGIN - rz)) < 1e-6 and abs(labels[0].wy - (ORIGIN - rx)) < 1e-6
    # the table for the Map: per continent, sorted, quotes escaped, the same text twice
    quoted = Label('Mirror "Lake"', -9000.04, 100.0, 7)
    text = names_lua("forever", "1.60.1.70630", {0: [labels[0], quoted], 1: []})
    assert text.startswith("-- GENERATED by tools/mapstyle, do not edit")
    assert '"Map.RegisterNames"' in text and 'client = "forever"' in text
    assert '{ "Mirror \\"Lake\\"", -9000, 100, 7 },' in text
    assert text.index("Goldshire") < text.index("Mirror")  # by name
    assert "[1] = {}," in text  # a continent without names
    assert names_lua("forever", "1.60.1.70630", {0: [quoted, labels[0]], 1: []}) == text


def test_the_names_file_carries_blizzards_labels_when_given():
    """every style shows Blizzard's labels (map_style.py --names --labels)."""
    from mapstyle.labels import Label, names_lua

    sub = {0: [Label("Westbrook", 300.0, -300.0, 100)], 1: []}
    named = {
        0: [
            {
                "text": "Gold\nshire",
                "wx": 1.5,
                "wy": 2.5,
                "height": 40,
                "kind": "place",
                "area": 87,
                "level": 2,
            }
        ]
    }
    plain = names_lua("forever", "1.60.1.70685", sub)
    text = names_lua("forever", "1.60.1.70685", sub, named)
    assert "labels = {" not in plain and "Blizzard's labels continent 0: 1" in text
    assert '{ "Gold\\nshire", 1.5, 2.5, 40, "place", 87, 2 },' in text
    assert text.count("continents = {") == 1
