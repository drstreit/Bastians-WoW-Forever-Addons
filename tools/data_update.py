"""The daily data edition (ADR 0019, strategies-design.md section 7): the newest AHSync export
becomes a new version of the Bastian's Data project, zipped, booted on the mock and ready for
CurseForge. The suite's apps are not uploaded: they change only with the code.

Usage: python tools/data_update.py [--export <dir>] [--out build/data] [--send]

1. Builds the Forever data packs (tools/build_client.py --skip-mapart into `<out>/packs`): the
   game data, the market prices of the export, the book with the rumours its pages rest on and
   the Rumour mill, and the candidate report `build/book-candidates.md` for choosing new pages.
2. Compares the data project's generated files with the last edition in
   `.local/data-editions.json`. Unchanged and sent: says so and stops, so the command can run as
   often as one likes. Changed: a new edition, numbered per day.
3. Zips the whole install, the suite and its data (tools/release.py into `<out>/release`), boots it
   on the WoW mock, and writes the Data project's CurseForge file with the version
   `<Data's TOC version>+data.<YYYYMMDD>.<n>` and a changelog from book.toml's What's new.
4. `--send` uploads that file (tools/curseforge.py: CF_API_KEY in the environment, never in the
   repo). CurseForge refuses it, and so does this command, while the project id or the slug is
   unknown (tools/curseforge.toml).

The ledger records each edition and whether it was sent: an edition that was not sent is
planned again by the next run. The daily data is Forever's (the book is written for Forever, the
export's markets are Forever's); retail's data ships with the suite's releases.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import tomllib
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

import build_client
import curseforge
import release

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / ".local" / "data-editions.json"
BOOK_TOML = ROOT / "content" / "strategies" / "book.toml"
PROJECT = "Bastians_Data"  # what is uploaded daily
INSTALL = "Bastians_Suite"  # what a player installs with it: booted on the mock
CLIENT = "forever"


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


def data_hash(packs: Path, folders: list[str]) -> str:
    """One hash over every generated file of the data project's folders (path and bytes, sorted),
    so any changed pack makes a new edition and an unchanged build none."""
    digest = hashlib.sha256()
    files = sorted(
        p for folder in folders for p in (packs / folder / release.GENERATED).glob("*.lua")
    )
    if not files:
        raise DataUpdateError(f"the build wrote no generated files under {packs}")
    for path in files:
        digest.update(path.relative_to(packs).as_posix().encode() + b"\0")
        digest.update(path.read_bytes())
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


def version_suffix(edition: dict) -> str:
    return f"+data.{edition['date'].replace('-', '')}.{edition['n']}"


def changelog(book: dict, seen: set[str], export_id: str | None) -> str:
    """Markdown for the CurseForge file: the book's What's new entries the last sent edition did
    not have (`seen`, their texts), newest first, and where the prices and rumours come from."""
    news = [n for n in book.get("news", []) if n["text"] not in seen]
    lines = [
        f"- {n['date']}: {n['text']}" for n in sorted(news, key=lambda n: n["date"], reverse=True)
    ]
    if not lines:
        lines = ["- The prices, the rumours and their sources are up to date."]
    if export_id:
        lines.append(f"\nPrices and rumours from the AHSync export {export_id}.")
    return "Bastian's Data, a new edition.\n\n" + "\n".join(lines) + "\n"


def seen_news(ledger: dict) -> set[str]:
    """The What's new texts the last sent edition carried."""
    sent = [e for e in ledger["editions"] if e.get("sent")]
    return set(sent[-1].get("news", [])) if sent else set()


def export_id(export: Path | None) -> str | None:
    if export is None:
        return None
    latest = export / "LATEST"
    return latest.read_text(encoding="utf-8").strip() if latest.is_file() else export.name


def run_build(inputs: build_client.BuildInputs, packs: Path) -> None:
    cmd = build_client.commands(inputs, packs, skip_mapart=True)[0]
    print("> " + " ".join(cmd[3:]), flush=True)
    run = subprocess.run(cmd, cwd=ROOT)
    if run.returncode:
        raise DataUpdateError(f"the data build exited with {run.returncode}")


Builder = Callable[[build_client.BuildInputs, Path], None]


def update(
    inputs: build_client.BuildInputs,
    out: Path,
    *,
    ledger_path: Path = LEDGER,
    book_toml: Path = BOOK_TOML,
    today: str | None = None,
    build: Builder = run_build,
    config: dict | None = None,
    addons_dir: Path = release.ADDONS_DIR,
    boot: bool = True,
) -> tuple[dict, list[curseforge.Upload] | None]:
    """Steps 1 to 3 of the module docstring. -> (the edition, the planned uploads, or None when
    the data is unchanged and that edition was sent)."""
    today = today or datetime.now(UTC).strftime("%Y-%m-%d")
    config = config or curseforge.load_config()
    packs = out / "packs"
    build(inputs, packs)
    sha = data_hash(packs, config["projects"][PROJECT]["folders"])
    with book_toml.open("rb") as fh:
        book = tomllib.load(fh)
    ledger = read_ledger(ledger_path)
    seen = seen_news(ledger)
    edition, new = next_edition(ledger, sha, today)
    if not new and edition.get("sent"):
        return edition, None
    if new:
        edition["news"] = [n["text"] for n in book.get("news", [])]
        ledger["editions"].append(edition)
        write_ledger(ledger_path, ledger)
    rel_dir = out / "release"
    packages, notes = release.release(
        CLIENT, addons_dir, rel_dir, only=set(project_folders(config, INSTALL)), generated_dir=packs
    )
    for note in notes:
        print(f"note: {note}")
    if boot:
        with tempfile.TemporaryDirectory(prefix="bastians-data-") as tmp:
            problems = release.verify(packages, CLIENT, Path(tmp))
        if problems:
            raise DataUpdateError("the edition does not boot: " + "; ".join(problems))
    log = changelog(book, seen, export_id(inputs.export))
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
    write_ledger(ledger_path, ledger)


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
        edition, uploads = update(inputs, args.out)
    except (
        DataUpdateError,
        build_client.BuildClientError,
        release.ReleaseError,
        curseforge.UploadError,
    ) as err:
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
    if any(u.problems for u in uploads):
        print("error: the file is not ready, nothing sent", file=sys.stderr)
        return 1
    token = os.environ.get("CF_API_KEY")
    if not token:
        print("error: CF_API_KEY is not set", file=sys.stderr)
        return 1
    config = curseforge.load_config()
    try:
        ids = curseforge.game_version_ids(config["game_versions"][CLIENT], token, transport)
        for u in uploads:
            answer = curseforge.send(u, ids, token, transport)
            mark_sent(LEDGER, edition, answer.get("id"))
            print(f"sent {u.project} {u.version}: file id {answer.get('id')}")
    except (curseforge.UploadError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
