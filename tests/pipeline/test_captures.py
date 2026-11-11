"""Captured walks (world-graph.md §9, W11): tools/capture_import.py turns a client's saved
variables into a capture of positions and times without names; corrections.captured_links turns
the walks two or more captures agree on into links, whose heights come from the waypoints they
join; a lone walk stays out."""

import importlib.util
import json
import sys
from pathlib import Path

from bastians_build.corrections import (
    Corrections,
    apply_corrections,
    captured_links,
    captured_ride_waits,
    captured_taxi_times,
)
from bastians_build.navnet import TaxiRow, build_network, graph_record, read_local

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "navnet-mini" / "0.json"
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location(
    "capture_import", ROOT / "tools" / "capture_import.py"
)
capture_import = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture_import)

SAVED = """
BastiansDataDB = {
  ["profileKeys"] = { ["Bastian - Realm"] = "Default" },
  ["global"] = {
    ["learned"] = {
      ["taxi"] = { ["taxinode:2>taxinode:4"] = 95 },
      ["ride"] = { ["transport:boat-1"] = { 30, 42 } },
      ["walk"] = {
        { ["map"] = 0, ["len"] = 250.3, ["at"] = 1760000000,
          ["points"] = { { 100.04, 300 }, { 150, 175.55 }, { 100, 50 } } },
        { ["map"] = 0, ["points"] = { { 1, 2 } } },
      },
      ["steps"] = {
        ["1861:1"] = { { 1429, 0.2857, 0.6139 }, { 1453, 0.5, 1 } },
        ["176:2"] = { { 1429, 0.4, 0.7 } },
      },
    },
  },
}
"""


def walk(*points, map_id: int = 0) -> dict:
    return {"map": map_id, "len": 250.0, "points": [list(p) for p in points]}


def write(folder: Path, name: str, walks: list[dict], **more) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    cap = {"client": "forever", "walk": walks, **more}
    (folder / name).write_text(json.dumps(cap), encoding="utf-8")


def test_the_capture_holds_positions_and_times_without_names(tmp_path: Path):
    sv = tmp_path / "WTF" / "Account" / "WOWACCOUNT1" / "SavedVariables" / "Bastians_Data.lua"
    sv.parent.mkdir(parents=True)
    sv.write_text(SAVED, encoding="utf-8")
    learned = capture_import.read_learned(sv)
    cap = capture_import.capture(learned, "forever", "2026-10-26T10:00:00Z")
    assert cap["taxi"] == {"taxinode:2>taxinode:4": 95}
    assert cap["ride"] == {"transport:boat-1": [30, 42]}
    assert cap["walk"] == [
        {
            "map": 0,
            "len": 250.3,
            "at": 1760000000,
            "points": [[100.0, 300.0], [150.0, 175.6], [100.0, 50.0]],
        }
    ]  # the one-point walk is dropped
    assert cap["steps"] == {  # where a quest step's count rose (package QK1)
        "176:2": [[1429, 0.4, 0.7]],
        "1861:1": [[1429, 0.2857, 0.6139], [1453, 0.5, 1.0]],
    }
    tag = capture_import.account_hash(sv)
    assert len(tag) == 8 and "NEMO" not in tag
    target, changed = capture_import.write_capture(cap, tmp_path / "captures", tag)
    assert changed and target.name == f"2026-10-26-{tag}.json"
    assert "WOWACCOUNT1" not in target.read_text(encoding="utf-8")
    assert capture_import.write_capture(cap, tmp_path / "captures", tag)[1] is False  # the same


def test_walks_two_captures_agree_on_become_links_with_the_ends_heights(tmp_path: Path):
    folder = tmp_path / "forever"
    # the same stretch of the lake ramp from two accounts (the ends within a 30-yard cell), one
    # walked back the other way; a third walk nobody else took
    write(folder, "2026-10-25-aaaaaaaa.json", [walk((100, 300), (150, 175), (100, 50))])
    write(
        folder,
        "2026-10-26-bbbbbbbb.json",
        [walk((100, 50), (140, 180), (102, 298)), walk((300, 150), (600, 600))],
    )
    links = captured_links(folder, agree=2)
    assert [(link.name, link.kind, link.verified) for link in links] == [
        ("captured-0-1", "path", "2 captures")
    ]
    link = links[0]
    assert link.a[:2] == (100.0, 300.0) and link.b[:2] == (100.0, 50.0) and link.a[2] is None
    assert link.points == [(150.0, 175.0, None)]
    assert captured_links(folder, agree=3) == []
    assert captured_links(tmp_path / "none") == []
    # applied like a hand-written link: the ends take the heights of the waypoints they join, the
    # point between them lies on the line between those heights
    level = read_local(FIXTURE)
    table = Corrections()
    table.links.extend(links)
    report = apply_corrections(level, table)
    assert report == ["link captured-0-1: path, 254 yards"] or report[0].startswith(
        "link captured-0-1: path, "
    )
    way = level.ways[-1]
    a = next(w for w in level.waypoints if w.id == way.a)
    b = next(w for w in level.waypoints if w.id == way.b)
    assert way.points[0][2] == round((a.z + b.z) / 2, 1)
    assert way.facts["indoor"] == 0 and not way.oneway


def test_flight_times_the_captures_agree_on_go_into_the_pack(tmp_path: Path):
    """The median over `agree` captures per pair becomes the flight's fourth field; a pair one
    capture timed, a time of zero and a foreign key stay out; ride waits are summarised only."""
    folder = tmp_path / "forever"
    write(
        folder,
        "2026-10-25-aaaaaaaa.json",
        [],
        taxi={"taxinode:2>taxinode:6": 101, "taxinode:6>taxinode:2": 97, "flight:1": 5},
        ride={"transport:boat-1": [30, 42]},
    )
    write(
        folder,
        "2026-10-26-bbbbbbbb.json",
        [],
        taxi={"taxinode:2>taxinode:6": 95.4, "taxinode:9>taxinode:2": 0},
        ride={"transport:boat-1": [200], "transport:zep-2": [10]},
    )
    write(folder, "2026-10-27-cccccccc.json", [], taxi={"taxinode:2>taxinode:6": 120})
    assert captured_taxi_times(folder, agree=2) == {(2, 6): 101}
    assert captured_taxi_times(folder, agree=1) == {(2, 6): 101, (6, 2): 97}
    assert captured_taxi_times(tmp_path / "none") == {}
    assert captured_ride_waits(folder) == {
        "transport:boat-1": (42, 3, 2),
        "transport:zep-2": (10, 1, 1),
    }
    level = read_local(FIXTURE)
    level.waypoints[5].key = "taxinode:6"
    paths = [TaxiRow(12, 2, 6, 0, 597.0), TaxiRow(13, 6, 2, 0, 597.0)]
    rec = graph_record(build_network(level), paths, None, captured_taxi_times(folder))
    assert rec["taxi"] == "2,6,597,101;6,2,597"
    assert graph_record(build_network(level), paths)["taxi"] == "2,6,597;6,2,597"
