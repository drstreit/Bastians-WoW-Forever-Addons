"""World drops: the shared loot
lists (CMaNGOS ``reference_loot_template``) are expanded; an item few creatures reach that way joins
their drops, an item many reach keeps the droppers' level band and count."""

from bastians_build import canon
from bastians_build.canon import Sources, merge_creatures, merge_items, reference_items
from bastians_build.model import World
from bastians_build.sources.cmangos import ItemRow, LootRow


def loot(kind, entry, item=None, chance=100.0, ref=None, quest=False):
    return LootRow(
        kind=kind,
        entry=entry,
        item_id=item,
        chance_pct=chance,
        quest_drop=quest,
        group_id=None,
        min_count=None if ref else 1,
        max_count=None if ref else 1,
        reference_id=ref,
    )


def item(i):
    return ItemRow(i, f"Item {i}", 2, 20, 15, 4, 1, None, 100, 1)


def test_shared_lists_are_expanded_nested_and_cut_at_a_cycle():
    rows = [
        loot("reference", 900, item=1, chance=50.0),
        loot("reference", 900, ref=901, chance=50.0),  # half the rolls go to the nested list
        loot("reference", 901, item=2, chance=10.0),
        loot("reference", 901, ref=900, chance=100.0),  # back to 900: cut
    ]
    lists = reference_items(rows)
    assert lists[901][0] == (2, 10.0, False)
    by_item = {i: c for i, c, _ in lists[900]}
    assert by_item[1] == 50.0 and round(by_item[2], 6) == 5.0


def test_an_item_many_creatures_reach_is_a_world_drop_with_their_level_band():
    s = Sources(client="forever", build="t")
    n = canon.WORLD_DROP_MIN_DROPPERS
    s.cm_creatures = [
        {"Entry": 1000 + i, "Name": f"Mob {i}", "MinLevel": 20 + i % 5, "MaxLevel": 21 + i % 5}
        for i in range(n)
    ]
    s.cm_items = [item(10), item(11)]
    s.cm_loot = [
        loot("reference", 24000, item=10, chance=2.0),
        *(loot("creature", 1000 + i, ref=24000, chance=100.0) for i in range(n)),
        # item 11: a small shared list two creatures roll, half the time
        loot("reference", 24001, item=11, chance=40.0),
        loot("creature", 1000, ref=24001, chance=50.0),
        loot("creature", 1001, ref=24001, chance=50.0),
    ]
    world = World("forever")
    merge_creatures(world, s)
    merge_items(world, s)
    assert world.get("item", 10)["worldDrop"] == [20, 25, n]
    assert world.get("item", 10).get("drops") is None
    # few droppers through a shared list: they are its drops, with the combined chance
    assert world.get("item", 11)["drops"] == [["npc:1000", 20.0, False], ["npc:1001", 20.0, False]]
    assert world.get("item", 11).get("worldDrop") is None
