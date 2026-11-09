"""tools/nav_build.py without a client: the client check, the road textures from the listfile, the
liquids that block, and the continents from the Map dump."""

import importlib.util
import json
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[2] / "tools" / "nav_build.py"
spec = importlib.util.spec_from_file_location("nav_build", TOOL)
nav_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nav_build)


def test_a_folder_of_the_other_client_is_refused():
    forever = "product=wowf version=1.60.1.70532 buildKey=x root=D:\\WoW"
    retail = "product=wow version=12.1.5.70575 buildKey=y root=D:\\WoW"
    assert nav_build.check_client("forever", forever) == "1.60.1.70532"
    assert nav_build.check_client("retail", retail) == "12.1.5.70575"
    # 25.10.2026: the old beta folder lost its .flavor.info and opened retail
    with pytest.raises(nav_build.NavBuildError, match="not a forever client"):
        nav_build.check_client("forever", retail)
    with pytest.raises(nav_build.NavBuildError):
        nav_build.check_client("retail", "no version line")


def test_road_textures_are_the_used_ones_whose_file_name_says_road(tmp_path):
    used = tmp_path / "textures.tsv"
    used.write_text("187100\t556\n187127\t6991\n999\t1\n", encoding="utf-8")
    listfile = tmp_path / "listfile.csv"
    listfile.write_text(
        "187100;tileset/elwynn/elwynncobblestonebase_s.blp\n"
        "187127;tileset/elwynn/elwynngrassbase_s.blp\n"
        "5;tileset/road/notused_s.blp\n"  # a road texture the map does not use
        "999;tileset/roadside/grass_s.blp\n",  # "road" only in the folder: not a road
        encoding="utf-8",
    )
    roads = nav_build.road_textures(used, listfile, ["cobble", "road"])
    assert roads == ["187100\ttileset/elwynn/elwynncobblestonebase_s.blp"]


def test_liquids_by_name_and_continents_from_the_map_dump(tmp_path, monkeypatch):
    liquid = tmp_path / "LiquidType.json"
    liquid.write_text(
        json.dumps(
            {
                "rows": {
                    "1": {"Name": "Water"},
                    "2": {"Name": "Ocean"},
                    "3": {"Name": "Magma"},
                    "15": {"Name": "Green Lava"},
                    "4": {"Name": "Slime"},
                }
            }
        ),
        encoding="utf-8",
    )
    blocked, ocean = nav_build.liquids(liquid, ["magma", "lava", "slime"], ["ocean"])
    assert blocked == [3, 4, 15] and ocean == [2]
    monkeypatch.setattr(nav_build, "OUT", tmp_path)
    (tmp_path / "x_Map.json").write_text(
        json.dumps({"rows": {"0": {"Directory": "Azeroth", "WdtFileDataID": 775971}}}),
        encoding="utf-8",
    )
    assert nav_build.continent_maps("retail", "x") == {0: ("Azeroth", 775971)}
    with pytest.raises(nav_build.NavBuildError, match="missing"):
        nav_build.continent_maps("retail", "none")


def test_only_a_client_with_hidden_ground_gets_a_config(tmp_path):
    """Forever's sheet of terrain under Stormwind (route.md "The join"): the boxes reach clientdump
    navnet in its own field names; a client without any builds as before."""
    box = {
        "name": "sheet",
        "continent": 0,
        "wx": [-10.0, 10.0],
        "wy": [0.0, 5.0],
        "z": [40.0, 88.0],
    }
    target = tmp_path / "config.json"
    assert nav_build.navnet_config({"hidden": {"forever": [box]}}, "retail", target) == []
    assert not target.exists()
    args = nav_build.navnet_config({"hidden": {"forever": [box]}}, "forever", target)
    assert args == ["--config", str(target)]
    written = json.loads(target.read_text(encoding="utf-8"))
    assert written == {"hidden": [{k: box[k] for k in ("continent", "wx", "wy", "z")}]}


def test_the_stormwind_boxes_leave_the_harbour_ramp():
    """The ramp from the harbour up to the streets runs through wx -8578 to -8474, wy 986 to 1077,
    heights 37 to 79: the only link between the two, it must stay."""
    conf = nav_build.tomllib.loads((nav_build.CONFIG / "nav.toml").read_text(encoding="utf-8"))
    for wx, wy, z in ((-8578, 1077, 37), (-8501, 1004, 61), (-8474, 986, 79)):
        for box in conf["hidden"]["forever"]:
            inside = (
                box["wx"][0] <= wx <= box["wx"][1]
                and box["wy"][0] <= wy <= box["wy"][1]
                and box["z"][0] <= z <= box["z"][1]
            )
            assert not inside, (wx, wy, z, box["name"])
