"""The engine step: every Forever client build and hotfix push dumped, compared and handed on.

ADR 0039 (H2, H3) and plan-data-quality.md E2 to E4. The desktop's hourly task
(`tools/daily.py --mirror`) runs it before the mirror's push; it can also run by hand.

Usage: python tools/engine.py [--force] [--dry-run] [--no-send]

In order, each step one line:

1. The installed build from the client's `.build.info` (product `wowf`).
2. Nothing while a game client runs: clientdump cannot read the archives then (ADR 0039).
3. The hotfix cache (`_forever_/Cache/ADB/enUS/DBCache.bin`): its sha256 against the last one
   used. When it changed, one small table is dumped with it to read the cache's build and highest
   push; a cache of another build is not applied (clientdump refuses it).
4. A dump when the build has no set yet, or the push grew (or `--force`): every table the build
   reads (`TABLES`) under the prefix `f<build>` in `.local/out`, written to a temp folder first and
   moved in only when every table succeeded. The hotfixes go into the tables in the cache's
   language only: an English cache over the German item table turned 1,522 German names English
   (measured 15.11.2026), so the other languages' name tables come from the files. The cache used
   is kept as `.local/hotfixes/forever/<build>/<push>.bin`, so a set can be dumped again.
5. The comparison with the set before, table by table (rows added, removed, changed), as
   `.local/engine/forever-<build>-<push>.md`; its first line says what needs a rebuild.
6. The set and the state to the notebook (tar over ssh), whose build takes the same prefix.
7. The map's tile lists and overview textures of the build (`map_art_step`), once per build:
   the release's cut of the map needs them by the same prefix.

The state is `.local/out/engine-forever.json`: build, prefix, push, sha256, the times of the dump
and the send, the prefix before.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import client_tables

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"
DUMPS = LOCAL / "out"
STATE = DUMPS / "engine-forever.json"
RECORDS = LOCAL / "engine"
HOTFIX_COPIES = LOCAL / "hotfixes" / "forever"
CACHE_LANGUAGE = "enUS"  # the only cache on this machine (ADR 0039, open question 6)
TARGET = "nbb"  # the desktop's ssh alias for the service user on the notebook
NOTEBOOK_OUT = "src/Bastians-WoW-Forever-Addons/.local/out"  # under the service user's home
PROBES = LOCAL / "probe"  # the probe's records, one per day and build (E5)
NOTEBOOK_PROBES = "src/Bastians-WoW-Forever-Addons/.local/probe"
# a run the probe finished by itself for this build (Bastians_Probe `db.auto`, E5)
AUTO_RE = re.compile(r'\["auto"\]\s*=\s*\{[^}]*?\["build"\]\s*=\s*"(\d+)"', re.S)
META_BUILD_RE = re.compile(r'\["meta"\]\s*=\s*\{[^}]*?\["build"\]\s*=\s*"(\d+)"', re.S)

# Every table the Forever build reads: the map, area, travel and creature tables
# (pipeline/bastians_build/load.py, mapart_art.py, by the dump prefix) and the client tables
# (sources/client_tables.py), the name tables also in every installed text language.
MAP_TABLES = (
    "AreaTable",
    "ContentTuning",
    "Creature",
    "CreatureDifficulty",
    "FactionTemplate",
    "LiquidType",
    "Map",
    "QuestV2CliTask",
    "TaxiNodes",
    "TaxiPath",
    "TaxiPathNode",
    "UiMap",
    "UiMapArt",
    "UiMapArtStyleLayer",
    "UiMapArtTile",
    "UiMapAssignment",
    "UiMapXMapArt",
    "WorldMapOverlay",
    "WorldMapOverlayTile",
)
TABLES = MAP_TABLES + tuple(client_tables.TABLES)
LOCALIZED = tuple(client_tables.LOCALIZED)
# what a changed table means for the slow builds that stay manual (ADR 0039, step 3). Not Map or
# AreaTable: the hotfixes of 70938 add 5 maps and 29 areas (Forever's own instances and places)
# and change no pack the map art or the network reads (measured 15.11.2026); a changed terrain
# shows in the minimap tile lists, which `tools/mapart_extract.py` compares
REBUILD = {
    "map art": (
        "UiMap",
        "UiMapArt",
        "UiMapArtTile",
        "UiMapXMapArt",
        "WorldMapOverlay",
        "WorldMapOverlayTile",
        "UiMapAssignment",
    ),
    "the walk network": ("TaxiNodes", "TaxiPath", "TaxiPathNode"),
}
PROBE_TABLE = "Map"  # small: dumped first to read the files' build and the cache's push

Runner = Callable[..., subprocess.CompletedProcess]


@dataclass
class Cache:
    """The hotfix cache as one dump with it reported it."""

    build: int | None
    push: int | None
    sha256: str


@dataclass
class Result:
    lines: list[str] = field(default_factory=list)
    dumped: str | None = None  # the prefix written, when a set was dumped
    failed: bool = False


def prefix_of(build: str) -> str:
    """1.60.1.70938 -> f70938, the prefix `[build.dump_prefix]` names."""
    return "f" + build.rsplit(".", 1)[-1]


def names(locales: list[str]) -> list[str]:
    """The file names of one set, without the prefix: `Map.json`, `ItemSparse.deDE.json`."""
    out = [f"{t}.json" for t in TABLES]
    out += [f"{t}.{loc}.json" for loc in locales for t in LOCALIZED]
    return sorted(out)


def complete(dumps: Path, prefix: str, locales: list[str]) -> bool:
    return all((dumps / f"{prefix}_{n}").is_file() for n in names(locales))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def game_running() -> bool:
    """Any WoW client of the shared Data folder: one locks the archives (ADR 0039)."""
    done = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, check=False
    )
    for line in done.stdout.splitlines():
        image = line.split(",", 1)[0].strip('"').lower()
        if image.startswith("wow") and image.endswith(".exe"):
            return True
    return False


def dump_table(
    install: Path,
    table: str,
    out: Path,
    locale: str | None,
    hotfixes: Path | None,
    run: Runner = subprocess.run,
) -> bool:
    cmd = [str(client_tables.EXE), "db2", "--install", str(install), "--table", table]
    cmd += ["--out", str(out)]
    if client_tables.DEFS.is_dir():
        cmd += ["--defs", str(client_tables.DEFS)]
    if locale:
        cmd += ["--locale", locale]
    if hotfixes is not None:
        cmd += ["--hotfixes", str(hotfixes)]
    done = run(cmd, capture_output=True, text=True, cwd=ROOT, check=False)
    return done.returncode == 0 and out.is_file()


def read_meta(path: Path) -> dict:
    """A dump's head: `build` and, with a cache applied, `hotfixes` (build, highestPush, ...)."""
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: v for k, v in data.items() if k not in ("rows", "columns")}


