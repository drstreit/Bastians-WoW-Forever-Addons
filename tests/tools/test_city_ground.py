"""tools/city_ground.py: the city's plan from the walk raster, each tile's mask, the manifest's
`ground` (map.md "Cities inside the ground")."""

import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOOLS = Path(__file__).resolve().parents[2] / "tools"


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules.setdefault(name, module)
    spec.loader.exec_module(module)
    return module


city_ground = load("city_ground")
city_sheet = load("city_sheet")

INDOOR, GROUND, DEEP = 4, 1, 16


def walk_of(h=200, w=300):
    """Two indoor halls with a wall between them, a hall with a courtyard, a speck, ground around
    and a sunken indoor floor under deep water."""
    walk = np.full((h, w), GROUND, "u1")
    walk[40:100, 30:90] = INDOOR
    walk[40:100, 94:150] = INDOOR  # 4 pixels of wall between the two halls
    walk[120:190, 180:280] = INDOOR
    walk[140:170, 210:250] = GROUND  # the courtyard inside the third hall
    walk[10:14, 250:254] = INDOOR  # a speck
    walk[150:190, 20:120] = INDOOR | DEEP  # under the lake
    return walk


def test_the_plan_closes_walls_fills_courts_and_drops_specks():
    alpha = city_ground.footprint(walk_of(), min_area=500)
    assert alpha.dtype == np.uint8 and alpha.shape == (200, 300)
    assert alpha[70, 60] == 255 and alpha[70, 120] == 255  # both halls
    assert alpha[70, 92] == 255  # the wall between them is closed over
    assert alpha[155, 230] == 255  # the courtyard is filled
    assert alpha[12, 252] == 0  # the speck is dropped
    assert alpha[170, 70] == 0  # the floor under deep water is no plan
    assert alpha[5, 5] == 0 and alpha[110, 160] == 0  # the land around
    assert 0 < alpha[70, 30 - 4] < 255  # grown past the floor, then feathered


def test_pieces_labels_each_piece_by_its_first_pixel():
    mask = np.zeros((5, 7), bool)
    mask[0, 0:2] = True
    mask[1, 1] = True
    mask[3:5, 4:7] = True
    lab = city_ground.pieces(mask)
    assert set(np.unique(lab).tolist()) == {-1, 0, 3 * 7 + 4}
    assert lab[1, 1] == 0 and lab[4, 6] == 25 and lab[2, 2] == -1


def test_each_tile_gets_the_mask_of_its_visible_part():
    alpha = np.zeros((668, 1002), "u1")
    alpha[:, 900:] = 255  # the plan at the sheet's east edge only
    masks = city_ground.tile_masks(alpha, 4008, 2672)
    assert sorted(masks) == [(r, c) for r in range(3) for c in range(4)]
    assert masks[0, 0] is None and masks[1, 2] is None  # no plan there
    edge = masks[2, 3]
    assert edge.size == (128, 128) and edge.mode == "RGBA"
    a = np.asarray(edge)[..., 3]
    # the edge tile shows 936 of its 1024 pixels: its mask spans those alone, the plan from
    # sheet pixel 3600 (raster 900) is at (3600 - 3072) / 936 of it
    first = int(np.argmax(a[64] > 127))
    assert abs(first - round(128 * (3600 - 3072) / 936)) <= 1
    assert np.asarray(edge)[..., :3].min() == 255  # white, the alpha carries the plan


def test_a_mask_file_is_a_plain_tga_and_deterministic():
    image = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
    image.putpixel((3, 0), (255, 255, 255, 200))
    data = city_ground.tga(image)
    assert data == city_ground.tga(image) and len(data) == 18 + 128 * 128 * 4
    assert data[2] == 2 and data[16] == 32 and data[17] == 0x28  # truecolour, 32 bpp, top-left
    assert data[18 + 3 * 4 : 18 + 4 * 4] == bytes([255, 255, 255, 200])  # BGRA


def test_the_manifest_names_the_masked_tiles(tmp_path):
    addon = tmp_path / "addon"
    tiles = addon / "Generated" / "Cities"
    tiles.mkdir(parents=True)
    listed = {ui: p for ui, p in city_sheet.PLACES.items() if ui in (1453, 1458)}
    assert listed[1458]["ground"] and not listed[1453]["ground"]
    for ui in listed:
        for r in range(3):
            for c in range(4):
                (tiles / f"{ui}_{r}_{c}.blp").write_bytes(b"BLP2")
    entries = [city_sheet.entry_of(ui, p, 4008, 2672, addon) for ui, p in listed.items()]
    (addon / "Generated" / "Cities.lua").write_text(city_sheet.manifest(entries), encoding="utf-8")
    for r, c in ((1, 1), (2, 3)):
        city_sheet.ground_file(addon, 1458, r, c).write_bytes(b"x")
    city_sheet.ground_file(addon, 1453, 0, 0).write_bytes(b"x")  # not marked: not listed
    entries = city_sheet.relist(addon, listed)
    text = (addon / "Generated" / "Cities.lua").read_text(encoding="utf-8")
    assert [e.get("ground") for e in entries] == [None, [(1, 1), (2, 3)]]
    assert 'ground = { "1_1", "2_3" } },' in text and text.count("ground =") == 1


def test_a_place_no_longer_marked_loses_its_masks(tmp_path):
    tiles = tmp_path / "Generated" / "Cities"
    tiles.mkdir(parents=True)
    (tiles / "1453_0_0_ground.tga").write_bytes(b"x")
    (tiles / "1453_0_0.blp").write_bytes(b"BLP2")
    assert city_ground.remove_masks(1453, tmp_path) == 1
    assert sorted(p.name for p in tiles.iterdir()) == ["1453_0_0.blp"]


def test_the_registry_marks_the_cities_inside_the_ground():
    marked = sorted(ui for ui, p in city_sheet.PLACES.items() if p["ground"])
    assert marked == [1455, 1458]  # Ironforge and the Undercity
