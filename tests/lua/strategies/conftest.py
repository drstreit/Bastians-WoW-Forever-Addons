"""The Strategies book is Forever's only ("we do not collect gold strategies for
retail"): its TOCs name interface 16001, so its tests run on the Forever mock alone."""

from pathlib import Path

import pytest
from harness import WowRuntime

FIXTURE_ADDONS = Path(__file__).resolve().parents[2] / "fixtures" / "addons"


@pytest.fixture(params=["forever"])
def wow(request) -> WowRuntime:
    return WowRuntime(request.param, extra_dirs=(FIXTURE_ADDONS,))
