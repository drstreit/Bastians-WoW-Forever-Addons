"""Build everything the addons need for one client in one go: data packs, tile table, overview.

Usage: python tools/build_client.py --client forever|retail [--out addons] [--dry-run]
       [--skip-mapart]

Reads the client folder from .local/install.toml (tools/install.py --wow remembers it) and the
machine-specific build inputs from its optional [build] section:

    [build]
    cmangos = "C:/path/to/cmangos-classic-db"          # Forever only, optional
    export = "C:/path/to/ahsync/export"                 # the AHSync market export, optional
    [build.ground_truth]                                # a string applies to both clients
    forever = "data/ground-truth/npc_places_forever_beta_2026-10-18.csv"
    [build.probe]                                       # Bastians_Probe dump (transforms, checks)
    forever = "data/probe/2026-10-20-forever-70450.lua"
    [build.dump_prefix]
    forever = "beta"                                    # clientdump JSON prefix in .local/out
    retail = "retail"

Then runs, in order, `python -m bastians_build data ...` (the packs, MapTransforms.lua, the report)
and `python -m bastians_build mapart ...` (MinimapTiles.lua and Bastians_Map_Art/Generated, when
the tile lists and overview cells of that client exist in .local/out; see tools/mapart_extract.py).
`addons/` holds one client's generated files at a time: build the other client into another
folder with --out, or rebuild afterwards.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / ".local" / "install.toml"
DUMPS = ROOT / ".local" / "out"
CLIENTS = ("forever", "retail")
DEFAULT_PREFIX = {"forever": "beta", "retail": "retail"}


@dataclass(frozen=True)
class BuildInputs:
    client: str
    addons: Path  # the client's Interface/AddOns folder
    prefix: str
    cmangos: Path | None = None
    ground_truth: Path | None = None
    export: Path | None = None
    probe: Path | None = None
    extra: list[str] = field(default_factory=list)


class BuildClientError(Exception):
    pass


def read_inputs(client: str, config_path: Path = CONFIG_PATH) -> BuildInputs:
    if client not in CLIENTS:
        raise BuildClientError(f"client must be one of {CLIENTS}")
    if not config_path.is_file():
        raise BuildClientError(f"{config_path} missing: run tools/install.py --wow <folder> first")
    with config_path.open("rb") as fh:
        raw = tomllib.load(fh)
    clients = raw.get("clients", {})
    if client not in clients:
        raise BuildClientError(f"no client folder for {client} in {config_path}")
    addons = Path(clients[client]) / "Interface" / "AddOns"
    if not addons.is_dir():
        raise BuildClientError(f"{addons} does not exist")
    build = raw.get("build", {})
    prefix = str(build.get("dump_prefix", {}).get(client, DEFAULT_PREFIX[client]))

    def optional(key: str) -> Path | None:
        """A path for every client (string) or per client (table keyed forever/retail)."""
        value = build.get(key)
        if isinstance(value, dict):
            value = value.get(client)
        if not value:
            return None
        path = Path(str(value))
        return path if path.is_absolute() else ROOT / path

    return BuildInputs(
        client=client,
        addons=addons,
        prefix=prefix,
        cmangos=optional("cmangos") if client == "forever" else None,
        ground_truth=optional("ground_truth"),
        export=optional("export"),
        probe=optional("probe"),
    )


def commands(inputs: BuildInputs, out: Path, *, skip_mapart: bool = False) -> list[list[str]]:
    """The pipeline invocations, data first; mapart only when its inputs exist."""
    python = sys.executable
    data = [
        python,
        "-m",
        "bastians_build",
        "data",
        "--client",
        inputs.client,
        "--addons",
        str(inputs.addons),
        "--dumps",
        str(DUMPS),
        "--dump-prefix",
        inputs.prefix,
        "--out",
        str(out),
    ]
    if inputs.cmangos:
        data += ["--cmangos", str(inputs.cmangos)]
    if inputs.ground_truth:
        data += ["--ground-truth", str(inputs.ground_truth)]
    if inputs.export:
        data += ["--export", str(inputs.export)]
    if inputs.probe:
        data += ["--probe", str(inputs.probe)]
    data += inputs.extra
    cmds = [data]
    tiles = DUMPS / f"mm_{inputs.prefix}"
    overview = DUMPS / f"ov_{inputs.prefix}"
    maps = DUMPS / f"{inputs.prefix}_Map.json"
    if not skip_mapart and tiles.is_dir() and maps.is_file():
        mapart = [
            python,
            "-m",
            "bastians_build",
            "mapart",
            "--client",
            inputs.client,
            "--tiles",
            str(tiles),
            "--maps",
            str(maps),
            "--out",
            str(out),
        ]
        if overview.is_dir():
            mapart += ["--overview", str(overview)]
        cmds.append(mapart)
    return cmds


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--out", type=Path, default=ROOT / "addons", help="output root")
    parser.add_argument("--dry-run", action="store_true", help="print the commands only")
    parser.add_argument("--skip-mapart", action="store_true", help="data packs only")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        inputs = read_inputs(args.client, args.config)
    except BuildClientError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    cmds = commands(inputs, args.out, skip_mapart=args.skip_mapart)
    if len(cmds) == 1 and not args.skip_mapart:
        print(
            f"note: no tile lists for prefix {inputs.prefix!r} in {DUMPS}; "
            f"run tools/mapart_extract.py --client {inputs.client} --prefix {inputs.prefix} first"
        )
    for cmd in cmds:
        print("> " + " ".join(cmd[3:]), flush=True)
        if args.dry_run:
            continue
        run = subprocess.run(cmd, cwd=ROOT)
        if run.returncode:
            print(f"error: {cmd[3]} exited with {run.returncode}", file=sys.stderr)
            return run.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
