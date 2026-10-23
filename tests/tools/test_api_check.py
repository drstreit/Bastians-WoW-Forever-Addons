"""tools/api_check.py: API presence from a probe P1 dump (B1.7)."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import api_check  # noqa: E402

DUMP = """BastiansProbeDB = {
  ["meta"] = { ["client"] = "forever", ["build"] = "70450", ["interface"] = 16001 },
  ["results"] = {
    ["P1"] = {
      ["functions"] = { "GetBuildInfo", "UnitPosition", "GetTrainerServiceInfo" },
      ["namespaces"] = {
        ["C_Map"] = { "GetBestMapForUnit", "GetWorldPosFromMapPos" },
        ["C_TaxiMap"] = { "GetAllTaxiNodes" },
      },
      ["tables"] = { "Settings", "Menu" },
      ["enums"] = { "QuestTag" },
    },
  },
}
"""


def write_dump(tmp_path: Path) -> Path:
    path = tmp_path / "2026-10-20-forever-70450.lua"
    path.write_text(DUMP, encoding="utf-8")
    return path


def test_status_distinguishes_present_absent_and_missing_namespaces(tmp_path):
    from bastians_build.sources import probe

    dump = probe.read_probe_dump(write_dump(tmp_path))
    api = api_check.ApiDump(dump.results["P1"])
    assert api.status("C_Map.GetWorldPosFromMapPos").startswith("present (C_Map: 2 functions)")
    assert api.status("C_Map.GetMapArtLayers") == "absent"
    assert api.status("C_QuestLog.GetInfo") == "namespace missing"
    assert api.status("UnitPosition") == "present"
    assert api.status("GetQuestLogTitle") == "absent"
    assert api.status("Settings") == "present (table)"
    assert api.status("C_TaxiMap") == "present (table)"


def test_compat_and_doc_names_are_collected():
    names = api_check.compat_names()
    assert "C_AddOns.LoadAddOn" in names and "C_Map.GetWorldPosFromMapPos" in names
    assert "InCombatLockdown" in names and "CreateFrame" not in names
    if api_check.API_DOC.is_file():  # docs/ is private: the public copy has no forever-api.md
        docs = api_check.doc_names()
        assert "C_TaxiMap.GetAllTaxiNodes" in docs and "UnitPosition" in docs


def test_cli_prints_lines_and_markdown(tmp_path, capsys):
    dump = write_dump(tmp_path)
    assert api_check.main([str(dump), "--names", "UnitPosition", "C_Nope.Fn"]) == 0
    out = capsys.readouterr().out
    assert "# 3 global functions, 2 namespaces (forever 70450)" in out
    assert "UnitPosition: present" in out and "C_Nope.Fn: namespace missing" in out
    assert api_check.main([str(dump), "--names", "GetBuildInfo", "--markdown"]) == 0
    assert (
        "| `GetBuildInfo` | present | P1, 2026-10-20-forever-70450.lua |" in capsys.readouterr().out
    )
    assert api_check.main([str(tmp_path / "missing.lua")]) == 2
    (tmp_path / "empty.lua").write_text("BastiansProbeDB = { results = {} }", encoding="utf-8")
    assert api_check.main([str(tmp_path / "empty.lua")]) == 2
    assert "no P1" in capsys.readouterr().err
