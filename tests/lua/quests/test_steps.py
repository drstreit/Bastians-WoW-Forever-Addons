"""Where a quest sends you (ADR 0069, quests.md): the facet `steps` with the log's state, and a
quest's Locations() as the places of its open steps.
"Mirror Lake" asks for a water sample nobody could place, and Map and Route led back to the giver."""

from harness import WowRuntime
from test_registrations import boot

MOD = "Bastians:GetModule('Quests')"
LOGIC = f"{MOD}.Logic"
REG = f"{MOD}.Registrations"

# take, two creatures, an item, hand-in: what data:Steps gives for a pack without `steps`
PLAIN = """
plain = {
  { step = "take", ref = "npc:1", places = { { map = 1429, x = 0.1, y = 0.1 } } },
  { step = "slay", ref = "npc:2", places = { { map = 1429, x = 0.2, y = 0.2 } } },
  { step = "slay", ref = "npc:3", places = { { map = 1429, x = 0.3, y = 0.3 } } },
  { step = "get", ref = "item:4", places = {} },
  { step = "handin", ref = "npc:1", places = { { map = 1429, x = 0.1, y = 0.1 } } },
}
function objective(kind, have, need)
  return { kind = kind, text = kind .. " " .. have .. "/" .. need, fulfilled = have, required = need,
    finished = have >= need }
end
"""


def steps(wow: WowRuntime, entry: str = "nil", status: str = "nil", plain: str = "plain") -> list:
    got = wow.eval(f"{LOGIC}.Steps({plain}, {entry}, {status})")
    return [got.state, *(got[i] for i in range(1, len(got) + 1))]


def open_steps(got: list) -> list:
    return [(s.step, s.n) for s in got[1:] if s.open]


def test_the_state_says_which_steps_are_open(wow: WowRuntime):
    boot(wow)
    wow.execute(PLAIN)
    assert open_steps(steps(wow, status="'available'")) == [("take", None)]
    assert steps(wow, status="'level'")[0] == "level"
    assert open_steps(steps(wow, status="'prereq'")) == [("take", None)]
    done = steps(wow, status="'done'")
    assert done[0] == "done" and open_steps(done) == []
    complete = steps(wow, "{ isComplete = true, objectives = {} }")
    assert complete[0] == "complete" and open_steps(complete) == [("handin", None)]
    ready = steps(wow, "{ readyForTurnIn = true, objectives = {} }")
    assert open_steps(ready) == [("handin", None)]
    # the input is another's cached answer: it is not changed
    assert wow.eval("plain.state == nil and plain[1].open == nil and plain[2].n == nil") is True
    assert wow.eval(f"{LOGIC}.Steps(nil, nil, 'available')") is None
    assert wow.errors == []


def test_a_running_quest_opens_what_is_not_finished(wow: WowRuntime):
    boot(wow)
    wow.execute(PLAIN)
    got = steps(
        wow,
        "{ objectives = { objective('monster', 8, 8), objective('monster', 2, 6), "
        "objective('item', 0, 1) } }",
    )
    assert got[0] == "active"
    assert [(s.step, s.n, s.done, s.have, s.count) for s in got[2:5]] == [
        ("slay", 1, True, 8, 8),
        ("slay", 2, False, 2, 6),
        ("get", 3, False, 0, 1),
    ]
    assert got[3].text == "monster 2/6"
    assert open_steps(got) == [("slay", 2), ("get", 3)]
    assert got[1].done is True  # it is in the log: taken
    # everything finished and the log not yet complete: the hand-in
    over = steps(
        wow,
        "{ objectives = { objective('monster', 8, 8), objective('monster', 6, 6), "
        "objective('item', 1, 1) } }",
    )
    assert open_steps(over) == [("handin", None)]
    # a delivery: nothing to do, nothing listed
    delivery = steps(wow, "{ objectives = {} }", plain="{ plain[1], plain[5] }")
    assert open_steps(delivery) == [("handin", None)]
    assert wow.errors == []


