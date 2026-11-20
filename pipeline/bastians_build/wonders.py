"""Bastian's Book: the wonders (ADR 0080, docs/addons/book.md "The data").

ForeverDB's special content becomes the record type ``wonder`` of the book's pack, by permanent
id ``<kind>:<key>``. Coordinates become map fractions 0..1; levels, places and items nobody knows
stay ``None``. Bastian's own lines come from ``content/strategies/wonders.toml``.

Round 4 (book.md "Round 4", built 17.11.2026):

- the five chapters named by what the reader does (E1): gold (the pages), ``secrets``,
  ``collections``, ``camp``, ``rares``;
- what is obtainable (E2): ``state`` is ``in`` or ``unknown``; a wonder that is out is not in
  the pack, and the build report names it with its reason;
- a wonder's sources as references (R4.3): ``from = [[how, ref], ...]``. The chance, the price
  and the places are read from the entity when the page is shown, so nothing is copied.
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

from bastians_build.book import BookError, check_text, plain
from bastians_build.model import World
from bastians_build.sources.client_tables import ClientIds
from bastians_build.sources.foreverdb_wonders import (
    Chain,
    ChainStep,
    LibraryBook,
    Source,
    Wonders,
)

SECRETS, COLLECTIONS, CAMP, RARES = "secrets", "collections", "camp", "rares"
# ForeverDB's chain category -> the chapter and the kind (E1)
CHAIN_CHAPTER = {
    "Secret": (SECRETS, "chain"),
    "Secret pets": (SECRETS, "pet"),
    "Camping": (CAMP, "camping"),
    "Collections": (COLLECTIONS, "library"),
}
UNSOLVED = "unsolved"  # a secret chain nobody has solved: its own kind
IN, UNKNOWN = "in", "unknown"  # E2; "out" is not a state of a record, the wonder is dropped
LOOT_SHOWN = 6  # a rare's gifts on its page: the file's first ones
ROUND = 4  # decimals of a map fraction
# the rows of `from`: at most this many of a way, and of all ways together
FROM_DROPS, FROM_VENDORS, FROM_QUESTS, FROM_RECIPES, FROM_MAX = 6, 6, 4, 3, 8
# an item's `ways` (data.md, QD3) the book names as they are
WAY_HOWS = ("container", "skin", "pick", "fish", "make")
# ForeverDB's source kind -> the way and the record type its name is looked for in
NAMED = {
    "vendor": ("vendor", "npc"),
    "drop": ("drop", "npc"),
    "boss": ("drop", "npc"),
    "object": ("drop", "object"),
    "quest": ("quest", "quest"),
}
# a name the developers left unfinished: "[PH] Purple Prideclaw", "[DNT] Test" (do not translate)
PLACEHOLDER = re.compile(r"\[(PH|DNT)\]")
QUEST_LEVEL = re.compile(r"\s*\(level \d+\)\s*$")  # "An OOX of Your Own (level 50)"


def _frac(pct: float | None) -> float | None:
    return None if pct is None else round(pct / 100.0, ROUND)


def _place(m: int | None, x: float | None, y: float | None) -> list | None:
    if m is None or x is None or y is None:
        return None
    return [m, _frac(x), _frac(y)]


def _zones(maps: list[int | None]) -> list[int] | None:
    out: list[int] = []
    for m in maps:
        if m is not None and m not in out:
            out.append(m)
    return out or None


def read_hooks(path: Path) -> dict[str, str]:
    """Bastian's lines by wonder id; each passes the book's text check."""
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        hooks = tomllib.load(fh).get("hooks", {})
    for wid, text in hooks.items():
        check_text(text, f"{path.name} {wid}")
    return dict(hooks)


def read_scenes(path: Path) -> dict[str, str]:
    """The drawings' scene lines by wonder id or `chapter:<name>` (D5, tools/book_drawings.py
    draws from them); each passes the book's text check, as a page's `scene` does."""
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        scenes = tomllib.load(fh).get("scenes", {})
    for wid, text in scenes.items():
        check_text(text, f"{path.name} scene {wid}")
    return dict(scenes)


def zone_index(world: World) -> dict[str, int]:
    """A zone's name (lower case) -> its uiMapID; the lowest id wins a shared name."""
    out: dict[str, int] = {}
    for zid, rec in sorted(world.records.get("zone", {}).items()):
        name = (rec.get("name") or "").strip().lower()
        if name and name not in out:
            out[name] = zid
    return out


