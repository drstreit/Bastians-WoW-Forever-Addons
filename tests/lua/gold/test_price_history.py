"""The price history (#19, gold.md "Price history"): each scan day keeps one line of medians per realm
and faction, 14 days; the Price section draws a sparkline from two days on, with the change; a day
without a scan is a gap, never 0; the newest scan again after a /reload changes nothing."""

from harness import WowRuntime
from test_prices import boot, listing, scan

DAY = 86400


def history(wow: WowRuntime):
    return wow.eval("Bastians:GetModule('Gold').History")


def series(wow: WowRuntime, item: int) -> list[tuple[int, int]]:
    s = history(wow).Series(item)
    return [(p.day, p.median) for p in s.values()]


def price_section(wow: WowRuntime, item: int) -> list[str]:
    for section in wow.eval(f"Bastians:GetDetailSections('item:{item}')").values():
        if section.id == "gold.price":
            return [(r.text or "") + " | " + str(r.value) for r in section.rows.values()]
    return []


def test_two_scan_days_draw_a_sparkline_with_the_change(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(0, 2589, 1, 100), listing(1, 1185, 1, 50)])
    assert len(series(wow, 2589)) == 1
    assert not any("Your scans" in r for r in price_section(wow, 2589))  # one day: no line yet
    wow.advance(2 * DAY)  # a day without a scan between: a gap, not a 0
    scan(wow, [listing(0, 2589, 1, 112)])
    days = series(wow, 2589)
    assert [m for _, m in days] == [100, 112] and days[1][0] - days[0][0] == 2
    assert [m for _, m in series(wow, 1185)] == [50]  # not seen on the second day
    row = next(r for r in price_section(wow, 2589) if "Your scans" in r)
    assert row.startswith("Your scans, 2 days  |TInterface\\Buttons\\WHITE8X8:2:3:0:-5:")
    assert row.count("WHITE8X8:12:3:0:0:") == 1 and row.endswith(" | +12 %")
    assert (
        history(wow).Change(
            wow.lua.table_from(
                [wow.lua.table_from({"median": 5}), wow.lua.table_from({"median": 5})]
            )
        )
        == "steady"
    )
    assert wow.errors == []


def test_the_newest_scan_after_a_reload_is_not_kept_twice_and_old_days_go(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(0, 2589, 1, 100)])
    fresh = wow.reload()
    fresh.run_frames(10)
    assert len(series(fresh, 2589)) == 1
    for n in range(16):
        fresh.advance(DAY)
        fresh.execute("AuctionHouseFrame:Show()")
        scan(fresh, [listing(0, 2589, 1, 100 + n)])
    kept = series(fresh, 2589)
    assert len(kept) == 14 and kept[-1][1] == 115  # 14 days, the newest last
    assert fresh.errors == []


def test_an_unknown_item_has_no_history_and_no_line(wow: WowRuntime):
    boot(wow)
    assert series(wow, 424242) == []
    assert history(wow).Row(424242) is None
    assert history(wow).Spark(wow.lua.table_from([])) is None
