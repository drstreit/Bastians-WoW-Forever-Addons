"""Bastian's Gold is Forever's only ("Gold out, vendor prices only" on
retail): its TOC names interface 16001, so its tests run on the Forever mock alone."""

from pathlib import Path

import pytest
from harness import WowRuntime

FIXTURE_ADDONS = Path(__file__).resolve().parents[2] / "fixtures" / "addons"


@pytest.fixture(params=["forever"])
def wow(request) -> WowRuntime:
    return WowRuntime(request.param, extra_dirs=(FIXTURE_ADDONS,))
