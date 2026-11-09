"""What a tile says of an item and a recipe (ADR 0056, PA2.3): the client's words for an item's kind
and slot, the reagents of a recipe; where the client knows nothing, the summary stays."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute('Bastians:GetService("data"):LoadPack("items")')
    wow.run_frames(5)
    return wow


def tile(wow: WowRuntime, ref: str):
    return wow.eval(f"Bastians:Entity('{ref}'):Facet('tile')")


def test_an_item_says_its_kind_and_slot(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.items[2589] = { equipLoc = 'INVTYPE_CHEST' }; INVTYPE_CHEST = 'Chest'")
    assert tile(wow, "item:2589").line == "Cloth, Chest"


def test_an_item_not_to_wear_says_its_kind(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.items[2589] = {}")  # the mock's INVTYPE_NON_EQUIP has no client word
    assert tile(wow, "item:2589").line == "Cloth"


def test_an_item_the_client_does_not_know_keeps_the_summary(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.items[2589] = nil")
    assert tile(wow, "item:2589") is None


def test_a_recipe_says_what_goes_in(wow: WowRuntime):
    boot(wow)
    line = tile(wow, "recipe:2152").line
    assert line and "Light Leather" in line
    assert wow.eval("(Bastians.Compat.ItemKind(nil))") is None
