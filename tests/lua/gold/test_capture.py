"""Gold capture (B6.1), ported from AHSync's test_ahsynccapture.py: the raw dump is lossless (every
value as it came, a missing value stays empty, texts interned), the listing is read in job slices,
late sellers arrive with the retry pass, closing the house mid-read saves at once, a second event is
deduped, the 15-minute window counts every addon's request, merchants and trainers are captured
through Compat (both trainer API shapes), and the saved variables survive /reload."""

from typing import Any

from harness import WowRuntime

CORE, DATA, GOLD = "Bastians_Core", "Bastians_Data", "Bastians_Gold"

FIELDS = [
    "itemID",
    "count",
    "buyout",
    "bid",
    "minBid",
    "minIncrement",
    "level",
    "levelType",
    "quality",
    "usable",
    "saleStatus",
    "hasAllInfo",
    "timeLeft",
    "texture",
    "name",
    "highBidder",
    "bidderFullName",
    "owner",
    "ownerFullName",
    "link",
]


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, GOLD)))
    wow.run_frames(5)
    wow.execute("AuctionHouseFrame:Show()")
    return wow


def listing(i: int, **kw: Any) -> dict[str, Any]:
    base = {
        "itemID": 2000 + i,
        "count": 1 + i % 5,
        "buyout": 100 + i,
        "bid": 0,
        "owner": f"Seller{i % 7}-Realm",
    }
    base.update(kw)
    return base


def set_listings(wow: WowRuntime, rows: list[dict[str, Any]]) -> None:
    clean = [{k: v for k, v in r.items() if v is not None} for r in rows]
    wow.g.Mock.auctions = wow.lua.table_from([wow.lua.table_from(r) for r in clean])


def scan(wow: WowRuntime, rows: list[dict[str, Any]], frames: int = 20) -> None:
    """A full passive capture: the event, the job slices, the retry wait, the second pass."""
    set_listings(wow, rows)
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(frames)
    wow.g.Mock.ownersLoaded = True
    wow.advance(2.1)
    wow.run_frames(frames)


def db(wow: WowRuntime):
    return wow.eval("BastiansGoldDB.global.capture")


def scans(wow: WowRuntime) -> list:
    return list(db(wow).scans.values())


def raws(wow: WowRuntime) -> list:
    return list(wow.eval("BastiansGoldRaw.scans").values())


def records(raw) -> list[dict[str, str]]:
    return [dict(zip(FIELDS, rec.split(":"), strict=True)) for rec in raw.data.split(";")]


def strings(raw) -> list[str]:
    return list(raw.strings.values())


def text(raw, rec: dict[str, str], name: str) -> str:
    idx = int(rec[name])
    return "" if idx == 0 else strings(raw)[idx - 1]


def log_lines(wow: WowRuntime) -> list[str]:
    return list(db(wow).log.values())


def said(wow: WowRuntime, needle: str) -> bool:
    return any(needle in line for line in wow.chat)


# -- format and lossless dump ------------------------------------------------------------------


def test_format_fields_and_the_dump_in_its_own_variable(wow: WowRuntime):
    boot(wow)
    assert wow.eval("BastiansGoldRaw.format") == 1 and db(wow).format == 1
    assert wow.eval("BastiansGoldRaw.fields") == ",".join(FIELDS)
    scan(wow, [listing(0)])
    (meta,), (raw,) = scans(wow), raws(wow)
    assert raw.data and raw.strings
    assert meta.data is None and meta.strings is None  # the summary stays small
    assert meta.ts == raw.ts and meta.addon == "0.1.0"
    assert said(wow, "do not /reload until it is saved")
    assert said(wow, "Type /reload to write the files")
    assert wow.errors == []


