"""Our authored quest places (ADR 0070 decision 5, data.md "Our authored table", package QD5):
what a person checked or read about where a quest's step is done wins over every source, says
whether it was checked in game, and stays in the build report until it was."""

from pathlib import Path

import pytest

from bastians_build import steps
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.model import World
from bastians_build.quest_places import QuestPlacesError, add_quest_places, read_quest_places

ROOT = Path(__file__).resolve().parents[2]
ELWYNN, WESTFALL = 1429, 1436

GOOD = """
[[place]]
quest = 1861
n = 1
ref = "object:174794"
map = 1429
x = 28.57
y = 61.39
src = "walked there"
verified = "11.11.2026, 1.60.1.70888, the count rose here"

[[place]]
quest = 1861
n = 1
map = 1429
x = 30
y = 60.5
src = "the quest's text"

[[place]]
quest = 76
map = 1429
x = 61.9
y = 53.2
src = "read in the quest's text"
verified = ""
note = "the mine's mouth"

[[place]]
quest = 4242
n = 2
map = 1436
x = 50
y = 50
src = "a quest the world does not have"
"""


def write(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "quest_places_forever.toml"
    path.write_text(text, encoding="utf-8")
    return path


def world() -> World:
    w = World(client="forever", build="test", sources=[])
    w.add("zone", ELWYNN, {"name": "Elwynn Forest"})
    w.add("npc", 1, {"name": "Kobold", "spawns": [[ELWYNN, 0.1, 0.1, "eq"]]})
    w.add("npc", 2, {"name": "Nowhere"})
    w.add("item", 7206, {"name": "Water Sample"})
    w.add(
        "quest",
        1861,
        {
            "name": "Mirror Lake",
            "level": 10,
            "zone": ELWYNN,
            "requiredItems": [[7206, 1]],
            # the client's own area and what players saw for the same objective, and a second
            "spots": {ELWYNN: [[0.9, 0.9, "area", 1], [0.8, 0.8, "area", 2]]},
            "spotsSrc": "client",
            "seenSpots": {1: [[ELWYNN, 0.7, 0.7]]},
        },
    )
    w.add(
        "quest",
        76,
        {
            "name": "The Jasperlode Mine",
            "level": 9,
            "zone": ELWYNN,
            "objectives": [["slay", "npc:1"], ["slay", "npc:2"]],
            "classicPoints": {"": [[WESTFALL, 0.5, 0.5]]},
        },
    )
    w.add("quest", 62, {"name": "The Fargodeep Mine", "objectives": [["slay", "npc:1"]]})
    return w


def rows_of(quest: dict) -> list[dict]:
    return [dict(zip(steps.ROW, row, strict=False)) for row in quest.get("steps") or ()]


def test_the_table_is_read_and_its_rows_go_onto_their_quests(tmp_path):
    rows = read_quest_places(write(tmp_path, GOOD))
    assert len(rows) == 4 and rows[0]["ref"] == "object:174794" and "n" not in rows[2]
    w = world()
    add_quest_places(w, rows)
    # map percent becomes a map fraction; a row says whether it was checked in game
    assert w.get("quest", 1861)["authored"] == [
        [1, ELWYNN, 0.2857, 0.6139, "object:174794", True],
        [1, ELWYNN, 0.3, 0.605, None, False],
    ]
    assert w.get("quest", 76)["authored"] == [[None, ELWYNN, 0.619, 0.532, None, False]]
    assert "authored" not in w.get("quest", 62)
    assert w.notes == [
        "authored quest places: 4 rows for 2 quests, 1 checked in game; "
        "1 quests are not in the world: 4242"
    ]
    quiet = world()
    add_quest_places(quiet, [])
    assert quiet.notes == []


@pytest.mark.parametrize(
    ("change", "message"),
    [
        (("quest = 1861", "quest = 0"), "quest must be a quest id"),
        (("n = 1\nref", "n = 0\nref"), "n is the objective's number in the quest log"),
        (('ref = "object:174794"', 'ref = "item:7206"'), "ref must be 'npc:<id>' or 'object:<id>'"),
        (("map = 1429\nx = 28.57", 'map = "Elwynn"\nx = 28.57'), "map must be a uiMapID"),
        (("x = 28.57", "x = 128.57"), "x must be map percent"),
        (("y = 61.39", "y = true"), "y must be map percent"),
        (('src = "walked there"\n', ""), "src is required"),
        (('note = "the mine\'s mouth"', "note = 3"), "note must be text"),
        (("x = 30\ny = 60.5", "x = 28.57\ny = 61.39"), "the same place of the same step twice"),
        (('src = "walked there"', 'src = "walked there"\nwho = "me"'), "unknown keys who"),
        (("[[place]]\nquest = 4242", "[[spot]]\nquest = 4242"), "unknown sections spot"),
    ],
)
def test_bad_rows_are_refused_with_the_reason(tmp_path, change, message):
    assert change[0] in GOOD
    with pytest.raises(QuestPlacesError, match=message):
        read_quest_places(write(tmp_path, GOOD.replace(*change)))


def test_the_shipped_tables_are_valid():
    """A file with no row is a table too: nothing in it is read or played yet."""
    for client in ("forever", "retail"):
        path = ROOT / "pipeline" / "config" / f"quest_places_{client}.toml"
        if path.is_file():
            assert isinstance(read_quest_places(path), list)
    assert (ROOT / "pipeline" / "config" / "quest_places_forever.toml").is_file()


def test_a_row_for_an_objective_wins_over_every_source(tmp_path):
    """Order 1 of the resolver. A row names an objective by its number in the game's list, as
    the client's own areas and what players saw do: its step takes that number's place and
    theirs are gone. Every row of it checked: `verified`; one not: `authored`."""
    w = world()
    add_quest_places(w, read_quest_places(write(tmp_path, GOOD)))
    report = steps.resolve(w)
    got = rows_of(w.get("quest", 1861))
    assert [(s["kind"], s["n"], s.get("src")) for s in got] == [
        ("get", None, None),  # the item itself: nobody knows who has it
        ("reach", 1, "authored"),  # one of its two rows is not checked yet
        ("reach", 2, "client"),  # the other objective keeps the client's area
    ]
    assert got[1]["places"] == {ELWYNN: [[0.2857, 0.6139, "object:174794"], [0.3, 0.605]]}
    # with every row of the step checked it says so
    checked = world()
    add_quest_places(checked, read_quest_places(write(tmp_path, GOOD))[:1])
    steps.resolve(checked)
    assert rows_of(checked.get("quest", 1861))[1]["src"] == "verified"
    assert rows_of(checked.get("quest", 1861))[1]["places"] == {
        ELWYNN: [[0.2857, 0.6139, "object:174794"]]
    }
    # the unchecked step is listed until somebody checks it; it is no Classic debt
    assert [(r.quest, r.step, r.zone, r.level) for r in report.assumed] == [
        (76, 2, "Elwynn Forest", 9),
        (1861, 2, "Elwynn Forest", 10),
    ]
    assert report.counts()["authored_unchecked"] == 2 and report.counts()["classic"] == 0
    assert report.counts()["placed_by_src"] == {"authored": 2, "client": 1, "subject": 2}


def test_a_row_for_the_quest_as_a_whole_places_what_nothing_placed(tmp_path):
    """Without `n`: the steps no source placed are done there, before the quest's Classic
    points; a quest whose steps all have a place gets a step "go there", as the row asks."""
    w = world()
    add_quest_places(w, read_quest_places(write(tmp_path, GOOD)))
    w.get("quest", 62)["authored"] = [[None, WESTFALL, 0.4, 0.4, "npc:9", True]]
    steps.resolve(w)
    mine = rows_of(w.get("quest", 76))
    assert [(s["ref"], s.get("src"), s["places"]) for s in mine] == [
        ("npc:1", None, {ELWYNN: [[0.1, 0.1]]}),  # a source places it: untouched
        ("npc:2", "authored", {ELWYNN: [[0.619, 0.532]]}),  # and not the Classic point
    ]
    assert "how" not in mine[1] or mine[1]["how"] is None  # placed: nothing unknown about it
    done = rows_of(w.get("quest", 62))
    assert [(s["kind"], s.get("ref"), s.get("src")) for s in done] == [
        ("slay", "npc:1", None),
        ("reach", None, "verified"),
    ]
    assert done[1]["places"] == {WESTFALL: [[0.4, 0.4, "npc:9"]]}


def test_the_report_lists_the_authored_places_nobody_checked(tmp_path):
    w = world()
    add_quest_places(w, read_quest_places(write(tmp_path, GOOD)))
    result = build(w, load_config(), tmp_path / "out")
    assert result.ok
    report = result.report
    assert "**Authored places to check in game** (2 steps; `quest_places_forever.toml`" in report
    assert "| 76 The Jasperlode Mine | 2 | Nowhere | Elwynn Forest | 9 |" in report
    assert "| 1861 Mirror Lake | 2 | - | Elwynn Forest | 10 |" in report
    assert "authored quest places: 4 rows for 2 quests, 1 checked in game" in report
    # the pack carries the step as any other; the table's rows themselves are the build's
    quests = next(p for p in result.packs if p.pack.name == "quests")
    text = quests.path.read_text(encoding="utf-8")
    assert (
        '{ 1, "reach", nil, nil, nil, nil, { [1429] = { { 0.2857, 0.6139, "object:174794" }' in text
    )
    assert '"authored" }' in text and "authored =" not in text
    # nothing to check: no such list
    plain = build(world(), load_config(), tmp_path / "plain")
    assert "Authored places to check" not in plain.report
