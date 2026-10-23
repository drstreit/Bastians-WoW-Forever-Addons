"""Readers for `tools/clientdump db2` JSON (client-extraction.md): TaxiNodes, UiMap and
UiMapAssignment.

The dump is ``{"table": "TaxiNodes", "build": "...", "rows": [ {...}, ... ]}``. A row's ``Pos``
is the world position ``[X, Y, Z]`` with X growing north and Y growing west (coordinates.md:
``wx = X``, ``wy = Y``); ``ContinentID`` 0 is Eastern Kingdoms, 1 Kalimdor. ``Flags`` bit 1 marks
an Alliance node, bit 2 a Horde node; rows with neither bit are dummy nodes (transport paths,
quest flights, "Programmer Isle") and are skipped. Checked on the Forever dump of 19.10.2026:
every real flight master carries a faction bit, every "Transport, ..." and "Quest Path ..." row
carries none.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from bastians_build.sources.probe import Transform

# A continent is a Map.db2 id (the instance id the client's world positions report). Without a Map
# dump only the two Azeroth continents count; with one (`<prefix>_Map.json`, `world_continents`)
# every world map with a zone counts: Outland, Northrend, ... on retail, Zephras Isle on Forever.
CONTINENTS = (0, 1)
MAP_CONTINENT = {0: 0, 1: 1}  # Map.db2 id (Azeroth, Kalimdor) -> continent index
ALLIANCE, HORDE = 1, 2
WORLD_INSTANCE_TYPE = 0  # Map.db2 InstanceType of open-world maps
UI_MAP_CONTINENT, UI_MAP_ZONE = 2, 3  # UiMap.Type


class ClientDumpError(ValueError):
    """The dump is not what clientdump writes."""


@dataclass(frozen=True)
class TaxiNode:
    id: int
    name: str
    faction: str  # "A" | "H" | "both"
    continent: int
    wx: float
    wy: float


@dataclass
class TaxiDump:
    build: str | None
    nodes: list[TaxiNode]
    dropped: list[tuple[int, str, str]]  # (id, name, reason)


def faction_of(flags: int) -> str | None:
    """ "A", "H", "both" from the TaxiNodes flag bits; None for a dummy node."""
    a, h = bool(flags & ALLIANCE), bool(flags & HORDE)
    if a and h:
        return "both"
    if a:
        return "A"
    if h:
        return "H"
    return None


def read_taxi_nodes(path: Path, continents=None) -> TaxiDump:
    """Every real flight master on the given continents (default: the two Azeroth continents),
    plus what was dropped and why."""
    allowed = set(continents) if continents is not None else set(CONTINENTS)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise ClientDumpError(f"{path}: not JSON ({err})") from err
    if not isinstance(data, dict) or data.get("table") != "TaxiNodes":
        raise ClientDumpError(f"{path}: expected a clientdump TaxiNodes dump")
    rows = data.get("rows")
    if not isinstance(rows, list):
        raise ClientDumpError(f"{path}: rows missing")
    nodes: list[TaxiNode] = []
    dropped: list[tuple[int, str, str]] = []
    for row in rows:
        node_id = row.get("ID")
        name = str(row.get("Name_lang") or "")
        if not isinstance(node_id, int):
            raise ClientDumpError(f"{path}: a row has no integer ID: {row!r}")
        faction = faction_of(int(row.get("Flags") or 0))
        continent = row.get("ContinentID")
        pos = row.get("Pos")
        if faction is None:
            dropped.append((node_id, name, "no faction bit (dummy node)"))
            continue
        if continent not in allowed:
            dropped.append((node_id, name, f"continent {continent} is not a world continent"))
            continue
        if not (isinstance(pos, list) and len(pos) >= 2):
            dropped.append((node_id, name, "no position"))
            continue
        nodes.append(
            TaxiNode(node_id, name, faction, int(continent), round(pos[0], 2), round(pos[1], 2))
        )
    nodes.sort(key=lambda n: n.id)
    build = data.get("build")
    return TaxiDump(str(build) if build else None, nodes, dropped)


# --- UiMap and UiMapAssignment ---------------------------------------------------------------


@dataclass(frozen=True)
class UiMapRow:
    id: int
    name: str
    parent: int | None
    type: int  # 1 cosmic/world, 2 continent, 3 zone, 4 dungeon, 5 micro, 6 orphan
    system: int = 0  # UiMap.System: 0 is the world map; 1 and 2 are other map systems (retail)


@dataclass(frozen=True)
class Assignment:
    ui_map_id: int
    map_id: int
    min_x: float
    min_y: float
    max_x: float
    max_y: float
    ui_min: tuple[float, float]
    ui_max: tuple[float, float]


def _rows(path: Path, table: str) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise ClientDumpError(f"{path}: not JSON ({err})") from err
    if not isinstance(data, dict) or data.get("table") != table:
        raise ClientDumpError(f"{path}: expected a clientdump {table} dump")
    rows = data.get("rows")
    if not isinstance(rows, list):
        raise ClientDumpError(f"{path}: rows missing")
    return rows


def read_ui_maps(path: Path) -> dict[int, UiMapRow]:
    out: dict[int, UiMapRow] = {}
    for row in _rows(path, "UiMap"):
        ui_map_id = row.get("ID")
        if not isinstance(ui_map_id, int):
            raise ClientDumpError(f"{path}: a UiMap row has no integer ID: {row!r}")
        parent = row.get("ParentUiMapID")
        out[ui_map_id] = UiMapRow(
            ui_map_id,
            str(row.get("Name_lang") or ""),
            int(parent) if isinstance(parent, int) and parent > 0 else None,
            int(row.get("Type") or 0),
            int(row.get("System") or 0),
        )
    return out


def read_ui_map_assignments(path: Path) -> list[Assignment]:
    out: list[Assignment] = []
    for row in _rows(path, "UiMapAssignment"):
        region = row.get("Region")
        ui_min, ui_max = row.get("UiMin"), row.get("UiMax")
        if not (isinstance(region, list) and len(region) == 6 and ui_min and ui_max):
            raise ClientDumpError(f"{path}: assignment {row.get('ID')} lacks Region/UiMin/UiMax")
        out.append(
            Assignment(
                ui_map_id=int(row["UiMapID"]),
                map_id=int(row.get("MapID", -1)),
                min_x=float(region[0]),
                min_y=float(region[1]),
                max_x=float(region[3]),
                max_y=float(region[4]),
                ui_min=(float(ui_min[0]), float(ui_min[1])),
                ui_max=(float(ui_max[0]), float(ui_max[1])),
            )
        )
    return out


@dataclass(frozen=True)
class MapRow:
    """One Map.db2 row: a continent, instance, transport or test map."""

    id: int
    name: str
    directory: str  # the WDT folder (minimap tile lists are named after it)
    instance_type: int  # 0 = open world
    wdt_file_id: int | None


def read_maps(path: Path) -> dict[int, MapRow]:
    out: dict[int, MapRow] = {}
    for row in _rows(path, "Map"):
        map_id = row.get("ID")
        if not isinstance(map_id, int):
            raise ClientDumpError(f"{path}: a Map row has no integer ID: {row!r}")
        wdt = row.get("WdtFileDataID")
        out[map_id] = MapRow(
            map_id,
            str(row.get("MapName_lang") or ""),
            str(row.get("Directory") or ""),
            int(row.get("InstanceType") or 0),
            int(wdt) if isinstance(wdt, int) and wdt > 0 else None,
        )
    return out


def _regions(assignments: list[Assignment], ui_maps: dict[int, UiMapRow]):
    """Per continent or zone UiMap the region area it has on each map; from that, per map, the
    continent UiMaps at home there (largest region) and the zone UiMaps with a region."""
    regions: dict[int, dict[int, float]] = {}  # ui map id -> map id -> region area
    for a in assignments:
        ui = ui_maps.get(a.ui_map_id)
        if ui is None or ui.type not in (UI_MAP_CONTINENT, UI_MAP_ZONE):
            continue
        area = abs(a.max_x - a.min_x) * abs(a.max_y - a.min_y)
        per_map = regions.setdefault(a.ui_map_id, {})
        per_map[a.map_id] = per_map.get(a.map_id, 0.0) + area
    homes: dict[int, list[tuple[float, int]]] = {}  # map id -> (area, continent ui map) at home
    zones: dict[int, list[tuple[float, int]]] = {}  # map id -> (area, zone ui map)
    for ui_map_id, per_map in regions.items():
        home = max(per_map.items(), key=lambda kv: (kv[1], -kv[0]))[0]
        if ui_maps[ui_map_id].type == UI_MAP_CONTINENT:
            homes.setdefault(home, []).append((per_map[home], ui_map_id))
        for map_id, area in per_map.items():
            if ui_maps[ui_map_id].type == UI_MAP_ZONE:
                zones.setdefault(map_id, []).append((area, ui_map_id))
    return regions, homes, zones


def continent_homes(assignments: list[Assignment], ui_maps: dict[int, UiMapRow]) -> dict[int, int]:
    """Map.db2 id -> the continent UiMap at home on it with the largest region (Eastern Kingdoms
    1415 on map 0, Kalimdor 1414 on map 1): the UiMap whose art is the map's parchment
    (mapart_art)."""
    _, homes, zones = _regions(assignments, ui_maps)
    # the world map system first (retail 12.1: "Eastern Kingdoms" 2481 of system 2 and "Northrend"
    # 988 of system 1, a one-tile art, have larger regions than the world map's 13 and 113)
    out = {
        map_id: max(entries, key=lambda e: (ui_maps[e[1]].system == 0, e[0], -e[1]))[1]
        for map_id, entries in homes.items()
    }
    # a map without a continent UiMap (Zephras Isle on Forever, Deepholm on retail) takes the zone
    # UiMap with the largest region: its zone art is the parchment then
    for map_id, entries in zones.items():
        if map_id not in out:
            out[map_id] = max(entries, key=lambda e: (ui_maps[e[1]].system == 0, e[0], -e[1]))[1]
    return out


def home_transform(
    ui_map_id: int, map_id: int, assignments: list[Assignment], continents=None
) -> Transform | None:
    """The transform of a continent UiMap from its largest assignment on its home map (a continent
    has several assignments, which `transform_table` skips): where the map art sits in world
    yards."""
    best = None
    for a in assignments:
        if a.ui_map_id != ui_map_id or a.map_id != map_id:
            continue
        area = abs(a.max_x - a.min_x) * abs(a.max_y - a.min_y)
        if best is None or area > best[0]:
            best = (area, a)
    return transform_of(best[1], continents) if best else None


def world_continents(
    maps: dict[int, MapRow], assignments: list[Assignment], ui_maps: dict[int, UiMapRow]
) -> dict[int, str]:
    """Map.db2 id -> name for every open-world map with a zone or continent UiMap assigned: the
    continents of Map and Route. A continent UiMap is at home on the map holding its largest
    region (Kalimdor's map also reaches onto 530 for the Exodar isles, Eastern Kingdoms' onto Tol
    Barad). The name is that of the largest continent UiMap at home on the map (Outland on 530),
    else the zone with the largest region (Deepholm, The Lost Isles, Tol Barad Peninsula), else the
    map's own."""
    regions, homes, zones = _regions(assignments, ui_maps)
    out: dict[int, str] = {}
    world = {m for per_map in regions.values() for m in per_map}
    for map_id in sorted(world):
        row = maps.get(map_id)
        if row is None or row.instance_type != WORLD_INSTANCE_TYPE:
            continue
        name = None
        if homes.get(map_id):
            name = ui_maps[max(homes[map_id])[1]].name
        elif zones.get(map_id):
            name = ui_maps[max(zones[map_id])[1]].name
        out[map_id] = name or row.name or str(map_id)
    return out


