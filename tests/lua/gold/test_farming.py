"""Your own rate at a farm spot (gold.md "Your own rate at a spot", catalog review A5.6,
07.11.2026): kills, loot and money inside the spot's radius add up per character, the farmed time
is the time between events, the rate shows from 20 kills, nothing counts outside a spot; the pure
rate rule."""

import re

from harness import WowRuntime
from test_prices import listing, scan

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
F = f"{MOD}.Farming"
ME = "Player-1-00000001"
HOGGER = "Creature-0-1-0-1-448-0000000001"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.execute("Mock.money = 1000")
    wow.start(CORE, DATA, GOLD)
    wow.run_frames(10)
    wow.execute("Bastians:GetService('data'):LoadPack('world')")
    wow.execute("AuctionHouseFrame:Show()")
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def kill(wow: WowRuntime) -> None:
    wow.fire("PARTY_KILL", ME, HOGGER)


def spot_rows(wow: WowRuntime) -> list[tuple[str, int | None]]:
    section = {s.id: s for s in wow.eval("Bastians:GetDetailSections('spot:1')").values()}[
        "gold.strategy"
    ]
    return [(strip(r.text), r.value) for r in section.rows.values()]


def test_kills_loot_and_money_inside_the_spot_make_your_rate(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(1, 2589, 1, 20)])  # Linen Cloth at 20c
    # Hogger's camp: 1429 (0.27, 0.86), radius 120 yards; the character stands in it
    wow.execute("Mock.playerMap = 1429; Mock.playerMapPos = { x = 0.27, y = 0.86 }")
    assert wow.eval(f"{F}.SpotHere().id") == 1
    for _ in range(19):
        kill(wow)
        wow.advance(30)
    r = wow.eval(f"{F}.Record(1)")
    assert (r.kills, r.sessions, r.seconds) == (19, 1, 18 * 30)
    assert any(t.startswith("Your rate here") and v is None for t, v in spot_rows(wow))
    assert any("after 20 kills; 19 so far" in t for t, _ in spot_rows(wow))
    # the loot and the money of the camp
    wow.execute(
        "Mock.loot = { fishing = false, slots = { { item = 2589, name = 'Linen Cloth', quantity = 2, source = '"
        + HOGGER
        + "' } } }"
    )
    wow.fire("LOOT_OPENED")
    wow.fire("LOOT_SLOT_CLEARED", 1)
    wow.execute("Mock.Fire('PLAYER_MONEY')")  # the first look at the money is no delta
    wow.execute("Mock.money = 1100; Mock.Fire('PLAYER_MONEY')")
    kill(wow)  # the twentieth
    r = wow.eval(f"{F}.Record(1)")
    assert (r.kills, r["items"], r.money, r.unpriced) == (20, 40, 100, 0)
    rate = wow.eval(f"({F}.Rate({F}.Record(1)))")
    assert rate == round(
        140 / (19 * 30) * 3600
    )  # 19 gaps of 30 s: the loot came 30 s after the 19th kill
    wow.advance(6)  # the section follows the coalesced BASTIANS_GOLD_FARMING (5 s)
    rows = spot_rows(wow)
    assert ("Your rate here (10 min, 20 kills)", rate) in rows
    assert rows[0][0].startswith("Gold per hour")  # the claim's figure stays first
    # a long pause starts a new session: the pause is not farmed time
    wow.advance(3600)
    kill(wow)
    r = wow.eval(f"{F}.Record(1)")
    assert (r.sessions, r.seconds) == (2, 19 * 30)
    assert wow.errors == []


def test_nothing_counts_outside_a_spot_or_from_others_or_from_the_mail(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.playerMap = 1429; Mock.playerMapPos = { x = 0.6, y = 0.4 }")  # the lake
    assert wow.eval(f"{F}.SpotHere()") is None
    kill(wow)
    wow.execute("Mock.money = 1100; Mock.Fire('PLAYER_MONEY')")
    assert wow.eval(f"{F}.Record(1)") is None and wow.eval(f"{F}.Record(2)") is None
    wow.execute("Mock.playerMapPos = { x = 0.27, y = 0.86 }")
    wow.fire("PARTY_KILL", "Player-1-00000009", HOGGER)  # not my kill
    assert wow.eval(f"{F}.Record(1)") is None
    wow.execute(f"{MOD}.Income.Register({MOD})")  # the mailbox open: a gain is the auction house
    wow.fire("MAIL_SHOW")
    wow.execute("Mock.money = 1300; Mock.Fire('PLAYER_MONEY')")
    assert wow.eval(f"{F}.Record(1)") is None
    assert wow.errors == []


def test_the_rate_is_pure_and_unknown_before_twenty_kills(core: WowRuntime):
    core.start(CORE, GOLD)
    assert (
        core.eval(f"{F}.Rate({{ kills = 20, seconds = 1800, money = 500, items = 400 }})") == 1800
    )
    assert core.eval(f"({F}.Rate({{ kills = 19, seconds = 1800, money = 500 }}))") is None
    assert core.eval(f"select(2, {F}.Rate({{ kills = 19, seconds = 1800 }}))") == "kills"
    assert core.eval(f"select(2, {F}.Rate({{ kills = 25, seconds = 30 }}))") == "time"
    assert core.eval(f"({F}.Rate(nil))") is None
    assert core.errors == []