def cache_of(install: Path, cache_path: Path, tmp: Path, run: Runner) -> tuple[str, Cache | None]:
    """The files' build (from a dump of PROBE_TABLE) and the cache when it applies to them."""
    tmp.mkdir(parents=True, exist_ok=True)
    plain = tmp / "plain.json"
    if not dump_table(install, PROBE_TABLE, plain, None, None, run):
        raise RuntimeError(f"clientdump could not read {PROBE_TABLE} from {install}")
    files_build = str(read_meta(plain).get("build") or "")
    if not cache_path.is_file():
        return files_build, None
    digest = sha256(cache_path)
    hot = tmp / "hot.json"
    if not dump_table(install, PROBE_TABLE, hot, None, cache_path, run):
        return files_build, Cache(None, None, digest)  # another build's cache: refused
    meta = read_meta(hot).get("hotfixes") or {}
    return files_build, Cache(meta.get("build"), meta.get("highestPush"), digest)


def previous_prefix(dumps: Path, prefix: str) -> str | None:
    """The newest other build's prefix in the folder (by `<prefix>_Map.json`), below this one."""
    number = int(prefix[1:])
    found = []
    for path in dumps.glob("f*_Map.json"):
        digits = path.name[1 : -len("_Map.json")]
        if digits.isdigit() and int(digits) < number:
            found.append(int(digits))
    return f"f{max(found)}" if found else None


