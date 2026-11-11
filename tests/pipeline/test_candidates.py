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
    assert "verification" not in top.parts  # nothing is judged
    assert top.parts["level cap"] == 20  # Elwynn's lowest level is within 30
    # half the evidence, one and a half times the value, the nuggets (none of these claims has
    # a number); no price in this export: no value, a gold chapter marks it
    assert top.evidence == 79 and top.parts["value"] == 0 and top.low_value is True
    assert top.score == round(top.evidence / 2 + 1.5 * top.parts["value"] + top.parts["nuggets"], 1)
    low = found["farming"][-1]
    assert low.parts["freshness"] == 0
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


def test_a_loot_row_without_a_chance_adds_no_worth_and_stops_no_build():
    """Found 11.11.2026: since QuestieDB's droppers list their items (package QD2) a creature's
    loot row may be `[item]`, the chance unknown. The report unpacked every row as item and
    chance, so every Forever build with an export ended there. Unknown is not zero: such a row
    adds nothing, and a creature with no other priced loot has no worth per kill."""
    world = read_fixture(WORLD, "forever")
    hogger = world.get("npc", 448)
    hogger["loot"] = [*hogger["loot"], [4306], [2592, None]]  # seen to drop, how often unknown
    world.add("npc", 99001, {"name": "Silk Gnoll", "spawns": [[1429, 0.3, 0.8]], "loot": [[4306]]})
    rich = claim(1, "farm_spot", "Hogger gnolls", "elwynn forest", "v1", "A")
    silk = claim(2, "farm_spot", "Silk Gnoll", "elwynn forest", "v2", "B")
    prices = [(1185, 50000), (2589, 26), (4306, 900), (2592, 300)]
    found = candidates(export(rich, silk, prices=prices), world, now=NOW)
    by = {s.claims[0]["claim_id"]: s for s in found["farming"]}
    assert "Hogger: 15s 31c a kill" in by[1].value_notes  # as without the two rows
    assert not any("Silk Gnoll" in note for note in by[2].value_notes)


def test_the_report_leads_with_what_changed_and_what_is_to_decide(tmp_path):
    """the claims grow every night, the report a person reads must not. First
    what entered or left a chapter's first five since the last build, then the strategies among
    the first five that no page tells; everything else is the appendix."""
    from bastians_build.candidates import Strategy, changes, report, to_decide, write_report

    def strategy(title: str, score: float, page: str | None = None) -> Strategy:
        s = Strategy(chapter="farming", zone=None, tokens=set())
        s.title, s.score, s.page = title, score, page
        sources = [{"channel": "A"}, {"channel": "B"}]
        s.claims = [{"claim_id": 7, "claim": f"{title} pays.", "sources": sources}]
        s.parts = {"evidence": score}
        return s

    found = {"farming": [strategy("Elwynn: boars", 30, "boar-run"), strategy("Westfall: wool", 20)]}
    assert changes(found, None) == []
    text = report(found)
    assert "No earlier report to compare with." in text
    assert text.index("## To decide") < text.index("# Appendix")
    assert to_decide(found) == [
        "- farming #2: **Westfall: wool**: 20; 1 claims, 2 channels",
        "   - `7` Westfall: wool pays.",
    ]  # the first has its page
    # the next build: a newcomer pushes in, the old first five is the last report's twin
    write_report(found, tmp_path)
    later = {"farming": [strategy("Duskwood: silk", 40), *found["farming"]]}
    later["farming"] = later["farming"][:1] + [strategy(f"Filler {n}", 35 - n) for n in range(4)]
    second = write_report(later, tmp_path).read_text(encoding="utf-8")
    assert (
        "- farming: **entered** the first five: Duskwood: silk: 40; 1 claims, 2 channels" in second
    )
    assert "- farming: left the first five: Elwynn: boars" in second
    third = write_report(later, tmp_path).read_text(encoding="utf-8")
    assert "Nothing entered or left a chapter's first five." in third