def _source_sentence(src: Source | None) -> str | None:
    if src is None or not src.text:
        return None
    text = plain(src.text)
    return {
        "vendor": f"Sold by {text}.",
        "drop": f"Drops from {text}.",
        "boss": f"Drops from {text}.",
        "quest": f"From the quest {text}.",
        "crafted": f"Made with {text}.",
        "object": f"Found in {text}.",
    }.get(src.kind or "", f"{text}.")


# ---------------------------------------------------------------- sources as references (R4.3)


def _placed(rec: dict | None) -> bool:
    """The world knows where it is: a place on a map, or the dungeon it stands in."""
    return rec is not None and (bool(rec.get("spawns")) or rec.get("dungeon") is not None)


class Ways:
    """What the world knows about how a thing is had: an item's droppers, vendors, quests and
    recipes, and the creatures, objects and quests by their names. Built once per build."""

    def __init__(self, world: World, zones: dict[str, int]) -> None:
        self.world = world
        self.zones = zones
        self.vendors: dict[int, list[int]] = {}
        self.quests: dict[int, list[int]] = {}
        self.recipes: dict[int, list[int]] = {}
        self.names: dict[str, dict[str, list[int]]] = {"npc": {}, "object": {}, "quest": {}}
        for nid, rec in sorted(world.records.get("npc", {}).items()):
            for row in rec.get("vendor") or ():
                self.vendors.setdefault(row[0], []).append(nid)
        for qid, rec in sorted(world.records.get("quest", {}).items()):
            rewards = rec.get("rewards") or {}
            for row in (*(rewards.get("items") or ()), *(rewards.get("choices") or ())):
                if qid not in self.quests.setdefault(row[0], []):
                    self.quests[row[0]].append(qid)
        for rid, rec in sorted(world.records.get("recipe", {}).items()):
            if rec.get("item") is not None:
                self.recipes.setdefault(rec["item"], []).append(rid)
        for kind, index in self.names.items():
            for rid, rec in sorted(world.records.get(kind, {}).items()):
                name = (rec.get("name") or "").strip().lower()
                if name:
                    index.setdefault(name, []).append(rid)

    def of_item(self, item: int | None) -> list[tuple[str, str]]:
        """The ways to an item the world holds, the likeliest of each first."""
        if item is None:
            return []
        rec = self.world.get("item", item) or {}
        rows = [("drop", d[0]) for d in (rec.get("drops") or ())[:FROM_DROPS]]
        npcs = self.world.records.get("npc", {})
        sellers = sorted(self.vendors.get(item, ()), key=lambda n: (not _placed(npcs.get(n)), n))
        rows += [("vendor", f"npc:{n}") for n in sellers[:FROM_VENDORS]]
        rows += [("quest", f"quest:{q}") for q in self.quests.get(item, ())[:FROM_QUESTS]]
        rows += [("craft", f"recipe:{r}") for r in self.recipes.get(item, ())[:FROM_RECIPES]]
        for way in rec.get("ways") or ():
            if way[0] in WAY_HOWS and isinstance(way[1], str) and ":" in way[1]:
                rows.append((way[0], way[1]))
        return rows

    def _holds(self, kind: str, rid: int, how: str, item: int | None) -> bool:
        """The record itself names the item: on its vendor list, in its loot, among its rewards."""
        rec = self.world.get(kind, rid) or {}
        if how == "vendor":
            return any(row[0] == item for row in rec.get("vendor") or ())
        if how == "drop":
            return any(row[0] == item for row in rec.get("loot") or ())
        rewards = rec.get("rewards") or {}
        rows = (*(rewards.get("items") or ()), *(rewards.get("choices") or ()))
        return any(row[0] == item for row in rows)

    def named(self, src: Source | None, item: int | None) -> tuple[tuple[str, str] | None, str]:
        """ForeverDB's source by its name -> the row, or None with why it stays a sentence.
        A name more than one record carries is settled by the record that names the item, then
        by the zone in the source's text; else it stays a sentence (two creatures of one name)."""
        if src is None or not src.text:
            return None, ""
        way = NAMED.get(src.kind or "")
        if way is None:
            return None, "" if src.kind == "crafted" else f"a source of kind {src.kind!r}"
        how, kind = way
        name, zone = src.text.strip(), None
        if kind == "quest":
            name = QUEST_LEVEL.sub("", name)
        elif src.zone_name and src.zone_name.lower() in self.zones:
            name, zone = name.rsplit(",", 1)[0].strip(), self.zones[src.zone_name.lower()]
        found = self.names[kind].get(name.lower(), [])
        if not found:
            return None, f"no {kind} is named {name!r}"
        if len(found) > 1 and item is not None:
            found = [r for r in found if self._holds(kind, r, how, item)] or found
        if len(found) > 1 and zone is not None:
            there = [
                r
                for r in found
                if any(s[0] == zone for s in (self.world.get(kind, r) or {}).get("spawns") or ())
            ]
            found = there or found
        if len(found) > 1:
            return None, f"{len(found)} {kind}s are named {name!r}"
        return (how, f"{kind}:{found[0]}"), ""


