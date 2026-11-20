"""`/bprobe booklook` and tools/book_look.py (plan-book-round3.md M5): the book measured as it is
laid out, at three widths, and the record held against docs/addons/book-look.md.

On the mock the frames have no layout, so the places are not what the client will answer; the
sizes, the radii, the faces and the colours are. The test holds the record's shape, that the
window comes back to the reader's size, and that the tool reads it and names what is off."""

import sys
from pathlib import Path

from harness import WowRuntime
from test_book_pages import MOD, boot

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
import book_look

OUT = "BastiansProbeDB.results.booklook"


def run_probe(wow: WowRuntime) -> None:
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe booklook")
    for _ in range(12):
        wow.advance(0.7)


def test_the_book_is_measured_at_three_widths_and_put_back(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    wow.execute(f"{MOD}.Window.win.db.size = {{ 940, 640 }}")
    run_probe(wow)
    assert wow.eval(f"#{OUT}.runs") == 3
    assert [wow.eval(f"{OUT}.runs[{i}].asked") for i in (1, 2, 3)] == [1100, 1532, 2100]
    run = f"{OUT}.runs[2]"
    assert wow.eval(f"{run}.error") is None
    assert wow.eval(f"{run}.head.height") == 50
    assert wow.eval(f"{run}.tools.record.height") == 28
    assert wow.eval(f"#{run}.chips") > 5
    assert wow.eval(f"{run}.chips[1].height") == 22 and wow.eval(f"{run}.chips[1].radius") == 11
    assert wow.eval(f"{run}.slider.width") == 204
    assert wow.eval(f"{run}.fonts.chip.size") == 11 and wow.eval(f"{run}.fonts.title.size") == 18
    assert wow.eval(f"{run}.colours.band.r ~= nil") is True
    assert wow.eval(f"{run}.screenshot.ok") is True
    # the reader's own size is back
    assert wow.eval(f"{MOD}.Window.win.frame:GetWidth()") == 940
    assert wow.errors == []


def test_the_tool_holds_the_record_against_the_look(wow: WowRuntime, tmp_path: Path):
    boot(wow)
    wow.slash("/bbook")
    run_probe(wow)
    record = wow.eval(OUT)
    lines, _ = book_look.report(record)
    text = "\n".join(lines)
    assert "width 1532" in text
    assert "ok  the head's height: spec 50, drawn 50" in text
    assert "ok  every chip's height: spec 22, drawn [22" in text
    assert "ok  every chip's corner (round ends): spec 11, drawn [11]" in text
    assert "ok  the chip's text size: spec 11, drawn 11" in text
    # a number that is off is named
    wow.execute(f"{OUT}.runs[1].head.height = 30")
    lines, good = book_look.report(wow.eval(OUT))
    assert good is False
    assert "OFF the head's height: spec 50, drawn 30" in "\n".join(lines)
    # a size is held to half a unit (R4.14): a unit hid a padding of 9 and a title of 17
    wow.execute(f"{OUT}.runs[1].head.height = 50; {OUT}.runs[1].fonts.title.size = 17")
    lines, good = book_look.report(wow.eval(OUT))
    assert good is False
    assert "OFF the title's text size: spec 18, drawn 17" in "\n".join(lines)
    # in the game's frame its own title bar carries the name: the book's is not held
    wow.execute(f"{OUT}.gameFramed = true")
    lines, good = book_look.report(wow.eval(OUT))
    assert "the title's text size" not in "\n".join(lines)
    wow.execute(f"{OUT}.gameFramed = nil; {OUT}.runs[1].fonts.title.size = 18")
    run = wow.eval(f"{OUT}.runs[1]")
    assert book_look.SIZE_TOLERANCE == 0.5 and book_look.TOLERANCE == 1.0
    assert all(c.ok for c in book_look.checks(run, None, False) if "text size" in c.what)
    # no record: the tool says what to do
    empty = tmp_path / "Bastians_Probe.lua"
    empty.write_text("BastiansProbeDB = { results = {} }\n", encoding="utf-8")
    assert book_look.main([str(empty)]) == 2
    assert book_look.main([str(tmp_path / "missing.lua")]) == 2
    # without a path: the newest saved variables under the client tools/install.py knows
    saved = tmp_path / "client" / "WTF" / "Account" / "SOMEONE" / "SavedVariables"
    saved.mkdir(parents=True)
    (saved / "Bastians_Probe.lua").write_text("BastiansProbeDB = {}", encoding="utf-8")
    config = tmp_path / "install.toml"
    client = (tmp_path / "client").as_posix()
    config.write_text(f'[clients]\nforever = "{client}"\n', encoding="utf-8")
    assert book_look.saved_variables(config) == saved / "Bastians_Probe.lua"
    assert book_look.saved_variables(tmp_path / "none.toml") is None
