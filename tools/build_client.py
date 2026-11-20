"""Build everything the addons need for one client in one go: data packs, tile table, overview.

Usage: python tools/build_client.py --client forever [--out addons] [--dry-run]
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
    [build.tdb_texts]                                   # TrinityCore's world dump (sources.md):
    forever = ".local/sources/retail/tdb/TDB_full_world_<build>.sql"  # the long quest texts
    [build.tdb]                                         # ~~retail: the world dump~~; still read
    retail = "<the same dump>"                          #   for the texts when tdb_texts is unset

Then runs, in order, `python -m bastians_build data ...` (the packs, MapTransforms.lua, the report)
and `python -m bastians_build mapart ...` (MinimapTiles.lua and Bastians_Map_Art/Generated, when
the tile lists and overview cells of that client exist in .local/out; see tools/mapart_extract.py),
then `python -m bastians_build nav ...` (Bastians_Data_Nav: the walk network from
tools/nav_build.py's graphs in .local/out/nav_<client>, or a stub without them).
~~`addons/` holds one client's generated files at a time~~: Forever is the only client since
15.11.2026 (ADR 0037).
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import re
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / ".local" / "install.toml"
DUMPS = ROOT / ".local" / "out"
LISTFILE = ROOT / ".local" / "listfile" / "community-listfile.csv"
# ~~forever and retail~~ Forever alone since 15.11.2026 (ADR 0037)
CLIENTS = ("forever",)
DEFAULT_PREFIX = {"forever": "beta"}


@dataclass(frozen=True)
class BuildInputs:
    client: str
    addons: Path  # the client's Interface/AddOns folder
    prefix: str
    cmangos: Path | None = None
    ground_truth: Path | None = None
    export: Path | None = None
    probe: Path | None = None
    # TrinityCore's world dump (sources.md) for the long quest texts in the other languages
    # ([build.tdb_texts], else [build.tdb]; data.md "Game data in other languages")
    tdb_texts: Path | None = None
    # the game data in other languages (ADR 0033): QuestieDB's l10n lookups, [build.l10n] or
    # .local/sources/<client>/questie-l10n (tools/fetch_questie_l10n.py) when it exists
    l10n: Path | None = None
    # the dungeon floors' maps (DG2c): the retail client's UiMap tables in .local/out
    # (retail_*.json) and the community listfile in .local/listfile, when they exist
    floor_art: Path | None = None
    listfile: Path | None = None
    # Forever: ForeverDB's API rows as AHSync stored them ([build.foreverdb_api], else AHSync's
    # data/external/foreverdb-api/latest when it exists): seen places for gaps (data.md)
    foreverdb_api: Path | None = None
    # why `prefix` is not the client's own build (engine_prefix), when it is not
    prefix_note: str | None = None
    # why `probe` is not a record of the client's own build, when it is not
    probe_note: str | None = None
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


def _present(path: Path | None) -> bool:
    """A file, or a folder with something in it."""
    if path is None or not path.exists():
        return False
    return path.is_file() or any(path.iterdir())


def missing_inputs(inputs: BuildInputs, dumps: Path = DUMPS) -> list[str]:
    """What a Forever build reads from this machine and does not find, one sentence each with
    where it comes from. A missing input never stops the build (the packs carry what is there),
    but each is an alarm: the packs lose what it gives, and nothing else says so (12.11.2026:
    the notebook had no TDB dump configured since it took over, and five language packs shipped
    without their long quest texts for two nights). ~~Retail is the test client: none checked~~
    (retail out 15.11.2026)."""
    dumped = dumps.is_dir() and any(dumps.glob(f"{inputs.prefix}_*"))
    checks = (
        (dumped, f"client dumps {inputs.prefix}_*", f"{dumps}, from tools/client_tables.py"),
        (_present(inputs.cmangos), "CMaNGOS mirror", "[build] cmangos in .local/install.toml"),
        (
            _present(inputs.l10n),
            "QuestieDB l10n lookups",
            "[build.l10n] or .local/sources/forever/questie-l10n",
        ),
        (
            _present(inputs.tdb_texts),
            "TDB world dump (the long quest texts of five languages)",
            "[build.tdb_texts] forever or [build.tdb] in .local/install.toml",
        ),
        (
            _present(inputs.foreverdb_api),
            "ForeverDB API rows (seen places)",
            "AHSync's data/external/foreverdb-api/latest or [build.foreverdb_api]",
        ),
    )
    return [
        f"the Forever build has no {what} on this machine ({where}): the packs lose what it gives"
        for ok, what, where in checks
        if not ok
    ]


FOREVERDB_API = ROOT / "ahsync" / "data" / "external" / "foreverdb-api" / "latest"


def _default_api() -> Path | None:
    """AHSync's last complete fetch of ForeverDB's API, when there is one."""
    return FOREVERDB_API if (FOREVERDB_API / "quests.json").is_file() else None


def _tdb_dump(build: dict) -> Path | None:
    """[build.tdb]'s dump when it exists: a path, or the `retail` key the retail builds read it
    from until 15.11.2026 (an install.toml of those days names it so); Forever reads its long
    quest texts from it when [build.tdb_texts] names none."""
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


def installed_build(client_dir: Path) -> str | None:
    """The Forever build in `.build.info`, in the client folder or the one above it (the desktop
    keeps it above `_forever_`, the notebook's mirror at its root); None without one."""
    for folder in (client_dir, client_dir.parent):
        info = folder / ".build.info"
        if not info.is_file():
            continue
        rows = info.read_text(encoding="utf-8").splitlines()
        head = [c.split("!")[0] for c in rows[0].split("|")] if rows else []
        for row in rows[1:]:
            cells = dict(zip(head, row.split("|"), strict=False))
            if cells.get("Product") == "wowf" and cells.get("Version"):
                return cells["Version"]
    return None


def engine_prefix(client_dir: Path, dumps: Path | None = None) -> tuple[str, str | None]:
    """`[build.dump_prefix]` "auto" (and its absence): the dumps of the client's own build,
    f<build>, which tools/engine.py writes on every build (plan-data-quality.md E2 to E4).
    Without them, the newest older set, with a note saying so. -> (prefix, note or None)."""
    dumps = dumps or DUMPS
    build = installed_build(client_dir)
    if build is None:
        return DEFAULT_PREFIX["forever"], "no .build.info beside the client: the beta's dumps"
    number = int(build.rsplit(".", 1)[-1])
    if (dumps / f"f{number}_ItemSparse.json").is_file() and (
        dumps / f"f{number}_Map.json"
    ).is_file():
        return f"f{number}", None
    older = sorted(
        int(p.name[1 : -len("_Map.json")])
        for p in dumps.glob("f*_Map.json")
        if p.name[1 : -len("_Map.json")].isdigit() and int(p.name[1 : -len("_Map.json")]) < number
    )
    if not older:
        return DEFAULT_PREFIX["forever"], f"no engine dumps for {build} or before: the beta's"
    return f"f{older[-1]}", f"no engine dumps for {build} yet: built on f{older[-1]}"


PROBE_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-forever-(\d+)\.lua$")


def engine_probe(
    client_dir: Path, folders: tuple[Path, ...] | None = None
) -> tuple[Path | None, str | None]:
    """`[build.probe]` "auto": the newest probe record of the client's own build, from the
    records tools/engine.py imports (.local/probe) and the kept ones (data/probe); else the
    newest of an older build, with a note (plan-data-quality.md E5, E7). -> (path, note)."""
    folders = folders or (ROOT / ".local" / "probe", ROOT / "data" / "probe")
    found = []
    for folder in folders:
        for path in folder.glob("*-forever-*.lua") if folder.is_dir() else ():
            m = PROBE_NAME.match(path.name)
            if m:
                found.append((int(m.group(2)), m.group(1), path))
    if not found:
        return None, "no probe record: the build's checks against the game are missing"
    build = installed_build(client_dir)
    number = int(build.rsplit(".", 1)[-1]) if build else None
    own = [f for f in found if f[0] == number]
    if own:
        return max(own)[2], None
    newest = max(found)
    return newest[2], (
        f"the probe is of build {newest[0]} ({newest[1]}), the client {build or '?'}: "
        "log in once with Bastians_Probe"
    )


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
    pinned = str(build.get("dump_prefix", {}).get(client, "auto"))
    prefix_note = None
    if pinned == "auto":
        prefix, prefix_note = engine_prefix(Path(clients[client]))
    else:
        prefix = pinned

    def optional(key: str) -> Path | None:
        """A path for every client (string) or per client (a table keyed by the client)."""
        value = build.get(key)
        if isinstance(value, dict):
            value = value.get(client)
        if not value:
            return None
        path = Path(str(value))
        return path if path.is_absolute() else ROOT / path

    probe, probe_note = optional("probe"), None
    raw_probe = build.get("probe")
    if (raw_probe.get(client) if isinstance(raw_probe, dict) else raw_probe) == "auto":
        probe, probe_note = engine_probe(Path(clients[client]))

    # the source addons can live outside the client (24.10.2026: the Forever beta was uninstalled,
    # its EverythingQuests, ForeverDB and QuestieDB are kept in .local/sources/forever)
    sources = optional("sources")
    if sources is not None:
        if not sources.is_dir():
            raise BuildClientError(f"[build.sources] {client}: {sources} does not exist")
        addons = sources
    return BuildInputs(
        client=client,
        addons=addons,
        prefix=prefix,
        prefix_note=prefix_note,
        cmangos=optional("cmangos"),
        ground_truth=optional("ground_truth"),
        export=optional("export"),
        probe=probe,
        probe_note=probe_note,
        tdb_texts=optional("tdb_texts") or _tdb_dump(build),
        l10n=optional("l10n") or _default_l10n(client),
        floor_art=DUMPS if (DUMPS / "retail_UiMapArtTile.json").is_file() else None,
        listfile=LISTFILE if LISTFILE.is_file() else None,
        foreverdb_api=optional("foreverdb_api") or _default_api(),
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
    if inputs.tdb_texts:
        data += ["--tdb-texts", str(inputs.tdb_texts)]
    if inputs.l10n:
        data += ["--l10n", str(inputs.l10n)]
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
    sent = data_update.last_built(data_update.read_ledger(data_update.LEDGER))
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
    args = parser.parse_args(argv)
    try:
        inputs = read_inputs(args.client, args.config)
    except BuildClientError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    if inputs.prefix_note:
        print(f"warning: {inputs.prefix_note}", flush=True)
    if inputs.probe_note:
        print(f"warning: {inputs.probe_note}", flush=True)
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
    if not args.dry_run:
        import book_art

        pictures = book_art.install(art, args.out, front=book_art.FRONT)
        print(f"book art: {len(pictures)} pictures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