class Sources:
    """The `from` rows of the wonders, and what the build report says about them."""

    def __init__(self, ways: Ways) -> None:
        self.ways = ways
        self.resolved = 0  # wonders with at least one row
        self.misses: list[str] = []  # a named source that stayed a sentence

    def rows(self, wid: str, src: Source | None, item: int | None) -> list[list[str]] | None:
        """The named source first (it is the one the tale tells), then the item's other ways."""
        named, why = self.ways.named(src, item)
        rows = self.ways.of_item(item)
        if named:
            rows = [named, *(r for r in rows if r != named)]
        elif why and not rows:
            self.misses.append(f"{wid} ({why})")
        if rows:
            self.resolved += 1
        return [list(r) for r in rows[:FROM_MAX]] or None


# ---------------------------------------------------------------- the chains


def _applies(step: ChainStep, side: str) -> bool:
    return step.side is None or step.side == side


def chain_done(chain: Chain) -> dict | None:
    """When the game shows a chain done: the last step per side that a quest or an item ends.
    ``{ quests = { A = [ids], H = [ids] } }`` (any one of the side's ids), or ``{ item = id }``."""
    for step in reversed(chain.steps):
        if step.item and not step.quest and not step.any_quests:
            return {"item": step.item}
        if step.quest or step.any_quests:
            break
    quests: dict[str, list[int]] = {}
    for side in ("A", "H"):
        if chain.side and chain.side != side:
            continue
        for step in reversed(chain.steps):
            if not _applies(step, side):
                continue
            ids = [step.quest] if step.quest else list(step.any_quests)
            if ids:
                quests[side] = ids
                break
    return {"quests": quests} if quests else None


def _chain_side(chain: Chain) -> str | None:
    if chain.side:
        return chain.side
    sides = {s.side for s in chain.steps}
    if sides == {"A"} or sides == {"H"}:
        return sides.pop()
    return None


def chain_record(chain: Chain, hooks: dict[str, str]) -> tuple[str, dict]:
    """A chain is Forever's own content with its steps told, so it is `in` whether or not
    players finished it: the unsolved ones are told as unsolved (E1, the Secrets chapter)."""
    wid = f"chain:{chain.key}"
    chapter, kind = CHAIN_CHAPTER.get(chain.cat, (SECRETS, "chain"))
    if chapter == SECRETS and kind == "chain" and UNSOLVED in chain.name.lower():
        kind = UNSOLVED
    steps = []
    for s in chain.steps:
        place = _place(s.map, s.x_pct, s.y_pct)
        steps.append(
            {
                "q": s.quest,
                "side": s.side,
                "title": plain(s.title),
                "text": plain(s.text),
                "tip": plain(s.tip),
                "npc": plain(s.npc),
                "place": place,
            }
        )
    first = next((s for s in steps if s["place"]), None)
    return wid, {
        "name": plain(chain.name),
        "chapter": chapter,
        "kind": kind,
        "hook": hooks.get(wid),
        "tale": plain(chain.why),
        "start": plain(chain.start),
        "note": plain(chain.note),
        "levelMin": chain.level,
        "zones": _zones([s.map for s in chain.steps]),
        "place": first["place"] if first else None,
        "side": _chain_side(chain),
        "gives": list(chain.rewards) or None,
        "steps": steps,
        "done": chain_done(chain),
        "state": IN,
    }


