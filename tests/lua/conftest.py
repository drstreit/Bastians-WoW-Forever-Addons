"""Fixtures for the Lua tests: one WowRuntime per client, so every module test runs on both."""

import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from harness import CLIENTS, WowRuntime  # noqa: E402

FIXTURE_ADDONS = HERE.parent / "fixtures" / "addons"


@pytest.fixture(params=CLIENTS)
def wow(request) -> WowRuntime:
    """A fresh mock client that knows the fixture addons too; one per client (forever, retail)."""
    return WowRuntime(request.param, extra_dirs=(FIXTURE_ADDONS,))


@pytest.fixture
def core(wow: WowRuntime) -> WowRuntime:
    """A client with Bastians_Core loaded and logged in."""
    wow.start("Bastians_Core")
    return wow


@pytest.fixture
def app(wow: WowRuntime) -> WowRuntime:
    """Core plus the fixture app Bastians_TestApp, logged in."""
    wow.start("Bastians_Core", "Bastians_TestApp")
    return wow
