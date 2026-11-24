"""Names what overflows in every app's window and holds its head against the frame's numbers
(W4, W5).

Usage: python tools/look_windows.py [path to Bastians_Probe.lua]

Reads the record `/bprobe windows` wrote into the probe's saved variables (the client's
`WTF/Account/<account>/SavedVariables/Bastians_Probe.lua`, written at /reload or logout; without a
path, the newest one under the Forever client `tools/install.py` knows, `.local/install.toml`) and
prints each window the probe opened: its size, whether the game's frame was around it, and what
overflows: labels the kit cut (the tooltip carries them whole), texts wider than their room, parts
standing outside the window (plan-suite-waves.md W4: "a probe photographs every app's window and
names what overflows; no app changed to make it fit", that is W9). Since W5 each window's head
is held against the frame's numbers (ADR 0084 decisions 2 to 4: a tall head 50 high, a low one
30, in the game's frame under its title strip of 22; a bare head has none), at the window's own
size and at 1,100, 1,532 and 2,100 wide and on the small screen's scale where its bounds allow.
The screenshots lie in the client's Screenshots folder. Exit code 0 with a record and every head
as specified (an overflow is named, not a failure), 1 when a head differs, 2 without a record.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from book_look import RESULTS, load, saved_variables

RECORD = RESULTS + "windows"

# The frame in numbers (addons/Bastians_Core/UI/Window.lua: Window.HEADS, CHROME_TITLE,
# CHROME_SIDE, PORTRAIT_X), held to half a unit.
HEADS = {"tall": 50, "low": 30}
NAME = {"tall": 18, "low": 13}
MARK = {"tall": 34, "low": 20}
STRIP = 22
SIDE = 6
RING = 58
TOLERANCE = 0.5


def _off(got: object, want: float) -> bool:
    return got is None or abs(float(got) - want) > TOLERANCE


def head_faults(head, framed: bool) -> list[str]:
    """What of a window's head differs from the frame's numbers; empty when it is as specified."""
    if head is None or head.kind is None:
        return ["no head recorded (a window Core did not build, or a probe before W5)"]
    kind = str(head.kind)
    out: list[str] = []
    if kind not in HEADS:
        return [f"an unknown head kind {kind!r}"]
    bare = bool(head.bare)
    if framed and bare:
        if head.shown:
            out.append("a bare head shows its band in the game's frame")
        if _off(head.contentTop, STRIP):
            out.append(f"the content starts {_n(head.contentTop)} under the top, {STRIP} wanted")
        return out
    if _off(head.height, HEADS[kind]):
        out.append(f"the head is {_n(head.height)} high, {HEADS[kind]} wanted")
    top = STRIP if framed else 1
    if _off(head.top, top):
        out.append(f"the head lies {_n(head.top)} under the top, {top} wanted")
    if _off(head.contentTop, top + HEADS[kind]):
        out.append(
            f"the content starts {_n(head.contentTop)} under the top, {top + HEADS[kind]} wanted"
        )
    if framed:
        ring = kind == "tall" or not head.portraitGone
        left = RING if ring else SIDE
        if _off(head.left, left):
            out.append(f"the head starts {_n(head.left)} from the left, {left} wanted")
        if head.nameShown:
            out.append("the head shows the name beside the game's title strip")
    else:
        if _off(head.nameSize, NAME[kind]):
            out.append(f"the name is {_n(head.nameSize)}, {NAME[kind]} wanted")
        if _off(head.mark, MARK[kind]):
            out.append(f"the home mark is {_n(head.mark)}, {MARK[kind]} wanted")
    return out


def _list(table: object) -> list:
    return [] if table is None else list(table.values())


def _n(value: object) -> str:
    return "?" if value is None else str(round(float(value)))


def report(record) -> tuple[list[str], int]:
    """The record in lines, and how many heads differ from the frame's numbers."""
    windows = _list(record.windows)
    lines = [
        f"windows {record.at}, build {record.build}: theme {record.theme}, look {record.look},"
        f" the game's frame {bool(record.gameFrames)}; {len(windows)} windows"
    ]
    wrong = 0
    for w in windows:
        cut, wide, outside = _list(w.cut), _list(w.wide), _list(w.outside)
        frame = "in the game's frame" if w.gameFramed else "own edge"
        faults = head_faults(w.head, bool(w.gameFramed))
        mark = "ok " if not (cut or wide or outside or faults) else "   "
        kind = w.head.kind if w.head is not None and w.head.kind else "?"
        bare = ", bare" if w.head is not None and w.head.bare else ""
        lines.append(
            f"\n{mark}{w.app} / {w.window}: {_n(w.width)} x {_n(w.height)}, {frame},"
            f" head {kind}{bare}"
        )
        for fault in faults:
            wrong += 1
            lines.append(f"    HEAD: {fault}")
        for v in _list(w.variants):
            vf = head_faults(v.head, bool(w.gameFramed))
            wrong += len(vf)
            over = (v.cut or 0) + (v.wide or 0) + (v.outside or 0)
            what = "the small screen, " if v.small else ""
            own_row = v.head is not None and v.head.barRow
            row = " (the tabs on a row of their own)" if own_row else ""
            state = "head ok" if not vf else "HEAD: " + "; ".join(vf)
            first = f", first {v.first!r}" if over and v.first else ""
            lines.append(f"    at {what}{_n(v.width)} wide: {state}{row}; {over} overflow{first}")
        for label in cut:
            lines.append(f"    cut: {label}")
        for t in wide:
            where = f" ({t.where})" if t.where else ""
            lines.append(f"    too wide: {t.text!r} needs {_n(t.needs)} in {_n(t.room)}{where}")
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
    lines.append(
        "\nevery head as the frame specifies it"
        if wrong == 0
        else f"\n{wrong} head measure(s) differ from the frame's numbers"
    )
    return lines, wrong


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
    lines, wrong = report(record)
    print("\n".join(lines))
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
