"""The Rumour mill (strategies-design.md section 7): per chapter of the book the strongest
strategies no page tells, inside the level cap and told by two channels at least, one claim each,
by rank."""

from pathlib import Path

from bastians_build.book import add_book, plain
from bastians_build.candidates import Strategy, candidates
from bastians_build.mill import add_mill, best_claim, mill_index, within_cap
from bastians_build.model import World
from bastians_build.sources.ahsync_export import read_export
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
EXPORT = ROOT / "tests" / "fixtures" / "export-mini"
BOOK = ROOT / "tests" / "fixtures" / "book-mini"


def claim(cid: int, text: str, channels: int = 2, status: str = "unverified") -> dict:
    sources = [
        {
            "channel": f"Channel {i}",
            "published": "2026-10-20",
            "link": f"https://y.example/{cid}{i}",
        }
        for i in range(channels)
    ]
    return {
        "claim_id": cid,
        "kind": "farm_spot",
        "subject": text,
        "status": status,
        "claim": text,
        "reach": 100,
        "where": "the coast",
        "sources": sources,
    }


def strategy(chapter: str, *claims: dict, page=None, low=False) -> Strategy:
    return Strategy(chapter=chapter, zone=None, claims=list(claims), page=page, low_value=low)


def book_world() -> World:
    world = World(client="forever")
    for cid in ("farming", "auction"):
        world.add("chapter", cid, {"name": cid, "order": 1, "opening": None, "active": 5})
    return world


def test_the_level_cap_reads_levels_and_skills_apart():
    assert within_cap({"claim": "Razor Maw, level 27-28, has 28 spawns"})
    assert within_cap({"claim": "Raw catfish need level 55 fishing and level 150 fishing"})
    assert within_cap({"claim": "The recipe requires cooking 175."})
    assert not within_cap({"claim": "Wait until level 60 to drop skinning."})
    assert not within_cap({"claim": "At 300 Leatherworking one crafts for tips."})
    assert not within_cap({"claim": "Most catches need 420 skill."})
    assert not within_cap({"claim": "It needs a fishing skill of 250."})
    assert within_cap({"claim": "Fine at level 60."}, cap=60)


def test_plain_text_is_ascii_for_the_game_fonts():
    quote, left, right, dash, dots = chr(0x2019), chr(0x201C), chr(0x201D), chr(0x2014), chr(0x2026)
    text = f"It{quote}s {left}the{right} one {dash} really{dots}"
    assert plain(text) == 'It\'s "the" one - really...'
    assert plain(f"a{chr(0xA0)} b{chr(0xFFFD)} c") == "a b c"
    assert plain(None) is None


def test_the_best_claim_is_verified_then_the_most_sources_inside_the_cap():
    s = strategy(
        "farming",
        claim(1, "Lots of cloth here.", channels=3),
        claim(2, "Silk drops at level 60.", channels=5, status="verified"),
        claim(3, "Silk drops in one kill of 20.", channels=1, status="verified"),
    )
    assert best_claim(s)["claim_id"] == 3  # 2 is beyond the cap
    assert best_claim(strategy("farming", claim(4, "Only at level 60."))) is None


def test_the_mill_keeps_strong_rumours_no_page_tells(tmp_path):
    world = book_world()
    found = {
        "farming": [
            strategy("farming", claim(10, "Told on a page."), page="p"),
            strategy("farming", claim(11, "Worth nothing."), low=True),
            strategy("farming", claim(12, "One traveller says so.", channels=1)),
            strategy("farming", claim(13, "Only at level 45.")),
            strategy("farming", claim(14, "Crabs on the coast, 37 spawns.")),
            strategy("farming", claim(15, "Murlocs in the Wetlands.")),
            strategy("farming", claim(16, "Harpies in the Needles.")),
        ],
        "auction": [strategy("auction", claim(20, "Deposits come back on a sale."))],
        "trades": [strategy("trades", claim(30, "Not a chapter of this book."))],
    }
    notes = add_mill(world, found, cap=2)
    assert notes == ["book: rumour mill auction 1, farming 2"]
    assert mill_index(world) == {"auction": [20], "farming": [14, 15]}
    m = world.get("mill", 14)
    assert (m["rank"], m["zone"], m["where"], m["channels"], m["claims"]) == (
        1,
        None,
        "the coast",
        2,
        1,
    )
    r = world.get("rumour", 15)
    assert r["claim"] == "Murlocs in the Wetlands." and len(r["sources"]) == 2
    assert world.get("mill", 30) is None and world.get("rumour", 30) is None
    assert add_mill(World(client="forever"), found) == []  # no book, no mill


def test_the_fixture_build_mills_the_two_channel_claim():
    world = read_fixture(WORLD, "forever")
    export = read_export(EXPORT)
    add_book(world, export, BOOK)
    add_mill(world, candidates(export, world))
    assert mill_index(world) == {"farming": [13]}
    m = world.get("mill", 13)
    assert (m["chapter"], m["rank"], m["zone"], m["channels"]) == ("farming", 1, 1429, 2)
    assert world.get("rumour", 13)["claim"].startswith("Hogger drops the Blood Saber")
