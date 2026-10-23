"""Gold's sections and tooltip lines (B6.3): the item Price section from the prices service, tooltip
lines only for known prices (never 0), the NPC Sells section from the own merchant captures."""

import re
from typing import Any

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"


def boot(wow: WowRuntime, *addons: str, realm: str | None = None) -> WowRuntime:
    if realm:
        wow.execute(f'function GetRealmName() return "{realm}" end')
    wow.start(*(addons or (CORE, DATA, GOLD)))
    wow.run_frames(10)
    wow.execute("AuctionHouseFrame:Show()")
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def rows(section) -> list[tuple]:
    return [(strip(r.text), r.value, r.valueKind) for r in section.rows.values()]


def listing(i: int, item: int, count: int, buyout: int) -> dict[str, Any]:
    return {"itemID": item, "count": count, "buyout": buyout, "bid": 0, "owner": f"Seller{i}-Realm"}


def scan(wow: WowRuntime, items: list[dict[str, Any]]) -> None:
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in items])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(10)


def test_unknown_price_is_said_not_shown_as_zero(wow: WowRuntime):
    boot(wow, CORE, GOLD)
    price = sections(wow, "item:1185")["gold.price"]
    assert rows(price) == [("AH price: unknown (no scan, no market data)", None, None)]
    linen = rows(sections(wow, "item:2589")["gold.price"])
    assert linen == [
        ("AH price: unknown (no scan, no market data)", None, None),
        ("Vendor sells for", 13, "money"),  # the client knows the sell price
    ]
    # nothing rather than 0 for the AH price; the vendor line the client knows is there (R9)
    tips = wow.eval("Bastians:GetTooltipRows('item:2589')")
    assert [strip(r.text) for r in tips.values()] == ["Vendor sells for"]
    assert [strip(t["left"]) for t in wow.tooltip("Item", 2589)] == ["Vendor sells for"]
    assert wow.errors == []


def test_price_section_and_tooltip_lines_from_the_own_scan(wow: WowRuntime):
    boot(wow, CORE, GOLD)
    scan(wow, [listing(0, 2589, 20, 600), listing(1, 2589, 1, 10)])
    price = rows(sections(wow, "item:2589")["gold.price"])
    assert price == [
        ("AH median (scan, 0 min ago)", 20, "money"),
        ("AH lowest buyout", 10, "money"),
        ("Listed", 21, "number"),
        ("Vendor sells for", 13, "money"),
    ]
    tips = wow.tooltip("Item", 2589)
    assert [(strip(t["left"]), strip(t["right"])) for t in tips] == [
        ("AH median (scan, 0 min ago)", "20c"),
        ("AH lowest buyout", "10c"),
        ("Vendor sells for", "13c"),  # R9: the vendor line the client knows
    ]
    wow.advance(2 * 3600)
    assert rows(sections(wow, "item:2589")["gold.price"])[0][0] == "AH median (scan, 2 h ago)"
    assert wow.errors == []


def test_price_section_from_the_market_pack_with_its_label(wow: WowRuntime):
    boot(wow, realm="Classic Beta PvE")
    price = rows(sections(wow, "item:2589")["gold.price"])
    if wow.client == "forever":
        assert price[0][0].startswith("AH median (US beta, ")
        assert ("Sales per day", 21.9, "number") in price
        assert ("30-day median", 75, "money") in price
        assert any(t.startswith("30-day range") for t, _, _ in price)
    else:
        assert price[0][0].startswith("AH median (retail EU, ")
    assert price[-1] == ("Vendor sells for", 13, "money")
    tips = [strip(r.text) for r in wow.eval("Bastians:GetTooltipRows('item:2589')").values()]
    gold = [t for t in tips if t.startswith("AH ")]
    assert len(gold) == 2 and gold[0].startswith("AH median (")  # after Data's source lines
    assert all(strip(t["right"]) != "0c" for t in wow.tooltip("Item", 2589) if "right" in t)
    # a scan refreshes the section: the registry drops the cache on BASTIANS_PRICES_UPDATED
    scan(wow, [listing(0, 2589, 1, 55)])
    assert rows(sections(wow, "item:2589")["gold.price"])[0] == (
        "AH median (scan, 0 min ago)",
        55,
        "money",
    )


def test_sells_section_from_the_own_merchant_capture(wow: WowRuntime):
    boot(
        wow, CORE, DATA, "Bastians_Quests", GOLD
    )  # Quests wants the world pack: Data's NPC sections
    assert "gold.sells" not in sections(wow, "npc:54")  # nothing captured yet; Data's list stays
    wow.execute(
        """
        Mock.guids = Mock.guids or {}
        Mock.guids.npc = "Creature-0-4469-0-12-54-0000ABCDEF"
        Mock.unitNames = { npc = "Corina Steelrock" }
        Mock.merchant = {
          { itemID = 2589, name = "Linen Cloth", price = 260, stackCount = 20, numAvailable = -1 },
          { itemID = 1185, name = "Blood Saber", price = 1000, stackCount = 1, numAvailable = 2 },
        }
        """
    )
    wow.fire("MERCHANT_SHOW")
    wow.advance(0.6)
    sells = sections(wow, "npc:54")["gold.sells"]
    assert sells.title == "Sells (seen)"
    got = [(strip(r.text), r.ref, r.value, r.valueKind) for r in sells.rows.values()]
    linen = (
        "Linen Cloth x20" if wow.client == "forever" else "Linen Cloth x20  AH 40c"
    )  # retail: pack
    assert got == [
        (linen, "item:2589", 13, "money"),  # 260 for 20: the unit price
        ("Blood Saber (2 in stock)", "item:1185", 1000, "money"),
        ("seen 0 min ago", None, None, None),
    ]
    scan(wow, [listing(0, 2589, 1, 38)])
    got = [strip(r.text) for r in sections(wow, "npc:54")["gold.sells"].rows.values()]
    assert got[0] == "Linen Cloth x20  AH 38c"
    assert [s for s in sections(wow, "npc:54")] == [
        "data.overview",
        "data.spawns",
        "data.vendor",
        "gold.sells",
        "data.zone",
    ]
    assert wow.errors == []


def test_the_vendor_line_shows_without_auction_data_and_the_setting_turns_it_off(
    wow: WowRuntime,
):
    """R9: retail has no market data, so the tooltip said nothing;
    the vendor sell price the client knows is a line of its own, off through the setting."""
    boot(wow, CORE, GOLD)
    tips = wow.tooltip("Item", 2589)
    assert [(strip(t["left"]), strip(t["right"])) for t in tips] == [("Vendor sells for", "13c")]
    wow.execute("Bastians:GetModule('Gold').db.profile.tooltipSell = false")
    wow.execute("Bastians:Fire('BASTIANS_PRICES_UPDATED', 'test')")
    assert wow.tooltip("Item", 2589) == []
    assert wow.errors == []
