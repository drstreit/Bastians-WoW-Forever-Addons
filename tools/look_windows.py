"""Names what overflows in every app's window, as the game laid them out in the one look (W4).

Usage: python tools/look_windows.py [path to Bastians_Probe.lua]

Reads the record `/bprobe windows` wrote into the probe's saved variables (the client's
`WTF/Account/<account>/SavedVariables/Bastians_Probe.lua`, written at /reload or logout; without a
path, the newest one under the Forever client `tools/install.py` knows, `.local/install.toml`) and
prints each window the probe opened: its size, whether the game's frame was around it, and what
overflows: labels the kit cut (the tooltip carries them whole), texts wider than their room, parts
standing outside the window (plan-suite-waves.md W4: "a probe photographs every app's window and
names what overflows; no app changed to make it fit", that is W9). The screenshots lie in the
client's Screenshots folder. Exit code 0 with a record (an overflow is named, not a failure), 2
without one.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from book_look import RESULTS, load, saved_variables

RECORD = RESULTS + "windows"


def _list(table: object) -> list:
    return [] if table is None else list(table.values())


def _n(value: object) -> str:
    return "?" if value is None else str(round(float(value)))


def report(record) -> list[str]:
    windows = _list(record.windows)
    lines = [
        f"windows {record.at}, build {record.build}: theme {record.theme}, look {record.look},"
        f" the game's frame {bool(record.gameFrames)}; {len(windows)} windows"
    ]
    for w in windows:
        cut, wide, outside = _list(w.cut), _list(w.wide), _list(w.outside)
        frame = "in the game's frame" if w.gameFramed else "own edge"
        mark = "ok " if not (cut or wide or outside) else "   "
        lines.append(f"\n{mark}{w.app} / {w.window}: {_n(w.width)} x {_n(w.height)}, {frame}")
        for label in cut:
            lines.append(f"    cut: {label}")
        for t in wide:
            lines.append(f"    too wide: {t.text!r} needs {_n(t.needs)} in {_n(t.room)}")
        for o in outside:
            past = [
                f"{side} {_n(abs(v))}"
                for side, v in (("left", -o.l), ("right", o.r), ("top", o.t), ("bottom", -o.b))
                if v is not None and v > 1
            ]
            lines.append(f"    outside: {o.what} ({', '.join(past)})")
    cities = record.cities
    if cities is not None and cities.why:
        lines.append(f"\ncity map: {cities.why}")
    elif cities is not None:
        lines.append(
            "\nthe city map's pins (all its layers asked, whether on or not for trainers):"
        )
        for c in _list(cities):
            if c.why:
                lines.append(f"    {c.name}: {c.why}")
                continue
            cut = max(0, (c.total or 0) - (c.cap or 0))
            layers = ", ".join(f"{k} {v}" for k, v in sorted(dict(c.byLayer or {}).items()))
            lines.append(
                f"    {c.name}: {c.total} pins (cap {c.cap}, {cut} cut): {layers or 'none'};"
                f" trainers {c.trainers} (layer {'on' if c.trainersOn else 'off'})"
            )
            missing = _list(c.missing)
            if missing:
                lines.append(f"      trainers not drawn: {'; '.join(str(m) for m in missing)}")
    skipped = _list(record.skipped)
    if skipped:
        lines.append("\nnot photographed:")
        lines += [f"    {s.app}{' / ' + s.window if s.window else ''}: {s.why}" for s in skipped]
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", type=Path)
    args = parser.parse_args(argv)
    path = args.path or saved_variables()
    if path is None or not path.is_file():
        print(f"no saved variables at {path or 'the Forever client of .local/install.toml'}")
        return 2
    record = load(path, RECORD)
    if record is None:
        print("no windows record: run /bprobe windows in the game, then /reload")
        return 2
    print("\n".join(report(record)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
