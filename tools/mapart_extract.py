"""Run tools/clientdump for every world continent of a client: tile lists and overview textures.

Usage: python tools/mapart_extract.py --client forever|retail --prefix beta|retail
       [--out .local/out/mm_<prefix>] [--overview .local/out/ov_<prefix>] [--only <map directory>]
       [--force] [--dry-run]

Reads the client folder from .local/install.toml (tools/install.py --wow remembers it) and the
continent list from the clientdump JSON in .local/out (<prefix>_Map, _UiMap, _UiMapAssignment,
dumped with `clientdump db2`), then runs `clientdump minimap` (the `<Dir>_tiles.txt` lists for
Bastians_Map) and `clientdump overview` (the stitched cells for Bastians_Map_Art) per map with the
span and pixels of pipeline/config/build.toml. Maps whose outputs exist are skipped unless --force.
Afterwards: python -m bastians_build mapart --client <client> --tiles <out> --overview <overview>
--maps .local/out/<prefix>_Map.json
"""

# ruff: noqa: E402  (the repo's pipeline and tools are put on sys.path first)
from __future__ import annotations

import argparse
import subprocess
import sys
import time
import tomllib
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
sys.path.insert(0, str(ROOT / "tools"))

from install import CONFIG_PATH
from install import load_config as load_install

from bastians_build import mapart_art
from bastians_build.config import CLIENTS, load_config
from bastians_build.sources import clientdump, probe

DUMPS = ROOT / ".local" / "out"
PROJECT = ROOT / "tools" / "clientdump"


@dataclass(frozen=True)
class Job:
    map_id: int
    name: str
    directory: str
    wdt: int
    tiles: Path  # <Dir>_tiles.txt
    index: Path  # <Dir>_overview.json
    skip: str | None  # why nothing runs for this map


def plan(
    continents: dict[int, str],
    maps: dict[int, clientdump.MapRow],
    out: Path,
    overview: Path,
    *,
    only: str | None = None,
    force: bool = False,
) -> list[Job]:
    """One job per world continent, in map id order; `skip` says why a map needs no run."""
    jobs: list[Job] = []
    for map_id, name in sorted(continents.items()):
        row = maps[map_id]
        tiles = out / f"{row.directory}_tiles.txt"
        index = overview / f"{row.directory}_overview.json"
        skip = None
        if only and row.directory.lower() != only.lower() and str(map_id) != only:
            skip = "not selected"
        elif not row.wdt_file_id:
            skip = "no WDT FileDataID in Map.db2"
        elif not force and tiles.is_file() and index.is_file():
            skip = "exists"
        jobs.append(Job(map_id, name, row.directory, row.wdt_file_id or 0, tiles, index, skip))
    return jobs


def commands(
    job: Job,
    install: Path,
    out: Path,
    overview: Path,
    span: int,
    pixels: int,
    alpha: str = "dxt1",
    sea: str | None = None,
    art: Path | None = None,
) -> list[list[str]]:
    """The clientdump invocations of one job (minimap first, then overview)."""
    base = ["dotnet", "run", "--project", str(PROJECT), "-c", "Release", "--no-build", "--"]
    common = ["--install", str(install), "--map", job.directory, "--wdt-fdid", str(job.wdt)]
    return [
        [*base, "minimap", *common, "--out", str(out)],
        [
            *base,
            "overview",
            *common,
            "--out",
            str(overview),
            "--span",
            str(span),
            "--pixels",
            str(pixels),
            "--alpha",
            alpha,
            *(["--sea", sea] if sea else []),
            *(["--art", str(art)] if art else []),
        ],
    ]


def probe_path(client: str, config_path: Path = CONFIG_PATH) -> Path | None:
    """`[build.probe] <client>` of .local/install.toml: the Bastians_Probe dump whose measured
    transforms the data build uses (build_client.py); the art must sit where the addon draws."""
    try:
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except OSError, tomllib.TOMLDecodeError:
        return None
    value = (data.get("build") or {}).get("probe")
    if isinstance(value, dict):
        value = value.get(client)
    if not value:
        return None
    path = Path(str(value))
    return path if path.is_absolute() else ROOT / path


