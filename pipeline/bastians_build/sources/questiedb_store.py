"""QuestieDB's baked store (sources.md, read since 06.11.2026): the NPCs, objects and quests of its
Forever build, which hold what no other source has for the zones Forever added; and its items
(10.11.2026, plan-quest-links.md QD1): who drops, holds and sells one.

The addon keeps its data in the TOC, one metadata line per field, so the client hands it over
without loading a file:

    ## X-Npc-254089-S: <base64>           the row: a CBOR array or map, field number -> value
    ## X-Npc-254089-7: <base64>           one field of its own
    ## X-Npc-254089-7: ~3~                the same, cut in three parts that follow as
    ## X-Npc-254089-7-1: <base64>         -1, -2, -3

Field numbers are the addon's `src/meta/*Meta.lua` (an item's: `itemMeta.lua`, read 10.11.2026
in 1.0.13). Spawns are `{ [zone] = { {x, y, phase?} } }`
in map percent, the zone an AreaTable id. An NPC's level 9999 is a placeholder and stays unknown.
"""

from __future__ import annotations

import base64
import re
import struct
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

LINE = re.compile(r"^## X-(Quest|Npc|Object|Item)-(\d+)-(\w+?)(?:-(\d+))?: (.*)$")
PARTS = re.compile(r"~\d+~")
PLACEHOLDER_LEVEL = 9999

Places = dict[int, list[tuple[float, float]]]  # zone (AreaTable id) -> points in map percent


class StoreError(ValueError):
    """The store does not read as CBOR."""


def _cbor(b: bytes, i: int = 0):
    head = b[i]
    i += 1
    major, info = head >> 5, head & 31
    if major == 7:
        simple = {20: False, 21: True, 22: None, 23: None}
        if info in simple:
            return simple[info], i
        sizes = {25: (">e", 2), 26: (">f", 4), 27: (">d", 8)}
        if info not in sizes:
            raise StoreError(f"simple value {info}")
        fmt, size = sizes[info]
        return struct.unpack(fmt, b[i : i + size])[0], i + size
    if info < 24:
        n = info
    elif info <= 27:
        size = 1 << (info - 24)
        n = int.from_bytes(b[i : i + size], "big")
        i += size
    else:
        raise StoreError(f"indefinite length {head:#x}")
    if major == 0:
        return n, i
    if major == 1:
        return -1 - n, i
    if major in (2, 3):
        return b[i : i + n].decode("utf-8", "replace"), i + n
    if major == 4:
        out = []
        for _ in range(n):
            value, i = _cbor(b, i)
            out.append(value)
        return out, i
    if major == 5:
        table = {}
        for _ in range(n):
            key, i = _cbor(b, i)
            table[key], i = _cbor(b, i)
        return table, i
    return _cbor(b, i)  # 6: a tag, the value follows


def decode(text: str):
    return _cbor(base64.b64decode(text))[0]


def _rows(lines: Iterable[str]) -> dict[str, dict[int, dict[int | str, object]]]:
    """kind -> id -> field number -> value, the parts of a cut field joined."""
    raw: dict[str, dict[int, dict]] = {}
    for line in lines:
        if not line.startswith("## X-"):
            continue
        m = LINE.match(line.rstrip("\r\n"))
        if not m:
            continue
        kind, entity, name, part, value = m.groups()
        fields = raw.setdefault(kind, {}).setdefault(int(entity), {})
        if part is not None:
            fields.setdefault(name, {})[int(part)] = value
        elif PARTS.fullmatch(value):
            fields.setdefault(name, {})
        else:
            fields[name] = value
    out: dict[str, dict[int, dict]] = {}
    for kind, entities in raw.items():
        rows = out.setdefault(kind, {})
        for entity, fields in entities.items():
            row: dict = {}
            for name, value in fields.items():
                if isinstance(value, dict):
                    value = "".join(value[i] for i in sorted(value))
                decoded = decode(value)
                if name == "S":
                    items = decoded.items() if isinstance(decoded, dict) else enumerate(decoded, 1)
                    for key, item in items:
                        if str(key).isdigit():  # "p" is the row's presence mask
                            row[int(key)] = item
                elif name.isdigit():
                    row[int(name)] = decoded
            rows[entity] = row
    return out


