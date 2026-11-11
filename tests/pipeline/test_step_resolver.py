"""A quest's steps as the build resolves them (ADR 0069, ADR 0070; data.md "A quest's `steps`",
package QD3): a step's places come from the first source that has any, every place says what
stands there, and a step nobody can place says what is known instead."""

import copy
import json

from bastians_build import steps
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.model import World

ELWYNN, WESTFALL = 1429, 1436


def world() -> World:
    """Creatures, objects and items with what the sources know of them; the quests are added by
    each test."""
    w = World(client="forever", build="test", sources=[])
    w.add("npc", 1, {"name": "Kobold", "spawns": [[ELWYNN, 0.1, 0.1, "eq"]]})
    w.add("npc", 2, {"name": "Old Kobold", "spawns": [[ELWYNN, 0.2, 0.2, "classic"]]})
    w.add("npc", 3, {"name": "Boss inside", "dungeon": 36})
    w.add("npc", 4, {"name": "Nowhere"})
    w.add("npc", 5, {"name": "Vendor", "spawns": [[ELWYNN, 0.5, 0.5, "fdb"]], "vendor": [[30]]})
    w.add("object", 10, {"name": "Chest", "spawns": [[WESTFALL, 0.3, 0.3, "classic", 12.5]]})
    w.add("object", 11, {"name": "Waterwall", "spawns": [[ELWYNN, 0.2857, 0.6139, "classic"]]})
    w.add("item", 20, {"name": "Dropped", "drops": [["npc:1", 40.0, False], ["npc:4", 5.0]]})
    w.add("item", 21, {"name": "In a chest", "drops": [["object:10", 100.0]]})
    w.add("item", 22, {"name": "Flask"})
    w.add(
        "item",
        23,
        {
            "name": "Water sample",
            "drops": [["object:11"]],  # as QuestieDB says it
            "ways": [
                ["make", "item:22", None, "object:99"],
                ["make", "item:22", None, "object:11"],
            ],
        },
    )
    w.add("item", 24, {"name": "In a box", "ways": [["container", "item:21", 5.0]]})
    w.add("item", 25, {"name": "Hide", "ways": [["skin", "npc:2", 60.0], ["skin", "npc:1", 20.0]]})
    w.add("item", 26, {"name": "Fish", "ways": [["fish", f"zone:{ELWYNN}", 50.0]]})
    w.add("item", 27, {"name": "Crafted"})
    w.add("item", 28, {"name": "A reward"})
    w.add("item", 29, {"name": "World drop", "worldDrop": [20, 25, 80]})
    w.add("item", 30, {"name": "Sold"})
    w.add("item", 31, {"name": "Nobody knows"})
    w.add("item", 32, {"name": "From the boss", "drops": [["npc:3", 100.0]]})
    w.add("recipe", 40, {"name": "Make it", "item": 27})
    w.add("quest", 900, {"name": "Earlier", "rewards": {"items": [[28, 1]]}})
    w.add(
        "entrance",
        "36-1",
        {"name": "Deadmines", "instance": 36, "spawns": [[WESTFALL, 0.42, 0.72, "places", 24.6]]},
    )
    return w


def resolve(w: World, quest_id: int, quest: dict) -> list[dict]:
    """The quest's steps as rows by field name."""
    w.add("quest", quest_id, quest)
    steps.resolve(w)
    return [dict(zip(steps.ROW, row, strict=False)) for row in quest.get("steps") or ()]


def test_the_quests_own_points_come_first_and_keep_their_source():
    """Order 2: Everything Quests' spots of the step's kind with its bit; the bit counts within
    the kind, and a spot's fifth field names who stands there."""
    got = resolve(
        world(),
        1,
        {
            "objectives": [["slay", "npc:1", 0], ["slay", "npc:2", 0], ["slay", "npc:4", 1]],
            "spots": {
                ELWYNN: [[0.4, 0.4, "slay", 1], [0.6, 0.6, "slay", 2, "npc:4"]],
                WESTFALL: [[0.7, 0.7, "slay", 3]],
            },
            "spotsSrc": "eq",
        },
    )
    first, second = got
    # two creatures count for the first objective: one step, both named, the first its subject
    assert (first["kind"], first["ref"], first["more"], first["nth"]) == (
        "slay",
        "npc:1",
        ["npc:2"],
        1,
    )
    assert first["places"] == {ELWYNN: [[0.4, 0.4]], WESTFALL: [[0.7, 0.7]]}
    assert first["src"] == "eq" and first["n"] is None  # the client's number: only the client's
    assert (second["ref"], second["nth"], second["src"]) == ("npc:4", 2, "eq")
    assert second["places"] == {ELWYNN: [[0.6, 0.6, "npc:4"]], WESTFALL: [[0.7, 0.7]]}