def transform_of(a: Assignment, continents=None) -> Transform | None:
    """The affine transform of one assignment (coordinates.md), or None for an instance."""
    allowed = continents if continents is not None else MAP_CONTINENT
    continent = a.map_id if a.map_id in allowed else None
    span_x, span_y = a.ui_max[0] - a.ui_min[0], a.ui_max[1] - a.ui_min[1]
    if continent is None or span_x <= 0 or span_y <= 0:
        return None
    if a.max_x <= a.min_x or a.max_y <= a.min_y:
        return None
    # map fraction x (east) runs along falling world Y, map fraction y (south) along falling world X
    wx_dy = -(a.max_x - a.min_x) / span_y
    wy_dx = -(a.max_y - a.min_y) / span_x
    wx0 = a.max_x - a.ui_min[1] * wx_dy
    wy0 = a.max_y - a.ui_min[0] * wy_dx
    return Transform(
        a.ui_map_id,
        continent,
        round(wx0, 4),
        0.0,
        round(wx_dy, 4),
        round(wy0, 4),
        round(wy_dx, 4),
        0.0,
        True,
    )


NOTE_IDS = 10  # how many multi-assignment map ids one note lists before "..."


def transform_table(
    assignments: list[Assignment], continents=None
) -> tuple[dict[int, Transform], list[str]]:
    """uiMapID -> Transform for every world map with exactly one assignment; plus the notes.

    `continents` is the set of Map.db2 ids that count as world (`world_continents`); without it
    only the two Azeroth continents do. Maps with several assignments (dungeon floors, cities with
    WMO groups, micro maps; 1178 on retail 12.1.5, one on the Forever beta) get no transform and
    one summary note, not a line each."""
    by_map: dict[int, list[Assignment]] = {}
    for a in assignments:
        by_map.setdefault(a.ui_map_id, []).append(a)
    out: dict[int, Transform] = {}
    multi: list[str] = []
    for ui_map_id, rows in sorted(by_map.items()):
        if len(rows) > 1:
            multi.append(f"{ui_map_id} ({len(rows)})")
            continue
        t = transform_of(rows[0], continents)
        if t is not None:
            out[ui_map_id] = t
    notes: list[str] = []
    if multi:
        shown = ", ".join(multi[:NOTE_IDS]) + (", ..." if len(multi) > NOTE_IDS else "")
        notes.append(
            f"{len(multi)} uiMap(s) with several assignments, no single transform: {shown}"
        )
    return out, notes


