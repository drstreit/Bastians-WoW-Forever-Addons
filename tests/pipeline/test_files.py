"""The atomic write (CLAUDE.md section 6) and its patience with a file a sync client holds: the
repository lives in OneDrive, which held fresh packs while uploading them (beta.13, 29.10.2026)."""

from pathlib import Path

import pytest

from bastians_build import files


def test_a_held_file_is_replaced_once_it_is_free(tmp_path: Path, monkeypatch):
    target = tmp_path / "Pack.lua"
    target.write_text("old\n", encoding="utf-8")
    real = Path.replace
    refusals = {"left": 3}

    def held(self, other):
        if refusals["left"]:
            refusals["left"] -= 1
            raise PermissionError(5, "Zugriff verweigert")
        return real(self, other)

    monkeypatch.setattr(Path, "replace", held)
    slept = []
    monkeypatch.setattr(files.time, "sleep", slept.append)
    assert files.write_text(target, "new\n") is True
    assert target.read_text(encoding="utf-8") == "new\n" and len(slept) == 3
    assert files.write_text(target, "new\n") is False  # unchanged: nothing written


def test_a_file_held_for_good_still_fails(tmp_path: Path, monkeypatch):
    def held(self, other):
        raise PermissionError(5, "Zugriff verweigert")

    monkeypatch.setattr(Path, "replace", held)
    monkeypatch.setattr(files.time, "sleep", lambda s: None)
    with pytest.raises(PermissionError):
        files.write_text(tmp_path / "Pack.lua", "x\n")