def test_without_own_points_a_step_is_where_its_subject_is():
    """Order 3: the creature's or the object's own places, which keep their own source; a step
    is `classic` when every place of it is Classic knowledge."""
    got = resolve(
        world(),
        2,
        {
            "objectives": [
                ["slay", "npc:1"],
                ["slay", "npc:2"],
                ["object", "object:10"],
                ["slay", "npc:4"],
            ]
        },
    )
    assert [(s["kind"], s["ref"], s.get("src"), s.get("how")) for s in got] == [
        ("slay", "npc:1", None, None),  # a Forever place: its own source, no label
        ("slay", "npc:2", "classic", None),
        ("use", "object:10", "classic", None),
        ("slay", "npc:4", None, "unknown"),  # no place, no guess
    ]
    assert got[0]["places"] == {ELWYNN: [[0.1, 0.1]]}  # the subject stands there: no ref
    assert got[2]["places"] == {WESTFALL: [[0.3, 0.3]]}
    assert "places" not in got[3]
    # a required item no row names takes no spot of the quest: who has it places it, as the
    # addon's reader of the old fields does
    item = resolve(
        world(),
        30,
        {
            "objectives": [["slay", "npc:1"]],
            "requiredItems": [[21, 1]],
            "spots": {ELWYNN: [[0.9, 0.9, "loot", 1]]},
        },
    )
    assert item[1]["places"] == {WESTFALL: [[0.3, 0.3, "object:10"]]}
    assert item[2]["kind"] == "reach"  # the spot nothing claims stays, as one step at the end
    # spots that were made from the subjects' places are not the quest's own points
    again = resolve(
        world(),
        3,
        {
            "objectives": [["slay", "npc:2"]],
            "spots": {ELWYNN: [[0.9, 0.9, "slay", 1]]},
            "spotsSrc": "spawns",
        },
    )
    assert again[0]["places"] == {ELWYNN: [[0.2, 0.2]]} and again[0]["src"] == "classic"
    assert len(again) == 1  # and they make no step of their own


def test_an_item_is_where_it_comes_from():
    """Order 4: who drops it, the object that holds it, the container, the creature it is
    skinned from, who sells it; each place names who stands there."""
    got = resolve(
        world(),
        4,
        {
            "requiredItems": [[20, 5], [21, 1], [24, 1], [25, 3], [30, 2], [26, 1]],
        },
    )
    by_item = {s["ref"]: s for s in got}
    dropped = by_item["item:20"]
    assert (dropped["how"], dropped["via"], dropped["count"]) == ("loot", ["npc:1", "npc:4"], 5)
    assert dropped["places"] == {ELWYNN: [[0.1, 0.1, "npc:1"]]} and dropped.get("src") is None
    chest = by_item["item:21"]
    assert (chest["how"], chest["via"], chest["src"]) == ("open", ["object:10"], "classic")
    assert chest["places"] == {WESTFALL: [[0.3, 0.3, "object:10"]]}
    # two levels: the box is in a chest that has a place
    box = by_item["item:24"]
    assert (box["how"], box["via"]) == ("container", ["item:21"])
    assert box["places"] == {WESTFALL: [[0.3, 0.3, "object:10"]]}
    hide = by_item["item:25"]
    assert (hide["how"], hide["via"]) == ("skin", ["npc:2", "npc:1"])
    assert hide["places"] == {ELWYNN: [[0.2, 0.2, "npc:2"], [0.1, 0.1, "npc:1"]]}
    sold = by_item["item:30"]
    assert (sold["how"], sold["via"]) == ("buy", ["npc:5"])
    assert sold["places"] == {ELWYNN: [[0.5, 0.5, "npc:5"]]}
    # a zone is no place: fished there, said, not placed
    fish = by_item["item:26"]
    assert (fish["how"], fish["via"]) == ("fish", [f"zone:{ELWYNN}"]) and "places" not in fish


