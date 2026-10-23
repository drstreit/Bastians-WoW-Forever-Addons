"""Coordinate conversions: map percent -> fractions, world yards -> the smallest containing map."""

import pytest

from bastians_build.coords import (
    best_map,
    named_map,
    pct_to_fraction,
    place_world_point,
    world_to_map,
)
from bastians_build.sources.probe import Transform

# Elwynn: x south -2314.59 over the map's y axis, y east -3470.84 over the map's x axis
ELWYNN = Transform(1429, 0, -7939.58, 0.0, -2314.59, 1535.42, -3470.84, 0.0, True)
STORMWIND = Transform(1453, 0, -8000.0, 0.0, -1000.0, 2000.0, -1500.0, 0.0, True)
TABLE = {1429: ELWYNN, 1453: STORMWIND}


def test_percent_to_fraction_keeps_the_source():
    s = pct_to_fraction(1429, 41.6, 65.8, "fdb")
    assert s.row() == [1429, 0.416, 0.658, "fdb"]


def test_world_to_map_inverts_the_transform():
    x, y = 0.25, 0.5
    wx = ELWYNN.wx0 + x * ELWYNN.wx_dx + y * ELWYNN.wx_dy
    wy = ELWYNN.wy0 + x * ELWYNN.wy_dx + y * ELWYNN.wy_dy
    back = world_to_map(ELWYNN, wx, wy)
    assert back == (pytest.approx(0.25), pytest.approx(0.5))
    degenerate = Transform(1, 0, 0, 0, 0, 0, 0, 0, True)
    assert world_to_map(degenerate, 1, 1) is None


def test_named_map_takes_the_place_then_the_zone_when_that_map_contains_the_point():
    """ "Tarren Mill, Hillsbrad" lies deep in the Alterac rectangle; the name decides. A capital
    ("Stormwind, Elwynn") lands on its city map because the place is tried before the zone."""
    hillsbrad = Transform(1424, 0, 0.0, 0.0, -1000.0, 1000.0, -1000.0, 0.0, True)
    alterac = Transform(1416, 0, 500.0, 0.0, -1000.0, 1000.0, -1000.0, 0.0, True)
    names = {
        1424: "Hillsbrad Foothills",
        1416: "Alterac Mountains",
        1429: "Elwynn Forest",
        1453: "Stormwind City",
    }
    table = {1424: hillsbrad, 1416: alterac, **TABLE}
    wx, wy = -150.0, 500.0  # y 0.15 in Hillsbrad (its northern edge), y 0.65 in Alterac
    assert best_map(table, 0, wx, wy)[0] == 1416
    hit = named_map(table, names, 0, wx, wy, ["Tarren Mill", " Hillsbrad"])
    assert hit is not None and hit[0] == 1424
    assert hit[1] == pytest.approx(0.5) and hit[2] == pytest.approx(0.15)
    # the place name wins over the zone name when its map contains the point
    assert named_map(table, names, 0, -8500, 1000, ["Stormwind", "Elwynn"])[0] == 1453
    assert named_map(table, names, 0, -8500, 1000, ["Goldshire", "Elwynn"])[0] == 1429
    # a named map that does not contain the point does not count; no name, no hit
    assert named_map(table, names, 0, wx, wy, ["Elwynn"]) is None
    assert named_map(table, names, 1, wx, wy, ["Hillsbrad"]) is None  # other continent
    assert named_map(table, {}, 0, wx, wy, ["Hillsbrad"]) is None
    assert named_map(table, names, 0, wx, wy, ["Hills", ""]) is None  # whole words only


def test_best_map_prefers_the_smallest_containing_map():
    # (-8500, 1000) lies inside both rectangles: it is central in Stormwind, at Elwynn's edge
    hit = best_map(TABLE, 0, -8500, 1000)
    assert hit[0] == 1453
    assert hit[1:] == (pytest.approx(2 / 3), pytest.approx(0.5))
    # deep in Elwynn, outside Stormwind
    assert best_map(TABLE, 0, -10000, -1500)[0] == 1429
    assert best_map(TABLE, 0, 5000, 5000) is None  # outside every map
    assert best_map(TABLE, 1, -8500, 1000) is None  # other continent
    # a point at the edge of a small map but central in a large one belongs to the large one
    large = Transform(10, 0, 1000.0, 0.0, -1000.0, 1000.0, -1000.0, 0.0, True)
    small = Transform(11, 0, 800.0, 0.0, -500.0, 750.0, -500.0, 0.0, True)
    assert best_map({10: large, 11: small}, 0, 500, 740)[0] == 10
    assert best_map({10: large, 11: small}, 0, 550, 500)[0] == 11  # central in both: smaller
    # a continent-sized map never beats a zone that contains the point
    continent = Transform(12, 0, 20000.0, 0.0, -40000.0, 20000.0, -40000.0, 0.0, True)
    assert best_map({10: large, 11: small, 12: continent}, 0, 500, 740)[0] == 10
    assert best_map({12: continent}, 0, 500, 740)[0] == 12


def test_place_world_point_uses_the_cmangos_map_as_continent():
    spawn = place_world_point(TABLE, 0, -10000, -1500, "classic")
    assert spawn.ui_map_id == 1429 and spawn.src == "classic"
    assert 0 <= spawn.x <= 1 and 0 <= spawn.y <= 1
    assert place_world_point(TABLE, 1, -10000, -1500, "classic") is None
    assert place_world_point(TABLE, 530, 0, 0, "classic") is None  # Outland: no continent mapping