# ---------------------------------------------------------------- the collections


def _zone_of(src: Source | None, zones: dict[str, int]) -> list[int] | None:
    name = src.zone_name if src else None
    zid = zones.get(name.lower()) if name else None
    return [zid] if zid else None


def _out_of_client(
    name: str | None,
    spell: int | None,
    item: int | None,
    src: Source | None,
    client: ClientIds | None,
) -> str | None:
    """Why a mount or a pet cannot be had (E2, "out"), or None."""
    if PLACEHOLDER.search(name or ""):
        return "a placeholder name in the client: not finished"
    if client is not None and spell is not None and spell not in client.spells:
        return "its spell is not in the client"
    if client is not None and item is not None and item not in client.items:
        return "its item is not in the client"
    if item is None and src is None:
        return "no item in the client teaches it, and no other way is known"
    return None


def collection_records(
    w: Wonders,
    zones: dict[str, int],
    hooks: dict[str, str],
    summons: dict[int, int] | None = None,
    client: ClientIds | None = None,
    sources: Sources | None = None,
) -> tuple[dict, dict[str, str]]:
    """The mounts, pets and titles, and the ones that are out with their reason. `summons`
    ({ spell: creature }, the client's SpellEffect) gives a mount or a pet its creature, so the
    book shows its model (BK8). `client`: the client's ids (none: nothing is judged against
    them). `sources`: the references' resolver (none: no `from`)."""
    summons = summons or {}
    out: dict[str, dict] = {}
    gone: dict[str, str] = {}

    def comes_from(wid: str, src: Source | None, item: int | None) -> list | None:
        return sources.rows(wid, src, item) if sources else None

    for m in w.collections.mounts:
        wid = f"mount:{m.spell}"
        why = _out_of_client(m.name, m.spell, m.item, m.source, client)
        if why:
            gone[wid] = why
            continue
        out[wid] = {
            "name": plain(m.name),
            "chapter": COLLECTIONS,
            "kind": "mount",
            "hook": hooks.get(wid),
            "tale": plain(m.why) or _source_sentence(m.source),
            "levelMin": m.level,
            "zones": _zone_of(m.source, zones),
            "side": m.side,
            "facets": {"source": m.source.kind if m.source else None, "class": m.cls},
            "gives": [m.item] if m.item else None,
            "done": {"spell": m.spell, "item": m.item},
            "npc": summons.get(m.spell),
            "state": IN if m.source and m.source.seen else UNKNOWN,
            "from": comes_from(wid, m.source, m.item),
        }
    for p in w.collections.pets:
        wid = f"pet:{p.spell}"
        why = _out_of_client(p.name, p.spell, p.item, p.source, client)
        if why:
            gone[wid] = why
            continue
        out[wid] = {
            "name": plain(p.name),
            "chapter": COLLECTIONS,
            "kind": "pet",
            "hook": hooks.get(wid),
            "tale": plain(p.why) or _source_sentence(p.source),
            "zones": _zone_of(p.source, zones),
            "facets": {"source": p.source.kind if p.source else None},
            "gives": [p.item] if p.item else None,
            "done": {"spell": p.spell, "item": p.item},
            "npc": summons.get(p.spell),
            "state": IN if p.source and p.source.seen else UNKNOWN,
            "from": comes_from(wid, p.source, p.item),
        }
    for t in w.collections.titles:
        wid = f"title:{t.id}"
        if PLACEHOLDER.search(t.name):
            gone[wid] = "a placeholder name in the client: not finished"
            continue
        out[wid] = {
            "name": plain(t.name),
            "chapter": COLLECTIONS,
            "kind": "title",
            "hook": hooks.get(wid),
            "tale": plain(t.how),
            "levelMin": t.level,
            "done": {"title": t.id},
            # a title Forever added tells in the client how it is had; Classic's rank titles are
            # in the client and nobody reported one
            "state": IN if t.new else UNKNOWN,
        }
    return out, gone