def test_a_step_nobody_can_match_stays_open(wow: WowRuntime):
    """The pack and the client count a kind differently: which is which is unknown, and unknown
    is not done. A step with `n` is the client's n-th whatever the counts say."""
    boot(wow)
    wow.execute(PLAIN)
    got = steps(wow, "{ objectives = { objective('monster', 8, 8), objective('item', 1, 1) } }")
    assert [(s.step, s.n, s.done, s.open) for s in got[2:5]] == [
        ("slay", None, None, True),
        ("slay", None, None, True),
        ("get", 2, True, False),
    ]
    wow.execute("plain[3].n = 1")
    numbered = steps(
        wow, "{ objectives = { objective('monster', 8, 8), objective('monster', 0, 4) } }"
    )
    assert [(s.step, s.n, s.done) for s in numbered[2:4]] == [("slay", 2, False), ("slay", 1, True)]
    assert wow.errors == []


def test_a_numbered_step_is_the_clients_objective_of_that_number(wow: WowRuntime):
    """Everything Quests numbers a step within its kind as the client does: no counting needed,
    and a number the client does not list stays open."""
    boot(wow)
    wow.execute(PLAIN)
    wow.execute("plain[2].nth = 2; plain[3].nth = 1; plain[4].nth = 2")
    got = steps(
        wow,
        "{ objectives = { objective('item', 3, 3), objective('monster', 8, 8), "
        "objective('monster', 0, 6) } }",
    )
    assert [(s.step, s.ref, s.n, s.done) for s in got[2:5]] == [
        ("slay", "npc:2", 3, False),
        ("slay", "npc:3", 2, True),
        ("get", "item:4", None, None),
    ]
    assert open_steps(got) == [("slay", 3), ("get", None)]
    assert wow.errors == []


def test_what_the_client_lists_and_the_pack_does_not_is_a_step_without_a_place(wow: WowRuntime):
    """An exploration the pack knows nothing of must not open the hand-in: the thing to do is
    there, its place is unknown."""
    boot(wow)
    wow.execute(PLAIN)
    got = steps(
        wow, "{ objectives = { objective('event', 0, 1) } }", plain="{ plain[1], plain[5] }"
    )
    assert [(s.step, s.n, s.how, s.text) for s in got[2:3]] == [("do", 1, "unknown", "event 0/1")]
    assert open_steps(got) == [("do", 1)]
    assert got[2].places is None
    finished = steps(
        wow, "{ objectives = { objective('event', 1, 1) } }", plain="{ plain[1], plain[5] }"
    )
    assert open_steps(finished) == [("handin", None)]
    # a kind the pack has steps of is theirs, even unmatched: no second step for it
    crowded = steps(wow, "{ objectives = { objective('item', 0, 1), objective('item', 0, 1) } }")
    assert [s.step for s in crowded[1:]] == ["take", "slay", "slay", "get", "handin"]
    assert wow.errors == []


def test_the_clients_area_joins_the_step_it_belongs_to(wow: WowRuntime):
    """A bare area is the client's own place for its n-th objective: the step that turns out to
    be that objective takes its places. A step nobody can match goes when areas stand for the
    things to do."""
    boot(wow)
    wow.execute(PLAIN)
    wow.execute(
        """
        withAreas = {
          plain[1],
          { step = "slay", ref = "npc:2", places = { { map = 1429, x = 0.2, y = 0.2 } } },
          { step = "get", ref = "item:4", places = {} },
          { step = "reach", n = 1, src = "data", places = { { map = 1429, x = 0.5, y = 0.5 } } },
          { step = "reach", n = 2, src = "data", places = { { map = 1429, x = 0.6, y = 0.6 } } },
          plain[5],
        }
        """
    )
    got = steps(
        wow,
        "{ objectives = { objective('monster', 0, 8), objective('item', 1, 1) } }",
        plain="withAreas",
    )
    assert [(s.step, s.ref, s.n, s.done) for s in got[2:4]] == [
        ("slay", "npc:2", 1, False),
        ("get", "item:4", 2, True),
    ]
    assert [(p.x, p.y) for p in got[2].places.values()] == [(0.5, 0.5)]  # the client's area
    assert got[2].src == "data" and len(got) == 5
    # the pack lists one item, the client two: the areas stay, the unmatched item step goes
    apart = steps(
        wow,
        "{ objectives = { objective('item', 0, 1), objective('item', 1, 1) } }",
        plain="{ withAreas[1], withAreas[3], withAreas[4], withAreas[5], withAreas[6] }",
    )
    assert [(s.step, s.ref, s.n, s.done) for s in apart[2:4]] == [
        ("reach", None, 1, False),
        ("reach", None, 2, True),
    ]
    assert open_steps(apart) == [("reach", 1)]
    assert wow.errors == []


