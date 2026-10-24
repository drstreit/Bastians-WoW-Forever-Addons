"""The tool tests never write into the repository's .local (CLAUDE.md section 7): the folder where
tools/curseforge.py keeps the files it sent points into each test's temp directory."""

import pytest


@pytest.fixture(autouse=True)
def _released_in_tmp(tmp_path, monkeypatch):
    import curseforge

    monkeypatch.setattr(curseforge, "RELEASED", tmp_path / "released")