# ---------------------------------------------------------------- the rares


def _respawn(lo: int | None, hi: int | None) -> str | None:
    def hm(s: int) -> str:
        h, m = divmod(round(s / 60), 60)
        return f"{h}h {m:02d}" if h else f"{m} min"

    if lo and hi and hi != lo:
        return f"Comes back after {hm(lo)} to {hm(hi)}."
    if lo or hi:
        return f"Comes back after {hm(lo or hi)}."  # type: ignore[arg-type]
    return None


def rare_records(
    w: Wonders, hooks: dict[str, str], world: World | None = None
) -> tuple[dict, dict[str, str]]:
    """The rares, and the ones that are out: a creature with no place at all (ForeverDB's
    spots, the world's places, a dungeon) is nowhere to hunt."""
    out: dict[str, dict] = {}
    gone: dict[str, str] = {}
    for r in w.rares:
        wid = f"rare:{r.npc}"
        if not r.spots and not r.instance and not _placed(world.get("npc", r.npc) if world else {}):
            gone[wid] = "the creature has no place"
            continue
        level = (
            f"level {r.level_lo}"
            if r.level_lo == r.level_hi or r.level_hi is None
            else f"level {r.level_lo} to {r.level_hi}"
        )
        what = f"A {r.rank or 'rare'} {(r.creature_type or 'creature').lower()}, {level}."
        if r.level_lo is None:
            what = f"A {r.rank or 'rare'} {(r.creature_type or 'creature').lower()}."
        tale = " ".join(x for x in (what, _respawn(r.respawn_lo, r.respawn_hi)) if x)
        first = r.spots[0] if r.spots else None
        out[wid] = {
            "name": plain(r.name),
            "chapter": RARES,
            "kind": r.rank or "rare",
            "hook": hooks.get(wid),
            "tale": tale,
            "levelMin": r.level_lo,
            "levelMax": r.level_hi,
            "zones": _zones([s[0] for s in r.spots]),
            "place": _place(*first) if first else None,
            "facets": {"type": r.creature_type, "dungeon": r.instance or None},
            "gives": list(r.loot[:LOOT_SHOWN]) or None,
            "npc": r.npc,
            "state": IN if r.seen else UNKNOWN,
        }
    return out, gone


# ---------------------------------------------------------------- the library and the camp


def _book_side(b: LibraryBook) -> str | None:
    sides = set(b.quests)
    return sides.pop() if len(sides) == 1 else None


def library_and_camp_records(
    w: Wonders,
    world: World,
    hooks: dict[str, str],
    client: ClientIds | None = None,
    sources: Sources | None = None,
) -> tuple[dict, dict[str, str]]:
    """The library's books (Collections) and the camp kits and items (Camp), and the ones that
    are out. A camp item is new in Forever with its recipe known, so it is `in`."""
    out: dict[str, dict] = {}
    gone: dict[str, str] = {}

    def comes_from(wid: str, item: int) -> list | None:
        return sources.rows(wid, None, item) if sources else None

    for b in w.books:
        if b.status < 0:
            continue  # only in the client's files (Season of Discovery)
        wid = f"book:{b.item}"
        if client is not None and b.item not in client.items:
            gone[wid] = "its item is not in the client"
            continue
        item = world.get("item", b.item)
        name = item.get("name") if item else None
        if not name:
            gone[wid] = "the item has no name in the world"
            continue
        first = b.places[0] if b.places else None
        out[wid] = {
            "name": plain(name),
            "chapter": COLLECTIONS,
            "kind": "library book",
            "hook": hooks.get(wid),
            "tale": (f"Found in {plain(b.where)}. " if b.where else "")
            + "A librarian takes it for the library's rewards.",
            "zones": _zones([p[0] for p in b.places]),
            "place": _place(*first) if first else None,
            "side": _book_side(b),
            "facets": {"source": "object"},  # a book lies in the world
            "gives": [b.item],
            "done": {"item": b.item, "quests": {s: [q] for s, q in sorted(b.quests.items())}}
            if b.quests
            else {"item": b.item},
            "state": IN if b.status == 2 else UNKNOWN,
            "from": comes_from(wid, b.item),
        }
    for c in w.camp:
        wid = f"camp:{c.item}"
        if client is not None and c.item not in client.items:
            gone[wid] = "its item is not in the client"
            continue
        out[wid] = {
            "name": plain(c.name),
            "chapter": CAMP,
            "kind": "camp kit" if c.kit else "camp item",
            "hook": hooks.get(wid),
            "tale": plain(c.effect),
            "facets": {"profession": c.profession or None, "skill": c.skill or None},
            "gives": [c.item],
            "done": {"item": c.item},
            "state": IN,
            "from": comes_from(wid, c.item),
        }
    return out, gone