def test_a_place_we_authored_for_the_objective_wins_over_the_quests_own_points(wow: WowRuntime):
    """data.md "Our authored table" (package QD5): a row of our own table names an objective by
    its number in the log, as the client's areas do. The quest's own points stay against the
    client's area; against a place a person checked or read they give way, checked or not."""
    boot(wow)
    wow.execute(PLAIN)
    wow.execute(
        """
        function own(areaSrc)
          return {
            plain[1],
            { step = "slay", ref = "npc:2", src = "eq", places = { { map = 1429, x = 0.2, y = 0.2 } } },
            { step = "reach", n = 1, src = areaSrc, places = { { map = 1429, x = 0.5, y = 0.5 } } },
            plain[5],
          }
        end
        """
    )
    entry = "{ objectives = { objective('monster', 0, 8) } }"
    for src, where, said in (
        ("client", (0.2, 0.2), "eq"),
        ("fdb", (0.2, 0.2), "eq"),
        ("verified", (0.5, 0.5), "verified"),
        ("authored", (0.5, 0.5), "authored"),
    ):
        got = steps(wow, entry, plain=f"own('{src}')")
        assert [(s.step, s.ref, s.n) for s in got[2:3]] == [("slay", "npc:2", 1)], src
        assert [(p.x, p.y) for p in got[2].places.values()] == [where], src
        assert got[2].src == said and len(got) == 4, src  # the area itself is gone either way
    assert wow.errors == []


MIRROR_LAKE = """
local q = Bastians:GetModule('Quests').Logic.quest(76)
q.objectives = { { 'loot', 'item:7206' } }; q.spots = nil
Mock.questLog[#Mock.questLog + 1] = { questID = 76, title = 'Mirror Lake', level = 10,
  complete = false, objectives = { { text = 'Mirror Lake Water Sample', type = 'item',
    finished = false, numFulfilled = 0, numRequired = 1 } } }
"""


def settle(wow: WowRuntime) -> None:
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.5)
    wow.run_frames(5)


def locations(wow: WowRuntime, ref: str = "quest:76") -> list[tuple]:
    points = wow.eval(f"Bastians:Entity('{ref}'):Locations()").values()
    return [(p.kind, p.map, p.x, p.y, p.src) for p in points]


def test_a_running_quest_without_a_known_place_has_no_place(wow: WowRuntime):
    """The reported error: in the log, open, the pack places nothing, the client gives no
    waypoint. The giver is also the hand-in, and neither is where the water is."""
    boot(wow)
    assert [p[0] for p in locations(wow)] == ["giver"]  # not taken yet: where it is given
    wow.execute(MIRROR_LAKE)
    settle(wow)
    facet = wow.eval("Bastians:Entity('quest:76'):Facet('steps')")
    assert facet.state == "active"
    todo = facet[2]
    assert (todo.step, todo.ref, todo.n, todo.open, todo.text) == (
        "get",
        "item:7206",
        1,
        True,
        "Mirror Lake Water Sample",
    )
    assert len(list(todo.places.values())) == 0
    assert locations(wow) == []
    assert wow.eval("#Bastians:Entity('quest:76'):Places()") == 0
    # every place the pack has is still there for who asks for all of them
    kinds = {p.kind for p in wow.eval("Bastians:Entity('quest:76'):AllLocations()").values()}
    assert kinds == {"giver"}  # the hand-in stands at the same place: one point
    # handed in later: the hand-in, as before
    wow.execute("Mock.questLog[#Mock.questLog].complete = true")
    settle(wow)
    assert [p[0] for p in locations(wow)] == ["turnin"]
    assert wow.errors == []


def test_the_clients_waypoint_fills_in_only_when_no_step_has_a_place(wow: WowRuntime):
    """D2: asked for the player's map and for the quest's zone (the owner stood in Stormwind, the
    lake is in Elwynn Forest); never when the pack places a step."""
    boot(wow)
    wow.execute(MIRROR_LAKE)
    wow.execute("Mock.playerMap = 1453; Mock.waypoints[76] = { map = 1429, x = 0.29, y = 0.61 }")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    settle(wow)
    assert wow.eval("Bastians.Coords.PlayerMap()") == 1453
    assert locations(wow) == [("objective", 1429, 0.29, 0.61, "client")]
    # quest 176 has spots in the pack: its waypoint is not asked for
    wow.execute("Mock.waypoints[176] = { map = 1429, x = 0.9, y = 0.9 }")
    settle(wow)
    assert wow.eval("Bastians:Entity('quest:176'):Facet('steps').waypoint") is None
    assert all(p[4] != "client" for p in locations(wow, "quest:176"))
    assert wow.errors == []


