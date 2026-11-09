"""The Bags view (ADR 0058, PH6; catalog review A5.4): one answer per bag item with the reason:
sell, auction, disenchant, mail to a character who asked, keep. The answer is pure; what Alts
and Helpers know comes through Core's services, so without them there is no mail and no never-sell
answer. Sell and Mail happen where they can: Helpers at the vendor, Alts at the mailbox."""

import re
from typing import Any

from harness import WowRuntime

CORE, DATA, GOLD, ALTS, HELPERS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Gold",
    "Bastians_Alts",
    "Bastians_Helpers",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Gold')"
ADV = f"{MOD}.Advisor"
BR = "Bastians:GetModule('Browser')"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, GOLD)))
    wow.run_frames(10)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def answer(wow: WowRuntime, item: str, ctx: str = "nil") -> tuple:
    a = wow.eval(f"{ADV}.Answer({item}, {ctx})")
    return a.answer, strip(a.reason), a.total, a.to


def listing(i: int, item: int, count: int, buyout: int) -> dict[str, Any]:
    return {"itemID": item, "count": count, "buyout": buyout, "bid": 0, "owner": f"Seller{i}-Realm"}


def scan(wow: WowRuntime, items: list[dict[str, Any]]) -> None:
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in items])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(10)


def test_one_answer_per_item_with_its_reason(wow: WowRuntime):
    boot(wow, CORE, GOLD)
    grey = "{ itemID = 1, count = 3, quality = 0, sell = 7 }"
    assert answer(wow, grey) == ("sell", "grey, the vendor pays 7c", 21, None)
    assert answer(wow, grey, "{ neverSell = true }") == (
        "keep",
        "on your never-sell list",
        None,
        None,
    )
    # a character who asked wins over everything
    assert answer(wow, grey, "{ wanted = { name = 'Burlina', count = 2 } }") == (
        "mail",
        "Burlina asked for 2 of these",
        None,
        "Burlina",
    )
    # the AH after the cut beats the vendor: auction
    cloth = "{ itemID = 2589, count = 20, quality = 1, sell = 13, price = { median = 110, salesPerDay = 5 } }"
    assert answer(wow, cloth)[0] == "auction"
    # disenchanting beats the way found: disenchant; soulbound never
    weapon = "{ itemID = 7, count = 1, quality = 2, sell = 38, price = { median = 50, salesPerDay = 5 } }"
    assert answer(wow, weapon, "{ disenchant = 120 }") == (
        "disenchant",
        "disenchanting brings 1s 20c, the vendor pays 38c",
        120,
        None,
    )
    assert answer(wow, weapon, "{ disenchant = 20 }")[0] == "sell"  # the vendor pays more
    bound = "{ itemID = 7, count = 1, quality = 2, bound = true, sell = 38 }"
    assert answer(wow, bound, "{ disenchant = 120 }")[0] == "keep"
    # no price known: keep, with the reason; never a figure
    assert answer(wow, "{ itemID = 9, count = 1, quality = 1 }") == (
        "keep",
        "price unknown",
        None,
        None,
    )
    assert wow.errors == []


def test_the_bags_tab_of_the_atlas_lists_every_slot_with_its_answer(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD, ALTS, HELPERS, BROWSER)
    wow.execute(
        "Mock.items[7073] = { name = 'Broken Fang', quality = 0, level = 1, class = 'Junk', sell = 7, stack = 5, "
        "icon = 133712 }; "
        "Mock.items[2592] = { name = 'Wool Cloth', quality = 1, level = 15, class = 'Tradeskill', sell = 50, "
        "stack = 20, icon = 132890 }; "
        "Mock.bagSlots[0] = { [1] = { itemID = 2589, count = 20 }, [3] = { itemID = 7073, count = 2 }, "
        "[6] = { itemID = 2592, count = 4 } }"
    )
    wow.execute("AuctionHouseFrame:Show()")  # a scan needs the house open, as the advisor test
    scan(wow, [listing(1, 2589, 20, 2000), listing(2, 2589, 20, 2400)])
    # Helpers' never-sell list and a request of another character reach Gold through services
    wow.execute("Bastians:GetModule('Helpers').Helpers.NeverSell(7073, true)")
    assert wow.eval("Bastians:GetService('requests') ~= nil") is True
    assert wow.eval("Bastians:GetService('neversell'):Is(7073)") is True
    wow.execute(f"{BR}.Browser.OpenWindow()")
    wow.execute("Bastians:ShowView('gold.bags')")
    wow.run_frames(10)
    assert wow.eval(f"{BR}.Browser.Current().id") == "gold.bags"
    rows = [
        (strip(r.text), strip(r.badge or ""), str(r.answer))
        for r in wow.eval(f"{BR}.tree.flat").values()
        if r.ref
    ]
    assert rows[0][0] == "Linen Cloth x20" and rows[0][2] == "auction" and rows[0][1] == "Auction"
    assert rows[1] == ("Broken Fang x2", "Keep", "keep")  # on the never-sell list
    assert rows[2][0] == "Wool Cloth x4" and rows[2][2] in ("sell", "keep")
    words = strip(wow.eval(f"{BR}.summary:GetText()"))
    assert words.startswith("3 items: ") and "1 to auction" in words
    # the Bags tab stands in the Gold section
    assert any(
        c.id == "nav:view:gold.bags" for c in wow.eval(f"{BR}.Browser.Categories()").values()
    )
    assert wow.eval(f"{BR}.Browser.SectionOf('nav:view:gold.bags')") == "gold"
    assert wow.errors == []


def test_without_alts_and_helpers_the_answers_stand_alone(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    wow.execute(
        "Mock.items[7073] = { name = 'Broken Fang', quality = 0, level = 1, class = 'Junk', sell = 7, stack = 5 }; "
        "Mock.bagSlots[0] = { [3] = { itemID = 7073, count = 2 } }"
    )
    answers = wow.eval(f"{ADV}.Answers()")
    assert [a.answer for a in answers.values()] == ["sell"]  # no never-sell list, no requests
    assert wow.errors == []
