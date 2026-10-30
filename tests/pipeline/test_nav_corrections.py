"""The correction table of the world graph's network (corrections.py, data.md "Our authored
tables"): lifts, links and forbidden ground applied to the navnet-mini local level, orphaned stops
joined, and the table's validation."""

from pathlib import Path

import pytest

from bastians_build.corrections import apply_corrections, read_corrections
from bastians_build.navnet import RUN_SPEED, NavnetError, Waypoint, build_network, read_local

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "navnet-mini" / "0.json"


def table(tmp_path: Path, text: str):
    path = tmp_path / "nav_corrections_test.toml"
    path.write_bytes(text.encode("utf-8"))
    return read_corrections(path)


LIFT = """
[[lift]]
name = "hill-lift"
continent = 0
top = [300.0, 150.0, 30.0]
bottom = [100.0, 150.0, 12.0]
ride = 10
cycle = 20
verified = false
"""


def test_a_missing_table_changes_nothing(tmp_path):
    level = read_local(FIXTURE)
    ways = len(level.ways)
    assert apply_corrections(level, read_corrections(tmp_path / "none.toml")) == []
    assert len(level.ways) == ways


def test_a_lift_joins_its_ends_by_height_and_is_timed_by_its_ride_and_wait(tmp_path):
    level = read_local(FIXTURE)
    report = apply_corrections(level, table(tmp_path, LIFT))
    assert report == ["lift hill-lift: 18 yards, 20 s with the wait"]
    new = level.waypoints[-2:]
    assert [(w.id, w.kind, w.z) for w in new] == [(7, "door", 30.0), (8, "door", 12.0)]
    lift = [w for w in level.ways if {w.a, w.b} == {7, 8}]
    assert len(lift) == 2 and all(w.oneway for w in lift)
    up = next(w for w in lift if w.a == 8)
    assert up.facts["len"] == 20 * RUN_SPEED and up.facts["indoor"] == up.facts["len"]
    assert up.facts["up"] == 18 and up.facts["down"] == 0
    # the ends sit on waypoints 4 and 2: no join way needed; the network builds with them
    net = build_network(level)
    assert len(net.order) == 8


def test_a_link_follows_its_points_and_a_block_removes_the_ways_it_covers(tmp_path):
    level = read_local(FIXTURE)
    rows = table(
        tmp_path,
        """
[[link]]
name = "lake-ramp"
kind = "ramp"
continent = 0
a = [100.0, 300.0, 10.0]
b = [100.0, 50.0, 12.0]
points = [[150.0, 175.0, 20.0]]
oneway = true
verified = false

[[block]]
name = "hill-gate"
continent = 0
center = [300.0, 150.0]
r = 10
""",
    )
    report = apply_corrections(level, rows)
    assert report[0] == "block hill-gate: 2 ways removed"
    assert report[1].startswith("link lake-ramp: ramp, ")
    link = level.ways[-1]
    assert link.oneway and link.points == [(150.0, 175.0, 20.0)]
    assert link.facts["up"] == 10 and link.facts["down"] == 8 and link.facts["indoor"] == 0
    assert all(4 not in (w.a, w.b) for w in level.ways)  # the hill is cut off


def test_a_stop_the_mesh_left_alone_joins_its_nearest_connected_waypoint(tmp_path):
    level = read_local(FIXTURE)
    level.waypoints.append(Waypoint(7, 100.0, -320.0, 5.0, "node", "transport:boat:1", 88))
    level.waypoints.append(Waypoint(8, 900.0, 900.0, 5.0, "node", "transport:boat:2", None))
    report = apply_corrections(level, read_corrections(tmp_path / "none.toml"))
    assert report == [
        "orphan transport:boat:1: joined by 20 yards",
        "orphan transport:boat:2: no connected waypoint within 40 yards",
    ]
    joined = level.ways[-1]
    assert (joined.a, joined.b, joined.facts["len"]) == (6, 7, 20.0)


@pytest.mark.parametrize(
    ("text", "message"),
    [
        (LIFT + LIFT, "name missing or twice"),
        (LIFT.replace("top = [300.0, 150.0, 30.0]", "top = [300.0, 150.0, 1.0]"), "higher"),
        (LIFT.replace("ride = 10", "ride = 0"), "seconds must be"),
        (LIFT.replace("[300.0, 150.0, 30.0]", "[300.0, 150.0]"), "a point must be"),
        (
            '[[link]]\nname = "x"\nkind = "lift"\ncontinent = 0\na = [0, 0, 0]\nb = [1, 1, 1]',
            "kind",
        ),
    ],
)
def test_the_table_is_validated(tmp_path, text, message):
    with pytest.raises(NavnetError, match=message):
        table(tmp_path, text)


def test_an_end_far_from_the_network_fails_the_build(tmp_path):
    level = read_local(FIXTURE)
    rows = table(tmp_path, LIFT.replace("[300.0, 150.0, 30.0]", "[5000.0, 5000.0, 30.0]"))
    with pytest.raises(NavnetError, match="no waypoint with ways within 100 yards"):
        apply_corrections(level, rows)


def test_the_shipped_tables_read():
    config = Path(__file__).resolve().parents[2] / "pipeline" / "config"
    for client, lifts in (("forever", 7), ("retail", 5)):
        rows = read_corrections(config / f"nav_corrections_{client}.toml")
        assert len(rows.lifts) == lifts
        assert all(lift.verified is False for lift in rows.lifts)  # not timed in game yet
