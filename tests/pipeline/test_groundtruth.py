"""Ground-truth check (B3.8): measured NPC places against the built world, report section, CLI."""

from pathlib import Path

import pytest

from bastians_build.__main__ import main
from bastians_build.build import build
from bastians_build.config import load_config
from bastians_build.groundtruth import (
    GroundTruthError,
    compare,
    read_truth,
    render_section,
    summary,
)
from bastians_build.sources.fixture import read_fixture

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "tests" / "fixtures" / "world-mini"
TRUTH = ROOT / "tests" / "fixtures" / "ground-truth" / "npc_places.csv"


def test_rows_are_read_as_map_fractions():
    rows = read_truth(TRUTH)
    assert [r.npc_id for r in rows] == [448, 240, 54, 999999]
    hogger = rows[0]
    assert (hogger.name, hogger.role, hogger.map) == ("Hogger", "mob", 1429)
    assert (hogger.x, hogger.y) == (pytest.approx(0.275), pytest.approx(0.863))


def test_compare_classifies_every_row():
    world = read_fixture(WORLD, "forever")
    checks = compare(world, read_truth(TRUTH))
    by_id = {c.npc_id: c for c in checks}
    assert by_id[448].status == "ok" and by_id[448].distance_pct == pytest.approx(0.58, abs=0.01)
    assert by_id[448].nearest == (0.27, 0.86, "eq")  # the nearer of Hogger's two spawns
    assert by_id[240].status == "off" and by_id[240].distance_pct == 3.0
    assert by_id[54].status == "no spawn on map"  # Corina has a spawn, but in Elwynn, not Stormwind
    assert by_id[999999].status == "missing npc"
    assert summary(checks) == {
        "checked": 4,
        "ok": 1,
        "off": 1,
        "no spawn on map": 1,
        "missing npc": 1,
    }
    lines = render_section(checks)
    assert lines[0] == "## Ground truth"
    assert "4 measured places checked, tolerance 1 map percent: 1 ok, 1 off" in lines[2]
    table = "\n".join(lines)
    assert "| Marshal Dughan (240) | 1429 | off | 3.00 | 42.0, 65.0 (eq) |" in table
    assert "| Nobody (999999) | 1429 | missing npc | - | - |" in table
    assert render_section(compare(world, []))[2].startswith("0 measured places checked")


def test_report_carries_the_section_only_when_asked(tmp_path):
    world = read_fixture(WORLD, "forever")
    plain = build(world, load_config(), tmp_path, write=False)
    assert plain.ground_truth is None
    result = build(world, load_config(), tmp_path, ground_truth=compare(world, read_truth(TRUTH)))
    report = result.report_path.read_text(encoding="utf-8")
    assert "## Ground truth" in report and report.index("## Ground truth") < report.index(
        "## Dropped rows"
    )
    assert "Marshal Dughan (240)" in report
    assert result.ok  # a bad place never fails the build


def test_cli_and_bad_files(tmp_path, capsys):
    argv = [
        "data",
        "--client",
        "forever",
        "--fixture",
        str(WORLD),
        "--ground-truth",
        str(TRUTH),
        "--out",
        str(tmp_path),
        "--report-dir",
        str(tmp_path),
    ]
    assert main(argv) == 0
    out = capsys.readouterr().out
    assert "ground truth: 4 checked, 1 ok, 1 off, 1 without a spawn on the map, 1 missing" in out
    assert "## Ground truth" in (tmp_path / "report.md").read_text(encoding="utf-8")
    bad = tmp_path / "bad.csv"
    bad.write_text("npc_id,x_pct\n1,2\n", encoding="utf-8")
    with pytest.raises(GroundTruthError, match="columns missing"):
        read_truth(bad)
    bad.write_text("npc_id,ui_map_id,x_pct,y_pct\nx,1429,1,2\n", encoding="utf-8")
    with pytest.raises(GroundTruthError, match="bad row"):
        read_truth(bad)
    assert (
        main([*argv[:5], "--ground-truth", str(tmp_path / "none.csv"), "--out", str(tmp_path)]) == 2
    )
    assert "not a file" in capsys.readouterr().err
