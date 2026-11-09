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


def test_live_rp_realm_maps_to_the_eu_rp_market(wow: WowRuntime):
    """The live client reports an internal realm name (measured 05.11.2026, build 70790); the realm
    list shows it as "EU - RP PvE"."""
    boot(wow, realm="CAMWOW EU5 Realm 10 RP")
    m = wow.eval("Bastians:GetService('prices'):Market()")
    if wow.client == "forever":
        assert (m.id, m.known) == ("forever/rp/alliance/eu", True)
    else:
        assert m.id == "retail/normal/neutral/eu"


def test_unlisted_live_realm_takes_the_ruleset_from_its_last_word(wow: WowRuntime):
    """A realm of the same shape that is not in the table: the ruleset from the last word, the
    region from the client, and still "not in the table"."""
    if wow.client != "forever":
        return
    boot(wow, realm="CAMWOW US2 Realm 4 RP")
    m = wow.eval("Bastians:GetService('prices'):Market()")
    assert (m.ruleset, m.known) == ("rp", False)
    for realm, ruleset in (
        ("CAMWOW EU1 Realm 7 PvP", "pvp"),
        ("CAMWOW EU1 Realm 2 PvE", "normal"),
        ("Stirrup", "normal"),  # a word that merely ends in the letters
        ("Realm of RP", "normal"),  # not the measured shape
    ):
        wow.execute(f'function GetRealmName() return "{realm}" end')
        got = wow.eval("Bastians:GetModule('Gold').Prices.DetectMarket().ruleset")
        assert got == ruleset, realm


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
        assert (p.salesPerDay, p.median30d, p.label) == (21.9, 75, "US normal")
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
    assert status.pack.label in ("US normal", "retail EU") and status.scan["items"] == 1


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


def test_a_market_without_rows_reads_along_its_chain(wow: WowRuntime):
    """EU RP has no rows; it reads EU normal, which in the fixture reads US normal
    (`market.list[eu].alias`, 23.10.2026: copies had tripled the pack with the first real export).
    The price carries the label of the market that answered."""
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
        wow.eval("Bastians:GetModule('Gold').Prices.PackMarket()") == "forever/normal/alliance/eu"
    )
    p = price(wow, 2589)
    assert (p.median, p.source, p.label) == (38, "market", "US normal")
    assert wow.errors == []


def test_an_item_the_market_lacks_comes_from_the_next_market_with_its_label(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    wow.execute(
        """
        svc = Bastians:GetService("prices")
        local d = Bastians:GetService("data")
        local here = svc:Market().id
        local rows = {
          ["a/eu:7"] = { median = 5, src = "EU normal" },
          ["a/us:7"] = { median = 9, src = "US normal" },
          ["a/us:8"] = { median = 3, src = "US normal" },
        }
        local list = {
          [here] = { label = "EU normal", alias = "a/eu" },
          ["a/eu"] = { label = "EU normal", fallback = "a/us" },
          ["a/us"] = { label = "US normal" },
        }
        d.Get = function(_, _, key) return rows[key] end
        d.Index = function(_, _, key) return list[key] end
        d.PackLoaded = function() return true end
        """
    )
    own = wow.eval("svc:Price(7)")
    assert own.median == 5 and own.label == "EU normal"
    further = wow.eval("svc:Price(8)")
    assert further.median == 3 and further.label == "US normal"
    assert wow.eval("svc:Price(9)") is None  # nobody knows it: unknown stays unknown
    assert wow.errors == []


def test_the_end_of_an_internal_realm_name_says_the_ruleset(wow: WowRuntime):
    if wow.client != "forever":
        return
    for realm, ruleset in (
        ("CAMWOW EU5 Realm 10 RP", "rp"),
        ("CAMWOW US2 Realm 7 PvE", "normal"),
        ("CAMWOW EU5 Realm 11 PvP", "pvp"),
        ("CAMWOW EU5 Realm 12 RP PvP", "rppvp"),
        ("Some Other Name", "normal"),
    ):
        wow.execute(f'function GetRealmName() return "{realm}" end')
        if realm.startswith("CAMWOW EU5 Realm 10"):
            boot(wow)
        wow.execute("Bastians:GetModule('Gold').Prices.DetectMarket()")
        assert wow.eval("Bastians:GetService('prices'):Market().ruleset") == ruleset


def test_an_addon_of_the_player_answers_before_the_pack_and_a_fresh_scan_before_it(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    wow.execute(
        """
        AHledgerAPI = { GetPrice = function(id)
          if id == 2589 then return { median = 77, minBuyout = 70, soldPerDay = 3 } end
        end }
        Auctionator = { API = { v1 = {
          GetAuctionPriceByItemID = function(_, id) if id == 1185 then return 55 end end,
          GetAuctionAgeByItemID = function() return 2 end,
        } } }
        TSM_API = { GetCustomPriceValue = function(_, s) if s == "i:9" then return 33 end end }
        """
    )
    p = price(wow, 2589)
    assert (p.median, p.salesPerDay, p.source) == (77, 3, "addon") and "ahledger.com" in p.label
    a = price(wow, 1185)
    assert (a.median, a.label, a.age) == (55, "Auctionator", 2 * 86400)
    assert price(wow, 9).label == "TradeSkillMaster"
    text = wow.eval(
        "Bastians:GetModule('Gold').Sections.SourceText(Bastians:GetService('prices'):Price(1185))"
    )
    assert text.startswith("Auctionator, ")
    scan(wow, [listing(1, 2589, 1, 500)])
    assert price(wow, 2589).source == "scan"  # the player's own eyes win
    assert wow.errors == []


def test_a_failing_addon_is_skipped_and_the_next_one_asked(wow: WowRuntime):
    boot(wow, CORE, DATA, GOLD)
    wow.execute(
        """
        AHledgerAPI = { GetPrice = function() error("broken") end }
        TSM_API = { GetCustomPriceValue = function() return 33 end }
        """
    )
    assert price(wow, 7).label == "TradeSkillMaster"
    assert wow.errors == []
