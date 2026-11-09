"""A log quest's map shows what is still to do (two of three targets done,
the map still drew all three spawn areas under the quest's name). A spot serves objectives by its
bit; finished ones go, the label and the card say what to do there, a spot nobody can tell stays."""

from harness import WowRuntime
from test_registrations import ELWYNN_VIEW, boot

MOD = "Bastians:GetModule('Quests')"
LOGIC = f"{MOD}.Logic"
REG = f"{MOD}.Registrations"


def objective(text: str, have: int, need: int, kind: str = "monster") -> str:
    done = "true" if have >= need else "false"
    return (
        f"{{ text = '{have}/{need} {text}', type = '{kind}', finished = {done}, "
        f"numFulfilled = {have}, numRequired = {need} }}"
    )


def setup(wow: WowRuntime, spots: str, *objectives: str) -> None:
    """Quest 76 in the log, focused, with these spots on Elwynn."""
    boot(wow)
    wow.execute(
        f"local q = {LOGIC}.quest(76); q.spots = {{ [1429] = {spots} }}; q._places = nil; "
        "Mock.questLog[#Mock.questLog + 1] = { questID = 76, title = 'The Jasperlode Mine', "
        f"level = 9, complete = false, objectives = {{ {', '.join(objectives)} }} }}"
    )
    settle(wow)
    wow.execute("Bastians:Focus('quest:76', { source = 'test' })")


def settle(wow: WowRuntime) -> None:
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.5)
    wow.run_frames(5)


def pins(wow: WowRuntime) -> list:
    found = wow.eval(f"Bastians:QueryLayer('quests.objectives', {ELWYNN_VIEW})").values()
    return [p for p in found if p.ref == "quest:76"]


THREE = (
    "{ { 0.43, 0.66, 'area', 1 }, { 0.44, 0.60, 'area', 1 }, { 0.40, 0.62, 'area', 2 }, "
    "{ 0.41, 0.60, 'area', 4 } }"
)
YOUTH, GUARD, MOTHER = ("Young Wolf slain", "Old Wolf slain", "Wolf Mother slain")


def test_finished_objectives_leave_the_map_and_the_rest_say_what_to_do(wow: WowRuntime):
    setup(
        wow,
        THREE,
        objective(YOUTH, 0, 8),
        objective(GUARD, 6, 6),
        objective(MOTHER, 1, 1),
    )
    found = pins(wow)
    assert [p.label for p in found] == ["Young Wolf slain 0/8", "Young Wolf slain 0/8"]
    assert wow.errors == []


def test_the_card_names_the_target_before_the_quest(wow: WowRuntime):
    setup(wow, THREE, objective(YOUTH, 3, 8), objective(GUARD, 6, 6), objective(MOTHER, 1, 1))
    pin = pins(wow)[0]
    card = pin.card(pin)
    assert card.title == "Young Wolf slain 3/8"
    assert card.lines[1].text == "The Jasperlode Mine"
    assert wow.errors == []


def test_the_map_follows_the_progress(wow: WowRuntime):
    setup(wow, THREE, objective(YOUTH, 0, 8), objective(GUARD, 5, 6), objective(MOTHER, 1, 1))
    assert sorted(p.label for p in pins(wow)) == [
        "Old Wolf slain 5/6",
        "Young Wolf slain 0/8",
        "Young Wolf slain 0/8",
    ]
    wow.execute(
        "local o = Mock.questLog[#Mock.questLog].objectives; "
        "o[2].numFulfilled = 6; o[2].finished = true; o[2].text = '6/6 Old Wolf slain'"
    )
    settle(wow)
    assert {p.label for p in pins(wow)} == {"Young Wolf slain 0/8"}
    assert wow.errors == []


def test_every_spot_done_leaves_no_pin_of_the_pack(wow: WowRuntime):
    setup(wow, THREE, objective(YOUTH, 8, 8), objective(GUARD, 6, 6), objective(MOTHER, 1, 1))
    assert pins(wow) == []
    assert wow.errors == []


def test_a_spot_nobody_can_tell_stays_under_the_quests_name(wow: WowRuntime):
    spots = "{ { 0.42, 0.65, 'slay', 0 }, { 0.44, 0.60, 'area', 8 }, { 0.40, 0.62, 'mystery', 1 } }"
    setup(wow, spots, objective(YOUTH, 8, 8))
    found = pins(wow)
    assert [p.label for p in found] == ["The Jasperlode Mine"] * 3
    assert found[0].open is None and found[0].card is None
    assert wow.errors == []


def test_a_kinds_bit_counts_within_that_kind(wow: WowRuntime):
    # the first monster objective is the client's second objective
    spots = "{ { 0.42, 0.65, 'slay', 1 }, { 0.44, 0.60, 'loot', 1 } }"
    setup(wow, spots, objective("Wolf Pelt", 3, 3, "item"), objective(YOUTH, 0, 8))
    assert [p.label for p in pins(wow)] == ["Young Wolf slain 0/8"]
    assert wow.errors == []


def test_one_place_for_several_objectives_lists_the_open_ones(wow: WowRuntime):
    spots = "{ { 0.42, 0.65, 'area', 7 } }"
    setup(wow, spots, objective(YOUTH, 0, 8), objective(GUARD, 6, 6), objective(MOTHER, 0, 1))
    pin = pins(wow)[0]
    assert pin.label == "Young Wolf slain 0/8"
    card = pin.card(pin)
    assert card.title == "Young Wolf slain 0/8" and card.lines[1].text == "Wolf Mother slain 0/1"
    assert card.lines[2].text == "The Jasperlode Mine"
    assert wow.errors == []


def test_route_and_map_buttons_go_only_to_what_is_left(wow: WowRuntime):
    setup(wow, THREE, objective(YOUTH, 0, 8), objective(GUARD, 6, 6), objective(MOTHER, 1, 1))
    places = wow.eval(f"{REG}.QuestPlaces('quest:76', 'objective')").values()
    assert sorted((p.x, p.y) for p in places) == [(0.43, 0.66), (0.44, 0.6)]
    locations = wow.eval("Bastians:Entity('quest:76'):Locations()").values()
    assert sorted((p.x, p.y) for p in locations) == [(0.43, 0.66), (0.44, 0.6)]
    assert wow.errors == []


def test_the_pure_reading_of_a_spot(wow: WowRuntime):
    boot(wow)
    objectives = (
        "{ { kind = 'monster', text = 'a' }, { kind = 'item', text = 'b' }, "
        "{ kind = 'monster', text = 'c' } }"
    )

    def served(spot: str):
        got = wow.eval(f"{LOGIC}.SpotObjectives({objectives}, {spot})")
        return None if got is None else [o.text for o in got.values()]

    assert served("{ 0, 0, 'area', 5 }") == ["a", "c"]
    assert served("{ 0, 0, 'slay', 2 }") == ["c"]
    assert served("{ 0, 0, 'slay', 3 }") == ["a", "c"]
    assert served("{ 0, 0, 'loot', 1 }") == ["b"]
    assert served("{ 0, 0, 'loot', 2 }") is None  # past the list: unknown, not done
    assert served("{ 0, 0, 'area', 8 }") is None
    assert served("{ 0, 0, 'slay', 0 }") is None
    assert served("{ 0, 0, 'slay' }") is None
    assert wow.eval(f"{LOGIC}.SpotObjectives(nil, {{ 0, 0, 'area', 1 }})") is None
    assert wow.errors == []
