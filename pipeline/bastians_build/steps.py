"""A quest's steps, resolved in the build (ADR 0069, ADR 0070; data.md "A quest's `steps`").

A step is a thing to do: its subject, how many, how it is done, and where. The build knows every
table the sources have, so it works out the places once and the pack ships the answer; the addon
only adds what the game knows (which steps are open). `resolve` runs on the finished world, the
hand-written fixture world included, and writes `steps` on every quest record.

What a quest record gives (canon.py fills what a source has; all of it may be absent):

- `objectives`: rows `{ kind, ref, number }` (Everything Quests: one creature that counts for
  the objective of that number within its kind) or `{ kind, ref }` (QuestieDB: an objective).
- `eqRows`: Everything Quests' rows before `fix_loot_objectives` paired them with items by row.
- `requiredItems`: `{ { item, count } }`, CMaNGOS' columns in their order.
- `goals`: `{ { ref, count, spell } }`, CMaNGOS' creature and object columns in their order.
- `spots`, `spotsSrc`: the quest's own points and where they come from (`eq`, `fdb`, `client`;
  `spawns` and `items` are made from the subjects' places and not read here).
- `seenSpots`: `{ [objective number] = { { map, x, y } } }`, where players saw it advance.
- `gives`: `{ { item, count } }`, what the giver hands over.
- `castAt`: `{ { item ref, target ref } }`, the handed item is used at or on that thing.
- `classicPoints`: `{ [ref or ""] = { { map, x, y } } }`, Classic points of a subject, under
  `""` the quest's own.
- `dungeon`: the instance the quest is done in.
- `authored`: `{ { n, map, x, y, ref, verified } }`, our own table's rows (quest_places.py):
  `n` the objective's number in the game's list, or none for the quest as a whole. They come
  before every source.

Pure over the World.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field

from bastians_build.model import World

PLACES_PER_MAP = 8  # a step's places per map, spread by farthest-point sampling
SOURCES = 12  # droppers, vendors or holders an item is followed to, the likeliest first
DEPTH = 2  # an item in a container that a creature drops: two levels, no further
STEP_OF = {"slay": "slay", "object": "use", "loot": "get"}
SPOT_OF = {"slay": "slay", "use": "object", "cast": "slay", "get": "loot"}
# spots that were made from the subjects' own places (canon.py): the resolver asks the subjects
DERIVED_SPOTS = frozenset({"spawns", "items"})
CLASSIC = frozenset({"classic", "fdb-classic"})
ROW = ("n", "kind", "ref", "count", "how", "via", "places", "src", "nth", "more")


@dataclass
class Step:
    kind: str
    ref: str | None = None
    refs: list[str] = field(default_factory=list)  # every subject, `ref` first
    count: int | None = None
    n: int | None = None  # the client's number of the objective, where the client said it
    nth: int | None = None  # the number within the kind (Everything Quests)
    how: str | None = None
    via: list[str] | None = None
    places: list[list] = field(default_factory=list)  # rows [map, x, y, ref or None]
    src: str | None = None
    # whether the quest's own spots may be the step's: not for a required item no row names
    # (the old fields' reader gives it no spot either: Steps.lua, data.md "In the game")
    spots: bool = True

    def row(self) -> list:
        by_map: dict[int, list] = {}
        for ui_map, x, y, ref in self.places:
            by_map.setdefault(ui_map, []).append([x, y, ref] if ref else [x, y])
        # the other subjects; without a subject of its own (an item no source names, only
        # who has it) all of them
        more = [ref for ref in self.refs if ref != self.ref] or None
        values = [
            self.n,
            self.kind,
            self.ref,
            self.count,
            self.how,
            self.via or None,
            dict(sorted(by_map.items())) or None,
            self.src,
            self.nth,
            more,
        ]
        while values and values[-1] is None:
            values.pop()
        return values


@dataclass
class Way:
    """One way an item is come by: how, the refs on the way, and where (rows [map, x, y, src,
    ref])."""

    how: str
    via: list[str]
    places: list[list] = field(default_factory=list)


@dataclass(frozen=True)
class Listed:
    """A step in one of the build's two lists (data.md "The count and the watch"): the Classic
    debt and the steps without a place. What is unknown stays None."""

    quest: object
    step: int  # its place in the quest's `steps`, from 1
    kind: str
    ref: str | None
    zone: str | None  # where its places lie; without a place, where the quest starts
    level: int | None
    name: str | None  # the quest's
    subject: str | None  # the subject's name
    reason: str | None = None  # a step without a place: its `how`
    via: tuple[str, ...] = ()


# the columns the spec names first (quest, step, subject, zone, level), then what a reader needs
LIST_COLUMNS = ("quest", "step", "subject", "zone", "level", "kind", "quest_name", "subject_name")
OPEN_COLUMNS = (*LIST_COLUMNS[:6], "reason", "via", *LIST_COLUMNS[6:])


def _cell(value: object) -> str:
    return "" if value is None else " ".join(str(value).split())


def listing(rows: list[Listed], *, reasons: bool = False) -> str:
    """A list as tab-separated text, a header line first; an unknown value is an empty cell."""
    lines = ["\t".join(OPEN_COLUMNS if reasons else LIST_COLUMNS)]
    for r in rows:
        cells = [r.quest, r.step, r.ref, r.zone, r.level, r.kind]
        if reasons:
            cells += [r.reason, " ".join(r.via)]
        lines.append("\t".join(_cell(c) for c in [*cells, r.name, r.subject]))
    return "\n".join(lines) + "\n"


@dataclass
class Report:
    """What the resolver made of the world's quests. A step is placed, or it needs no place (the
    item the giver hands over), or it is without one: `unplaced`, by what is known instead."""

    steps: int = 0
    kinds: Counter = field(default_factory=Counter)  # the steps by kind
    placed: Counter = field(default_factory=Counter)  # by the step's `src` ("" = the subject's)
    placed_kinds: Counter = field(default_factory=Counter)  # the steps with a place, by kind
    given: int = 0  # the item the giver hands over: carried, no place needed
    unplaced: Counter = field(default_factory=Counter)  # by `how`
    quests: int = 0
    without: int = 0  # quests with no step at all
    classic: list[Listed] = field(default_factory=list)  # the Classic debt
    open: list[Listed] = field(default_factory=list)  # the steps without a place
    # the steps our own table places that nobody checked in game yet (`src` = `authored`)
    assumed: list[Listed] = field(default_factory=list)

    def counts(self) -> dict:
        """The numbers of `links-<client>.json`: what the edition keeps and the watch compares."""
        zones = Counter(row.zone or "unknown" for row in self.classic)
        return {
            "quests": self.quests,
            "quests_without_steps": self.without,
            "steps": self.steps,
            "steps_by_kind": {
                kind: {"steps": n, "placed": self.placed_kinds[kind]}
                for kind, n in sorted(self.kinds.items())
            },
            "placed": sum(self.placed.values()),
            "placed_by_src": {k or "subject": n for k, n in sorted(self.placed.items())},
            "given": self.given,
            "unplaced": sum(self.unplaced.values()),
            "unplaced_by_reason": dict(sorted(self.unplaced.items())),
            "classic": len(self.classic),
            "classic_by_zone": dict(sorted(zones.items())),
            "authored_unchecked": len(self.assumed),
        }


class Context:
    """The world's tables the resolver follows, each built once."""

    def __init__(self, world: World) -> None:
        self.world = world
        self.vendors: dict[int, list[str]] = {}
        for npc_id, rec in sorted(world.records.get("npc", {}).items(), key=_by_id):
            for row in rec.get("vendor") or ():
                if row and isinstance(row[0], int):
                    self.vendors.setdefault(row[0], []).append(f"npc:{npc_id}")
        self.recipes: dict[int, list[str]] = {}
        for recipe_id, rec in sorted(world.records.get("recipe", {}).items(), key=_by_id):
            if isinstance(rec.get("item"), int):
                self.recipes.setdefault(rec["item"], []).append(f"recipe:{recipe_id}")
        self.rewards: dict[int, list[int]] = {}
        for quest_id, rec in sorted(world.records.get("quest", {}).items(), key=_by_id):
            rewards = rec.get("rewards") or {}
            for row in [*(rewards.get("items") or ()), *(rewards.get("choices") or ())]:
                if row and isinstance(row[0], int):
                    self.rewards.setdefault(row[0], []).append(quest_id)
        self.entrances: dict[object, list[list]] = {}
        for _entrance_id, rec in sorted(world.records.get("entrance", {}).items(), key=_by_id):
            if rec.get("instance") is not None:
                rows = self.entrances.setdefault(rec["instance"], [])
                rows += [[s[0], s[1], s[2], _src(s), None] for s in rec.get("spawns") or ()]

    def record(self, ref: str) -> dict | None:
        kind, _, raw = ref.partition(":")
        if not raw:
            return None
        return self.world.get(kind, int(raw) if raw.isdigit() else raw)

    def spawns(self, refs: list[str], own: str | None = None) -> list[list]:
        """Where the things are: rows [map, x, y, src, ref], the ref left out for `own`."""
        out: list[list] = []
        for ref in refs:
            for s in (self.record(ref) or {}).get("spawns") or ():
                out.append([s[0], s[1], s[2], _src(s), None if ref == own else ref])
        return out

    def dungeon_of(self, refs: list[str]) -> object | None:
        """The one instance the things named belong to (a boss names its dungeon)."""
        found = {(self.record(ref) or {}).get("dungeon") for ref in refs} - {None}
        return next(iter(found)) if len(found) == 1 else None


