"""Derived indexes (data.md): by zone, quests by giver, ender and item, the quest graph for the
Quests logic (start and turn-in map, followers, chain components). Pure over the World."""

from __future__ import annotations

from collections.abc import Callable, Iterable

from bastians_build import book, market, mill
from bastians_build.model import World

Index = dict[object, list[int]]


def _grouped(pairs: Iterable[tuple[object, int]]) -> Index:
    out: dict[object, set[int]] = {}
    for key, record_id in pairs:
        out.setdefault(key, set()).add(record_id)
    return {key: sorted(ids) for key, ids in out.items()}


def by_zone(world: World, record_type: str) -> Index:
    """IDs per uiMapID: from the `zone` field and from every spawn's map."""

    def pairs():
        for record_id, rec in world.records.get(record_type, {}).items():
            if rec.get("zone") is not None:
                yield rec["zone"], record_id
            for spawn in rec.get("spawns") or []:
                yield spawn[0], record_id

    return _grouped(pairs())


def quests_by(world: World, field_name: str) -> Index:
    """Quest IDs per entity ref listed in `starts` or `ends`."""

    def pairs():
        for quest_id, rec in world.records.get("quest", {}).items():
            for ref in rec.get(field_name) or []:
                yield ref, quest_id

    return _grouped(pairs())


def quests_by_item(world: World) -> Index:
    """Quest IDs per item ID: items a quest requires (`requiredItems`) or has as an objective."""

    def pairs():
        for quest_id, rec in world.records.get("quest", {}).items():
            for item in rec.get("requiredItems") or []:
                yield int(item[0]), quest_id
            for objective in rec.get("objectives") or []:
                ref = objective[1] if len(objective) > 1 else None
                if isinstance(ref, str) and ref.startswith("item:"):
                    yield int(ref[5:]), quest_id

    return _grouped(pairs())


# The quest graph as Quests' Logic.lua reads it (quests.md "Logic layer"). Shipped since 21.10.2026
# (B11.1): without these the first zone page decoded every quest record to build them, 0.5 s on the
# retail pack (31,234 quests) plus 0.6 s for the chain components; the Forever pack took a fifth.
# The rules mirror Logic.startMap, Logic.turnInMap, Logic.index and Logic.chainIndex exactly.


def _map_of(places: object) -> int | None:
    first = places[0] if isinstance(places, list) and places else None
    return int(first[0]) if isinstance(first, list | tuple) and first else None


def quest_start_map(rec: dict) -> int | None:
    """The map a quest starts on: its zone, else the map of its first start place."""
    if rec.get("zone") is not None:
        return int(rec["zone"])
    return _map_of(rec.get("startPlaces"))


def quest_turn_in_map(rec: dict) -> int | None:
    """The map of the first turn-in place, else the start map."""
    return _map_of(rec.get("endPlaces")) or quest_start_map(rec)


def quest_start_maps(rec: dict) -> list[int]:
    """The maps a quest is taken on: its start map and, when different, the map of its first
    start place (the giver stands there). Dornogal listed 172 quests by zone while 248 givers
    stood in the city: the zone page lists both."""
    out = []
    for m in (quest_start_map(rec), _map_of(rec.get("startPlaces"))):
        if m is not None and m not in out:
            out.append(m)
    return out


def quests_by_start(world: World) -> Index:
    return _grouped(
        (m, quest_id)
        for quest_id, rec in world.records.get("quest", {}).items()
        for m in quest_start_maps(rec)
    )


def quests_by_turn_in(world: World) -> Index:
    """The map of the first turn-in place; without one the start maps. Empty when it equals
    `quest.byStart` (retail knows no turn-in places): the loader then reads `byStart` for both,
    and the pack does not carry the table twice."""

    def pairs():
        for quest_id, rec in world.records.get("quest", {}).items():
            end = _map_of(rec.get("endPlaces"))
            for m in [end] if end is not None else quest_start_maps(rec):
                yield m, quest_id

    index = _grouped(pairs())
    return {} if index == quests_by_start(world) else index


