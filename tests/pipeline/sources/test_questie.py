"""Questie's hidden quests (ADR 0051) against a trimmed copy of the real files: the expressions are
evaluated for Forever, and the flags land on the world's quests."""

from pathlib import Path

from bastians_build.canon import Sources, merge_questie_gates
from bastians_build.model import World
from bastians_build.sources import questie
from bastians_build.sources.questie import QuestGates

FIX = Path(__file__).resolve().parents[2] / "fixtures" / "sources" / "questie"


def test_the_expressions_are_evaluated_for_forever():
    gates = questie.read_quest_gates(FIX)
    assert gates.version == "12.6.0"
    assert 787 in gates.absent  # plain true
    assert 2358 in gates.absent and 236 in gates.absent  # true on Era
    assert 9260 not in gates.absent  # false on Era: it is the invasion that hides it
    assert 63866 not in gates.absent
    assert 78124 not in gates.absent  # HIDE_ON_MAP: the quest exists


def test_the_one_time_events_are_dormant():
    gates = questie.read_quest_gates(FIX)
    assert gates.dormant == {8492, 8493, 9260, 9292}


def test_the_event_quests_are_read_with_their_event():
    gates = questie.read_quest_gates(FIX)
    assert gates.events == {172: "Children's Week", 10960: "Children's Week"}


def world(*quests: tuple[int, dict]) -> World:
    w = World(client="forever", build="test", sources=[])
    for quest_id, rec in quests:
        w.records.setdefault("quest", {})[quest_id] = dict(rec)
    return w


def merged(w: World, **gates) -> World:
    s = Sources(client="forever")
    s.questie_gates = QuestGates(
        gates.get("absent", frozenset()),
        gates.get("dormant", frozenset()),
        gates.get("events", {}),
        "12.6.0",
    )
    merge_questie_gates(w, s)
    return w


def test_the_flags_land_on_the_quests_the_world_has():
    w = merged(
        world((787, {"flags": ["event"]}), (9260, {})),
        absent=frozenset({787, 5}),
        dormant=frozenset({9260}),
    )
    assert w.get("quest", 787)["flags"] == ["absent", "event"]
    assert w.get("quest", 9260)["flags"] == ["dormant"]
    assert w.get("quest", 5) is None


def test_a_quest_players_were_seen_taking_keeps_no_flag():
    w = merged(world((787, {"seenBy": 3})), absent=frozenset({787}), dormant=frozenset({787}))
    assert w.get("quest", 787).get("flags") is None


def test_an_event_quest_gets_its_event_and_never_absent():
    # Questie hides 172 until Children's Week runs: absent would hide it during the event too
    w = merged(
        world((172, {}), (8649, {"holiday": "Lunar Festival"})),
        absent=frozenset({172, 8649}),
        events={172: "Children's Week", 8649: "Other"},
    )
    assert w.get("quest", 172)["holiday"] == "Children's Week"
    assert w.get("quest", 172).get("flags") is None
    assert w.get("quest", 8649)["holiday"] == "Lunar Festival"  # a source's name stays
    assert w.get("quest", 8649).get("flags") is None


def test_no_questie_changes_nothing():
    w = world((787, {}))
    merge_questie_gates(w, Sources(client="forever"))
    assert w.get("quest", 787) == {}