def _by_id(pair: tuple[object, dict]) -> tuple[int, object]:
    return (0, pair[0]) if isinstance(pair[0], int) else (1, str(pair[0]))


def _src(spawn: list) -> str | None:
    return spawn[3] if len(spawn) > 3 else None


def _spread(rows: list[list]) -> list[list]:
    """At most PLACES_PER_MAP rows a map, spread; maps ascending, a place once."""
    from bastians_build.canon import farthest_points  # the one sampling the spawns use

    by_map: dict[int, list] = {}
    seen: set[tuple] = set()
    for row in rows:
        key = (row[0], row[1], row[2])
        if key not in seen:
            seen.add(key)
            by_map.setdefault(row[0], []).append(row)
    out: list[list] = []
    for ui_map in sorted(by_map):
        out += farthest_points(by_map[ui_map], PLACES_PER_MAP)
    return out


def _place(step: Step, rows: list[list], src: str | None = None) -> bool:
    """Gives the step its places from rows [map, x, y, src, ref]; with no `src` the step is
    `classic` when every place is Classic knowledge, else its places keep their own source."""
    rows = _spread(rows)
    if not rows:
        return False
    step.places = [[r[0], r[1], r[2], r[4] if len(r) > 4 else None] for r in rows]
    step.src = src or ("classic" if all(r[3] in CLASSIC for r in rows) else None)
    return True


