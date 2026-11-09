"""Export the learned facts of Bastian's Data (the walks the mesh missed, the flight times, the
ride waits) from a client's saved variables into data/captures/<client>/ (world-graph.md §9,
W11). Positions and times only: the account folder becomes a short hash, no name is written.

Usage: python tools/capture_import.py --client forever|retail [--wow <client folder>]
       [--file <Bastians_Data.lua>] [--out data/captures]
       python tools/capture_import.py --text <file>      a player's pasted text (catalog review B5)
       python tools/capture_import.py --issue <number>   the same from a GitHub issue, through gh
The build reads the folder (`bastians_build nav --captures`): a walk held by two or more
captures becomes a link for everyone (corrections.captured_links).

A player's text comes from the settings hub, Data > "Copy my captures" (Export.lua): a header
`BASTIANS CAPTURE 1 <client> <build> <at>`, one line per walk, flight time and ride, and
`END <lines> <checksum>`; a cut or changed paste is refused. The text may sit inside an issue's
other words: the first header and the END after it are taken."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

from install import CONFIG_PATH, ROOT, InstallError, resolve_client_dir

OUT_DIR = ROOT / "data" / "captures"
HEADER = re.compile(r"^BASTIANS CAPTURE (\d+) (\S+) (\S+) (\S+)\s*$")


class CaptureError(InstallError):
    """A pasted text that is not a whole capture."""


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


def checksum(body: list[str]) -> int:
    """The bytes of the body lines joined with newlines, summed modulo 65536 (Export.Sum)."""
    return sum("\n".join(body).encode("utf-8")) % 65536


def _number(word: str) -> float | None:
    return None if word == "-" else float(word)


def parse_text(text: str) -> dict:
    """A player's pasted text -> { client, build, exported, learned } with the learned table in
    the saved variables' shape (walk, taxi, ride), checked whole."""
    lines = [line.rstrip("\r") for line in text.splitlines()]
    start = next((i for i, line in enumerate(lines) if line.startswith("BASTIANS CAPTURE ")), None)
    if start is None:
        raise CaptureError("no 'BASTIANS CAPTURE' line: paste the whole text of Copy my captures")
    m = HEADER.match(lines[start].strip())
    if not m:
        raise CaptureError(f"a header this tool cannot read: {lines[start][:60]}")
    if m.group(1) != "1":
        raise CaptureError(f"a capture of version {m.group(1)}; this tool reads version 1")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("END ")), None)
    if end is None:
        raise CaptureError("the END line is missing: the text was cut")
    body = [line.strip() for line in lines[start + 1 : end] if line.strip()]
    parts = lines[end].split()
    if len(parts) != 3 or not (parts[1].isdigit() and parts[2].isdigit()):
        raise CaptureError(f"an END line this tool cannot read: {lines[end][:60]}")
    if int(parts[1]) != len(body):
        raise CaptureError(
            f"the text holds {len(body)} lines, END says {parts[1]}: cut or mixed up"
        )
    if int(parts[2]) != checksum(body):
        raise CaptureError("the checksum does not match: the text changed on the way")
    learned: dict = {"walk": [], "taxi": {}, "ride": {}}
    for line in body:
        kind, _, rest = line.partition(" ")
        try:
            if kind == "walk":
                map_, length, at, points = rest.split(" ", 3)
                learned["walk"].append(
                    {
                        "map": int(map_),
                        "len": _number(length),
                        "at": _number(at),
                        "points": [
                            [float(x), float(y)]
                            for x, y in (p.split(",") for p in points.split(";"))
                        ],
                    }
                )
            elif kind == "taxi":
                key, seconds = rest.rsplit(" ", 1)
                learned["taxi"][key] = float(seconds)
            elif kind == "ride":
                ref, waits = rest.rsplit(" ", 1)
                learned["ride"][ref] = [float(w) for w in waits.split(",")]
            else:
                raise ValueError(kind)
        except ValueError as err:
            raise CaptureError(f"a line this tool cannot read: {line[:60]}") from err
    return {"client": m.group(2), "build": m.group(3), "exported": m.group(4), "learned": learned}


def issue_body(number: int, runner=subprocess.run) -> str:
    """The body of a GitHub issue of this repository's public twin, through gh."""
    proc = runner(
        ["gh", "issue", "view", str(number), "--json", "body", "-q", ".body"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise CaptureError(f"gh could not read issue {number}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def text_tag(text: str) -> str:
    """A short hash of the pasted text: tells captures apart, names nobody."""
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]


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
    parser.add_argument(
        "--client", choices=("forever", "retail"), help="the client of the saved variables"
    )
    parser.add_argument("--text", type=Path, help="a player's pasted text (- for stdin)")
    parser.add_argument("--issue", type=int, help="a GitHub issue number with a player's text")
    parser.add_argument("--wow", help="client folder that contains Interface/AddOns (remembered)")
    parser.add_argument(
        "--file", type=Path, help="one saved variables file instead of the client's"
    )
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    args = parser.parse_args(argv)
    try:
        if args.text or args.issue:
            if args.text:
                raw = (
                    sys.stdin.read()
                    if str(args.text) == "-"
                    else args.text.read_text(encoding="utf-8")
                )
            else:
                raw = issue_body(args.issue)
            parsed = parse_text(raw)
            cap = capture(parsed["learned"], parsed["client"], parsed["exported"])
            cap["build"] = parsed["build"]
            tag = f"issue{args.issue}" if args.issue else text_tag(raw)
            target, changed = write_capture(cap, args.out, tag)
            shown = target.relative_to(ROOT) if ROOT in target.parents else target
            print(
                f"{'written' if changed else 'unchanged'}: {shown} "
                f"({len(cap['walk'])} walks, {len(cap['taxi'])} flight times, "
                f"{len(cap['ride'])} rides; build {parsed['build']})"
            )
            return 0
        if not args.client:
            parser.error("--client is required without --text or --issue")
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
