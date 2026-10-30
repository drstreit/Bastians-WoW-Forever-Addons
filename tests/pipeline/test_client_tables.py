"""The client's own tables (ADR 0035, "client first"): items, recipes, quest lines and objective
areas from clientdump's JSON, over the older sources; the item names of every installed text
language for the language packs."""

from pathlib import Path

from bastians_build.canon import (
    PROFESSION_SKILL_LINES,
    Sources,
    merge_client_items,
    merge_client_quest_areas,
    merge_client_quest_lines,
    merge_client_recipes,
)
from bastians_build.l10n import add_l10n
from bastians_build.sources.client_tables import (
    localized_names,
    read_client_tables,
    read_quest_lines,
)
from bastians_build.sources.cmangos import ItemRow
from bastians_build.sources.fixture import read_fixture
from bastians_build.sources.probe import Transform

ROOT = Path(__file__).resolve().parents[1]
DUMPS = ROOT / "fixtures" / "client-tables"
WORLD = ROOT / "fixtures" / "world-mini"


def tables():
    t = read_client_tables(DUMPS, "forever", set(PROFESSION_SKILL_LINES))
    assert t is not None
    return t


def test_the_reader_takes_items_recipes_lines_and_areas():
    t = tables()
    linen = t.items[2589]
    assert (linen.name, linen.quality, linen.level, linen.sell, linen.buy, linen.stack) == (
        "Linen Cloth",
        1,
        5,
        13,
        55,
        20,
    )
    assert (linen.item_class, linen.item_subclass, linen.required_level) == (7, 5, None)
    # the skill itself (Blacksmithing, no product, no reagents) is no recipe
    assert [r.spell for r in t.recipes] == [2660]
    stone = t.recipes[0]
    assert (stone.name, stone.item, stone.count, stone.reagents) == (
        "Rough Sharpening Stone",
        2862,
        1,
        ((2835, 1),),
    )
    assert stone.learned_at is None  # rank 1: the trainer's level lives server-side
    assert read_quest_lines(DUMPS, "forever") == [[176, 62]]  # by OrderIndex
    assert len(t.quest_areas) == 2
    assert read_client_tables(DUMPS, "retail", set()) is None  # no retail dumps here


def test_the_client_wins_for_what_it_holds():
    world = read_fixture(WORLD, "forever")
    s = Sources(client="forever")
    s.client_tables = tables()
    # a Classic item list that lacks the token: the token is new in Forever
    s.cm_items = [_classic(2589), _classic(2862), _classic(2835)]
    s.transforms = {1429: Transform(1429, 0, 0.0, -200.0, 0.0, 100.0, 0.0, -200.0, True)}
    merge_client_recipes(world, s)
    merge_client_items(world, s)
    merge_client_quest_lines(world, s)
    merge_client_quest_areas(world, s)
    linen = world.records["item"][2589]
    assert (linen["name"], linen["sell"], linen["buy"], linen["stack"]) == (
        "Linen Cloth",
        13,
        55,
        20,
    )
    token = world.records["item"][190001]
    assert token["foreverNew"] is True and token["src"] == "client"
    recipe = world.records["recipe"][2660]
    assert (recipe["profession"], recipe["item"], recipe["reagents"]) == (
        "Blacksmithing",
        2862,
        [[2835, 1]],
    )
    assert world.records["quest"][176]["chain"] == 62  # the line's order
    spots = world.records["quest"][76]["spots"]
    # the objective area's centre as a map fraction; the turn-in area (-1) gives no spot
    assert list(spots) == [1429] and spots[1429] == [[0.55, 0.05, "area", 1]]


def test_the_item_names_of_every_installed_language_win_in_the_packs():
    names = localized_names(DUMPS, "forever")
    assert names == {"deDE": {"item": {2589: {"name": "Leinenstoff (Client)"}}}}
    world = read_fixture(WORLD, "forever")
    add_l10n(world, ROOT / "fixtures" / "questie-l10n", client_names=names)
    assert world.records["item_deDE"][2589]["name"] == "Leinenstoff (Client)"  # over QuestieDB
    assert world.records["item_deDE"][1185]["name"] == "Blutsäbel"  # QuestieDB where no client
    assert any(src.startswith("client names (deDE)") for src in world.sources)


def _classic(item_id: int) -> ItemRow:
    return ItemRow(item_id, "classic", 1, 5, 0, 7, 5, 1, 4, 20)
