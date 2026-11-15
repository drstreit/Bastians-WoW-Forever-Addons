"""The developer probe's `/bprobe tracking` ("track beasts and track
humanoids are not working on our minimap"). On the mock it must record every tracking type as the
client answers it, Compat.CreatureTrackingOn, the Map's own sweep, and its own sweep of the game
minimap: each name heard with its points and what the Data knows of it. A name the Data does not
know may be another player's and is kept only as its shape (CLAUDE.md §8); the soft cursor is
given back every frame. What the real client answers is for the client.

`/bprobe ground`: the game's minimap
without its ground, lifted over our tiles in one of our styles, the view radius per zoom, and all
put back by a second call, also after a /reload."""

from harness import WowRuntime
from test_mini import boot
from test_tracked import blips, hunter, our_style

RESULT = "BastiansProbeDB.results.tracking"
GROUND = """
Mock.ground = true
C_Minimap.SetDrawGroundTextures = function(on) Mock.ground = on end
C_Minimap.GetDrawGroundTextures = function() return Mock.ground end
"""


def probe_alone(wow: WowRuntime) -> None:
    """The probe's ground measured alone: the Map's own dots layer (ADR 0078, test_mini_dots.py)
    switches the same ground and is kept off by its setting."""
    wow.execute("Bastians:GetModule('Map').db.profile.miniTracked = false")


def mentions(wow: WowRuntime, text: str) -> bool:
    """Whether any key or string anywhere in the record holds the text."""
    return wow.eval(
        f"""(function()
          local function has(t)
            for k, v in pairs(t) do
              if type(k) == "string" and string.find(k, {text!r}, 1, true) then return true end
              if type(v) == "string" and string.find(v, {text!r}, 1, true) then return true end
              if type(v) == "table" and has(v) then return true end
            end
            return false
          end
          return has({RESULT})
        end)()"""
    )


def run(wow: WowRuntime) -> object:
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe tracking")
    for _ in range(200):
        wow.advance(1 / 60)  # the probe's frames are C_Timer.After(0) steps
        if wow.eval(f"{RESULT} and {RESULT}.done ~= nil"):
            break
    return wow.eval(RESULT)


def test_the_probe_records_the_tracking_and_what_the_minimap_answers(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow)
    wow.execute(
        "function UnitName(u) if u == 'pet' then return 'Old Hound' end return 'Bastienne' end"
    )
    blips(
        wow,
        (20, 0, "Young Wolf"),
        (40, 40, "Elder Stormbrow"),  # a quest giver: an NPC of the data with a service
        (0, 0, "Bastienne"),  # the player
        (-45, -35, "Old Hound"),  # the pet
        (-40, 30, "Somebody Else"),  # another player: never saved by name
    )
    out = run(wow)
    assert out is not None, list(wow.eval("Mock.chat").values())[-3:]
    assert out.sweep.done is not None and out.sweep.err is None
    # the tracking types exactly as the client answered them
    assert out.numTypes == 1
    info = out.types[1].info
    assert info.ok and info.ret[1].type == "spell" and info.ret[1].spellID == 1494
    assert out.creatureTrackingOn.ok and out.creatureTrackingOn.ret[1] is True
    # the Map's own sweep
    assert out.map.style.ret[1] == "pencil"
    assert out.map.active.ret[1] is True
    # the names heard, with what the Data knows
    names = out.sweep.names
    assert set(names.keys()) == {"Young Wolf", "Elder Stormbrow"}
    wolf = names["Young Wolf"]
    assert wolf.points > 0 and wolf.data.npc[1].id == 91 and wolf.text == "Young Wolf"
    assert names["Elder Stormbrow"].data.npc[1].flags[1] == "questgiver"
    assert out.sweep.player > 0 and out.sweep.pet > 0
    assert out.sweep.answered > 0 and out.sweep.secret == 0
    # another player's name is nowhere in the record, only its shape
    shapes = dict(out.sweep.shapes)
    assert list(shapes) == ["Aaaaaaaa Aaaa"] and shapes["Aaaaaaaa Aaaa"] > 0
    assert not mentions(wow, "Somebody")
    assert wow.eval("Minimap.softCursor") is False
    # the ways of writing a point: the scaled one is the sweep above; each other one is swept too
    conventions = list(out.conventions.values())
    assert conventions[:2] == ["scaled", "ui"]
    assert all(out.sweeps[c].done is not None for c in conventions)
    assert out.sweeps.scaled.f == wow.eval("Minimap:GetEffectiveScale()")
    # the minimap's state and the player's place
    assert out.state.position.ok and out.state.position.ret[1] is not None
    assert wow.eval("#BastiansProbeDB.results.trackingRuns") == 1  # every run is kept
    assert any("sweep scaled" in line for line in wow.chat)
    assert wow.errors == []


