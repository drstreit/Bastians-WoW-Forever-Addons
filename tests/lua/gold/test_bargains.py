"""Bargains: "HOW am I supposed to find
one?" - every item whose lowest listing lies far under its 30-day median, the biggest saving
first, as Gold's tab; a fresh own scan keeps the pack's 30-day median beside its listing."""

import re

from harness import WowRuntime
from test_prices import boot, listing, price, scan

CORE, DATA, GOLD, BROWSER = "Bastians_Core", "Bastians_Data", "Bastians_Gold", "Bastians_Browser"
BG = "Bastians:GetModule('Gold').Bargains"
BR = "Bastians:GetModule('Browser')"


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def test_rows_are_the_bargains_by_saving_and_unknown_is_no_row(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    prices = (
        "function(id) return ({ [1] = { minBuyout = 50, median30d = 100 },"
        " [2] = { minBuyout = 90, median30d = 100 }, [3] = { minBuyout = 10, median30d = 200 },"
        " [4] = { median30d = 100 } })[id] end"
    )
    rows = list(wow.eval(f"{BG}.Rows({{ 1, 2, 3, 4, 5 }}, {prices})").values())
    assert [r.ref for r in rows] == ["item:3", "item:1"]  # 190 saved before 50; 2, 4, 5 are none
    assert rows[0].value == 190 and rows[0].valueKind == "money"
    assert strip(rows[1].meta) == "lowest 50c, usually 1s 00c (30 days)"
    assert wow.errors == []


def test_the_tab_lists_the_markets_bargains_and_a_fresh_scan_keeps_them(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD, BROWSER, realm="Classic Beta PvE")
    assert wow.eval("Bastians:GetView('gold.bargains').rail") == "gold"
    wow.execute(f"{BR}.Browser.ShowView('gold.bargains')")
    wow.run_frames(40)
    refs = [r.ref for r in wow.eval(f"{BR}.tree.flat").values() if r.ref]
    if wow.client == "forever":  # Linen Cloth: lowest 20c, 30-day median 75c in the fixture
        assert "item:2589" in refs
    # a fresh own scan: its listing against the pack's 30-day median
    scan(wow, [listing(0, 2589, 1, 30)])
    p = price(wow, 2589)
    assert p.source == "scan"
    if wow.client == "forever":
        assert p.median30d == 75
        assert wow.eval(f"{BG}.Row(2589, Bastians:GetService('prices'):Price(2589)) ~= nil")
    assert wow.errors == []
