"""The bag advisor (gold.md "Bag advisor", S4, 22.10.2026): per bag item post, vendor or keep with
the reason (pure over plain tables), the Bags tab of the Gold window from the client's bag slots,
the window that opens with a merchant or the auction house and closes with it, the setting."""

import re
from typing import Any

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"
MOD = "Bastians:GetModule('Gold')"
ADV = f"{MOD}.Advisor"
WIN = f"{MOD}.Window"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, GOLD)))
    wow.run_frames(10)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def advise(wow: WowRuntime, item: str, opts: str = "nil") -> tuple:
    a = wow.eval(f"{ADV}.Advise({item}, {opts})")
    return a.verdict, strip(a.reason), a.unit, a.total


def listing(i: int, item: int, count: int, buyout: int) -> dict[str, Any]:
    return {"itemID": item, "count": count, "buyout": buyout, "bid": 0, "owner": f"Seller{i}-Realm"}


def scan(wow: WowRuntime, items: list[dict[str, Any]]) -> None:
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in items])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(10)


def texts(wow: WowRuntime) -> list[str]:
    wow.execute(f"{WIN}.tree.scroll:SetSize(480, 400); {WIN}.tree:Refresh()")
    return [strip(r.text) for r in wow.eval(f"{WIN}.tree.flat").values()]


def test_the_verdicts_with_their_reasons_never_invent_a_price(wow: WowRuntime):
    boot(wow, CORE, GOLD)
    # grey: the vendor, the known price; without one, keep and say so
    assert advise(wow, "{ count = 3, quality = 0, sell = 13 }") == (
        "vendor",
        "grey, the vendor pays 13c",
        13,
        39,
    )
    assert advise(wow, "{ count = 1, quality = 0 }") == (
        "keep",
        "grey, no vendor price known",
        None,
        None,
    )
    # soulbound: keep, the vendor price as a note
    assert advise(wow, "{ count = 1, quality = 2, bound = true, sell = 500 }") == (
        "keep",
        "soulbound (a vendor would pay 5s 00c)",
        None,
        None,
    )
    # no AH price: keep, with the vendor price when known; nothing is 0
    assert advise(wow, "{ count = 5, quality = 1, sell = 13 }") == (
        "keep",
        "AH price unknown, the vendor pays 13c",
        None,
        None,
    )
    assert advise(wow, "{ count = 5, quality = 1, noValue = true }") == (
        "keep",
        "cannot be sold",
        None,
        None,
    )
    assert advise(wow, "{ count = 5, quality = 1 }") == ("keep", "price unknown", None, None)
    # the AH net (after the 5 % cut) against the vendor: post when it beats the vendor by a quarter
    assert advise(wow, "{ count = 20, quality = 1, sell = 13, price = { median = 100 } }") == (
        "post",
        "AH 95c after the cut, the vendor pays 13c",
        95,
        1900,
    )
    assert advise(wow, "{ count = 2, quality = 1, sell = 100, price = { median = 90 } }") == (
        "vendor",
        "AH 86c after the cut, below the vendor's 1s 00c",
        100,
        200,
    )
    assert advise(wow, "{ count = 2, quality = 1, sell = 100, price = { median = 120 } }") == (
        "vendor",
        "AH 1s 14c after the cut, barely above the vendor's 1s 00c",
        100,
        200,
    )
    # slow sales: the vendor now, unless the vendor pays nothing
    assert advise(
        wow, "{ count = 1, quality = 1, sell = 10, price = { median = 1000, salesPerDay = 0.2 } }"
    ) == ("vendor", "sells 0.2 a day on the AH; the vendor pays 10c now", 10, 10)
    assert advise(
        wow, "{ count = 1, quality = 1, price = { median = 1000, salesPerDay = 0.2 } }"
    ) == (
        "post",
        "AH 9s 50c after the cut, no vendor value, slow (0.2 a day)",
        950,
        950,
    )
    # a stale scan is said
    assert advise(
        wow, "{ count = 1, quality = 1, sell = 10, price = { median = 1000, stale = true } }"
    )[1] == ("AH 9s 50c after the cut, the vendor pays 10c (stale scan)")
    # the groups: totals only where a value is known
    g = wow.eval(
        f"{ADV}.Build({{ {{ name = 'a', count = 2, quality = 0, sell = 10 }}, "
        "{ name = 'b', count = 1, quality = 1 }, { name = 'c', count = 1, quality = 0, sell = 50 } })"
    )
    # a Lua field named `items` must be indexed: `.items` is the lupa table method
    assert [a.item.name for a in g.vendor["items"].values()] == ["c", "a"] and g.vendor.total == 70
    assert [a.item.name for a in g.keep["items"].values()] == ["b"] and g.keep.total is None
    assert len(g.post["items"]) == 0 and g.post.total is None
    assert wow.errors == []