# ---- the ways to an item ---------------------------------------------------------------------


def item_ways(ctx: Context, item_id: int, depth: int = 1, asking: object = None) -> list[Way]:
    """Every way the world knows to come by an item, the ways that can have a place first:
    who drops it, what it is made from and where, the container that holds it, who it is skinned
    or picked from, who sells it, where it is fished; then the ways without a place of their own:
    a recipe, another quest's reward, a world drop."""
    item = ctx.world.get("item", item_id) or {}
    ways: list[Way] = []
    droppers = [str(row[0]) for row in (item.get("drops") or ())[:SOURCES] if row]
    if droppers:
        how = "open" if droppers[0].startswith("object:") else "loot"
        ways.append(Way(how, droppers, ctx.spawns(droppers)))
    for row in item.get("ways") or ():
        how, ref = row[0], row[1]
        at = row[3] if len(row) > 3 else None
        if how == "make":
            # one way per item that is used: every place it can be used at, the first of them
            # that has a place named in `via`
            same = next((w for w in ways if w.how == "make" and w.via[0] == ref), None)
            if same is None:
                same = Way("make", [ref])
                ways.append(same)
            found = ctx.spawns([at]) if at else []
            if at and (len(same.via) == 1 or (found and not same.places)):
                same.via = [ref, at]
            same.places += found
        elif how == "container":
            places: list[list] = []
            raw = str(ref).partition(":")[2]
            if depth < DEPTH and raw.isdigit():
                for inner in item_ways(ctx, int(raw), depth + 1):
                    if inner.places and inner.how in ("loot", "open", "buy"):
                        places = inner.places
                        break
            ways.append(Way("container", [ref], places))
        elif how in ("skin", "pick"):
            same = next((w for w in ways if w.how == how), None)
            if same is None:
                ways.append(Way(how, [ref], ctx.spawns([ref])))
            elif len(same.via) < SOURCES:
                same.via.append(ref)
                same.places += ctx.spawns([ref])
        elif how == "fish":
            same = next((w for w in ways if w.how == "fish"), None)
            if same is None:
                ways.append(Way("fish", [ref]))
            elif len(same.via) < SOURCES:
                same.via.append(ref)
    vendors = ctx.vendors.get(item_id) or []
    if vendors:
        placed = [v for v in vendors if (ctx.record(v) or {}).get("spawns")]
        vendors = (placed + [v for v in vendors if v not in placed])[:SOURCES]
        ways.append(Way("buy", vendors, ctx.spawns(vendors)))
    if ctx.recipes.get(item_id):
        ways.append(Way("craft", ctx.recipes[item_id][:SOURCES]))
    rewarded = [q for q in ctx.rewards.get(item_id) or () if q != asking]  # another quest's
    if rewarded:
        ways.append(Way("reward", [f"quest:{q}" for q in rewarded[:SOURCES]]))
    if item.get("worldDrop") is not None:
        ways.append(Way("worlddrop", []))
    return ways


