"""Breadcrumbs (Everything Quests 2.16.0, 21.11.2026): `leads` on the breadcrumb, `crumbs` on the
quest it leads to, `maxLevel` from the same table."""

from bastians_build.canon import Sources, link_breadcrumbs, merge_quests
from bastians_build.model import World
from bastians_build.sources.everything_quests import assemble


def world_of(quests: dict[int, dict]) -> World:
    world = World(client="forever", build="test", sources=[])
    world.records["quest"] = {k: dict(v) for k, v in quests.items()}
    return world


def test_every_quest_names_the_breadcrumbs_that_lead_to_it():
    world = world_of({5: {}, 163: {"leads": [5]}, 164: {"leads": [5, 95]}, 95: {}, 7: {}})
    link_breadcrumbs(world)
    q = world.records["quest"]
    assert q[5]["crumbs"] == [163, 164] and q[95]["crumbs"] == [164]
    assert "crumbs" not in q[163] and "crumbs" not in q[7]
    assert any(n.startswith("breadcrumbs: 3 lead to 2 quests") for n in world.notes)


def test_a_lead_to_an_unknown_quest_or_to_itself_names_nothing():
    world = world_of({163: {"leads": [999, 163]}})
    link_breadcrumbs(world)
    assert "crumbs" not in world.records["quest"][163] and world.notes == []


def test_merge_quests_ships_leads_and_max_level():
    eq = assemble(
        {
            "names": {163: "Raven Hill", 5: "Jitters' Growling Gut", 7863: "Arathi Basin"},
            "leads": {163: [5]},
            "maxLevel": {7863: 34},
        }
    )
    world = World(client="forever", build="test", sources=[])
    s = Sources(client="forever")
    s.eq = eq
    merge_quests(world, s)
    q = world.records["quest"]
    assert q[163]["leads"] == [5] and q[5].get("leads") is None
    assert q[7863]["maxLevel"] == 34 and q[5].get("maxLevel") is None
