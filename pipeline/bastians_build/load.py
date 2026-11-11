"""Load every available source for a client into `canon.Sources` (the pipeline's `load` stage)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from bastians_build.areas import AreasError, read_navmesh_dir
from bastians_build.canon import PROFESSION_SKILL_LINES, Sources
from bastians_build.sources import (
    client_tables,
    clientdump,
    cmangos,
    foreverdb,
    foreverdb_api,
    probe,
    questie,
    questiedb,
    questiedb_store,
    tdb,
)
from bastians_build.sources.allthethings import read_allthethings
from bastians_build.sources.everything_quests import read_everything_quests
from bastians_build.sources.itemdb import read_itemdb

# AllTheThings and ItemDB flavors per client; read for retail only (data.md "Retail data"): on
# Forever, Everything Quests already carries ATT's quest data and ForeverDB the item names.
ATT_FLAVOR = {"retail": "Standard"}
ITEMDB_FLAVOR = {"retail": "Retail"}


@dataclass(frozen=True)
class SourcePaths:
    addons: Path | None = None  # WoW Interface/AddOns folder with the source addons
    cmangos: Path | None = None  # CMaNGOS classic-db checkout or its Full_DB/*.sql.gz
    probe: Path | None = None  # a Bastians_Probe dump (data/probe/*.lua)
    # ForeverDB's Dungeons.lua for a client whose AddOns lack it: the retail test client shows
    # Forever's dungeons
    dungeons: Path | None = None
    taxi: Path | None = None  # a clientdump TaxiNodes JSON (client-extraction.md)
    dumps: Path | None = (
        None  # folder with <prefix>_UiMap.json, _UiMapAssignment.json, _TaxiNodes.json
    )
    dump_prefix: str = "beta"
    everything_quests_flavor: str = "Forever"
    # TrinityCore's retail world database, TDB_full_world_*.sql (sources.md); its FactionTemplate
    # and ContentTuning come from the dumps folder (<prefix>_FactionTemplate.json, ...)
    tdb: Path | None = None
    # the navmesh folder (`clientdump navmesh`, <Map>.navmesh): the subzones' places (data.md
    # "Areas"); default <dumps>/navmesh_<client>
    navmesh: Path | None = None
    # the dungeon floors' map art (DG2c): the folder with retail's <floor_art_prefix>_UiMap.json,
    # _UiMapAssignment.json, _UiMapXMapArt.json and _UiMapArtTile.json (both clients read the
    # retail tables: the Forever client has no dungeon UiMaps), and the community listfile
    # that names the tiles for the Forever client
    floor_art: Path | None = None
    floor_art_prefix: str = "retail"
    listfile: Path | None = None
    # ForeverDB's API rows as AHSync stored them (quests.json, vendors.json; Forever only):
    # places players saw, for gaps (sources/foreverdb_api.py)
    foreverdb_api: Path | None = None


def load_areas(s: Sources, client: str, paths: SourcePaths) -> None:
    """The navmesh files' area blocks and the client's AreaTable, when both exist (data.md
    "Areas"); otherwise `s.areas_note` says what was missing."""
    assert paths.dumps is not None
    folder = paths.navmesh or paths.dumps / f"navmesh_{client}"
    table_path = next(
        (
            p
            for p in (paths.dumps / f"{x}_AreaTable.json" for x in (paths.dump_prefix, client))
            if p.is_file()
        ),
        None,
    )
    files = sorted(folder.glob("*.navmesh")) if folder.is_dir() else []
    if not files:
        s.areas_note = f"areas: no navmesh files in {folder}, no areas"
        return
    if table_path is None:
        s.areas_note = f"areas: no {paths.dump_prefix}_AreaTable.json in {paths.dumps}, no areas"
        return
    try:
        s.area_blocks = read_navmesh_dir(folder)
    except (AreasError, OSError) as err:
        s.areas_note = f"areas: {err}, no areas"
        return
    s.area_table = clientdump.read_area_table(table_path)
    builds = sorted({b.build for b in s.area_blocks})
    s.source_names.append(f"clientdump navmesh area blocks {', '.join(builds)}")
    s.source_names.append(f"clientdump AreaTable ({table_path.name.split('_')[0]})")


def find_dump(cmangos_dir: Path) -> Path:
    if cmangos_dir.is_file():
        return cmangos_dir
    dumps = sorted((cmangos_dir / "Full_DB").glob("*.sql.gz"))
    if not dumps:
        raise FileNotFoundError(f"no Full_DB/*.sql.gz under {cmangos_dir}")
    return dumps[-1]


def load_sources(client: str, paths: SourcePaths, *, eq_spawns: bool = True) -> Sources:
    s = Sources(client=client)
    if paths.probe and paths.probe.is_file():
        dump = probe.read_probe_dump(paths.probe)
        s.transforms = probe.transform_table(dump)
        s.transforms_source = f"probe {paths.probe.name}"
        s.map_names = probe.map_names(dump)
        s.map_types = probe.map_types(dump)
        s.map_parents = {
            m: (e.get("parent"), s.transforms[m].continent if m in s.transforms else None)
            for m, e in dump.maps.items()
            if isinstance(e, dict)
        }
        s.build = dump.build or s.build
        s.source_names.append(f"probe {paths.probe.name}")
    if paths.dumps:
        prefix = paths.dump_prefix
        ui_map_path = paths.dumps / f"{prefix}_UiMap.json"
        assign_path = paths.dumps / f"{prefix}_UiMapAssignment.json"
        if ui_map_path.is_file() and assign_path.is_file():
            ui_maps = clientdump.read_ui_maps(ui_map_path)
            assignments = clientdump.read_ui_map_assignments(assign_path)
            for a in assignments:
                if a.area_id and a.ui_map_id not in s.area_maps.get(a.area_id, []):
                    s.area_maps.setdefault(a.area_id, []).append(a.ui_map_id)
            for maps in s.area_maps.values():
                maps.sort()
            maps_path = paths.dumps / f"{prefix}_Map.json"
            if maps_path.is_file():  # every world map is a continent (coordinates.md)
                s.continents = clientdump.world_continents(
                    clientdump.read_maps(maps_path), assignments, ui_maps
                )
                s.source_names.append(f"clientdump Map ({prefix})")
            table, notes = clientdump.transform_table(assignments, s.continents or None)
            if not s.transforms:  # a probe dump (measured in game) wins over the client's table
                s.transforms = table
                s.transforms_source = f"client UiMapAssignment ({prefix})"
            if not s.map_names:
                s.map_names = {m: r.name for m, r in ui_maps.items() if r.name}
                s.map_parents = clientdump.map_parents(ui_maps, s.transforms)
            if not s.map_types:
                s.map_types = {m: r.type for m, r in ui_maps.items()}
            s.notes.extend(notes)
            s.source_names.append(f"clientdump UiMap ({prefix})")
        taxi_paths = paths.dumps / f"{prefix}_TaxiPath.json"
        taxi_points = paths.dumps / f"{prefix}_TaxiPathNode.json"
        if taxi_paths.is_file() and taxi_points.is_file():  # the travel level (ADR 0026, W4)
            s.taxi_paths = clientdump.read_taxi_paths(taxi_paths, taxi_points)
            s.source_names.append(f"clientdump TaxiPath ({prefix})")
        taxi_path = paths.dumps / f"{prefix}_TaxiNodes.json"
        if paths.taxi is None and taxi_path.is_file():
            paths = SourcePaths(**{**paths.__dict__, "taxi": taxi_path})
        retail_maps = paths.dumps / "retail_UiMap.json"
        if prefix != "retail" and retail_maps.is_file():
            # names and types of maps this client lacks (its dungeons: the ids are shared)
            others = clientdump.read_ui_maps(retail_maps)
            s.fallback_map_names = {m: r.name for m, r in others.items() if r.name}
            s.fallback_map_types = {m: r.type for m, r in others.items()}
            s.source_names.append("clientdump UiMap (retail, for maps this client lacks)")
        load_areas(s, client, paths)
        titles_path = paths.dumps / f"{prefix}_QuestV2CliTask.json"
        if titles_path.is_file():  # retail: the client tasks' titles (D1, data.md "Retail data")
            s.quest_titles = clientdump.read_quest_titles(titles_path)
            s.source_names.append(f"clientdump QuestV2CliTask ({prefix})")
        # the client's data tables (ADR 0035): items, recipes, quest chains and areas
        tables = client_tables.read_client_tables(paths.dumps, client, set(PROFESSION_SKILL_LINES))
        if tables is not None:
            s.client_tables = tables
            s.source_names.extend(tables.sources)
    if paths.taxi and paths.taxi.is_file():
        dump = clientdump.read_taxi_nodes(paths.taxi, s.continents or None)
        s.taxi = dump.nodes
        s.source_names.append(f"clientdump TaxiNodes {dump.build or '?'}")
        if s.build == "unknown" and dump.build:
            s.build = dump.build
    if paths.addons:
        eq_dir = paths.addons / "EverythingQuests"
        if eq_dir.is_dir():
            s.eq = read_everything_quests(eq_dir, paths.everything_quests_flavor, spawns=eq_spawns)
            s.source_names.append(f"Everything Quests {s.eq.version or '?'}")
        fdb = paths.addons / "ForeverDB" / "Data"
        if fdb.is_dir():
            meta = foreverdb.read_meta(fdb / "Meta.lua") if (fdb / "Meta.lua").is_file() else None
            s.fdb_npcs = foreverdb.read_npcs(fdb / "NPCs.lua")
            s.fdb_recipes = foreverdb.read_recipes(fdb / "Recipes.lua")
            s.fdb_gather = foreverdb.read_gather(fdb / "Gather.lua")
            s.fdb_quests = foreverdb.read_quests(fdb / "QuestForever.lua")
            s.fdb_items = foreverdb.read_items(fdb / "Items.lua")
            s.fdb_names = foreverdb.read_search_names(fdb / "SearchNames.lua")
            s.fdb_seen = foreverdb.read_quest_seen(fdb / "QuestForever.lua")
            s.fdb_npc_names = foreverdb.read_npc_names(fdb / "QuestForever.lua")
            s.fdb_triggers = foreverdb.read_triggers(fdb / "QuestForever.lua")
            s.fdb_sold = foreverdb.read_sold(fdb / "NPCs.lua")
            s.fdb_trainers = foreverdb.read_trainers(fdb / "NPCs.lua")
            if (fdb / "QuestXP.lua").is_file():
                s.fdb_xp = foreverdb.read_quest_xp(fdb / "QuestXP.lua")
            if (fdb / "QuestGuide.lua").is_file():
                s.fdb_guide = foreverdb.read_quest_guide(fdb / "QuestGuide.lua")
            if (fdb / "Dungeons.lua").is_file():  # since ForeverDB 0.44 (data.md "Dungeons")
                s.fdb_dungeons = foreverdb.read_dungeons(fdb / "Dungeons.lua")
            if (fdb / "DungeonMaps.lua").is_file():  # the floors (DG2)
                s.fdb_dungeon_maps = foreverdb.read_dungeon_maps(fdb / "DungeonMaps.lua")
            if (fdb / "Loot.lua").is_file():  # the bosses' creatures (02.11.2026)
                s.fdb_boss_creatures = foreverdb.read_boss_creatures(fdb / "Loot.lua")
            s.source_names.append(f"ForeverDB {meta.addon if meta and meta.addon else '?'}")
            if s.build == "unknown" and meta and meta.build:
                s.build = str(meta.build)  # the client build ForeverDB read its data from
        toc = paths.addons / "QuestieDB" / "QuestieDB_Forever.toc"
        if client == "forever" and toc.is_file():
            s.questie = questiedb_store.read_store(toc)
            s.source_names.append(f"QuestieDB store ({len(s.questie.npcs)} NPCs)")
        zones = paths.addons / "QuestieDB" / "support" / "Forever" / "Zones" / "areaIdToUiMapId.lua"
        if zones.is_file():
            table = questiedb.read_area_to_ui_map_file(zones)
            s.area_to_map = {a: m for a, m in table.mapping.items() if m}
            s.source_names.append(f"QuestieDB zones {table.source_build or '?'}")
        questie_dir = paths.addons / "Questie"
        if client == "forever" and (questie_dir / questie.BLACKLIST).is_file():
            s.questie_gates = questie.read_quest_gates(questie_dir)
            s.source_names.append(f"Questie {s.questie_gates.version or '?'}")
        att_dir = paths.addons / "AllTheThings"
        if client in ATT_FLAVOR and (att_dir / "db" / ATT_FLAVOR[client]).is_dir():
            s.att = read_allthethings(att_dir, ATT_FLAVOR[client])
            s.source_names.append(f"AllTheThings {s.att.version or '?'} ({s.att.flavor})")
        idb_dir = paths.addons / "ItemDB"
        if client in ITEMDB_FLAVOR and (idb_dir / "Data" / ITEMDB_FLAVOR[client]).is_dir():
            s.idb = read_itemdb(idb_dir, ITEMDB_FLAVOR[client])
            s.source_names.append(f"ItemDB {s.idb.version or '?'} ({s.idb.flavor})")
            if s.build == "unknown" and s.idb.build:
                s.build = s.idb.build
    if client == "forever" and paths.foreverdb_api and paths.foreverdb_api.is_dir():
        s.fdb_api = foreverdb_api.read_api(paths.foreverdb_api)
        s.source_names.append(
            f"ForeverDB API ({len(s.fdb_api.quest_places)} seen quest places, "
            f"{len(s.fdb_api.vendors)} seen vendors)"
        )
    if not s.fdb_dungeons and paths.dungeons and paths.dungeons.is_file():
        s.fdb_dungeons = foreverdb.read_dungeons(paths.dungeons)
        s.source_names.append(
            "ForeverDB Dungeons.lua (Forever's dungeons, for tests on this client)"
        )
        loot = paths.dungeons.with_name("Loot.lua")
        if loot.is_file():
            s.fdb_boss_creatures = foreverdb.read_boss_creatures(loot)
        maps = paths.dungeons.with_name("DungeonMaps.lua")
        if maps.is_file():
            s.fdb_dungeon_maps = foreverdb.read_dungeon_maps(maps)
    if paths.floor_art and s.fdb_dungeon_maps:
        s.floor_art = clientdump.read_floor_art(
            paths.floor_art, paths.floor_art_prefix, paths.listfile
        )
        s.source_names.append(
            f"clientdump UiMap dungeon floors ({paths.floor_art_prefix}"
            f"{', listfile' if paths.listfile else ''})"
        )
    if paths.cmangos:
        dump_path = find_dump(paths.cmangos)
        tables = cmangos.read_tables(dump_path)
        s.cm_quests = cmangos.quest_rows(tables)
        s.cm_creatures = tables.get("creature_template", [])
        s.cm_objects = tables.get("gameobject_template", [])
        s.cm_spawns = cmangos.spawn_rows(tables)
        s.cm_vendors = cmangos.vendor_rows(tables)
        s.cm_trainers = cmangos.trainer_services(tables)
        s.cm_loot = cmangos.loot_rows(tables)
        s.cm_items = cmangos.item_rows(tables)
        s.cm_disenchant = cmangos.disenchant_lists(tables)
        s.cm_links = cmangos.links(tables)
        s.cm_spell_names = {
            int(r["Id"]): str(r["SpellName"])
            for r in tables.get("spell_template", [])
            if r.get("SpellName")
        }
        s.source_names.append(f"CMaNGOS classic-db {dump_path.name}")
        if paths.dumps:
            # the build's own prefix first, else the client's (the Forever beta is gone: its tables
            # come from the launch client as forever_*.json, 26.10.2026)
            for prefix in (paths.dump_prefix, client):
                factions = paths.dumps / f"{prefix}_FactionTemplate.json"
                if factions.is_file():
                    s.cm_factions = tdb.faction_sides(tdb.table_rows(factions))
                    s.source_names.append(f"clientdump FactionTemplate ({prefix})")
                    break
    if paths.tdb:
        if not paths.dumps:
            raise FileNotFoundError("--tdb needs --dumps (FactionTemplate and ContentTuning)")
        prefix = paths.dump_prefix
        s.tdb = tdb.read_tdb(
            paths.tdb,
            paths.dumps / f"{prefix}_FactionTemplate.json",
            paths.dumps / f"{prefix}_ContentTuning.json",
        )
        s.source_names.append(f"TrinityCore {s.tdb.name}")
    return s
