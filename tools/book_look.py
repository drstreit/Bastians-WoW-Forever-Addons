"""Holds Bastian's Book as the game laid it out against its look in numbers (M5).

Usage: python tools/book_look.py [path to Bastians_Probe.lua]

Reads the record `/bprobe booklook` wrote into the probe's saved variables (the client's
`WTF/Account/<account>/SavedVariables/Bastians_Probe.lua`, written at /reload or logout; without
a path, the newest one under the Forever client `tools/install.py` knows, `.local/install.toml`) and
prints, for each width it measured, every number of docs/addons/book-look.md sections 3 to 6
beside what the client drew (plan-book-round3.md, M5), and the same for the record of
`/bprobe booklook small` (the room of a 1,920 x 1,080 screen) when there is one. Exit code 1
when a place is off by more than a unit or a size by more than half a unit (R4.14: a unit hid a
title of 17 for 18 and a padding of 9 for 10), 2 when there is no record.
"""

from __future__ import annotations

import argparse
import itertools
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / ".local" / "install.toml"  # tools/install.py: the clients' folders
RESULTS = "BastiansProbeDB and BastiansProbeDB.results and BastiansProbeDB.results."
RECORD = RESULTS + "booklook"
SMALL = RESULTS + "booklookSmall"  # `/bprobe booklook small`: a 1,920 x 1,080 screen's room
TOLERANCE = 1.0  # UI units, for a place (the game lays out on whole pixels)
SIZE_TOLERANCE = 0.5  # UI units, for a size: a text's, a part's height, a padding

# the look in numbers (docs/addons/book-look.md sections 4 to 6)
HEAD = 50
BAR_ITEM = 28
GEAR = 20
LOGO = 34
CHIP = 22
CHIP_RADIUS = 11
ROW_GAP = 8
SLIDER = (204, 34)
BAND_TOP, BAND_SIDE = 10, 15
LABEL_W = 41
TILE_GAP = 11
SIZES = {"title": 18, "tab": 13, "tool": 13, "atlas": 13, "chip": 11, "label": 11}
# the dark table (section 3), the WoW look only
DARK = {"band": "#1a1410", "rule": "#4a3b2c", "table": "#120e0b"}
# a row is a chip's or the slider's, whose chips sit 6 lower in a row of 34
ROW_STEPS = (CHIP + ROW_GAP, CHIP + ROW_GAP + 6, SLIDER[1] + ROW_GAP - 6)


@dataclass
class Check:
    what: str
    want: object
    got: object
    ok: bool


def _near(got: object, want: float, tolerance: float = TOLERANCE) -> bool:
    return isinstance(got, (int, float)) and abs(float(got) - want) <= tolerance


def _round(value: object) -> object:
    return round(value, 1) if isinstance(value, (int, float)) else value


def _hex(colour: object) -> str | None:
    if colour is None or colour["r"] is None:
        return None
    return "#" + "".join(f"{round(colour[k] * 255):02x}" for k in ("r", "g", "b"))


def _list(table: object) -> list:
    return [] if table is None else [table[i] for i in range(1, len(table) + 1)]


