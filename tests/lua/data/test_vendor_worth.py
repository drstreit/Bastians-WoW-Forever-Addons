"""Data's vendor worth (ADR 0022): an item is worth its vendor sell price where no Gold says more
(retail has no Gold since 24.10.2026); Gold's worth wins where Gold runs; an item without a
vendor price has no worth line, never 0."""

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
BROWSER = "Bastians_Browser"  # an app that wants the items pack (Data loads what apps declare)


def worth(wow: WowRuntime, ref: str):
    w = wow.eval(f"Bastians:Entity('{ref}'):Worth()")
    return None if w is None else (str(w.text).replace("|r", ""), w.copper)


def test_an_item_is_worth_its_vendor_price_without_gold(wow: WowRuntime):
    wow.start(CORE, DATA, BROWSER)
    wow.run_frames(5)
    text, copper = worth(wow, "item:2589")  # Linen Cloth, sells for 13c (the fixture world)
    assert text.startswith("vendor 13") and copper == 13
    assert worth(wow, "item:999999") is None  # unknown: no line
    assert wow.errors == []


def test_gold_says_more_where_it_runs(wow: WowRuntime):
    wow.needs(GOLD)
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')  # the fixture market
    wow.start(CORE, DATA, BROWSER, GOLD)
    wow.run_frames(10)
    wow.advance(0.5)
    text, _ = worth(wow, "item:2589")
    assert text.startswith("AH ")  # Gold's provider (priority 50) over Data's (10)
    assert wow.errors == []
