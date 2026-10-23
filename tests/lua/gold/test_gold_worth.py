"""The worth of items, mobs, nodes, farm spots and strategies (C3, ADR 0014): AH median with its
age and the vendor price, loot value per kill, the node's item price, gold per hour with the
status. Unknown prints "price unknown", never 0. Pure functions, then the provider on the fixture
world with the market pack and an own scan."""

import re
from typing import Any

from harness import WowRuntime

CORE, DATA, QUESTS, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Gold"
WORTH = "Bastians:GetModule('Gold').Worth"


def strip(text: str | None) -> str:
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text or "")
    return text.replace("|r", "")


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, QUESTS, GOLD)))
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute("AuctionHouseFrame:Show()")
    return wow


def listing(i: int, item: int, count: int, buyout: int) -> dict[str, Any]:
    return {"itemID": item, "count": count, "buyout": buyout, "bid": 0, "owner": f"Seller{i}-Realm"}


def scan(wow: WowRuntime, items: list[dict[str, Any]]) -> None:
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in items])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(10)


def worth(wow: WowRuntime, ref: str):
    w = wow.eval(f"Bastians:Entity('{ref}'):Worth()")
    return (strip(w.text), w.copper) if w is not None else None


def test_the_pure_worth_lines(core: WowRuntime):
    core.start(GOLD)
    core.run_frames(5)
    core.execute(
        f"""
        W = {WORTH}
        prices = {{ [2589] = 38, [1185] = 5000 }}
        local function priceOf(id) return prices[id] end
        item = W.item({{ median = 1230, age = 200 }}, 5)
        itemNoAge = W.item({{ median = 1230 }}, nil)
        itemVendor = W.item(nil, 5)
        itemNone = W.item(nil, nil)
        mob = W.mob({{ {{ 2589, 45.5 }}, {{ 1185, 3.2 }}, {{ 999, 10 }} }}, priceOf)
        mobNone = W.mob({{ {{ 999, 10 }} }}, priceOf)
        noLoot = W.mob({{}}, priceOf)
        node = W.node(2589, priceOf)
        nodeNone = W.node(999, priceOf)
        spot = W.spot(123456, 0, "verified")
        spotNone = W.spot(nil, 2, nil)
        """
    )
    assert strip(core.eval("item.text")) == "AH 12s 30c (3 min ago) - vendor 5c"
    assert core.eval("item.copper") == 1230
    assert strip(core.eval("itemNoAge.text")) == "AH 12s 30c"
    assert (
        strip(core.eval("itemVendor.text")) == "vendor 5c" and core.eval("itemVendor.copper") == 5
    )
    assert (
        strip(core.eval("itemNone.text")) == "price unknown"
        and core.eval("itemNone.copper") is None
    )
    # 38 x 0.455 + 5000 x 0.032 = 177.29 -> 177 copper; one item without a price is said
    assert strip(core.eval("mob.text")) == "~1s 77c per kill (1 items without price)"
    assert core.eval("mob.copper") == 177
    assert (
        strip(core.eval("mobNone.text")) == "loot price unknown"
        and core.eval("mobNone.copper") is None
    )
    assert core.eval("noLoot") is None
    assert strip(core.eval("node.text")) == "AH 38c" and core.eval("node.copper") == 38
    assert strip(core.eval("nodeNone.text")) == "price unknown"
    assert (
        strip(core.eval("spot.text")) == "12.3g/h, verified" and core.eval("spot.copper") == 123456
    )
    assert (
        strip(core.eval("spotNone.text")) == "gold/h unknown, (2 items without price), unverified"
    )
    assert core.errors == []


def test_the_provider_reads_the_market_pack_and_the_own_scan(wow: WowRuntime):
    boot(wow)
    text, copper = worth(wow, "item:2589")
    linen = 38 if wow.client == "forever" else 40  # the market pack: forever EU, retail EU
    assert text.startswith(f"AH {linen}c") and copper == linen
    assert "vendor 13c" in text  # Data's sell price
    # Hogger: linen 45.5 %, Blood Saber 3.2 % (50g on Forever, no retail price)
    mob = worth(wow, "npc:448")[0]
    if wow.client == "forever":
        assert mob.startswith("~1s 77c per kill")
    else:
        assert mob == "~18c per kill (1 items without price)"
    assert worth(wow, "npc:240") is None  # no loot: no worth line for a quest giver
    assert worth(wow, "spot:1")[0].endswith("verified") or "unverified" in worth(wow, "spot:1")[0]
    assert worth(wow, "item:424242")[0] == "price unknown"
    # an own scan replaces the market median and drops the cached worth through the message
    scan(wow, [listing(0, 2589, 1, 50)])
    wow.advance(0.1)
    text, copper = worth(wow, "item:2589")
    assert text.startswith("AH 50c") and copper == 50
    assert worth(wow, "npc:448")[1] not in (177, 18)  # the mob's value follows the price
    assert wow.errors == []


def test_rows_show_the_worth_in_gold_where_they_have_no_value(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(400, 200)
        tree = Bastians.UI.Tree(host, {})
        tree.scroll:SetSize(386, 200)
        tree:SetRows({ { text = "Linen", ref = "item:2589" }, { text = "Linen", ref = "item:2589", value = 7, valueKind = "number" },
          { text = "Dughan", ref = "npc:240" }, { text = "Linen", ref = "item:2589", worth = false } })
        """
    )
    assert strip(wow.eval("tree.pool[1].value:GetText()")).startswith("AH ")
    assert wow.eval("tree.pool[1].value:IsShown()") is True
    r, g, b, _ = wow.eval("tree.pool[1].value:GetTextColor()")
    assert (round(r, 2), round(g, 2), b) == (1, 0.82, 0)
    assert wow.eval("tree.pool[2].value:GetText()") == "7"  # an own value wins
    assert wow.eval("tree.pool[3].value:IsShown()") is False  # nothing to say
    assert wow.eval("tree.pool[4].value:IsShown()") is False  # the row opted out
    assert wow.errors == []
