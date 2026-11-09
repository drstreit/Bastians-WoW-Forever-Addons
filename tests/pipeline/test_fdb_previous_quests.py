"""ForeverDB's confirmed previous quest joins `pre`, and never locks a quest for good."""

from bastians_build.canon import Sources, merge_fdb_previous_quests
from bastians_build.model import World
from bastians_build.sources.foreverdb import QuestRow


def row(quest_id: int, previous: int | None) -> QuestRow:
    return QuestRow(quest_id, "T", 3, 1, None, (), (), 1, False, previous, None)


def merged(quests: dict[int, dict], *rows: QuestRow) -> dict[int, dict]:
    world = World(client="forever", build="test", sources=[])
    world.records["quest"] = {k: dict(v) for k, v in quests.items()}
    s = Sources(client="forever")
    s.fdb_quests = list(rows)
    merge_fdb_previous_quests(world, s)
    return world.records["quest"]


def test_the_previous_quest_joins_what_the_sources_named():
    q = merged({1: {"pre": [9]}, 2: {}, 9: {}}, row(1, 2))
    assert q[1]["pre"] == [9, 2]


def test_a_quest_without_one_or_with_an_unknown_one_is_left_alone():
    q = merged({1: {}, 3: {}}, row(1, None), row(3, 77))
    assert q[1].get("pre") is None and q[3].get("pre") is None


def test_one_the_sources_already_name_is_not_repeated():
    q = merged({1: {"pre": [2]}, 2: {}, 3: {"preAny": [2]}}, row(1, 2), row(3, 2))
    assert q[1]["pre"] == [2] and q[3].get("pre") is None


def test_it_never_locks_a_quest_for_good():
    alliance, horde, mage, priest = 77, 178, 128, 16
    q = merged(
        {
            1: {},  # itself
            2: {"excl": [6]},  # excluding it
            3: {"races": alliance},  # the other faction's
            4: {"classes": mage},  # another class's
            5: {},  # a cycle through 7
            6: {},
            7: {"pre": [5]},
            8: {"races": horde},
            9: {"classes": priest},
        },
        row(1, 1),
        row(2, 6),
        row(3, 8),
        row(4, 9),
        row(5, 7),
    )
    assert all(q[i].get("pre") is None for i in (1, 2, 3, 4, 5))


def test_an_unknown_mask_says_nothing():
    q = merged({1: {"races": 77}, 2: {}}, row(1, 2))
    assert q[1]["pre"] == [2]
