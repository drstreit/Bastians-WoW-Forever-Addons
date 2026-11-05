"""Owner, Forever launch night 05.11.2026: "[warn] Core: bus message BASTIANS_ACTION_STATE is not in
the catalogue (core-contracts §16)". Core declares the cross-app messages of the §16 catalogue itself;
an app declares only the messages it owns. Every §16 row must be declared once all apps are loaded."""

import re
from pathlib import Path

import pytest
from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "docs" / "architecture" / "core-contracts.md"

# the §16 table rows: "| `BASTIANS_X` | args | ..."
ROW = re.compile(r"^\| `(BASTIANS_[A-Z_]+)` \|", re.MULTILINE)

ALL_ADDONS = [
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
    "Bastians_Notes",
    "Bastians_Alts",
    "Bastians_Helpers",
    "Bastians_Voice",
    "Bastians_Gestures",
    "Bastians_Campfire",
    "Bastians_Chat",
]


def test_core_declares_the_cross_app_messages(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.run_frames(2)
    for name in ("BASTIANS_ACTION_STATE", "BASTIANS_REWARD_INFO_CHANGED"):
        assert wow.eval(f"Bastians.Messages['{name}']") is True, name
    assert wow.errors == []


def test_every_catalogue_row_is_declared_with_all_apps_loaded(wow: WowRuntime):
    if wow.client != "forever":
        pytest.skip("Campfire is Forever-only; the whole catalogue is checked on Forever")
    if not CONTRACTS.is_file():
        pytest.skip("core-contracts.md is private; the public snapshot has no catalogue to read")
    rows = sorted(set(ROW.findall(CONTRACTS.read_text(encoding="utf-8"))))
    assert rows, "no §16 rows found in core-contracts.md"
    present = [a for a in ALL_ADDONS if (ROOT / "addons" / a).is_dir()]
    wow.start(*present)
    wow.run_frames(10)
    missing = [name for name in rows if wow.eval(f"Bastians.Messages['{name}']") is not True]
    assert missing == []
    assert wow.errors == []
