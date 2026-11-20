"""ForeverDB's special content for Bastian's Book (ADR 0080, book.md "The data").

``SpecialQuests.lua`` (the secret, camping and secret-pet chains), ``Collections.lua`` (mounts,
companion pets, titles), ``Rares.lua``, ``Books.lua`` (the library books) and ``Camp.lua`` (the camp
kits). Formats read 16.11.2026 on ForeverDB 0.62.1, client build 1.60.1.70938.

Coordinates stay as the file has them, **map percent 0..100** on ``map``; the book converts.
Unknown stays ``None``. Every ``parse_*`` takes the file text and does no I/O.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .luatable import to_python
from .luatext import run_text, sorted_items

# ---------------------------------------------------------------- SpecialQuests.lua


@dataclass(frozen=True)
class ChainStep:
    quest: int | None  # q
    any_quests: tuple[int, ...]  # qany: one of these
    item: int | None  # the step ends when the item is had
    side: str | None  # "A", "H" or None (both)
    title: str | None
    text: str | None  # t
    tip: str | None
    npc: str | None  # the giver's name, as the file has it
    map: int | None
    x_pct: float | None
    y_pct: float | None
    seen: bool


@dataclass(frozen=True)
class Chain:
    key: str
    name: str
    cat: str  # "Secret", "Secret pets", "Camping", "Collections"
    side: str | None
    start: str | None
    why: str | None
    note: str | None
    seen: bool
    level: int | None  # the lowest level the chain asks for, None when the file has none
    rewards: tuple[int, ...]
    steps: tuple[ChainStep, ...]


def _side(value: Any) -> str | None:
    s = str(value or "").upper()
    return s if s in ("A", "H") else None


def _num(value: Any) -> float | None:
    return None if value is None else float(value)


def _opt_int(value: Any) -> int | None:
    return None if value in (None, 0, "") else int(value)


def parse_special_quests(text: str) -> list[Chain]:
    """``ns.specialQuests.chains`` in the file's order."""
    data = to_python(run_text(text, "SpecialQuests.lua").specialQuests) or {}
    out = []
    for c in data.get("chains") or []:
        steps = []
        for s in c.get("steps") or []:
            steps.append(
                ChainStep(
                    quest=_opt_int(s.get("q")),
                    any_quests=tuple(int(q) for q in s.get("qany") or []),
                    item=_opt_int(s.get("item")),
                    side=_side(s.get("side")),
                    title=s.get("title") or None,
                    text=s.get("t") or None,
                    tip=s.get("tip") or None,
                    npc=s.get("npc") or None,
                    map=_opt_int(s.get("m")),
                    x_pct=_num(s.get("x")),
                    y_pct=_num(s.get("y")),
                    seen=bool(s.get("seen")),
                )
            )
        lv = c.get("lv") or []
        out.append(
            Chain(
                key=str(c["key"]),
                name=str(c["name"]),
                cat=str(c.get("cat") or ""),
                side=_side(c.get("side")),
                start=c.get("start") or None,
                why=c.get("why") or None,
                note=c.get("note") or None,
                seen=bool(c.get("seen")),
                level=int(lv[0]) if lv else None,
                rewards=tuple(int(i) for i in c.get("reward") or []),
                steps=tuple(steps),
            )
        )
    return out


# ---------------------------------------------------------------- Collections.lua

SOURCE_KINDS = {
    "v": "vendor",
    "d": "drop",
    "b": "boss",
    "q": "quest",
    "c": "crafted",
    "o": "object",
}


@dataclass(frozen=True)
class Source:
    kind: str | None  # SOURCE_KINDS' words
    text: str | None  # "Gregor MacVince, Dustwallow Marsh"
    seen: bool  # players saw it in Forever (else Classic data)

    @property
    def zone_name(self) -> str | None:
        """The text after the last comma: the file names a vendor's zone that way."""
        if not self.text or "," not in self.text:
            return None
        return self.text.rsplit(",", 1)[1].strip() or None


def parse_source(raw: str) -> Source | None:
    """``kind~text~seen``; empty: None."""
    if not raw:
        return None
    parts = raw.split("~")
    kind = SOURCE_KINDS.get(parts[0])
    text = parts[1] if len(parts) > 1 and parts[1] else None
    seen = len(parts) > 2 and parts[2] == "1"
    return Source(kind, text, seen)


@dataclass(frozen=True)
class Mount:
    spell: int
    name: str
    item: int | None
    side: str | None
    level: int | None  # the riding level
    source: Source | None
    why: str | None
    cls: str | None  # a class mount: the class token


@dataclass(frozen=True)
class Pet:
    spell: int
    name: str
    item: int | None
    source: Source | None
    why: str | None


@dataclass(frozen=True)
class Title:
    id: int
    name: str
    level: int | None
    how: str | None
    new: bool = False  # the flag "n": a title Forever added (not one of Classic's)


@dataclass
class Collections:
    mounts: list[Mount] = field(default_factory=list)
    pets: list[Pet] = field(default_factory=list)
    titles: list[Title] = field(default_factory=list)


def _cols(raw: str, n: int) -> list[str]:
    cols = raw.split("|")
    return cols + [""] * (n - len(cols))


def parse_collections(text: str) -> Collections:
    ns = run_text(text, "Collections.lua")
    out = Collections()
    for spell, raw in sorted_items(ns.collMounts or {}):
        name, item, side, level, _flags, source, why, cls = _cols(str(raw), 8)[:8]
        out.mounts.append(
            Mount(
                int(spell),
                name,
                _opt_int(int(item)) if item else None,
                _side(side),
                int(level) if level else None,
                parse_source(source),
                why or None,
                cls or None,
            )
        )
    for spell, raw in sorted_items(ns.collPets or {}):
        name, item, _flags, source, why = _cols(str(raw), 5)[:5]
        out.pets.append(
            Pet(
                int(spell),
                name,
                _opt_int(int(item)) if item else None,
                parse_source(source),
                why or None,
            )
        )
    for tid, raw in sorted_items(ns.collTitles or {}):
        name, level, flags, how = _cols(str(raw), 4)[:4]
        out.titles.append(
            Title(int(tid), name, int(level) or None if level else None, how or None, "n" in flags)
        )
    return out