# ---------------------------------------------------------------- into the world


def _clean(rec: dict) -> dict:
    """No empty values in the pack: None and empty containers leave."""
    out = {}
    for k, v in rec.items():
        if isinstance(v, dict):
            v = {kk: vv for kk, vv in v.items() if vv is not None} or None
        if v is None or v == [] or v == {}:
            continue
        out[k] = v
    return out


def _kind_of(wid: str) -> str:
    return wid.split(":", 1)[0]


def _counts(records: dict[str, dict], gone: dict[str, str]) -> str:
    """ "mount 18 in, 99 unknown, 24 out; ..." by the id's kind, the kinds sorted."""
    kinds = sorted({_kind_of(w) for w in (*records, *gone)})
    parts = []
    for kind in kinds:
        states = [r["state"] for w, r in records.items() if _kind_of(w) == kind]
        out = sum(1 for w in gone if _kind_of(w) == kind)
        parts.append(f"{kind} {states.count(IN)} in, {states.count(UNKNOWN)} unknown, {out} out")
    return "; ".join(parts)


def add_wonders(
    world: World,
    w: Wonders,
    hooks_path: Path,
    summons: dict[int, int] | None = None,
    client: ClientIds | None = None,
) -> int:
    """Adds every obtainable wonder to the world's ``wonder`` records; returns how many. The
    ones that are out are dropped with their reason (the build report lists them), and the
    report's notes carry the counts per state and the sources that stayed a sentence.
    `summons` as `collection_records` takes it (none: no models for mounts and pets); `client`:
    the client's own ids (none: nothing is judged against the client)."""
    hooks = read_hooks(hooks_path)
    zones = zone_index(world)
    sources = Sources(Ways(world, zones))
    records: dict[str, dict] = {}
    gone: dict[str, str] = {}
    for chain in w.chains:
        wid, rec = chain_record(chain, hooks)
        records[wid] = rec
    for found, out in (
        library_and_camp_records(w, world, hooks, client, sources),
        collection_records(w, zones, hooks, summons, client, sources),
        rare_records(w, hooks, world),
    ):
        records.update(found)
        gone.update(out)
    unknown = sorted(set(hooks) - set(records) - set(gone))
    if unknown:
        raise BookError(f"wonders.toml: lines for wonders that do not exist: {', '.join(unknown)}")
    entrances = {f"chapter:{c}" for c in ("gold", SECRETS, COLLECTIONS, CAMP, RARES)}
    unknown = sorted(set(read_scenes(hooks_path)) - set(records) - set(gone) - entrances)
    if unknown:
        raise BookError(f"wonders.toml: scenes for wonders that do not exist: {', '.join(unknown)}")
    for wid in sorted(gone):
        world.drop("wonder", wid, gone[wid])
    for wid in sorted(records):
        world.add("wonder", wid, _clean(records[wid]))  # type: ignore[arg-type]
    states = [r["state"] for r in records.values()]
    judged = "held against the client's items and spells" if client else "the client not read"
    world.notes.append(
        f"wonders: {states.count(IN)} in, {states.count(UNKNOWN)} unknown, {len(gone)} out "
        f"({judged}): {_counts(records, gone)}"
    )
    with_from = sum(1 for r in records.values() if r.get("from"))
    note = f"wonder sources: {with_from} wonders name their sources as references"
    if sources.misses:
        note += f"; {len(sources.misses)} named sources stayed a sentence: " + ", ".join(
            sorted(sources.misses)
        )
    world.notes.append(note)
    return len(records)
