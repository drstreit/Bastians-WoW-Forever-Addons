"""Load every available source for a client into `canon.Sources` (the pipeline's `load` stage)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from bastians_build.canon import Sources
from bastians_build.sources import clientdump, cmangos, foreverdb, probe, questiedb
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
    taxi: Path | None = None  # a clientdump TaxiNodes JSON (client-extraction.md)
    dumps: Path | None = (
        None  # folder with <prefix>_UiMap.json, _UiMapAssignment.json, _TaxiNodes.json
    )
    dump_prefix: str = "beta"
    everything_quests_flavor: str = "Forever"


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
        titles_path = paths.dumps / f"{prefix}_QuestV2CliTask.json"
        if titles_path.is_file():  # retail: the client tasks' titles (D1, data.md "Retail data")
            s.quest_titles = clientdump.read_quest_titles(titles_path)
            s.source_names.append(f"clientdump QuestV2CliTask ({prefix})")
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
            s.source_names.append(f"ForeverDB {meta.addon if meta and meta.addon else '?'}")
            if s.build == "unknown" and meta and meta.build:
                s.build = str(meta.build)  # the client build ForeverDB read its data from
        zones = paths.addons / "QuestieDB" / "support" / "Forever" / "Zones" / "areaIdToUiMapId.lua"
        if zones.is_file():
            table = questiedb.read_area_to_ui_map_file(zones)
            s.area_to_map = {a: m for a, m in table.mapping.items() if m}
            s.source_names.append(f"QuestieDB zones {table.source_build or '?'}")
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
        s.cm_spell_names = {
            int(r["Id"]): str(r["SpellName"])
            for r in tables.get("spell_template", [])
            if r.get("SpellName")
        }
        s.source_names.append(f"CMaNGOS classic-db {dump_path.name}")
    return s
