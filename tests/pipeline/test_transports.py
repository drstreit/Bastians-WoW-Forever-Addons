"""Transport tables (route.md, B9.1): TOML per client -> `transport` records with stops and world
points."""

from pathlib import Path

import pytest

from bastians_build.config import CONFIG_DIR
from bastians_build.model import World
from bastians_build.sources.probe import Transform
from bastians_build.transports import TransportError, add_transports, read_transports, stop_world

ROOT = Path(__file__).resolve().parents[2]


def test_forever_table_is_valid_and_covers_both_continents():
    rows = read_transports(CONFIG_DIR / "transports_forever.toml")
    ids = {r["id"] for r in rows}
    assert {
        "boat-menethil-auberdine",
        "tram-stormwind-ironforge",
        "zeppelin-orgrimmar-undercity",
    } <= ids
    kinds = {r["kind"] for r in rows}
    assert kinds == {"boat", "zeppelin", "tram", "portal"}
    assert all(r["verified"] is False for r in rows)  # nothing measured on Forever yet
    assert all(len(r["stops"]) == 2 for r in rows)
    assert read_transports(CONFIG_DIR / "transports_retail.toml") == []


def write(tmp_path: Path, body: str) -> Path:
    p = tmp_path / "transports_test.toml"
    p.write_text(body, encoding="utf-8")
    return p


GOOD = """
[[transport]]
id = "boat-a-b"
kind = "boat"
name = "A - B"
faction = "both"
stops = [[1429, 0.5, 0.5, "A dock"], [1453, 0.5, 0.5, "B dock"]]
ride = 60
cycle = 240
verified = false
note = "test"
"""


@pytest.mark.parametrize(
    ("change", "message"),
    [
        ('kind = "boat"', "kind must be"),
        ('faction = "both"', "faction must be"),
        ("ride = 60", "positive"),
        ('stops = [[1429, 0.5, 0.5, "A dock"], [1453, 0.5, 0.5, "B dock"]]', "stops needs"),
    ],
)
def test_bad_rows_are_rejected(tmp_path, change, message):
    replacement = {
        'kind = "boat"': 'kind = "rocket"',
        'faction = "both"': 'faction = "Goblins"',
        "ride = 60": "ride = 0",
        'stops = [[1429, 0.5, 0.5, "A dock"], [1453, 0.5, 0.5, "B dock"]]': (
            "stops = [[1429, 0.5, 0.5, 'A']]"
        ),
    }[change]
    with pytest.raises(TransportError, match=message):
        read_transports(write(tmp_path, GOOD.replace(change, replacement)))


def test_duplicate_ids_and_bad_stops_are_rejected(tmp_path):
    with pytest.raises(TransportError, match="duplicate"):
        read_transports(write(tmp_path, GOOD + GOOD))
    with pytest.raises(TransportError, match="map fractions"):
        read_transports(write(tmp_path, GOOD.replace('0.5, 0.5, "A dock"', '50, 50, "A dock"')))


def test_records_get_spawns_and_world_points_from_the_transforms(tmp_path):
    path = write(tmp_path, GOOD)
    elwynn = Transform(1429, 0, 200.0, 0.0, -400.0, 200.0, -400.0, 0.0, True)
    world = World(client="forever")
    notes = add_transports(world, path, {1429: elwynn})
    rec = world.records["transport"]["boat-a-b"]
    assert rec["spawns"] == [[1429, 0.5, 0.5, "config"], [1453, 0.5, 0.5, "config"]]
    assert rec["world"] is None and notes == ["transport boat-a-b: no map transform for B dock"]
    assert rec["src"] == "assumed"
    stormwind = Transform(1453, 0, 300.0, 0.0, -200.0, 300.0, -200.0, 0.0, True)
    world = World(client="forever")
    assert add_transports(world, path, {1429: elwynn, 1453: stormwind}) == []
    assert world.records["transport"]["boat-a-b"]["world"] == [[0, 0.0, 0.0], [0, 200.0, 200.0]]
    # without a transform table the world points stay unknown and nothing is noted
    world = World(client="forever")
    assert (
        add_transports(world, path) == []
        and world.records["transport"]["boat-a-b"]["world"] is None
    )


def test_the_forever_tram_entrances_lie_where_the_exit_triggers_put_a_player():
    """(P1): the route led 570 yards north out of Stormwind to the
    Deeprun Tram. The entrances are the CMaNGOS exit triggers 2171 (Stormwind) and 2166
    (Ironforge) through Forever's transforms (probe 70532); both stops lie within 10 yards."""
    from bastians_build.sources import probe

    root = Path(__file__).resolve().parents[2]
    path = root / "data" / "probe" / "2026-10-23-forever-70532.lua"
    if not path.is_file():
        pytest.skip("the probe dumps are private (data/ stays on the owner's machine)")
    dump = probe.read_probe_dump(path)
    transforms = probe.transform_table(dump)
    rows = {
        r["id"]: r
        for r in read_transports(root / "pipeline" / "config" / "transports_forever.toml")
    }
    tram = rows["tram-stormwind-ironforge"]
    triggers = {1453: (-8354.23, 524.068), 1455: (-4839.51, -1317.74)}
    for stop in tram["stops"]:
        world = stop_world(transforms, stop)
        wx, wy = triggers[stop[0]]
        assert ((world[1] - wx) ** 2 + (world[2] - wy) ** 2) ** 0.5 < 10, stop
