"""tools/city_look.py and tools/mapstyle/city.py (map.md "City plans", ADR 0065): the plan grid and
the walk raster's call are Stormwind's to the digit (its tiles are rebuilt byte for byte only
then), the registry's looks are whole, the world pack's records are read without Lua, a model of
a few groups gives its houses by both room rules, and a small canyon gives its floor, its hut,
its gate tunnel, its pond and its rock."""

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("PIL")

import city_look  # noqa: E402
from mapstyle import city  # noqa: E402
from mapstyle import draw as D  # noqa: E402
from mapstyle.scene import ORIGIN  # noqa: E402

PLACES = city_look.sheet_tool().PLACES
STORMWIND, ORGRIMMAR = PLACES[1453], PLACES[1454]


def test_stormwinds_plan_grid_is_the_prototypes():
    grid = city.grid_of(*city_look.area_of(STORMWIND))
    assert grid == city.Grid(47 * 1024 + 30, 29 * 1024 + 340, 2070, 2140)
    assert grid.tiles() == (29, 47, 31, 49)


def test_a_place_without_an_area_takes_its_whole_region():
    wx, wy = city_look.area_of(ORGRIMMAR)
    assert (wx, wy) == (ORGRIMMAR["wx"], ORGRIMMAR["wy"])
    grid = city.grid_of(wx, wy)
    assert (grid.width, grid.height) == (2693, 1796)


def test_a_plan_pixel_and_its_world_point():
    grid = city.Grid(100, 200, 50, 60)
    col, row = grid.pix(ORIGIN - 100.5 * city.YPP, ORIGIN - 200.5 * city.YPP)
    assert (round(col, 6), round(row, 6)) == (0, 0)  # the middle of the first pixel


def test_the_walk_raster_is_asked_for_as_the_prototype_did(tmp_path):
    grid = city.grid_of(*city_look.area_of(STORMWIND))
    cmd = city_look.walk_command(tmp_path / "x.exe", tmp_path / "m", tmp_path / "w", grid, None)
    at = cmd.index("--origin")
    assert cmd[at + 1] == "15643.7500,25082.2917"  # four decimals: another raster otherwise
    assert cmd[cmd.index("--size") + 1] == "2140,2070"
    assert float(cmd[cmd.index("--ppy") + 1]) == pytest.approx(1.92)
    assert "--seed" not in cmd
    seeded = city_look.walk_command(tmp_path / "x", tmp_path / "m", tmp_path / "w", grid, (1, 2, 3))
    east, up, south = (float(v) for v in seeded[seeded.index("--seed") + 1].split(","))
    assert (east, up, south) == (ORIGIN - 2, 3, ORIGIN - 1)


def test_stormwinds_sheet_has_the_prototypes_yards_a_pixel():
    frame = city.Frame(STORMWIND["wx"], STORMWIND["wy"], 4008, 2672)
    assert frame.ypp == 0.433
    grid = city.grid_of(*city_look.area_of(STORMWIND))
    a = frame.affine(grid)
    assert a[0, 2] == pytest.approx(692.6, abs=0.1)  # the plan's west edge on the sheet
    assert a[0, 0] == pytest.approx(city.YPP / (1737.504 / 4008), rel=1e-4)
    x, y = frame.of_world(STORMWIND["wx"][1], STORMWIND["wy"][1])
    assert (x, y) == (0, 0)  # the Region's north-west corner


def test_every_painted_place_of_the_registry_is_whole():
    painted = {ui: p["painted"] for ui, p in PLACES.items() if p["painted"]}
    assert 1453 in painted and 1454 in painted
    for ui, look in painted.items():
        assert city_look.look_problems(look, 4008, 2672) == [], ui
    assert PLACES[1453]["look"] == "painted"