# the order in which a way without a place says what is known (plan-quest-links.md section 2.1)
KNOWN = ("craft", "reward", "loot", "open", "container", "skin", "pick", "make", "buy", "fish")


def _get(
    ctx: Context, quest: dict, step: Step, item_id: int, named: list[str], asking: object
) -> list[Way]:
    """Says how an item step is done (`how`, `via`) and returns its ways with a place."""
    given = {row[0] for row in quest.get("gives") or () if row}
    if item_id in given:
        step.how = "given"  # the giver hands it over: the player carries it, no place is needed
        return []
    ways = item_ways(ctx, item_id, asking=asking)
    if not any(w.how in ("loot", "open") for w in ways) and named:
        # no table knows who has it: the creatures Everything Quests lists for the objective
        ways.insert(0, Way("open" if named[0].startswith("object:") else "loot", named))
        ways[0].places = ctx.spawns(named)
    # the item the giver hands over is made into this one: that is how the quest means it
    # (Mirror Lake: QuestieDB says the waterwall drops the sample, CMaNGOS that Jennea's Flask
    # is filled there)
    handed = {f"item:{item}" for item in given}
    ways.sort(key=lambda w: not (w.how == "make" and w.via[0] in handed))
    placed = [w for w in ways if w.places]
    best = placed[0] if placed else None
    if best is None:
        best = next((w for how in KNOWN for w in ways if w.how == how), None)
        best = best or next(iter(ways), None)
    if best is not None:
        step.how, step.via = best.how, list(best.via) or None
    return placed


# ---- the things to do --------------------------------------------------------------------------


def _numbered(rows: list) -> bool:
    return any(isinstance(o, list) and len(o) > 2 and isinstance(o[2], int) for o in rows)


def _item_id(ref: object) -> int | None:
    kind, _, raw = str(ref or "").partition(":")
    return int(raw) if kind == "item" and raw.isdigit() else None