def map_parents(
    ui_maps: dict[int, UiMapRow], transforms: dict[int, Transform]
) -> dict[int, tuple[int | None, int | None]]:
    """uiMapID -> (parent, continent) as `canon.merge_zones` wants it."""
    out = {}
    for ui_map_id, row in ui_maps.items():
        t = transforms.get(ui_map_id)
        continent = t.continent if t else None
        if continent is None and row.parent in transforms:
            continent = transforms[row.parent].continent
        out[ui_map_id] = (row.parent, continent)
    return out


def read_quest_titles(path: Path) -> dict[int, str]:
    """clientdump QuestV2CliTask -> quest id -> title (``QuestTitle_lang``), empty titles skipped.

    The retail client has no table with the titles of ordinary quests (they arrive from the server;
    measured 22.10.2026 on 12.1.5.70448: QuestV2 carries no text column and no other DB2 table
    holds quest titles); this client-task table names 6,257 quests, mostly WANTED posters and
    later-expansion tasks. The rest stay runtime names (data.md "Retail data")."""
    out: dict[int, str] = {}
    for row in _rows(path, "QuestV2CliTask"):
        quest_id = row.get("ID")
        title = row.get("QuestTitle_lang")
        if isinstance(quest_id, int) and isinstance(title, str) and title.strip():
            out[quest_id] = title.strip()
    return out
