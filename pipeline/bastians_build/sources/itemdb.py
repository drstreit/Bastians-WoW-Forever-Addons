"""Reader for LibItemDB (addon folder ``ItemDB``, MIT): retail item names, item facts and the
"where to get it" places (sources.md, B4.1).

The data files call the library: ``lib:LoadNames({ [id] = "name" })`` per locale,
``lib:LoadCore(classID, { [id] = "quality<SEP>subclass<SEP>equipLoc<SEP>itemLevel<SEP>stats" })``
per item class file under ``Data/<flavor>/_core`` and ``lib:LoadItemPlaces(entities, items)`` with
``SEP`` = ``\\031``. Places (``ItemPlaces.lua``, retail: 10,489 creatures and 1,233 objects, 43,560
items, measured 20.10.2026, ItemDB 1.6.0) are re-expressed from the TrinityCore world database and
wago.tools by ItemDB's build tools:

* entity ``"c<id>"`` = ``"<name><SEP><side><SEP><place>..."`` with side ``A``, ``H``, ``AH`` or
  empty (hostile to both); ``"o<id>"`` = ``"<name><SEP><profession><SEP><place>..."`` with
  ``Herbalism``, ``Mining``, ``Fishing`` or empty (a plain chest);
* place ``"<uiMapID>:<count>:<x>,<y>;<x>,<y>"`` (map percent, up to three points standing for
  ``count`` spawns) or ``"@<instance>:<count>"``;
* item ``"<kind><entity>[:<chance>[:<condition>]],..."`` with kind ``d`` drop (chance in percent,
  negative = only while on a quest), ``v`` vendor, ``g`` gathered or looted from an object, ``q`` a
  quest giver (the second field is the quest id).

The reader runs the files on a sandboxed Lua 5.1 (lupa) with a stub library that records the calls;
everything else is a pure function of the recorded tables.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from lupa import lua51

from bastians_build.sources.luatable import to_python

SEP = "\x1f"
FLAVORS = ("Retail", "Forever")
PLACE_KINDS = {"d": "drop", "v": "vendor", "g": "object", "q": "quest"}
CONDITIONS = {
    "A": "Alliance",
    "H": "Horde",
    "e": "event",
    "qd": "questDone",
    "qt": "questTaken",
    "qn": "questNotStarted",
    "c": "other",
}
TOKEN = re.compile(r"^([a-z])(\d+):?(-?[\d.]*):?(\w*)$")

SANDBOX = r"""
local calls = { names = {}, core = {}, places = {}, build = nil }
local lib = {}
function lib:SetBuild(build) calls.build = build end
function lib:LoadNames(names) calls.names[#calls.names + 1] = names end
function lib:LoadCore(classID, bucket) calls.core[#calls.core + 1] = { classID, bucket } end
function lib:LoadItemPlaces(entities, items)
  calls.places[#calls.places + 1] = { entities, items }
end
setmetatable(lib, { __index = function() return function() end end })
LibStub = function() return lib end
GetLocale = function() return "enUS" end
_G.calls = calls
"""


class ItemDBError(ValueError):
    pass


@dataclass(frozen=True)
class ItemCore:
    id: int
    class_id: int
    quality: int | None
    subclass_id: int | None
    equip_loc: str | None
    item_level: int | None


@dataclass(frozen=True)
class PlacePoint:
    ui_map_id: int
    count: int
    points: tuple[tuple[float, float], ...]  # map fractions


@dataclass
class PlaceEntity:
    kind: str  # "npc" | "object"
    id: int
    name: str
    side: str | None = None  # creatures: "A", "H", "AH", or None when hostile to both
    profession: str | None = None  # objects: Herbalism, Mining, Fishing, or None (a chest)
    places: list[PlacePoint] = field(default_factory=list)
    instances: list[tuple[str, int]] = field(default_factory=list)  # (instance name, count)


@dataclass(frozen=True)
class ItemSource:
    kind: str  # drop | vendor | object | quest
    entity: str  # "c<id>" or "o<id>", the key into Places.entities
    chance: float | None = None  # percent, drops and objects
    quest_only: bool = False
    quest_id: int | None = None  # quest rows
    condition: str | None = None  # drops: Alliance, Horde, event, questDone, ..., skill, other
    condition_skill: int | None = None


@dataclass
class Places:
    entities: dict[str, PlaceEntity]
    items: dict[int, list[ItemSource]]


@dataclass
class ItemDB:
    flavor: str
    version: str | None
    build: str | None
    names: dict[int, str]
    core: dict[int, ItemCore]
    places: Places


# ---------------------------------------------------------------------------------------------
# Decoders (pure)
# ---------------------------------------------------------------------------------------------


def _int(value) -> int | None:
    try:
        return int(value)
    except TypeError, ValueError:
        return None


def decode_core(item_id: int, class_id: int, packed: str) -> ItemCore:
    fields = packed.split(SEP)
    quality = _int(fields[0]) if len(fields) > 0 else None
    subclass = _int(fields[1]) if len(fields) > 1 else None
    equip = fields[2] if len(fields) > 2 and fields[2] else None
    level = _int(fields[3]) if len(fields) > 3 else None
    return ItemCore(item_id, class_id, quality, subclass if subclass != -1 else None, equip, level)


def decode_place(text: str) -> PlacePoint | tuple[str, int] | None:
    m = re.match(r"^@(.*):(\d+)$", text)
    if m:
        return m.group(1), int(m.group(2))
    m = re.match(r"^(\d+):(\d+):?(.*)$", text)
    if not m:
        return None
    points = tuple(
        (round(float(x) / 100, 4), round(float(y) / 100, 4))
        for x, y in re.findall(r"([\d.]+),([\d.]+)", m.group(3))
    )
    return PlacePoint(int(m.group(1)), int(m.group(2)), points)


def decode_entity(key: str, packed: str) -> PlaceEntity | None:
    m = re.match(r"^([co])(\d+)$", key)
    if not m:
        return None
    fields = packed.split(SEP)
    name = fields[0] if fields and fields[0] else None
    if name is None:
        return None
    kind = "npc" if m.group(1) == "c" else "object"
    second = fields[1] if len(fields) > 1 and fields[1] else None
    entity = PlaceEntity(
        kind=kind,
        id=int(m.group(2)),
        name=name,
        side=second if kind == "npc" else None,
        profession=second if kind == "object" else None,
    )
    for raw in fields[2:]:
        place = decode_place(raw)
        if isinstance(place, PlacePoint):
            entity.places.append(place)
        elif isinstance(place, tuple):
            entity.instances.append(place)
    return entity


def decode_item_sources(packed: str) -> list[ItemSource]:
    out: list[ItemSource] = []
    for token in packed.split(","):
        m = TOKEN.match(token.strip())
        if not m:
            continue
        letter, entity_id, number, cond = m.groups()
        kind = PLACE_KINDS.get(letter)
        if kind is None:
            continue
        entity = ("o" if letter == "g" else "c") + entity_id
        chance = quest_id = None
        quest_only = False
        if number:
            if letter == "q":
                quest_id = _int(number)
            else:
                value = float(number)
                chance, quest_only = abs(value), value < 0
        condition = condition_skill = None
        if cond:
            skill = re.match(r"^s(\d+)$", cond)
            if skill:
                condition, condition_skill = "skill", int(skill.group(1))
            else:
                condition = CONDITIONS.get(cond, "other")
        out.append(
            ItemSource(kind, entity, chance, quest_only, quest_id, condition, condition_skill)
        )
    return out


# ---------------------------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------------------------


def _run(lua: lua51.LuaRuntime, path: Path) -> None:
    chunk = lua.globals().loadstring(path.read_text(encoding="utf-8-sig"), f"@{path.name}")
    if isinstance(chunk, tuple):
        raise ItemDBError(f"{path.name}: {chunk[1]}")
    try:
        chunk("ItemDB")
    except lua51.LuaError as exc:
        raise ItemDBError(f"{path.name}: {exc}") from exc


def read_version(toc: Path) -> str | None:
    if not toc.is_file():
        return None
    m = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8-sig"), re.M)
    return m.group(1) if m else None


def read_itemdb(itemdb_dir: Path, flavor: str = "Retail", locale: str = "enUS") -> ItemDB:
    """Names of one locale, the core of every item class file and the places of
    ``Data/<flavor>``."""
    if flavor not in FLAVORS:
        raise ItemDBError(f"unknown ItemDB flavor {flavor!r}, expected one of {FLAVORS}")
    data = itemdb_dir / "Data" / flavor
    core_dir = data / "_core"
    if not core_dir.is_dir():
        raise ItemDBError(f"no ItemDB core under {core_dir}")
    lua = lua51.LuaRuntime(
        unpack_returned_tuples=True, register_eval=False, register_builtins=False
    )
    lua.execute(SANDBOX)
    names_file = data / locale / "Names.lua"
    if names_file.is_file():
        _run(lua, names_file)
    for path in sorted(core_dir.glob("*.lua")):
        _run(lua, path)
    calls = to_python(lua.globals().calls)
    names: dict[int, str] = {}
    for table in calls.get("names") or []:
        for key, value in (table or {}).items():
            item_id = _int(key)
            if item_id is not None and isinstance(value, str) and value:
                names[item_id] = value
    core: dict[int, ItemCore] = {}
    for class_id, bucket in calls.get("core") or []:
        for key, packed in (bucket or {}).items():
            item_id = _int(key)
            if item_id is not None and isinstance(packed, str):
                core[item_id] = decode_core(item_id, int(class_id), packed)
    entities: dict[str, PlaceEntity] = {}
    items: dict[int, list[ItemSource]] = {}
    for entity_table, item_table in calls.get("places") or []:
        for key, packed in (entity_table or {}).items():
            if isinstance(key, str) and isinstance(packed, str):
                entity = decode_entity(key, packed)
                if entity is not None:
                    entities[key] = entity
        for key, packed in (item_table or {}).items():
            item_id = _int(key)
            if item_id is not None and isinstance(packed, str):
                items[item_id] = decode_item_sources(packed)
    build = calls.get("build")
    return ItemDB(
        flavor=flavor,
        version=read_version(itemdb_dir / "ItemDB.toc"),
        build=str(build) if build is not None else None,
        names=names,
        core=core,
        places=Places(entities, items),
    )
