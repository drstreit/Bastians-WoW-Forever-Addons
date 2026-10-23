"""Ground truth from a Bastians_Probe dump (B3.8): landmarks and taxi-map positions against the
transform table, taxi nodes against the flight masters, the quest log against the quests, flight
times for the report; and the data command's report section."""

from pathlib import Path

from bastians_build.__main__ import main
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.probetruth import (
    ProbeTruth,
    check_probe,
    flight_times,
    node_checks,
    point_checks,
    quest_checks,
    render_probe_section,
    target_checks,
)
from bastians_build.sources import probe
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "fixtures"
DUMP = FIXTURES / "sources" / "probe" / "2026-10-21-forever-truth.lua"


def load():
    dump = probe.read_probe_dump(DUMP)
    world = read_fixture(FIXTURES / "world-mini", "forever")
    return dump, world, probe.transform_table(dump)


def test_points_check_the_transforms_with_landmarks_and_taxi_maps():
    dump, _, transforms = load()
    points = {p.label: p for p in point_checks(dump, transforms)}
    assert points["Goldshire inn door"].status == "ok"
    assert points["Goldshire inn door"].distance_pct == 0
    assert points["Crystal Lake shore"].status == "off"
    assert 4 < points["Crystal Lake shore"].distance_pct < 5  # 100 yards south of the centre
    assert "transform 50.0, 54.3" in points["Crystal Lake shore"].note
    assert (
        points["Deadmines entrance"].status == "no transform"
        and points["Deadmines entrance"].map == 1436
    )
    assert points["inside the Deadmines"].status == "unusable"
    assert points["taxi map 1"].status == "ok" and points["taxi map 1"].map == 1453
    assert points["Marshal Dughan"].status == "ok"  # the target landmarks sit on the transform
    assert point_checks(dump, {})[0].status == "no transform"


def test_targets_check_the_pack_places_names_and_ids():
    """B4.4: a landmark with a target checks the pack's record of that id on the player's map."""
    dump, world, _ = load()
    targets = {t.label: t for t in target_checks(dump, world)}
    assert len(targets) == 7  # landmarks without a target are not listed
    assert targets["Marshal Dughan"].status == "ok" and targets["Marshal Dughan"].kind == "npc"
    assert targets["Marshal Dughan"].distance_pct < 0.3
    assert targets["Marshal Dughan"].note == "player 42.1, 65.2; pack 42.0, 65.0 (eq)"
    assert targets["Hogger far off"].status == "off" and targets["Hogger far off"].distance_pct > 30
    # a game object: the object record, else the node record of that id
    assert targets["poster"].status == "ok" and targets["poster"].kind == "object"
    assert targets["poster"].distance_pct == 0
    assert targets["renamed innkeeper"].status == "name differs"
    assert targets["renamed innkeeper"].note == "world: Innkeeper Farley"
    assert targets["Dughan seen in Westfall"].status == "no spawn on map"
    assert (
        targets["a stranger"].status == "missing record"
        and targets["a stranger"].target_id == 77777
    )
    assert targets["another player"].status == "unusable" and targets["another player"].map is None


def test_taxi_nodes_check_the_flight_masters():
    dump, world, transforms = load()
    nodes = {n.node_id: n for n in node_checks(dump, world)}  # no transforms: map spawns
    assert nodes[2].status == "ok" and nodes[2].distance_pct < 0.4
    assert nodes[4].status == "no spawn on map"
    # with transforms the node's taxi-map position is compared in world yards with the record
    nodes = {n.node_id: n for n in node_checks(dump, world, transforms=transforms)}
    assert nodes[4].status == "off" and "yards" in nodes[4].note  # the mini world is synthetic
    assert nodes[2].status == "off" and nodes[2].distance_pct > 1000
    assert nodes[6].status == "name differs" and "Ironforge, Dun Morogh" in nodes[6].note
    assert nodes[999].status == "missing node"


def test_quest_log_checks_ids_and_titles_once():
    dump, world, _ = load()
    quests = {q.quest_id: q for q in quest_checks(dump, world)}
    assert len(quests) == 3  # the header and the failed call are skipped, 176 counted once
    assert quests[176].status == "ok"
    assert quests[62].status == "name differs" and quests[62].note == "world: The Fargodeep Mine"
    assert quests[99999].status == "missing quest"


