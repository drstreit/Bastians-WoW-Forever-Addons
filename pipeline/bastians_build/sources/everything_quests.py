"""Reader for Everything Quests (MIT, data from AllTheThings): the main quest source (sources.md).

EQ ships, per flavor, plain Lua tables under ``Data/`` whose packed encodings are documented in each
file's header; the decoders below follow those headers literally:

* QuestAvailable: ``ns.CLASSIC_QUEST_AVAILABLE`` = { start, gates, names, pre, preAll, excl, chain,
  parent, skill, minRep, maxRep }
* QuestTurnIn: ``ns.CLASSIC_QUEST_TURNIN`` [quest] = { [uiMapID] = { packed } }
* QuestCoords: ``ns.CLASSIC_QUEST_COORDS`` [quest] = uiMapID*1e8 + x*1e4*1e4 + y*1e4
* QuestSources: ``ns.CLASSIC_QUEST_SOURCES`` { npc = {id = name}, obj = {id = name} }
* QuestNPCs: ``ns.CLASSIC_QUEST_NPCS`` [quest] = { objIdx*1e8 + kind*1e7 + npcID }
* QuestCategory: ``ns.CLASSIC_QUEST_CATEGORY`` [quest] = bitmask
* QuestSpawns: ``ns.CLASSIC_QUEST_SPAWNS_SRC`` long string, [quest] = { [uiMapID] = { packed } }
* QuestHolidays_Classic: ``ns.CLASSIC_QUEST_HOLIDAY`` = { event, window }, ``ns.EQ_HOLIDAY_NAMES``

Coordinates come out as map fractions 0..1 (EQ stores floor(x*1e4)). Everything here is a pure
function of the file texts; ``read_everything_quests`` is the only I/O.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from bastians_build.sources.luatable import eval_long_string, new_runtime, run_file, to_python

KIND_NPC, KIND_OBJECT, KIND_ITEM = 1, 2, 3
OBJECTIVE_KINDS = {1: "slay", 2: "object", 3: "loot"}
SOURCE_KINDS = {1: "npc", 2: "object", 3: "item"}
CATEGORY_BITS = {1: "instance", 2: "repeatable", 4: "event", 8: "class", 16: "profession"}
SPECIAL_FLAGS = {1: "repeatable", 2: "scripted", 4: "monthly"}


@dataclass(frozen=True)
class Place:
    """Where a quest starts, is turned in, or has an objective. x, y are map fractions."""

    ui_map_id: int
    x: float
    y: float
    kind: str  # "npc" | "object" | "item" (start) ; "slay" | "object" | "loot" (objective)
    source_id: int | None = (
        None  # creature or object id for start/turn-in; None for items/entrances
    )
    entrance: bool = False  # the real place is inside an instance; this marks the way in
    objective_mask: int | None = None  # objectives of this kind served (bitmask), spawns only


@dataclass(frozen=True)
class Gates:
    required_level: int
    quest_level: int
    special_flags: int
    required_races: int  # bitmask, 0 = no restriction
    required_classes: int  # bitmask, 0 = no restriction

    @property
    def repeatable(self) -> bool:
        return bool(self.special_flags & 1)


@dataclass(frozen=True)
class Objective:
    index: int  # 0-based within its own kind, as the client numbers objectives
    kind: str  # slay | object | loot
    npc_id: int


@dataclass
class Quest:
    id: int
    name: str | None = None
    gates: Gates | None = None
    starts: list[Place] = field(default_factory=list)
    turn_ins: list[Place] = field(default_factory=list)
    coord: Place | None = None  # where the quest is advanced
    pre_any: list[int] = field(default_factory=list)
    pre_all: list[int] = field(default_factory=list)
    exclusive: list[int] = field(default_factory=list)
    chain: int | None = None
    parent: int | None = None
    skill: tuple[int, int] | None = None  # skillLineID, required value
    min_rep: tuple[int, int] | None = None  # factionID, standing
    max_rep: tuple[int, int] | None = None
    categories: set[str] = field(default_factory=set)
    objectives: list[Objective] = field(default_factory=list)
    spawns: list[Place] = field(default_factory=list)
    holiday: str | None = None
    holiday_window: str | None = None


@dataclass
class EverythingQuests:
    flavor: str
    version: str | None
    quests: dict[int, Quest]
    npc_names: dict[int, str]
    object_names: dict[int, str]


# ---------------------------------------------------------------------------------------------
# Decoders (the formulas of the file headers)
# ---------------------------------------------------------------------------------------------


def _split_rest(rest: int) -> tuple[float, float]:
    return (rest // 10_000) / 10_000, (rest % 10_000) / 10_000


def decode_source_place(ui_map_id: int, packed: int) -> Place:
    """start/turn-in place; kinds 5 and 6 mark an instance entrance (QuestAvailable header)."""
    source_id = packed // 1_000_000_000
    kind = (packed // 100_000_000) % 10
    x, y = _split_rest(packed % 100_000_000)
    entrance = kind > 4
    if entrance:
        kind -= 4
    return Place(
        ui_map_id=ui_map_id,
        x=x,
        y=y,
        kind=SOURCE_KINDS.get(kind, str(kind)),
        source_id=source_id or None,
        entrance=entrance,
    )


def decode_spawn(ui_map_id: int, packed: int) -> Place:
    """objective spot: objMask*1e9 + kind*1e8 + x*1e4*1e4 + y*1e4; kinds 5-7 mark an entrance."""
    mask = packed // 1_000_000_000
    kind = (packed % 1_000_000_000) // 100_000_000
    x, y = _split_rest(packed % 100_000_000)
    entrance = kind > 4
    if entrance:
        kind -= 4
    return Place(
        ui_map_id=ui_map_id,
        x=x,
        y=y,
        kind=OBJECTIVE_KINDS.get(kind, str(kind)),
        entrance=entrance,
        objective_mask=mask,
    )


def decode_coord(packed: int) -> Place:
    """where a quest is advanced: uiMapID*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)."""
    ui_map_id = packed // 100_000_000
    x, y = _split_rest(packed % 100_000_000)
    return Place(ui_map_id=ui_map_id, x=x, y=y, kind="progress")


def decode_gates(packed: int) -> Gates:
    """requiredLevel*1e11 + questLevel*1e9 + specialFlags*1e8 + requiredRaces*1e4 + classes."""
    return Gates(
        required_level=packed // 100_000_000_000,
        quest_level=(packed // 1_000_000_000) % 100,
        special_flags=(packed // 100_000_000) % 10,
        required_races=(packed % 100_000_000) // 10_000,
        required_classes=packed % 10_000,
    )


def decode_objective(packed: int) -> Objective:
    """objIdx*1e8 + kind*1e7 + npcID."""
    return Objective(
        index=packed // 100_000_000,
        kind=OBJECTIVE_KINDS.get((packed % 100_000_000) // 10_000_000, "?"),
        npc_id=packed % 10_000_000,
    )


def decode_categories(mask: int) -> set[str]:
    return {name for bit, name in CATEGORY_BITS.items() if mask & bit}


def decode_pair(packed: int, factor: int) -> tuple[int, int]:
    return packed // factor, packed % factor


# ---------------------------------------------------------------------------------------------
# Assembling quests from the tables
# ---------------------------------------------------------------------------------------------


def _places(table: dict | None, decoder) -> dict[int, list[Place]]:
    out: dict[int, list[Place]] = {}
    for quest_id, by_map in (table or {}).items():
        places = []
        for ui_map_id, packed_list in by_map.items():
            for packed in packed_list:
                places.append(decoder(ui_map_id, packed))
        out[quest_id] = places
    return out


def _ids(value) -> list[int]:
    if value is None:
        return []
    if isinstance(value, list):
        return [int(v) for v in value]
    return [int(value)]


def assemble(
    available: dict,
    turn_in: dict | None = None,
    coords: dict | None = None,
    sources: dict | None = None,
    npcs: dict | None = None,
    categories: dict | None = None,
    spawns: dict | None = None,
    holidays: dict | None = None,
    holiday_names: list | None = None,
    flavor: str = "Forever",
    version: str | None = None,
) -> EverythingQuests:
    """Pure: the Python forms of the tables -> quests keyed by id."""
    quests: dict[int, Quest] = {}

    def quest(quest_id: int) -> Quest:
        q = quests.get(quest_id)
        if q is None:
            q = Quest(id=quest_id)
            quests[quest_id] = q
        return q

    for quest_id, name in (available.get("names") or {}).items():
        quest(quest_id).name = name
    for quest_id, packed in (available.get("gates") or {}).items():
        quest(quest_id).gates = decode_gates(packed)
    for quest_id, places in _places(available.get("start"), decode_source_place).items():
        quest(quest_id).starts = places
    for quest_id, places in _places(turn_in, decode_source_place).items():
        quest(quest_id).turn_ins = places
    for quest_id, packed in (coords or {}).items():
        quest(quest_id).coord = decode_coord(packed)
    for key, attr in (("pre", "pre_any"), ("preAll", "pre_all"), ("excl", "exclusive")):
        for quest_id, value in (available.get(key) or {}).items():
            setattr(quest(quest_id), attr, _ids(value))
    for key, attr in (("chain", "chain"), ("parent", "parent")):
        for quest_id, value in (available.get(key) or {}).items():
            setattr(quest(quest_id), attr, int(value))
    for quest_id, packed in (available.get("skill") or {}).items():
        quest(quest_id).skill = decode_pair(packed, 10_000)
    for quest_id, packed in (available.get("minRep") or {}).items():
        quest(quest_id).min_rep = decode_pair(packed, 1_000_000)
    for quest_id, packed in (available.get("maxRep") or {}).items():
        quest(quest_id).max_rep = decode_pair(packed, 1_000_000)
    for quest_id, mask in (categories or {}).items():
        quest(quest_id).categories = decode_categories(mask)
    for quest_id, packed_list in (npcs or {}).items():
        quest(quest_id).objectives = [decode_objective(p) for p in packed_list]
    for quest_id, places in _places(spawns, decode_spawn).items():
        quest(quest_id).spawns = places
    names = holiday_names or []
    for quest_id, index in ((holidays or {}).get("event") or {}).items():
        quest(quest_id).holiday = names[index - 1] if 0 < index <= len(names) else str(index)
    for quest_id, window in ((holidays or {}).get("window") or {}).items():
        quest(quest_id).holiday_window = window
    sources = sources or {}
    return EverythingQuests(
        flavor=flavor,
        version=version,
        quests=dict(sorted(quests.items())),
        npc_names={int(k): v for k, v in (sources.get("npc") or {}).items()},
        object_names={int(k): v for k, v in (sources.get("obj") or {}).items()},
    )


# ---------------------------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------------------------

FILES = {
    "available": "QuestAvailable_{f}.lua",
    "turn_in": "QuestTurnIn_{f}.lua",
    "coords": "QuestCoords_{f}.lua",
    "sources": "QuestSources_{f}.lua",
    "npcs": "QuestNPCs_{f}.lua",
    "categories": "QuestCategory_{f}.lua",
    "spawns": "QuestSpawns_{f}.lua",
}
TABLES = {
    "available": "CLASSIC_QUEST_AVAILABLE",
    "turn_in": "CLASSIC_QUEST_TURNIN",
    "coords": "CLASSIC_QUEST_COORDS",
    "sources": "CLASSIC_QUEST_SOURCES",
    "npcs": "CLASSIC_QUEST_NPCS",
    "categories": "CLASSIC_QUEST_CATEGORY",
}


def read_version(toc_text: str) -> str | None:
    for line in toc_text.splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    return None


def read_everything_quests(
    addon_dir: Path, flavor: str = "Forever", *, spawns: bool = True
) -> EverythingQuests:
    """Read an installed Everything Quests folder. `spawns=False` skips the 6 MB objective spots."""
    data = addon_dir / "Data"
    tables: dict[str, dict] = {}
    for key, pattern in FILES.items():
        if key == "spawns" and not spawns:
            continue
        path = data / pattern.format(f=flavor)
        if not path.is_file():
            if key == "available":
                raise FileNotFoundError(path)
            continue
        lua = new_runtime()
        ns = run_file(lua, path)
        if key == "spawns":
            tables[key] = to_python(eval_long_string(lua, ns.CLASSIC_QUEST_SPAWNS_SRC))
        else:
            tables[key] = to_python(ns[TABLES[key]])
    holidays = data / "QuestHolidays_Classic.lua"
    holiday_tables = None
    holiday_names = None
    if holidays.is_file():
        lua = new_runtime()
        ns = run_file(lua, holidays)
        if ns.CLASSIC_QUEST_HOLIDAY is not None:
            holiday_tables = to_python(ns.CLASSIC_QUEST_HOLIDAY)
        if ns.EQ_HOLIDAY_NAMES is not None:
            holiday_names = to_python(ns.EQ_HOLIDAY_NAMES)
    tocs = sorted(addon_dir.glob("*.toc"))
    version = read_version(tocs[0].read_text(encoding="utf-8")) if tocs else None
    return assemble(
        tables["available"],
        turn_in=tables.get("turn_in"),
        coords=tables.get("coords"),
        sources=tables.get("sources"),
        npcs=tables.get("npcs"),
        categories=tables.get("categories"),
        spawns=tables.get("spawns"),
        holidays=holiday_tables,
        holiday_names=holiday_names,
        flavor=flavor,
        version=version,
    )
