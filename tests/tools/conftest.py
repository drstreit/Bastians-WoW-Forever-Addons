"""The tool tests never write into the repository's .local (CLAUDE.md section 7), nor read from it:
the folder where tools/curseforge.py keeps the files it sent, and the owner's approved book
pictures tools/data_update.py falls back to, point into each test's temp directory."""

import pytest


@pytest.fixture(autouse=True)
def _released_in_tmp(tmp_path, monkeypatch):
    import curseforge
    import data_update

    monkeypatch.setattr(curseforge, "RELEASED", tmp_path / "released")
    monkeypatch.setattr(data_update, "LOCAL_ART", tmp_path / "book-art" / "current")


@pytest.fixture(autouse=True)
def _sources_offline(monkeypatch):
    """The sources step (tools/sources_update.py, run by daily.py) asks neither CurseForge nor the
    machine's client in a test."""
    try:
        import sources_update
    except ImportError:  # the public snapshot has no daily run (tools/publish.py PRIVATE)
        return
    monkeypatch.setattr(sources_update, "latest_on_curseforge", lambda project: None)
    monkeypatch.setattr(sources_update, "client_build", lambda: None)