def test_the_data_fix_gives_the_step_its_place(wow: WowRuntime):
    """What package QD1 brings: the item's record names the object it comes from, and the place
    says what stands there."""
    boot(wow)
    wow.execute(MIRROR_LAKE)
    wow.execute(
        "local d = Bastians:GetService('data'); "
        "Mock.Keep(d:Get('item', 2589)).drops = { { 'object:1734' } }; "
        "Mock.Keep(Bastians:GetModule('Quests').Logic.quest(76)).objectives = { { 'loot', 'item:2589' } }"
    )
    settle(wow)
    points = list(wow.eval("Bastians:Entity('quest:76'):Locations()").values())
    assert [(p.kind, p.x, p.y, p.ref, p.step) for p in points] == [
        ("objective", 0.42, 0.66, "object:1734", 2)
    ]
    assert wow.errors == []


def test_a_done_quest_shows_where_it_began(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MOD}.State.MarkDone(76); Bastians:Fire('BASTIANS_QUESTS_CHANGED')")
    assert wow.eval("Bastians:Entity('quest:76'):Facet('steps').state") == "done"
    assert [p[0] for p in locations(wow)] == ["giver"]
    assert wow.errors == []


# ---------------------------------------------------------------------------------------------
# The readers (package QR2): one statement, read by the band, the log's rows, the sheet, the
# focus quest, the round and the ranking
# ---------------------------------------------------------------------------------------------


def places(wow: WowRuntime, ref: str, kind: str) -> list[tuple]:
    points = wow.eval(f"{REG}.QuestPlaces('{ref}', '{kind}')").values()
    return [(p.kind, p.x, p.y, p.ref, p.step, p.src) for p in points]


def test_the_bands_places_are_the_steps_of_one_kind(wow: WowRuntime):
    """Giver, Targets and Hand-in read the facet: where it is taken, the things to do that are
    not finished, where it is handed in, whatever the quest's status."""
    boot(wow)
    assert places(wow, "quest:176", "giver") == [("giver", 0.42, 0.66, "object:1734", 1, "eq")]
    assert [p[:3] for p in places(wow, "quest:176", "objective")] == [
        ("objective", 0.25, 0.93),
        ("objective", 0.4, 0.7),
    ]
    assert places(wow, "quest:176", "objective")[0][3:5] == ("item:1931", 2)  # what it is for
    assert [p[0] for p in places(wow, "quest:176", "turnin")] == ["turnin"]
    assert places(wow, "quest:424242", "giver") == []  # a quest nobody knows
    # the thing to do finished: its places are no targets any more
    wow.execute(
        "Mock.questLog[2].objectives = { { text = 'Huge Gnoll Claw: 1/1', type = 'item', "
        "finished = true, numFulfilled = 1, numRequired = 1 } }"
    )
    settle(wow)
    assert places(wow, "quest:176", "objective") == []
    # the client's place fills in for a quest of the log none of whose steps has one
    wow.execute(MIRROR_LAKE)
    wow.execute("Mock.waypoints[76] = { map = 1429, x = 0.29, y = 0.61 }")
    settle(wow)
    assert places(wow, "quest:76", "objective") == [("objective", 0.29, 0.61, None, None, "client")]
    assert wow.errors == []


SONG = """
Mock.questLog[#Mock.questLog + 1] = { questID = 99999, title = 'A Song for Our Future', level = 10,
  complete = false, objectives = { { text = 'Sing', type = 'event', finished = false,
    numFulfilled = 0, numRequired = 1 } } }
"""


