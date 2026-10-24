"""What's new written by the build (strategies-design.md section 7, 24.10.2026): the book's daily
changes since the last edition that was sent, as entries in the pack, each linked to its page or
to its chapter's Rumour mill. book.toml's hand-written entries (new pages) stay; these join them.

The build compares this export's book with the state of the last sent edition (`--book-previous`,
written by an earlier build with `--book-state` and kept by tools/data_update.py):

- new travellers on a page: channels of the strategies the page tells that the last edition lacked;
- a rumour on a page with a new stamp (true, half true, lies);
- new rumours in a chapter's mill.

A second edition on the same day adds to that day's lines ("2 new travellers" becomes 3), so a
page has one line a day. Without a previous state nothing is generated (there is nothing to
compare with); the state is still written, so the next build has one. Same inputs, same entries:
the date is the export's.
"""

from __future__ import annotations

import datetime as dt
import json
from collections.abc import Mapping
from pathlib import Path

from bastians_build.candidates import Strategy
from bastians_build.model import World

STATE_SCHEMA = 1
DAILY_CAP = 8  # generated entries per edition; the rest folds into one line
KEEP_DAYS = 30  # generated entries older than this leave the pack
KEEP_MAX = 40
STAMP_WORDS = {"true": "proved true", "half": "proved half true", "lies": "proved to be lies"}
ADDS_UP = ("travellers", "mill", "more")  # kinds whose counts add up over a day's editions
KIND_ORDER = {"stamp": 0, "travellers": 1, "mill": 2}


class BookNewsError(ValueError):
    pass


def text(kind: str, n: int, name: str = "", stamp: str = "") -> str:
    if kind == "travellers":
        return f'A new traveller on "{name}".' if n == 1 else f'{n} new travellers on "{name}".'
    if kind == "mill":
        return (
            f"{name}: a new rumour in the mill."
            if n == 1
            else f"{name}: {n} new rumours in the mill."
        )
    if kind == "stamp":
        return f'A rumour on "{name}" {STAMP_WORDS[stamp]}.'
    return f"And {n} more changes in the book."


def book_state(world: World, found: Mapping[str, list[Strategy]]) -> dict:
    """What the next build compares with: per page its travellers (the channels of every strategy
    it tells and of its own rumours) and its rumours' stamps, per chapter the mill's claim ids."""
    pages = world.records.get("page", {})
    rumours = world.records.get("rumour", {})
    channels: dict[str, set[str]] = {
        pid: set() for pid, p in pages.items() if p.get("shelf") != "retired"
    }
    for strategies in found.values():
        for s in strategies:
            if s.page in channels:
                channels[s.page] |= s.channels
    out_pages: dict[str, dict] = {}
    for pid in sorted(channels):
        stamps: dict[str, str] = {}
        for cid, stamp, _why in pages[pid].get("rumours") or []:
            stamps[str(cid)] = stamp
            for source in (rumours.get(cid) or {}).get("sources") or []:
                if source and source[0]:
                    channels[pid].add(str(source[0]))
        out_pages[pid] = {"channels": sorted(channels[pid]), "stamps": dict(sorted(stamps.items()))}
    mill: dict[str, list[int]] = {}
    for cid, m in world.records.get("mill", {}).items():
        mill.setdefault(str(m["chapter"]), []).append(int(cid))
    return {
        "schema": STATE_SCHEMA,
        "pages": out_pages,
        "mill": {ch: sorted(ids) for ch, ids in sorted(mill.items())},
        "news": [],
    }


def entry(date: str, kind: str, n: int, name: str = "", **link: str) -> dict:
    stamp = link.pop("stamp", "")
    return {"date": date, "kind": kind, "n": n, "text": text(kind, n, name, stamp), **link}


