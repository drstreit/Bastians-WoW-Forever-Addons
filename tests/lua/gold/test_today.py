"""Today list, farm spots and the Gold window (B6.4): capital, time and profession filters and the
sorting on the fixture Market pack; spot entities, the layer with gold per hour and the claim's
status; the Where-to-farm section and actions; the window tabs."""

import re

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
WIN = f"{MOD}.Window"
ELWYNN_VIEW = "{ continent = 0, x1 = -300, y1 = -300, x2 = 300, y2 = 300, level = 3 }"


def boot(wow: WowRuntime, money: int = 1000000, professions: str = "{}") -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.execute(f"Mock.money = {money}; Mock.professions = {professions}")
    wow.start(CORE, DATA, GOLD)
    wow.run_frames(10)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def signals(wow: WowRuntime) -> str:
    market = "forever/normal/alliance/us" if wow.client == "forever" else "retail/normal/neutral/eu"
    return (
        "(function() local d = Bastians:GetService('data'); local out = {} "
        f"for _, k in ipairs(d:Index('signal.byMarket', '{market}')) do out[#out + 1] = d:Get('signal', k) end "
        "return out end)()"
    )


def build(wow: WowRuntime, ctx: str):
    lines, dropped, total = wow.eval(f"{MOD}.Today.build({signals(wow)}, {ctx})")
    return (
        [
            (line.key, line.action, round(line.gpm, 1) if line.gpm != float("inf") else "inf")
            for line in lines.values()
        ],
        dict(dropped.items()),
        total,
    )


def test_today_filters_capital_time_profession_and_sorts_by_gold_per_minute(wow: WowRuntime):
    boot(wow)
    if wow.client != "forever":
        lines, dropped, total = build(
            wow, "{ capital = 0, minutes = 60, professions = {}, now = 1760000000 }"
        )
        assert lines == [("retail/normal/neutral/eu:8", "sell", 60.0)] and total == 1
        return
    # rich, time, no professions known (nil): everything valid stays, craft lines carry a note
    lines, dropped, total = build(
        wow, "{ capital = 10000000, minutes = 120, professions = nil, now = 1760000000 }"
    )
    assert lines == [
        ("forever/normal/alliance/us:4", "avoid", "inf"),
        ("forever/normal/alliance/us:6", "craft", 450.0),
        ("forever/normal/alliance/us:5", "sell", 200.0),
        ("forever/normal/alliance/us:1", "sell", 160.0),
        ("forever/normal/alliance/us:3", "craft", 120.0),
        ("forever/normal/alliance/us:2", "farm", 100.0),
    ]
    assert dropped == {"expired": 1, "capital": 0, "time": 0, "profession": 0} and total == 6
    # poor: the two craft lines need capital the character lacks
    lines, dropped, _ = build(
        wow, "{ capital = 100, minutes = 120, professions = nil, now = 1760000000 }"
    )
    assert [k for k, _, _ in lines] == [
        "forever/normal/alliance/us:4",
        "forever/normal/alliance/us:5",
        "forever/normal/alliance/us:1",
        "forever/normal/alliance/us:2",
    ]
    assert dropped["capital"] == 2
    # ten minutes: the farm (30 min) and the big craft (20 min) go
    lines, dropped, _ = build(
        wow, "{ capital = 10000000, minutes = 10, professions = nil, now = 1760000000 }"
    )
    assert [k for k, _, _ in lines] == [
        "forever/normal/alliance/us:4",
        "forever/normal/alliance/us:5",
        "forever/normal/alliance/us:1",
        "forever/normal/alliance/us:3",
    ]
    assert dropped["time"] == 2
    # professions known and no leatherworking: both craft lines go; with it they stay without a note
    lines, dropped, _ = build(
        wow,
        "{ capital = 10000000, minutes = 120, professions = { Mining = 50 }, now = 1760000000 }",
    )
    assert dropped["profession"] == 2 and not any(a == "craft" for _, a, _ in lines)
    lines, _, _ = build(
        wow,
        "{ capital = 10000000, minutes = 120, professions = { Leatherworking = 100 }, now = 1760000000 }",
    )
    assert any(a == "craft" for _, a, _ in lines)
    # the ten-line cap
    assert (
        wow.eval(
            f"#({MOD}.Today.build({signals(wow)}, {{ capital = 10000000, minutes = 120, maxLines = 2 }}))"
        )
        == 2
    )