def test_a_quest_the_pack_does_not_know_has_what_the_client_lists(wow: WowRuntime):
    """Forever's own quests are in no source: the log's objectives are the things to do, without
    a place, and the client's place is all there is, for the hand-in too."""
    boot(wow)
    assert wow.eval("Bastians:Entity('quest:99999'):Facet('steps')") is None  # nobody knows it
    wow.execute(SONG)
    settle(wow)
    facet = wow.eval("Bastians:Entity('quest:99999'):Facet('steps')")
    assert facet.state == "active"
    assert [(s.step, s.n, s.text, s.open) for s in (facet[1], facet[2], facet[3])] == [
        ("take", None, None, None),
        ("do", 1, "Sing", True),
        ("handin", None, None, None),
    ]
    assert locations(wow, "quest:99999") == []
    wow.execute("Mock.waypoints[99999] = { map = 1429, x = 0.3, y = 0.4 }")
    settle(wow)  # the log did not change: the client is asked again once per burst of its events
    assert locations(wow, "quest:99999") == [("objective", 1429, 0.3, 0.4, "client")]
    wow.execute("Mock.questLog[#Mock.questLog].complete = true")
    settle(wow)
    assert locations(wow, "quest:99999") == [("turnin", 1429, 0.3, 0.4, "client")]
    assert wow.errors == []


def test_the_clients_place_is_asked_again_when_it_may_have_changed(wow: WowRuntime):
    """The client learns its places after the log, and the waypoint is asked for the player's
    map: asked again once per burst of quest events and on a zone change, told once."""
    boot(wow)
    wow.execute(MIRROR_LAKE)
    settle(wow)
    assert locations(wow) == []
    wow.execute(
        """
        fired = 0
        local w = Bastians:NewModule("PlaceWatcher", { addon = "Bastians_Quests" })
        w:On("BASTIANS_QUESTS_CHANGED", function() fired = fired + 1 end)
        """
    )
    settle(wow)
    assert wow.eval("fired") == 0  # the client said nothing new: nothing is told
    wow.execute("Mock.waypoints[76] = { map = 1429, x = 0.29, y = 0.61 }")
    settle(wow)
    assert wow.eval("fired") == 1 and len(locations(wow)) == 1
    settle(wow)
    assert wow.eval("fired") == 1  # the same answer again: said once
    wow.execute("Mock.waypoints[76] = nil")
    wow.execute("Bastians:Fire('BASTIANS_PLAYER_MOVED_ZONE', 1453, 0)")
    assert locations(wow) == []
    assert wow.errors == []


def test_the_log_row_the_sheet_and_the_map_read_one_place(wow: WowRuntime):
    """Plan-quest-links.md section 4.3: the sheet's line was one reader's hand-in, its buttons
    another's giver. Every reader takes the nearest place of the open steps, or none."""
    boot(wow)
    wow.execute(MIRROR_LAKE)
    settle(wow)
    views, sheet = f"{MOD}.Views", f"{MOD}.Sheet"
    row = wow.eval(f"{views}.PlaceOf({MOD}.State.log[76], 1429, 0.42, 0.65)")
    assert (row.map, row.x, row.target, row.d) == (None, None, "objective", float("inf"))
    assert wow.eval(f"{sheet}.Model(76).where") == "Where this is done is not known"
    assert wow.eval(f"{REG}.FocusQuest()") == 176  # Mirror Lake has no place on the map
    # the open quest of the fixture: the nearer of its two spots, for all of them
    row = wow.eval(f"{views}.PlaceOf({MOD}.State.log[176], 1429, 0.42, 0.65)")
    assert (row.map, row.x, row.y, row.target) == (1429, 0.4, 0.7, "objective")
    assert abs(row.d - (0.02**2 + 0.05**2)) < 1e-9
    nearest = wow.eval("Bastians:Entity('quest:176'):Locations()")
    assert (0.4, 0.7) in [(p.x, p.y) for p in nearest.values()]
    assert wow.eval(f"{sheet}.Model(176).where") == "Right here"  # 21 yards away
    # on another map than the viewed one: named, and no distance on this map
    row = wow.eval(f"{views}.PlaceOf({MOD}.State.log[176], 1436, 0.5, 0.5)")
    assert (row.map, row.target, row.d) == (1429, "objective", float("inf"))
    # complete: the hand-in
    row = wow.eval(f"{views}.PlaceOf({MOD}.State.log[62], 1429, 0.42, 0.65)")
    assert (row.map, row.x, row.y, row.target) == (1429, 0.42, 0.65, "turnin")
    assert wow.errors == []


