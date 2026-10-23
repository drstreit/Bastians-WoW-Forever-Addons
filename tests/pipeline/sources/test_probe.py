"""Probe dump reader: P3 map corners -> the affine transform table for Bastians.Coords."""

import pytest

from bastians_build.sources.probe import (
    map_names,
    parse_probe_dump,
    transform_for,
    transform_table,
)

DUMP = """
BastiansProbeDB = {
  ["meta"] = { ["client"] = "forever", ["build"] = "70450", ["interface"] = 16001 },
  ["results"] = {
    ["P3"] = {
      ["found"] = 3,
      ["maps"] = {
        [1429] = {
          ["name"] = "Elwynn Forest", ["mapType"] = 3, ["parent"] = 1415,
          ["c00"] = { ["continent"] = 0, ["x"] = -7939.58, ["y"] = 1535.42 },
          ["c11"] = { ["continent"] = 0, ["x"] = -10254.17, ["y"] = -1935.42 },
          ["c10"] = { ["continent"] = 0, ["x"] = -7939.58, ["y"] = -1935.42 },
        },
        [1453] = {
          ["name"] = "Stormwind City",
          ["c00"] = { ["continent"] = 0, ["x"] = -8000, ["y"] = 2000 },
          ["c11"] = { ["continent"] = 0, ["x"] = -9000, ["y"] = 500 },
        },
        [947] = { ["name"] = "Azeroth", ["mapType"] = 1 },
      },
    },
  },
}
"""


def test_three_corners_give_an_exact_transform():
    dump = parse_probe_dump(DUMP)
    assert (dump.client, dump.build, dump.interface) == ("forever", "70450", 16001)
    table = transform_table(dump)
    t = table[1429]
    assert t.exact is True and t.continent == 0
    # (1,0) corner: x axis east -> world y decreases; y axis south -> world x decreases
    assert (t.wx_dx, t.wy_dx) == (0.0, pytest.approx(-3470.84))
    assert (t.wx_dy, t.wy_dy) == (pytest.approx(-2314.59), 0.0)
    # the row feeds Bastians.Coords: world = origin + fractions * matrix
    x, y = 0.5, 0.5
    wx = t.wx0 + x * t.wx_dx + y * t.wx_dy
    wy = t.wy0 + x * t.wy_dx + y * t.wy_dy
    assert (wx, wy) == (pytest.approx(-9096.875), pytest.approx(-200.0))
    assert t.row() == [0, t.wx0, t.wx_dx, t.wx_dy, t.wy0, t.wy_dx, t.wy_dy]


def test_two_corners_are_marked_as_assumed_orientation():
    dump = parse_probe_dump(DUMP)
    t = transform_table(dump)[1453]
    assert t.exact is False
    assert (t.wx_dx, t.wx_dy, t.wy_dx, t.wy_dy) == (0.0, -1000.0, -1500.0, 0.0)


def test_maps_without_world_positions_are_left_out():
    dump = parse_probe_dump(DUMP)
    assert 947 not in transform_table(dump)
    assert transform_for(947, dump.maps[947]) is None
    assert map_names(dump) == {947: "Azeroth", 1429: "Elwynn Forest", 1453: "Stormwind City"}


def test_dump_without_table_is_an_error():
    with pytest.raises(ValueError):
        parse_probe_dump("x = 1")
