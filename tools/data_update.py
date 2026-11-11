"""The daily data edition (ADR 0019, strategies-design.md section 7): the newest AHSync export
becomes a new version of the Bastian's Data project, zipped, booted on the mock and ready for
CurseForge. The suite's apps are not uploaded: they change only with the code (ADR 0020).

Usage: python tools/data_update.py [--export <dir>] [--out build/data] [--send]

1. Builds the Forever data packs (tools/build_client.py --skip-mapart into `<out>/packs`): the
   game data, the market prices of the export, the book with the rumours its pages rest on and
   the Rumour mill, and the candidate report `build/book-candidates.md` for choosing new pages.
   The build gets the book's state of the last sent edition and writes What's new entries for
   what changed since (pipeline book_news.py: new travellers, mill rumours).
2. Compares the data project's files (the packs, the loader's and the packs' code, without the
   TOC version line) with the last edition in `.local/data-editions.json`. Unchanged and sent:
   says so and stops, so the command can run as often as one likes. Changed: a new edition,
   numbered per day; its book state goes to `.local/book-states/`.
   A pack whose rows fell by more than a tenth since the last sent edition holds the run
   (catalog review B2, 07.11.2026: a source that changed shape would ship a thin pack); the
   build report's counts ride with the edition, `--allow-drift` ships a fall that is right.
   The quest steps' numbers ride with it too (the build's `links-forever.json`, data.md "The
   count and the watch"): steps that fell by a tenth, or steps without a place or placed by
   Classic knowledge alone that rose by a tenth, hold the run the same way. A smaller rise
   holds nothing: the watch says it (tools/ops/health.py `links`).
3. Zips the whole install, the suite and its data (tools/release.py into `<out>/release`), boots it
   on the WoW mock (with the Suite as it was last sent when `.local/released/forever/` keeps it:
   what players run), and writes the Data project's CurseForge file with the version
   `<Data's TOC version>+data.<YYYYMMDD>.<n>` and a changelog: What's new (book.toml's entries
   and the build's), the release notes of Data's commits since the last sent edition (ADR 0020).
4. `--send` uploads that file (tools/curseforge.py: the token from CF_API_KEY or
   ~/.curseforge/.secrets, never in the repo). CurseForge refuses it, and so does this command,
   while the project id or the slug is unknown (tools/curseforge.toml).

With the read API's key (tools/curseforge.py `core_key`) the edition also carries the projects'
CurseForge download counts for the About page (`Bastians_Data/Generated/Downloads.lua`, written
after the edition's hash: a new count alone makes no new edition), and `confirm` asks whether a
sent file went live (tools/daily.py after its upload). Without the key both say nothing.

The ledger records each edition (its commit, the export it was built from and that export's
fingerprint) and whether it was sent: an edition that was not sent is planned again by the next
run. The daily data is Forever's (the book is written for Forever, the export's markets are
Forever's); retail's data ships with the suite's releases. tools/daily.py runs this every day.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.error
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

import book_art
import build_client
import curseforge
import release
import release_notes

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / ".local" / "data-editions.json"
LOCAL_ART = ROOT / ".local" / "book-art" / "current"  # the approved pictures until AHSync's
BOOK_STATES = ROOT / ".local" / "book-states"
BOOK_TOML = ROOT / "content" / "strategies" / "book.toml"
PROJECT = "Bastians_Data"  # what is uploaded daily
INSTALL = "Bastians_Suite"  # what a player installs with it: booted on the mock
CLIENT = "forever"
# what a Data build reads from this repository besides the export (the skip in tools/daily.py)
INPUTS = (
    "pipeline",
    "content/strategies",
    "tools/build_client.py",
    "tools/data_update.py",
    "tools/release.py",
    "tools/curseforge.py",
    "tools/curseforge.toml",
)


class DataUpdateError(Exception):
    pass


# the About page's download counts: a generated file of the loader, outside
# the edition's hash
DOWNLOADS = Path("Bastians_Data") / release.GENERATED / "Downloads.lua"
CONFIRM_WAIT_S = 10 * 60  # how long a run waits for CurseForge to take a sent file
CONFIRM_STEP_S = 30


# what Forever's packs are built from: the build skips a missing source without a word, so the
# daily edition refuses instead of shipping packs without their quests and NPCs (24.10.2026)
SOURCES = (
    "EverythingQuests",
    "ForeverDB/Data",
    "QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua",
    "Questie/Database/Corrections/QuestieQuestBlacklist.lua",
)


def missing_sources(addons: Path) -> list[str]:
    return [s for s in SOURCES if not (addons / s).exists()]


def project_folders(config: dict, project: str) -> list[str]:
    """The project's folders and those of every project it requires, recursively: what a player
    installs with it, so the boot on the mock tests the real install."""
    seen: list[str] = []
    folders: list[str] = []

    def visit(name: str) -> None:
        if name in seen or name not in config["projects"]:
            return
        seen.append(name)
        p = config["projects"][name]
        folders.extend(f for f in p["folders"] if f not in folders)
        for dep in p.get("required", []):
            visit(dep)

    visit(project)
    return folders


def input_paths(config: dict) -> list[str]:
    return [*INPUTS, *(f"addons/{f}" for f in config["projects"][PROJECT]["folders"])]


def data_hash(packs: Path, folders: list[str], addons_dir: Path = release.ADDONS_DIR) -> str:
    """One hash over what a player gets from the data project (path and bytes, sorted): every
    generated file and the folders' own code, the TOCs without their version line, so a changed
    pack or a loader fix makes a new edition, a version bump alone none."""
    digest = hashlib.sha256()
    generated = sorted(
        p
        for folder in folders
        for p in (packs / folder / release.GENERATED).rglob("*")
        # the packs and the book's pictures (Generated/Art); not the download counts
        if p.is_file() and p.relative_to(packs) != DOWNLOADS
    )
    if not any(p.suffix == ".lua" for p in generated):
        raise DataUpdateError(f"the build wrote no generated files under {packs}")
    files: list[tuple[str, bytes]] = [
        (p.relative_to(packs).as_posix(), p.read_bytes()) for p in generated
    ]
    for folder in folders:
        root = addons_dir / folder
        if not root.is_dir():
            continue
        for p in sorted(root.rglob("*")):
            rel = p.relative_to(root)
            if (
                not p.is_file()
                or rel.parts[0] == release.GENERATED
                or not release.shippable(p, root)
            ):
                continue
            data = p.read_bytes()
            if p.suffix == ".toc":
                data = b"\n".join(
                    line for line in data.splitlines() if not line.startswith(b"## Version:")
                )
            files.append((f"{folder}/{rel.as_posix()}", data))
    for name, data in sorted(files):
        digest.update(name.encode() + b"\0")
        digest.update(data)
    return digest.hexdigest()


def read_ledger(path: Path) -> dict:
    if not path.is_file():
        return {"editions": []}
    return json.loads(path.read_text(encoding="utf-8"))


def write_ledger(path: Path, ledger: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(
        json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    tmp.replace(path)


def next_edition(ledger: dict, sha256: str, today: str) -> tuple[dict, bool]:
    """The edition for data with this hash: the last one when nothing changed, else a new one,
    numbered from 1 per day. -> (edition, is_new)."""
    editions = ledger["editions"]
    if editions and editions[-1]["sha256"] == sha256:
        return editions[-1], False
    n = 1 + sum(1 for e in editions if e["date"] == today)
    return {"date": today, "n": n, "sha256": sha256, "sent": False}, True


def last_sent(ledger: dict) -> dict | None:
    sent = [e for e in ledger["editions"] if e.get("sent")]
    return sent[-1] if sent else None


def version_suffix(edition: dict) -> str:
    return f"+data.{edition['date'].replace('-', '')}.{edition['n']}"


def changelog(
    book: dict, seen: set[str], export_id: str | None, notes: list[str] | tuple = ()
) -> str:
    """Markdown for the CurseForge file: the What's new entries (`book["news"]`: book.toml's and
    the build's) the last sent edition did not have (`seen`, their texts), newest first, the
    release notes of Data's commits since that edition, and where the prices and rumours come from.
    """
    news = [n for n in book.get("news", []) if n["text"] not in seen]
    lines = [
        f"- {n['date']}: {n['text']}" for n in sorted(news, key=lambda n: n["date"], reverse=True)
    ]
    lines += [f"- {note}" for note in notes]
    if not lines:
        lines = ["- The prices, the rumours and their sources are up to date."]
    if export_id:
        lines.append(f"\nPrices and rumours from the AHSync export {export_id}.")
    return "Bastian's Data, a new edition.\n\n" + "\n".join(lines) + "\n"


def seen_news(ledger: dict) -> set[str]:
    """The What's new texts the last sent edition carried."""
    sent = last_sent(ledger)
    return set(sent.get("news", [])) if sent else set()