def test_passive_capture_over_several_frames(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.cpuStep = 5")  # every clock read costs 5 ms: one job slice per frame
    set_listings(wow, [listing(i) for i in range(600)])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    assert scans(wow) == []  # still reading: 250 per slice
    assert wow.eval("Bastians:GetModule('Gold').Capture.IsScanning()") is True
    wow.run_frames(1)
    assert scans(wow) == []
    wow.run_frames(10)
    (meta,), (raw,) = scans(wow), raws(wow)
    assert meta.count == 600 and meta.expected == 600 and meta.ownersKnown == 600
    assert meta.trigger == "another addon's scan"
    assert (raw.realm, raw.faction) == ("Mock Realm", "Alliance")
    assert raw.region == ("110" if wow.client == "forever" else "eu")  # recorded, never interpreted
    recs = records(raw)
    assert len(recs) == 600
    r = recs[3]
    assert (r["itemID"], r["count"], r["buyout"], r["bid"], r["timeLeft"]) == (
        "2003",
        "4",
        "103",
        "0",
        "3",
    )
    assert text(raw, r, "ownerFullName") == "Seller3-Realm" and text(raw, r, "owner") == "Seller3"
    assert meta.sellers == 7
    assert said(wow, "seller known for 100%")


def test_every_field_is_kept_as_it_came(wow: WowRuntime):
    boot(wow)
    scan(
        wow,
        [
            listing(
                1,
                name="Linen Cloth",
                texture=132911,
                quality=2,
                level=17,
                levelType="REQ_LEVEL_ABBR",
                minBid=50,
                minIncrement=2,
                bid=60,
                sale=1,
                timeLeft=4,
            )
        ],
    )
    raw = raws(wow)[0]
    (r,) = records(raw)
    assert (r["level"], r["minBid"], r["minIncrement"]) == ("17", "50", "2")
    assert text(raw, r, "levelType") == "REQ_LEVEL_ABBR"
    assert (r["quality"], r["usable"], r["saleStatus"], r["hasAllInfo"]) == ("2", "1", "1", "1")
    assert (r["bid"], r["timeLeft"], r["texture"]) == ("60", "4", "132911")
    assert text(raw, r, "name") == "Linen Cloth"
    assert (
        text(raw, r, "highBidder") == "Bidder" and text(raw, r, "bidderFullName") == "Bidder-Realm"
    )


def test_a_missing_value_stays_empty_never_zero(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(1, minBid=0), listing(2)])
    first, second = records(raws(wow)[0])
    assert first["minBid"] == "0"  # a real 0
    assert second["minBid"] == ""  # nothing sent
    assert second["level"] == "" and second["levelType"] == "0"  # text without a value: index 0


def test_text_is_stored_once_link_is_reduced_and_huge_prices_do_not_raise(wow: WowRuntime):
    boot(wow)
    link = "|cff1eff00|Hitem:9999:0:0:0:0:0:-15:1234:60|h[Sword of the Eagle]|h|r"
    rows = [listing(i, name="Same Name") for i in range(100)]
    rows.append(listing(100, itemID=9999, link=link, buyout=99999999999999))
    scan(wow, rows)
    raw = raws(wow)[0]
    s = strings(raw)
    assert s.count("Same Name") == 1 and s.count("Seller0-Realm") == 1 and len(s) == len(set(s))
    last = records(raw)[-1]
    assert text(raw, last, "link") == "item:9999:0:0:0:0:0:-15:1234:60"
    assert last["buyout"] == "99999999999999"


# -- sellers and the retry pass --------------------------------------------------------------


def test_late_sellers_are_filled_in_by_the_retry_pass(wow: WowRuntime):
    boot(wow)
    rows = [listing(i, late=(i % 2 == 0)) for i in range(10)]
    rows[4] = listing(4, owner=None, noInfo=True)  # item data and seller never come
    set_listings(wow, rows)
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(5)
    assert scans(wow) == []  # waiting for the item data
    assert wow.g.Mock.loadRequests > 0
    wow.g.Mock.ownersLoaded = True
    wow.advance(2.1)
    wow.run_frames(5)
    (meta,), (raw,) = scans(wow), raws(wow)
    assert meta.ownersKnown == 9
    recs = records(raw)
    assert recs[4]["ownerFullName"] == "0" and recs[4]["owner"] == "0"
    assert all(r["ownerFullName"] != "0" for i, r in enumerate(recs) if i != 4)
    assert recs[0]["hasAllInfo"] == "1" and recs[4]["hasAllInfo"] == "0"
    assert meta.retryPending == 5 and meta.retryFound == 4