def _subjects(quest: dict) -> list[tuple[Step, list[str]]]:
    """The things to do with their subjects, before any place: (step, who is named as having an
    item). Numbered rows are grouped by kind and number, and the items are the quest's required
    items in their order (Steps.lua's reader of the same rows, which this replaces)."""
    rows = [o for o in quest.get("eqRows") or quest.get("objectives") or () if isinstance(o, list)]
    rows = [o for o in rows if o and o[0]]
    items = [it for it in quest.get("requiredItems") or () if isinstance(it, list) and it]
    out: list[tuple[Step, list[str]]] = []
    if _numbered(rows):
        groups: dict[tuple[str, int], list[str]] = {}
        for o in rows:
            if len(o) > 2 and isinstance(o[2], int):
                refs = groups.setdefault((o[0], o[2]), [])
                for ref in (o[1], o[3] if len(o) > 3 else None):
                    if isinstance(ref, str) and not ref.startswith("item:") and ref not in refs:
                        refs.append(ref)
        for (kind, number), refs in groups.items():
            if kind != "loot":
                step = Step(STEP_OF.get(kind, kind), refs[0] if refs else None, list(refs))
                step.nth = number + 1
                out.append((step, []))
        for i, it in enumerate(items):
            step = Step("get", f"item:{it[0]}" if it[0] else None, count=_count(it))
            step.refs, step.nth = ([step.ref] if step.ref else []), i + 1
            out.append((step, groups.get(("loot", i), [])))
        for (kind, number), refs in groups.items():
            if kind == "loot" and number >= len(items):  # an item the pack does not name
                step = Step("get", None, list(refs))
                step.nth = number + 1
                out.append((step, list(refs)))
        return out
    named: set[int] = set()
    for o in rows:
        ref = o[1] if len(o) > 1 and isinstance(o[1], str) else None
        step = Step(STEP_OF.get(o[0], o[0]), ref, [ref] if ref else [])
        item_id = _item_id(ref)
        if item_id is not None:
            named.add(item_id)
            step.count = next((_count(it) for it in items if it[0] == item_id), None)
        source = o[3] if len(o) > 3 and isinstance(o[3], str) else None
        out.append((step, [source] if source else []))
    if not rows:  # no source lists objectives: CMaNGOS' creature and object columns
        for goal in quest.get("goals") or ():
            ref = goal[0]
            step = Step("use" if str(ref).startswith("object:") else "slay", ref, [ref])
            out.append((step, []))
    for it in items:
        if it[0] and it[0] not in named:
            step = Step("get", f"item:{it[0]}", [f"item:{it[0]}"], count=_count(it), spots=False)
            out.append((step, []))
    return out


def _count(row: list) -> int | None:
    return row[1] if len(row) > 1 and isinstance(row[1], int) and row[1] > 0 else None


def _goals(quest: dict, step: Step) -> None:
    """What CMaNGOS' columns add to a creature or object step: how many, and that it is not
    killed or used but the handed item is cast on it."""
    for goal in quest.get("goals") or ():
        if goal and goal[0] in step.refs:
            if step.count is None and len(goal) > 1 and isinstance(goal[1], int) and goal[1] > 0:
                step.count = goal[1]
            if len(goal) > 2 and goal[2]:
                step.kind = "cast"
                step.via = [row[0] for row in quest.get("castAt") or () if row[1] in step.refs]
                step.via = step.via or None
            return


def _own_spots(quest: dict, step: Step, bit: int | None, claimed: set[int]) -> list[list]:
    """The quest's own points for a step: the spots of its kind with its bit."""
    if bit is None or quest.get("spotsSrc") in DERIVED_SPOTS:
        return []
    kind = SPOT_OF.get(step.kind)
    rows = []
    for ui_map, spots in sorted((quest.get("spots") or {}).items()):
        for s in spots:
            mask = s[3] if len(s) > 3 and isinstance(s[3], int) else 0
            if s[2] == kind and (mask >> bit) & 1:
                claimed.add(id(s))
                rows.append([ui_map, s[0], s[1], None, s[4] if len(s) > 4 else None])
    return rows


