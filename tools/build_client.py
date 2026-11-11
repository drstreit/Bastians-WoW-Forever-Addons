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
    [build.sources]                                     # the source addons, if not the client's
    forever = ".local/sources/forever"                  #   Interface/AddOns (Forever: the beta's)
    [build.dump_prefix]
    forever = "beta"                                    # clientdump JSON prefix in .local/out
    retail = "retail"
    [build.tdb]                                         # retail: TrinityCore's world dump
    retail = ".local/sources/retail/tdb/TDB_full_world_<build>.sql"  # (sources.md), or --tdb
    [build.tdb_texts]                                   # Forever: the Korean and Chinese long
    forever = "<the same dump>"                         #   quest texts (default: the retail one)

Then runs, in order, `python -m bastians_build data ...` (the packs, MapTransforms.lua, the report)
and `python -m bastians_build mapart ...` (MinimapTiles.lua and Bastians_Map_Art/Generated, when
the tile lists and overview cells of that client exist in .local/out; see tools/mapart_extract.py),
then `python -m bastians_build nav ...` (Bastians_Data_Nav: the walk network from
tools/nav_build.py's graphs in .local/out/nav_<client>, or a stub without them).
`addons/` holds one client's generated files at a time: build the other client into another
folder with --out, or rebuild afterwards.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / ".local" / "install.toml"
DUMPS = ROOT / ".local" / "out"
LISTFILE = ROOT / ".local" / "listfile" / "community-listfile.csv"
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
    tdb: Path | None = None  # retail: TrinityCore's world dump (sources.md), [build.tdb] or --tdb
    # Forever: the same dump for the long quest texts in Korean and Chinese ([build.tdb_texts],
    # else [build.tdb]'s retail dump; data.md "Game data in other languages")
    tdb_texts: Path | None = None
    # the game data in other languages (ADR 0033): QuestieDB's l10n lookups, [build.l10n] or
    # .local/sources/<client>/questie-l10n (tools/fetch_questie_l10n.py) when it exists
    l10n: Path | None = None
    # retail: ForeverDB's Dungeons.lua from the Forever sources, so the test client shows the
    # dungeon pages too
    dungeons: Path | None = None
    # the dungeon floors' maps (DG2c): retail's UiMap tables in .local/out and the community
    # listfile in .local/listfile, for both clients, when they exist
    floor_art: Path | None = None
    listfile: Path | None = None
    # Forever: ForeverDB's API rows as AHSync stored them ([build.foreverdb_api], else AHSync's
    # data/external/foreverdb-api/latest when it exists): seen places for gaps (data.md)
    foreverdb_api: Path | None = None
    extra: list[str] = field(default_factory=list)


class BuildClientError(Exception):
    pass


def _tree(path: Path | None) -> tuple[int, int]:
    """(files, bytes) under a folder or of a file; (0, 0) when it is not there."""
    if path is None or not path.exists():
        return 0, 0
    files = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
    return len(files), sum(p.stat().st_size for p in files)


def _git_head(path: Path | None) -> str:
    """A checkout's commit, read from its files (no git needed); "" when it is none."""
    if path is None or not (path / ".git" / "HEAD").is_file():
        return ""
    head = (path / ".git" / "HEAD").read_text(encoding="utf-8").strip()
    if not head.startswith("ref: "):
        return head[:12]
    ref = path / ".git" / head[5:]
    if ref.is_file():
        return ref.read_text(encoding="utf-8").strip()[:12]
    packed = path / ".git" / "packed-refs"
    if packed.is_file():
        for line in packed.read_text(encoding="utf-8").splitlines():
            if line.endswith(" " + head[5:]):
                return line.split(" ", 1)[0][:12]
    return ""


def local_inputs(inputs: BuildInputs, dumps: Path = DUMPS) -> tuple[str, list[str]]:
    """What the build reads from this machine besides the repository, the export and the source
    addons: the client's dumps, the CMaNGOS mirror, the language lookups and long texts. -> (a
    short hash, one line per input). The edition's skip check takes the hash (until 10.11.2026 a
    new dump with an unchanged export built nothing), and the lines say why two machines build
    different packs (09.11.2026: the French text pack was 4,028 KB on one and 5,292 KB on the
    other). Sizes and names, never times: a copy has other times."""
    n, size = 0, 0
    for path in sorted(dumps.glob(f"{inputs.prefix}_*")) if dumps.is_dir() else []:
        files, more = _tree(path)
        n, size = n + files, size + more
    parts = [f"dumps {inputs.prefix}: {n} files, {size} bytes"]
    parts.append(f"cmangos: {_git_head(inputs.cmangos) or 'none'}")
    for name, path in (
        ("l10n", inputs.l10n),
        ("long texts", inputs.tdb_texts),
        ("ForeverDB API", inputs.foreverdb_api),
    ):
        files, more = _tree(path)
        parts.append(f"{name}: {files} files, {more} bytes")
    digest = hashlib.sha1("\n".join(parts).encode()).hexdigest()[:12]
    return digest, parts


FOREVERDB_API = ROOT / "ahsync" / "data" / "external" / "foreverdb-api" / "latest"


def _default_api() -> Path | None:
    """AHSync's last complete fetch of ForeverDB's API, when there is one."""
    return FOREVERDB_API if (FOREVERDB_API / "quests.json").is_file() else None


def _retail_tdb(build: dict) -> Path | None:
    """[build.tdb]'s retail dump when it exists (Forever reads its long quest texts from it)."""
    value = build.get("tdb")
    value = value.get("retail") if isinstance(value, dict) else value
    if not value:
        return None
    path = Path(str(value))
    path = path if path.is_absolute() else ROOT / path
    return path if path.is_file() else None


def _default_l10n(client: str) -> Path | None:
    path = ROOT / ".local" / "sources" / client / "questie-l10n"
    return path if path.is_dir() else None


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
    build = raw.get("build", {})
    if not addons.is_dir() and not (build.get("sources") or {}).get(client):
        raise BuildClientError(f"{addons} does not exist")
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

    # the source addons can live outside the client (24.10.2026: the Forever beta was uninstalled,
    # its EverythingQuests, ForeverDB and QuestieDB are kept in .local/sources/forever)
    sources = optional("sources")
    if sources is not None:
        if not sources.is_dir():
            raise BuildClientError(f"[build.sources] {client}: {sources} does not exist")
        addons = sources
    dungeons = None
    if client == "retail":
        forever_sources = (build.get("sources") or {}).get("forever")
        if forever_sources:
            candidate = Path(str(forever_sources))
            candidate = candidate if candidate.is_absolute() else ROOT / candidate
            candidate = candidate / "ForeverDB" / "Data" / "Dungeons.lua"
            dungeons = candidate if candidate.is_file() else None
    return BuildInputs(
        client=client,
        addons=addons,
        prefix=prefix,
        cmangos=optional("cmangos") if client == "forever" else None,
        ground_truth=optional("ground_truth"),
        export=optional("export"),
        probe=optional("probe"),
        tdb=optional("tdb") if client == "retail" else None,
        tdb_texts=(optional("tdb_texts") or _retail_tdb(build)) if client == "forever" else None,
        l10n=optional("l10n") or _default_l10n(client),
        dungeons=dungeons,
        floor_art=DUMPS if (DUMPS / "retail_UiMapArtTile.json").is_file() else None,
        listfile=LISTFILE if LISTFILE.is_file() else None,
        foreverdb_api=(optional("foreverdb_api") or _default_api())
        if client == "forever"
        else None,
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
    if inputs.tdb:
        data += ["--tdb", str(inputs.tdb)]
    if inputs.tdb_texts:
        data += ["--tdb-texts", str(inputs.tdb_texts)]
    if inputs.l10n:
        data += ["--l10n", str(inputs.l10n)]
    if inputs.dungeons:
        data += ["--dungeons", str(inputs.dungeons)]
    if inputs.floor_art:
        data += ["--floor-art", str(inputs.floor_art)]
    if inputs.listfile:
        data += ["--listfile", str(inputs.listfile)]
    if inputs.foreverdb_api:
        data += ["--foreverdb-api", str(inputs.foreverdb_api)]
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
    # the walk network (ADR 0025): from tools/nav_build.py's graphs of this client, else the stub,
    # so Nav.lua always belongs to the client the other packs were built for
    nav = [python, "-m", "bastians_build", "nav", "--client", inputs.client, "--out", str(out)]
    cmds.append(nav)
    return cmds


def book_args(inputs: BuildInputs) -> tuple[list[str], Path | None]:
    """The book's inputs the daily edition passes (tools/data_update.py): the pictures' folder
    (`--art`, the export's art/ else the owner's approved set) and the last sent edition's book
    state (`--book-previous`, What's new). Without them a page carries no picture flag, and the
    book shows no picture of Bastian and only generic marks on its story map (owner, Forever
    07.11.2026, after a build_client run). -> (the extra arguments, the art folder)."""
    import data_update  # lazily: data_update imports this module

    extra: list[str] = []
    sent = data_update.last_sent(data_update.read_ledger(data_update.LEDGER))
    previous = (
        data_update.BOOK_STATES / sent["book_state"] if sent and sent.get("book_state") else None
    )
    if previous is not None and previous.is_file():
        extra += ["--book-previous", str(previous)]
    art = data_update.art_folder(inputs.export)
    if art is not None:
        extra += ["--art", str(art)]
    return extra, art


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--out", type=Path, default=ROOT / "addons", help="output root")
    parser.add_argument("--dry-run", action="store_true", help="print the commands only")
    parser.add_argument("--skip-mapart", action="store_true", help="data packs only")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help=argparse.SUPPRESS)
    parser.add_argument(
        "--tdb", type=Path, help="retail: TrinityCore's world dump (overrides [build.tdb])"
    )
    args = parser.parse_args(argv)
    try:
        inputs = read_inputs(args.client, args.config)
    except BuildClientError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    if args.tdb:
        inputs = dataclasses.replace(inputs, tdb=args.tdb)
    art = None
    if args.client == "forever":
        book, art = book_args(inputs)
        inputs = dataclasses.replace(inputs, extra=[*inputs.extra, *book])
    cmds = commands(inputs, args.out, skip_mapart=args.skip_mapart)
    if not any(cmd[3] == "mapart" for cmd in cmds) and not args.skip_mapart:
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
    if args.client == "forever" and not args.dry_run:
        import book_art

        pictures = book_art.install(art, args.out, front=book_art.FRONT)
        print(f"book art: {len(pictures)} pictures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
