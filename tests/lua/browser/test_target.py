"""Target follow (C6, ADR 0014): with the toggle on (default) and the window shown, an NPC or object
the player targets becomes the subject; never in combat lockdown; a player target is ignored. The
GUID is parsed by Compat.TargetEntity (Creature and Vehicle: npc, GameObject: object)."""

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def target(wow: WowRuntime, guid: str | None) -> None:
    if guid is None:
        wow.execute("Mock.guids = Mock.guids or {}; Mock.guids.target = nil")
    else:
        wow.execute(f'Mock.guids = Mock.guids or {{}}; Mock.guids.target = "{guid}"')
    wow.fire("PLAYER_TARGET_CHANGED")


def test_the_guid_shapes(core: WowRuntime):
    parse = "Bastians.Compat.EntityFromGUID(%r)"
    assert core.eval(parse % "Creature-0-4469-0-12-54-0000ABCDEF") == "npc:54"
    assert core.eval(parse % "Vehicle-0-4469-0-12-448-0000ABCDEF") == "npc:448"
    assert core.eval(parse % "GameObject-0-4469-0-12-1734-0000ABCDEF") == "object:1734"
    assert core.eval(parse % "Player-1-00000001") is None
    assert core.eval(parse % "Pet-0-4469-0-12-54-0000ABCDEF") is None
    assert core.eval(parse % "nonsense") is None and core.eval(parse % "") is None
    assert core.eval("Bastians.Compat.TargetEntity()") is None  # no target
    core.execute('Mock.guids = { target = "Creature-0-4469-0-12-54-0000ABCDEF" }')
    assert core.eval("Bastians.Compat.TargetEntity()") == "npc:54"
    assert core.eval("Bastians.Compat.CONTRACT.TargetEntity ~= nil") is True


def test_a_targeted_npc_or_object_becomes_the_subject(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MOD}.db.profile.followTarget") is True  # on by default
    target(wow, "Creature-0-4469-0-12-54-0000ABCDEF")
    assert (
        wow.eval("BastiansBrowserFrame == nil or not BastiansBrowserFrame:IsShown()") is True
    )  # window hidden
    wow.execute(f"{BR}.Open('zone:1429')")
    target(wow, "Creature-0-4469-0-12-54-0000ABCDEF")
    assert wow.eval(f"{BR}.Current().ref") == "npc:54"
    target(wow, "GameObject-0-4469-0-12-1734-0000ABCDEF")
    assert wow.eval(f"{BR}.Current().ref") == "object:1734"
    # the same target again: nothing pushed twice
    history, _ = wow.eval(f"{BR}.History()")
    n = len(list(history.values()))
    target(wow, "GameObject-0-4469-0-12-1734-0000ABCDEF")
    assert wow.eval(f"#(({BR}.History()))") == n
    # a player target and no target: the subject stays
    target(wow, "Player-1-00000002")
    assert wow.eval(f"{BR}.Current().ref") == "object:1734"
    target(wow, None)
    assert wow.eval(f"{BR}.Current().ref") == "object:1734"
    assert wow.errors == []


def test_combat_and_the_toggle_keep_the_window_quiet(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('zone:1429')")
    wow.set_combat(True)
    target(wow, "Creature-0-4469-0-12-54-0000ABCDEF")
    assert wow.eval(f"{BR}.Current().ref") == "zone:1429"  # in combat: ignored
    wow.set_combat(False)
    # the toolbar toggle mirrors the setting
    assert wow.eval(f"{MOD}.toolbar.target:IsShown()") is True
    wow.execute(f"{MOD}.toolbar.target:Click()")
    assert wow.eval(f"{MOD}.db.profile.followTarget") is False
    target(wow, "Creature-0-4469-0-12-54-0000ABCDEF")
    assert wow.eval(f"{BR}.Current().ref") == "zone:1429"  # off: ignored
    wow.execute(f"{MOD}.toolbar.target:Click()")  # on again: the standing target is taken up
    assert wow.eval(f"{MOD}.db.profile.followTarget") is True
    assert wow.eval(f"{BR}.Current().ref") == "npc:54"
    assert wow.errors == []