def test_flight_times_are_listed_and_the_landing_names_the_destination():
    dump, world, transforms = load()
    plain = flight_times(dump)
    assert (plain[0].to, plain[0].seconds, plain[0].from_map, plain[0].landed_map) == (
        "Sentinel Hill, Westfall",
        61.2,
        1453,
        1436,
    )
    assert plain[0].landed_at is None
    # a flight the UnitOnTaxi poller recorded: no name, but the landing position is on a known map
    flights = dump.results["P7"]["flights"]
    (flights.append if isinstance(flights, list) else lambda f: flights.__setitem__(2, f))(
        {
            "seconds": 30.0,
            "from": {"mapID": 1429},
            "landed": {
                "mapID": 1453,
                "mapX": 0.5,
                "mapY": 0.5,
                "unitPosition": {"ok": True, "ret": {1: 200.0, 2: 200.0, 3: 0, 4: 0}},
            },
            "detectedBy": "UnitOnTaxi",
        }
    )
    named = flight_times(dump, world, transforms)
    assert named[1].to == "Stormwind, Elwynn"
    assert named[1].landed_at == "Stormwind, Elwynn (0 yards)"
    text = "\n".join(render_probe_section(check_probe(dump, world, transforms)))
    assert "| Stormwind, Elwynn | 30.0 | 1429 | 1453 | Stormwind, Elwynn (0 yards) |" in text


def test_section_lists_what_is_not_ok_and_the_flights():
    dump, world, transforms = load()
    truth = check_probe(dump, world, transforms)
    lines = render_probe_section(truth)
    text = "\n".join(lines)
    assert lines[0] == "## Probe ground truth"
    assert "12 checked, 8 ok, 1 off, 2 no transform, 1 unusable" in text
    assert "4 checked, 0 ok, 2 off, 1 name differs, 0 no spawn on map, 1 missing node" in text
    assert "3 checked, 1 ok, 1 name differs, 1 missing quest" in text
    assert (
        "7 checked, 2 ok, 1 off, 1 name differs, 1 no spawn on map, 1 missing record, 1 unusable"
        in text
    )
    assert "| npc 448 Hogger | Hogger far off | 1429 | off | 36.06 |" in text
    assert "| Marshal Dughan" not in text.split("| Target |")[1].split("| Quest |")[0]
    assert "| Crystal Lake shore | 1429 | off |" in text
    assert "| Goldshire inn door" not in text
    assert "| Nowhere (999) | 1453 | missing node |" in text
    assert "| Ghost quest (99999) | missing quest |" in text
    assert "| Sentinel Hill, Westfall | 61.2 | 1453 | 1436 |" in text
    empty = render_probe_section(ProbeTruth())
    assert "holds no P2, P4 or P7" in "\n".join(empty)


def test_report_carries_the_probe_section_and_the_cli_prints_the_counts(tmp_path, capsys):
    dump, world, transforms = load()
    result = build(
        world,
        load_config(),
        tmp_path / "out",
        write=False,
        transforms=transforms,
        probe_truth=check_probe(dump, world, transforms),
    )
    assert "## Probe ground truth" in result.report
    assert (
        "## Probe ground truth"
        not in build(world, load_config(), tmp_path / "o2", write=False).report
    )
    argv = [
        "data",
        "--out",
        str(tmp_path / "addons"),
        "--client",
        "forever",
        "--fixture",
        str(FIXTURES / "world-mini"),
        "--probe",
        str(DUMP),
        "--report-dir",
        str(tmp_path / "report"),
    ]
    assert main(argv) == 0
    out = capsys.readouterr().out
    assert (
        "probe ground truth: positions 8/12 ok, taxi nodes 0/4 ok, quests 1/3 ok, targets 2/7 ok, "
        "1 flights" in out
    )
    report = (tmp_path / "report" / "report.md").read_text(encoding="utf-8")
    assert "## Probe ground truth" in report and "Crystal Lake shore" in report