def test_a_broken_look_is_named():
    look = {"kind": "island", "rooms": "tents", "district": [{"name": "A", "at": [1], "roof": []}]}
    look["banner"] = [10, 10, 5000, 20]
    look["water_fade"] = [["up", 1, 2]]
    problems = " | ".join(city_look.look_problems(look, 4008, 2672))
    for word in ("kind", "rooms", "streets", "district A", "box", "water_fade"):
        assert word in problems


ANN = (
    '{ "Ann \\"the Bold\\"", "Banker", 5, nil, 1454, { "banker" }, "H", '
    '{ { 1429, 0.1, 0.2, "fdb" }, { 1454, 0.25, 0.5, "classic", 12.5 }, '
    '{ 1454, 0.75, 0.5, "eq" } }, nil }'
)
BOB = (
    '{ "Bob", nil, 5, nil, 1429, nil, "H", { { 1429, 0.1, 0.2, "fdb" } }, nil, '
    '{ { 1454, "Life Tap" } } }'
)
WORLD = f"""
    npc = {{
      [7] = [=[{ANN}]=],
      [8] = [=[{BOB}]=],
    }},
    object = {{
"""


def test_the_world_packs_npcs_are_read_without_lua():
    npcs = city.npcs_of(WORLD, 1454, (1000.0, 2000.0), (-500.0, 500.0))
    assert [n["id"] for n in npcs] == [7]  # Bob only teaches spell 1454
    ann = npcs[0]
    assert ann["name"] == 'Ann "the Bold"' and ann["flags"] == ["banker"]
    assert ann["src"] == "eq"  # a measured place before a Classic one
    assert (ann["wx"], ann["wy"]) == (1500.0, -250.0)
    assert city.lua_value('{ 1, -2.5, "a", nil, true, { } }') == [1, -2.5, "a", None, True, []]
    with pytest.raises(ValueError):
        city.lua_value("{ x = 1 }")


def box(x0, x1, y0, y1, z0, z1):
    """The vertices and triangles of a floor at z0 and, when z1 is given, a ceiling at z1."""

    def quad(z):
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]

    v = quad(z0) + (quad(z1) if z1 is not None else [])
    t = [(0, 1, 2), (0, 2, 3)] + ([(4, 5, 6), (4, 6, 7)] if z1 is not None else [])
    return np.array(v, "f4"), np.array(t, "i4")


def tiny_model():
    """A street, a room with a ceiling joined by a portal to a floor without one (a hut's upper
    storey, whose ceiling is the next group's), and a door from the room to the street."""
    groups = [
        {"i": 0, "id": 100, "flags": city.INDOOR | city.LIT, "portals": [[0, 1, 0]]},
        {"i": 1, "id": 101, "flags": city.INDOOR, "portals": [[0, 0, 0], [1, 2, 0]]},
        {"i": 2, "id": 102, "flags": city.INDOOR, "portals": [[1, 1, 0]]},
    ]
    mesh = {
        0: box(0, 60, 0, 60, 0, None),
        1: box(20, 30, 20, 30, 0, 6),
        2: box(22, 28, 22, 28, 6, None),
    }
    portals = [[[20, 25, 0], [20, 25, 4], [20, 26, 4], [20, 26, 0]], [[25, 25, 6]] * 4]
    return {"groups": groups, "portals": portals}, mesh


def test_a_room_by_its_ceiling_or_by_the_clients_light():
    placement, mesh = tiny_model()
    # the grid's north-west corner is the world's (64, 64): wx and wy fall to the south and east
    grid = city.Grid(round((ORIGIN - 64) / city.YPP), round((ORIGIN - 64) / city.YPP), 130, 130)
    names = {100: "The Drag", 101: "The Drag", 102: "The Drag"}
    banker = {"id": 7, "name": "Ann", "sub": None, "flags": ["banker"], "wx": 25.0, "wy": 25.0}
    shell, labels, info = city.houses(placement, mesh, names, grid, {"The Drag"}, [banker])
    assert list(info) == [0] and info[0]["groups"] == [101]  # the storey has no ceiling of its own
    assert len(info[0]["doors"]) == 2 and info[0]["residents"][0]["useful"]
    assert info[0]["area"] == pytest.approx(100, rel=0.25)  # a drawn outline is a pixel wider
    col, row = grid.pix(25.0, 25.0)
    assert labels[round(row), round(col)] == 0 and shell[round(row), round(col)]
    _, _, lit = city.houses(placement, mesh, names, grid, {"The Drag"}, [], "indoor")
    assert list(lit) == [0] and lit[0]["groups"] == [101, 102]  # both storeys are one house
    assert len(lit[0]["doors"]) == 1 and lit[0]["zmax"] == 6