def test_the_bags_tab_lists_the_slots_by_verdict_with_the_item_icons(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.items[2592] = { name = 'Wool Cloth', quality = 1, level = 15, class = 'Tradeskill', sell = 50, "
        "stack = 20, icon = 132890 }; "
        "Mock.items[7073] = { name = 'Broken Fang', quality = 0, level = 1, class = 'Junk', sell = 7, stack = 5, "
        "icon = 133712 }; "
        "Mock.bagSlots[0] = { [1] = { itemID = 2589, count = 20 }, [3] = { itemID = 7073, count = 2 }, "
        "[5] = { itemID = 6948, count = 1, bound = true }, [6] = { itemID = 2592, count = 4 } }"
    )
    wow.execute("AuctionHouseFrame:Show()")
    scan(wow, [listing(1, 2589, 20, 2000), listing(2, 2589, 20, 2400), listing(3, 2592, 1, 10)])
    wow.slash("/bgold bags")
    rows = texts(wow)
    assert rows[0].startswith("POST ON THE AUCTION HOUSE  expected after the cut")
    assert (
        rows[1] == "Linen Cloth x20  AH 1s 05c after the cut, the vendor pays 13c"
    )  # median 1s 10c
    assert rows[2].startswith("SELL TO A VENDOR  the vendor pays")
    assert rows[3] == "Wool Cloth x4  AH 10c after the cut, below the vendor's 50c"
    assert rows[4] == "Broken Fang x2  grey, the vendor pays 7c"
    assert rows[5].startswith("KEEP  nothing to gain by selling")
    assert rows[6] == "Hearthstone  soulbound"
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "4 items: post 1, vendor 2, keep 1"
    flat = list(wow.eval(f"{WIN}.tree.flat").values())
    assert flat[1].ref == "item:2589" and flat[1].icon == 132889 and flat[1].value == 2100
    assert flat[0].value == 2100 and flat[2].value == 214 and flat[5].value is None
    # the bags change: the tab re-renders (coalesced), another tab does not
    wow.execute("Mock.bagSlots[0][1] = nil")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(0.2)
    rows = texts(wow)
    assert rows[0].startswith("SELL TO A VENDOR") and "Linen" not in " ".join(rows)
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "3 items: post 0, vendor 2, keep 1"
    wow.execute("Mock.bagSlots = {}")
    wow.fire("BAG_UPDATE_DELAYED")
    wow.advance(0.2)
    assert texts(wow) == ["Your bags are empty."]
    assert wow.errors == []


def test_the_window_opens_with_a_shop_and_closes_with_it_unless_the_player_had_it(
    wow: WowRuntime,
):
    boot(wow, CORE, GOLD)
    wow.execute("Mock.bagSlots[0] = { [1] = { itemID = 2589, count = 5 } }")
    assert wow.eval(f"{WIN}.IsShown()") is False
    wow.fire("MERCHANT_SHOW")
    assert wow.eval(f"{WIN}.IsShown()") is True and wow.eval(f"{MOD}.db.profile.view") == "bags"
    assert texts(wow)[1] == "Linen Cloth x5  AH price unknown, the vendor pays 13c"
    wow.fire("MERCHANT_CLOSED")
    assert wow.eval(f"{WIN}.IsShown()") is False
    # the auction house the same way
    wow.fire("AUCTION_HOUSE_SHOW")
    assert wow.eval(f"{WIN}.IsShown()") is True
    wow.fire("AUCTION_HOUSE_CLOSED")
    assert wow.eval(f"{WIN}.IsShown()") is False
    # the player had the window open: the shop's close leaves it
    wow.slash("/bgold today")
    wow.fire("MERCHANT_SHOW")
    assert wow.eval(f"{MOD}.db.profile.view") == "today"
    wow.fire("MERCHANT_CLOSED")
    assert wow.eval(f"{WIN}.IsShown()") is True
    wow.execute(f"{WIN}.Hide()")
    # closed by hand while the shop is open: the shop's close has nothing to close
    wow.fire("MERCHANT_SHOW")
    assert wow.eval(f"{WIN}.IsShown()") is True
    wow.execute(f"{WIN}.Hide()")
    wow.slash("/bgold today")
    wow.fire("MERCHANT_CLOSED")
    assert wow.eval(f"{WIN}.IsShown()") is True
    wow.execute(f"{WIN}.Hide()")
    # the setting off: nothing opens; /bgold bags still does
    wow.execute(f"{MOD}.db.profile.advisorAuto = false")
    wow.fire("MERCHANT_SHOW")
    assert wow.eval(f"{WIN}.IsShown()") is False
    wow.slash("/bgold bags")
    assert wow.eval(f"{WIN}.IsShown()") is True and wow.eval(f"{MOD}.db.profile.view") == "bags"
    assert wow.errors == []