@dataclass(frozen=True)
class StoreNpc:
    id: int
    name: str | None
    level: int | None
    level_max: int | None
    rank: int
    places: Places
    faction_template: int | None
    friendly: str | None  # "A", "H", "AH", or None when hostile to both
    subname: str | None
    npc_flags: int | None


@dataclass(frozen=True)
class StoreObject:
    id: int
    name: str | None
    places: Places


@dataclass(frozen=True)
class StoreQuest:
    id: int
    name: str | None
    level: int | None
    min_level: int | None
    races: int | None
    classes: int | None
    zone: int | None  # AreaTable id when positive, a quest sort when negative
    starts_npc: tuple[int, ...] = ()
    starts_object: tuple[int, ...] = ()
    starts_item: tuple[int, ...] = ()
    ends_npc: tuple[int, ...] = ()
    ends_object: tuple[int, ...] = ()
    objective_text: str | None = None
    creatures: tuple[int, ...] = ()
    objects: tuple[int, ...] = ()
    items: tuple[int, ...] = ()
    pre_all: tuple[int, ...] = ()
    pre_any: tuple[int, ...] = ()
    next_quest: int | None = None
    exclusive: tuple[int, ...] = ()
    rep: tuple[tuple[int, int], ...] = ()
    # the links of package QD3 (plan-quest-links.md G3, G6); questMeta.lua's fields 11, 9, 29
    source_item: int | None = None  # the item the giver hands over
    trigger_end: Places | None = None  # where the quest is finished by going there
    # the things to do the quest log does not list: (the refs named, where)
    extra: tuple[tuple[tuple[str, ...], Places], ...] = ()


@dataclass(frozen=True)
class StoreItem:
    """Where an item comes from; the store has no chance for any of it."""

    id: int
    npc_drops: tuple[int, ...] = ()  # creatures
    object_drops: tuple[int, ...] = ()  # objects
    item_drops: tuple[int, ...] = ()  # the items that hold it (containers)
    vendors: tuple[int, ...] = ()  # creatures


@dataclass
class Store:
    npcs: dict[int, StoreNpc] = field(default_factory=dict)
    objects: dict[int, StoreObject] = field(default_factory=dict)
    quests: dict[int, StoreQuest] = field(default_factory=dict)
    items: dict[int, StoreItem] = field(default_factory=dict)  # only those with a source


def _level(value) -> int | None:
    return int(value) if value and value != PLACEHOLDER_LEVEL else None


def _places(value) -> Places:
    out: Places = {}
    if not isinstance(value, dict):
        return out
    for zone, points in value.items():
        rows = [
            (float(p[0]), float(p[1]))
            for p in points or ()
            if isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[1] is not None
        ]
        rows = [p for p in rows if 0 <= p[0] <= 100 and 0 <= p[1] <= 100]
        if rows:
            out[int(zone)] = rows
    return out


def _group(value, index: int) -> list:
    """The index-th (1-based) of positional groups, kept as an array or, with gaps, as a map."""
    if isinstance(value, dict):
        return value.get(index) or value.get(str(index)) or []
    if isinstance(value, list) and index <= len(value):
        return value[index - 1] or []
    return []


def _ids(value) -> tuple[int, ...]:
    """An id list; one kept as a map (an array with gaps) in the order of its keys."""
    if isinstance(value, dict):
        value = [value[key] for key in sorted(value, key=lambda k: (not isinstance(k, int), k))]
    return tuple(int(v) for v in value or () if isinstance(v, int) and not isinstance(v, bool))


def _targets(value, index: int) -> tuple[int, ...]:
    """The ids of one objective group, rows { id, text, ... }."""
    rows = _group(value, index)
    return tuple(int(r[0]) for r in rows if isinstance(r, list) and r and isinstance(r[0], int))


