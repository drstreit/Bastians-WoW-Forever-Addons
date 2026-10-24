"""The daily data edition (ADR 0019, strategies-design.md section 7): the newest AHSync export
becomes a new version of the Bastian's Data project, zipped, booted on the mock and ready for
CurseForge. The suite's apps are not uploaded: they change only with the code (ADR 0020).

Usage: python tools/data_update.py [--export <dir>] [--out build/data] [--send]

1. Builds the Forever data packs (tools/build_client.py --skip-mapart into `<out>/packs`): the
   game data, the market prices of the export, the book with the rumours its pages rest on and
   the Rumour mill, and the candidate report `build/book-candidates.md` for choosing new pages.
   The build gets the book's state of the last sent edition and writes What's new entries for
   what changed since (pipeline book_news.py: new travellers, stamps, mill rumours).
2. Compares the data project's files (the packs, the loader's and the packs' code, without the
   TOC version line) with the last edition in `.local/data-editions.json`. Unchanged and sent:
   says so and stops, so the command can run as often as one likes. Changed: a new edition,
   numbered per day; its book state goes to `.local/book-states/`.
3. Zips the whole install, the suite and its data (tools/release.py into `<out>/release`), boots it
   on the WoW mock (with the Suite as it was last sent when `.local/released/forever/` keeps it:
   what players run), and writes the Data project's CurseForge file with the version
   `<Data's TOC version>+data.<YYYYMMDD>.<n>` and a changelog: What's new (book.toml's entries
   and the build's), the release notes of Data's commits since the last sent edition (ADR 0020).
4. `--send` uploads that file (tools/curseforge.py: the token from CF_API_KEY or
   ~/.curseforge/.secrets, never in the repo). CurseForge refuses it, and so does this command,
   while the project id or the slug is unknown (tools/curseforge.toml).

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
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.error
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

import build_client
import curseforge
import release
import release_notes

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / ".local" / "data-editions.json"
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
        p for folder in folders for p in (packs / folder / release.GENERATED).glob("*.lua")
    )
    if not generated:
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


def run_build(inputs: build_client.BuildInputs, packs: Path) -> None:
    cmd = build_client.commands(inputs, packs, skip_mapart=True)[0]
    print("> " + " ".join(cmd[3:]), flush=True)
    code = stream(cmd, ROOT)
    if code:
        raise DataUpdateError(f"the data build exited with {code}")


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
) -> tuple[dict, list[curseforge.Upload] | None]:
    """Steps 1 to 3 of the module docstring. -> (the edition, the planned uploads, or None when
    the data is unchanged and that edition was sent)."""
    today = today or datetime.now(UTC).strftime("%Y-%m-%d")
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
    build(dataclasses.replace(inputs, extra=[*inputs.extra, *extra]), packs)
    data = config["projects"][PROJECT]["folders"]
    sha = data_hash(packs, data, addons_dir)
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
            inputs, args.out, suite_zip=suite, commit=release_notes.head(), inputs_commit=last
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