def _areas(quest: dict, claimed: set[int]) -> list[Step]:
    """The client's own places for its objectives, and where players saw them advance: a bare
    `reach` step per objective number. Which thing to do that is, only the log can say (Bastian's
    Quests joins the two), so they stand beside the subjects' steps."""
    by_number: dict[int, tuple[list[list], str]] = {}
    label = quest.get("spotsSrc") or "client"
    for ui_map, spots in sorted((quest.get("spots") or {}).items()):
        for s in spots:
            mask = s[3] if len(s) > 3 and isinstance(s[3], int) else 0
            if s[2] == "area" and mask > 0:
                claimed.add(id(s))
                for bit in range(mask.bit_length()):
                    if (mask >> bit) & 1:
                        by_number.setdefault(bit + 1, ([], label))[0].append(
                            [ui_map, s[0], s[1], None, None]
                        )
    for number, points in sorted((quest.get("seenSpots") or {}).items()):
        if number not in by_number and points:
            by_number[number] = ([[p[0], p[1], p[2], None, None] for p in points], "fdb")
    # our own table names an objective by the same number, and wins over both
    numbers = sorted({row[0] for row in _authored(quest) if row[0] is not None})
    for number in numbers:
        rows = [row for row in _authored(quest) if row[0] == number]
        by_number[number] = (_authored_rows(rows), _authored_src(rows))
    out = []
    for number in sorted(by_number):
        rows, src = by_number[number]
        step = Step("reach", n=number)
        _place(step, rows, src)
        out.append(step)
    return out


def _authored(quest: dict) -> list[list]:
    """Our own table's rows of a quest: [n, map, x, y, ref, verified]."""
    return [r for r in quest.get("authored") or () if isinstance(r, list) and len(r) > 3]


def _authored_rows(rows: list[list]) -> list[list]:
    return [[r[1], r[2], r[3], None, r[4] if len(r) > 4 else None] for r in rows]


def _authored_src(rows: list[list]) -> str:
    """One source a step: `verified` only when every row of it was checked in game."""
    return "verified" if all(len(r) > 5 and r[5] for r in rows) else "authored"


def quest_steps(ctx: Context, quest: dict, quest_id: object = None) -> list[Step]:
    """A quest's things to do with their places. A step's places come from the first that has
    any: our own table, the quest's own points for it, the subject's own places, for an item
    where it comes from, the quest's Classic points; else none, and `how` says what is known."""
    claimed: set[int] = set()
    classic = quest.get("classicPoints") or {}
    label = quest.get("spotsSrc") or "eq"
    numbered = _numbered(
        [o for o in quest.get("eqRows") or quest.get("objectives") or () if isinstance(o, list)]
    )
    order: Counter = Counter()
    steps: list[Step] = []
    for step, named in _subjects(quest):
        order[step.kind] += 1
        bit = step.nth - 1 if step.nth else (None if numbered else order[step.kind] - 1)
        own = _own_spots(quest, step, bit if step.spots else None, claimed)
        item_id = _item_id(step.ref)
        ways: list[Way] = []
        if step.kind == "get":
            if item_id is not None:
                ways = _get(ctx, quest, step, item_id, named, quest_id)
            elif named:
                step.how = "open" if named[0].startswith("object:") else "loot"
                step.via = list(named)
                ways = [Way(step.how, named, ctx.spawns(named))]
        else:
            _goals(quest, step)
        if own:
            _place(step, own, label)
        elif step.kind != "get":
            _place(step, ctx.spawns(step.refs, step.ref))
        elif ways and step.how != "given":
            _place(step, ways[0].places)
        if not step.places and step.how != "given":
            points = [p for ref in step.refs for p in classic.get(ref) or ()]
            _place(step, [[p[0], p[1], p[2], "classic", None] for p in points], "classic")
        steps.append(step)
    # our own table's place of the quest as a whole: the steps nothing placed are done there;
    # with none of those it is a step of its own, as the row asks
    whole = [row for row in _authored(quest) if row[0] is None]
    if whole:
        takers = [s for s in steps if not s.places and s.how != "given"]
        if not takers:
            takers = [Step("reach")]
            steps += takers
        for step in takers:
            _place(step, _authored_rows(whole), _authored_src(whole))
    # the quest's own Classic points serve the steps nothing else placed; a quest with nothing
    # to do but go there gets a step for it
    points = [[p[0], p[1], p[2], "classic", None] for p in classic.get("") or ()]
    open_steps = [s for s in steps if not s.places and s.how != "given"]
    for step in open_steps:
        _place(step, points, "classic")
    for step in steps:
        if step.places or step.how == "given":
            continue
        # inside an instance nothing is placed: the way in is the place, and the step says so
        instance = quest.get("dungeon") if quest.get("dungeon") is not None else None
        if instance is None:
            instance = ctx.dungeon_of([*step.refs, *(step.via or [])])
        if instance is not None and _place(step, ctx.entrances.get(instance) or []):
            step.how = "dungeon"
        elif step.how is None or (step.kind == "get" and step.how in ("loot", "open")):
            step.how = "dungeon" if instance is not None else (step.how or "unknown")
    areas = _areas(quest, claimed)
    steps += areas
    rest = [
        [ui_map, s[0], s[1], None, s[4] if len(s) > 4 else None]
        for ui_map, spots in sorted((quest.get("spots") or {}).items())
        for s in spots
        if id(s) not in claimed
    ]
    if rest and quest.get("spotsSrc") not in DERIVED_SPOTS:
        step = Step("reach")
        _place(step, rest, label)
        steps.append(step)
    for item_ref, target in quest.get("castAt") or ():
        # the handed item is used at or on a thing no step names: a step of its own
        if not any(target in s.refs or target in (s.via or ()) for s in steps):
            step = Step("cast", target, [target], via=[item_ref])
            _place(step, ctx.spawns([target], target))
            steps.append(step)
    if points and not open_steps and not any(s.places for s in steps):
        step = Step("reach")
        _place(step, points, "classic")
        steps.append(step)
    for step in steps:
        if not step.places and step.how is None:
            step.how = "unknown"  # no place and nothing known: said, never guessed
    return steps


