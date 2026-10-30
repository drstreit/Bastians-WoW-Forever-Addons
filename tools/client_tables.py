"""Dump the client's data tables for the build (ADR 0035, "client first").

Usage: python tools/client_tables.py --client forever|retail [--install <folder>] [--force]
       [--dry-run]

Writes ``.local/out/<client>_<Table>.json`` for every table in TABLES and, for every text language
the install carries besides enUS (the launcher's language settings, read from ``.build.info``),
``.local/out/<client>_<Table>.<locale>.json`` for the tables in LOCALIZED (their ``_lang`` columns
in that language). The pipeline reads them through ``bastians_build.sources.client_tables``.
Idempotent: a dump that exists is kept unless --force. The game must be closed: clientdump cannot
read the archives while the client runs.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DUMPS = ROOT / ".local" / "out"
EXE = ROOT / "tools" / "clientdump" / "bin" / "Release" / "net10.0" / "clientdump.exe"
DEFS = ROOT / ".local" / "WoWDBDefs" / "definitions"
CLIENTS = ("forever", "retail")
PRODUCTS = {"forever": "wowf", "retail": "wow"}
FOLDERS = {"forever": "_forever_", "retail": "_retail_"}
TABLES = (
    "ItemSparse",
    "Item",
    "SpellName",
    "SkillLine",
    "SkillLineAbility",
    "SpellReagents",
    "SpellEffect",
    "QuestLine",
    "QuestLineXQuest",
    "QuestPOIBlob",
    "QuestPOIPoint",
)
# the tables whose names the language packs take from the client (data.md, ADR 0033 and 0035)
LOCALIZED = ("ItemSparse", "SpellName", "SkillLine")


def install_of(client: str) -> Path:
    """The client folder: .local/install.toml's [clients] when it names the right product, else
    the standard folder next to the retail one."""
    cfg = ROOT / ".local" / "install.toml"
    if cfg.is_file():
        with cfg.open("rb") as fh:
            folder = (tomllib.load(fh).get("clients") or {}).get(client)
        if folder and (Path(folder) / ".flavor.info").is_file():
            flavor = (Path(folder) / ".flavor.info").read_text(encoding="utf-8").splitlines()
            if len(flavor) > 1 and flavor[1].strip() == PRODUCTS[client]:
                return Path(folder)
    return Path("D:/Spiele/World of Warcraft") / FOLDERS[client]


def text_locales(install: Path, product: str) -> list[str]:
    """The text languages installed for the product (.build.info's Tags: "<xxYY> text?")."""
    root = install
    while root.parent != root and not (root / ".build.info").is_file():
        root = root.parent
    lines = (root / ".build.info").read_text(encoding="utf-8").splitlines()
    header = [h.split("!")[0] for h in lines[0].split("|")]
    found: list[str] = []
    for line in lines[1:]:
        cells = dict(zip(header, line.split("|"), strict=False))
        if cells.get("Product") != product:
            continue
        for tag in (cells.get("Tags") or "").split(":"):
            words = tag.replace("?", "").split()
            if len(words) >= 2 and words[-1] == "text" and len(words[-2]) == 4:
                found.append(words[-2])
    return sorted(set(found))


def dump(install: Path, table: str, out: Path, locale: str | None, dry_run: bool) -> bool:
    cmd = [str(EXE), "db2", "--install", str(install), "--table", table, "--out", str(out)]
    if DEFS.is_dir():
        cmd += ["--defs", str(DEFS)]
    if locale:
        cmd += ["--locale", locale]
    if dry_run:
        print("> " + " ".join(cmd))
        return True
    run = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, check=False)
    if run.returncode:
        print(f"failed: {table} {locale or ''}: {run.stderr.strip()[-200:]}")
        return False
    print(run.stdout.strip().splitlines()[-1] if run.stdout.strip() else f"written: {out}")
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--install", type=Path, help="the client folder (default: see install_of)")
    parser.add_argument("--force", action="store_true", help="dump again what exists")
    parser.add_argument("--dry-run", action="store_true", help="print the commands only")
    args = parser.parse_args(argv)
    install = args.install or install_of(args.client)
    locales = [loc for loc in text_locales(install, PRODUCTS[args.client]) if loc != "enUS"]
    print(f"{args.client}: {install}, text languages besides enUS: {', '.join(locales) or 'none'}")
    ok = True
    jobs = [(t, None) for t in TABLES] + [(t, loc) for loc in locales for t in LOCALIZED]
    for table, locale in jobs:
        name = f"{args.client}_{table}" + (f".{locale}" if locale else "") + ".json"
        out = DUMPS / name
        if out.is_file() and not args.force:
            continue
        ok = dump(install, table, out, locale, args.dry_run) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
