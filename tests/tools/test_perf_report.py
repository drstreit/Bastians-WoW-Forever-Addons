"""tools/perf_report.py (B11.1): snapshots from a Bastians_Core.lua saved-variables file, the budget
table with breaches, history, and the exit code that gates a release."""

from pathlib import Path

import perf_report
import pytest

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "savedvariables" / "Bastians_Core.lua"


def test_snapshots_are_read_oldest_first():
    snaps = perf_report.read_snapshots(FIXTURE)
    assert [s["uptime"] for s in snaps] == [120, 3600]
    assert snaps[1]["modules"]["Gold"]["maxMs"] == 3.9
    total, without, packs = perf_report.memory_totals(snaps[1])
    assert (total, without, packs) == (19000, 5000, True)
    assert perf_report.memory_totals(snaps[0]) == (4000, 4000, False)


def test_breaches_follow_the_nfr_budgets():
    snaps = perf_report.read_snapshots(FIXTURE)
    assert perf_report.breaches(snaps[0]) == ["module Map max 9.50 ms over 8 ms"]
    assert (
        perf_report.breaches(snaps[1]) == []
    )  # Map at 6.5 ms is within its 8 ms, Gold within 4 ms
    heavy = dict(snaps[1])
    heavy["memoryKB"] = {"Bastians_Core": 9000, "Bastians_Data_World": 30000}
    assert perf_report.breaches(heavy) == [
        "memory without packs 8.8 MB over 8 MB",
        "memory with packs 38.1 MB over 35 MB",
    ]


def test_report_renders_and_the_exit_code_gates(tmp_path, capsys):
    out = tmp_path / "perf.md"
    assert perf_report.main([str(FIXTURE), "--out", str(out)]) == 0  # the newest snapshot is clean
    text = out.read_text(encoding="utf-8")
    assert "| Memory with data packs | 18.55 MB | < 35 MB | ok |" in text
    assert "| Longest frame, Map | 6.50 ms | < 8 ms | ok |" in text
    assert "| Bastians_Data_World | 9000 |" in text and "| **total** | **19000** |" in text
    assert text.count("| 2025-10-09") == 2  # two history rows
    assert "none" in text.split("## Breaches")[1].split("## History")[0]
    assert not list(tmp_path.glob("*.tmp"))
    # a file whose newest snapshot breaches returns 1
    broken = tmp_path / "Bastians_Core.lua"
    broken.write_text(
        FIXTURE.read_text(encoding="utf-8").replace('["maxMs"] = 6.5', '["maxMs"] = 16.5'),
        encoding="utf-8",
    )
    assert perf_report.main([str(broken), "--out", str(out)]) == 1
    assert "**BREACH**" in out.read_text(encoding="utf-8")
    assert perf_report.main([str(tmp_path / "missing.lua"), "--out", str(out)]) == 2
    assert "error:" in capsys.readouterr().err


def test_empty_and_foreign_files(tmp_path):
    empty = tmp_path / "x.lua"
    empty.write_text("BastiansCoreDB = { global = { perf = {} } }", encoding="utf-8")
    assert "No snapshots" in perf_report.render(perf_report.read_snapshots(empty))
    other = tmp_path / "y.lua"
    other.write_text("SomethingElse = {}", encoding="utf-8")
    with pytest.raises(perf_report.PerfReportError, match="no BastiansCoreDB"):
        perf_report.read_snapshots(other)