def test_mirror_lake_the_handed_flask_is_filled_at_the_waterwall():
    """The owner's report (10.11.2026): the sample is made with the item the giver hands over,
    at the object that has a place; that is said before a table's "the object drops it"."""
    got = resolve(world(), 1861, {"requiredItems": [[23, 1]], "gives": [[22, 1]]})
    assert got == [
        {
            "n": None,
            "kind": "get",
            "ref": "item:23",
            "count": 1,
            "how": "make",
            "via": ["item:22", "object:11"],  # the object with a place, not the first one named
            "places": {ELWYNN: [[0.2857, 0.6139, "object:11"]]},
            "src": "classic",
        }
    ]
    # without the handed item the table's dropper is the way
    plain = resolve(world(), 1862, {"requiredItems": [[23, 1]]})
    assert (plain[0]["how"], plain[0]["via"]) == ("open", ["object:11"])


def test_a_step_nobody_can_place_says_what_is_known():
    """Order 6: the item the giver hands over, a recipe, another quest's reward, a world drop,
    or nothing; never a guess."""
    got = resolve(
        world(),
        5,
        {
            "requiredItems": [[22, 1], [27, 1], [28, 1], [29, 1], [31, 1]],
            "gives": [[22, 1]],
            "rewards": {"items": [[31, 1]]},  # its own reward is no way to its own item
        },
    )
    assert [(s["ref"], s["how"], s.get("via")) for s in got] == [
        ("item:22", "given", None),  # a delivery: the player carries it
        ("item:27", "craft", ["recipe:40"]),
        ("item:28", "reward", ["quest:900"]),
        ("item:29", "worlddrop", None),
        ("item:31", "unknown", None),
    ]
    assert all("places" not in s for s in got)


def test_inside_an_instance_the_way_in_is_the_place():
    """A quest of a dungeon, or a boss that names his: the entrance, and `how` says so."""
    w = world()
    got = resolve(w, 6, {"objectives": [["slay", "npc:4"]], "dungeon": 36})
    assert (got[0]["how"], got[0]["places"]) == ("dungeon", {WESTFALL: [[0.42, 0.72]]})
    boss = resolve(w, 7, {"objectives": [["slay", "npc:3"]], "requiredItems": [[32, 1]]})
    assert [(s["ref"], s["how"]) for s in boss] == [("npc:3", "dungeon"), ("item:32", "dungeon")]
    assert boss[1]["via"] == ["npc:3"] and boss[1]["places"] == {WESTFALL: [[0.42, 0.72]]}
    # a dungeon without a known entrance: said, not placed
    nowhere = resolve(w, 8, {"objectives": [["slay", "npc:4"]], "dungeon": 99})
    assert nowhere[0]["how"] == "dungeon" and "places" not in nowhere[0]


def test_classic_points_serve_only_what_nothing_else_places():
    """Order 5, and "a Forever source drops the Classic points": a subject's own Classic points
    place its step when nothing else does; the quest's own serve every step left without."""
    quest = {
        "objectives": [["slay", "npc:1"], ["slay", "npc:4"], ["object", "object:12"]],
        "requiredItems": [[31, 2]],
        "classicPoints": {
            "npc:1": [[ELWYNN, 0.8, 0.8]],  # the creature has a Forever place: not used
            "npc:4": [[ELWYNN, 0.7, 0.7]],
            "": [[WESTFALL, 0.5, 0.5]],
        },
    }
    got = resolve(world(), 9, quest)
    assert [(s["ref"], s.get("src"), s["places"]) for s in got] == [
        ("npc:1", None, {ELWYNN: [[0.1, 0.1]]}),
        ("npc:4", "classic", {ELWYNN: [[0.7, 0.7]]}),
        ("object:12", "classic", {WESTFALL: [[0.5, 0.5]]}),
        ("item:31", "classic", {WESTFALL: [[0.5, 0.5]]}),
    ]
    # a quest with nothing to do but go there: one step for it
    explore = resolve(world(), 10, {"classicPoints": {"": [[ELWYNN, 0.3, 0.3]]}})
    assert explore == [
        {"n": None, "kind": "reach", "ref": None, "count": None, "how": None, "via": None}
        | {"places": {ELWYNN: [[0.3, 0.3]]}, "src": "classic"}
    ]
    # a delivery with a place of its own (an event on the way): the place is a step too
    carried = {"requiredItems": [[22, 1]], "gives": [[22, 1]], "classicPoints": {"": [[1, 0, 0]]}}
    assert [s["kind"] for s in resolve(world(), 11, carried)] == ["get", "reach"]


