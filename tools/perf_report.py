"""Performance report (nfr.md budgets, roadmap B11.1) from the snapshots `/bastians perf` saves.

Usage: python tools/perf_report.py <Bastians_Core.lua saved variables> [--out build/perf-report.md]
       [--last N] [--client forever|retail]

The saved-variables file holds `BastiansCoreDB`; its `global.perf` list carries up to 20 snapshots
(Perf.lua): time, uptime, client, build, memory per Bastians addon in KB and CPU per module (calls,
total ms, max ms). The report is Markdown: the newest snapshot against the budgets, every breach
flagged, and a history table of the memory totals. Exit code 1 when the newest snapshot breaches a
budget, so the owner can gate a release on it. A snapshot never proves a budget holds for cases it
did not exercise; the in-game checklist says what to do before taking one.
"""

from __future__ import annotations

import argparse
import sys
from datetime import UTC, datetime
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent

# nfr.md "Performance budgets"
MEMORY_NO_PACKS_KB = 8 * 1024  # Core + Data (no packs) + all apps
MEMORY_WITH_PACKS_KB = 35 * 1024
FRAME_MS = 4.0  # any single frame in our code
FRAME_MS_MAP = 8.0  # map pan and zoom
MAP_MODULES = ("Map",)
PACK_PREFIX = "Bastians_Data_"


class PerfReportError(ValueError):
    pass


def to_python(value):
    """Lua table -> dict/list; integral floats -> int."""
    if lua51.lua_type(value) == "table":
        keys = list(value.keys())
        if (
            keys
            and all(isinstance(k, int) for k in keys)
            and sorted(keys) == list(range(1, len(keys) + 1))
        ):
            return [to_python(value[i]) for i in range(1, len(keys) + 1)]
        return {to_python(k): to_python(value[k]) for k in keys}
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def read_snapshots(path: Path) -> list[dict]:
    """Every snapshot in the saved-variables file, oldest first."""
    if not path.is_file():
        raise PerfReportError(f"not a file: {path}")
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    try:
        lua.execute(path.read_text(encoding="utf-8"))
    except lua51.LuaError as err:
        raise PerfReportError(f"{path}: not a Lua saved-variables file ({err})") from err
    db = lua.globals().BastiansCoreDB
    if db is None:
        raise PerfReportError(f"{path}: no BastiansCoreDB in the file")
    data = to_python(db)
    snaps = (data.get("global") or {}).get("perf") or []
    if not isinstance(snaps, list):
        snaps = list(snaps.values())
    return [s for s in snaps if isinstance(s, dict)]


def memory_totals(snapshot: dict) -> tuple[float, float, bool]:
    """(total KB, KB without data packs, packs loaded?)"""
    memory = snapshot.get("memoryKB") or {}
    total = sum(float(v) for v in memory.values())
    packs = sum(float(v) for k, v in memory.items() if str(k).startswith(PACK_PREFIX))
    return total, total - packs, packs > 0


def breaches(snapshot: dict) -> list[str]:
    out = []
    total, without, packs_loaded = memory_totals(snapshot)
    if without > MEMORY_NO_PACKS_KB:
        out.append(
            f"memory without packs {without / 1024:.1f} MB over {MEMORY_NO_PACKS_KB / 1024:.0f} MB"
        )
    if packs_loaded and total > MEMORY_WITH_PACKS_KB:
        out.append(
            f"memory with packs {total / 1024:.1f} MB over {MEMORY_WITH_PACKS_KB / 1024:.0f} MB"
        )
    for name, stat in sorted((snapshot.get("modules") or {}).items()):
        limit = FRAME_MS_MAP if name in MAP_MODULES else FRAME_MS
        max_ms = float(stat.get("maxMs") or 0)
        if max_ms > limit:
            out.append(f"module {name} max {max_ms:.2f} ms over {limit:.0f} ms")
    return out


def _when(snapshot: dict) -> str:
    t = snapshot.get("time")
    if not isinstance(t, int | float):
        return "?"
    return datetime.fromtimestamp(int(t), UTC).strftime("%Y-%m-%d %H:%M UTC")


