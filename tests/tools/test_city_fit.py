"""tools/city_fit.py: the walk raster is asked for on the picture's own grid, and laid over it."""

import importlib.util
from pathlib import Path

import numpy as np
import pytest

TOOL = Path(__file__).resolve().parents[2] / "tools" / "city_fit.py"
spec = importlib.util.spec_from_file_location("city_fit", TOOL)
city_fit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(city_fit)

MID = 32 * 1600 / 3


def option(cmd: list, name: str) -> str:
    return cmd[cmd.index(name) + 1]


def test_the_raster_starts_at_the_pictures_north_west_corner():
    place = {"wx": (-9154.17, -7995.83), "wy": (-14.584, 1722.92), "seed": None}
    cmd = city_fit.walk_command(Path("cd.exe"), Path("m.navmesh"), Path("w.bin"), place, 2004, 1336)
    east, south = (float(v) for v in option(cmd, "--origin").split(","))
    # the picture's left edge is the greatest wy (west), its top the greatest wx (north)
    assert east == pytest.approx(MID - 1722.92) and south == pytest.approx(MID + 7995.83)
    assert option(cmd, "--size") == "2004,1336"
    # pixels per yard: the picture's width over the place's width, and the same down
    ppy = float(option(cmd, "--ppy"))
    assert ppy == pytest.approx(2004 / 1737.504)
    assert 1336 / ppy == pytest.approx(9154.17 - 7995.83, rel=0.002)
    assert "--seed" not in cmd


def test_a_seed_goes_in_the_meshs_frame():
    place = {"wx": (0.0, 100.0), "wy": (0.0, 150.0), "seed": (10.0, 20.0, 30.0)}
    cmd = city_fit.walk_command(Path("cd.exe"), Path("m.navmesh"), Path("w.bin"), place, 300, 200)
    east, up, south = (float(v) for v in option(cmd, "--seed").split(","))
    assert (east, up, south) == pytest.approx((MID - 20.0, 30.0, MID - 10.0))


def test_the_tint_marks_what_is_walked_and_leaves_the_rest():
    picture = np.full((2, 3, 3), 100, "u1")
    walk = np.array([[0, 1, 2], [4, 8, 16]], "u1")
    out = city_fit.tinted(picture, walk)
    assert out[0, 0].tolist() == [100, 100, 100]  # nothing walked: the picture
    assert out[0, 1].tolist() == [67, 155, 78]  # ground, green over the picture
    assert out[0, 2].tolist() == [185, 185, 185]  # a road, white
    assert out[1, 1].tolist() == out[1, 2].tolist()  # shallow and deep water, one blue