def test_no_sellers_at_all_is_reported_and_needs_no_second_pass(wow: WowRuntime):
    boot(wow)
    set_listings(wow, [listing(i, owner=None) for i in range(300)])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(5)
    (meta,) = scans(wow)  # saved without waiting: the item data was there
    assert meta.ownersKnown == 0 and meta.sellers == 0 and meta.retryPending is None
    assert wow.g.Mock.loadRequests == 0
    assert said(wow, "no seller names came back")


def test_seller_name_falls_back_to_the_short_name(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(0, owner="Solo-Realm", noFull=True)])
    raw = raws(wow)[0]
    (r,) = records(raw)
    assert text(raw, r, "owner") == "Solo" and r["ownerFullName"] == "0"
    assert scans(wow)[0].ownersKnown == 1


# -- flow ------------------------------------------------------------------------------------


def test_second_event_within_two_minutes_is_ignored(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(i) for i in range(5)])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(5)
    assert len(scans(wow)) == 1
    assert any("finished less than" in line for line in log_lines(wow))
    wow.advance(200)
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(5)
    assert len(scans(wow)) == 2


def test_ignored_when_the_house_is_not_open(wow: WowRuntime):
    boot(wow)
    wow.execute("AuctionHouseFrame:Hide()")
    scan(wow, [listing(0)])
    assert scans(wow) == []
    assert any("does not count as open" in line for line in log_lines(wow))