def export_folder(export: Path) -> Path:
    """The dated folder of an export root (its LATEST), or the folder itself."""
    latest = export / "LATEST"
    if latest.is_file():
        return export / latest.read_text(encoding="utf-8").strip()
    return export


def art_folder(export: Path | None, local: Path | None = None) -> Path | None:
    """Where the book's pictures come from: the export's art/ when it brings pictures (AHSync,
    content/strategies/art), else the owner's approved set in `.local/book-art/current` (until
    AHSync's generator runs, 24.10.2026), else none."""
    local = LOCAL_ART if local is None else local  # looked up now: the tests point it elsewhere
    for folder in (export_folder(export) / "art" if export else None, local):
        pictures = (
            folder is not None
            and folder.is_dir()
            and any(p.suffix.lower() in book_art.SOURCES for p in folder.iterdir())
        )
        if pictures:
            return folder
    return None


def export_id(export: Path | None) -> str | None:
    if export is None:
        return None
    return export_folder(export).name


def export_fingerprint(export: Path) -> str | None:
    """A hash over the export's tables (their sha256 in the manifest), so an export with a new
    date but the same content counts as the same; None without a manifest."""
    manifest = export_folder(export) / "manifest.json"
    if not manifest.is_file():
        return None
    tables = json.loads(manifest.read_text(encoding="utf-8")).get("tables", [])
    text = "\n".join(sorted(f"{t.get('name')}:{t.get('sha256')}" for t in tables))
    return hashlib.sha256(text.encode()).hexdigest()