def test_the_parts_of_a_mask_are_draws():
    rng = np.random.default_rng(1)
    mask = rng.random((40, 50)) > 0.55
    assert np.array_equal(city.components(mask), D.components(mask))
    boxes = sorted((b[0].start, b[1].start, int(p.sum())) for b, p in city._parts(mask))
    assert sum(n for _, _, n in boxes) == int(mask.sum())


def canyon():
    """300 x 160 pixels: a floor at 10 yards inside a rim at 60, a hut, a corridor with doors 30
    yards apart, a pond on the floor and a river outside the model."""
    h, w = 160, 300
    walk = np.zeros((h, w), "u1")
    walk[30:130, 30:170] = 4
    zh = np.where(walk > 0, 10.0, np.nan).astype("f4")
    building = np.full((h, w), np.nan, "f4")
    building[10:150, 10:190] = 60
    building[30:130, 30:170] = 10
    building[70:90, 90:110] = 22  # the hut's roof
    water = np.zeros((h, w), bool)
    water[100:115, 50:70] = True
    water[:, 290:300] = True
    labels = np.full((h, w), -1, "i4")
    labels[70:90, 90:110] = 0
    labels[30:40, 30:100] = 1
    room = {"names": ["The Drag"], "residents": [], "zmax": 20.0}
    info = {0: {**room, "doors": [[0, 0, 0]]}, 1: {**room, "doors": [[0, 0, 0], [30, 0, 0]]}}
    p = {"walk": walk, "zh": zh, "zl": zh, "paved": ~np.isnan(building), "building": building}
    return {**p, "water": water}, labels, info


def test_a_canyon_gives_floor_hut_tunnel_pond_and_rock():
    p, labels, info = canyon()
    none = np.zeros(labels.shape, bool)
    drawn, status, m = city.canyon_masks(p, labels, info, {"The Drag"}, none, none)
    assert status == {0: "house", 1: "passage"}
    assert drawn[80, 100] == 0 and m["house"][80, 100] and not m["road"][80, 100]
    assert m["road"][60, 60] and m["gate"][35, 60] and m["road"][35, 60]
    assert m["water"][105, 60] and not m["water"][80, 295]  # the pond, not the river
    assert not m["road"][105, 60]
    assert m["cliff"][20, 100] and m["rock"][20, 100] == 50  # the rim, 50 yards above the floor
    assert not m["cliff"][60, 60] and not m["green"].any() and not m["cave"].any()


def test_a_cave_district_lies_in_shadow_and_roofs_nothing():
    p, labels, info = canyon()
    cave = np.zeros(labels.shape, bool)
    cave[60:130, 80:170] = True
    p["building"][60:130, 80:170] = 40  # rock over that part of the floor
    _, status, m = city.canyon_masks(p, labels, info, {"The Drag"}, cave & False, cave)
    assert status[0] == "underground" and not m["house"].any()
    assert m["cave"][100, 120] and not m["cave"][60, 60]


def test_a_landmark_with_far_doors_keeps_its_roof():
    p, labels, info = canyon()
    info[1]["names"] = ["The Ring of Valor"]
    none = np.zeros(labels.shape, bool)
    _, status, _ = city.canyon_masks(p, labels, info, {"The Drag"}, none, none)
    assert status[1] == "house"
