"""Export the learned facts of Bastian's Data (the walks the mesh missed, the flight times, the
ride waits) from a client's saved variables into data/captures/<client>/ (world-graph.md §9,
W11). Positions and times only: the account folder becomes a short hash, no name is written.

Usage: python tools/capture_import.py --client forever|retail [--wow <client folder>]
       [--file <Bastians_Data.lua>] [--out data/captures]
The build reads the folder (`bastians_build nav --captures`): a walk held by two or more
captures becomes a link for everyone (corrections.captured_links)."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

from install import CONFIG_PATH, ROOT, InstallError, resolve_client_dir

OUT_DIR = ROOT / "data" / "captures"
SV_NAME = "Bastians_Data.lua"
TABLE = "BastiansDataDB"


def find_saved_variables(client_dir: Path) -> list[Path]:
    """Every account's Bastians_Data.lua below WTF/Account/*/SavedVariables."""
    found = sorted((client_dir / "WTF" / "Account").glob(f"*/SavedVariables/{SV_NAME}"))
    if not found:
        raise InstallError(
            f"No {SV_NAME} below {client_dir / 'WTF' / 'Account'}: log out once so WoW writes it."
        )
    return found


def read_learned(path: Path) -> dict:
    """The `global.learned` table of the saved variables file, as plain Python."""
    import lupa.lua51 as lupa_mod

    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(path.read_text(encoding="utf-8"))
    root = lua.globals()[TABLE]
    learned = root and root["global"] and root["global"]["learned"]
    if not learned:
        return {}

    def plain(value):
        if lupa_mod.lua_type(value) == "table":
            keys = list(value.keys())
            if keys and all(isinstance(k, int) for k in keys):
                return [plain(value[k]) for k in sorted(keys)]
            return {str(k): plain(value[k]) for k in sorted(keys, key=str)}
        return value

    return plain(learned)


def capture(learned: dict, client: str, exported: str) -> dict:
    """The capture: taxi times, ride waits and walks; nothing else, no names."""
    walks = []
    for w in learned.get("walk") or []:
        if (
            isinstance(w, dict)
            and isinstance(w.get("map"), int)
            and len(w.get("points") or []) >= 2
        ):
            walks.append(
                {
                    "map": w["map"],
                    "len": w.get("len"),
                    "at": w.get("at"),
                    "points": [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in w["points"]],
                }
            )
    taxi = {k: v for k, v in (learned.get("taxi") or {}).items() if isinstance(v, int | float)}
    ride = {k: v for k, v in (learned.get("ride") or {}).items() if isinstance(v, list)}
    return {"client": client, "exported": exported, "taxi": taxi, "ride": ride, "walk": walks}


def account_hash(path: Path) -> str:
    """A short hash of the account folder's name: tells captures apart, names nobody."""
    account = path.parents[1].name
    return hashlib.sha1(account.encode("utf-8")).hexdigest()[:8]


def write_capture(cap: dict, out_dir: Path, tag: str) -> tuple[Path, bool]:
    day = re.sub(r"T.*", "", cap["exported"])
    target = out_dir / cap["client"] / f"{day}-{tag}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(cap, indent=1, sort_keys=True) + "\n"
    if target.is_file() and target.read_text(encoding="utf-8") == text:
        return target, False
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(target)
    return target, True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", required=True, choices=("forever", "retail"))
    parser.add_argument("--wow", help="client folder that contains Interface/AddOns (remembered)")
    parser.add_argument(
        "--file", type=Path, help="one saved variables file instead of the client's"
    )
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    args = parser.parse_args(argv)
    try:
        files = (
            [args.file]
            if args.file
            else find_saved_variables(resolve_client_dir(args.client, args.wow, CONFIG_PATH))
        )
        today = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        for path in files:
            cap = capture(read_learned(path), args.client, today)
            target, changed = write_capture(cap, args.out, account_hash(path))
            print(
                f"{'written' if changed else 'unchanged'}: {target.relative_to(ROOT)} "
                f"({len(cap['walk'])} walks, {len(cap['taxi'])} flight times)"
            )
    except InstallError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