def data_notes(since: str | None, config: dict) -> list[str]:
    """The player sentences of Data's commits after `since` (ADR 0020), oldest first."""
    if not since:
        return []
    found = release_notes.commits(since, release_notes.track_paths(config, "data"))
    return [n.text for n in release_notes.player_notes(found)]


def stream(cmd: list[str], cwd: Path, env: dict | None = None) -> int:
    """Runs a command and prints its output line by line, so a log that wraps stdout keeps it
    (tools/daily.py). -> the exit code."""
    env = {**(env if env is not None else os.environ), "PYTHONIOENCODING": "utf-8"}
    with subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    ) as proc:
        assert proc.stdout is not None
        for line in proc.stdout:
            print(line.rstrip("\n"), flush=True)
    return proc.returncode


def foreign_files(
    config: dict,
    ledger: dict,
    transport: curseforge.Transport = curseforge._urlopen,
    key: str | None = None,
) -> list[str]:
    """The Data project's files on CurseForge that are newer than every file this machine's
    ledger knows: another machine uploaded too (plan-nightly-content.md F2: the desktop's task
    beside the notebook's, or a Suite release, which sends Data from the desktop's ledger). One
    line per file; [] without the read key, without a sent edition or when CurseForge does not
    answer. The read API lists a file only once it is approved, so a file sent minutes ago is
    not seen yet: this finds the second sender the next night, not the same minute."""
    key = key or curseforge.core_key()
    known = [int(e["file_id"]) for e in ledger.get("editions", []) if e.get("file_id")]
    if not key or not known:
        return []
    project = config["projects"][PROJECT]["id"]
    try:
        files = curseforge.core_get(f"/v1/mods/{project}/files?pageSize=20", key, transport)["data"]
        newer = sorted(
            (int(f["id"]), str(f.get("displayName") or f.get("fileName") or ""))
            for f in files
            if int(f["id"]) > max(known)
        )
    except (urllib.error.URLError, OSError, KeyError, TypeError, ValueError) as err:
        print(f"note: CurseForge's file list was not read: {err}")
        return []
    return [
        f"CurseForge has Data file {fid} ({name}) that this machine did not send: another "
        "machine uploads too, and its ledger and this one's now differ"
        for fid, name in newer
    ]