def test_reason_lines_and_the_profession_note(wow: WowRuntime):
    boot(wow)
    if wow.client != "forever":
        return
    reason = lambda key, ctx: strip(  # noqa: E731
        wow.eval(
            f"{MOD}.Today.reason(({MOD}.Today.line(Bastians:GetService('data'):Get('signal', '{key}'), {ctx})))"
        )
    )
    assert (
        reason("forever/normal/alliance/us:1", "{ capital = 1000, minutes = 60, professions = {} }")
        == "+8s, 5 min, 1s/min, 80 %"  # MoneyShort drops the copper
    )
    assert (
        reason("forever/normal/alliance/us:4", "{ capital = 1000, minutes = 60 }")
        == "do not buy or craft now, 90 %"
    )
    assert reason("forever/normal/alliance/us:3", "{ capital = 100000, minutes = 60 }") == (
        "+12s, 10 min, 1s/min, capital 50s, 60 %, needs Leatherworking (your professions are unknown)"
    )


def test_spots_are_entities_with_gold_per_hour_and_evidence(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:Entity('spot:1'):Name()") == "Hogger's camp"
    summary = strip(wow.eval("Bastians:Entity('spot:1'):Summary()"))
    if wow.client == "forever":
        # 30 linen at 38c = 11s 40c; the claw has no price
        assert (
            summary
            == "level 8-12, 11s/h (1 items without price), verified, 3 channels, reach 12000"
        )
        assert wow.eval(f"{MOD}.Spots.GoldPerHour(Bastians:GetService('data'):Get('spot', 1))") == (
            1140,
            1,
        )
    else:
        assert summary.startswith("level 8-12, 12s/h (1 items without price), verified")  # 30 x 40c
    assert (
        strip(wow.eval("Bastians:Entity('spot:3'):Summary()"))
        == "level 10-15, gold/h unknown, refuted"
    )
    assert wow.eval("Bastians:Entity('strategy:11'):Name()") == "Hogger's camp linen farm"
    assert wow.eval("Bastians:Entity('strategy:11'):Summary()") == "farm, verified, 3 channels"
    locs = wow.eval("Bastians:Entity('spot:1'):Locations()")
    assert (locs[1].map, locs[1].x, locs[1].y, locs[1].kind) == (1429, 0.27, 0.86, "spot")
    assert wow.errors == []


def test_farm_spot_layer_pins_carry_radius_colour_and_gold_per_hour(wow: WowRuntime):
    boot(wow)
    pins = {
        p.ref: p for p in wow.eval(f"Bastians:QueryLayer('gold.farmspots', {ELWYNN_VIEW})").values()
    }
    assert sorted(pins) == ["spot:1", "spot:2"]  # Westfall is outside the view
    hogger = pins["spot:1"]
    assert (hogger.radius, hogger.status, hogger.cluster) == (120, "verified", True)
    assert list(hogger.color.values()) == list(
        wow.eval("Bastians.UI.Style.C.good").values()
    )  # the theme's token (ST3)
    assert hogger.label.startswith("Hogger's camp (") and hogger.label.endswith("/h)")
    assert list(pins["spot:2"].color.values()) == list(
        wow.eval("Bastians.UI.Style.C.neutral").values()
    )
    assert wow.eval("Bastians:GetMapLayer('gold.farmspots').defaultOn") is True


def test_where_to_farm_section_search_and_actions(wow: WowRuntime):
    boot(wow)
    sections = {s.id: s for s in wow.eval("Bastians:GetDetailSections('item:2589')").values()}
    rows = [(strip(r.text), r.ref) for r in sections["gold.farm"].rows.values()]
    assert rows == [
        ("Hogger's camp  verified, 3 channels, reach 12000", "spot:1"),
        ("Fargodeep Mine  unverified, 1 channel, reach 800", "spot:2"),
    ]
    assert "gold.farm" not in {
        s.id for s in wow.eval("Bastians:GetDetailSections('item:6948')").values()
    }
    strategy = {s.id: s for s in wow.eval("Bastians:GetDetailSections('spot:1')").values()}[
        "gold.strategy"
    ]
    texts = [strip(r.text) for r in strategy.rows.values()]
    assert texts[0].startswith("Gold per hour (1 items without price)")
    assert texts[1] == "Linen Cloth x30/h" and texts[2] == "Huge Gnoll Claw x1/h"
    assert "Evidence: verified, 3 channels, reach 12000" in texts
    assert any(
        t.startswith("Hogger's camp linen farm  last seen 2025-10-09") or "last seen" in t
        for t in texts
    )
    ids = [a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()]
    assert "gold.farm" in ids and "gold.prices" in ids
    ids = [a.id for a in wow.eval("Bastians:GetActions('item:6948', { source = 'test' })").values()]
    assert "gold.farm" not in ids and "gold.prices" not in ids  # no spot, no price
    wow.execute(
        "hits = nil; Bastians:Search('hogger', { limit = 10 }, function(r, done) if done then hits = r end end)"
    )
    wow.run_frames(10)
    assert ("spot:1", "farm spot") in [(h.ref, h.note) for h in wow.g.hits.values()]
    assert ("strategy:11", "strategy") in [(h.ref, h.note) for h in wow.g.hits.values()]


def test_window_today_spots_and_price_tabs(wow: WowRuntime):
    boot(wow, money=100)
    wow.slash("/bgold today")
    wow.execute(f"{WIN}.tree.scroll:SetSize(480, 400); {WIN}.tree:Refresh()")
    texts = [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]
    summary = strip(wow.eval(f"{WIN}.summary:GetText()"))
    assert texts[0] == "INCOME  gold per day" and texts[1].startswith("Today  ")  # R9, first
    texts = texts[3:]  # the income block: the section, today, the last 7 days (no character yet)
    if wow.client == "forever":
        assert texts[0] == "SELL  2" and texts[3] == "FARM  1" and texts[5] == "AVOID  1"
        assert texts[1] == "Light Leather  +4s, 2 min, 2s/min, 50 %"
        assert summary == "4 of 7 signals - 2 need more capital - capital 1s, 30 min"
    else:
        assert texts[0] == "SELL  1"
    wow.execute("Bastians:RunAction('gold.farm', 'item:2589', { source = 'test' })")
    texts = [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]
    first, second = ("Fargodeep Mine", "Hogger's camp")  # Blood Saber lifts the mine to 32s/h
    if wow.client == "retail":
        first, second = (
            second,
            first,
        )  # the retail pack prices no saber: linen only, 30 vs 20 an hour
    assert texts[0].startswith(first) and texts[1].startswith(second)
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "2 farm spots for Linen Cloth"
    wow.execute("Bastians:RunAction('gold.prices', 'item:2589', { source = 'test' })")
    texts = [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]
    assert texts[0] == "Price" and any(t.startswith("AH median (") for t in texts)
    assert "Where to farm" in texts
    wow.slash("/bgold spots")
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "3 farm spots"
    wow.execute("Bastians:GetModule('Gold'):Disable()")
    assert wow.eval(f"{WIN}.IsShown()") is False
    assert wow.errors == []


def test_income_per_day_files_ah_apart_from_loot_for_the_account_and_each_character(
    wow: WowRuntime,
):
    """R9: PLAYER_MONEY deltas per day, a gain
    while the mailbox is open is AH, any other gain is loot, a loss is spent; the account's total
    with a line per character on the Today tab; kept in the global saved variables."""
    boot(wow, money=10000)
    INC = f"{MOD}.Income"
    wow.execute("Mock.money = 10500")
    wow.fire("PLAYER_MONEY")
    wow.fire("MAIL_SHOW")
    wow.execute("Mock.money = 12500")
    wow.fire("PLAYER_MONEY")
    wow.fire("MAIL_CLOSED")
    wow.execute("Mock.money = 12200")
    wow.fire("PLAYER_MONEY")
    day = wow.eval(f"{INC}.Day()")
    assert (day.ah, day.loot, day.spent) == (2000, 500, 300)
    me = wow.eval(f"{INC}.CharKey()")
    assert wow.eval(f"{INC}.Day().chars['{me}'].ah") == 2000
    week = wow.eval(f"{INC}.Total(7)")
    assert (week.ah, week.loot, week.spent) == (2000, 500, 300)
    key = wow.eval(f"{INC}.DayKey()")
    assert wow.eval(f"BastiansGoldDB.global.income['{key}'].loot") == 500
    # a login or a zone load is no income
    wow.execute("Mock.money = 99999")
    wow.fire("PLAYER_ENTERING_WORLD", False, True)
    wow.fire("PLAYER_MONEY")
    assert wow.eval(f"{INC}.Day().loot") == 500
    # the Today tab shows the block first: the account, then the character
    wow.slash("/bgold today")
    wow.execute(f"{WIN}.tree.scroll:SetSize(480, 400); {WIN}.tree:Refresh()")
    texts = [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]
    assert texts[0] == "INCOME  gold per day"
    assert texts[1].startswith("Today  AH 20s 00c, loot 5s 00c, spent 3s 00c")
    assert texts[2].startswith("Last 7 days  AH 20s 00c")
    assert texts[3].startswith(me)
    values = [r.value for r in wow.eval(f"{WIN}.tree.flat").values()][1:4]
    assert values == [2500, 2500, 2500]
    # the store survives a reload and is pruned past 60 days
    wow.execute(
        "BastiansGoldDB.global.income['2020-01-01'] = { ah = 1, loot = 1, spent = 0, chars = {} }"
    )
    fresh = wow.reload()
    fresh.execute("Mock.money = 12200")
    fresh.run_frames(3)
    assert fresh.eval(f"BastiansGoldDB.global.income['{key}'].ah") == 2000
    fresh.execute("Mock.money = 12300")
    fresh.fire("PLAYER_MONEY")
    assert fresh.eval("BastiansGoldDB.global.income['2020-01-01']") is None
    assert fresh.errors == []