def _npc(entity: int, row: dict) -> StoreNpc:
    return StoreNpc(
        id=entity,
        name=row.get(1),
        level=_level(row.get(4)),
        level_max=_level(row.get(5)),
        rank=int(row.get(6) or 0),
        places=_places(row.get(7)),
        faction_template=row.get(12),
        friendly=row.get(13),
        subname=row.get(14),
        npc_flags=row.get(15),
    )


def _quest(entity: int, row: dict) -> StoreQuest:
    lines = [t for t in row.get(8) or () if isinstance(t, str) and t.strip()]
    return StoreQuest(
        id=entity,
        name=row.get(1),
        level=_level(row.get(5)),
        min_level=_level(row.get(4)),
        races=row.get(6) or None,
        classes=row.get(7) or None,
        zone=row.get(17),
        starts_npc=_ids(_group(row.get(2), 1)),
        starts_object=_ids(_group(row.get(2), 2)),
        starts_item=_ids(_group(row.get(2), 3)),
        ends_npc=_ids(_group(row.get(3), 1)),
        ends_object=_ids(_group(row.get(3), 2)),
        objective_text=" ".join(lines) or None,
        creatures=_targets(row.get(10), 1),
        objects=_targets(row.get(10), 2),
        items=_targets(row.get(10), 3),
        pre_all=_ids(row.get(12)),
        pre_any=_ids(row.get(13)),
        next_quest=row.get(22) or None,
        exclusive=_ids(row.get(16)),
        rep=tuple(
            (int(r[0]), int(r[1])) for r in row.get(26) or () if isinstance(r, list) and len(r) > 1
        ),
        source_item=row.get(11) if isinstance(row.get(11), int) and row.get(11) else None,
        trigger_end=_trigger(row.get(9)),
        extra=_extra(row.get(29)),
    )


EXTRA_KINDS = {"monster": "npc", "creature": "npc", "npc": "npc", "object": "object"}


def _trigger(value) -> Places | None:
    """`triggerEnd` = { text, { [zone] = { {x, y} } } }: the places, or None without any."""
    if isinstance(value, list) and len(value) > 1:
        return _places(value[1]) or None
    return None


def _extra(value) -> tuple[tuple[tuple[str, ...], Places], ...]:
    """`extraObjectives` = { { spawns or nil, icon, text, objective index, { {kind, id} } } }."""
    out = []
    for row in value or ():
        if not isinstance(row, list) or not row:
            continue
        refs = []
        for ref in row[4] if len(row) > 4 and isinstance(row[4], list) else ():
            if isinstance(ref, list) and len(ref) > 1 and isinstance(ref[1], int):
                kind = EXTRA_KINDS.get(str(ref[0]))
                if kind:
                    refs.append(f"{kind}:{ref[1]}")
        places = _places(row[0])
        if refs or places:
            out.append((tuple(refs), places))
    return tuple(out)


def _item(entity: int, row: dict) -> StoreItem:
    return StoreItem(
        id=entity,
        npc_drops=_ids(row.get(2)),
        object_drops=_ids(row.get(3)),
        item_drops=_ids(row.get(4)),
        vendors=_ids(row.get(14)),
    )


def parse_store(lines: Iterable[str]) -> Store:
    rows = _rows(lines)
    items = (_item(i, r) for i, r in rows.get("Item", {}).items())
    return Store(
        npcs={i: _npc(i, r) for i, r in rows.get("Npc", {}).items()},
        objects={
            i: StoreObject(i, r.get(1), _places(r.get(4)))
            for i, r in rows.get("Object", {}).items()
        },
        quests={i: _quest(i, r) for i, r in rows.get("Quest", {}).items()},
        items={
            it.id: it
            for it in items
            if it.npc_drops or it.object_drops or it.item_drops or it.vendors
        },
    )


def read_store(toc: Path) -> Store:
    with toc.open(encoding="utf-8", errors="replace") as fh:
        return parse_store(fh)
