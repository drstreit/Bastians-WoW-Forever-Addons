"""Home and every way back (route.md, R26.7): the teleport table from the generator's fixture world
(a mage's Stormwind, a shaman's Astral Recall), what Compat says the character has ready, the
teleports handed to the graph, the landing learned when one is cast, and Home to the inn."""

from harness import WowRuntime

CORE, DATA, MAP, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Route"
MOD = "Bastians:GetModule('Route')"
R = f"{MOD}.Route"
STATE = "Bastians.Compat.GetTeleportState"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, MAP, ROUTE)
    wow.run_frames(5)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    return wow


def test_compat_tells_owned_ready_and_the_reagent(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{STATE}('spell', 3561, 17031)") == (False, False, None)  # not known
    wow.execute("Mock.spells[3561] = true")
    assert wow.eval(f"{STATE}('spell', 3561, 17031)") == (True, False, None)  # no rune
    wow.execute("Mock.bags[17031] = 5")
    owned, ready, left = wow.eval(f"{STATE}('spell', 3561, 17031)")
    assert (owned, ready, left) == (True, True, 0)
    wow.execute("Mock.spellCooldowns[3561] = { start = GetTime(), duration = 600 }")
    owned, ready, left = wow.eval(f"{STATE}('spell', 3561, 17031)")
    assert owned is True and ready is False and 590 < left <= 600
    # an item counts in the bags or worn; a toy when collected
    assert wow.eval(f"{STATE}('item', 65360)") == (False, False, None)
    wow.execute("Mock.worn[65360] = true")
    assert wow.eval(f"{STATE}('item', 65360)") == (True, True, 0)
    wow.execute("Mock.toys[64488] = true")
    assert wow.eval(f"{STATE}('toy', 64488)") == (True, True, 0)
    # a client without the spell book API cannot tell: unknown, never owned
    wow.execute("C_SpellBook = nil; IsSpellKnown = nil")
    assert wow.eval(f"{STATE}('spell', 3561, 17031)") is None
    assert wow.errors == []


def test_the_ready_teleports_of_the_character(wow: WowRuntime):
    boot(wow)  # the mock is an Alliance mage
    assert len(wow.eval(f"{R}.Teleports()")) == 0  # nothing known
    wow.execute("Mock.spells[3561] = true; Mock.bags[17031] = 1")
    tps = list(wow.eval(f"{R}.Teleports()").values())
    assert [(t.id, t.name, t.map, t.wx, t.wy, t.wz, t.seconds) for t in tps] == [
        ("mage-stormwind", "Stormwind", 0, 100, -50, 11, 10)
    ]
    # a learned landing wins over the table's place
    wow.execute(
        f"{MOD}.db.global.landings['mage-stormwind'] = {{ continent = 0, wx = 120, wy = -60 }}"
    )
    t = wow.eval(f"{R}.Teleports()")[1]
    assert (t.wx, t.wy, t.wz) == (120, -60, None)
    # a shaman's Astral Recall lands at the learned inn, under the inn's name
    wow.execute("Mock.classID = 7; Mock.spells[556] = true")
    assert len(wow.eval(f"{R}.Teleports()")) == 0  # the inn is not known yet
    wow.execute(
        f"{MOD}.db.char.hearth = {{ name = 'Goldshire', continent = 0, wx = -9460, wy = 60 }}"
    )
    tps = list(wow.eval(f"{R}.Teleports()").values())
    assert [(t.id, t.name, t.wx) for t in tps] == [("shaman-astral-recall", "Goldshire", -9460)]
    assert wow.errors == []


def test_a_cast_teleport_learns_its_landing(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{R}.TeleportCast(12345)") is None  # not a teleport of the table
    assert wow.eval(f"{R}.TeleportCast(3561)") == "mage-stormwind"
    wow.execute("Mock.playerMapPos = { x = 0.10, y = 0.10 }")  # far away after the loading screen
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(1.1)
    landing = wow.eval(f"{MOD}.db.global.landings['mage-stormwind']")
    here = wow.eval("{ Bastians.Coords.Player() }")
    assert (landing.continent, landing.wx, landing.wy) == (here[1], here[2], here[3])
    # an item's teleport by the spell its use casts; without a loading screen after five seconds
    wow.execute("Mock.itemSpells[18984] = 23442")
    assert wow.eval(f"{R}.TeleportCast(23442)") == "ripper-everlook"
    wow.execute("Mock.playerMapPos = { x = 0.90, y = 0.90 }")
    wow.advance(5.1)
    assert wow.eval(f"{MOD}.db.global.landings['ripper-everlook']") is not None
    assert wow.errors == []


def test_home_plans_to_the_inn(wow: WowRuntime):
    boot(wow)
    wow.slash("/broute home")
    assert "inn unknown" in wow.chat[-1]
    wow.execute(
        f"{MOD}.db.char.hearth = {{ name = 'Goldshire', continent = 0, wx = -9460, wy = 60 }}"
    )
    wow.slash("/broute home")
    route = wow.eval(f"{R}.Active()")
    assert route is not None and route.goal.name == "Goldshire"
    assert (route.goal.wx, route.goal.wy) == (-9460, 60)
    assert wow.errors == []


def test_a_teleport_step_reads_teleport_to(wow: WowRuntime):
    boot(wow)
    text = wow.eval(
        f"{MOD}.Graph.StepText({{ mode = 'teleport', to = {{ name = 'Stormwind' }}, approx = true }})"
    )
    assert text == "Teleport to Stormwind"
    wow.slash("/broute teleports")
    assert any("Stormwind: not yours" in line for line in wow.chat)
    assert wow.errors == []