def test_hover_reads_what_the_tooltip_says_under_the_real_mouse(wow: WowRuntime):
    boot(wow)  # the game's style: its minimap shows, the Map's sweep rests
    hunter(wow)
    blips(wow, (20, 0, "Young Wolf"), (-40, 30, "Somebody Else"))
    wow.execute("function GetMouseFoci() return { Minimap } end")
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe tracking hover")
    wow.execute("Mock.minimapProbe = { u = 20, v = 0 }")  # the real mouse over the wolf
    wow.run_frames(30)
    wow.execute("Mock.minimapProbe = { u = -40, v = 30 }")  # and over another player
    wow.run_frames(30)
    wow.advance(16)
    wow.run_frames(2)
    out = wow.eval("BastiansProbeDB.results.trackingHover")
    assert out.done is not None and out.err is None and out.fociErr is None
    assert out.names["Young Wolf"].points == 30 and out.answered == 60
    assert dict(out.foci) == {"Minimap": out.frames}
    assert list(dict(out.shapes)) == ["Aaaaaaaa Aaaa"]
    assert not wow.eval(
        """(function()
          local function has(t)
            for k, v in pairs(t) do
              if type(k) == "string" and string.find(k, "Somebody", 1, true) then return true end
              if type(v) == "string" and string.find(v, "Somebody", 1, true) then return true end
              if type(v) == "table" and has(v) then return true end
            end
            return false
          end
          return has(BastiansProbeDB.results.trackingHover)
        end)()"""
    )
    assert any("tracking hover: the mouse was over" in line for line in wow.chat)
    assert wow.errors == []


def test_a_line_that_also_names_a_player_is_kept_as_its_shape(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow)
    wow.execute(
        "Mock.minimapBlips = { { u = 20, v = 0, name = 'x', text = 'Young Wolf\\nSomebody' } }"
    )
    out = run(wow)
    wolf = out.sweep.names["Young Wolf"]
    assert wolf.text == "Aaaaa Aaaa\nAaaaaaaa"
    assert wolf.tooltip.lines[1].leftText == wolf.text
    assert not mentions(wow, "Somebody")
    assert wow.errors == []


