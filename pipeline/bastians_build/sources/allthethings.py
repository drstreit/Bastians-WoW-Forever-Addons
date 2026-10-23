"""Reader for AllTheThings (MIT): the retail quest, NPC and object places (sources.md, B4.1).

ATT ships its world as Lua files under ``db/<flavor>/Categories`` (``Standard`` = retail,
``Camelot`` = Forever). Each file registers one ``OnBuildDataCache`` handler that builds a tree by
calling the addon's constructors: ``m(mapID, t)``, ``q(questID, t)``, ``n(npcID, t)``,
``o(objectID, t)``, ``fp(id, t)``,
``i(itemID, t)``, ``s(sourceID, itemID, t)``, headers ``h(-id, t)`` and many more. Children sit in
``t.g`` or in the array part of ``t``. The reader runs the files on a sandboxed Lua 5.1 (lupa) with
stub constructors that record every call, links children to parents, and reads the fields it needs.

What ATT carries (measured 20.10.2026, ATT 5.4.3, ``db/Standard``): 48,586 quest entries (32,316
with ``coords``, 31,155 with ``qgs``), 8,044 NPC and 7,941 object entries with places, 1,518 flight
paths,
795 maps; **no quest or NPC names** (the addon reads them from the client at runtime), object names
in ``LocalizationDB.lua`` (8,444). ``coords`` are ``{ [uiMapID] = { {x, y}, ... } }`` in map percent
(older entries: ``{ {x, y, uiMapID}, ... }``); the reader returns map fractions. ``r`` is the
faction
(1 Horde, 2 Alliance), ``u`` the availability code (1 never implemented, 2 removed from the game, 3
real money, 7 trading post, ...), ``awp``/``rwp`` the patch that added/removed the entry. ``u``,
``r``,
``races`` and ``c`` are inherited from the nearest ancestor when an entry has none, as ATT does at
runtime. The same id appears in several places of the tree; the reader merges the occurrences.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from lupa import lua51

from bastians_build.sources.luatable import LuaDataError, to_python

FLAVORS = ("Standard", "Camelot")
HORDE, ALLIANCE = 1, 2
PROVIDER_KINDS = {"n": "npc", "o": "object", "i": "item"}
FLAG_FIELDS = {
    "isDaily": "daily",
    "isWeekly": "weekly",
    "isMonthly": "monthly",
    "isYearly": "yearly",
    "repeatable": "repeatable",
    "isWorldQuest": "worldquest",
    "isBreadcrumb": "breadcrumb",
    "isRaid": "raid",
    "pvp": "pvp",
}

# The stub addon table: every Create* call records {kind, id, t} and returns t; anything else the
# data files touch (WOWAPI, L, Enum, GetCVar, ...) is a permissive value that can be called,
# indexed, concatenated and compared without raising. The files run their handlers against an empty
# categories table. `link_parents` walks `g` lists and array parts with `pairs`, since inline
# functions in the data return nil for some entries and `ipairs` would stop there.
SANDBOX = r"""
local records = {}
local function make(kind, needsTwo)
  return function(id, b, c)
    local t = c or b
    if type(t) ~= "table" then t = {} end
    if needsTwo then t.__second = b end
    t.__kind = kind
    t.__id = id
    records[#records + 1] = t
    return t
  end
end
local function anything(k)
  return setmetatable({}, {
    __call = function() return 0 end,
    __index = function(_, k2) return anything(k .. "." .. tostring(k2)) end,
    __concat = function(a, b)
      local left = type(a) == "table" and "" or tostring(a)
      return left .. (type(b) == "table" and "" or tostring(b))
    end,
    __tostring = function() return "" end,
  })
end
local app = {}
app.L = setmetatable({}, { __index = function(_, k) return tostring(k) end })
app.handlers = {}
app.AddEventHandler = function(_, fn) app.handlers[#app.handlers + 1] = fn end
local kinds = {
  CreateQuest = "q", CreateNPC = "n", CreateObject = "o", CreateMap = "m", CreateFlightPath = "fp",
  CreateItem = "i", CreateItemSource = "s", CreateHeader = "h", CreateCustomHeader = "hdr",
}
for fname, kind in pairs(kinds) do app[fname] = make(kind, kind == "s") end
setmetatable(app, { __index = function(_, k)
  if type(k) == "string" and k:sub(1, 6) == "Create" then return make(k:sub(7)) end
  return anything(k)
end })
app.WOWAPI = setmetatable({}, { __index = function() return function() return 0 end end })
app.Level, app.FactionID, app.RaceIndex, app.ClassIndex, app.MODE_DEBUG = 80, 2, 1, 1, false
local sformat = string.format
string.format = function(fmt, ...)
  local args = { ... }
  for i = 1, select("#", ...) do
    local v = args[i]
    if type(v) ~= "number" and type(v) ~= "string" then args[i] = tostring(v) end
  end
  local ok, res = pcall(sformat, tostring(fmt), unpack(args))
  return ok and res or ""
end
_G.app = app
_G.records = records
setmetatable(_G, { __index = function(_, k) return anything(k) end })

function link_parents()
  for _, rec in ipairs(records) do
    for _, list in ipairs({ rec, rawget(rec, "g") or false }) do
      if type(list) == "table" then
        for k, child in pairs(list) do
          if type(k) == "number" and type(child) == "table" and rawget(child, "__kind")
            and not rawget(child, "__parent") then
            child.__parent = rec
          end
        end
      end
    end
  end
end

local function enclosing_map(rec)
  local p = rec.__parent
  while p do
    if p.__kind == "m" then return p.__id end
    p = p.__parent
  end
  return nil
end

local function inherited(rec, key)
  local p = rec
  while p do
    local v = rawget(p, key)
    if v ~= nil then return v end
    p = p.__parent
  end
  return nil
end

local function child_items(rec)
  local out = {}
  for _, list in ipairs({ rec, rawget(rec, "g") or false }) do
    if type(list) == "table" then
      for k, child in pairs(list) do
        local kind = type(k) == "number" and type(child) == "table" and child.__kind
        if kind == "i" or kind == "s" then
          local id = child.__kind == "s" and rawget(child, "__second") or child.__id
          if type(id) == "number" then out[#out + 1] = id end
        end
      end
    end
  end
  return out
end

-- Flat per-kind tables of the fields the pipeline reads; conversion to Python happens once.
function extract()
  local out = { q = {}, n = {}, o = {}, fp = {}, m = {} }
  for _, r in ipairs(records) do
    local kind = r.__kind
    if kind == "q" then
      out.q[#out.q + 1] = {
        id = r.__id, zone = enclosing_map(r), coords = rawget(r, "coords"),
        u = inherited(r, "u"), r = inherited(r, "r"), races = inherited(r, "races"),
        c = inherited(r, "c"),
        lvl = rawget(r, "lvl"), qgs = rawget(r, "qgs"), providers = rawget(r, "providers"),
        sourceQuests = rawget(r, "sourceQuests"), sqreq = rawget(r, "sqreq"),
        nextQuests = rawget(r, "nextQuests"), altQuests = rawget(r, "altQuests"),
        crs = rawget(r, "crs"), qis = rawget(r, "qis"), maps = rawget(r, "maps"),
        awp = rawget(r, "awp"), rwp = rawget(r, "rwp"), rewards = child_items(r),
        isDaily = rawget(r, "isDaily"), isWeekly = rawget(r, "isWeekly"),
        isMonthly = rawget(r, "isMonthly"),
        isYearly = rawget(r, "isYearly"), repeatable = rawget(r, "repeatable"),
        isWorldQuest = rawget(r, "isWorldQuest"), isBreadcrumb = rawget(r, "isBreadcrumb"),
        isRaid = rawget(r, "isRaid"), pvp = rawget(r, "pvp"),
      }
    elseif kind == "n" or kind == "o" or kind == "fp" then
      local coords = rawget(r, "coords")
      if coords ~= nil or kind == "fp" then
        out[kind][#out[kind] + 1] = {
          id = r.__id, zone = enclosing_map(r), coords = coords, u = inherited(r, "u"),
          r = inherited(r, "r"), crs = rawget(r, "crs"),
        }
      end
    elseif kind == "m" then
      out.m[#out.m + 1] = { id = r.__id, lvl = rawget(r, "lvl"), maps = rawget(r, "maps") }
    end
  end
  return out
end
"""


@dataclass(frozen=True)
class Point:
    """A place on a map as fractions 0..1."""

    ui_map_id: int
    x: float
    y: float


@dataclass
class AttQuest:
    id: int
    zone: int | None = None  # the uiMapID of the enclosing map group, if any
    places: list[Point] = field(default_factory=list)  # where the quest is picked up
    givers: list[str] = field(default_factory=list)  # entity refs: npc:1, object:2, item:3
    faction: str | None = None  # "A" | "H" | None (both)
    races: list[int] = field(default_factory=list)  # race ids, empty = no restriction
    classes: list[int] = field(default_factory=list)  # class ids, empty = no restriction
    min_level: int | None = None
    max_level: int | None = None
    pre: list[int] = field(default_factory=list)  # sourceQuests
    pre_required: int | None = None  # sqreq: how many of `pre` are needed (None = all)
    next: list[int] = field(default_factory=list)
    alt: list[int] = field(default_factory=list)  # altQuests: taking one rules out the others
    targets: list[int] = field(default_factory=list)  # crs: creatures of the objectives
    items: list[int] = field(default_factory=list)  # qis: quest items
    rewards: list[int] = field(default_factory=list)  # item ids listed under the quest
    maps: list[int] = field(default_factory=list)
    flags: set[str] = field(default_factory=set)
    unavailable: int | None = None  # ATT `u` code, None = obtainable
    added: int | None = None  # awp
    removed: int | None = None  # rwp


@dataclass
class AttPlaced:
    """An NPC, object or flight path with its places."""

    id: int
    zone: int | None = None
    places: list[Point] = field(default_factory=list)
    faction: str | None = None
    unavailable: int | None = None
    creatures: list[int] = field(default_factory=list)  # flight paths: the flight master (crs)


@dataclass
class AttMap:
    id: int
    level_lo: int | None = None
    level_hi: int | None = None
    maps: list[int] = field(default_factory=list)  # child map ids this entry also stands for


@dataclass
class AllTheThings:
    flavor: str
    version: str | None
    quests: dict[int, AttQuest]
    npcs: dict[int, AttPlaced]
    objects: dict[int, AttPlaced]
    flightpaths: dict[int, AttPlaced]
    maps: dict[int, AttMap]
    object_names: dict[int, str]


class AllTheThingsError(ValueError):
    pass


# ---------------------------------------------------------------------------------------------
# Field decoders (pure)
# ---------------------------------------------------------------------------------------------


def _num(v) -> bool:
    return isinstance(v, int | float) and not isinstance(v, bool)


def decode_coords(coords) -> list[Point]:
    """``{ [uiMapID] = { {x, y}, ... } }`` or ``{ {x, y, uiMapID}, ... }`` (percent) -> fractions.

    A keyed table whose map ids happen to be 1..n (Durotar is uiMapID 1) arrives as a list of
    point lists; a list of number triples is the older shape. Both are told apart by the
    elements."""
    if not isinstance(coords, dict | list):
        return []
    out: list[Point] = []
    if isinstance(coords, dict):
        items = list(coords.items())
    elif coords and all(isinstance(c, list) and c and isinstance(c[0], list) for c in coords):
        items = list(enumerate(coords, 1))  # keyed by 1..n: the index is the uiMapID
    else:
        items = [(None, c) for c in coords]
    for key, value in items:
        if isinstance(key, int) and isinstance(value, list):
            for pt in value:
                if isinstance(pt, list) and len(pt) >= 2 and _num(pt[0]) and _num(pt[1]):
                    out.append(Point(key, round(pt[0] / 100, 4), round(pt[1] / 100, 4)))
        elif key is None and isinstance(value, list) and len(value) >= 3:
            x, y, ui_map_id = value[0], value[1], value[2]
            if _num(x) and _num(y) and isinstance(ui_map_id, int):
                out.append(Point(ui_map_id, round(x / 100, 4), round(y / 100, 4)))
    return out


def decode_faction(r) -> str | None:
    if r == ALLIANCE:
        return "A"
    if r == HORDE:
        return "H"
    return None


def decode_level(lvl) -> tuple[int | None, int | None]:
    """``lvl`` is the required level, or ``{lo, hi}`` for a level band."""
    if isinstance(lvl, int) and not isinstance(lvl, bool):
        return lvl, None
    if isinstance(lvl, list) and lvl and isinstance(lvl[0], int):
        hi = lvl[1] if len(lvl) > 1 and isinstance(lvl[1], int) else None
        return lvl[0], hi
    return None, None


def _int_list(value) -> list[int]:
    if isinstance(value, int) and not isinstance(value, bool):
        return [value]
    if not isinstance(value, list):
        return []
    return [v for v in value if isinstance(v, int) and not isinstance(v, bool)]


def decode_providers(qgs, providers) -> list[str]:
    """``qgs`` (quest giver NPC ids) and ``providers`` (``{ {"n"|"o"|"i", id}, ... }``) -> refs."""
    refs: list[str] = []
    for npc_id in _int_list(qgs):
        ref = f"npc:{npc_id}"
        if ref not in refs:
            refs.append(ref)
    for p in providers or []:
        if isinstance(p, list) and len(p) >= 2 and p[0] in PROVIDER_KINDS and isinstance(p[1], int):
            ref = f"{PROVIDER_KINDS[p[0]]}:{p[1]}"
            if ref not in refs:
                refs.append(ref)
    return refs


def _merge_unavailable(current: int | None, new, seen_before: bool) -> int | None:
    """An id obtainable in one place of the tree is obtainable: None wins; else the lowest code."""
    new = new if isinstance(new, int) and not isinstance(new, bool) else None
    if not seen_before:
        return new
    if current is None or new is None:
        return None
    return min(current, new)


def assemble(
    raw: dict, object_names: dict[int, str], flavor: str, version: str | None
) -> AllTheThings:
    """The flat Lua extraction -> merged records per id."""
    quests: dict[int, AttQuest] = {}
    for e in raw.get("q") or []:
        qid = e.get("id")
        if not isinstance(qid, int):
            continue
        seen = qid in quests
        q = quests.setdefault(qid, AttQuest(id=qid))
        q.unavailable = _merge_unavailable(q.unavailable, e.get("u"), seen)
        if q.zone is None and isinstance(e.get("zone"), int):
            q.zone = e["zone"]
        for pt in decode_coords(e.get("coords")):
            if pt not in q.places:
                q.places.append(pt)
        for ref in decode_providers(e.get("qgs"), e.get("providers")):
            if ref not in q.givers:
                q.givers.append(ref)
        if q.faction is None:
            q.faction = decode_faction(e.get("r"))
        lists = (
            ("races", q.races),
            ("c", q.classes),
            ("sourceQuests", q.pre),
            ("nextQuests", q.next),
            ("altQuests", q.alt),
            ("crs", q.targets),
            ("qis", q.items),
            ("rewards", q.rewards),
            ("maps", q.maps),
        )
        for key, target in lists:
            for v in _int_list(e.get(key)):
                if v not in target:
                    target.append(v)
        if q.min_level is None:
            q.min_level, q.max_level = decode_level(e.get("lvl"))
        if isinstance(e.get("sqreq"), int):
            q.pre_required = e["sqreq"]
        for key, flag in FLAG_FIELDS.items():
            if e.get(key):
                q.flags.add(flag)
        if q.added is None and isinstance(e.get("awp"), int):
            q.added = e["awp"]
        if q.removed is None and isinstance(e.get("rwp"), int):
            q.removed = e["rwp"]
    placed: dict[str, dict[int, AttPlaced]] = {"n": {}, "o": {}, "fp": {}}
    for kind in ("n", "o", "fp"):
        for e in raw.get(kind) or []:
            rid = e.get("id")
            if not isinstance(rid, int) or rid < 1:
                continue  # negative ids are ATT headers
            seen = rid in placed[kind]
            p = placed[kind].setdefault(rid, AttPlaced(id=rid))
            p.unavailable = _merge_unavailable(p.unavailable, e.get("u"), seen)
            if p.zone is None and isinstance(e.get("zone"), int):
                p.zone = e["zone"]
            for pt in decode_coords(e.get("coords")):
                if pt not in p.places:
                    p.places.append(pt)
            if p.faction is None:
                p.faction = decode_faction(e.get("r"))
            for v in _int_list(e.get("crs")):
                if v not in p.creatures:
                    p.creatures.append(v)
    maps: dict[int, AttMap] = {}
    for e in raw.get("m") or []:
        mid = e.get("id")
        if not isinstance(mid, int) or mid < 1:
            continue
        m = maps.setdefault(mid, AttMap(id=mid))
        if m.level_lo is None:
            m.level_lo, m.level_hi = decode_level(e.get("lvl"))
        for v in _int_list(e.get("maps")):
            if v not in m.maps:
                m.maps.append(v)
    return AllTheThings(
        flavor=flavor,
        version=version,
        quests=quests,
        npcs=placed["n"],
        objects=placed["o"],
        flightpaths=placed["fp"],
        maps=maps,
        object_names=object_names,
    )


# ---------------------------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------------------------


def read_version(toc: Path) -> str | None:
    if not toc.is_file():
        return None
    m = re.search(r"^## Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8-sig"), re.M)
    return m.group(1) if m else None


def read_object_names(lua: lua51.LuaRuntime, path: Path) -> dict[int, str]:
    """``local ObjectNames = { ... } _.ObjectNames = ObjectNames`` from LocalizationDB.lua, run on
    its own: the rest of that file needs the live addon. Non-string values are skipped."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8-sig")
    start = text.find("local ObjectNames = {")
    if start < 0:
        return {}
    end = text.find("} _.ObjectNames = ObjectNames", start)
    if end < 0:
        return {}
    body = text[start + len("local ObjectNames = ") : end + 1]
    chunk = lua.globals().loadstring("local _ = ...; local L = _.L; return " + body, "@ObjectNames")
    if isinstance(chunk, tuple):
        raise AllTheThingsError(f"{path.name}: ObjectNames: {chunk[1]}")
    table = chunk(lua.globals().app)
    out: dict[int, str] = {}
    for key, value in to_python(table).items():
        if isinstance(key, int) and isinstance(value, str) and value:
            out[key] = value
    return out


def read_allthethings(att_dir: Path, flavor: str = "Standard") -> AllTheThings:
    """Run ``db/<flavor>/Categories/*.lua`` and return the merged records. ``att_dir`` is the addon
    folder (with ``AllTheThings.toc``)."""
    if flavor not in FLAVORS:
        raise AllTheThingsError(
            f"unknown AllTheThings flavor {flavor!r}, expected one of {FLAVORS}"
        )
    db = att_dir / "db" / flavor
    categories = sorted((db / "Categories").glob("*.lua"))
    if not categories:
        raise AllTheThingsError(f"no data files under {db / 'Categories'}")
    lua = lua51.LuaRuntime(
        unpack_returned_tuples=True, register_eval=False, register_builtins=False
    )
    lua.execute(SANDBOX)
    app = lua.globals().app
    for path in categories:
        chunk = lua.globals().loadstring(path.read_text(encoding="utf-8-sig"), f"@{path.name}")
        if isinstance(chunk, tuple):
            raise AllTheThingsError(f"{path.name}: {chunk[1]}")
        try:
            chunk("AllTheThings", app)
        except lua51.LuaError as exc:
            raise AllTheThingsError(f"{path.name}: {exc}") from exc
    handlers = app.handlers
    for i in range(1, len(handlers) + 1):
        try:
            handlers[i](lua.table())
        except lua51.LuaError as exc:
            raise AllTheThingsError(f"OnBuildDataCache handler {i}: {exc}") from exc
    lua.globals().link_parents()
    try:
        raw = to_python(lua.globals().extract())
    except LuaDataError as exc:
        raise AllTheThingsError(str(exc)) from exc
    object_names = read_object_names(lua, db / "LocalizationDB.lua")
    return assemble(raw, object_names, flavor, read_version(att_dir / "AllTheThings.toc"))
