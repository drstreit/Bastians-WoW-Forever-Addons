"""The game's tracking dots on Bastian's minimap styles:
our tiles cover the game's minimap there, so its dots (Find Herbs, Find Minerals) are read back by
asking the minimap's tooltip over a grid, grouped by name, placed in world yards by the game
minimap's own size and zoom, and shown as live pins of the overlay. Only herbs and ore get a pin
. Nothing runs in the game's style, nothing without the client's calls or the
data, nothing while our frame is hidden. The dots are no map
layer: no layer switch,
not the layers-on-the-minimap setting and not the pin limit takes them away."""

import math

from harness import WowRuntime
from test_mini import MINI, MOD, boot, pencil, setting

TR = f"{MOD}.Tracked"
MM = f"{MOD}.Minimap"


NODES = {"Peacebloom": "herb", "Copper Vein": "mine", "Battleboar": "skin"}


def our_style(wow: WowRuntime) -> None:
    pencil(wow)
    nodes(wow)
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('pencil')")
    wow.run_frames(2)


def blips(wow: WowRuntime, *dots: tuple[float, float, str]) -> None:
    rows = ", ".join(f"{{ u = {u}, v = {v}, name = '{name}' }}" for u, v, name in dots)
    wow.execute(f"Mock.minimapBlips = {{ {rows} }}")


def sweep(wow: WowRuntime, frames: int = 16, wait: float = 1.5) -> None:
    """One sweep: the wait, the frames of probing, then the overlay's coalesced query."""
    wow.advance(wait)
    wow.run_frames(frames)
    wow.advance(0.3)
    wow.run_frames(2)


def tracked_pins(wow: WowRuntime) -> dict[str, object]:
    out = {}
    for pin in wow.eval(f"{MM}.Pins()").values():
        if str(pin.ref).startswith("tracked:"):
            out[pin.label] = pin
    return out


def known(wow: WowRuntime) -> list:
    return list(wow.eval(f"{TR}.Known()").values())


def settle(wow: WowRuntime) -> None:
    """The overlay's coalesced query after a stop or a style change."""
    wow.run_frames(3)
    wow.advance(0.3)
    wow.run_frames(2)


def player(wow: WowRuntime) -> tuple[float, float]:
    vals = wow.eval("Bastians.Coords.Player()")  # continent, wx, wy, and the map behind them
    return vals[1], vals[2]


def nodes(wow: WowRuntime) -> None:
    """The fixture world has no node records: these are the data's nodes here."""
    rows = ", ".join(f"{{ name = '{name}', kind = '{kind}' }}" for name, kind in NODES.items())
    wow.execute(
        f"""
        local d, rows = Bastians:GetService("data"), {{ {rows} }}
        local each, get = d.Each, d.Get
        d.Each = function(self, typ)
          if typ ~= "node" then return each(self, typ) end
          local ids = {{}}
          for i = 1, #rows do ids[i] = i end
          return ids
        end
        d.Get = function(self, typ, id)
          if typ ~= "node" then return get(self, typ, id) end
          return rows[id]
        end
        {TR}.Reset()
        """
    )


def until_swept(wow: WowRuntime) -> None:
    """Frame by frame to the end of the next sweep: the fine pass starts on the frame after it."""
    n = wow.eval(f"{TR}.stats.sweeps")
    wow.advance(1.5)
    for _ in range(40):
        wow.run_frames(1)
        if wow.eval(f"{TR}.stats.sweeps") > n:
            return
    raise AssertionError("no sweep ended")


def test_nothing_runs_in_the_games_style_or_without_the_calls(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MINI}.Style()") == "game"
    assert wow.eval(f"{TR}.Running()") is False
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") == 0
    assert tracked_pins(wow) == {}
    # our style, but the client lacks the calls: nothing runs, the settings' note says why (the mock
    # raises on an unknown PascalCase method, so the absence is a non-function value)
    wow.execute("Minimap.UpdateMouseoverAtPoint = false")
    our_style(wow)
    assert wow.eval(f"{TR}.Running()") is False
    assert wow.eval(f"({TR}.Available()) == nil") is True
    assert "minimap" in wow.eval(f"{TR}.Note()")
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") == 0
    assert wow.errors == []