def downloads(
    config: dict,
    transport: curseforge.Transport = curseforge._urlopen,
    key: str | None = None,
    today: str | None = None,
) -> dict | None:
    """{"at", "suite", "data"}: the two projects' CurseForge download counts. None without the
    read API's key or when CurseForge does not answer (unknown is not zero: the About page says
    nothing)."""
    key = key or curseforge.core_key()
    if not key:
        return None
    try:
        counts = {
            name: curseforge.download_count(config["projects"][project]["id"], key, transport)
            for name, project in (("suite", INSTALL), ("data", PROJECT))
        }
    except (urllib.error.URLError, OSError, KeyError, TypeError, ValueError) as err:
        print(f"note: no download counts from CurseForge: {err}")
        return None
    return {"at": today or datetime.now(UTC).strftime("%Y-%m-%d"), **counts}


def write_downloads(packs: Path, counts: dict | None) -> Path | None:
    """`<packs>/Bastians_Data/Generated/Downloads.lua` with the counts, over the build's stub;
    without counts the stub stays (the loader's TOC lists the file)."""
    path = packs / DOWNLOADS
    if not counts:
        return None
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = f'at = "{counts["at"]}", suite = {int(counts["suite"])}, data = {int(counts["data"])}'
    text = "\n".join(
        [
            "-- GENERATED by tools/data_update.py, do not edit",
            f"-- CurseForge's download counts for {CLIENT}, read when the edition was built "
            "(the About page)",
            "local B = Bastians or {}",
            "Bastians = B",
            "B.deferred = B.deferred or {}",
            f'B.deferred[#B.deferred + 1] = {{ "Data.RegisterDownloads", {{ {entry} }} }}',
            "",
        ]
    )
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(path)
    return path


def confirm(
    file_id: object,
    config: dict | None = None,
    transport: curseforge.Transport = curseforge._urlopen,
    key: str | None = None,
    sleep: Callable[[float], None] = time.sleep,
    wait_s: float = CONFIRM_WAIT_S,
    step_s: float = CONFIRM_STEP_S,
) -> tuple[str, str]:
    """Whether CurseForge took a sent Data file: ("live" | "refused" | "pending" | "unknown", the
    words for the summary). Asks until it is live or refused, at most `wait_s`."""
    key = key or curseforge.core_key()
    if not key:
        return "unknown", "not checked: no key for CurseForge's read API (CF_CORE_API_KEY)"
    project_id = (config or curseforge.load_config())["projects"][PROJECT]["id"]
    waited = 0.0
    while True:
        try:
            status, available = curseforge.file_state(project_id, int(file_id), key, transport)
        except urllib.error.HTTPError as err:
            if err.code != 404:
                return "unknown", f"not checked: CurseForge did not answer ({err})"
            # The read API lists a file only once CurseForge approved it (measured 30.10.2026:
            # 404 right after the upload, approved and live 40 minutes later): not an error.
            status, available = None, False
            name = "not yet listed by CurseForge's read API (approval pending)"
        except (urllib.error.URLError, OSError, KeyError, TypeError, ValueError) as err:
            return "unknown", f"not checked: CurseForge did not answer ({err})"
        else:
            name = curseforge.FILE_STATUS.get(status, f"status {status}")
        if status in curseforge.LIVE and available:
            return "live", f"{name} and live"
        if status in curseforge.REFUSED:
            return "refused", f"REFUSED by CurseForge: {name}"
        if waited >= wait_s:
            return "pending", f"still {name} after {waited / 60:.0f} min; the next run asks again"
        sleep(step_s)
        waited += step_s