def checks(run, look: str | None, game_framed: bool) -> list[Check]:
    """The spec's numbers against one measured width."""
    out: list[Check] = []

    def near(what: str, want: float, got: object, tolerance: float = TOLERANCE) -> None:
        out.append(Check(what, want, _round(got), _near(got, want, tolerance)))

    def size(what: str, rect, key: str, want: float) -> None:
        near(what, want, rect[key] if rect is not None else None, SIZE_TOLERANCE)

    size("the head's height", run.head, "height", HEAD)
    if run.oneBar:
        size("the tabs' height", run.tabs, "height", BAR_ITEM)
        size("a tab's height", run.tab, "height", BAR_ITEM)
        size("the search's height", run.search, "height", BAR_ITEM)
        for name in ("record", "atlas"):
            size(f"the tool {name}: height", run.tools[name], "height", BAR_ITEM)
        size("the options' pictogram", run.tools.gear, "width", GEAR)
        if not game_framed:
            size("the logo", run.tools.logo, "width", LOGO)
        if run.band is not None and run.head is not None and run.band.top is not None:
            foot = run.head.top + run.head.height
            near("the band directly under the bar", 0, run.band.top - foot)
    chips = _list(run.chips)
    if chips:
        heights = sorted({round(c.height, 1) for c in chips if c.height is not None})
        all_high = all(_near(h, CHIP, SIZE_TOLERANCE) for h in heights)
        out.append(Check("every chip's height", CHIP, heights, all_high))
        radii = sorted({c.radius for c in chips if c.radius is not None})
        round_ends = radii == [CHIP_RADIUS]
        out.append(Check("every chip's corner (round ends)", CHIP_RADIUS, radii, round_ends))
        first = chips[0]
        if run.band is not None and run.band.top is not None and first.top is not None:
            pad = first.top - run.band.top
            near("the band's padding over the first chip", BAND_TOP, pad, SIZE_TOLERANCE)
            column = BAND_SIDE + LABEL_W
            near("the first chip after the label column", column, first.left - run.band.left)
        tops = sorted({round(c.top, 1) for c in chips if c.top is not None})
        steps = [round(b - a, 1) for a, b in itertools.pairwise(tops)]
        pitched = all(any(_near(s, a) for a in ROW_STEPS) for s in steps)
        out.append(Check("the rows' pitch", sorted(ROW_STEPS), steps, pitched))
    if run.slider is not None and run.slider.width is not None:
        size("the slider's width", run.slider, "width", SLIDER[0])
        size("the slider's height", run.slider, "height", SLIDER[1])
    for row in _list(run.rows):
        tiles = _list(row.tiles)
        if len(tiles) >= 2 and tiles[0].left is not None:
            near(
                "the gap between two tiles",
                TILE_GAP,
                tiles[1].left - tiles[0].left - tiles[0].width,
                SIZE_TOLERANCE,
            )
            if run.body is not None and run.body.left is not None:
                inset = tiles[0].left - run.body.left
                near("the table's padding left of the tiles", BAND_SIDE, inset)
            break
    for name, want in SIZES.items():
        if name == "title" and game_framed:
            continue  # the game's own title bar carries the name there, the book's is not drawn
        face = run.fonts[name]
        # the reader's text size setting scales every text; at 100 % these hold
        got = face.size if face is not None else None
        near(f"the {name}'s text size", want, got, SIZE_TOLERANCE)
    if look == "wow":
        for name, want in DARK.items():
            got = _hex(run.colours[name])
            out.append(Check(f"the {name}'s colour (the dark table)", want, got, got == want))
    return out


def saved_variables(config: Path = INSTALL) -> Path | None:
    """The probe's newest saved variables under the Forever client; None when there are none."""
    if not config.is_file():
        return None
    client = tomllib.loads(config.read_text(encoding="utf-8")).get("clients", {}).get("forever")
    if not client:
        return None
    found = Path(client).glob("WTF/Account/*/SavedVariables/Bastians_Probe.lua")
    return max(found, key=lambda f: f.stat().st_mtime, default=None)


def load(path: Path, record: str = RECORD):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(path.read_text(encoding="utf-8", errors="replace"))
    return lua.eval(record)


def report(record) -> tuple[list[str], bool]:
    look = None
    if record.look is not None and record.look.ok:
        look = record.look.ret[1]
    lines = [f"booklook {record.at}: look {look}, the game's frame {bool(record.gameFramed)}"]
    if record.small is not None:
        # the layout is the small screen's; the sharpness is this screen's
        lines.append(
            f"the small screen: {record.small.height} units high, the window scaled by "
            f"{_round(record.small.factor)}, room {_round(record.room.width)} x "
            f"{_round(record.room.height)} units"
        )
    good = True
    for run in _list(record.runs):
        lines.append(f"\nwidth {run.width} (asked {run.asked}), one bar: {bool(run.oneBar)}")
        if run.error:
            lines.append(f"  error: {run.error}")
            good = False
            continue
        for check in checks(run, look, bool(record.gameFramed)):
            mark = "ok " if check.ok else "OFF"
            lines.append(f"  {mark} {check.what}: spec {check.want}, drawn {check.got}")
            good = good and check.ok
    return lines, good


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", type=Path)
    args = parser.parse_args(argv)
    path = args.path or saved_variables()
    if path is None or not path.is_file():
        print(f"no saved variables at {path or 'the Forever client of .local/install.toml'}")
        return 2
    record = load(path)
    if record is None:
        print("no booklook record: run /bprobe booklook in the game, then /reload")
        return 2
    lines, good = report(record)
    small = load(path, SMALL)
    if small is not None:
        more, small_good = report(small)
        lines += ["", *more]
        good = good and small_good
    print("\n".join(lines))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
