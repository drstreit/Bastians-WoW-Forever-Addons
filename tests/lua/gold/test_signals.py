"""Gold's signals as things and activities (gold.md "Signals as activities", W10 step 2): a sell or
craft signal is an entity named after its action and item, placed at the nearest auction house
(a farm signal at its spot), with the activity facet Explore lists; Explore is offered the signals
Today would list for this character and nothing else."""

import re

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
US = "signal:forever/normal/alliance/us"


def boot(wow: WowRuntime, money: int = 1000000, professions: str = "{}") -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.execute(f"Mock.money = {money}; Mock.professions = {professions}")
    wow.start(CORE, DATA, GOLD)
    wow.run_frames(10)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')  # the auctioneer's place
    wow.run_frames(5)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def candidates(wow: WowRuntime) -> list[str]:
    refs = wow.eval("Bastians:FacetCandidates('activity')").values()
    return sorted(r for r in refs if r.startswith("signal:"))


def test_a_sell_signal_is_a_thing_at_the_auction_house(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"Bastians:Entity('{US}:1'):Name()") == "Sell Linen Cloth"
    assert strip(wow.eval(f"Bastians:Entity('{US}:1'):Summary()")).startswith("+8s, 5 min")
    locs = wow.eval(f"Bastians:Entity('{US}:1'):Locations()")
    assert (locs[1].map, locs[1].x, locs[1].y) == (1429, 0.425, 0.645)  # Auctioneer Fitch
    farm = wow.eval(f"Bastians:Entity('{US}:2'):Locations()")
    assert (farm[1].map, farm[1].x) == (1429, 0.27)  # Hogger's camp, the signal's spot
    act = wow.eval(f"Bastians:Entity('{US}:1'):Facet('activity')")
    assert (act.kind, act.takes, act.gives[1].amount, act.consumes) == ("flip", 300, 800, None)
    craft = wow.eval(f"Bastians:Entity('{US}:3'):Facet('activity')")
    assert (craft.kind, craft.consumes[1].amount, craft.window.to) == ("craft", 5000, 1760090000)
    assert wow.eval(f"Bastians:Entity('{US}:4'):Facet('activity')") is None  # avoid: nothing to do
    assert wow.eval(f"Bastians:Entity('{US}:2'):Facet('activity')") is None  # farm: the spot is
    assert wow.errors == []


def test_explore_is_offered_the_signals_today_would_list(wow: WowRuntime):
    boot(wow, professions="{ Leatherworking = 150 }")
    # not 2 (farm), 4 (avoid), 7 (expired)
    assert candidates(wow) == [f"{US}:1", f"{US}:3", f"{US}:5", f"{US}:6"]
    assert wow.errors == []


def test_what_the_character_cannot_do_or_afford_is_not_offered(wow: WowRuntime):
    boot(wow)  # no profession: the two crafts are out
    assert candidates(wow) == [f"{US}:1", f"{US}:5"]
    assert wow.errors == []


def test_what_the_character_cannot_afford_is_not_offered(wow: WowRuntime):
    boot(wow, money=1000, professions="{ Leatherworking = 150 }")
    assert candidates(wow) == [f"{US}:1", f"{US}:5"]  # 3 binds 50s, 6 binds 20g
    assert wow.errors == []