def mark_status(ledger_path: Path, file_id: object, state: str) -> None:
    """Writes what CurseForge said about a sent file into its edition (`live`: true once it was)."""
    ledger = read_ledger(ledger_path)
    for e in ledger["editions"]:
        if e.get("file_id") == file_id:
            e["curseforge"] = state
            if state == "live":
                e["live"] = True
    write_ledger(ledger_path, ledger)


NAV = Path("Bastians_Data_Nav") / release.GENERATED / "Nav.lua"


def run_build(inputs: build_client.BuildInputs, packs: Path) -> None:
    # the data packs and the walk network (the nav step): Bastian's Data ships both. 2.0.0 and
    # every release before went out without the network because only the first command ran
    # (06.11.2026); the stub the nav step writes without graphs is refused below
    started = time.time()
    for path in (REPORT, LINKS):
        (packs / path.name).unlink(missing_ok=True)  # never the last build's
    for cmd in build_client.commands(inputs, packs, skip_mapart=True):
        print("> " + " ".join(cmd[3:]), flush=True)
        code = stream(cmd, ROOT)
        if code:
            raise DataUpdateError(f"the {cmd[3]} build exited with {code}")
    place_report(REPORT, packs, started)
    place_report(LINKS, packs, started)


REPORT = ROOT / "build" / "report.md"  # where `bastians_build data` writes it (--report-dir)
LINKS = ROOT / "build" / f"links-{CLIENT}.json"  # the quest steps' numbers, beside the report


def place_report(report: Path, packs: Path, started: float) -> None:
    """Puts this build's report beside the packs, where the drift check reads it. Until
    10.11.2026 nothing did: the build wrote build/report.md, the check looked in the packs
    folder, said "not checked" and shipped. A report older than the build is another build's
    and is not taken."""
    if report.is_file() and report.stat().st_mtime >= started - 1:
        shutil.copyfile(report, packs / report.name)


DROP = (
    0.10  # a pack type whose rows fell by more than a tenth holds the edition (catalog review B2)
)
MIN_ROWS = 50  # under this many rows before, a fall is noise, not drift


def report_counts(packs: Path) -> dict[str, dict[str, int]]:
    """The record counts per pack and type from the build's report (`report.md` beside the packs,
    its Packs table), {} without one."""
    path = packs / "report.md"
    if not path.is_file():
        return {}
    out: dict[str, dict[str, int]] = {}
    in_packs = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            in_packs = line.strip() == "## Packs"
            continue
        if not in_packs or not line.startswith("| ") or line.startswith("| Pack"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 5:
            continue
        counts: dict[str, int] = {}
        for part in cells[4].split(","):
            m = re.match(r"^(\S+) (\d+)$", part.strip())
            if m:
                counts[m.group(1)] = int(m.group(2))
        if counts:
            out[cells[0]] = counts
    return out


def drift(old: dict | None, new: dict) -> tuple[list[str], list[str]]:
    """The row counts against the last sent edition's: (the falls that hold the edition, every
    change as a line). A type gone is a fall; a type under MIN_ROWS before never is."""
    held: list[str] = []
    lines: list[str] = []
    for pack in sorted(old or {}):
        for typ, before in sorted(old[pack].items()):
            now = new.get(pack, {}).get(typ, 0)
            if now != before:
                lines.append(f"{pack} {typ} {before} -> {now}")
            if before >= MIN_ROWS and now < before * (1 - DROP):
                held.append(f"{pack} {typ} {before} -> {now}")
    return held, lines


def check_drift(packs: Path, sent: dict | None, allow: bool) -> dict[str, dict[str, int]]:
    """Says every change of the row counts since the last sent edition and refuses a fall of more
    than a tenth unless `allow` (catalog review B2: a source that changed shape without notice
    would ship a thin pack otherwise). -> this build's counts, for the edition."""
    records = report_counts(packs)
    if not records:
        if sent and sent.get("records") and not allow:
            raise DataUpdateError(
                "no build report beside the packs although the last sent edition had one: the "
                "row counts cannot be checked (pass --allow-drift to ship without the check)"
            )
        print("drift: no build report beside the packs, the row counts were not checked")
        return records
    held, lines = drift(sent.get("records") if sent else None, records)
    for line in lines:
        print(f"drift: {line}")
    if held and not allow:
        raise DataUpdateError(
            "rows fell by more than a tenth since the last sent edition: "
            + "; ".join(held)
            + " (a source changed shape? pass --allow-drift when the fall is right)"
        )
    return records


# steps without a place, or placed by Classic knowledge alone, that rose by more than a tenth
# hold the edition (ADR 0073)
RISE = 0.10
# the build's numbers the edition keeps, and what each is called in a line
LINK_COUNTS = {
    "steps": "quest steps",
    "unplaced": "steps without a place",
    "classic": "Classic-only steps",
}


def link_counts(packs: Path) -> dict[str, int]:
    """The quest steps' numbers of this build (`links-forever.json` beside the packs): the
    steps, those without a place and the Classic debt; {} without the file."""
    try:
        data = json.loads((packs / LINKS.name).read_text(encoding="utf-8"))
    except OSError, ValueError:
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        name: data[name]
        for name in LINK_COUNTS
        if isinstance(data.get(name), int) and not isinstance(data[name], bool)
    }


