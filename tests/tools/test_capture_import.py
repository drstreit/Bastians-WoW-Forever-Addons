"""tools/capture_import.py (catalog review B5, 07.11.2026): a player's pasted text, as the game's
Copy my captures writes it, is read whole (the line count and the checksum) into the capture the
nav build reads; a cut or changed paste is refused; the issue's other words are ignored."""

import hashlib
import json
from pathlib import Path

import capture_import as ci
import pytest

BODY = [
    "walk 1429 2140.5 1762000000 1000.0,-300.5;600.0,900.0;100.0,-300.0",
    "taxi taxinode:2>taxinode:4 95.0",
    "ride transport:176495 12.0,30.5",
]
TEXT = (
    "BASTIANS CAPTURE 1 forever 70790 2026-11-07T20:00:00Z\n"
    + "\n".join(BODY)
    + f"\nEND 3 {sum(chr(0).join([]).encode()) if False else ci.checksum(BODY)}\n"
)


def test_a_pasted_text_becomes_a_capture_and_a_cut_or_changed_one_is_refused(tmp_path: Path):
    parsed = ci.parse_text("Hi, here are mine:\n\n" + TEXT + "\nThanks!\n")
    assert (parsed["client"], parsed["build"], parsed["exported"]) == (
        "forever",
        "70790",
        "2026-11-07T20:00:00Z",
    )
    learned = parsed["learned"]
    assert learned["taxi"] == {"taxinode:2>taxinode:4": 95.0}
    assert learned["ride"] == {"transport:176495": [12.0, 30.5]}
    (walk,) = learned["walk"]
    assert walk["map"] == 1429 and walk["len"] == 2140.5 and walk["at"] == 1762000000.0
    assert walk["points"] == [[1000.0, -300.5], [600.0, 900.0], [100.0, -300.0]]
    cap = ci.capture(learned, parsed["client"], parsed["exported"])
    assert cap["walk"][0]["points"][1] == [600.0, 900.0] and cap["taxi"] == learned["taxi"]
    target, changed = ci.write_capture(cap, tmp_path, ci.text_tag(TEXT))
    assert (
        changed and target.name == f"2026-11-07-{hashlib.sha1(TEXT.encode()).hexdigest()[:8]}.json"
    )
    assert json.loads(target.read_text(encoding="utf-8"))["client"] == "forever"
    # a walk without a length or a time
    short = ci.parse_text(
        "BASTIANS CAPTURE 1 forever ? x\nwalk 1 - - 1.0,2.0;3.0,4.0\nEND 1 "
        + str(ci.checksum(["walk 1 - - 1.0,2.0;3.0,4.0"]))
        + "\n"
    )
    assert short["learned"]["walk"][0]["len"] is None and short["learned"]["walk"][0]["at"] is None
    # cut, changed, foreign
    with pytest.raises(ci.CaptureError, match="END line is missing"):
        ci.parse_text(TEXT.split("END")[0])
    with pytest.raises(ci.CaptureError, match="holds 2 lines, END says 3"):
        ci.parse_text(TEXT.replace(BODY[1] + "\n", ""))
    with pytest.raises(ci.CaptureError, match="checksum does not match"):
        ci.parse_text(TEXT.replace("95.0", "96.0"))
    with pytest.raises(ci.CaptureError, match="no 'BASTIANS CAPTURE' line"):
        ci.parse_text("just words")
    with pytest.raises(ci.CaptureError, match="version 2"):
        ci.parse_text(TEXT.replace("CAPTURE 1", "CAPTURE 2"))
    with pytest.raises(ci.CaptureError, match="cannot read: fly"):
        body = ["fly 1 2"]
        ci.parse_text(f"BASTIANS CAPTURE 1 forever 1 x\n{body[0]}\nEND 1 {ci.checksum(body)}\n")


def test_the_command_reads_a_file_or_an_issue(tmp_path: Path, monkeypatch, capsys):
    path = tmp_path / "paste.txt"
    path.write_text("From a player:\n" + TEXT, encoding="utf-8")
    assert ci.main(["--text", str(path), "--out", str(tmp_path / "caps")]) == 0
    out = capsys.readouterr().out
    assert out.startswith("written: ") and "(1 walks, 1 flight times, 1 rides; build 70790)" in out
    assert any(p.suffix == ".json" for p in (tmp_path / "caps" / "forever").iterdir())
    # an issue through gh: the body is the text; the file is named by the issue
    monkeypatch.setattr(
        ci,
        "issue_body",
        lambda number, runner=None: "## The text from Copy my captures\n\n" + TEXT,
    )
    assert ci.main(["--issue", "42", "--out", str(tmp_path / "caps")]) == 0
    assert (tmp_path / "caps" / "forever" / "2026-11-07-issue42.json").is_file()
    # a bad paste says why and fails
    (tmp_path / "bad.txt").write_text("nothing here", encoding="utf-8")
    assert ci.main(["--text", str(tmp_path / "bad.txt"), "--out", str(tmp_path / "caps")]) == 2
    assert "no 'BASTIANS CAPTURE' line" in capsys.readouterr().err
