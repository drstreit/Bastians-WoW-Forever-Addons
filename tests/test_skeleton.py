"""Skeleton checks: the TOC gate passes and the package imports."""

import check_toc

import bastians_build


def test_toc_check_passes():
    assert check_toc.check_all() == []


def test_package_imports():
    assert bastians_build.__version__ == "0.1.0"


def test_check_toc_detects_problems(tmp_path):
    folder = tmp_path / "Demo"
    folder.mkdir()
    (folder / "Demo.toc").write_text(
        "## Title: Demo\nMissing.lua\nTwice.lua\ntwice.lua\n", encoding="utf-8"
    )
    (folder / "Extra.lua").write_text("-- x\n", encoding="utf-8")
    (folder / "Twice.lua").write_text("-- x\n", encoding="utf-8")
    problems = check_toc.check_addon(folder)
    assert any("Interface" in p for p in problems)
    assert any("Version" in p for p in problems)
    assert any("Missing.lua" in p for p in problems)
    assert any("Extra.lua" in p for p in problems)
    # the client loaded Bastians_Map/Overview.lua twice on 20.10.2026 (listed twice, case ignored)
    assert any("listed twice" in p and "twice.lua" in p for p in problems)
