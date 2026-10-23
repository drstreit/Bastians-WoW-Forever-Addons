"""tools/probe_import.py: finds the newest saved file and copies it under its canonical name."""

import os

import pytest
from install import InstallError
from probe_import import find_saved_variables, import_probe

SAVED = """BastiansProbeDB = {
["meta"] = {
["client"] = "forever",
["build"] = "70450",
["updated"] = "2026-10-20T19:12:03Z",
},
["results"] = {
},
}
"""


def write_saved(client_dir, account, text, mtime):
    path = client_dir / "WTF" / "Account" / account / "SavedVariables" / "Bastians_Probe.lua"
    path.parent.mkdir(parents=True)
    path.write_text(text, encoding="utf-8")
    os.utime(path, (mtime, mtime))
    return path


def test_newest_saved_file_wins(tmp_path):
    write_saved(tmp_path, "ACCOUNT1", SAVED, 1_000)
    newest = write_saved(tmp_path, "ACCOUNT2", SAVED, 2_000)
    assert find_saved_variables(tmp_path) == newest


def test_missing_saved_file_is_a_clear_error(tmp_path):
    with pytest.raises(InstallError, match="Run /bprobe"):
        find_saved_variables(tmp_path)


def test_import_names_by_date_client_build_and_is_idempotent(tmp_path):
    source = write_saved(tmp_path / "wow", "ACCOUNT", SAVED, 1_000)
    out = tmp_path / "probe"
    target, changed = import_probe(source, out)
    assert target.name == "2026-10-20-forever-70450.lua"
    assert changed
    assert target.read_text(encoding="utf-8") == SAVED
    assert import_probe(source, out) == (target, False)


def test_file_without_meta_is_refused(tmp_path):
    source = write_saved(tmp_path, "ACCOUNT", "BastiansProbeDB = {}\n", 1_000)
    with pytest.raises(InstallError, match="meta"):
        import_probe(source, tmp_path / "probe")