def test_the_dots_become_pins_at_their_place_in_world_yards(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    assert wow.eval(f"{TR}.Available() == true") is True
    assert wow.eval(f"{TR}.Running()") is True
    assert wow.eval(f"{TR}.Note()") is None
    # 20 px right of the centre, 30 px up: east and north of the player at the game minimap's scale
    blips(wow, (20, 0, "Peacebloom"), (0, 30, "Copper Vein"))
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") > 0
    assert wow.eval("Minimap.softCursor") is False  # given back after the sweep
    pins = tracked_pins(wow)
    assert set(pins) == {"Peacebloom", "Copper Vein"}
    px, py = player(wow)
    scale = wow.eval(f"{MM}.Scale()")  # pixels per yard of the game's minimap at its own zoom
    tolerance = wow.eval(f"{TR}.STEP") / scale  # a grid point's reach
    herb, ore = pins["Peacebloom"], pins["Copper Vein"]
    assert math.isclose(herb.wx, px, abs_tol=tolerance) and math.isclose(
        herb.wy, py - 20 / scale, abs_tol=tolerance
    )
    assert math.isclose(ore.wx, px + 30 / scale, abs_tol=tolerance) and math.isclose(
        ore.wy, py, abs_tol=tolerance
    )
    assert herb.card(herb).title == "Peacebloom"
    # in the game's yellow, to tell them from the layers' pins
    assert wow.eval(f"{MM}.Pins()[1].color == Bastians.UI.Style.C.gold") is True
    # the pins are drawn by the overlay on our style
    shown = [f.pin.label for f in wow.eval(f"{MM}.pool").values() if f.IsShown(f) and f.pin]
    assert "Peacebloom" in shown and "Copper Vein" in shown
    stats = wow.eval(f"{TR}.stats")
    assert stats.sweeps >= 1 and stats.dots == 2 and stats.answered > 2
    assert wow.errors == []


def test_the_yards_come_from_the_clients_own_view_radius(wow: WowRuntime):
    # indoors or on a client whose zoom steps differ from the overlay's table: the client's figure
    boot(wow)
    our_style(wow)
    half = wow.eval("Minimap:GetWidth()") / 2
    wow.execute(f"Mock.minimapViewRadius = {half}")  # one pixel a yard
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    px, py = player(wow)
    herb = tracked_pins(wow)["Peacebloom"]
    step = wow.eval(f"{TR}.STEP")
    assert math.isclose(herb.wx, px, abs_tol=step)
    assert math.isclose(herb.wy, py - 20, abs_tol=step)
    assert wow.errors == []


def test_no_layer_switch_no_setting_and_no_pin_limit_takes_the_dots_away(wow: WowRuntime):
    # the layer the dots had been was off, and no dot showed
    boot(wow)
    wow.execute(f"{MOD}.db.profile.layers['map.tracked'] = false")
    assert wow.eval("Bastians:GetMapLayer('map.tracked')") is None  # no layer, no pill to switch
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert set(tracked_pins(wow)) == {"Peacebloom"}
    # the map's layers off the minimap: the dots stay, the layers' pins go
    setting(wow, "minimapPins", "false")
    settle(wow)
    pins = list(wow.eval(f"{MM}.Pins()").values())
    assert [p.label for p in pins] == ["Peacebloom"]
    assert wow.eval(f"{MM}.frame:IsShown()") is True
    blips(wow, (20, 0, "Peacebloom"), (-40, 30, "Copper Vein"))
    sweep(wow)
    assert set(tracked_pins(wow)) == {"Peacebloom", "Copper Vein"}
    # a limit of five and a layer with thirty nearer pins: the dots are not counted against it
    setting(wow, "minimapPins", "true")
    setting(wow, "minimapMax", "5")
    wow.execute(
        f"""
        local m = {MOD}
        Bastians:RegisterMapLayer(m, {{
          id = "test.crowd", label = "Crowd", minLevel = 0,
          query = function(view)
            local out = {{}}
            local _, px, py = Bastians.Coords.Player()
            for i = 1, 30 do
              out[i] = {{ ref = "npc:" .. i, wx = px + i * 0.1, wy = py, label = "n" .. i }}
            end
            return out
          end,
        }})
        """
    )
    settle(wow)
    labels = [p.label for p in wow.eval(f"{MM}.Pins()").values()]
    assert "Peacebloom" in labels and "Copper Vein" in labels
    assert len(labels) == 2 + 5
    # the game's style: the game draws its dots itself, ours go
    wow.execute(f"{MINI}.SetStyle('game')")
    settle(wow)
    assert tracked_pins(wow) == {}
    assert wow.errors == []


def test_the_soft_cursor_is_given_back_every_frame(wow: WowRuntime):
    # held across frames the game would show the tooltip of the last point asked
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    wow.advance(1.5)
    before = wow.eval("Mock.minimapProbes")
    for _ in range(6):
        wow.run_frames(1)
        assert wow.eval("Minimap.softCursor") is False
    asked = wow.eval("Mock.minimapProbes") - before
    assert 0 < asked <= 6 * wow.eval(f"{TR}.PER_FRAME")  # a share per frame, never the whole grid
    assert wow.errors == []


def test_a_tooltip_line_is_cleaned_into_its_names(wow: WowRuntime):
    boot(wow)
    names = wow.eval(
        f"{TR}.Names('|cffffd200Peacebloom|r\\n|TInterface\\\\Icons\\\\x:0|t Copper Vein \\n\\n|A:atlas:12:12|a')"
    )
    assert list(names.values()) == ["Peacebloom", "Copper Vein"]
    our_style(wow)
    # one line names two dots, coloured: two pins with plain names
    wow.execute(
        "Mock.minimapBlips = { { u = 20, v = 0, name = 'x',"
        " text = '|cffffd200Peacebloom|r\\nCopper Vein' } }"
    )
    sweep(wow)
    assert set(tracked_pins(wow)) == {"Peacebloom", "Copper Vein"}
    assert wow.errors == []


def test_a_dot_found_again_keeps_its_pin_and_a_gone_one_leaves_after_a_second_look(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"), (-40, -10, "Peacebloom"))
    sweep(wow)
    pins = known(wow)
    assert len(pins) == 2  # two dots of one name, apart: two pins
    refs = sorted(p.ref for p in pins)
    sweep(wow, wait=3.5)  # nothing changed, the player stands: the slow pace
    assert sorted(p.ref for p in known(wow)) == refs  # found again: the same
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow, wait=3.5)
    assert len(known(wow)) == 2  # unseen once: kept
    sweep(wow)  # and looked for again at the quick pace
    assert len(known(wow)) == 1  # unseen twice: gone
    assert len(tracked_pins(wow)) == 1
    assert wow.errors == []


def test_the_sweeps_slow_down_while_nothing_changes_and_wake_when_the_player_sets_off(
    wow: WowRuntime,
):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)  # the dot is new: the quick pace follows
    sweep(wow)  # nothing new, the player stood: the slow pace follows
    n = wow.eval(f"{TR}.stats.sweeps")
    sweep(wow)  # 1.5 s later: still waiting
    assert wow.eval(f"{TR}.stats.sweeps") == n
    wow.fire("PLAYER_STARTED_MOVING")
    sweep(wow)
    assert wow.eval(f"{TR}.stats.sweeps") == n + 1
    assert wow.errors == []