def test_the_clients_areas_and_what_players_saw_are_steps_by_the_clients_numbers():
    """The client's own places carry its objective numbers, which no table can join to a
    subject: a bare `reach` step with `n` beside the subjects' steps (Bastian's Quests joins
    them in the log). Where players saw an objective advance fills the numbers the client's
    areas leave out."""
    got = resolve(
        world(),
        12,
        {
            "objectives": [["slay", "npc:4"]],
            "spots": {ELWYNN: [[0.3, 0.3, "area", 1], [0.6, 0.6, "area", 5]]},
            "spotsSrc": "client",
            "seenSpots": {1: [[ELWYNN, 0.9, 0.9]], 2: [[WESTFALL, 0.2, 0.2]]},
        },
    )
    assert [(s["kind"], s["n"], s.get("ref"), s.get("src")) for s in got] == [
        ("slay", None, "npc:4", None),
        ("reach", 1, None, "client"),
        ("reach", 2, None, "fdb"),
        ("reach", 3, None, "client"),
    ]
    assert got[1]["places"] == {ELWYNN: [[0.3, 0.3], [0.6, 0.6]]}
    assert got[2]["places"] == {WESTFALL: [[0.2, 0.2]]} and got[3]["places"] == {
        ELWYNN: [[0.6, 0.6]]
    }
    # a spot nothing claims is one step at the end: nothing the sources know is lost
    rest = resolve(
        world(),
        13,
        {"objectives": [["slay", "npc:1"]], "spots": {ELWYNN: [[0.5, 0.5, "event", 0]]}},
    )
    assert [(s["kind"], s.get("src")) for s in rest] == [("slay", None), ("reach", "eq")]


def test_numbered_rows_are_the_items_of_the_quest_in_their_order():
    """Everything Quests lists the creatures that drop an item, several per objective; the item
    objectives are the required items in their order (plan-quest-links.md S9: the pipeline's
    own item rows pair by row and are not read where the source's rows are kept)."""
    quest = {
        # as `fix_loot_objectives` left them: the first two rows became the items
        "objectives": [["loot", "item:31", 0], ["loot", "item:20", 1], ["loot", "npc:1", 1]],
        "eqRows": [["loot", "npc:2", 0], ["loot", "npc:4", 0], ["loot", "npc:1", 1]],
        "requiredItems": [[31, 4], [20, 2]],
        "spots": {ELWYNN: [[0.4, 0.4, "loot", 2]]},
        "spotsSrc": "eq",
    }
    got = resolve(world(), 14, quest)
    first, second = got
    # no table knows who has item 31: the creatures the source lists for the objective do
    assert (first["ref"], first["count"], first["nth"]) == ("item:31", 4, 1)
    assert (first["how"], first["via"]) == ("loot", ["npc:2", "npc:4"])
    assert first["places"] == {ELWYNN: [[0.2, 0.2, "npc:2"]]} and first["src"] == "classic"
    # the item's own droppers are named, and the quest's own spot is the place
    assert (second["ref"], second["count"], second["nth"]) == ("item:20", 2, 2)
    assert second["via"] == ["npc:1", "npc:4"] and second["src"] == "eq"
    assert second["places"] == {ELWYNN: [[0.4, 0.4]]}
    # a loot objective beyond the required items: who has it, without an item
    more = resolve(world(), 15, {"objectives": [["loot", "npc:1", 0], ["loot", "npc:2", 0]]})
    assert more[0]["ref"] is None and more[0]["more"] == ["npc:1", "npc:2"]
    assert (more[0]["how"], more[0]["via"]) == ("loot", ["npc:1", "npc:2"])


