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


def test_a_new_build_is_probed_by_itself_once(lua):
    # plan-data-quality.md E5: the first login on a build runs P1, P3 and P2 without a command
    lua.globals().stub_drain()
    db = lua.globals().BastiansProbeDB
    assert db.auto.build == "70450" and db.auto.parts == "P1, P3, P2"
    for probe in ("P1", "P2", "P3"):
        assert db.results[probe] is not None, probe
    assert db.results.P5 is None  # the screenshot parts still wait for a hand
    text = "\n".join(messages(lua))
    assert "build 70450 is new to the probe" in text and "recorded by itself" in text
    before = len(messages(lua))
    lua.globals().stub_fire("PLAYER_LOGIN")  # the next login on the same build: nothing
    lua.globals().stub_drain()
    assert not any("new to the probe" in m for m in messages(lua)[before:])


def test_in_a_fight_the_automatic_probe_waits_for_its_end(lua):
    lua.execute("function InCombatLockdown() return true end")
    lua.globals().stub_drain()
    assert lua.globals().BastiansProbeDB.auto is None
    lua.execute("function InCombatLockdown() return false end")
    lua.globals().stub_fire("PLAYER_REGEN_ENABLED")
    lua.globals().stub_drain()
    assert lua.globals().BastiansProbeDB.auto.build == "70450"


def test_what_the_client_tells_in_play_is_kept_per_build(lua):
    # plan-data-quality.md E6: every NPC talked to, every merchant's whole stock, no player
    lua.execute(
        """
        function UnitName() return "Innkeeper Farley" end
        function GetMerchantNumItems() return 2 end
        C_MerchantFrame = { GetItemInfo = function(i)
          return { price = i * 100, stackCount = i == 1 and 5 or 1, numAvailable = -1 }
        end }
        function GetMerchantItemLink(i) return "|cff|Hitem:" .. (2588 + i) .. "::|h[x]|h|r" end
        """
    )
    fire = lua.globals().stub_fire
    fire("GOSSIP_SHOW")
    fire("MERCHANT_SHOW")
    truth = lua.globals().BastiansProbeDB.truth["70450"]
    npc = truth.npcs["npc:448"]
    assert (npc.name, npc.map, npc.seen, npc.wx) == ("Innkeeper Farley", 1429, 2, -9460.0)
    assert npc.kinds.gossip and npc.kinds.merchant
    stock = truth.merchants["npc:448"]
    assert stock["count"] == 2
    first = stock["items"][1]
    assert (first.item, first.price, first.stack, first.available) == (2589, 100, 5, -1)
    lua.execute('function UnitGUID() return "GameObject-0-1-0-1-1731-0000" end')
    fire("QUEST_DETAIL")
    assert truth.npcs["object:1731"].kinds.quest
    lua.execute('function UnitGUID() return "Player-1234-0ABCDEF1" end')
    fire("GOSSIP_SHOW")
    assert truth.count == 2  # a player is never kept
    assert "failed" not in "\n".join(messages(lua))