def test_a_quests_activity_says_where_it_is_done_now(wow: WowRuntime):
    """S7: Quests' activity rule answered before Data's and had no places."""
    boot(wow)
    act = wow.eval("Bastians:Entity('quest:176'):Facet('activity')")
    assert [(p.ui, p.x, p.kind) for p in act.places.values()] == [
        (1429, 0.25, "objective"),
        (1429, 0.4, "objective"),
    ]
    assert act.takes > 0 and act.src == "estimate"
    wow.execute(MIRROR_LAKE)
    settle(wow)
    assert len(wow.eval("Bastians:Entity('quest:76'):Facet('activity')").places) == 0
    assert wow.errors == []


def test_the_work_counts_things_to_do_not_rows(wow: WowRuntime):
    """Twelve wolves that drop the flank are one thing to do: the pack's rows counted them as
    twelve objectives. A step's count where the data has one, else the default of its kind."""
    boot(wow)
    rec = f"{MOD}.Recommend"
    wow.execute(
        """
        TIMES = { slay = 1, loot = 2, object = 3, event = 5, delivery = 7 }
        KABOBS = { { step = "take" }, { step = "get", ref = "item:1015", count = 10 },
          { step = "get", ref = "item:2665" }, { step = "slay", ref = "npc:1" },
          { step = "use", ref = "object:1" }, { step = "reach" }, { step = "handin" } }
        """
    )
    counts = wow.eval(f"{rec}.DEFAULT_COUNTS")
    want = 2 * 10 + 2 * counts.loot + 1 * counts.slay + 3 * counts.object + 5 * counts.event
    assert wow.eval(f"{rec}.objectiveMinutes(nil, TIMES, 1, KABOBS)") == want
    assert wow.eval(f"{rec}.objectiveMinutes(nil, TIMES, 2, KABOBS)") == 2 * want
    # nothing to do: a delivery; the log's own counts win where the quest is in the log
    assert wow.eval(f"{rec}.objectiveMinutes(nil, TIMES, 1, {{ KABOBS[1], KABOBS[7] }})") == 7
    assert wow.eval(f"{rec}.objectiveMinutes(nil, TIMES, 1, nil)") == 7
    entry = "{ objectives = { { kind = 'monster', required = 8, fulfilled = 5 } } }"
    assert wow.eval(f"{rec}.objectiveMinutes({entry}, TIMES, 1, KABOBS)") == 3
    assert wow.errors == []


def test_a_spots_icon_follows_the_kinds_the_data_has(wow: WowRuntime):
    """S1: the table named `kill`, `item` and `event`; the data's kinds are `slay`, `loot`,
    `object` and `area`, the steps' `slay`, `use`, `get`, `reach` and `cast`."""
    boot(wow)
    icons = wow.eval(f"{REG}.SPOT_ICON")
    assert {k: icons[k] for k in ("slay", "loot", "object", "area")} == {
        "slay": "mob",
        "loot": "mob",
        "object": "treasure",
        "area": "zone",
    }
    assert all(icons[k] for k in ("use", "get", "reach", "cast"))
    assert icons["kill"] is None and icons["event"] is None
    assert wow.errors == []


# ---------------------------------------------------------------------------------------------
# Step places a player learns: recording
# ---------------------------------------------------------------------------------------------


def risen(wow: WowRuntime, old: str, new: str) -> list:
    return list(
        wow.eval(f"{LOGIC}.Risen({{ objectives = {old} }}, {{ objectives = {new} }})").values()
    )


def test_a_count_that_grew_or_an_objective_that_finished_has_risen(wow: WowRuntime):
    boot(wow)
    wow.execute(PLAIN)
    two = "{ objective('monster', 2, 8), objective('item', 0, 1) }"
    assert risen(wow, two, "{ objective('monster', 5, 8), objective('item', 0, 1) }") == [1]
    assert risen(wow, two, "{ objective('monster', 8, 8), objective('item', 1, 1) }") == [1, 2]
    assert risen(wow, two, two) == []
    assert risen(wow, two, "{ objective('monster', 1, 8), objective('item', 0, 1) }") == []  # fell
    # an exploration has no count: it finishes
    event = "{ { kind = 'event', finished = %s } }"
    assert risen(wow, event % "false", event % "true") == [1]
    # a count unknown before is no rise: unknown is not zero
    unknown = "{ { kind = 'item', required = 4, finished = false } }"
    assert risen(wow, unknown, "{ objective('item', 3, 4) }") == []
    # the list changed (a quest of several stages): the number means another thing now
    assert risen(wow, two, "{ objective('monster', 5, 8) }") == []
    assert risen(wow, two, "{ objective('object', 5, 8), objective('item', 0, 1) }") == []
    assert risen(wow, two, "{ objective('monster', 5, 9), objective('item', 0, 1) }") == []
    assert list(wow.eval(f"{LOGIC}.Risen(nil, {{ objectives = {two} }})").values()) == []
    assert wow.errors == []