def test_combat_pauses_the_sweeps_and_a_secret_text_keeps_the_known_dots(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    # in combat the tooltip's texts may be secret: nothing is asked, the dot stays
    wow.set_combat(True)
    probes = wow.eval("Mock.minimapProbes")
    for _ in range(4):
        sweep(wow, wait=3.5)
    assert wow.eval("Mock.minimapProbes") == probes
    assert len(tracked_pins(wow)) == 1
    wow.set_combat(False)
    # a text the addon may not read: the sweep tells nothing about the dots it did not name
    wow.execute("Mock.minimapBlips = { { u = -60, v = 40, name = 'x', secret = true } }")
    for _ in range(4):
        sweep(wow, wait=3.5)
    assert wow.eval("Mock.minimapProbes") > probes
    assert len(tracked_pins(wow)) == 1
    assert wow.errors == []


def test_a_failed_sweep_is_tried_again_and_three_in_a_row_rest_until_the_next_login(
    wow: WowRuntime,
):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    wow.execute("Mock.minimapError = 'forbidden'")
    sweep(wow, wait=3.5)
    assert wow.eval(f"{TR}.stats.errors") == 1
    assert wow.eval(f"{TR}.Running()") is True and wow.eval(f"{TR}.Note()") is None
    assert wow.eval("Minimap.softCursor") is False  # given back after the error too
    assert len(tracked_pins(wow)) == 1  # one failure takes no dot away
    # the game answers again: the count starts over
    wow.execute("Mock.minimapError = nil")
    sweep(wow, wait=31)
    assert wow.eval(f"{TR}.stats.errors") == 1
    wow.execute("Mock.minimapError = 'forbidden'")
    for _ in range(3):
        sweep(wow, wait=31)
    assert wow.eval(f"{TR}.stats.errors") == 4
    assert wow.eval(f"{TR}.Running()") is False
    assert "minimap" in wow.eval(f"{TR}.Note()")
    settle(wow)
    assert tracked_pins(wow) == {}
    assert wow.errors == []


def test_the_games_style_the_setting_and_a_hidden_frame_stop_the_sweep(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (20, 0, "Peacebloom"))
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    wow.execute(f"{MINI}.SetStyle('game')")
    settle(wow)
    assert wow.eval(f"{TR}.Running()") is False
    assert tracked_pins(wow) == {}
    wow.execute(f"{MINI}.SetStyle('pencil')")
    sweep(wow)
    assert len(tracked_pins(wow)) == 1
    setting(wow, "miniTracked", "false")
    settle(wow)
    assert wow.eval(f"{TR}.Running()") is False and tracked_pins(wow) == {}
    setting(wow, "miniTracked", "true")
    sweep(wow)
    assert wow.eval(f"{TR}.Running()") is True
    setting(wow, "miniMap", "false")
    assert wow.eval(f"{TR}.Running()") is False
    assert wow.errors == []


def test_a_nodes_place_is_the_centre_of_all_that_answers_its_name(wow: WowRuntime):
    # the positions are to be exact; a dot between the grid's points
    boot(wow)
    our_style(wow)
    blips(wow, (23.7, -11.3, "Peacebloom"))
    until_swept(wow)
    k = known(wow)[0]
    assert k.fine is None  # the grid only found it
    px, py = player(wow)
    scale = wow.eval(f"{MM}.Scale()")
    wx, wy = px - 11.3 / scale, py - 23.7 / scale
    grid_error = math.hypot(k.wx - wx, k.wy - wy)
    wow.run_frames(40)
    k = known(wow)[0]
    assert k.fine is True and wow.eval(f"{TR}.stats.fine") == 1
    assert math.hypot(k.wx - wx, k.wy - wy) < 0.5 / scale  # within half a pixel of the game's dot
    assert math.hypot(k.wx - wx, k.wy - wy) < grid_error
    assert wow.eval("Minimap.softCursor") is False
    # the overlay draws the fine place
    wow.advance(0.3)
    wow.run_frames(2)
    pin = tracked_pins(wow)["Peacebloom"]
    assert (pin.wx, pin.wy) == (k.wx, k.wy)
    # the place is measured: the next sweeps leave it, and no second pass runs
    before = wow.eval("Mock.minimapProbes")
    sweep(wow, frames=40, wait=3.5)
    first = wow.eval("Mock.minimapProbes") - before
    before = wow.eval("Mock.minimapProbes")
    sweep(wow, frames=40, wait=3.5)
    assert wow.eval("Mock.minimapProbes") - before == first  # the grid alone, sweep after sweep
    again = known(wow)[0]
    assert (again.wx, again.wy) == (k.wx, k.wy)
    assert wow.eval(f"{TR}.stats.fine") == 1
    assert wow.errors == []


def test_a_nodes_place_holds_while_the_player_rides_on_during_its_pass(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    scale = wow.eval(f"{MM}.Scale()")
    px, py = player(wow)
    wx, wy = px - 11.3 / scale, py - 23.7 / scale  # the node, fixed in the world
    blips(wow, (23.7, -11.3, "Peacebloom"))
    until_swept(wow)
    for _ in range(40):
        wow.execute("Mock.playerMapPos.x = Mock.playerMapPos.x + 0.00004")  # a rider's frame
        px, py = player(wow)
        blips(wow, (-(wy - py) * scale, (wx - px) * scale, "Peacebloom"))
        wow.run_frames(1)
    k = known(wow)[0]
    assert k.fine is True
    assert math.hypot(k.wx - wx, k.wy - wy) < 1 / scale
    assert wow.errors == []


def test_two_nodes_of_one_name_each_get_their_own_place(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (23.7, -11.3, "Peacebloom"), (-33.1, 17.9, "Peacebloom"))
    sweep(wow, frames=80)
    px, py = player(wow)
    scale = wow.eval(f"{MM}.Scale()")
    places = sorted((k.wx, k.wy) for k in known(wow))
    wanted = sorted(
        [(px - 11.3 / scale, py - 23.7 / scale), (px + 17.9 / scale, py + 33.1 / scale)]
    )
    assert wow.eval(f"{TR}.stats.fine") == 2
    for got, want in zip(places, wanted, strict=True):
        assert math.hypot(got[0] - want[0], got[1] - want[1]) < 0.5 / scale
    assert wow.errors == []


def test_only_herbs_and_ore_get_a_pin(wow: WowRuntime):
    # the tooltip names all that is on the minimap; a pin lay under the player's
    # arrow and another hid the quest pin
    boot(wow)
    our_style(wow)
    blips(
        wow,
        (20, 0, "Peacebloom"),
        (-30, 25, "Copper Vein"),
        (0, 0, "Bastienne"),  # the player
        (40, 40, "Elder Stormbrow"),  # a quest giver
        (-45, -35, "Battleboar"),  # skinnable: a node of the data, but a creature
    )
    sweep(wow, frames=60)
    pins = tracked_pins(wow)
    assert set(pins) == {"Peacebloom", "Copper Vein"}
    assert pins["Peacebloom"].icon == wow.eval("Bastians.UI.IconTexture('herb')")
    assert pins["Copper Vein"].icon == wow.eval("Bastians.UI.IconTexture('mine')")
    assert wow.eval(f"{TR}.stats.dots") == 2
    assert wow.errors == []


def hunter(wow: WowRuntime, active: bool = True, spell: int = 1494) -> None:
    """A hunter with one tracking spell, and the data's creatures."""
    on = "true" if active else "false"
    wow.execute(
        f"""
        function UnitClass() return "Hunter", "HUNTER", 3 end
        C_Minimap.GetNumTrackingTypes = function() return 1 end
        C_Minimap.GetTrackingInfo = function()
          return {{ name = "Tracking", active = {on}, type = "spell", spellID = {spell} }}
        end
        local d = Bastians:GetService("data")
        local find, get = d.Find, d.Get
        local rows = {{
          [91] = {{ name = "Young Wolf" }},
          [92] = {{ name = "Elder Stormbrow", flags = {{ "questgiver" }} }},
          [93] = {{ name = "Rare Stag", flags = "rare" }},
          [94] = {{ name = "Old Hound" }},
        }}
        d.Find = function(self, typ, text, limit)
          if typ ~= "npc" then return find(self, typ, text, limit) end
          local out = {{}}
          for id, r in pairs(rows) do
            if r.name == text then out[#out + 1] = {{ id = id, name = r.name }} end
          end
          return out
        end
        d.Get = function(self, typ, id)
          if typ == "npc" and rows[id] then return rows[id] end
          return get(self, typ, id)
        end
        {TR}.Reset()
        """
    )


def test_a_tracked_beast_gets_a_pin_and_a_person_does_not(wow: WowRuntime):
    # "the hunters track beasts is not working on our maps"
    boot(wow)
    our_style(wow)
    hunter(wow)
    wow.execute(
        "function UnitName(u) if u == 'pet' then return 'Old Hound' end return 'Bastienne' end"
    )
    blips(
        wow,
        (20, 0, "Young Wolf"),
        (-30, 25, "Rare Stag"),
        (0, 0, "Bastienne"),  # the player: no NPC
        (40, 40, "Elder Stormbrow"),  # a quest giver: a service
        (-45, -35, "Old Hound"),  # the hunter's own pet, named like an NPC
        (45, -35, "Copper Vein"),
    )
    sweep(wow, frames=60)
    pins = tracked_pins(wow)
    assert set(pins) == {"Young Wolf", "Rare Stag", "Copper Vein"}
    assert pins["Young Wolf"].icon == wow.eval("Bastians.UI.IconTexture(Bastians.UI.MobKind())")
    assert pins["Copper Vein"].icon == wow.eval("Bastians.UI.IconTexture('mine')")
    assert wow.errors == []


def test_no_creature_pin_while_no_creature_tracking_is_on(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow, active=False)
    blips(wow, (20, 0, "Young Wolf"))
    sweep(wow, frames=60)
    assert tracked_pins(wow) == {}
    # Find Herbs on a hunter is no creature tracking either
    hunter(wow, active=True, spell=2383)
    sweep(wow, frames=60)
    assert tracked_pins(wow) == {}
    assert wow.errors == []


def test_no_creature_pin_for_a_class_without_creature_tracking(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow)
    wow.execute("function UnitClass() return 'Mage', 'MAGE', 8 end")
    blips(wow, (20, 0, "Young Wolf"))
    sweep(wow, frames=60)
    assert tracked_pins(wow) == {}
    assert wow.errors == []


def test_a_creatures_pin_follows_it_and_goes_with_it(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow)
    blips(wow, (20, 0, "Young Wolf"))
    sweep(wow, frames=60)
    first = known(wow)[0]
    start = (first.wx, first.wy)
    assert first.fine is None and first.kind == "creature"
    blips(wow, (26, 0, "Young Wolf"))  # it walked a few yards
    sweep(wow, frames=60)
    moved = known(wow)[0]
    assert len(known(wow)) == 1 and (moved.wx, moved.wy) != start and moved.fine is None
    blips(wow)
    sweep(wow, frames=60)
    sweep(wow, frames=60)
    assert tracked_pins(wow) == {}
    assert wow.errors == []


def test_the_classic_shape_of_the_tracking_answer_is_read_too(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    hunter(wow)
    wow.execute(
        "C_Minimap.GetTrackingInfo = function() return 'Track Beasts', 1, true, 'spell', nil, 1494 end"
    )
    assert wow.eval("Bastians.Compat.CreatureTrackingOn()") is True
    wow.execute(
        "C_Minimap.GetTrackingInfo = function() return 'Track Beasts', 1, false, 'spell', nil, 1494 end"
    )
    assert wow.eval("Bastians.Compat.CreatureTrackingOn()") is False
    wow.execute("C_Minimap.GetTrackingInfo = nil")
    assert wow.eval("Bastians.Compat.CreatureTrackingOn()") is None
    assert wow.errors == []


def test_a_name_in_the_clients_language_is_found_through_the_game_objects(wow: WowRuntime):
    # the text packs translate objects, not nodes; a vein of no gather kind has only its object
    boot(wow)
    our_style(wow)
    wow.execute(
        f"""
        local d = Bastians:GetService("data")
        local get, index = d.Get, d.Index
        local names = {{ [1731] = "Kupfervorkommen", [73941] = "Schlammbedecktes Goldvorkommen" }}
        d.Index = function(self, name, key)
          if name ~= "node.objects" then return index(self, name, key) end
          return {{ [1731] = "mine", [73941] = "mine" }}
        end
        d.Get = function(self, typ, id)
          if typ == "object" then return {{ name = names[id] }} end
          return get(self, typ, id)
        end
        {TR}.Reset()
        """
    )
    blips(wow, (20, 0, "Kupfervorkommen"), (-30, 25, "Schlammbedecktes Goldvorkommen"))
    sweep(wow, frames=60)
    assert set(tracked_pins(wow)) == {"Kupfervorkommen", "Schlammbedecktes Goldvorkommen"}
    assert wow.errors == []


def test_a_herbs_name_also_comes_from_its_item(wow: WowRuntime):
    # the text packs miss some objects (Arthas' Tears in German); the client names the item
    boot(wow)
    our_style(wow)
    wow.execute(
        f"""
        local d = Bastians:GetService("data")
        local get = d.Get
        d.Get = function(self, typ, id)
          if typ == "node" and id == 1 then return {{ name = "Arthas' Tears", kind = "herb", item = 8836 }} end
          if typ == "item" and id == 8836 then return {{ name = "Arthas' Traenen" }} end
          return get(self, typ, id)
        end
        {TR}.Reset()
        """
    )
    wow.execute('Mock.minimapBlips = { { u = 20, v = 0, name = "Arthas\' Traenen" } }')
    sweep(wow, frames=60)
    assert set(tracked_pins(wow)) == {"Arthas' Traenen"}
    assert wow.errors == []


def test_without_the_data_no_sweep_runs_and_the_setting_says_why(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local service = Bastians.GetService
        Bastians.GetService = function(self, name)
          if name == "data" then return nil end
          return service(self, name)
        end
        """
    )
    pencil(wow)
    wow.execute(f"{MOD}.db.profile.miniWarned = true; {MINI}.SetStyle('pencil')")
    wow.run_frames(2)
    assert wow.eval(f"{TR}.Running()") is False
    assert "Data" in wow.eval(f"{TR}.Note()")
    sweep(wow)
    assert wow.eval("Mock.minimapProbes") == 0
    assert wow.errors == []


def test_a_node_at_the_rim_keeps_the_grids_place_until_all_of_it_shows(wow: WowRuntime):
    # the rim cuts off what answers and would pull the centre inwards
    boot(wow)
    our_style(wow)
    half = wow.eval("Minimap:GetWidth()") / 2
    blips(wow, (half - 8, 0, "Peacebloom"))
    sweep(wow, frames=40)
    assert len(known(wow)) == 1 and known(wow)[0].fine is None
    assert known(wow)[0].tries == 0  # no pass ran: nothing counts against it
    assert wow.eval(f"{TR}.stats.fine") == 0
    assert wow.errors == []


def test_a_node_gone_before_its_pass_is_no_error_and_combat_stops_the_pass(wow: WowRuntime):
    boot(wow)
    our_style(wow)
    blips(wow, (23.7, -11.3, "Peacebloom"))
    until_swept(wow)
    wow.execute("Mock.minimapBlips = {}")  # gathered: the pass hears nothing
    wow.run_frames(40)
    assert wow.eval(f"{TR}.stats.fine") == 0
    assert known(wow)[0].tries == 1 and known(wow)[0].fine is None
    # in combat nothing is asked, the pass is dropped, the next sweep after it starts one again
    blips(wow, (23.7, -11.3, "Peacebloom"))
    until_swept(wow)
    wow.run_frames(1)
    wow.set_combat(True)
    probes = wow.eval("Mock.minimapProbes")
    wow.run_frames(10)
    assert wow.eval("Mock.minimapProbes") == probes
    assert wow.eval("Minimap.softCursor") is False
    assert wow.eval(f"{TR}.stats.fine") == 0
    wow.set_combat(False)
    sweep(wow, frames=60)
    assert wow.eval(f"{TR}.stats.fine") == 1 and known(wow)[0].fine is True
    assert wow.errors == []


def test_the_grouping_and_the_yard_conversion_are_pure(wow: WowRuntime):
    boot(wow)
    groups = wow.eval(
        f"{TR}.Cluster({{ {{ 0, 0 }}, {{ 8, 0 }}, {{ 0, 8 }}, {{ 8, 8 }}, {{ 100, 100 }}, {{ 108, 100 }} }}, 8)"
    )
    assert [(g.u, g.v, g.n) for g in groups.values()] == [(4.0, 4.0, 4), (104.0, 100.0, 2)]
    # points that carry their world yards: the group's place is their mean
    groups = wow.eval(f"{TR}.Cluster({{ {{ 0, 0, 10, 20 }}, {{ 8, 0, 14, 24 }} }}, 8)")
    assert [(g.wx, g.wy) for g in groups.values()] == [(12.0, 22.0)]
    # 10 px right at 0.5 px per yard: 20 yd east, which is 20 yd less wy; up is north, more wx
    assert tuple(wow.eval(f"{TR}.ToWorld(10, 0, 0.5, nil, 1000, 2000)")) == (1000, 1980)
    assert tuple(wow.eval(f"{TR}.ToWorld(0, 10, 0.5, nil, 1000, 2000)")) == (1020, 2000)
    # a rotating minimap: facing east (a quarter turn) puts "ahead" up, so up is east
    wx, wy = wow.eval(f"{TR}.ToWorld(0, 10, 0.5, -math.pi / 2, 1000, 2000)")
    assert math.isclose(wx, 1000, abs_tol=1e-6) and math.isclose(wy, 1980, abs_tol=1e-6)