def prepare_art(
    client: str,
    prefix: str,
    install: Path,
    maps: dict[int, clientdump.MapRow],
    ui: dict[int, clientdump.UiMapRow],
    assign: list[clientdump.Assignment],
    continents: dict[int, str],
    overview: Path,
    *,
    dry_run: bool = False,
) -> dict[int, Path]:
    """`<Dir>_art.json` per continent in the overview folder (mapart_art): the continent UiMap's
    parchment and its transform (the probe dump's when there is one, else UiMapAssignment's).
    Dumps the four art tables with clientdump when they are missing. A map without art gets a
    note and no file; the stitcher then paints the sea tone alone."""
    paths = mapart_art.table_paths(DUMPS, prefix)
    missing = [name for name, path in paths.items() if not path.is_file()]
    if missing and not dry_run:
        for name in missing:
            run = subprocess.run(
                [
                    "dotnet",
                    "run",
                    "--project",
                    str(PROJECT),
                    "-c",
                    "Release",
                    "--no-build",
                    "--",
                    "db2",
                    "--install",
                    str(install),
                    "--table",
                    name,
                    "--out",
                    str(paths[name]),
                ],
                capture_output=True,
                text=True,
            )
            if run.returncode:
                print(f"art: no {name} dump ({run.stderr.strip()[-160:]}); cells without parchment")
                return {}
    if any(not path.is_file() for path in paths.values()):
        print("art: the UiMapArt dumps are missing; cells without parchment")
        return {}
    try:
        tables = mapart_art.read_art_tables(paths)
    except (clientdump.ClientDumpError, OSError) as err:
        print(f"art: {err}; cells without parchment")
        return {}
    homes = clientdump.continent_homes(assign, ui)
    transforms: dict[int, probe.Transform] = {}
    dump_path = probe_path(client)
    if dump_path and dump_path.is_file():
        transforms = probe.transform_table(probe.read_probe_dump(dump_path))
    out: dict[int, Path] = {}
    for map_id in sorted(continents):
        data, note = mapart_art.continent_art(
            map_id, tables, homes, transforms, assign, set(continents)
        )
        row = maps.get(map_id)
        if data is None or row is None:
            print(f"art  {map_id:5d} {continents[map_id][:32]:32s} none: {note}")
            continue
        path = overview / f"{row.directory}_art.json"
        if not dry_run:
            overview.mkdir(parents=True, exist_ok=True)
            mapart_art.write_art(path, data)
        out[map_id] = path
        print(f"art  {map_id:5d} {continents[map_id][:32]:32s} {note}")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--prefix", required=True, help="clientdump JSON prefix in .local/out")
    parser.add_argument(
        "--out", type=Path, help="tile list folder (default .local/out/mm_<prefix>)"
    )
    parser.add_argument(
        "--overview", type=Path, help="overview output folder (default .local/out/ov_<prefix>)"
    )
    parser.add_argument("--only", help="one map directory or id")
    parser.add_argument("--force", action="store_true", help="rerun maps whose outputs exist")
    parser.add_argument("--dry-run", action="store_true", help="print the commands only")
    args = parser.parse_args(argv)

    clients = load_install(CONFIG_PATH)
    if args.client not in clients:
        print(f"error: no client folder for {args.client} in {CONFIG_PATH}", file=sys.stderr)
        return 2
    install = Path(clients[args.client])
    out = args.out or DUMPS / f"mm_{args.prefix}"
    overview = args.overview or DUMPS / f"ov_{args.prefix}"
    try:
        maps = clientdump.read_maps(DUMPS / f"{args.prefix}_Map.json")
        ui = clientdump.read_ui_maps(DUMPS / f"{args.prefix}_UiMap.json")
        assign = clientdump.read_ui_map_assignments(DUMPS / f"{args.prefix}_UiMapAssignment.json")
    except (OSError, clientdump.ClientDumpError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    continents = clientdump.world_continents(maps, assign, ui)
    config = load_config().mapart
    art_of = prepare_art(
        args.client,
        args.prefix,
        install,
        maps,
        ui,
        assign,
        continents,
        overview,
        dry_run=args.dry_run,
    )
    pixels = config.pixels_for(args.client)
    jobs = plan(continents, maps, out, overview, only=args.only, force=args.force)
    print(
        f"{len(continents)} continents, span {config.span}, {pixels} px per tile, "
        f"alpha {config.alpha}, sea {config.sea or 'transparent'}"
    )
    if not args.dry_run:
        build = subprocess.run(
            ["dotnet", "build", str(PROJECT), "-c", "Release", "--nologo", "-v", "q"],
            capture_output=True,
            text=True,
        )
        if build.returncode:
            print(build.stdout + build.stderr, file=sys.stderr)
            return 1
    failed = 0
    for job in jobs:
        if job.skip:
            print(f"skip {job.map_id:5d} {job.name[:32]:32s} {job.directory:20s} {job.skip}")
            continue
        for cmd in commands(
            job,
            install,
            out,
            overview,
            config.span,
            pixels,
            config.alpha,
            config.sea,
            art_of.get(job.map_id),
        ):
            if args.dry_run:
                print(" ".join(cmd))
                continue
            started = time.time()
            run = subprocess.run(cmd, capture_output=True, text=True)
            summary = [ln for ln in run.stdout.splitlines() if ln.startswith(("overview", "MAID"))]
            status = "ok" if run.returncode == 0 else f"exit {run.returncode}"
            print(
                f"{cmd[8]:8s} {job.map_id:5d} {job.name[:32]:32s} {status}, "
                f"{time.time() - started:.0f} s  "
                f"{summary[-1] if summary else run.stderr.strip()[-200:]}"
            )
            if run.returncode:
                failed += 1
                break
    print(
        f"next: python -m bastians_build mapart --client {args.client} --tiles {out} "
        f"--overview {overview} --maps {DUMPS / f'{args.prefix}_Map.json'}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