COUNTED = """
Mock.questLog[#Mock.questLog + 1] = { questID = 1861, title = 'Mirror Lake', level = 10,
  complete = false, objectives = {
    { text = 'Mirror Lake Water Sample: 0/1', type = 'item', finished = false,
      numFulfilled = 0, numRequired = 1 },
    { text = 'Murloc slain: 0/8', type = 'monster', finished = false,
      numFulfilled = 0, numRequired = 8 } } }
function count(n, have)
  local o = Mock.questLog[#Mock.questLog].objectives[n]
  o.numFulfilled, o.finished = have, have >= o.numRequired
end
"""


def learned_steps(wow: WowRuntime) -> dict:
    steps = wow.eval("BastiansDataDB.global.learned.steps")
    return {key: [tuple(p.values()) for p in places.values()] for key, places in steps.items()}


def test_where_a_count_rose_is_recorded_once(wow: WowRuntime):
    """The character's place on its map, by the objective's number in the client's list, through
    the graph. Taking a quest with the item already in the bags is no rise."""
    boot(wow)
    wow.advance(10)  # the log has settled
    wow.execute(COUNTED)
    wow.execute("count(1, 1)")  # in the bags when it is taken
    settle(wow)
    assert learned_steps(wow) == {}
    wow.execute("Mock.playerMapPos = { x = 0.28574, y = 0.61386 }; count(2, 3)")
    settle(wow)
    assert learned_steps(wow) == {"1861:2": [(1429, 0.2857, 0.6139)]}
    settle(wow)  # the same log again: nothing rose
    wow.execute("count(2, 5)")  # the same camp: one place
    settle(wow)
    assert learned_steps(wow) == {"1861:2": [(1429, 0.2857, 0.6139)]}
    wow.execute("Mock.playerMapPos = { x = 0.6, y = 0.3 }; count(2, 8)")
    settle(wow)
    assert learned_steps(wow)["1861:2"] == [(1429, 0.2857, 0.6139), (1429, 0.6, 0.3)]
    # the exploration of the Fargodeep Mine finishes where the character stands
    wow.execute(
        "Mock.playerMapPos = { x = 0.39, y = 0.82 }; "
        "local o = Mock.questLog[2].objectives[1]; o.finished, o.numFulfilled = true, 1"
    )
    settle(wow)
    assert learned_steps(wow)["176:1"] == [(1429, 0.39, 0.82)]
    assert wow.errors == []


def test_no_place_and_no_settled_log_record_nothing(wow: WowRuntime):
    """An instance gives no position; and in the first seconds after a loading screen a count
    that only arrived is no step done where the character logged in (assumed, quests.md)."""
    boot(wow)
    wow.advance(10)
    wow.execute(COUNTED)
    settle(wow)
    wow.execute("Mock.playerMap = nil; count(2, 2)")  # inside a dungeon
    settle(wow)
    assert learned_steps(wow) == {}
    wow.execute("Mock.playerMap = 1429")
    wow.fire("PLAYER_ENTERING_WORLD", False, False)  # out of the dungeon: a loading screen
    wow.execute("count(2, 4)")
    settle(wow)
    assert learned_steps(wow) == {}
    wow.advance(6)
    wow.execute("count(2, 6)")
    settle(wow)
    assert list(learned_steps(wow)) == ["1861:2"]
    assert wow.errors == []


def test_without_bastians_data_nothing_is_recorded_and_nothing_breaks(wow: WowRuntime):
    boot(wow, "Bastians_Core", "Bastians_Quests")
    wow.advance(10)
    wow.execute(COUNTED)
    settle(wow)
    wow.execute("count(2, 3)")
    settle(wow)
    assert wow.eval("Bastians:GetService('graph')") is None
    assert wow.eval(f"{MOD}.State.Entry(1861).objectives[2].fulfilled") == 3
    assert wow.errors == []
