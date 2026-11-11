"""ForeverDB's API rows in the build (sources/foreverdb_api.py, canon.merge_fdb_api; data.md
"ForeverDB's API fills gaps"): only what players saw, only where nothing else has a value."""

import json
from pathlib import Path

import pytest

from bastians_build.canon import Sources, merge_fdb_api
from bastians_build.model import World
from bastians_build.sources import foreverdb_api as api

SEEN = "seen in WoW Forever"
CLASSIC = "Classic data (CMaNGOS)"


def end(kind: str, source_id: int, place: tuple | None, source: str = SEEN) -> dict:
    location = None
    if place:
        location = {"uiMapId": place[0], "x": place[1], "y": place[2], "source": source}
    return {"type": kind, "id": source_id, "location": location, "source": source}


QUESTS = [
    {
        "id": 2,
        "starts": end("item", 16305, None, CLASSIC),
        "ends": end("npc", 12696, (1440, 73.8, 61.5)),
    },
    {
        "id": 5,
        "starts": end("npc", 261, (1429, 48.2, 42.9)),
        "ends": end("object", 31, (1429, 10, 20)),
    },
    {"id": 7, "starts": end("npc", 300, (1429, 30.0, 30.0), CLASSIC), "ends": None},
    {"id": 8, "starts": end("npc", 301, (1429, 130.0, 30.0)), "ends": end("npc", 302, (0, 1, 1))},
    {"id": "x"},
    "not a row",
]  # fmt: skip
VENDORS = [
    {"id": 54, "name": "Corina Steele", "title": "Weaponsmith", "side": "Alliance",
     "mapId": 1429, "x": 41.6, "y": 65.8, "seenInForever": True},
    {"id": 55, "name": "Old Hand", "side": "Horde", "mapId": 1411, "x": 1, "y": 2,
     "seenInForever": False},
    {"id": 56, "name": "No Place", "side": "Alliance", "mapId": 1429, "x": None, "y": 2,
     "seenInForever": True},
]  # fmt: skip


def test_only_places_players_saw_are_read():
    places = api.parse_quests(QUESTS)
    assert places == [
        api.QuestPlace(2, "end", "npc", 12696, 1440, 73.8, 61.5),
        api.QuestPlace(5, "end", "object", 31, 1429, 10.0, 20.0),
        api.QuestPlace(5, "start", "npc", 261, 1429, 48.2, 42.9),
    ]  # no item giver, no Classic place, no point off the map, no map 0
    assert api.parse_vendors(VENDORS) == [
        api.Vendor(54, "Corina Steele", "Weaponsmith", "A", 1429, 41.6, 65.8)
    ]
    assert api.parse_quests({"data": []}) == [] and api.parse_vendors(None) == []


def test_the_folder_is_read_and_a_missing_file_is_a_note(tmp_path: Path):
    (tmp_path / "quests.json").write_text(json.dumps(QUESTS), encoding="utf-8")
    (tmp_path / "meta.json").write_text('{"build": "1.60.1.70862"}', encoding="utf-8")
    rows = api.read_api(tmp_path)
    assert len(rows.quest_places) == 3 and rows.vendors == [] and rows.build == "1.60.1.70862"
    assert rows.notes == [f"ForeverDB API: no vendors.json in {tmp_path}"]
    (tmp_path / "vendors.json").write_text("{half", encoding="utf-8")
    with pytest.raises(ValueError):
        api.read_api(tmp_path)  # a half-written hand-over is an error, not "no rows"


def world() -> World:
    w = World(client="forever")
    w.add("quest", 2, {"name": "Sharptalon's Claw", "endPlaces": [[1440, 0.1, 0.1, "eq"]]})
    w.add("quest", 5, {"name": "Open", "starts": ["npc:999"]})
    w.add("npc", 261, {"name": "Guard Thomas"})
    w.add("npc", 12696, {"name": "Senani", "spawns": [[1440, 0.7, 0.6, "classic"]]})
    w.add("object", 31, {"name": "Old Lion Statue"})
    w.add("npc", 54, {"name": "Corina Steele", "flags": ["vendor"]})
    return w


def test_the_api_fills_gaps_and_changes_nothing_that_has_a_value():
    w = world()
    s = Sources(client="forever")
    s.fdb_api = api.ApiRows(
        quest_places=[
            *api.parse_quests(QUESTS),
            api.QuestPlace(404, "start", "npc", 1, 1429, 1.0, 1.0),  # no such quest
        ],
        vendors=[
            *api.parse_vendors(VENDORS),
            api.Vendor(900, "Mira Newstall", "Trade Goods", "A", 1453, 50.0, 50.0),
            api.Vendor(901, "Mar\u00eda Nueva", None, "H", 1454, 50.0, 50.0),  # localized: out
            api.Vendor(902, None, None, None, 1454, 50.0, 50.0),  # no name: left out
        ],
        build="1.60.1.70862",
    )
    merge_fdb_api(w, s)
    q2, q5 = w.get("quest", 2), w.get("quest", 5)
    assert q2["endPlaces"] == [[1440, 0.1, 0.1, "eq"]]  # named already: kept
    assert q2["ends"] == ["npc:12696"]  # the taker was unknown: named
    assert q5["startPlaces"] == [[1429, 0.482, 0.429, "fdb"]]
    assert q5["endPlaces"] == [[1429, 0.1, 0.2, "fdb"]]
    assert q5["starts"] == ["npc:999"] and q5["ends"] == ["object:31"]
    assert w.get("npc", 261)["spawns"] == [[1429, 0.482, 0.429, "fdb"]]  # a giver without a place
    assert w.get("npc", 12696)["spawns"] == [[1440, 0.7, 0.6, "classic"]]  # had one: kept
    assert w.get("object", 31)["spawns"] == [[1429, 0.1, 0.2, "fdb"]]
    assert w.get("npc", 54)["spawns"] == [[1429, 0.416, 0.658, "fdb"]]
    assert w.get("npc", 900) == {
        "name": "Mira Newstall",
        "subname": "Trade Goods",
        "faction": "A",
        "flags": ["vendor"],
        "spawns": [[1453, 0.5, 0.5, "fdb"]],
        "src": "forever",
    }
    assert w.get("npc", 901) is None and w.get("npc", 902) is None and w.get("quest", 404) is None
    assert w.notes == [
        "ForeverDB API (build 1.60.1.70862): 4 seen quest places and 4 seen vendors read; "
        "filled 1 quest starts, 1 hand-ins, 2 givers' places, 1 vendors' places, "
        "1 vendors no other source had"
    ]


def test_without_the_api_rows_nothing_changes():
    w = world()
    before = json.dumps(w.records, sort_keys=True)
    merge_fdb_api(w, Sources(client="forever"))
    assert json.dumps(w.records, sort_keys=True) == before and w.notes == []