def test_cmangos_columns_give_the_count_and_the_cast():
    """`goals`: how many of a creature, and that the handed item is cast on it; a quest no source
    lists objectives for has the columns as its steps; the handed item used at a thing no step
    names is a step of its own."""
    w = world()
    got = resolve(
        w,
        16,
        {
            "objectives": [["slay", "npc:1"], ["slay", "npc:2"]],
            "goals": [["npc:1", 10, None], ["npc:2", None, 700]],
            "castAt": [["item:22", "npc:2"]],
        },
    )
    assert [(s["kind"], s["ref"], s["count"], s.get("via")) for s in got] == [
        ("slay", "npc:1", 10, None),
        ("cast", "npc:2", None, ["item:22"]),  # no count: unknown is not 1
    ]
    bare = resolve(w, 17, {"goals": [["npc:1", 8, None], ["object:10", 1, None]]})
    assert [(s["kind"], s["ref"], s["count"]) for s in bare] == [
        ("slay", "npc:1", 8),
        ("use", "object:10", 1),
    ]
    used = resolve(w, 18, {"castAt": [["item:22", "object:11"]], "gives": [[22, 1]]})
    assert [(s["kind"], s["ref"], s["via"], s["src"]) for s in used] == [
        ("cast", "object:11", ["item:22"], "classic")
    ]
    assert used[0]["places"] == {ELWYNN: [[0.2857, 0.6139]]}


def test_a_step_keeps_eight_places_a_map_spread_over_them():
    w = world()
    spawns = [[ELWYNN, round(0.01 * i, 2), 0.5, "classic"] for i in range(40)]
    spawns += [[WESTFALL, 0.5, 0.5, "classic"]]
    w.add("npc", 50, {"name": "Everywhere", "spawns": spawns})
    got = resolve(w, 19, {"objectives": [["slay", "npc:50"]]})
    places = got[0]["places"]
    assert len(places[ELWYNN]) == steps.PLACES_PER_MAP and len(places[WESTFALL]) == 1
    xs = sorted(p[0] for p in places[ELWYNN])
    assert xs[0] == 0.0 and xs[-1] == 0.39  # the ends of the line are kept: a spread


def test_the_same_world_gives_the_same_steps_and_a_row_ends_where_its_values_do():
    w = world()
    w.add("quest", 20, {"objectives": [["slay", "npc:1"]], "requiredItems": [[20, 3]]})
    w.add("quest", 21, {"name": "Nothing to do"})
    twin = copy.deepcopy(w)
    report = steps.resolve(w)
    steps.resolve(twin)
    steps.resolve(w)  # running twice is the normal case
    assert w.records["quest"] == twin.records["quest"]
    assert w.get("quest", 20)["steps"] == [
        [None, "slay", "npc:1", None, None, None, {ELWYNN: [[0.1, 0.1]]}],
        [None, "get", "item:20", 3, "loot", ["npc:1", "npc:4"], {ELWYNN: [[0.1, 0.1, "npc:1"]]}],
    ]
    assert "steps" not in w.get("quest", 21)  # no step: the field is absent, not empty
    assert report.steps == 2 and report.quests == 3 and report.without == 2
    assert dict(report.placed) == {"": 2} and not report.unplaced
    assert report.counts()["placed_by_src"] == {"subject": 2}


def counted_world() -> World:
    """Six quests: three placed by Classic knowledge alone, one with two items nobody can place,
    one whose item the giver hands over, one placed by a Forever source."""
    w = world()
    w.add("zone", ELWYNN, {"name": "Elwynn Forest"})
    w.add("quest", 30, {"name": "Old kobolds", "level": 12, "objectives": [["slay", "npc:2"]]})
    w.add("quest", 31, {"name": "The point", "level": 5})
    w.get("quest", 31)["classicPoints"] = {"": [[WESTFALL, 0.3, 0.3]]}
    w.add("quest", 32, {"objectives": [["slay", "npc:2"]]})  # no name, no level
    w.add(
        "quest",
        33,
        {"name": "Lost\tthings", "level": 8, "zone": ELWYNN, "requiredItems": [[31, 1], [27, 1]]},
    )
    w.add("quest", 34, {"name": "Carry it", "gives": [[22, 1]], "requiredItems": [[22, 1]]})
    w.add("quest", 35, {"name": "Kobolds", "level": 3, "objectives": [["slay", "npc:1"]]})
    return w