def links_drift(old: dict | None, new: dict) -> tuple[list[str], list[str]]:
    """The quest steps' numbers against the last sent edition's: (the jumps that hold the
    edition, every change as a line). A jump is the resolver or a source gone wrong: the steps
    fell by more than a tenth, or the steps without a place or the Classic debt rose by more
    than a tenth. A number under MIN_ROWS before never holds. A smaller rise is the watch's
    alarm, not a stop (ADR 0073)."""
    held: list[str] = []
    lines: list[str] = []
    for name, words in LINK_COUNTS.items():
        before, now = (old or {}).get(name), new.get(name)
        if before is None or now is None or now == before:
            continue
        line = f"{words} {before} -> {now}"
        lines.append(line)
        fell = name == "steps" and now < before * (1 - DROP)
        rose = name != "steps" and now > before * (1 + RISE)
        if before >= MIN_ROWS and (fell or rose):
            held.append(line)
    return held, lines


def check_links(packs: Path, sent: dict | None, allow: bool) -> dict[str, int]:
    """Says every change of the quest steps' numbers since the last sent edition and refuses a
    jump unless `allow`. -> this build's numbers, for the edition and the watch."""
    counts = link_counts(packs)
    before = sent.get("links") if sent else None
    if not counts:
        if before and not allow:
            raise DataUpdateError(
                f"no {LINKS.name} beside the packs although the last sent edition had one: the "
                "quest steps cannot be checked (pass --allow-drift to ship without the check)"
            )
        print(f"steps: no {LINKS.name} beside the packs, the quest steps were not checked")
        return counts
    held, lines = links_drift(before, counts)
    for line in lines:
        print(f"steps: {line}")
    if held and not allow:
        raise DataUpdateError(
            "the quest steps jumped by more than a tenth since the last sent edition: "
            + "; ".join(held)
            + " (the resolver or a source broke? pass --allow-drift when the change is right)"
        )
    return counts


def check_nav(packs: Path) -> None:
    """Refuses an edition whose walk network is the stub: Route would plan without it."""
    nav = packs / NAV
    if not nav.is_file():
        raise DataUpdateError(f"the build wrote no {NAV}")
    head = nav.read_text(encoding="utf-8", errors="replace")[:400]
    if "no walk network" in head or not ("waypoints" in head or "nodes" in head):
        raise DataUpdateError(f"{NAV} holds no walk network (a stub): build the graphs first")


Builder = Callable[[build_client.BuildInputs, Path], None]
Notes = Callable[[str | None, dict], list[str]]


