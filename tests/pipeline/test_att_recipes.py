"""Retail's recipes from AllTheThings (28.10.2026: "we have no recipes"): ``CreateRecipe`` entries
become recipe records with the profession, the skill and the teaching item; removed ones and
unknown skill lines are left out; Forever keeps its own."""

from bastians_build.canon import Sources, merge_att_recipes
from bastians_build.model import World
from bastians_build.sources.allthethings import assemble


def att():
    raw = {
        "r": [
            {"id": 247694, "skill": 171, "learnedAt": 10, "item": 151706},
            {"id": 247694, "skill": 171},  # the same recipe elsewhere in the tree
            {"id": 28677, "skill": 171, "u": 2},  # removed from the game
            {"id": 131733, "skill": 999},  # not a profession we name
            {"id": 3275, "skill": 129, "learnedAt": 1},  # First Aid, learned from a trainer
        ]
    }
    return assemble(raw, {}, "Standard", "5.4.4")


def test_recipes_from_allthethings_on_retail():
    s = Sources(client="retail")
    s.att = att()
    world = World("retail")
    merge_att_recipes(world, s)
    alchemy = world.get("recipe", 247694)
    assert (alchemy["profession"], alchemy["skill"]) == ("Alchemy", 10)
    assert (alchemy["source"], alchemy["sourceItem"], alchemy["src"]) == ("item", 151706, "att")
    assert world.get("recipe", 28677) is None and world.get("recipe", 131733) is None
    aid = world.get("recipe", 3275)
    assert aid["profession"] == "First Aid" and aid.get("sourceItem") is None


def test_forever_keeps_its_own_recipes():
    s = Sources(client="forever")
    s.att = att()
    world = World("forever")
    merge_att_recipes(world, s)
    assert world.get("recipe", 247694) is None