# ---------------------------------------------------------------- Rares.lua

RANKS = {1: "elite", 2: "rare elite", 3: "boss", 4: "rare"}


@dataclass(frozen=True)
class Rare:
    npc: int
    name: str
    level_lo: int | None
    level_hi: int | None
    rank: str | None
    creature_type: str | None
    respawn_lo: int | None  # seconds
    respawn_hi: int | None
    spots: tuple[tuple[int, float, float], ...]  # (map, x pct, y pct): seen first, else Classic
    seen: bool  # players saw it in Forever
    loot: tuple[int, ...]  # item ids, the file's order
    instance: bool


def _spots(raw: str) -> list[tuple[int, float, float]]:
    """``map:x,y;x,y|...`` (several maps separated by spaces or slashes are not in 0.62.1)."""
    out = []
    for part in filter(None, raw.split(" ")):
        if ":" not in part:
            continue
        m, rest = part.split(":", 1)
        for xy in filter(None, rest.split(";")):
            x, _, y = xy.partition(",")
            try:
                out.append((int(m), float(x), float(y)))
            except ValueError:
                continue
    return out


def parse_rares(text: str) -> list[Rare]:
    ns = run_text(text, "Rares.lua")
    out = []
    for npc, raw in sorted_items(ns.rareRows or {}):
        cols = _cols(str(raw), 17)
        name, lo, hi, _lsrc, rank, _rsrc, ctype, rlo, rhi = cols[:9]
        spawns, seen_spots, loot, inst = cols[12], cols[13], cols[15], cols[16]
        seen = _spots(seen_spots)
        items = []
        for entry in filter(None, loot.split("~")):
            first = entry.split(",", 1)[0]
            if first.isdigit():
                items.append(int(first))
        out.append(
            Rare(
                npc=int(npc),
                name=name,
                level_lo=int(lo) if lo else None,
                level_hi=int(hi) if hi else None,
                rank=RANKS.get(int(rank)) if rank.isdigit() else None,
                creature_type=ctype or None,
                respawn_lo=int(rlo) if rlo.isdigit() else None,
                respawn_hi=int(rhi) if rhi.isdigit() else None,
                spots=tuple(seen or _spots(spawns)),
                seen=bool(seen),
                loot=tuple(items),
                instance=bool(inst),
            )
        )
    return out


# ---------------------------------------------------------------- Books.lua


@dataclass(frozen=True)
class LibraryBook:
    item: int
    status: int  # 2 seen in Forever, 1 reported, 0 unknown, -1 only in the client's files
    quests: dict[str, int]  # side -> the hand-in quest
    places: tuple[tuple[int, float, float], ...]  # (map, x pct, y pct), most finds first
    where: str | None


def parse_books(text: str) -> list[LibraryBook]:
    data = to_python(run_text(text, "Books.lua").books) or {}
    out = []
    for row in data.get("books") or []:
        item, status, quests, places, where = (list(row) + [None] * 5)[:5]
        found = sorted(
            (p for p in places or [] if len(p) >= 3),
            key=lambda p: -(p[3] if len(p) > 3 else 0),
        )
        out.append(
            LibraryBook(
                item=int(item),
                status=int(status),
                quests={_side(k) or str(k): int(v) for k, v in (quests or {}).items()},
                places=tuple((int(p[0]), float(p[1]), float(p[2])) for p in found),
                where=where or None,
            )
        )
    return out


# ---------------------------------------------------------------- Camp.lua


@dataclass(frozen=True)
class CampItem:
    item: int
    name: str
    profession: str
    tier: int
    skill: int
    kit: bool  # a campfire kit (the camp's heart)
    effect: str | None


def parse_camp(text: str) -> list[CampItem]:
    rows = to_python(run_text(text, "Camp.lua").camp) or []
    return [
        CampItem(
            item=int(r["item"]),
            name=str(r["name"]),
            profession=str(r.get("prof") or ""),
            tier=int(r.get("tier") or 0),
            skill=int(r.get("skill") or 0),
            kit=bool(r.get("kit")),
            effect=r.get("fx") or None,
        )
        for r in rows
    ]


# ---------------------------------------------------------------- reading the files


@dataclass
class Wonders:
    chains: list[Chain] = field(default_factory=list)
    collections: Collections = field(default_factory=Collections)
    rares: list[Rare] = field(default_factory=list)
    books: list[LibraryBook] = field(default_factory=list)
    camp: list[CampItem] = field(default_factory=list)


def read_wonders(data_dir: Path) -> Wonders:
    """The five files from ForeverDB's ``Data`` folder; a missing file gives an empty part."""

    def text(name: str) -> str | None:
        path = data_dir / name
        return path.read_text(encoding="utf-8") if path.is_file() else None

    out = Wonders()
    if (t := text("SpecialQuests.lua")) is not None:
        out.chains = parse_special_quests(t)
    if (t := text("Collections.lua")) is not None:
        out.collections = parse_collections(t)
    if (t := text("Rares.lua")) is not None:
        out.rares = parse_rares(t)
    if (t := text("Books.lua")) is not None:
        out.books = parse_books(t)
    if (t := text("Camp.lua")) is not None:
        out.camp = parse_camp(t)
    return out