def test_the_probe_waits_for_the_end_of_combat(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    wow.execute("function InCombatLockdown() return true end")
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe tracking")
    wow.run_frames(3)
    assert wow.eval(RESULT) is None
    assert "combat" in list(wow.eval("Mock.chat").values())[-1]
    assert wow.errors == []


def test_ground_off_lifts_the_game_minimap_over_our_tiles_and_puts_it_back(wow: WowRuntime):
    boot(wow)
    probe_alone(wow)
    our_style(wow)
    wow.execute(GROUND)
    strata, level, zoom = wow.eval(
        "(function() return Minimap:GetFrameStrata(), Minimap:GetFrameLevel(), Minimap:GetZoom() end)()"
    )
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is False
    assert wow.eval("Minimap:GetFrameStrata()") == "HIGH"
    run = wow.eval("BastiansProbeDB.results.ground.runs[1]")
    assert run.action == "off" and run.before.ret[1] is True and run.after.ret[1] is False
    assert run.style == "pencil" and run.raised is True
    assert len(run.zooms) == run.levels and all(z.set for z in run.zooms.values())
    assert wow.eval("Minimap:GetZoom()") == zoom  # the zoom it had
    assert any("view radius in yards per zoom" in line for line in wow.chat)
    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is True
    assert wow.eval("Minimap:GetFrameStrata()") == strata
    assert wow.eval("Minimap:GetFrameLevel()") == level
    assert wow.eval("BastiansProbeDB.results.ground.runs[2].action") == "back on"
    assert wow.errors == []


def test_ground_left_off_by_a_reload_is_put_back(wow: WowRuntime):
    boot(wow)
    wow.execute(GROUND + "Mock.ground = false")  # off before the /reload; the game's style
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is True
    assert wow.eval("BastiansProbeDB.results.ground.runs[1].action") == "back on"
    # and in the game's style nothing is lifted when it goes off
    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is False
    assert wow.eval("BastiansProbeDB.results.ground.runs[2].raised") is None
    assert wow.errors == []


def test_ground_off_brings_our_view_to_the_games_centre_and_scale_and_keeps_it(wow: WowRuntime):
    """with the view dragged away a node stood 88 px beside its place.
    The game's dots lie around the minimap's centre at its own scale, so our view follows the
    player at that scale while the ground is off, also after a wheel or a drag, and gets its own
    zoom back."""
    boot(wow)
    probe_alone(wow)
    our_style(wow)
    wow.execute(GROUND)
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    mini = "Bastians:GetModule('Map').Mini"
    wow.execute(f"{mini}.Camera().level = 3.5; {mini}.Camera():Pan(40, 25); {mini}.Zoom(1)")
    was = wow.eval(f"{mini}.Camera().level")
    wow.slash("/bprobe ground")
    fits = f"""(function()
      local cam, view = {mini}.Camera(), {mini}.View()
      local half = Minimap:GetWidth() / 2 * Minimap:GetEffectiveScale() / view:GetEffectiveScale()
      return math.abs(cam:Scale() - half / C_Minimap.GetViewRadius()) < 1e-6
    end)()"""
    assert wow.eval(fits)
    assert wow.eval(f"{mini}.Following()") is True
    run = "BastiansProbeDB.results.ground.runs[1]"
    assert wow.eval(f"{run}.fit.was") == was and wow.eval(f"{run}.fit.changed") is True
    assert wow.eval(f"{run}.mouse.enabled") is not None
    assert any("follows you at the game's scale" in line for line in wow.chat)

    # a wheel on our map parts the two; half a second later they agree again
    wow.execute(f"{mini}.Zoom(-2, true)")
    assert not wow.eval(fits)
    wow.advance(0.6)
    assert wow.eval(fits)
    assert wow.eval(f"{run}.refits") == 1

    wow.slash("/bprobe ground")
    assert wow.eval(f"{mini}.Camera().level") == was  # the zoom it had
    wow.execute(f"{mini}.Zoom(-2, true)")
    level = wow.eval(f"{mini}.Camera().level")
    wow.advance(2)
    assert wow.eval(f"{mini}.Camera().level") == level  # nothing holds the view any more
    assert wow.errors == []


def test_a_login_records_whether_the_ground_stayed_off(wow: WowRuntime):
    boot(wow)
    wow.execute(GROUND + "Mock.ground = false")
    wow.execute("BastiansProbeDB = { results = { ground = { runs = {} } } }")
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.fire("PLAYER_LOGIN")
    assert wow.eval("#BastiansProbeDB.results.ground.logins") == 1
    assert wow.eval("BastiansProbeDB.results.ground.logins[1].ground.ret[1]") is False
    assert wow.errors == []


def test_ground_level_sets_the_game_minimap_between_our_tiles_and_our_pins(wow: WowRuntime):
    """ADR 0078, G1 and G2: the game's minimap above the view's tiles (10 levels over the view)
    and under the pins' overlay (15), in its own strata; the clicks it gets there are counted
    by button, and the second call gives the level back."""
    boot(wow)
    probe_alone(wow)
    our_style(wow)
    wow.execute(GROUND)
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    mini = "Bastians:GetModule('Map').Mini"
    strata, level = wow.eval(
        "(function() return Minimap:GetFrameStrata(), Minimap:GetFrameLevel() end)()"
    )
    view = wow.eval(f"{mini}.View():GetFrameLevel()")
    wow.slash("/bprobe ground level")
    run = "BastiansProbeDB.results.ground.runs[1]"
    assert wow.eval("Mock.ground") is False
    assert wow.eval("Minimap:GetFrameStrata()") == strata  # not lifted by strata
    now = wow.eval("Minimap:GetFrameLevel()")
    assert view + 10 < now < view + 15
    assert wow.eval(f"{run}.variant") == "level" and wow.eval(f"{run}.raised") is True
    assert wow.eval(f"{mini}.Following()") is True  # the fit holds here too
    wow.execute(
        "local up = Minimap:GetScript('OnMouseUp'); "
        "up(Minimap, 'LeftButton'); up(Minimap, 'LeftButton'); up(Minimap, 'RightButton')"
    )
    assert wow.eval(f"{run}.clicks.LeftButton") == 2
    assert wow.eval(f"{run}.clicks.RightButton") == 1

    wow.slash("/bprobe ground")
    assert wow.eval("Mock.ground") is True
    assert wow.eval("Minimap:GetFrameLevel()") == level
    wow.execute("Minimap:GetScript('OnMouseUp')(Minimap, 'LeftButton')")
    assert wow.eval(f"{run}.clicks.LeftButton") == 2  # counted only while the ground is off
