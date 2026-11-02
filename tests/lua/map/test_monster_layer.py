"""The map's monster areas ("I dont have a mob filter in the map - can we
do that as regions for all mobs? clickable to open the browser for that mob"): every monster of
the zones in view as soft regions where it stands, tinted by its level against the character's,
off by default, a pin per region that opens the monster's page."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
WORLD = "{ continent = 0, x1 = -20000, y1 = -20000, x2 = 20000, y2 = 20000, level = %d }"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(10)
    return wow


def test_places_that_lie_together_make_one_region(core: WowRuntime):
    core.start("Bastians_Map")
    regions = core.eval(
        """Bastians:GetModule('Map').Layers.MobRegions({
          { wx = 0, wy = 0 }, { wx = 50, wy = 0 }, { wx = 100, wy = 0, r = 10 },
          { wx = 1000, wy = 1000 },
        })"""
    )
    got = [(r.wx, r.wy, r.r, r.n) for r in regions.values()]
    assert got[0][:2] == (50, 0) and got[0][3] == 3  # linked through the middle one
    assert got[0][2] == 60  # the far place, 50 yards out, and its 10 yards of roaming
    assert got[1] == (1000, 1000, 20, 1)  # a lone place: the smallest region
    assert core.errors == []


def test_the_monsters_layer_draws_regions_of_the_monsters_only(wow: WowRuntime):
    boot(wow)
    pins = list(wow.eval(f"Bastians:QueryLayer('map.monsters', {WORLD % 5})").values())
    refs = sorted({p.ref for p in pins})
    assert refs == ["npc:327", "npc:448"]  # Goldtooth and Hogger; no vendor, no innkeeper
    hogger = [p for p in pins if p.ref == "npc:448"]
    assert len(hogger) == 1 and hogger[0].radius >= 20  # its two places lie together
    assert hogger[0].label == "Hogger  11"
    assert hogger[0].icon == wow.eval("Bastians.UI.IconTexture('mob')")
    level = wow.eval("UnitLevel('player')")
    token = wow.eval(f"Bastians.UI.Style.LevelToken(11, {level})")
    assert list(hogger[0].color.values()) == list(wow.eval(f"Bastians.UI.Style.C.{token}").values())
    assert wow.eval(f"{MOD}.Pins.IsLayerOn(Bastians:GetMapLayer('map.monsters'))") is False
    minimap = WORLD.replace("level = %d", "level = 5, minimap = true") % ()
    assert len(wow.eval(f"Bastians:QueryLayer('map.monsters', {minimap})")) == 0
    assert wow.errors == []


def test_the_level_colour_follows_the_games_scale(core: WowRuntime):
    tok = "Bastians.UI.Style.LevelToken"
    assert core.eval(f"{tok}(15, 10)") == "diffRed"
    assert core.eval(f"{tok}(13, 10)") == "diffOrange"
    assert core.eval(f"{tok}(9, 10)") == "diffYellow"
    assert core.eval(f"{tok}(5, 10)") == "diffGreen"  # 6 levels below still give experience
    assert core.eval(f"{tok}(3, 10)") == "diffGrey"
    assert core.eval(f"{tok}(nil, 10)") is None
    assert core.errors == []