def _zone(ctx: Context, ui_map: object) -> str | None:
    if ui_map is None:
        return None
    return (ctx.world.get("zone", ui_map) or {}).get("name") or f"map {ui_map}"


def _listed(ctx: Context, quest_id: object, quest: dict, index: int, step: Step) -> Listed:
    """A step as a row of the lists. Its zone is the map most of its places lie on (the lowest
    id among equals); a step without a place has the quest's zone, where it starts."""
    ui_map = quest.get("zone")
    if step.places:
        maps = Counter(place[0] for place in step.places)
        ui_map = min(maps, key=lambda m: (-maps[m], m))
    ref = step.ref or next(iter(step.refs), None)
    level = quest.get("level")
    return Listed(
        quest=quest_id,
        step=index,
        kind=step.kind,
        ref=ref,
        zone=_zone(ctx, ui_map),
        level=level if isinstance(level, int) and not isinstance(level, bool) else None,
        name=quest.get("name"),
        subject=(ctx.record(ref) or {}).get("name") if ref else None,
        reason=None if step.places else step.how,
        via=() if step.places else tuple(step.via or ()),
    )


def _lowest_level_first(row: Listed) -> tuple:
    """The order of the lists: where a low character can check a place first; a quest without a
    level comes last."""
    return (row.level is None, row.level or 0, _by_id((row.quest, {})), row.step)


def resolve(world: World) -> Report:
    """Writes `steps` on every quest record (none: the field is absent) and counts them."""
    ctx = Context(world)
    report = Report()
    for quest_id, quest in sorted(world.records.get("quest", {}).items(), key=_by_id):
        steps = quest_steps(ctx, quest, quest_id)
        report.quests += 1
        report.without += not steps
        for index, step in enumerate(steps, 1):
            report.steps += 1
            report.kinds[step.kind] += 1
            if step.places:
                report.placed[step.src or ""] += 1
                report.placed_kinds[step.kind] += 1
                if step.src == "classic":
                    report.classic.append(_listed(ctx, quest_id, quest, index, step))
                elif step.src == "authored":
                    report.assumed.append(_listed(ctx, quest_id, quest, index, step))
            elif step.how == "given":
                report.given += 1
            else:
                report.unplaced[step.how or "unknown"] += 1
                report.open.append(_listed(ctx, quest_id, quest, index, step))
        quest.pop("steps", None)
        if steps:
            quest["steps"] = [step.row() for step in steps]
    report.classic.sort(key=_lowest_level_first)
    report.open.sort(key=_lowest_level_first)
    report.assumed.sort(key=_lowest_level_first)
    return report
