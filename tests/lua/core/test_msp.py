"""Roleplay names through msp (plan-launch-version L3, plan-second-wave S8): Core's Compat reads
Total RP 3's and MyRolePlay's profiles (LibMSP's `msp`) read only, asks for missing ones at most
every 30 s, announces arrivals as BASTIANS_RP_NAME; Gestures' %rp, Chat's say and emote lines and
the Orbiter's line under the hub show the name; without msp everything answers nil."""

from harness import WowRuntime

CORE, CHAT, GESTURES, VOICE, DATA = (
    "Bastians_Core",
    "Bastians_Chat",
    "Bastians_Gestures",
    "Bastians_Voice",
    "Bastians_Data",
)
MSP = """
Requested = {}
msp = {
  char = {
    ["Tobb-MockRealm"] = { field = { NA = "|cff99ccffTobb Ironhand|r", NT = "Wandering cook", NI = "Tobbs" } },
    ["Lira-OtherRealm"] = { field = { NA = "Lira of the Vale" } },
    ["Nobody-MockRealm"] = { field = {} },
  },
  callback = { received = {} },
  Request = function(self, name, fields) Requested[#Requested + 1] = name end,
}
"""
TARGET = """
Mock.guids = Mock.guids or {} ; Mock.guids.target = 'Player-1-2'
Mock.unitNames = Mock.unitNames or {} ; Mock.unitNames.target = 'Tobb'
UnitIsPlayer = function(u) return u == 'player' or u == 'target' end
"""


def test_without_msp_every_answer_is_nil(wow: WowRuntime):
    wow.start(CORE)
    assert wow.eval("Bastians.Compat.HasMsp()") is False
    assert wow.eval("Bastians.Compat.MspName('Tobb')") is None
    assert wow.eval("Bastians.Compat.MspRequest('Tobb')") is False
    assert wow.errors == []


def test_names_are_read_plain_by_name_or_unit_and_requests_are_paced(wow: WowRuntime):
    wow.start(CORE)
    wow.execute(MSP)
    rp = wow.eval("Bastians.Compat.MspName('Tobb')")
    assert (rp.name, rp.title, rp.nick) == ("Tobb Ironhand", "Wandering cook", "Tobbs")
    assert wow.eval("Bastians.Compat.MspName('Lira-OtherRealm').name") == "Lira of the Vale"
    assert wow.eval("Bastians.Compat.MspName('Nobody')") is None  # a profile without a name
    wow.execute(TARGET)
    assert wow.eval("Bastians.Compat.MspName('target').name") == "Tobb Ironhand"
    assert wow.eval("Bastians.Compat.MspRequest('Stranger')") is True
    assert wow.eval("Bastians.Compat.MspRequest('Stranger')") is False  # 30 s pause per player
    wow.advance(31)
    assert wow.eval("Bastians.Compat.MspRequest('Stranger')") is True
    assert list(wow.eval("Requested").values()) == ["Stranger-MockRealm", "Stranger-MockRealm"]
    wow.execute(
        "Heard = {} ; Bastians:GetModule('Core'):On('BASTIANS_RP_NAME', function(_, _, n) Heard[#Heard + 1] = n end)"
    )
    wow.execute("for _, fn in ipairs(msp.callback.received) do fn('Stranger-MockRealm') end")
    assert list(wow.eval("Heard").values()) == ["Stranger-MockRealm"]
    assert wow.errors == []


def test_gestures_rp_placeholder_fills_from_the_target(wow: WowRuntime):
    wow.start(CORE, DATA, GESTURES)
    wow.run_frames(3)
    wow.execute(MSP + TARGET)
    ring = "Bastians:GetModule('Gestures').Ring"
    model = "Bastians:GetModule('Gestures').Model"
    assert (
        wow.eval(f"{model}.Fill('Well met, %rp.', {ring}.Context())") == "Well met, Tobb Ironhand."
    )
    assert wow.errors == []


def test_chat_shows_the_roleplay_name_in_the_link_or_at_the_emote_start(wow: WowRuntime):
    wow.start(CORE, CHAT)
    m = "Bastians:GetModule('Chat').Model"
    link = "|Hplayer:Tobb-MockRealm:12:SAY|h[Tobb]|h says: Hello."
    out = wow.eval(f"{m}.WithRoleplayName('{link}', 'Tobb-MockRealm', 'Tobb Ironhand')")
    assert out == "|Hplayer:Tobb-MockRealm:12:SAY|h[Tobb Ironhand]|h says: Hello."
    assert wow.eval(
        f"{m}.WithRoleplayName('Tobb waves at you.', 'Tobb-MockRealm', 'Tobb Ironhand')"
    ) == ("Tobb Ironhand waves at you.")
    assert (
        wow.eval(f"{m}.WithRoleplayName('Grimtok waves.', 'Tobb-MockRealm', 'X')")
        == "Grimtok waves."
    )
    assert (
        wow.eval(f"{m}.WithRoleplayName('Tobb waves.', 'Tobb', '100% Tobb')") == "100% Tobb waves."
    )
    assert wow.errors == []


def test_the_orbiter_line_shows_the_targets_roleplay_name(wow: WowRuntime):
    wow.start(CORE, DATA, VOICE)
    wow.run_frames(3)
    orbit = "Bastians:GetModule('Voice').Orbit"
    assert wow.eval(f"{orbit}.RoleplayLine()") is None  # no target
    wow.execute(MSP + TARGET)
    assert wow.eval(f"{orbit}.RoleplayLine()") == "Tobb Ironhand, Wandering cook"
    wow.execute("Mock.unitNames.target = 'Stranger'")
    assert wow.eval(f"{orbit}.RoleplayLine()") is None
    assert list(wow.eval("Requested").values()) == ["Stranger-MockRealm"]  # asked for once
    assert wow.errors == []