def test_the_build_counts_the_steps_and_lists_the_classic_debt_lowest_level_first():
    """data.md "The count and the watch" (package QD4; "a constant check to
    replace these classic with forever asap"). A step has a place, or needs none (the item the
    giver hands over), or is without one; the Classic debt is the steps Classic knowledge alone
    places, listed where a low character can check them first."""
    report = steps.resolve(counted_world())
    assert report.counts() == {
        "quests": 7,  # with the fixture's quest 900, which has nothing to do
        "quests_without_steps": 1,
        "steps": 7,
        "steps_by_kind": {
            "get": {"steps": 3, "placed": 0},
            "reach": {"steps": 1, "placed": 1},
            "slay": {"steps": 3, "placed": 3},
        },
        "placed": 4,
        "placed_by_src": {"subject": 1, "classic": 3},
        "given": 1,
        "unplaced": 2,
        "unplaced_by_reason": {"craft": 1, "unknown": 1},
        "classic": 3,
        "classic_by_zone": {"Elwynn Forest": 2, f"map {WESTFALL}": 1},
        "authored_unchecked": 0,  # our own table's rows nobody checked (QD5)
    }
    # the lowest quest level first, a quest without a level last; unknown is an empty cell
    assert steps.listing(report.classic).splitlines() == [
        "quest\tstep\tsubject\tzone\tlevel\tkind\tquest_name\tsubject_name",
        f"31\t1\t\tmap {WESTFALL}\t5\treach\tThe point\t",
        "30\t1\tnpc:2\tElwynn Forest\t12\tslay\tOld kobolds\tOld Kobold",
        "32\t1\tnpc:2\tElwynn Forest\t\tslay\t\tOld Kobold",
    ]
    # the steps without a place say what is known instead, and where the quest starts; the
    # handed item is in neither list; a tab in a name cannot break a row
    assert steps.listing(report.open, reasons=True).splitlines() == [
        "quest\tstep\tsubject\tzone\tlevel\tkind\treason\tvia\tquest_name\tsubject_name",
        "33\t1\titem:31\tElwynn Forest\t8\tget\tunknown\t\tLost things\tNobody knows",
        "33\t2\titem:27\tElwynn Forest\t8\tget\tcraft\trecipe:40\tLost things\tCrafted",
    ]


def test_every_build_writes_the_count_and_the_two_lists_beside_its_report(tmp_path):
    """`links-<client>.json` is what the edition keeps and the watch compares; the lists are
    for a person. No time in them: the same world gives the same bytes. No number stops a
    build."""
    config = load_config()
    result = build(counted_world(), config, tmp_path / "a", report_dir=tmp_path / "a" / "build")
    assert result.ok
    folder = tmp_path / "a" / "build"
    assert result.links_path == folder / "links-forever.json"
    counts = json.loads(result.links_path.read_text(encoding="utf-8"))
    assert (counts["client"], counts["build"]) == ("forever", "test")
    assert (counts["steps"], counts["unplaced"], counts["classic"]) == (7, 2, 3)
    assert counts["edges"]["edge.targets"]["keys"] > 0 < counts["edges"]["edge.targets"]["bytes"]
    classic = (folder / "links-classic-forever.tsv").read_text(encoding="utf-8")
    assert classic.splitlines()[1].startswith("31\t1\t")
    unplaced = (folder / "links-unplaced-forever.tsv").read_text(encoding="utf-8")
    assert len(unplaced.splitlines()) == 3
    report = result.report
    assert "## Quest steps" in report and "7 steps in 6 of 7 quests." in report
    assert "| slay | 3 | 3 |" in report and "| get | 3 | 0 |" in report
    assert "- With a place: 4 (subject 1, classic 3;" in report
    assert "- No place needed: 1 (the item the giver hands over)." in report
    assert "- Without a place: 2 (craft 1, unknown 1). The list: `links-unplaced-forever.tsv`." in (
        report
    )
    assert "**The Classic debt**: 3 steps" in report
    # the zones with the most to check first
    zones = report.split("| Zone | Classic-only steps |")[1].splitlines()[2:4]
    assert zones == ["| Elwynn Forest | 2 |", f"| map {WESTFALL} | 1 |"]
    again = build(counted_world(), config, tmp_path / "b", report_dir=tmp_path / "b" / "build")
    for name in ("links-forever.json", "links-classic-forever.tsv", "links-unplaced-forever.tsv"):
        assert (folder / name).read_bytes() == (again.links_path.parent / name).read_bytes()
    # a check writes nothing
    checked = build(counted_world(), config, tmp_path / "c", write=False)
    assert checked.links_path is None and not (tmp_path / "c").exists()