def render(snapshots: list[dict], last: int = 1) -> str:
    """Markdown: the newest snapshot in detail, breaches, and a history of totals."""
    if not snapshots:
        return "# Performance report\n\nNo snapshots: run `/bastians perf` in game first.\n"
    newest = snapshots[-1]
    total, without, packs_loaded = memory_totals(newest)
    lines = [
        "# Performance report",
        "",
        f"Newest snapshot: {_when(newest)}, client {newest.get('client', '?')}, build "
        f"{newest.get('build', '?')}, {float(newest.get('uptime') or 0):.0f} s after login. "
        f"{len(snapshots)} snapshots in the file.",
        "",
        "## Budgets (nfr.md)",
        "",
        "| Measure | Value | Budget | State |",
        "|---|---|---|---|",
    ]

    def row(measure, value, budget, ok):
        lines.append(f"| {measure} | {value} | {budget} | {'ok' if ok else '**BREACH**'} |")

    row(
        "Memory without data packs",
        f"{without / 1024:.2f} MB",
        f"< {MEMORY_NO_PACKS_KB / 1024:.0f} MB",
        without <= MEMORY_NO_PACKS_KB,
    )
    if packs_loaded:
        row(
            "Memory with data packs",
            f"{total / 1024:.2f} MB",
            f"< {MEMORY_WITH_PACKS_KB / 1024:.0f} MB",
            total <= MEMORY_WITH_PACKS_KB,
        )
    else:
        lines.append("| Memory with data packs | no pack loaded | < 35 MB | not measured |")
    modules = newest.get("modules") or {}
    worst = max(
        (float(s.get("maxMs") or 0) for n, s in modules.items() if n not in MAP_MODULES), default=0
    )
    row(
        "Longest frame, all modules but Map",
        f"{worst:.2f} ms",
        f"< {FRAME_MS:.0f} ms",
        worst <= FRAME_MS,
    )
    map_worst = max(
        (float(s.get("maxMs") or 0) for n, s in modules.items() if n in MAP_MODULES), default=None
    )
    if map_worst is not None:
        row(
            "Longest frame, Map",
            f"{map_worst:.2f} ms",
            f"< {FRAME_MS_MAP:.0f} ms",
            map_worst <= FRAME_MS_MAP,
        )
    lines += ["", "## Memory per addon", "", "| Addon | KB |", "|---|---|"]
    for name, kb in sorted((newest.get("memoryKB") or {}).items()):
        lines.append(f"| {name} | {float(kb):.0f} |")
    lines.append(f"| **total** | **{total:.0f}** |")
    lines += [
        "",
        "## CPU per module",
        "",
        "| Module | Calls | Total ms | Max ms | Avg ms |",
        "|---|---|---|---|---|",
    ]
    for name, stat in sorted(modules.items(), key=lambda kv: -float(kv[1].get("ms") or 0)):
        calls = int(stat.get("calls") or 0)
        ms = float(stat.get("ms") or 0)
        avg = ms / calls if calls else 0
        lines.append(
            f"| {name} | {calls} | {ms:.1f} | {float(stat.get('maxMs') or 0):.2f} | {avg:.3f} |"
        )
    found = breaches(newest)
    lines += ["", "## Breaches", ""]
    lines += [f"- {b}" for b in found] or ["none"]
    history = snapshots[-max(last, 1) :] if last > 1 else snapshots
    lines += [
        "",
        "## History",
        "",
        "| When | Client | Uptime s | Memory MB | Without packs MB | Breaches |",
        "|---|---|---|---|---|---|",
    ]
    for s in history:
        t, w, _ = memory_totals(s)
        lines.append(
            f"| {_when(s)} | {s.get('client', '?')} | {float(s.get('uptime') or 0):.0f} | "
            f"{t / 1024:.2f} | "
            f"{w / 1024:.2f} | {len(breaches(s))} |"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="perf report from /bastians perf snapshots (nfr.md)"
    )
    parser.add_argument(
        "file", type=Path, help="Bastians_Core.lua from WTF/Account/<acc>/SavedVariables"
    )
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "perf-report.md")
    parser.add_argument("--last", type=int, default=0, help="history rows (default: all)")
    parser.add_argument(
        "--client", choices=("forever", "retail"), help="only snapshots of this client"
    )
    args = parser.parse_args(argv)
    try:
        snapshots = read_snapshots(args.file)
    except PerfReportError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    if args.client:
        snapshots = [s for s in snapshots if s.get("client") == args.client]
    text = render(snapshots, args.last)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_name(args.out.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(args.out)
    print(text)
    print(f"report: {args.out}")
    return 1 if snapshots and breaches(snapshots[-1]) else 0


if __name__ == "__main__":
    sys.exit(main())