def changes(previous: Mapping, current: Mapping, world: World, date: str) -> list[dict]:
    """One edition's entries, at most DAILY_CAP: stamps first, then travellers (most first), then
    the mill, the rest folded into one line without a link."""
    pages = world.records.get("page", {})
    chapters = world.records.get("chapter", {})
    found: list[dict] = []
    for pid, now in current["pages"].items():
        before = previous.get("pages", {}).get(pid)
        if before is None:
            continue  # a new page: book.toml carries its entry
        title = str(pages[pid]["name"])
        new = set(now["channels"]) - set(before.get("channels", []))
        if new:
            found.append(entry(date, "travellers", len(new), title, page=pid))
        old_stamps = before.get("stamps", {})
        for cid, stamp in now["stamps"].items():
            old = old_stamps.get(cid)
            if old is not None and old != stamp and stamp in STAMP_WORDS:
                found.append(entry(date, "stamp", 1, title, page=pid, stamp=stamp))
    for ch, ids in current["mill"].items():
        if ch not in chapters:
            continue
        new = set(ids) - set(previous.get("mill", {}).get(ch, []))
        if new:
            found.append(entry(date, "mill", len(new), str(chapters[ch]["name"]), mill=ch))
    found.sort(key=lambda e: (KIND_ORDER[e["kind"]], -e["n"], e["text"]))
    if len(found) > DAILY_CAP:
        rest = len(found) - (DAILY_CAP - 1)
        found = [*found[: DAILY_CAP - 1], entry(date, "more", rest)]
    return found


def merge(old: list[dict], new: list[dict], world: World) -> list[dict]:
    """The day's new entries joined to the kept ones: a count of the same day, kind and link adds
    up (one line per page and day), an equal text of the same day is kept once."""
    out = [dict(e) for e in old]
    for e in new:
        key = (e["date"], e["kind"], e.get("page"), e.get("mill"))
        same = next(
            (o for o in out if (o["date"], o.get("kind"), o.get("page"), o.get("mill")) == key),
            None,
        )
        if same is not None and e["kind"] in ADDS_UP:
            same["n"] = int(same.get("n", 0)) + e["n"]
            name = ""
            if e.get("page"):
                name = str(world.records["page"][e["page"]]["name"])
            elif e.get("mill"):
                name = str(world.records["chapter"][e["mill"]]["name"])
            same["text"] = text(e["kind"], same["n"], name)
        elif not any((o["date"], o["text"]) == (e["date"], e["text"]) for o in out):
            out.append(e)
    return out


def add_generated_news(
    world: World, found: Mapping[str, list[Strategy]], previous: Mapping | None, date: str | None
) -> tuple[dict, list[str]]:
    """Adds the generated entries to the book's `news` records (with book.toml's, newest first, the
    id is the place in that order). -> (the state to keep, report notes)."""
    state = book_state(world, found)
    if not world.records.get("chapter"):
        return state, []
    kept: list[dict] = []
    new: list[dict] = []
    if previous is not None and date:
        if previous.get("schema") != STATE_SCHEMA:
            raise BookNewsError(f"book state schema {previous.get('schema')}, not {STATE_SCHEMA}")
        new = changes(previous, state, world, date)
        oldest = (dt.date.fromisoformat(date) - dt.timedelta(days=KEEP_DAYS)).isoformat()
        kept = [e for e in merge(list(previous.get("news", [])), new, world) if e["date"] >= oldest]
        # a link to a page or chapter that is gone leaves the entry as plain text
        for e in kept:
            if e.get("page") and e["page"] not in world.records.get("page", {}):
                e.pop("page")
            if e.get("mill") and e["mill"] not in world.records["chapter"]:
                e.pop("mill")
        kept.sort(key=lambda e: (e["date"], e["text"]), reverse=True)
        kept = kept[:KEEP_MAX]
    state["news"] = kept
    generated = {(e["date"], e["text"]) for e in kept}
    authored = [
        n for n in world.records.get("news", {}).values() if (n["date"], n["text"]) not in generated
    ]
    merged = sorted([*authored, *kept], key=lambda n: (n["date"], n["text"]), reverse=True)
    world.records["news"] = {}
    for i, n in enumerate(merged, 1):
        world.add(
            "news",
            i,
            {
                "date": n["date"],
                "text": n["text"],
                "page": n.get("page"),
                "mill": n.get("mill"),
                "kind": n.get("kind"),
                "n": n.get("n"),
            },
        )
    if previous is None:
        note = "book: no earlier state, no generated What's new (the next build compares)"
    else:
        note = f"book: {len(new)} generated What's new entries on {date}, {len(kept)} kept"
    world.notes.append(note)
    return state, [note]


def read_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise BookNewsError(f"book state {path}: {exc}") from exc


def write_state(path: Path, state: Mapping) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(
        json.dumps(state, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    tmp.replace(path)