def test_closing_mid_read_saves_everything_at_once(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.cpuStep = 5")
    set_listings(wow, [listing(i) for i in range(1000)])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(1)
    assert scans(wow) == []
    wow.fire("AUCTION_HOUSE_CLOSED")  # the list vanishes with the window: read the rest now
    (meta,) = scans(wow)
    assert meta.count == 1000
    wow.run_frames(5)
    wow.advance(3)
    assert len(scans(wow)) == 1 and wow.eval("Bastians.Jobs:Pending()") == 0
    assert wow.errors == []


def test_closing_during_the_retry_wait_saves_what_we_have(wow: WowRuntime):
    boot(wow)
    set_listings(wow, [listing(i, late=True) for i in range(5)])
    wow.fire("REPLICATE_ITEM_LIST_UPDATE")
    wow.run_frames(5)  # the first pass is done, the retry timer waits
    assert scans(wow) == []
    wow.fire("AUCTION_HOUSE_CLOSED")
    (meta,) = scans(wow)
    assert meta.count == 5 and meta.ownersKnown == 0
    wow.advance(3)
    wow.run_frames(5)
    assert len(scans(wow)) == 1


def test_empty_listing_and_unreadable_rows(wow: WowRuntime):
    boot(wow)
    scan(wow, [])
    assert scans(wow) == [] and raws(wow) == []
    scan(wow, [listing(0), listing(1, itemID=0), listing(2, count=0), listing(3)])
    (meta,) = scans(wow)
    assert meta.count == 2 and meta.skipped == 2


def test_manual_scan_requests_once_labels_the_trigger_and_reports_refusals(wow: WowRuntime):
    boot(wow)
    wow.execute("AuctionHouseFrame:Hide()")
    wow.slash("/bgold scan")
    assert wow.g.Mock.replicateRequests == 0 and said(wow, "open the auction house first")
    wow.execute("AuctionHouseFrame:Show()")
    wow.slash("/bgold scan")
    assert wow.g.Mock.replicateRequests == 1
    assert any("replicate requested by this addon" in line for line in log_lines(wow))
    scan(wow, [listing(0)])
    assert scans(wow)[0].trigger == "own request"
    wow.advance(1000)
    wow.slash("/bgold scan force")
    wow.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
    assert said(wow, "refused")


def test_keep_limits_summaries_and_keepraw_limits_dumps(wow: WowRuntime):
    boot(wow)
    wow.slash("/bgold keep 4")
    wow.slash("/bgold keepraw 2")
    for k in range(5):
        wow.advance(1000)
        scan(wow, [listing(k)])
    assert len(scans(wow)) == 4 and len(raws(wow)) == 2
    assert [records(r)[0]["itemID"] for r in raws(wow)] == ["2003", "2004"]
    wow.slash("/bgold keep 999")
    assert db(wow).keep == 4
    wow.slash("/bgold nonsense")
    assert said(wow, "commands:")


# -- the 15-minute window --------------------------------------------------------------------


def test_any_addons_request_starts_the_window_and_blocks_our_own(wow: WowRuntime):
    boot(wow)
    wow.execute("C_AuctionHouse.ReplicateItems()")  # another addon asks
    assert db(wow).pending is True and db(wow).lastRequestAt == wow.eval("GetServerTime()")
    assert any("replicate requested by another addon" in line for line in log_lines(wow))
    wow.advance(5)
    wow.slash("/bgold scan")
    assert wow.g.Mock.replicateRequests == 1
    assert said(wow, "not sending") and said(wow, "not been answered")
    wow.slash("/bgold scan force")
    assert wow.g.Mock.replicateRequests == 2
    wow.advance(15 * 60 + 1)
    wow.slash("/bgold scan")
    assert wow.g.Mock.replicateRequests == 3
    assert db(wow).requestCount == 3 and len(db(wow).requestLog) == 3


def test_a_reply_clears_pending_closing_before_it_is_reported_and_status_shows_the_window(
    wow: WowRuntime,
):
    boot(wow)
    wow.slash("/bgold status")
    assert said(wow, "window: free")
    wow.execute("C_AuctionHouse.ReplicateItems()")
    wow.fire("AUCTION_HOUSE_CLOSED")
    assert said(wow, "still used up the 15-minute window")
    wow.execute("AuctionHouseFrame:Show()")
    scan(wow, [listing(0)])
    assert db(wow).pending is False
    wow.advance(60)
    wow.slash("/bgold status")
    assert said(wow, "window: last request 1 min ago (answered)") and said(wow, "14 more min")
    assert said(wow, "last: Mock Realm Alliance, 1 listings")


# -- merchants, sell prices, trainers --------------------------------------------------------


def with_npc(wow: WowRuntime, guid_id: int, name: str) -> None:
    wow.execute(
        f"Mock.guids = Mock.guids or {{}}; Mock.guids.npc = 'Creature-0-4469-0-12-{guid_id}-0000ABCDEF';"
        f' Mock.unitNames = {{ npc = "{name}" }}'
    )


def test_merchant_offers_are_read_once_after_the_window_opens(wow: WowRuntime):
    boot(wow)
    with_npc(wow, 1257, "Keldric Boucher")
    wow.execute(
        """
        Mock.merchant = {
          { itemID = 4470, name = "Simple Wood", price = 38, stackCount = 1, numAvailable = -1 },
          { itemID = 6217, name = "Copper Rod", price = 124, stackCount = 1, numAvailable = 2 },
          { itemID = 2589, name = "Linen Cloth", price = 260, stackCount = 20, numAvailable = -1 },
        }
        """
    )
    wow.fire("MERCHANT_SHOW")
    wow.fire("MERCHANT_UPDATE")
    assert dict(db(wow).merchants.items()) == {}  # after the delay
    wow.advance(0.6)
    ((key, m),) = db(wow).merchants.items()
    assert key == "Mock Realm|1257"
    assert (m.npcID, m.name, m.zone, m.faction) == (
        1257,
        "Keldric Boucher",
        "Elwynn Forest",
        "Alliance",
    )
    assert (m.count, m.missing) == (3, 0)
    assert m.offers.split(";") == ["4470:38:1::", "6217:124:1:2:", "2589:260:20::"]
    assert m.fields == "itemID,price,stack,available,extended"
    assert (m.mapID, m.x, m.y) == (1429, 42.0, 65.0)
    assert [line for line in wow.chat if "merchant Keldric Boucher (1257)" in line] == [
        "|cff66ccffBastians:|r merchant Keldric Boucher (1257): 3 offers, 0 without data at 42.0, 65.0"
    ]
    wow.fire("MERCHANT_UPDATE")  # a purchase: only the log
    wow.advance(0.6)
    assert len([line for line in wow.chat if "merchant Keldric" in line]) == 1
    assert len([line for line in log_lines(wow) if "merchant Keldric" in line]) == 2
    wow.slash("/bgold vendors")
    # R9: the merchant's offers fill the sell prices the client knows (before: 0 after a first scan)
    known = wow.eval("Bastians:GetModule('Gold').Capture.Counts().sellPrices")
    assert known >= 1
    assert said(
        wow,
        f"1 merchants with 3 offers noted; 0 trainers with 0 services; sell price known for {known} items",
    )


def test_sell_prices_are_collected_after_a_scan(wow: WowRuntime):
    boot(wow)
    scan(
        wow,
        [
            listing(0, itemID=2589),
            listing(1, itemID=1185),
            listing(2, itemID=424242),
            listing(3, itemID=2589),
        ],
    )
    prices = dict(db(wow).sellPrices.items())
    assert prices == {2589: 13}  # the mock knows Linen Cloth's sell price; the others have no data
    assert scans(wow)[0].sellPricesNew == 1


def test_trainer_reads_every_service_and_restores_the_filters(wow: WowRuntime):
    boot(wow)
    with_npc(wow, 5500, "Tel'Athir")
    wow.execute(
        """
        Mock.tradeskillTrainer = true
        Mock.trainer = {
          { name = "Alchemy", kind = "header" },
          { name = "Alchemy", subtext = "Apprentice", kind = "used", cost = 10, level = 5 },
          { name = "Minor Healing Potion", kind = "used", cost = 0, skill = "Alchemy", skillRank = 1, itemID = 118 },
          { name = "Elixir of Wisdom", kind = "unavailable", cost = 900, skill = "Alchemy", skillRank = 90, itemID = 3383 },
          { name = "Alchemy", subtext = "Journeyman", kind = "available", cost = 500, level = 10 },
        }
        """
    )
    wow.fire("TRAINER_SHOW")
    wow.fire("TRAINER_SHOW")  # twice: one read
    assert dict(db(wow).trainers.items()) == {}
    wow.advance(0.6)
    ((key, t),) = db(wow).trainers.items()
    assert key == "Mock Realm|5500"
    assert (t.npcID, t.name, t.tradeskill, t.allShown) == (5500, "Tel'Athir", 1, 1)
    assert (t.count, t.missing, t.collapsed) == (4, 0, 0)
    got = [dict(s.items()) for s in t.services.values()]
    assert got[0]["name"] == "Alchemy" and got[0]["kind"] == "used" and got[0]["group"] == "Alchemy"
    assert (got[0]["cost"], got[0]["level"]) == (10, 5)
    assert got[1]["cost"] == 0 and got[1]["itemID"] == 118 and "level" not in got[1]
    assert (got[2]["skill"], got[2]["skillLevel"], got[2]["cost"]) == ("Alchemy", 90, 900)
    if wow.client == "forever":
        assert "rank" not in got[0]  # Forever returns name, type, icon: no rank text
    else:
        assert got[0]["rank"] == "Apprentice"
    assert dict(wow.g.Mock.trainerFilters.items()) == {
        "available": True,
        "unavailable": True,
        "used": False,
    }
    assert len(wow.g.Mock.trainerFilterCalls) == 2  # "used" on and off again
    assert said(
        wow,
        "trainer Tel'Athir (5500): 4 services (1 available, 1 not yet, 2 learned), 0 without data",
    )


def test_trainer_waits_for_an_empty_list_and_notes_collapsed_groups(wow: WowRuntime):
    boot(wow)
    with_npc(wow, 5500, "Tel'Athir")
    wow.execute("Mock.trainer = {}")
    wow.fire("TRAINER_SHOW")
    wow.advance(2)
    assert dict(db(wow).trainers.items()) == {}
    assert any("trainer window stayed empty" in line for line in log_lines(wow))
    wow.execute(
        """
        Mock.trainer = {
          { name = "Cooking", kind = "header", expanded = false },
          { name = "Fishing", kind = "header" },
          { name = "Fishing", subtext = "Apprentice", kind = "available", cost = 10 },
        }
        """
    )
    wow.fire("TRAINER_SHOW")
    wow.advance(0.6)
    (t,) = db(wow).trainers.values()
    if wow.client == "forever":
        assert (t.count, t.collapsed) == (1, 0)  # Forever's order carries no expanded flag
    else:
        assert (t.count, t.collapsed) == (1, 1) and said(wow, "1 groups collapsed")


def test_trainer_without_filter_api_or_with_a_broken_one_still_reads_what_is_shown(wow: WowRuntime):
    boot(wow)
    with_npc(wow, 5500, "Tel'Athir")
    wow.execute(
        """
        Mock.trainer = {
          { name = "Alchemy", subtext = "Apprentice", kind = "used", cost = 10, level = 5 },
          { name = "Alchemy", subtext = "Journeyman", kind = "available", cost = 500, level = 10 },
        }
        GetTrainerServiceTypeFilter = nil
        """
    )
    wow.fire("TRAINER_SHOW")
    wow.advance(0.6)
    (t,) = db(wow).trainers.values()
    assert (t.count, t.allShown) == (1, 0)  # the learned one stays hidden
    wow.execute("Bastians:GetModule('Gold').Capture.Register(Bastians:GetModule('Gold'))")
    wow.execute(
        "BastiansGoldDB.global.capture.trainers = {};"
        " function GetTrainerServiceTypeFilter(k) return Mock.trainerFilters[k] end;"
        " function SetTrainerServiceTypeFilter() error('nope') end"
    )
    wow.fire("TRAINER_SHOW")
    wow.advance(0.6)
    (t,) = db(wow).trainers.values()
    assert (t.count, t.allShown) == (1, 0)
    assert said(wow, "filters stayed closed, hidden services are missing")
    assert wow.errors == []


def test_saved_variables_survive_a_reload(wow: WowRuntime):
    boot(wow)
    scan(wow, [listing(i) for i in range(3)])
    fresh = wow.reload()
    fresh.run_frames(5)
    assert len(list(fresh.eval("BastiansGoldRaw.scans").values())) == 1
    assert fresh.eval("BastiansGoldRaw.fields") == ",".join(FIELDS)
    assert len(list(fresh.eval("BastiansGoldDB.global.capture.scans").values())) == 1
    assert fresh.eval("BastiansGoldDB.global.capture.format") == 1
    assert any(
        "loaded v0.1.0" in line for line in fresh.eval("BastiansGoldDB.global.capture.log").values()
    )
    assert fresh.errors == []


def test_scan_fires_prices_updated_and_works_without_data(wow: WowRuntime):
    boot(wow, CORE, GOLD)
    wow.execute(
        """
        updates = {}
        local w = Bastians:NewModule("PriceWatcher", { addon = "Bastians_Gold" })
        w:On("BASTIANS_PRICES_UPDATED", function(_, _, source) updates[#updates + 1] = source end)
        """
    )
    scan(wow, [listing(0)])
    assert list(wow.g.updates.values()) == ["scan"]
    notes = [
        o.text()
        for o in wow.eval("Bastians:GetModule('Gold').options").values()
        if o.type == "note"
    ]
    assert any(n.startswith("0 merchants (0 offers), 0 trainers (0 services)") for n in notes)
    assert wow.errors == []
