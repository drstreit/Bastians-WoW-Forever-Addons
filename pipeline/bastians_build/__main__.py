"""Entry point: python -m bastians_build <command> (pipeline.md).

data   --client forever|retail [--addons <AddOns>] [--cmangos <dir>] [--probe <dump>]
       (a probe dump also feeds the "Probe ground truth" report section: P4 landmarks and P7 taxi
       maps against the transforms, taxi nodes against the flight masters, the quest log, flights)
       [--taxi <TaxiNodes.json>] [--transports <toml>]
       [--dumps <folder> [--dump-prefix beta]]  clientdump UiMap/UiMapAssignment/TaxiNodes:
                                             map transform table from the client (no probe dump)
       [--navmesh <folder>]                  the subzones from the navmesh area blocks and the
                                             dumps' AreaTable (default <dumps>/navmesh_<client>)
       builds the data packs, plus Bastians_Data/Generated/MapTransforms.lua from a probe dump
data   --client forever --fixture <dir>      the same from the hand-written fixture world (tests)
       [--export <dir>]                      plus Bastians_Data_Market from an AHSync export (B10.2)
       [--book <dir>]                        plus the Strategies book (Bastians_Data_Strategies),
                                             the claims from the export; default content/strategies
                                             (not for --fixture builds)
       [--book-previous <json>] [--book-state <json>]
                                             the book's state of the last sent edition: What's
                                             new entries for what changed since (book_news.py);
                                             this build's state goes to --book-state (default
                                             <report-dir>/book-state.json)
       [--ground-truth <csv>]              measured NPC places checked, report section (B3.8)
check  ...                                   validate only, no output
mapart --client forever|retail --tiles <dir> [--overview <dir>] [--maps <Map.json>] [--out addons]
       Bastians_Map/Generated/MinimapTiles.lua from the clientdump tile lists (<Map>_tiles.txt);
       with --overview the stitched cells (<Map>_overview.json, clientdump overview) go into
       Bastians_Map_Art/Generated/ (Tiles/*.blp and Overview.lua)
nav                                          later backlog item (B9)
tales  <slug>... | --all [--source content/tales] [--out addons]
       compiles each tale into its addon and refuses it with every problem (library.md 8.1)
tales  --catalogue [--check]                 Bastians_Library/Catalogue.lua from
                                             pipeline/config/tales_catalogue.toml
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from bastians_build import __version__
from bastians_build.attunements import AttunementError, add_attunements
from bastians_build.book import CONTENT_DIR, BookError, add_book
from bastians_build.book_news import BookNewsError, add_generated_news, read_state, write_state
from bastians_build.build import build
from bastians_build.candidates import candidates, write_report
from bastians_build.canon import build_world
from bastians_build.config import CLIENTS, CONFIG_DIR, ConfigError, load_config
from bastians_build.corrections import (
    apply_corrections,
    captured_links,
    captured_ride_waits,
    captured_taxi_times,
    read_corrections,
)
from bastians_build.dungeon_art import DungeonArtError, add_dungeon_art
from bastians_build.emit import emit_pack
from bastians_build.files import write_text
from bastians_build.groundtruth import GroundTruthError, compare, read_truth, summary
from bastians_build.l10n import add_l10n
from bastians_build.load import SourcePaths, load_sources
from bastians_build.mapart import (
    MapArtError,
    build_tiles,
    directories_from_maps,
    refuse_fixture_into_addons,
    sea_tiles,
)
from bastians_build.market import add_market
from bastians_build.mill import add_mill
from bastians_build.nav import (
    NavError,
    emit_nav,
    load_links,
    nav_nodes,
    nav_pack,
    read_graphs,
    stub,
)
from bastians_build.navnet import (
    NavnetError,
    danger_points,
    graph_records,
    read_levels,
    read_taxi_rows,
    taxi_rows,
    tdb_danger,
)
from bastians_build.overview import install_overview
from bastians_build.places import PlacesError, add_entrances, add_teleports, read_places
from bastians_build.probetruth import check_probe
from bastians_build.quest_places import add_quest_places, read_quest_places
from bastians_build.sources import client_tables
from bastians_build.sources.ahsync_export import ExportError, read_export
from bastians_build.sources.clientdump import ClientDumpError
from bastians_build.sources.fixture import FixtureError, read_fixture
from bastians_build.sources.probe import read_probe_dump, transform_table
from bastians_build.themes import OUT as THEMES_OUT
from bastians_build.themes import ThemeError, build_themes
from bastians_build.transports import TransportError, add_transports, read_transports


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="bastians_build", description=f"bastians_build {__version__}"
    )
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("data", "check", "all"):
        p = sub.add_parser(name)
        p.add_argument("--client", required=True, choices=CLIENTS)
        p.add_argument("--fixture", type=Path, help="hand-written fixture world folder (*.toml)")
        p.add_argument(
            "--addons", type=Path, help="WoW Interface/AddOns folder with the source addons"
        )
        p.add_argument("--cmangos", type=Path, help="CMaNGOS classic-db checkout or Full_DB dump")
        p.add_argument("--probe", type=Path, help="Bastians_Probe dump (data/probe/*.lua)")
        p.add_argument(
            "--dungeons",
            type=Path,
            help="ForeverDB's Dungeons.lua for a client whose AddOns lack it (retail tests)",
        )
        p.add_argument(
            "--foreverdb-api",
            type=Path,
            help="ForeverDB's API rows as AHSync stored them (quests.json, vendors.json): places "
            "players saw in Forever, for gaps only (data.md)",
        )
        p.add_argument(
            "--floor-art",
            type=Path,
            help="folder with retail's <prefix>_UiMap/_UiMapAssignment/_UiMapXMapArt/_UiMapArtTile"
            " JSON: the dungeon floors' maps (data.md Dungeons)",
        )
        p.add_argument("--floor-art-prefix", default="retail", help="their prefix (default retail)")
        p.add_argument(
            "--listfile", type=Path, help="the community listfile naming the floors' tiles"
        )
        p.add_argument(
            "--taxi", type=Path, help="clientdump TaxiNodes JSON (flight masters, route.md)"
        )
        p.add_argument(
            "--dumps",
            type=Path,
            help="folder with clientdump JSON (<prefix>_UiMap, _UiMapAssignment, _TaxiNodes)",
        )
        p.add_argument(
            "--dump-prefix", default="beta", help="file prefix in --dumps (default beta)"
        )
        p.add_argument(
            "--navmesh",
            type=Path,
            help='folder with clientdump\'s <Map>.navmesh files: the subzones (data.md "Areas"; '
            "default <dumps>/navmesh_<client>, needs --dumps for the AreaTable)",
        )
        p.add_argument(
            "--ground-truth",
            type=Path,
            help="measured NPC places CSV (data/ground-truth/*.csv) checked against the world",
        )
        p.add_argument(
            "--export",
            type=Path,
            help="AHSync market export root (reads LATEST) or one dated folder (ahsync-export.md)",
        )
        p.add_argument(
            "--book",
            type=Path,
            help="Strategies book content (default: content/strategies when it exists and the "
            "build is not a fixture; needs --export)",
        )
        p.add_argument(
            "--book-previous",
            type=Path,
            help="the book state of the last sent edition: the build writes What's new entries "
            "for what changed since (tools/data_update.py passes it)",
        )
        p.add_argument(
            "--book-state",
            type=Path,
            help="where this build's book state goes (default: <report-dir>/book-state.json)",
        )
        p.add_argument(
            "--art",
            type=Path,
            help="the book's pictures, <page id>.jpg (default: the export's art/ folder; "
            "tools/data_update.py passes the folder it installs the textures from)",
        )
        p.add_argument(
            "--transports",
            type=Path,
            help="a TOML with [[transport]] rows (default: the places table, "
            "pipeline/config/places_<client>.toml; "
            "the fixture world carries its own)",
        )
        p.add_argument(
            "--tdb",
            type=Path,
            help="TrinityCore's retail world dump TDB_full_world_*.sql (sources.md; needs --dumps "
            "with the client's FactionTemplate and ContentTuning)",
        )
        p.add_argument(
            "--tdb-texts",
            type=Path,
            help="Forever: TDB's world dump for the long quest texts in Korean and Chinese, taken "
            'where its English is ours (data.md "Game data in other languages")',
        )
        p.add_argument(
            "--places",
            type=Path,
            help="our places table (default: pipeline/config/places_<client>.toml; ADR 0026)",
        )
        p.add_argument(
            "--quest-places",
            type=Path,
            help="our authored quest places (default: pipeline/config/quest_places_<client>.toml; "
            "ADR 0070): where a quest's step is done, before every source",
        )
        p.add_argument(
            "--no-eq-spawns", action="store_true", help="skip Everything Quests objective spots"
        )
        p.add_argument(
            "--l10n",
            type=Path,
            help="QuestieDB's l10n lookups, <locale>/lookup*.lua (tools/fetch_questie_l10n.py): "
            'the packs text_deDE, text_frFR, text_esES (data.md "Game data in other languages")',
        )
        p.add_argument(
            "--out", type=Path, default=Path("addons"), help="output root (default: addons)"
        )
        p.add_argument(
            "--config", type=Path, help="build.toml (default: pipeline/config/build.toml)"
        )
        p.add_argument(
            "--attunements",
            type=Path,
            help="attunements TOML (default: pipeline/config/attunements_<client>.toml; "
            "the fixture world carries its own)",
        )
        p.add_argument(
            "--dungeon-art",
            type=Path,
            help="hand-drawn dungeon maps TOML (default: pipeline/config/dungeon_art.toml)",
        )
        p.add_argument(
            "--report-dir",
            type=Path,
            default=Path("build"),
            help="where report.md goes (default: build)",
        )
    p = sub.add_parser("mapart")
    p.add_argument("--client", required=True, choices=CLIENTS)
    p.add_argument(
        "--tiles", type=Path, required=True, help="folder with the clientdump <Map>_tiles.txt lists"
    )
    p.add_argument("--out", type=Path, default=Path("addons"), help="output root (default: addons)")
    p.add_argument(
        "--maps",
        type=Path,
        help="clientdump Map JSON: maps every tile list's directory to its continent "
        "(without it only Azeroth and Kalimdor are known)",
    )
    p.add_argument(
        "--overview",
        type=Path,
        help="folder with clientdump overview output (<Map>_overview.json and the cell textures) "
        "for Bastians_Map_Art",
    )
    p = sub.add_parser("nav", help="the walk network pack from tools/nav_build.py's graphs")
    p.add_argument("--client", required=True, choices=CLIENTS)
    p.add_argument(
        "--graphs",
        type=Path,
        help="folder with <continent>.json and meta.json (default: .local/out/nav_<client>); "
        "without graphs Nav.lua is a stub",
    )
    p.add_argument(
        "--nodes",
        type=Path,
        help="the data build's nodes (default: build/nav-nodes-<client>.json)",
    )
    p.add_argument(
        "--links", type=Path, help="connectors (default: pipeline/config/nav_<client>.toml)"
    )
    p.add_argument(
        "--navnet",
        type=Path,
        help="folder with the local levels <continent>.json of clientdump navnet "
        "(default: .local/out/navnet_<client>; ADR 0026)",
    )
    p.add_argument(
        "--corrections",
        type=Path,
        help="what the mesh gets wrong: lifts, links, forbidden ground "
        "(default: pipeline/config/nav_corrections_<client>.toml)",
    )
    p.add_argument(
        "--captures",
        type=Path,
        help="the players' captured walks (tools/capture_import.py; "
        "default: data/captures/<client>)",
    )
    p.add_argument(
        "--agree", type=int, default=2, help="captures that must hold a walk for it to be a link"
    )
    p.add_argument("--out", type=Path, default=Path("addons"), help="output root (default: addons)")
    p = sub.add_parser("themes", help="compile the theme TOML files into Core's Themes.lua")
    p.add_argument("--check", action="store_true", help="exit 1 when Themes.lua is not current")
    p = sub.add_parser("tales", help="compile the Library's tales or its catalogue (library.md 8)")
    p.add_argument("slugs", nargs="*", help="tale folders under --source")
    p.add_argument("--all", action="store_true", help="every tale under --source")
    p.add_argument("--source", type=Path, help="default content/tales")
    p.add_argument("--out", type=Path, default=Path("addons"), help="output root (default: addons)")
    p.add_argument("--catalogue", action="store_true", help="compile Catalogue.lua instead")
    p.add_argument("--check", action="store_true", help="with --catalogue: exit 1 when not current")
    return parser


def run_tales(args: argparse.Namespace) -> int:
    # the Library's compiler loads only for its command: the public snapshot has no Library
    #
    from bastians_build.tales import (
        CATALOGUE_LUA,
        CONTENT_DIR,
        TaleError,
        build_catalogue,
        build_tale,
        tale_folders,
    )
    from bastians_build.tales import advice as tale_advice

    args.source = args.source or CONTENT_DIR
    if args.catalogue:
        current = build_catalogue(check=args.check)
        if args.check:
            print(f"{'current' if current else 'differs'}: {CATALOGUE_LUA}")
            return 0 if current else 1
        print(f"written: {CATALOGUE_LUA}")
        return 0
    folders = tale_folders(args.source) if args.all else [args.source / s for s in args.slugs]
    if not folders:
        print("error: name a tale or pass --all", file=sys.stderr)
        return 2
    failed = 0
    for folder in folders:
        try:
            print(f"written: {build_tale(folder, args.out)}")
            for path, message in tale_advice(folder):
                print(f"advice: {folder.name}: {path}: {message}")
        except (TaleError, OSError) as err:
            print(f"error: {err}", file=sys.stderr)
            failed += 1
    return 2 if failed else 0


def run_themes(args: argparse.Namespace) -> int:
    try:
        current = build_themes(check=args.check)
    except (ThemeError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    if args.check:
        print(f"{'current' if current else 'differs'}: {THEMES_OUT}")
        return 0 if current else 1
    print(f"written: {THEMES_OUT}")
    return 0


def run_mapart(args: argparse.Namespace) -> int:
    try:
        skip = sea_tiles(args.overview, load_config().mapart.skip_sea) if args.overview else {}
        path, changed, counts = build_tiles(
            args.client, args.tiles, args.out, maps_json=args.maps, skip=skip
        )
        for continent, n in sorted(counts.items()):
            print(f"continent {continent}: {n} tiles")
        if skip:
            print(f"all-sea tiles left out: {sum(len(v) for v in skip.values())}")
        print(f"{'written' if changed else 'unchanged'}: {path}")
        if args.overview:
            config = load_config()
            build = None
            if args.maps:
                import json

                build = json.loads(args.maps.read_text(encoding="utf-8")).get("build")
            refuse_fixture_into_addons(args.overview, args.out, "overview cells")
            result = install_overview(
                args.client,
                args.overview,
                args.out,
                config.mapart,
                directories=directories_from_maps(args.maps) if args.maps else None,
                build=build,
            )
    except (MapArtError, ConfigError, ClientDumpError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    if args.overview:
        for continent, n in sorted(result.counts.items()):
            print(f"continent {continent}: {n} overview cells")
        budget = f" of {result.budget_kb / 1024:.0f} MB budget" if result.budget_kb else ""
        over = " OVER BUDGET" if result.over_budget else ""
        print(
            f"overview textures: {result.size / 1024 / 1024:.1f} MB{budget}{over}, "
            f"{result.copied} copied, {result.removed} stale removed, {result.masks} coast masks"
        )
        print(f"{'written' if result.changed else 'unchanged'}: {result.path}")
        if result.over_budget:
            return 1
    return 0


def report_ride_waits(captures_dir: Path, places_file: Path) -> None:
    """The captured dock waits per transport against half its loop: a report, never the pack
    (corrections.captured_ride_waits)."""
    waits = captured_ride_waits(captures_dir)
    if not waits:
        return
    cycles: dict[str, int] = {}
    if places_file.is_file():
        try:
            cycles = {
                f"transport:{t['id']}": t["cycle"]
                for t in read_transports(places_file)
                if t["cycle"]
            }
        except TransportError as err:
            print(f"nav captures: {err}", file=sys.stderr)
    for ref, (median, n, files) in waits.items():
        cycle = cycles.get(ref)
        against = f", half the loop is {cycle // 2} s" if cycle else ", no loop in the places table"
        print(f"nav captures: {ref} waits {median} s (median of {n} in {files} captures){against}")


def run_nav(args: argparse.Namespace) -> int:
    """Bastians_Data_Nav/Generated/Nav.lua from the graphs, or the stub when there are none."""
    graphs_dir = args.graphs or Path(".local") / "out" / f"nav_{args.client}"
    nodes_path = args.nodes or Path("build") / f"nav-nodes-{args.client}.json"
    links_path = args.links or CONFIG_DIR / f"nav_{args.client}.toml"
    navnet_dir = args.navnet or Path(".local") / "out" / f"navnet_{args.client}"
    corrections_path = args.corrections or CONFIG_DIR / f"nav_corrections_{args.client}.toml"
    target = args.out / "Bastians_Data_Nav" / "Generated" / "Nav.lua"
    try:
        graphs, build_id = read_graphs(graphs_dir) if graphs_dir.is_dir() else ({}, None)
        levels = read_levels(navnet_dir) if navnet_dir.is_dir() else {}
        if not graphs and not levels:
            write_text(target, stub(args.client))
            print(f"nav: no graphs in {graphs_dir}, no levels in {navnet_dir}, wrote the stub")
            return 0
        given = json.loads(nodes_path.read_text(encoding="utf-8")) if nodes_path.is_file() else []
        if levels:
            # the world graph's network (ADR 0026): the record `graph` per continent
            report = nodes_path.parent
            danger_path = report / f"nav-danger-{args.client}.json"
            taxi_path = report / f"nav-taxi-{args.client}.json"
            danger = (
                json.loads(danger_path.read_text(encoding="utf-8"))
                if danger_path.is_file()
                else None
            )
            taxi = read_taxi_rows(taxi_path) if taxi_path.is_file() else []
            known = {int(n["id"].split(":")[1]) for n in given if n["id"].startswith("flightpath:")}
            table = read_corrections(corrections_path)
            captures_dir = args.captures or (Path("data") / "captures" / args.client)
            for link in captured_links(captures_dir, args.agree):
                table.links.append(link)
                print(f"nav captures: {link.name} ({link.verified}) on continent {link.continent}")
            for continent, level in sorted(levels.items()):
                for line in apply_corrections(level, table):
                    print(f"nav corrections {continent}: {line}")
            taxi_times = captured_taxi_times(captures_dir, args.agree)
            for (a, b), seconds in taxi_times.items():
                print(f"nav captures: flight {a} > {b} takes {seconds} s")
            report_ride_waits(captures_dir, CONFIG_DIR / f"places_{args.client}.toml")
            records = graph_records(levels, danger, taxi, known or None, taxi_times or None)
            build_id = build_id or next(iter(levels.values())).build
            pack = nav_pack(graphs, given, load_links(links_path), args.client, build_id)
            pack["graph"] = records
            pack["sources"] = [*pack["sources"], "client collision mesh (clientdump navnet)"]
            counts = "; ".join(
                f"{c}: {len(lv.waypoints)} waypoints, {len(lv.ways)} ways"
                for c, lv in sorted(levels.items())
            )
            text = emit_pack(
                "nav", pack, comment=f"pack nav for {args.client}, build {build_id}; {counts}"
            )
        else:
            text = emit_nav(graphs, given, load_links(links_path), args.client, build_id or "?")
    except (NavError, NavnetError, OSError, ValueError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    changed = write_text(target, text)
    size = len(text.encode("utf-8")) // 1024
    print(f"nav: {target} ({size} KB, {'changed' if changed else 'unchanged'})")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "mapart":
        return run_mapart(args)
    if args.command == "themes":
        return run_themes(args)
    if args.command == "tales":
        return run_tales(args)
    if args.command == "nav":
        return run_nav(args)
    try:
        config = load_config(args.config)
        transforms = None
        transforms_source = None
        continent_names = None
        if args.fixture:
            if args.command != "check":
                refuse_fixture_into_addons(args.fixture, args.out, "world")
            world = read_fixture(args.fixture, args.client)
        elif args.addons or args.cmangos or args.probe or args.taxi or args.dumps:
            paths = SourcePaths(
                addons=args.addons,
                cmangos=args.cmangos,
                probe=args.probe,
                dungeons=args.dungeons,
                foreverdb_api=args.foreverdb_api,
                floor_art=args.floor_art,
                floor_art_prefix=args.floor_art_prefix,
                listfile=args.listfile,
                taxi=args.taxi,
                dumps=args.dumps,
                dump_prefix=args.dump_prefix,
                tdb=args.tdb,
                navmesh=args.navmesh,
            )
            sources = load_sources(args.client, paths, eq_spawns=not args.no_eq_spawns)
            world = build_world(sources)
            transforms = sources.transforms or None
            transforms_source = sources.transforms_source
            continent_names = sources.continents or None
            attunements = args.attunements or (
                (args.config or CONFIG_DIR / "build.toml").parent
                / f"attunements_{args.client}.toml"
            )
            if attunements.is_file():
                add_attunements(world, attunements)
            # the hand-drawn dungeon maps (ADR 0048): the same file for both clients
            dungeon_art = args.dungeon_art or (
                (args.config or CONFIG_DIR / "build.toml").parent / "dungeon_art.toml"
            )
            if dungeon_art.is_file():
                add_dungeon_art(world, dungeon_art)
            places_file = args.places or (
                (args.config or CONFIG_DIR / "build.toml").parent / f"places_{args.client}.toml"
            )
            transports_file = args.transports or places_file
            if transports_file.is_file():
                add_transports(world, transports_file, sources.transforms or None)
            if places_file.is_file():
                tables = read_places(places_file)
                add_entrances(world, tables["entrance"], sources.transforms or None)
                add_teleports(world, tables["teleport"])
            # where a quest's step is done as a person checked or read it (ADR 0070, QD5): the
            # steps' resolver puts these rows before every source
            quest_places = args.quest_places or (
                (args.config or CONFIG_DIR / "build.toml").parent
                / f"quest_places_{args.client}.toml"
            )
            if quest_places.is_file():
                add_quest_places(world, read_quest_places(quest_places))
        else:
            print(
                "error: give --fixture, or --addons / --cmangos / --probe / --taxi / --dumps",
                file=sys.stderr,
            )
            return 2
        export = read_export(args.export) if args.export else None
        if export:
            add_market(world, export, config.market)
        # the client's own item names in every installed text language (ADR 0035); Forever only:
        # the retail client names its items in its own language at runtime, and the names of every
        # referred item made each retail language pack 10.8 MB (29.10.2026)
        client_names = (
            client_tables.localized_names(args.dumps, args.client)
            if args.dumps and args.client == "forever"
            else {}
        )
        if args.l10n or args.tdb or args.tdb_texts or client_names:
            # the game data in other languages (data.md, ADR 0033): QuestieDB's l10n lookups,
            # CMaNGOS' quest locales (German, Chinese) and TDB's long quest texts (Korean,
            # Chinese) for Forever, TDB's locale tables for retail
            added = add_l10n(world, args.l10n, args.cmangos, args.tdb, client_names, args.tdb_texts)
            for locale, n in added.items():
                print(f"l10n {locale}: {n} records")
        checks = compare(world, read_truth(args.ground_truth)) if args.ground_truth else None
        probe_truth = None
        if args.probe:
            # the dump's P2, P4 and P7 measurements against the world and the transforms used
            dump = read_probe_dump(args.probe)
            if not transforms:
                transforms = transform_table(dump) or None
                transforms_source = transforms_source or f"probe {args.probe.name}"
            probe_truth = check_probe(dump, world, transforms)
        book_dir = args.book or (None if args.fixture or not CONTENT_DIR.is_dir() else CONTENT_DIR)
        if book_dir and export:
            # the Strategies book (strategies-design.md section 6), the claims from the export
            add_book(world, export, book_dir, transforms, args.art or export.folder / "art")
        if export and world.client == "forever":
            # the daily run's selection: the export's strategies scored (design section 7)
            found = candidates(export, world)
            report = write_report(found, args.report_dir)
            print(f"candidates: {report}")
            # the Rumour mill: the strongest strategies no page tells yet, rebuilt every export
            add_mill(world, found)
            if world.records.get("chapter"):
                # What's new written by the build: the book's changes since the last sent edition
                previous = read_state(args.book_previous) if args.book_previous else None
                date = (export.created_at or "")[:10] or None
                state, _ = add_generated_news(world, found, previous, date)
                if args.command != "check":
                    state_path = args.book_state or args.report_dir / "book-state.json"
                    write_state(state_path, state)
                    print(f"book state: {state_path}")
        elif args.book:
            print("error: --book needs --export (the claims come from it)", file=sys.stderr)
            return 2
        result = build(
            world,
            config,
            args.out,
            write=args.command != "check",
            transforms=transforms,
            report_dir=args.report_dir,
            ground_truth=checks,
            transforms_source=transforms_source,
            continent_names=continent_names,
            probe_truth=probe_truth,
        )
        if args.command != "check" and not args.fixture:
            # the walk network's nodes for tools/nav_build.py (ADR 0025)
            nodes_path = args.report_dir / f"nav-nodes-{world.client}.json"
            write_text(nodes_path, json.dumps(nav_nodes(world), indent=1, sort_keys=True) + "\n")
            # the world graph's network (ADR 0026, W3b): danger points and the taxi paths
            danger_path = args.report_dir / f"nav-danger-{world.client}.json"
            danger = danger_points(world, transforms)
            extra = tdb_danger(sources.tdb)  # retail: the hostile spawns stay out of the pack
            danger["hostile"] += extra["hostile"]
            danger["guards"] += extra["guards"]
            write_text(danger_path, json.dumps(danger, sort_keys=True) + "\n")
            if sources.taxi_paths:
                taxi_path = args.report_dir / f"nav-taxi-{world.client}.json"
                rows = taxi_rows(sources.taxi_paths)
                write_text(taxi_path, json.dumps(rows, indent=0, sort_keys=True) + "\n")
    except (
        AttunementError,
        BookError,
        BookNewsError,
        ClientDumpError,
        ConfigError,
        DungeonArtError,
        ExportError,
        FixtureError,
        GroundTruthError,
        PlacesError,
        TransportError,
        OSError,
        ValueError,
    ) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    for problem in result.problems:
        print(f"problem: {problem}")
    if result.ground_truth is not None:
        counts = summary(result.ground_truth)
        print(
            f"ground truth: {counts['checked']} checked, {counts['ok']} ok, {counts['off']} off, "
            f"{counts['no spawn on map']} without a spawn on the map, "
            f"{counts['missing npc']} missing"
        )
    if result.probe_truth is not None:
        t = result.probe_truth
        print(
            "probe ground truth: positions "
            f"{sum(p.status == 'ok' for p in t.points)}/{len(t.points)} ok, taxi nodes "
            f"{sum(n.status == 'ok' for n in t.nodes)}/{len(t.nodes)} ok, quests "
            f"{sum(q.status == 'ok' for q in t.quests)}/{len(t.quests)} ok, targets "
            f"{sum(x.status == 'ok' for x in t.targets)}/{len(t.targets)} ok, "
            f"{len(t.flights)} flights"
        )
    for name in result.skipped:
        print(f"skipped: pack {name} (optional, no records)")
    for p in result.packs:
        state = "written" if p.changed else "unchanged"
        over = " ABOVE THE CEILING (build.toml [limits] pack_kb)" if p.over_ceiling else ""
        print(f"{state}: {p.path} ({p.size / 1024:.1f} KB){over}")
    if result.transforms_path:
        print(
            f"{'written' if result.transforms_changed else 'unchanged'}: {result.transforms_path}"
        )
    if result.report_path:
        print(f"report: {result.report_path}")
    if result.links_path:
        c = result.steps.counts()
        print(
            f"quest steps: {c['steps']}, {c['placed']} with a place, {c['unplaced']} without, "
            f"the Classic debt {c['classic']}: {result.links_path}"
        )
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