def update(
    inputs: build_client.BuildInputs,
    out: Path,
    *,
    ledger_path: Path = LEDGER,
    book_toml: Path = BOOK_TOML,
    book_states: Path = BOOK_STATES,
    today: str | None = None,
    build: Builder = run_build,
    config: dict | None = None,
    addons_dir: Path = release.ADDONS_DIR,
    boot: bool = True,
    suite_zip: Path | None = None,
    commit: str | None = None,
    inputs_commit: str | None = None,
    notes: Notes = data_notes,
    counts: dict | None = None,
    allow_drift: bool = False,
) -> tuple[dict, list[curseforge.Upload] | None]:
    """Steps 1 to 3 of the module docstring. -> (the edition, the planned uploads, or None when
    the data is unchanged and that edition was sent)."""
    today = today or datetime.now(UTC).strftime("%Y-%m-%d")
    if build is run_build:
        missing = missing_sources(inputs.addons)
        if missing:
            raise DataUpdateError(
                f"the Forever source addons are missing in {inputs.addons}: {', '.join(missing)} "
                "(set [build.sources] forever in .local/install.toml)"
            )
    config = config or curseforge.load_config()
    ledger = read_ledger(ledger_path)
    sent = last_sent(ledger)
    packs = out / "packs"
    state_out = out / "book-state.json"
    state_out.unlink(missing_ok=True)
    extra = ["--book-state", str(state_out)]
    previous = book_states / sent["book_state"] if sent and sent.get("book_state") else None
    if previous is not None and previous.is_file():
        extra += ["--book-previous", str(previous)]
    art = art_folder(inputs.export)
    if art is not None:
        extra += ["--art", str(art)]
    build(dataclasses.replace(inputs, extra=[*inputs.extra, *extra]), packs)
    # the pages' pictures (content/strategies/art): the game's textures by the packs
    pictures = book_art.install(art, packs, front=book_art.FRONT)
    if pictures:
        print(f"book art: {len(pictures)} pictures from {art} and {book_art.FRONT.name}/")
    data = config["projects"][PROJECT]["folders"]
    check_nav(packs)
    records = check_drift(packs, sent, allow_drift)
    links = check_links(packs, sent, allow_drift)
    sha = data_hash(packs, data, addons_dir)
    write_downloads(packs, counts)  # after the hash: a new count is no new edition
    with book_toml.open("rb") as fh:
        book = tomllib.load(fh)
    state = json.loads(state_out.read_text(encoding="utf-8")) if state_out.is_file() else {}
    book_news = [*book.get("news", []), *state.get("news", [])]
    seen = seen_news(ledger)
    edition, new = next_edition(ledger, sha, today)
    if not new and edition.get("sent"):
        return edition, None
    if new:
        edition["news"] = sorted({n["text"] for n in book_news})
        edition["commit"] = commit
        edition["inputs"] = inputs_commit  # the last commit on what the build reads (the skip)
        edition["export"] = export_id(inputs.export)
        edition["export_sha"] = export_fingerprint(inputs.export) if inputs.export else None
        edition["records"] = records  # the row counts the next edition is held against (B2)
        if links:  # the quest steps' numbers: held against too, and the watch's line
            edition["links"] = links
        if state:
            name = f"{edition['date']}.{edition['n']}.json"
            book_states.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(state_out, book_states / name)
            edition["book_state"] = name
        ledger["editions"].append(edition)
        write_ledger(ledger_path, ledger)
    rel_dir = out / "release"
    packages, build_notes = release.release(
        CLIENT, addons_dir, rel_dir, only=set(project_folders(config, INSTALL)), generated_dir=packs
    )
    for note in build_notes:
        print(f"note: {note}")
    if boot:
        booted = packages
        if suite_zip is not None:
            # what players run: the Suite as it was last sent, with this edition's data
            booted = [p for p in packages if p.addon in data]
            booted.append(release.Package(INSTALL, "released", CLIENT, suite_zip, "", 0))
        with tempfile.TemporaryDirectory(prefix="bastians-data-") as tmp:
            problems = release.verify(booted, CLIENT, Path(tmp))
        if problems:
            raise DataUpdateError("the edition does not boot: " + "; ".join(problems))
    log = changelog(
        {"news": book_news},
        seen,
        export_id(inputs.export),
        notes(sent.get("commit") if sent else None, config),
    )
    uploads = curseforge.plan(config, CLIENT, rel_dir, {PROJECT}, log, version_suffix(edition))
    return edition, uploads