def _predecessors(rec: dict) -> list[int]:
    out = [int(p) for key in ("pre", "preAny") for p in rec.get(key) or []]
    if rec.get("parent") is not None:
        out.append(int(rec["parent"]))
    return out


def quest_followers(world: World) -> Index:
    """Quest id -> the quests that need it (pre, preAny, parent) and the quest it chains into."""

    def pairs():
        for quest_id, rec in world.records.get("quest", {}).items():
            for p in _predecessors(rec):
                yield p, quest_id
            if rec.get("chain") is not None:
                yield quest_id, int(rec["chain"])

    return _grouped(pairs())


def chain_components(world: World) -> dict[int, int]:
    """Quest id -> the smallest id of its component, over pre, preAny, parent and chain edges
    between known quests; quests without such an edge are absent (they belong to no chain)."""
    quests = world.records.get("quest", {})
    up: dict[int, int] = {}

    def find(x: int) -> int:
        while up[x] != x:
            up[x] = up[up[x]]
            x = up[x]
        return x

    def union(a: int, b: int) -> None:
        if a not in quests or b not in quests:
            return
        up.setdefault(a, a)
        up.setdefault(b, b)
        ra, rb = find(a), find(b)
        if ra != rb:
            up[max(ra, rb)] = min(ra, rb)

    for quest_id, rec in sorted(quests.items()):
        for p in _predecessors(rec):
            union(quest_id, p)
        if rec.get("chain") is not None:
            union(quest_id, int(rec["chain"]))
    return {q: find(q) for q in up}


def chain_members(world: World) -> Index:
    """Component root (its smallest quest id) -> every quest of the chain, ascending."""
    return _grouped((root, q) for q, root in chain_components(world).items())


def chain_from(world: World) -> Index:
    """Quest id -> the quests whose `chain` names it (the predecessors a chain edge adds)."""
    return _grouped(
        (int(rec["chain"]), quest_id)
        for quest_id, rec in world.records.get("quest", {}).items()
        if rec.get("chain") is not None
    )


def attunements_by_faction(world: World) -> dict[object, list[str]]:
    """Attunement IDs per faction; "both" lists under Alliance and Horde."""
    out: dict[str, list[str]] = {}
    for record_id, rec in sorted(world.records.get("attunement", {}).items()):
        factions = ("Alliance", "Horde") if rec.get("faction") == "both" else (rec.get("faction"),)
        for faction in factions:
            if faction:
                out.setdefault(faction, []).append(str(record_id))
    return out


def area_to_map(world: World) -> dict[object, list[int]]:
    """AreaTable id -> uiMapID, for the QuestieDB bridge (its spawns are grouped by AreaId)."""
    return {area: ui_map for area, ui_map in sorted(world.area_to_map.items()) if ui_map}


BUILDERS: dict[str, Callable[[World], Index]] = {
    "area.toMap": area_to_map,
    "npc.byZone": lambda w: by_zone(w, "npc"),
    "object.byZone": lambda w: by_zone(w, "object"),
    "node.byZone": lambda w: by_zone(w, "node"),
    "quest.byZone": lambda w: by_zone(w, "quest"),
    "quest.byGiver": lambda w: quests_by(w, "starts"),
    "quest.byEnder": lambda w: quests_by(w, "ends"),
    "quest.byItem": quests_by_item,
    "quest.byStart": quests_by_start,
    "quest.byTurnIn": quests_by_turn_in,
    "quest.followers": quest_followers,
    "quest.chainMembers": chain_members,
    "quest.chainFrom": chain_from,
    "attunement.byFaction": attunements_by_faction,
    "market.list": lambda w: market.market_list(w),
    "signal.byMarket": lambda w: market.signals_by_market(w),
    "spot.all": lambda w: market.spots_all(w),
    "spot.byItem": lambda w: market.spots_by_item(w),
    "strategy.all": lambda w: market.strategies_all(w),
    "book.toc": lambda w: book.book_toc(w),
    "book.mill": lambda w: mill.mill_index(w),
}


def build_index(world: World, name: str) -> Index:
    try:
        builder = BUILDERS[name]
    except KeyError as exc:
        raise KeyError(f"no builder for index {name!r}; known: {sorted(BUILDERS)}") from exc
    return builder(world)
