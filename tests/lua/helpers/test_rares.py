"""The rare finder (helpers.md "The rare finder", "I stumbled upon a rare
gnoll ... I did not get an alarm like a rare finder - can we have that? marking them on all maps
and as alarm with arrow where it is?"): a rare's nameplate, target, mouse or words sound the raid
warning and show a banner with Arrow and Map, once in ten minutes; the rare stays on the maps for
five minutes; the known rare spawns are a layer that starts off."""

from harness import WowRuntime
from test_helpers import DATA, HELPERS, H, P, boot, notice

R = f"{H}.Rares"
GUID = "Creature-0-1-0-1-%d-0000000001"
LEPRITHUS, HOGGER = 1260, 448  # a rare of the fixture world, and an elite who is no rare
VIEW = "{ continent = %s, x1 = -1e9, y1 = -1e9, x2 = 1e9, y2 = 1e9, level = 6 }"


def plate(wow: WowRuntime, unit: str, npc: int) -> None:
    wow.execute(
        f"Mock.guids = Mock.guids or {{}}; Mock.guids['{unit}'] = '{GUID % npc}';"
        f" Mock.Fire('NAME_PLATE_UNIT_ADDED', '{unit}')"
    )


def banner(wow: WowRuntime) -> tuple:
    shown = wow.eval("BastiansRareBanner and BastiansRareBanner:IsShown()")
    if not shown:
        return (False, None, [])
    buttons = [
        b.label.GetText(b.label)
        for b in wow.eval("BastiansRareBanner.buttons").values()
        if b.IsShown(b)
    ]
    return (True, wow.eval("BastiansRareBanner.title:GetText()"), buttons)


def live(wow: WowRuntime) -> list:
    continent = wow.eval("(Bastians.Coords.Player())") or 0
    return list(wow.eval(f"Bastians:QueryLayer('helpers.rares', {VIEW % continent})").values())


def test_a_rares_nameplate_sounds_the_alarm_once_with_the_banner_and_its_place(wow: WowRuntime):
    boot(wow, "Bastians_Core", DATA, HELPERS)
    plate(wow, "nameplate1", LEPRITHUS)
    assert wow.eval("Mock.kits[#Mock.kits]") == 8959  # the raid warning
    shown, title, buttons = banner(wow)
    assert shown and title == "Rare nearby: Leprithus"
    assert buttons == []  # neither Route nor Map is there: no button
    assert notice(wow) == "Rare: Leprithus"  # and the line in the strip and the addon chat
    pins = live(wow)
    assert len(pins) == 1 and pins[0].ref == f"npc:{LEPRITHUS}" and pins[0].label == "Leprithus"
    # once in ten minutes, and the banner goes after twelve seconds
    kits = wow.eval("#Mock.kits")
    wow.execute(f"{H}.lastNotice = nil")
    plate(wow, "nameplate2", LEPRITHUS)
    assert wow.eval("#Mock.kits") == kits and notice(wow) is None
    wow.advance(13)
    assert banner(wow)[0] is False
    # five minutes on the maps, then gone; after ten minutes it sounds again
    wow.advance(300)
    assert live(wow) == []
    wow.advance(300)
    plate(wow, "nameplate3", LEPRITHUS)
    assert wow.eval("#Mock.kits") == kits + 1
    assert wow.errors == []


def test_an_elite_is_no_rare_unless_the_client_says_so(wow: WowRuntime):
    boot(wow, "Bastians_Core", DATA, HELPERS)
    plate(wow, "nameplate1", HOGGER)
    assert banner(wow)[0] is False
    # a rare our data does not know: the client's own word counts
    wow.execute("Mock.classification = { nameplate2 = 'rareelite' }")
    plate(wow, "nameplate2", HOGGER)
    assert banner(wow)[1] == "Rare nearby: Hogger"
    assert wow.errors == []


def test_a_rare_that_speaks_is_found_by_its_guid(wow: WowRuntime):
    """Gruff Swiftbite in the owner's chat: "Grrrr... fresh meat!" (CHAT_MSG_MONSTER_SAY)."""
    boot(wow, "Bastians_Core", DATA, HELPERS)
    args = ", ".join(
        ["'Grrrr... fresh meat!'", "'Leprithus'"] + ["nil"] * 9 + [f"'{GUID % LEPRITHUS}'"]
    )
    wow.execute(f"Mock.Fire('CHAT_MSG_MONSTER_SAY', {args})")
    assert banner(wow)[1] == "Rare nearby: Leprithus"
    assert wow.errors == []


def test_the_banner_offers_the_arrow_and_the_map(wow: WowRuntime):
    boot(wow, "Bastians_Core", DATA, "Bastians_Map", "Bastians_Route", HELPERS)
    wow.execute(
        "RAN = {}; local run = Bastians.RunAction;"
        " Bastians.RunAction = function(self, id, ref, ctx) RAN[#RAN + 1] = id .. ' ' .. tostring(ref)"
        " return run(self, id, ref, ctx) end"
    )
    plate(wow, "nameplate1", LEPRITHUS)
    assert banner(wow)[2] == ["Arrow", "Map"]
    wow.execute("BastiansRareBanner.buttons[1]:Click()")
    assert list(wow.eval("RAN").values())[-1] == f"route.to npc:{LEPRITHUS}"
    assert banner(wow)[0] is False  # a button closes it
    assert wow.errors == []


def test_the_settings_switch_the_finder_and_its_sound(wow: WowRuntime):
    boot(wow, "Bastians_Core", DATA, HELPERS)
    wow.execute(f"{P}.rareSound = false")
    plate(wow, "nameplate1", LEPRITHUS)
    assert wow.eval("#Mock.kits") == 0 and banner(wow)[0] is True  # no sound, still the banner
    wow.execute(f"BastiansRareBanner:Hide(); {P}.warnRares = false")
    wow.execute(f"Mock.guids.target = '{GUID % 1261}'; Mock.Fire('PLAYER_TARGET_CHANGED')")
    assert banner(wow)[0] is False
    assert wow.errors == []


def test_the_known_rare_spawns_are_a_layer_that_starts_off(wow: WowRuntime):
    boot(wow, "Bastians_Core", DATA, HELPERS)
    layer = wow.eval("Bastians:GetMapLayer('helpers.rarespawns')")
    assert layer.defaultOn is False
    assert wow.eval("Bastians:GetMapLayer('helpers.rares').defaultOn") is True
    continent = wow.eval("(Bastians.Coords.Player())") or 0
    query = f"Bastians:QueryLayer('helpers.rarespawns', {VIEW % continent})"
    assert list(wow.eval(query).values()) == []  # the first ask starts reading, in a job
    wow.run_frames(30)
    wow.advance(1)
    pins = list(wow.eval(query).values())
    assert pins and all(p.ref.startswith("npc:") and "(" in p.label for p in pins)
    assert f"npc:{LEPRITHUS}" in {p.ref for p in pins}
    assert wow.errors == []
