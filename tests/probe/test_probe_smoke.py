"""Smoke test: Bastians_Probe loads on Lua 5.1 and every probe runs on a stub client without errors.

The full WoW mock arrives with roadmap item B2.2; this stub only needs to keep the probe honest
before the Forever beta evenings.
"""

from pathlib import Path

import pytest
from lupa import lua51

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "addons" / "Bastians_Probe" / "Probe.lua"

STUB = Path(__file__).with_name("stub_client.lua")


@pytest.fixture
def lua():
    runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(STUB.read_text(encoding="utf-8"))
    chunk = runtime.compile(PROBE.read_text(encoding="utf-8"))
    chunk("Bastians_Probe", runtime.table())
    runtime.globals().stub_fire("ADDON_LOADED", "Bastians_Probe")
    runtime.globals().stub_fire("PLAYER_LOGIN")
    return runtime


def messages(lua) -> list[str]:
    return list(lua.globals().stub_messages().values())


def test_all_probes_run_without_errors(lua):
    lua.globals().SlashCmdList.BASTIANSPROBE("all")
    lua.globals().stub_drain()
    text = "\n".join(messages(lua))
    assert "failed" not in text, text
    assert "all done" in text
    results = lua.globals().BastiansProbeDB.results
    for probe in ("P1", "P2", "P3", "P5", "P6", "P10"):
        assert results[probe] is not None, probe
    assert results.P3.found == 2
    assert results.P2.completedModern == 3
    assert lua.globals().BastiansProbeDB.meta.client == "forever"


def test_single_probes_and_passive_handlers(lua):
    slash = lua.globals().SlashCmdList.BASTIANSPROBE
    for cmd in ("help", "status", "p4 Goldshire inn door", "p5 12345", "p10", "unknown", "hide"):
        slash(cmd)
    for event in ("TAXIMAP_OPENED", "TRAINER_SHOW", "MERCHANT_SHOW", "PLAYER_CONTROL_GAINED"):
        lua.globals().stub_fire(event)
    text = "\n".join(messages(lua))
    assert "failed" not in text, text
    results = lua.globals().BastiansProbeDB.results
    assert results.P4[1].label == "Goldshire inn door"
    # the stub's target is Creature 448 (UnitGUID); its name comes from UnitName when present
    assert (results.P4[1].target.kind, results.P4[1].target.id) == ("npc", 448)
    assert "target npc 448" in text
    # without a target the landmark carries none (UnitGUID nil arrives packed as "<nil>")
    lua.execute("function UnitGUID() return nil end")
    slash("p4 no target")
    assert results.P4[2].target is None
    assert "target ? nil" not in chr(10).join(messages(lua))
    assert results.P7.opens[1] is not None
    assert results.trainer[1] is not None
    assert results.merchant[1] is not None