def compare(old_dir: Path, old: str, new_dir: Path, new: str, locales: list[str]) -> list[dict]:
    """Per table of the set: rows before and after, added, removed, changed (by the ID column);
    a table one side lacks is left out."""
    out = []
    for name in names(locales):
        a, b = old_dir / f"{old}_{name}", new_dir / f"{new}_{name}"
        if not (a.is_file() and b.is_file()):
            continue
        ra, rb = _rows(a), _rows(b)
        out.append(
            {
                "table": name[: -len(".json")],
                "before": len(ra),
                "after": len(rb),
                "added": len(rb.keys() - ra.keys()),
                "removed": len(ra.keys() - rb.keys()),
                "changed": sum(1 for k in ra.keys() & rb.keys() if ra[k] != rb[k]),
            }
        )
    return out


def _rows(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    cols = data.get("columns") or []
    rows = data.get("rows") or []
    if isinstance(rows, dict):
        rows = list(rows.values())
    key = "ID" if "ID" in cols else (cols[0] if cols else None)
    out: dict[str, str] = {}
    for n, row in enumerate(rows):
        rec = row if isinstance(row, dict) else dict(zip(cols, row, strict=False))
        k = str(rec.get(key, n)) if key else str(n)
        while k in out:
            k += "#"
        out[k] = json.dumps(rec, sort_keys=True, ensure_ascii=False)
    return out


def rebuilds(diff: list[dict]) -> list[str]:
    """Which slow builds a comparison asks for: a changed table they read."""
    moved = {d["table"] for d in diff if d["added"] or d["removed"] or d["changed"]}
    return [what for what, tables in REBUILD.items() if moved & set(tables)]


def record(diff: list[dict], old: str | None, new: str, build: str, cache: Cache | None) -> str:
    """The comparison as Markdown, for the engine record (plan-data-quality.md E8)."""
    push = cache.push if cache and cache.build is not None else None
    need = rebuilds(diff) if old else []
    lines = [
        f"# Engine {build}" + (f", hotfix push {push}" if push else ", no hotfixes"),
        "",
        "Needs a rebuild: " + (", ".join(need) if need else "nothing"),
        "",
        f"Dumped {datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} as `{new}`"
        + (
            f", compared with the set it replaces (`{old}`)."
            if old == new
            else (f", compared with `{old}`." if old else ", nothing to compare with.")
        ),
        "",
    ]
    if diff:
        lines += ["| Table | rows | added | removed | changed |", "|---|---|---|---|---|"]
        for d in diff:
            if d["added"] or d["removed"] or d["changed"] or d["before"] != d["after"]:
                lines.append(
                    f"| {d['table']} | {d['before']} -> {d['after']} | {d['added']} | "
                    f"{d['removed']} | {d['changed']} |"
                )
        same = sum(1 for d in diff if not (d["added"] or d["removed"] or d["changed"]))
        lines += ["", f"{same} of {len(diff)} tables identical."]
    return "\n".join(lines) + "\n"


def send(dumps: Path, prefix: str, state: Path, run: Runner = subprocess.run) -> int:
    """The set and the state into the notebook's `.local/out` (one ssh connection)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for path in sorted(dumps.glob(f"{prefix}_*.json")):
            tar.add(path, arcname=path.name)
        tar.add(state, arcname=state.name)
    # -m: the files take the notebook's time; its clock ran 90 s behind (15.11.2026)
    script = f"mkdir -p {NOTEBOOK_OUT} && tar -xmf - -C {NOTEBOOK_OUT}"
    done = run(["ssh", "-o", "BatchMode=yes", TARGET, script], input=buf.getvalue(), check=False)
    return done.returncode


def probe_step(
    install: Path,
    probes: Path = PROBES,
    *,
    do_send: bool = True,
    run: Runner = subprocess.run,
) -> list[str]:
    """The probe's record of the live build, when the probe finished its own run for it (E5):
    copied to `probes` as `<date>-forever-<build>.lua` and sent to the notebook. A record the
    probe has not finished, of another client, or already copied is left alone."""
    import probe_import
    from install import InstallError

    try:
        source = probe_import.find_saved_variables(install)
        text = source.read_text(encoding="utf-8")
        meta = probe_import.read_meta(text)
    except (InstallError, OSError) as err:
        return [f"engine: no probe record to import ({str(err).splitlines()[0][:80]})"]
    done, current = AUTO_RE.search(text), META_BUILD_RE.search(text)
    build = current.group(1) if current else meta["build"]
    if meta["client"] != "forever" or not done or done.group(1) != build or meta["build"] != build:
        return [f"engine: the probe has no finished run of build {build} yet"]
    target, changed = probe_import.import_probe(source, probes)
    if not changed:
        return []
    lines = [f"engine: the probe's record {target.name} imported"]
    if do_send:
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as tar:
            tar.add(target, arcname=target.name)
        script = f"mkdir -p {NOTEBOOK_PROBES} && tar -xmf - -C {NOTEBOOK_PROBES}"
        sent = run(
            ["ssh", "-o", "BatchMode=yes", TARGET, script], input=buf.getvalue(), check=False
        )
        lines.append(
            f"engine: the probe's record sent to {TARGET}"
            if sent.returncode == 0
            else f"engine: the probe's record was not sent (ssh exited with {sent.returncode})"
        )
    return lines


def map_art_step(
    build_info: Path,
    *,
    dumps: Path = DUMPS,
    run: Runner = subprocess.run,
    running: Callable[[], bool] = game_running,
    client_build: Callable[[Path], str | None] | None = None,
) -> list[str]:
    """The map's tile lists and overview textures of the installed build, once per build ->
    its lines. `tools/mapart_extract.py` writes them as `mm_<prefix>` and `ov_<prefix>` beside the
    tables; the build of the map and its pictures reads them by the same prefix. Until 20.11.2026
    a person ran it for every client build: with 70959 nobody had, and the release cut did not
    boot ("listed file missing: Bastians_Map/Generated/MinimapTiles.lua"). It takes 24 seconds
    for the three continents (measured that day). It waits for the build's tables (the step
    before) and for the game to close; a set that is there is left alone."""
    if client_build is None:
        import sources_update

        client_build = sources_update.client_build
    build = client_build(build_info)
    if not build:
        return []
    prefix = prefix_of(build)
    tiles, overview = dumps / f"mm_{prefix}", dumps / f"ov_{prefix}"
    if any(tiles.glob("*_tiles.txt")) and any(overview.glob("*_art.json")):
        return []
    if not (dumps / f"{prefix}_Map.json").is_file():
        return []  # the tables first: the next hour
    if running():
        return [f"engine: the map's tile lists of {prefix} wait for the game client to close"]
    done = run(
        [
            sys.executable,
            str(ROOT / "tools" / "mapart_extract.py"),
            "--client",
            "forever",
            "--prefix",
            prefix,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if done.returncode:
        last = ((done.stderr or "") + (done.stdout or "")).strip().splitlines()[-1:] or ["?"]
        return [f"engine: the map's tile lists of {prefix} failed: {last[0][:200]}"]
    return [f"engine: the map's tile lists and overview of {prefix} extracted"]


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError, ValueError:
        return {}


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def step(
    *,
    install: Path,
    build_info: Path,
    dumps: Path = DUMPS,
    state_path: Path = STATE,
    records: Path = RECORDS,
    copies: Path = HOTFIX_COPIES,
    force: bool = False,
    dry_run: bool = False,
    do_send: bool = True,
    run: Runner = subprocess.run,
    running: Callable[[], bool] = game_running,
    client_build: Callable[[Path], str | None] | None = None,
) -> Result:
    """The step as the docstring at the top tells it; -> its lines."""
    res = Result()
    if client_build is None:
        import sources_update

        client_build = sources_update.client_build
    build = client_build(build_info)
    if not build:
        res.lines.append(f"engine: no Forever build in {build_info}")
        return res
    prefix = prefix_of(build)
    locales = [loc for loc in client_tables.text_locales(install, "wowf") if loc != CACHE_LANGUAGE]
    state = load_state(state_path)
    have = complete(dumps, prefix, locales)
    if running():
        res.lines.append(f"engine: {build}, a game client runs; dumps wait for it to close")
        return res
    cache_path = install / "Cache" / "ADB" / CACHE_LANGUAGE / "DBCache.bin"
    if have and not force and state.get("prefix") == prefix:
        if not cache_path.is_file():
            res.lines.append(f"engine: {build} as {prefix}, no hotfix cache")
            return res
        if sha256(cache_path) == state.get("sha256"):
            res.lines.append(f"engine: {build} as {prefix}, hotfix cache unchanged")
            return res
    tmp = dumps / f".engine-{prefix}.tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    try:
        files_build, cache = cache_of(install, cache_path, tmp, run)
    except RuntimeError as err:
        res.lines.append(f"engine: {err}")
        res.failed = True
        return res
    if files_build != build:
        res.lines.append(
            f"engine: .build.info says {build}, the files are {files_build or '?'}: "
            "the client is patching; the next hour tries again"
        )
        shutil.rmtree(tmp, ignore_errors=True)
        return res
    applies = cache is not None and cache.build is not None and str(cache.build) == prefix[1:]
    push = cache.push if applies and cache else None
    grew = push is not None and push > int(state.get("push") or 0)
    if have and not force and state.get("prefix") == prefix and not grew:
        state["sha256"] = cache.sha256 if cache else None
        if not dry_run:
            write_json(state_path, state)
        if applies:
            words = f"hotfix cache rewritten, push {push} not new"
        else:
            words = f"the hotfix cache is of build {cache.build if cache else '?'}, not applied"
        res.lines.append(f"engine: {build} as {prefix}, {words}")
        shutil.rmtree(tmp, ignore_errors=True)
        return res
    if dry_run:
        res.lines.append(f"engine: would dump {build} as {prefix} (push {push}) (dry run)")
        shutil.rmtree(tmp, ignore_errors=True)
        return res
    hotfixes = None
    if applies and cache:
        hotfixes = copies / build / f"{push}.bin"
        hotfixes.parent.mkdir(parents=True, exist_ok=True)
        if not hotfixes.is_file():
            shutil.copyfile(cache_path, hotfixes)
    failed = []
    for name in names(locales):
        table, _, rest = name[: -len(".json")].partition(".")
        locale = rest or None
        ok = dump_table(
            install, table, tmp / f"{prefix}_{name}", locale, None if locale else hotfixes, run
        )
        if not ok:
            failed.append(name)
    if failed:
        shown = ", ".join(failed[:4])
        res.lines.append(f"engine: {len(failed)} tables failed ({shown}); kept the set before")
        res.failed = True
        return res
    # the comparison before the move: a new push of the same build replaces that build's set
    old = prefix if have else previous_prefix(dumps, prefix)
    diff = compare(dumps, old, tmp, prefix, locales) if old else []
    for path in sorted(tmp.glob(f"{prefix}_*.json")):
        path.replace(dumps / path.name)
    shutil.rmtree(tmp, ignore_errors=True)
    stamp = f"{build}-{push}" if push else build
    records.mkdir(parents=True, exist_ok=True)
    (records / f"forever-{stamp}.md").write_text(
        record(diff, old, prefix, build, cache if applies else None), encoding="utf-8"
    )
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    state = {
        "build": build,
        "prefix": prefix,
        "previous": old,
        "push": push,
        "sha256": cache.sha256 if cache else None,
        "hotfixes": hotfixes is not None,
        "dumped": now,
        "sent": None,
    }
    write_json(state_path, state)
    res.dumped = prefix
    moved = [d["table"] for d in diff if d["added"] or d["removed"] or d["changed"]]
    res.lines.append(
        f"engine: dumped {build} as {prefix}"
        + (f" with hotfix push {push}" if push else " without hotfixes")
        + (f"; against {old}: {len(moved)} of {len(diff)} tables changed" if old else "")
        + (f"; needs a rebuild: {', '.join(rebuilds(diff))}" if rebuilds(diff) else "")
    )
    if do_send:
        code = send(dumps, prefix, state_path, run)
        if code:
            res.lines.append(f"engine: the send to {TARGET} failed (ssh exited with {code})")
            res.failed = True
        else:
            state["sent"] = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            write_json(state_path, state)
            res.lines.append(f"engine: {prefix} sent to {TARGET}")
    return res


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="dump even when nothing is new")
    parser.add_argument("--dry-run", action="store_true", help="say what would be dumped")
    parser.add_argument("--no-send", action="store_true", help="do not send to the notebook")
    args = parser.parse_args(argv)
    import sources_update

    install = client_tables.install_of("forever")
    res = step(
        install=install,
        build_info=sources_update.BUILD_INFO,
        force=args.force,
        dry_run=args.dry_run,
        do_send=not args.no_send,
    )
    lines = list(res.lines)
    if not args.dry_run:
        lines += map_art_step(sources_update.BUILD_INFO)
        lines += probe_step(install, do_send=not args.no_send)
    print("\n".join(lines))
    return 1 if res.failed else 0


if __name__ == "__main__":
    sys.exit(main())
