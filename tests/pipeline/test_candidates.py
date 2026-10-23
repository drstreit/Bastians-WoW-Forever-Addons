"""The book's candidate report (strategies-design.md section 7): claims grouped into strategies per
video, chapter and zone, merged across videos that name the same things, scored by visible parts,
the strategies a page already tells marked; price levels are no strategies."""

from pathlib import Path

from bastians_build.candidates import candidates, group, report
from bastians_build.sources.ahsync_export import Export
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
DAY = 86400.0
NOW = 1_800_000_000.0


def claim(cid, kind, subject, where, video, channel, status="unverified", reach=1000, days=3):
    return {
        "claim_id": cid,
        "kind": kind,
        "subject": subject,
        "where": where,
        "ui_map_id": None,
        "status": status,
        "reach": reach,
        "last_seen": NOW - days * DAY,
        "claim": f"{subject} at {where}",
        "sources": [{"channel": channel, "link": f"https://www.youtube.com/watch?v={video}&t=10s"}],
    }


def export(*claims, prices=()) -> Export:
    rows = [{"item_id": i, "median_7d": p, "median": p} for i, p in prices]
    return Export(
        folder=Path("x"), manifest={}, tables={"claims": list(claims), "prices_latest": rows}
    )


def test_claims_group_by_video_and_zone_and_merge_across_videos():
    world = read_fixture(WORLD, "forever")
    found = group(
        export(
            claim(1, "farm_spot", "Hogger gnolls linen", "elwynn forest", "v1", "A"),
            claim(2, "farm_spot", "gnolls drop linen", "elwynn forest", "v1", "A"),
            claim(3, "farm_spot", "Hogger gnolls camp", "elwynn forest", "v2", "B"),
            claim(4, "farm_spot", "kobolds candles", "elwynn forest", "v3", "C"),
            claim(5, "fishing_spot", "Westfall coast", "westfall", "v1", "A"),
            claim(6, "price_level", "Linen Cloth", "auction house", "v1", "A"),
        ),
        world,
    )
    by = {tuple(sorted(c["claim_id"] for c in s.claims)): s for s in found}
    # one video's gnoll claims, merged with another video's on the same camp; the kobolds apart
    assert set(by) == {(1, 2, 3), (4,), (5,)}
    assert by[(1, 2, 3)].zone == 1429 and by[(1, 2, 3)].channels == {"A", "B"}
    assert by[(5,)].chapter == "fishing"  # a price level is no strategy


def test_the_score_has_visible_parts_and_the_page_is_marked():
    world = read_fixture(WORLD, "forever")
    world.add("page", "hogger-camp", {"rumours": [[1, "true", None]], "shelf": "active"})
    ex = export(
        claim(1, "farm_spot", "Hogger gnolls", "elwynn forest", "v1", "A", status="verified"),
        claim(2, "farm_spot", "Hogger gnolls", "elwynn forest", "v2", "B", reach=100000),
        claim(7, "farm_spot", "old camp", "elwynn forest", "v9", "Z", status="refuted", days=90),
    )
    found = candidates(ex, world, now=NOW)
    top = found["farming"][0]
    assert top.page == "hogger-camp"
    assert top.parts["channels"] == 20 and top.parts["freshness"] == 15
    assert top.parts["verification"] == 7.5  # one verified of two
    assert top.parts["level cap"] == 20  # Elwynn's lowest level is within 30
    # half the evidence, one and a half times the value, the nuggets (none of these claims has
    # a number); no price in this export: no value, a gold chapter marks it
    assert top.evidence == 86.5 and top.parts["value"] == 0 and top.low_value is True
    assert top.score == round(top.evidence / 2 + 1.5 * top.parts["value"] + top.parts["nuggets"], 1)
    low = found["farming"][-1]
    assert low.parts["verification"] == -15 and low.parts["freshness"] == 0
    text = report(found)
    assert "## farming (2 strategies)" in text and "page `hogger-camp`" in text
    assert "## fishing (0 strategies)" in text


def test_value_comes_from_loot_prices_margins_and_stated_gold_per_hour():
    world = read_fixture(WORLD, "forever")
    rich = claim(1, "farm_spot", "Hogger gnolls", "elwynn forest", "v1", "A")
    stated = claim(2, "farm_spot", "kobold candles", "elwynn forest", "v2", "B")
    stated["claim"] = "Kobolds make up to 4.5 gold per hour."
    # Hogger drops Blood Saber in 3.2 % of kills (5g) and Linen in 45.5 % (26c): 15s 31c a kill
    found = candidates(export(rich, stated, prices=[(1185, 50000), (2589, 26)]), world, now=NOW)
    by = {s.claims[0]["claim_id"]: s for s in found["farming"]}
    assert by[1].parts["value"] == 30 and "Hogger: 15s 31c a kill" in by[1].value_notes
    assert by[2].parts["value"] == 20 and by[2].value_notes[0] == "a claim says 4.5 gold an hour"
    assert by[2].parts["nuggets"] == 10  # a concrete number in every claim
    assert found["farming"][0] is by[1]  # the paying one first
    assert "Hogger: 15s 31c a kill" in report(found)
