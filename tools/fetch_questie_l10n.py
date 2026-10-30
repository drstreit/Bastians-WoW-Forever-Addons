"""Fetch QuestieDB's l10n lookups for the game data in other languages (data.md "Game data in other
languages", ADR 0033).

Usage: python tools/fetch_questie_l10n.py [--commit <sha>] [--out <folder>]

Downloads ``l10n/Forever/lookup{Quests,Npcs,Items,Objects}/<locale>.lua`` and the same under
``l10n/Forever/traces/`` for deDE, frFR, esES, koKR, zhCN and zhTW from GitHub
(``Questie/QuestieDB``, GPL-3.0) at one commit (default: the newest on master) into
``<out>/<locale>/`` and writes the commit to ``<out>/COMMIT``, so a build names its source. Needs
the ``gh`` CLI. The files are data the pipeline runs in its Lua sandbox
(bastians_build.sources.luatable); nothing here executes them. Idempotent: a file already there
with the same bytes is not rewritten.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "Questie/QuestieDB"
LOCALES = ("deDE", "frFR", "esES", "koKR", "zhCN", "zhTW")
LOOKUPS = ("lookupQuests", "lookupNpcs", "lookupItems", "lookupObjects")
DEFAULT_OUT = ROOT / ".local" / "sources" / "forever" / "questie-l10n"


def gh(*args: str) -> bytes:
    done = subprocess.run(["gh", *args], capture_output=True, check=False)
    if done.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)}: {done.stderr.decode(errors='replace').strip()}")
    return done.stdout


def head_commit() -> str:
    return gh("api", f"repos/{REPO}/commits/master", "--jq", ".sha").decode().strip()


def fetch(path: str, commit: str) -> bytes | None:
    """A file's bytes at the commit, or None when it does not exist there."""
    try:
        return gh(
            "api",
            "-H",
            "Accept: application/vnd.github.raw",
            f"repos/{REPO}/contents/{path}?ref={commit}",
        )
    except RuntimeError as exc:
        if "404" in str(exc) or "Not Found" in str(exc):
            return None
        raise


def write(target: Path, data: bytes) -> bool:
    if target.is_file() and target.read_bytes() == data:
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(target)
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--commit", help="QuestieDB commit (default: the newest on master)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    commit = args.commit or head_commit()
    for locale in LOCALES:
        for lookup in LOOKUPS:
            for sub in ("", "traces/"):
                data = fetch(f"l10n/Forever/{sub}{lookup}/{locale}.lua", commit)
                if data is None:
                    print(f"absent: {sub}{lookup}/{locale}.lua")
                    continue
                target = args.out / locale / sub / f"{lookup}.lua"
                print(("written: " if write(target, data) else "same: ") + str(target))
    write(args.out / "COMMIT", (commit + "\n").encode())
    print(f"QuestieDB {commit} -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
