"""The edge registry (ADR 0070, data.md "Links and steps"): every link between two things is
declared once. A row says which types an edge joins, in which record field it is stored, where
the far end and each property sit there, and the index that serves the direction no field
stores. The build makes that index from the row, the pack's header carries the rows as `edges`,
and the addon's `graph:Edges` reads both directions from them. A new link is one row here.

Pure over the World.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass

from bastians_build.model import World

FORMS = ("refs", "ids", "id", "rows")


@dataclass(frozen=True)
class Part:
    """One place an edge is stored: a field of the records of one type.

    `side` says which end of the edge the storing record is. `form`: `refs` (a list of refs),
    `ids` (a list of ids of the type `far`), `id` (one such id), `rows` (a list of rows, the far
    end at `ref`: a ref, or an id of the type `far`). `field` may name a table inside a field
    (`rewards.items`). `props` are a row's properties by position, `also` properties from other
    fields of the same record, `const` properties every link of this part has. Of rows, `when`
    (a position and the value it must hold) picks the rows that are this edge where one field
    stores several (`item.ways`), and `many` names a position that holds further far ends, each
    a link with the row's properties (the other creatures that count for one step); `ref` 0
    says the row has no far end of its own beside those. A far end of a type the edge does not
    join is no link (a step's `via` names a quest or a recipe too)."""

    on: str
    field: str
    form: str
    side: str = "from"
    far: str | None = None
    ref: int = 1
    props: tuple[tuple[str, int], ...] = ()
    also: tuple[tuple[str, str], ...] = ()
    const: tuple[tuple[str, object], ...] = ()
    when: tuple[int, object] | None = None
    many: int | None = None


@dataclass(frozen=True)
class Edge:
    """An edge type. `index` serves the direction no part stores: the far end's ref (`key` =
    "ref") or id ("id": the indexes older suites read) -> the ids of the type that stores the
    edge. An edge without one says why."""

    name: str
    src: tuple[str, ...]
    dst: tuple[str, ...]
    parts: tuple[Part, ...]
    index: str | None = None
    key: str = "ref"
    why: str | None = None


EDGES: tuple[Edge, ...] = (
    Edge(
        "starts",
        ("npc", "object", "item"),
        ("quest",),
        (Part("quest", "starts", "refs", side="to"),),
        index="quest.byGiver",
    ),
    Edge(
        "ends",
        ("npc", "object"),
        ("quest",),
        (Part("quest", "ends", "refs", side="to"),),
        index="quest.byEnder",
    ),
    Edge(
        "needs",
        ("quest",),
        ("quest",),
        (
            Part("quest", "pre", "ids", far="quest", const=(("all", True),)),
            Part("quest", "preAny", "ids", far="quest", const=(("any", True),)),
        ),
        index="edge.needs",
    ),
    Edge(
        "excludes",
        ("quest",),
        ("quest",),
        (Part("quest", "excl", "ids", far="quest"),),
        index="edge.excludes",
    ),
    Edge(
        "chains",
        ("quest",),
        ("quest",),
        (Part("quest", "chain", "id", far="quest"),),
        index="quest.chainFrom",
        key="id",
    ),
    # a step's subject (steps.py): the creature, object or item of a thing to do, with the
    # step's kind, its count and its numbers; `more` holds the other creatures that count. And
    # what is on the way to it (`via`): who has the item, the item that is used and where
    Edge(
        "targets",
        ("quest",),
        ("npc", "object", "item"),
        (
            Part(
                "quest",
                "steps",
                "rows",
                ref=3,
                props=(("n", 1), ("kind", 2), ("count", 4), ("nth", 9)),
                many=10,
            ),
            Part(
                "quest",
                "steps",
                "rows",
                ref=0,
                props=(("n", 1), ("kind", 2), ("nth", 9), ("how", 5)),
                const=(("via", True),),
                many=6,
            ),
        ),
        index="edge.targets",
    ),
    Edge(
        "gives",
        ("quest",),
        ("item",),
        (Part("quest", "gives", "rows", far="item", props=(("count", 2),)),),
        index="edge.gives",
    ),
    Edge(
        "rewards",
        ("quest",),
        ("item",),
        (
            Part("quest", "rewards.items", "rows", far="item", props=(("count", 2),)),
            Part(
                "quest",
                "rewards.choices",
                "rows",
                far="item",
                props=(("count", 2),),
                const=(("choice", True),),
            ),
        ),
        index="edge.rewards",
    ),
    Edge(
        "drops",
        ("npc", "object"),
        ("item",),
        (
            Part("npc", "loot", "rows", far="item", props=(("chance", 2),)),
            Part("object", "loot", "rows", far="item", props=(("chance", 2),)),
            Part("item", "drops", "rows", side="to", props=(("chance", 2),)),
            # skinned from and picked from a creature: the item's side only (`item.ways`), a
            # creature's `loot` is what a kill gives
            Part(
                "item",
                "ways",
                "rows",
                side="to",
                ref=2,
                props=(("chance", 3),),
                const=(("how", "skin"),),
                when=(1, "skin"),
            ),
            Part(
                "item",
                "ways",
                "rows",
                side="to",
                ref=2,
                props=(("chance", 3),),
                const=(("how", "pick"),),
                when=(1, "pick"),
            ),
        ),
        why="stored at both ends: a dropper's loot and an item's droppers, each the likeliest few",
    ),
    # the ways to an item that are no drop (`item.ways` = { { how, ref, chance, at } }), each
    # kind of way an edge of its own, stored at the item that is come by
    Edge(
        "holds",
        ("item",),
        ("item",),
        (
            Part(
                "item",
                "ways",
                "rows",
                side="to",
                ref=2,
                props=(("chance", 3),),
                when=(1, "container"),
            ),
        ),
        index="edge.holds",
    ),
    Edge(
        "yields",
        ("item",),
        ("item",),
        (Part("item", "ways", "rows", side="to", ref=2, props=(("at", 4),), when=(1, "make")),),
        index="edge.yields",
    ),
    Edge(
        "fished",
        ("zone",),
        ("item",),
        (Part("item", "ways", "rows", side="to", ref=2, props=(("chance", 3),), when=(1, "fish")),),
        index="edge.fished",
    ),
    Edge(
        "sells",
        ("npc",),
        ("item",),
        (
            Part(
                "npc",
                "vendor",
                "rows",
                far="item",
                props=(("price", 2), ("stack", 3), ("limited", 4)),
            ),
        ),
        index="npc.bySoldItem",
        key="id",
    ),
    Edge(
        "teaches",
        ("npc",),
        ("spell",),
        (
            Part(
                "npc",
                "trainer",
                "rows",
                far="spell",
                props=(("cost", 3), ("skill", 4), ("level", 5)),
            ),
        ),
        index="edge.teaches",
    ),
    Edge(
        "makes",
        ("recipe",),
        ("item",),
        (Part("recipe", "item", "id", far="item", also=(("count", "count"),)),),
        index="edge.makes",
    ),
    Edge(
        "uses",
        ("recipe",),
        ("item",),
        (Part("recipe", "reagents", "rows", far="item", props=(("count", 2),)),),
        index="edge.uses",
    ),
)


class LinkError(ValueError):
    """A registry row that cannot be built."""


def check(edges: tuple[Edge, ...] = EDGES) -> None:
    """The rules a row keeps, so the build and the addon can read it without a special case."""
    names: set[str] = set()
    indexes: set[str] = set()
    for e in edges:
        if e.name in names:
            raise LinkError(f"edge {e.name} is declared twice")
        names.add(e.name)
        if not e.parts:
            raise LinkError(f"edge {e.name} is stored nowhere")
        if (e.index is None) == (e.why is None):
            raise LinkError(f"edge {e.name} needs an index or the reason it has none")
        if e.key not in ("ref", "id"):
            raise LinkError(f"edge {e.name}: unknown key {e.key!r}")
        for p in e.parts:
            near = e.src if p.side == "from" else e.dst
            far = e.dst if p.side == "from" else e.src
            if p.form not in FORMS or p.side not in ("from", "to"):
                raise LinkError(f"edge {e.name}: part {p.on}.{p.field} has an unknown form or side")
            if p.on not in near:
                raise LinkError(f"edge {e.name}: {p.on} is no {p.side} end of it")
            if p.far is not None and p.far not in far:
                raise LinkError(f"edge {e.name}: {p.far} is no far end of {p.on}.{p.field}")
            if p.form in ("ids", "id") and p.far is None:
                raise LinkError(f"edge {e.name}: {p.on}.{p.field} holds ids of no named type")
            if p.form != "rows" and (p.when is not None or p.many is not None):
                raise LinkError(f"edge {e.name}: only rows have `when` and `many`")
        if e.index is not None:
            if e.index in indexes:
                raise LinkError(f"index {e.index} serves two edges")
            indexes.add(e.index)
            if len({(p.on, p.side) for p in e.parts}) != 1:
                raise LinkError(f"edge {e.name}: an index needs every part on one type and side")
            far = e.dst if e.parts[0].side == "from" else e.src
            if e.key == "id" and len(far) != 1:
                raise LinkError(f"edge {e.name}: an id key needs one far type")


check()
BY_INDEX: dict[str, Edge] = {e.index: e for e in EDGES if e.index}
# The indexes this registry brought (`edge.*`) go into the pack as text and are compiled when
# first asked for, as the records are: 3.2 MB of tables nobody reads on most days (measured
# 10.11.2026, data.md "The edge registry"). The older names stay tables: installed suites read
# them as such.
LAZY: frozenset[str] = frozenset(name for name in BY_INDEX if name.startswith("edge."))


def _field(rec: dict, path: str) -> object:
    value: object = rec
    for name in path.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(name)
    return value


def _ref(value: object, far: str | None) -> str | None:
    """The far end as a ref: a ref as stored, or an id of the part's far type."""
    if isinstance(value, str):
        return value if ":" in value else None
    if isinstance(value, int) and not isinstance(value, bool) and far is not None:
        return f"{far}:{value}"
    return None


def part_links(rec: dict, part: Part) -> Iterator[tuple[str, dict[str, object]]]:
    """The links one record stores in one part: (the far end's ref, the link's properties)."""
    value = _field(rec, part.field)
    if value is None:
        return
    const = dict(part.const)
    for prop, field_name in part.also:
        if rec.get(field_name) is not None:
            const[prop] = rec[field_name]
    if part.form == "id":
        ref = _ref(value, part.far)
        if ref is not None:
            yield ref, dict(const)
        return
    if not isinstance(value, list | tuple):
        return
    for item in value:
        if part.form == "rows":
            if not isinstance(item, list | tuple) or len(item) < part.ref:
                continue
            if part.when is not None and (
                len(item) < part.when[0] or item[part.when[0] - 1] != part.when[1]
            ):
                continue
            ref = _ref(item[part.ref - 1], part.far) if part.ref else None
            props = dict(const)
            for prop, position in part.props:
                if len(item) >= position and item[position - 1] is not None:
                    props[prop] = item[position - 1]
            if ref is not None:
                yield ref, dict(props)
            more = item[part.many - 1] if part.many and len(item) >= part.many else None
            for other in more if isinstance(more, list | tuple) else ():
                other_ref = _ref(other, part.far)
                if other_ref is not None and other_ref != ref:
                    yield other_ref, dict(props)
            continue
        ref, props = _ref(item, part.far), dict(const)
        if ref is not None:
            yield ref, props


def links(world: World, edge: Edge) -> Iterator[tuple[str, str, dict[str, object]]]:
    """Every link of an edge the world stores: (from ref, to ref, properties). An edge stored at
    both ends gives a link once per end that stores it."""
    for part in edge.parts:
        ends = far_types(edge, part)
        for record_id, rec in sorted(world.records.get(part.on, {}).items(), key=_id_order):
            near = f"{part.on}:{record_id}"
            for far, props in part_links(rec, part):
                if far.partition(":")[0] in ends:
                    yield (near, far, props) if part.side == "from" else (far, near, props)


def far_types(edge: Edge, part: Part) -> tuple[str, ...]:
    """The types the far end of a part may have: a ref of another type is no link of the edge."""
    return edge.dst if part.side == "from" else edge.src


def _id_order(pair: tuple[object, dict]) -> tuple[int, object]:
    return (0, pair[0]) if isinstance(pair[0], int) else (1, str(pair[0]))


def index(world: World, name: str) -> dict[object, list]:
    """The index of an edge: the far end (its ref, or its id for an `id` key) -> the ids of the
    records that store the link, ascending."""
    edge = BY_INDEX[name]
    out: dict[object, set] = {}
    for part in edge.parts:
        ends = far_types(edge, part)
        for record_id, rec in world.records.get(part.on, {}).items():
            for far, _props in part_links(rec, part):
                if far.partition(":")[0] not in ends:
                    continue
                key: object = far
                if edge.key == "id":
                    raw = far.partition(":")[2]
                    key = int(raw) if raw.isdigit() else raw
                out.setdefault(key, set()).add(record_id)
    return {key: sorted(ids, key=lambda i: (not isinstance(i, int), i)) for key, ids in out.items()}


def indexes_for(types: set[str] | frozenset[str]) -> list[str]:
    """The indexes of the edges stored on these record types, in the registry's order: they go
    into the pack that holds the records."""
    return [e.index for e in EDGES if e.index and e.parts[0].on in types]


def manifest(types: set[str] | frozenset[str]) -> dict[str, dict]:
    """The rows a pack's header carries as `edges`: every edge with a part on one of the pack's
    types, with those parts. An edge stored in two packs (`drops`) is in both, each with its own
    parts; the addon joins them. The index is named by the pack that holds it."""
    out: dict[str, dict] = {}
    for e in EDGES:
        parts = [p for p in e.parts if p.on in types]
        if not parts:
            continue
        row: dict[str, object] = {"from": list(e.src), "to": list(e.dst)}
        if e.index is not None and e.parts[0].on in types:
            row["index"] = e.index
            row["key"] = e.key
        row["parts"] = [_part_row(p) for p in parts]
        out[e.name] = row
    return out


def _part_row(p: Part) -> dict[str, object]:
    row: dict[str, object] = {"on": p.on, "field": p.field, "form": p.form, "side": p.side}
    if p.far is not None:
        row["far"] = p.far
    if p.form == "rows":
        row["ref"] = p.ref
    if p.props:
        row["props"] = dict(p.props)
    if p.also:
        row["also"] = dict(p.also)
    if p.const:
        row["const"] = dict(p.const)
    if p.when is not None:
        row["when"] = list(p.when)
    if p.many is not None:
        row["many"] = p.many
    return row


def counts(world: World) -> dict[str, int]:
    """How many links of each edge the world stores (an edge stored at both ends: both counted)."""
    return {e.name: sum(1 for _ in links(world, e)) for e in EDGES}
