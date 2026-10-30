"""Our places table (ADR 0026, data.md "Our authored tables"): instance entrances, validated and
added to the world pack with their world place and, for drawing, a map place; the teleports a
character may have (R26.7, route.md "Home and every way back")."""

from pathlib import Path

import pytest

from bastians_build.model import World
from bastians_build.places import PlacesError, add_entrances, add_teleports, read_places
from bastians_build.sources.probe import Transform

ROOT = Path(__file__).resolve().parents[2]

GOOD = """
[[entrance]]
id = "36-1"
instance = 36
name = "Deadmines"
place = [0, -11208.7, 1675.9, 24.6]
level = 10
src = "cmangos teleport 119"
verified = ""

[[entrance]]
id = "349-2"
instance = 349
name = "Maraudon"
label = "orange"
place = [1, -1468.2, 2614.2]
src = "cmangos teleport 3131"
"""


def write(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "places_forever.toml"
    path.write_text(text, encoding="utf-8")
    return path


def test_entrances_are_read_and_become_world_records(tmp_path):
    rows = read_places(write(tmp_path, GOOD))["entrance"]
    assert [r["id"] for r in rows] == ["36-1", "349-2"]
    world = World(client="forever", build="test")
    # a transform that holds the Deadmines place but not Maraudon's
    t = Transform(
        ui_map_id=1436,
        continent=0,
        wx0=-10000.0,
        wx_dx=0.0,
        wx_dy=-3000.0,
        wy0=3000.0,
        wy_dx=-3000.0,
        wy_dy=0.0,
        exact=True,
    )
    notes = add_entrances(world, rows, {1436: t})
    dm = world.get("entrance", "36-1")
    assert (dm["continent"], dm["wx"], dm["wy"], dm["wz"]) == (0, -11208.7, 1675.9, 24.6)
    assert dm["instance"] == 36 and dm["level"] == 10 and dm["zone"] == 1436
    assert dm["spawns"][0][0] == 1436 and dm["spawns"][0][3:] == ["places", 24.6]
    assert dm["verified"] is None and dm["src"] == "places"  # not checked in game yet
    mara = world.get("entrance", "349-2")
    assert mara["wz"] is None and mara["level"] is None  # unknown stays None
    assert mara.get("spawns") is None and mara["label"] == "orange"
    assert notes == ["entrance 349-2 (Maraudon): no map contains the place"]


@pytest.mark.parametrize(
    ("change", "message"),
    [
        (('id = "36-1"', 'id = "36"'), "id must be '<instance>-<n>'"),
        (('id = "36-1"', 'id = "36-0"'), "id must be '<instance>-<n>'"),
        (("instance = 36", "instance = 35"), "instance must be the id's first number"),
        (('id = "349-2"', 'id = "36-1"'), "id 36-1 twice"),
        (("place = [0, -11208.7, 1675.9, 24.6]", "place = [0, -11208.7]"), "place must be"),
        (("level = 10", "level = -1"), "level must be a whole number"),
        (('src = "cmangos teleport 119"', 'src = ""'), "src is required"),
        (("level = 10", "colour = 1"), "unknown keys colour"),
    ],
)
def test_bad_rows_are_refused_with_the_reason(tmp_path, change, message):
    with pytest.raises(PlacesError, match=message):
        read_places(write(tmp_path, GOOD.replace(*change, 1)))


def test_the_shipped_tables_are_valid():
    """Both clients' tables load; every Forever entrance lies on Eastern Kingdoms or Kalimdor."""
    for client in ("forever", "retail"):
        rows = read_places(ROOT / "pipeline" / "config" / f"places_{client}.toml")["entrance"]
        assert len(rows) >= 30, client
        assert all(r["place"][0] in (0, 1) for r in rows)


TELEPORTS = """
[[teleport]]
id = "mage-undercity"
name = "Undercity"
kind = "spell"
spell = 3563
class = 8
faction = "H"
reagent = 17031
place = [0, 1773.5, 61.1, -46.3]
src = "cmangos spell_target_position 3563"
verified = ""

[[teleport]]
id = "shaman-astral-recall"
name = "Astral Recall"
kind = "spell"
spell = 556
class = 7
hearth = true
cast = 10
src = "the hearth's bind location"

[[teleport]]
id = "cloak-a"
name = "Stormwind (cloak)"
kind = "item"
item = 65360
faction = "A"
place = [0, -9003.5, 870.0]
src = "assumed"
"""


def test_teleports_are_read_and_become_world_records(tmp_path):
    rows = read_places(write(tmp_path, TELEPORTS))["teleport"]
    assert [r["id"] for r in rows] == ["mage-undercity", "shaman-astral-recall", "cloak-a"]
    world = World(client="forever", build="test")
    add_teleports(world, rows)
    uc = world.get("teleport", "mage-undercity")
    assert (uc["kind"], uc["spell"], uc["item"], uc["class"], uc["faction"]) == (
        "spell",
        3563,
        None,
        8,
        "H",
    )
    assert (uc["continent"], uc["wx"], uc["wy"], uc["wz"]) == (0, 1773.5, 61.1, -46.3)
    assert uc["reagent"] == 17031 and uc["cast"] == 10 and uc["hearth"] is None
    assert uc["verified"] is None and uc["src"] == "places"
    recall = world.get("teleport", "shaman-astral-recall")
    assert recall["hearth"] is True and recall["continent"] is None and recall["wx"] is None
    cloak = world.get("teleport", "cloak-a")
    assert (cloak["kind"], cloak["item"], cloak["spell"], cloak["wz"]) == (
        "item",
        65360,
        None,
        None,
    )


@pytest.mark.parametrize(
    ("change", "message"),
    [
        (('id = "cloak-a"', 'id = "Cloak A"'), "id must be a unique lower-case slug"),
        (('id = "cloak-a"', 'id = "mage-undercity"'), "id must be a unique lower-case slug"),
        (('kind = "item"', 'kind = "scroll"'), "kind must be one of"),
        (("item = 65360", "spell = 65360"), "a item needs its item id"),
        (("hearth = true", "hearth = 1"), "hearth is true or false"),
        (("hearth = true", "place = [0, 1.0, 2.0]\nhearth = true"), "either place or hearth"),
        (("place = [0, -9003.5, 870.0]", ""), "either place or hearth"),
        (("cast = 10", "cast = -1"), "cast must be seconds"),
        (('faction = "A"', 'faction = "Alliance"'), "faction must be A or H"),
        (("class = 8", "class = 0"), "class must be an id"),
        (('src = "assumed"', 'src = ""'), "src is required"),
        (("cast = 10", "colour = 1"), "unknown keys colour"),
    ],
)
def test_bad_teleports_are_refused_with_the_reason(tmp_path, change, message):
    with pytest.raises(PlacesError, match=message):
        read_places(write(tmp_path, TELEPORTS.replace(*change, 1)))


def test_the_shipped_teleports_are_valid():
    """Both clients' teleport rows load; every place lies on Eastern Kingdoms or Kalimdor."""
    for client in ("forever", "retail"):
        rows = read_places(ROOT / "pipeline" / "config" / f"places_{client}.toml")["teleport"]
        assert len(rows) >= 9, client
        assert all(r["place"][0] in (0, 1) for r in rows if "place" in r)
