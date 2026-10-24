"""What's new written by the build (book_news.py, strategies-design.md section 7): the book's
changes since the last sent edition become entries in the pack, linked to the page or the
chapter's Rumour mill; without a previous state nothing is generated; the same inputs give the
same entries; a day's flood folds into one line; old entries leave the pack."""

import json
from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.book import add_book
from bastians_build.book_news import (
    DAILY_CAP,
    KEEP_DAYS,
    BookNewsError,
    add_generated_news,
    book_state,
)
from bastians_build.candidates import Strategy
from bastians_build.sources.ahsync_export import read_export
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
EXPORT = ROOT / "tests" / "fixtures" / "export-mini"
BOOK = ROOT / "tests" / "fixtures" / "book-mini"


def book_world(mill: tuple[int, ...] = ()):
    world = read_fixture(WORLD, "forever")
    add_book(world, read_export(EXPORT), BOOK)
    for rank, cid in enumerate(mill, 1):
        world.add("mill", cid, {"chapter": "farming", "rank": rank, "channels": 2, "claims": 1})
    return world


def strategies(*channels: str) -> dict[str, list[Strategy]]:
    claims = [{"claim_id": 11, "sources": [{"channel": c} for c in channels]}]
    return {"farming": [Strategy(chapter="farming", zone=None, claims=claims, page="hogger-camp")]}


def news(world) -> list[dict]:
    return [world.records["news"][i] for i in sorted(world.records["news"])]


def test_without_a_previous_state_only_the_state_is_written():
    world = book_world(mill=(901,))
    state, notes = add_generated_news(world, strategies("Alpha"), None, "2026-10-25")
    assert "no earlier state" in notes[0]
    assert [n["text"] for n in news(world)] == ["New page: Hogger's Camp.", "The book opens."]
    page = state["pages"]["hogger-camp"]
    assert "Alpha" in page["channels"] and page["stamps"]["12"] == "half"
    assert "old-gnolls" not in state["pages"]  # a tombstone has no travellers
    assert state["mill"] == {"farming": [901]} and state["news"] == []


def test_new_travellers_stamps_and_mill_rumours_become_linked_entries():
    previous = book_state(book_world(mill=(901,)), strategies("Alpha"))
    previous["pages"]["hogger-camp"]["stamps"]["11"] = "open"
    world = book_world(mill=(901, 902, 903))
    current = strategies("Alpha", "Beta", "Gamma")
    state, _ = add_generated_news(world, current, previous, "2026-10-25")
    generated = [n for n in news(world) if n["date"] == "2026-10-25"]
    texts = {n["text"]: n for n in generated}
    assert texts['2 new travellers on "Hogger\'s Camp".']["page"] == "hogger-camp"
    assert texts["Farming and easy kills: 2 new rumours in the mill."]["mill"] == "farming"
    # claim 11 is verified in the export and has no stamp of its own: open -> true
    assert texts['A rumour on "Hogger\'s Camp" proved true.']["page"] == "hogger-camp"
    assert state["pages"]["hogger-camp"]["stamps"]["11"] == "true"
    # newest first, the hand-written entries kept, the ids their place in that order
    assert news(world)[-1]["text"] == "The book opens."
    assert [n["date"] for n in news(world)] == sorted(
        (n["date"] for n in news(world)), reverse=True
    )
    assert state["news"] == sorted(
        state["news"], key=lambda e: (e["date"], e["text"]), reverse=True
    )


def test_the_same_inputs_give_the_same_entries_and_a_second_edition_adds_only_its_own():
    previous = book_state(book_world(), strategies("Alpha"))
    first, _ = add_generated_news(book_world(), strategies("Alpha", "Beta"), previous, "2026-10-25")
    again, _ = add_generated_news(book_world(), strategies("Alpha", "Beta"), previous, "2026-10-25")
    assert first == again
    assert [e["text"] for e in first["news"]] == ['A new traveller on "Hogger\'s Camp".']
    # edition 2 the same day compares with edition 1 (sent): one line for the page, added up
    world = book_world()
    second, _ = add_generated_news(world, strategies("Alpha", "Beta", "Gamma"), first, "2026-10-25")
    assert [(e["text"], e["n"]) for e in second["news"]] == [
        ('2 new travellers on "Hogger\'s Camp".', 2)
    ]
    assert news(world)[0]["text"] == '2 new travellers on "Hogger\'s Camp".'
    # the next day starts a new line
    third, _ = add_generated_news(
        book_world(), strategies("A", "B", "C", "D"), second, "2026-10-26"
    )
    assert [e["date"] for e in third["news"]] == ["2026-10-26", "2026-10-25"]
    assert json.loads(json.dumps(second)) == second  # the state is plain JSON


def test_a_flood_folds_into_one_line_and_old_entries_leave():
    previous = book_state(book_world(), strategies("Alpha"))
    world = book_world(mill=tuple(range(900, 930)))
    previous["mill"] = {}
    previous["news"] = [{"date": "2026-09-01", "text": "Long ago.", "page": None}]
    many = {
        "farming": [
            Strategy(chapter="farming", zone=None, claims=[{"claim_id": 11, "sources": []}])
        ]
    }
    # one page and one mill only give two entries: fill the day through more pages in the state
    for i in range(DAILY_CAP + 3):
        pid = f"page-{i}"
        world.add("page", pid, {"name": f"Page {i}", "chapter": "farming", "shelf": "active"})
        previous["pages"][pid] = {"channels": [], "stamps": {}}
        many["farming"].append(
            Strategy(
                chapter="farming", zone=None, claims=[{"sources": [{"channel": "X"}]}], page=pid
            )
        )
    state, _ = add_generated_news(world, many, previous, "2026-10-25")
    today = [e for e in state["news"] if e["date"] == "2026-10-25"]
    assert len(today) == DAILY_CAP
    assert any(e["text"].startswith("And ") and "more changes" in e["text"] for e in today)
    assert KEEP_DAYS == 30 and "Long ago." not in {e["text"] for e in state["news"]}


def test_a_state_of_another_schema_is_refused():
    with pytest.raises(BookNewsError, match="schema"):
        add_generated_news(book_world(), strategies("Alpha"), {"schema": 99}, "2026-10-25")


def test_the_cli_reads_the_previous_state_and_writes_the_next(tmp_path: Path):
    base = ["data", "--client", "forever", "--fixture", str(WORLD), "--out", str(tmp_path / "a")]
    base += ["--report-dir", str(tmp_path), "--book", str(BOOK), "--export", str(EXPORT)]
    assert main(base) == 0
    state_path = tmp_path / "book-state.json"
    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["schema"] == 1 and "hogger-camp" in state["pages"]
    # a traveller fewer in the previous state: the next build writes an entry for it
    page = state["pages"]["hogger-camp"]
    page["channels"] = page["channels"][1:]
    previous = tmp_path / "previous.json"
    previous.write_text(json.dumps(state), encoding="utf-8")
    nxt = tmp_path / "next.json"
    args = [*base[:6], str(tmp_path / "b"), *base[7:]]
    assert main([*args, "--book-previous", str(previous), "--book-state", str(nxt)]) == 0
    written = json.loads(nxt.read_text(encoding="utf-8"))
    assert [e["page"] for e in written["news"]] == ["hogger-camp"]
    book = (tmp_path / "b" / "Bastians_Data_Strategies" / "Generated" / "Book.lua").read_text(
        encoding="utf-8"
    )
    assert "new traveller" in book and '"mill"' in book
