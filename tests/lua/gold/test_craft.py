"""Craft for gold (gold.md "Craft for gold", catalog review A5.1, 07.11.2026): the known recipes
by profit with the way to sell; a reagent without a price leaves the profit unknown; the pure
Pricing.Ways rule."""

import re

from harness import WowRuntime
from test_prices import boot, listing, scan

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
P = f"{MOD}.Pricing"
C = f"{MOD}.Craft"


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def test_the_view_lists_the_known_recipes_by_profit(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    wow.execute("Bastians:GetService('data'):LoadPack('world')")
    wow.execute("Mock.spells[2152] = true")  # Light Armor Kit: 1 Light Leather (2318) -> 2304
    rows, summary = wow.eval(f"{C}.Rows()")
    assert summary == "1 recipes known, 0 with a profit"
    row = next(iter(rows.values()))
    assert row.ref == "recipe:2152" and row.value is None
    assert strip(row.meta).startswith("Costs at least") and "profit unknown" in row.meta
    # prices arrive: leather at 10c, the kit at 1s; the auction house after the cut brings 95c
    scan(wow, [listing(1, 2318, 1, 10), listing(2, 2304, 1, 100)])
    rows, summary = wow.eval(f"{C}.Rows()")
    row = next(iter(rows.values()))
    assert summary == "1 recipes known, 1 with a profit"
    assert row.value == 85 and row.valueKind == "money"
    assert strip(row.meta) == "Costs 10c; the auction house brings 95c"
    # an unknown recipe is not listed
    wow.execute("Mock.spells[2152] = nil")
    rows, summary = wow.eval(f"{C}.Rows()")
    assert len(rows) == 0 and summary == "You know none of the recipes the data lists."
    assert wow.errors == []


def test_the_view_is_registered_and_opens(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    assert wow.eval("Bastians:GetView('gold.craft') ~= nil") is True
    assert wow.eval("Bastians:GetView('gold.craft').title") == "Craft for gold"
    assert wow.errors == []


def test_ways_is_pure_and_unknown_stays_unknown(core: WowRuntime):
    core.start(CORE, GOLD)
    recipe = "{ item = 1, count = 2, reagents = { { 10, 3 }, { 11, 1 } } }"
    prices = "function(id) return ({ [1] = 100, [10] = 5, [11] = 20 })[id] end"
    sell = "function(id) return 30 end"
    de = "function(id) return 60, 0 end"
    w = core.eval(f"{P}.Ways({recipe}, {prices}, {sell}, {de})")
    assert (w.cost, w.missing) == (35, 0)
    assert (w.ah, w.vendor, w.disenchant) == (190, 60, 120)  # 2 x 100 after the cut, 2 x 30, 2 x 60
    assert (w.best, w.way, w.profit) == (190, "ah", 155)
    # disenchanting wins when the auction house is unknown; a reagent without a price: no profit
    w = core.eval(
        f"{P}.Ways({recipe}, function(id) return id == 10 and 5 or nil end, {sell}, {de})"
    )
    assert w.ah is None and (w.best, w.way) == (120, "disenchant") and w.profit is None
    assert w.missing == 1 and w.cost == 15
    # a disenchant value with a material unpriced is no way to count on
    w = core.eval(f"{P}.Ways({recipe}, {prices}, nil, function(id) return 60, 1 end)")
    assert w.disenchant is None and w.vendor is None and (w.best, w.way) == (190, "ah")
    assert core.eval(f"{P}.Ways(nil, {prices})").best is None
    assert core.errors == []
