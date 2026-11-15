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
    for cmd in (
        "help",
        "status",
        "p4 Goldshire inn door",
        "p5 12345",
        "p10",
        "minimaps",  # without the suite it says so
        "unknown",
        "hide",
    ):
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


def test_the_chat_probes_count_and_never_name(lua):
    """plan-chat-v3.md §13: the calls, the item level, the whisper flags; no name, no word."""
    slash = lua.globals().SlashCmdList.BASTIANSPROBE
    lua.execute(
        """
        function GetAverageItemLevel() return 21.5, 20.25 end
        function GetInventoryItemLink(_, slot)
          if slot == 1 or slot == 16 then return "|cff1eff00|Hitem:" .. slot .. "|h[x]|h|r" end
        end
        C_Item = {
          GetDetailedItemLevelInfo = function(link) return link:find("item:1|") and 20 or 24 end,
        }
        function CombatLogGetCurrentEventInfo()
          return 0, "SPELL_DAMAGE", false, "Player-1-1", "", 0, 0, "Creature-0-1", "", 0, 0,
            1, "", 0, 37
        end
        function UnitGUID() return "Player-1-1" end
        """
    )
    slash("chat")
    slash("combatlog")
    lua.globals().stub_fire(
        "CHAT_MSG_WHISPER",
        "hello there",
        "Testfriend-Realm",
        "",
        "",
        "",
        "GM",
        0,
        0,
        "",
        0,
        7,
        "Player-1-0002",
    )
    lua.globals().stub_fire("COMBAT_LOG_EVENT_UNFILTERED")
    text = "\n".join(messages(lua))
    assert "failed" not in text, text
    chat = lua.globals().BastiansProbeDB.results.chat
    assert chat.calls["GetAverageItemLevel"] == "function"
    assert chat.calls["ChatFrameUtil.SendTell"] == "nil"
    assert chat.average.ret[1] == 21.5
    assert (chat.worn.count, chat.worn.mean) == (2, 22)
    e = chat.events.CHAT_MSG_WHISPER
    assert (e.count, e.flags.GM, e.guid.Player) == (1, 1, 1)

    def flat(t) -> str:
        if lua.globals().type(t) != "table":
            return str(t)
        return " ".join(f"{k}={flat(v)}" for k, v in t.items())

    saved = flat(chat)
    assert "Testfriend" not in saved and "hello" not in saved
    log = lua.globals().BastiansProbeDB.results.combatlog
    assert log.registered is True
    assert (log.count, log.done.damage, log.subevents.SPELL_DAMAGE) == (1, 37, 1)
