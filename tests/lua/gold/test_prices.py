"""The prices service (B6.2): market detection from realm and faction, the own scan when fresh, the
Market pack otherwise, a stale scan flagged, nil when nothing is known; the summary survives /reload."""

from typing import Any

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"


def listing(i: int, item: int, count: int, buyout: int) -> dict[str, Any]:
    return {"itemID": item, "count": count, "buyout": buyout, "bid": 0, "owner": f"Seller{i}-Realm"}


def boot(wow: WowRuntime, *addons: str, realm: str | None = None) -> WowRuntime:
    if realm:
        wow.execute(f'function GetRealmName() return "{realm}" end')
    wow.start(*(addons or (CORE, GOLD)))
    wow.run_frames(10)
    wow.execute("AuctionHouseFrame:Show()")
    return wow


def scan(wow: WowRuntime, rows: list[dict[str, Any]]) -> None:
    clean = [{k: v for k, v in r.items() if v is not None} for r in rows]
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in clean])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(10)


def price(wow: WowRuntime, item: int):
    return wow.eval(f"Bastians:GetService('prices'):Price({item})")


def test_market_detection_from_realm_and_faction(wow: WowRuntime):
    boot(wow)
    m = wow.eval("Bastians:GetService('prices'):Market()")
    if wow.client == "forever":
        assert (m.id, m.known, m.realm) == ("forever/normal/alliance/unknown", False, "Mock Realm")
    else:
        assert (m.id, m.known) == ("retail/normal/neutral/eu", True)
    note = wow.eval("Bastians:GetModule('Gold').Prices.Note()")
    assert "no own scan yet" in note and "no market data yet" in note
    assert price(wow, 2589) is None  # nothing known: nil, never 0


def test_known_beta_realm_maps_to_the_us_normal_market(wow: WowRuntime):
    boot(wow, realm="Classic Beta PvE")
    m = wow.eval("Bastians:GetService('prices'):Market()")
    if wow.client == "forever":
        assert (m.id, m.known, m.ruleset, m.region) == (
            "forever/normal/alliance/us",
            True,
            "normal",
            "us",
        )
    else:
        assert m.id == "retail/normal/neutral/eu"


def test_own_scan_gives_unit_medians_and_fires_prices_updated(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        updates = {}
        local w = Bastians:NewModule("PriceWatcher", { addon = "Bastians_Gold" })
        w:On("BASTIANS_PRICES_UPDATED", function(_, _, source) updates[#updates + 1] = source end)
        """
    )
    scan(
        wow,
        [
            listing(0, 2589, 20, 600),  # 30 per unit
            listing(1, 2589, 1, 10),  # 10
            listing(2, 2589, 5, 100),  # 20
            listing(3, 2589, 3, 0),  # bid only: no price
            listing(4, 1185, 1, 4000),
        ],
    )
    assert list(wow.g.updates.values()) == ["scan"]
    p = price(wow, 2589)
    assert (p.median, p.minBuyout, p.quantity, p.source, p.stale, p.salesPerDay) == (
        20,
        10,
        26,
        "scan",
        None,
        None,
    )
    assert p.age == 0
    assert price(wow, 1185).median == 4000
    assert price(wow, 424242) is None
    status = wow.eval("Bastians:GetService('prices'):Status()")
    assert status.scan["items"] == 2 and status.pack is None  # lupa: .items is the dict method
    assert "own scan: 2 items, 0 min old" in wow.eval("Bastians:GetModule('Gold').Prices.Note()")


def test_fresh_scan_beats_the_pack_and_a_stale_scan_yields_to_it(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD, realm="Classic Beta PvE")
    assert wow.eval("Bastians:GetService('data'):PackLoaded('market')") is True  # Gold wants it
    p = price(wow, 2589)
    assert (p.median, p.minBuyout, p.source) == (
        (38, 20, "market") if wow.client == "forever" else (40, 25, "market")
    )
    if wow.client == "forever":
        assert (p.salesPerDay, p.median30d, p.label) == (21.9, 75, "US beta")
        assert price(wow, 1185).salesPerDay is None  # unknown stays nil in the pack too
    assert p.age == wow.eval("GetServerTime()") - 1760000000
    scan(wow, [listing(0, 2589, 1, 55)])
    p = price(wow, 2589)
    assert (p.median, p.source) == (55, "scan")  # fresh own scan first
    wow.advance(25 * 3600)
    p = price(wow, 2589)
    assert p.source == "market"  # the scan is older than a day
    wow.execute("Bastians:GetModule('Gold').db.profile.scanMaxAgeHours = 48")
    assert price(wow, 2589).source == "scan"
    status = wow.eval("Bastians:GetService('prices'):Status()")
    assert status.pack.label in ("US beta", "retail EU") and status.scan["items"] == 1


def test_stale_scan_is_the_last_resort_and_is_flagged(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(0, 2589, 2, 40)])
    wow.advance(30 * 3600)
    p = price(wow, 2589)
    assert (p.median, p.source, p.stale) == (20, "scan", True)
    assert p.age >= 30 * 3600


def test_summary_is_rebuilt_from_the_saved_dump_after_reload(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(0, 2589, 4, 100), listing(1, 2589, 1, 30)])
    fresh = wow.reload()
    fresh.run_frames(10)
    p = fresh.eval("Bastians:GetService('prices'):Price(2589)")
    assert (p.median, p.minBuyout, p.quantity) == (27, 25, 5)  # (25 + 30) / 2 rounded down
    assert fresh.errors == []


def test_service_is_gone_while_gold_is_disabled(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:GetService('prices')") is not None
    wow.execute("Bastians:GetModule('Gold'):Disable()")
    assert wow.eval("Bastians:GetService('prices')") is None
    wow.execute("Bastians:GetModule('Gold'):Enable()")
    assert wow.eval("Bastians:GetService('prices'):Market() ~= nil") is True
    assert wow.errors == []


def test_an_eu_market_reads_the_us_beta_rows_through_its_alias(wow: WowRuntime):
    """Before launch the EU markets have no rows; the Market pack points them at a US beta market
    (`market.list[eu].alias`, 23.10.2026: copies had tripled the pack with the first real export).
    An RP Alliance player in the EU reads the US normal Alliance prices, labelled US beta."""
    if wow.client != "forever":
        return
    boot(wow, CORE, DATA, GOLD)
    wow.execute(
        "local P = Bastians:GetModule('Gold').Prices; "
        "P.REALMS['Mock Realm'] = { ruleset = 'rp', region = 'eu' }; P.DetectMarket()"
    )
    wow.run_frames(10)
    assert wow.eval("Bastians:GetService('prices'):Market().id") == "forever/rp/alliance/eu"
    assert (
        wow.eval("Bastians:GetModule('Gold').Prices.PackMarket()") == "forever/normal/alliance/us"
    )
    p = price(wow, 2589)
    assert (p.median, p.source, p.label) == (38, "market", "US beta")
    assert wow.errors == []