def mark_sent(ledger_path: Path, edition: dict, file_id: object) -> None:
    ledger = read_ledger(ledger_path)
    for e in ledger["editions"]:
        if (
            e["sha256"] == edition["sha256"]
            and e["date"] == edition["date"]
            and e["n"] == edition["n"]
        ):
            e["sent"] = True
            e["file_id"] = file_id
            e["sent_at"] = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    write_ledger(ledger_path, ledger)


def send(
    edition: dict,
    uploads: list[curseforge.Upload],
    transport: curseforge.Transport = curseforge._urlopen,
    ledger_path: Path = LEDGER,
    token: str | None = None,
) -> list[tuple[str, object]]:
    """Uploads the edition's file and marks it sent. -> [(project, file id)]. Raises
    DataUpdateError when a file is not ready or there is no token; nothing is sent then."""
    problems = [p for u in uploads for p in u.problems]
    if problems:
        raise DataUpdateError("the file is not ready: " + "; ".join(problems))
    token = token or curseforge.api_token()
    if not token:
        raise DataUpdateError("no upload token (CF_API_KEY or ~/.curseforge/.secrets)")
    config = curseforge.load_config()
    sent = []
    try:
        ids = curseforge.game_version_ids(config["game_versions"][CLIENT], token, transport)
        for u in uploads:
            answer = curseforge.send(u, ids, token, transport)
            mark_sent(ledger_path, edition, answer.get("id"))  # at once: a later failure keeps it
            curseforge.keep_sent(u, answer.get("id"), CLIENT)
            sent.append((u.project, answer.get("id")))
    except urllib.error.HTTPError as err:
        # CurseForge says why in the body ({"errorCode": .., "errorMessage": ..})
        body = err.read().decode("utf-8", "replace")[:500]
        raise DataUpdateError(f"CurseForge refused: HTTP {err.code}: {body}") from err
    return sent


ERRORS = (
    DataUpdateError,
    build_client.BuildClientError,
    release.ReleaseError,
    curseforge.UploadError,
    release_notes.NotesError,
)


def main(
    argv: list[str] | None = None, transport: curseforge.Transport = curseforge._urlopen
) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--export", type=Path, help="the AHSync export (default: .local/install.toml)"
    )
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "data")
    parser.add_argument("--send", action="store_true", help="upload; without it a dry run")
    parser.add_argument(
        "--allow-drift",
        action="store_true",
        help="ship although a pack's rows fell, or the quest steps' numbers jumped, by more "
        "than a tenth since the last sent edition",
    )
    args = parser.parse_args(argv)
    try:
        inputs = build_client.read_inputs(CLIENT)
        if args.export:
            inputs = dataclasses.replace(inputs, export=args.export)
        if inputs.export is None:
            raise DataUpdateError("no AHSync export: pass --export or set [build.export] forever")
        suite = curseforge.kept(INSTALL, CLIENT)
        last = release_notes.last_change(input_paths(curseforge.load_config()))
        edition, uploads = update(
            inputs,
            args.out,
            suite_zip=suite,
            commit=release_notes.head(),
            inputs_commit=last,
            counts=downloads(curseforge.load_config(), transport),
            allow_drift=args.allow_drift,
        )
    except ERRORS as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    label = f"edition {edition['date']}.{edition['n']}"
    if uploads is None:
        print(f"the data is unchanged since {label}, which was sent: nothing to do")
        return 0
    for u in uploads:
        print(f"{label}: {u.project} {u.version} -> {u.zip_path}")
        for problem in u.problems:
            print(f"  not ready: {problem}")
    if not args.send:
        print("dry run: nothing sent (--send uploads)")
        return 0
    try:
        for project, file_id in send(edition, uploads, transport):
            print(f"sent {project}: file id {file_id}")
    except (*ERRORS, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
