"""Entry point: python -m bastians_build <command> (pipeline.md).

data   --client forever|retail [--addons <AddOns>] [--cmangos <dir>] [--probe <dump>]
       (a probe dump also feeds the "Probe ground truth" report section: P4 landmarks and P7 taxi
       maps against the transforms, taxi nodes against the flight masters, the quest log, flights)
       [--taxi <TaxiNodes.json>] [--transports <toml>]
       [--dumps <folder> [--dump-prefix beta]]  clientdump UiMap/UiMapAssignment/TaxiNodes:
                                             map transform table from the client (no probe dump)
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
"""

from __future__ import annotations

import argparse
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
from bastians_build.groundtruth import GroundTruthError, compare, read_truth, summary
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
from bastians_build.overview import install_overview
from bastians_build.probetruth import check_probe
from bastians_build.sources.ahsync_export import ExportError, read_export
from bastians_build.sources.clientdump import ClientDumpError
from bastians_build.sources.fixture import FixtureError, read_fixture
from bastians_build.sources.probe import read_probe_dump, transform_table
from bastians_build.themes import OUT as THEMES_OUT
from bastians_build.themes import ThemeError, build_themes
from bastians_build.transports import TransportError, add_transports


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
            "--transports",
            type=Path,
            help="transports TOML (default: pipeline/config/transports_<client>.toml; "
            "the fixture world carries its own)",
        )
        p.add_argument(
            "--no-eq-spawns", action="store_true", help="skip Everything Quests objective spots"
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
    p = sub.add_parser("themes", help="compile the theme TOML files into Core's Themes.lua")
    p.add_argument("--check", action="store_true", help="exit 1 when Themes.lua is not current")
    return parser


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


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "mapart":
        return run_mapart(args)
    if args.command == "themes":
        return run_themes(args)
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
                taxi=args.taxi,
                dumps=args.dumps,
                dump_prefix=args.dump_prefix,
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
            transports_file = args.transports or (
                (args.config or CONFIG_DIR / "build.toml").parent / f"transports_{args.client}.toml"
            )
            if transports_file.is_file():
                add_transports(world, transports_file, sources.transforms or None)
        else:
            print(
                "error: give --fixture, or --addons / --cmangos / --probe / --taxi / --dumps",
                file=sys.stderr,
            )
            return 2
        export = read_export(args.export) if args.export else None
        if export:
            add_market(world, export, config.market)
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
            add_book(world, export, book_dir, transforms)
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
    except (
        AttunementError,
        BookError,
        BookNewsError,
        ClientDumpError,
        ConfigError,
        ExportError,
        FixtureError,
        GroundTruthError,
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
        over = " OVER BUDGET" if p.over_budget else ""
        print(f"{state}: {p.path} ({p.size / 1024:.1f} KB){over}")
    if result.transforms_path:
        print(
            f"{'written' if result.transforms_changed else 'unchanged'}: {result.transforms_path}"
        )
    if result.report_path:
        print(f"report: {result.report_path}")
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
