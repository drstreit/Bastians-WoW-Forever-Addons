"""A quest's steps without a state (ADR 0069, ADR 0070; data.md "Links and steps"): the giver,
each thing to do with its own places, the hand-in. `Data.Steps.Of` is pure; `data:Steps` and the
facet `steps` answer for a quest without Bastian's Quests."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"
STEPS = "Bastians.Data.Steps"
# what the pure function reads: a creature's places, an item's droppers, a giver's place
READ = """
local spawns = {
  ["npc:448"] = { { map = 1429, x = 0.25, y = 0.93, src = "eq", wz = 30, r = 12 } },
  ["npc:327"] = { { map = 1429, x = 0.3, y = 0.8, src = "classic" } },
  ["object:174794"] = { { map = 1429, x = 0.2857, y = 0.6139, src = "classic" } },
}
local items = {
  [2589] = { drops = { { "npc:448", 45.5 }, { "npc:327", 12 } } },
  [7206] = { drops = { { "object:174794" } } },
}
read = {
  spawns = function(ref) return spawns[ref] or {} end,
  item = function(id) return items[id] end,
  places = function(ref)
    if ref == "npc:240" then return { { map = 1429, x = 0.42, y = 0.65, src = "eq" } } end
    if ref == "object:1734" then -- a notice board in two villages
      return { { map = 1429, x = 0.42, y = 0.66, src = "eq" }, { map = 1436, x = 0.5, y = 0.5, src = "eq" } }
    end
  end,
}
"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in ("world", "quests"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.execute(READ)
    return wow


def steps_of(wow: WowRuntime, record: str) -> list:
    return list(wow.eval(f"{STEPS}.Of({record}, read)").values())


def places(step) -> list[tuple]:
    return [(p.map, p.x, p.y, p.ref, p.src) for p in step.places.values()]


def test_a_quest_is_taken_done_and_handed_in(wow: WowRuntime):
    boot(wow)
    got = steps_of(
        wow,
        "{ starts = { 'npc:240' }, ends = { 'npc:241' }, "
        "endPlaces = { { 1453, 0.5, 0.86, 'fdb' } }, "
        "objectives = { { 'slay', 'npc:448' } } }",
    )
    assert [(s.step, s.ref) for s in got] == [
        ("take", "npc:240"),
        ("slay", "npc:448"),
        ("handin", "npc:241"),
    ]
    # the giver's own place where the quest names none; the quest's hand-in place as it is
    assert places(got[0]) == [(1429, 0.42, 0.65, "npc:240", "eq")]
    assert places(got[2]) == [(1453, 0.5, 0.86, None, "fdb")]
    # no spot: where the creature is, with its height and its roaming
    spawn = got[1].places[1]
    assert (spawn.x, spawn.wz, spawn.r, spawn.ref, spawn.src) == (0.25, 30, 12, None, "eq")
    assert got[1].n is None and got[1].open is None  # no state: Bastian's Quests knows
    # a giver with several places has them all (S4: only the first was taken), up to Steps.ENDS
    board = steps_of(wow, "{ starts = { 'object:1734' } }")
    assert [(p[0], p[3]) for p in places(board[0])] == [
        (1429, "object:1734"),
        (1436, "object:1734"),
    ]
    wow.execute(f"{STEPS}.ENDS = 1")
    assert len(places(steps_of(wow, "{ starts = { 'object:1734' } }")[0])) == 1
    wow.execute(f"{STEPS}.ENDS = 8")
    assert wow.eval(f"{STEPS}.Of(nil, read)") is None
    assert wow.errors == []


def test_a_spot_belongs_to_the_objective_with_its_bit_within_the_kind(wow: WowRuntime):
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'loot', 'item:2589' }, { 'slay', 'npc:448' }, { 'slay', 'npc:327' } }, "
        "spots = { [1429] = { { 0.1, 0.1, 'slay', 1 }, { 0.2, 0.2, 'slay', 2 }, { 0.3, 0.3, 'slay', 3 } }, "
        "[1433] = { { 0.5, 0.5, 'loot', 1 } } } }",
    )
    assert [s.step for s in got] == ["take", "get", "slay", "slay", "handin"]
    assert places(got[1]) == [(1433, 0.5, 0.5, None, None)] and got[1].src == "data"
    assert [p[1] for p in places(got[2])] == [0.1, 0.3]
    assert [p[1] for p in places(got[3])] == [0.2, 0.3]
    assert wow.errors == []


def test_a_spot_says_who_stands_there(wow: WowRuntime):
    """Package QD1: the build gives a quest without a spot the places of who has its item, and a
    spot's fifth field names them. Mirror Lake's pin is the waterwall's, and its way is said."""
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'loot', 'item:7206' } }, "
        "spots = { [1429] = { { 0.2857, 0.6139, 'loot', 1, 'object:174794' } } } }",
    )
    assert places(got[1]) == [(1429, 0.2857, 0.6139, "object:174794", None)]
    assert (got[1].src, got[1].how, list(got[1].via.values())) == (
        "data",
        "open",
        ["object:174794"],
    )
    assert wow.errors == []


def test_an_item_without_a_spot_is_where_its_droppers_are(wow: WowRuntime):
    """The water sample of "Mirror Lake" is filled at an object: the
    place names what stands there. An item nothing drops has no place, and no guess."""
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'loot', 'item:7206' }, { 'loot', 'item:2589', nil, 'npc:999' }, "
        "{ 'loot', 'item:1', nil, 'npc:327' }, { 'loot', 'item:2' } } }",
    )
    assert places(got[1]) == [(1429, 0.2857, 0.6139, "object:174794", "classic")]
    # the loot record's droppers, the likeliest first; the objective's named source is not asked
    assert [p[3] for p in places(got[2])] == ["npc:448", "npc:327"]
    # no loot record: the named source is all there is
    assert [p[3] for p in places(got[3])] == ["npc:327"]
    assert places(got[4]) == []
    wow.execute(f"{STEPS}.DROPPERS = 1")
    again = steps_of(wow, "{ objectives = { { 'loot', 'item:2589' } } }")
    assert [p[3] for p in places(again[1])] == ["npc:448"]
    wow.execute(f"{STEPS}.DROPPERS = 12")
    assert wow.errors == []


def test_numbered_rows_are_grouped_into_the_objectives_they_count_for(wow: WowRuntime):
    """Everything Quests' rows (the installed Forever pack, 10.11.2026): a row is one creature that
    counts for the objective of its number within its kind, so twelve wolves are one thing to do.
    The items are the quest's required items in their order; the loot group of that number names
    who has an item whose own loot record names nobody. The pipeline's item rows pair by row
    (here the second names a wolf for the herbs) and are not read."""
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'loot', 'item:1015', 0, 'npc:213' }, { 'loot', 'item:2665', 0, 'npc:521' }, "
        "{ 'loot', 'npc:327', 0 }, { 'loot', 'npc:448', 1 }, "
        "{ 'slay', 'npc:448', 0 }, { 'slay', 'npc:327', 0 }, { 'slay', 'npc:9', 1 } }, "
        "requiredItems = { { 1015, 10 }, { 2665, 2 } }, "
        "spots = { [1429] = { { 0.7, 0.7, 'slay', 2 } } } }",
    )
    assert [(s.step, s.nth, s.ref, s.count) for s in got[1:-1]] == [
        ("slay", 1, "npc:448", None),
        ("slay", 2, "npc:9", None),
        ("get", 1, "item:1015", 10),
        ("get", 2, "item:2665", 2),
    ]
    assert list(got[1].refs.values()) == ["npc:448", "npc:327"] and got[2].refs is None
    # either creature counts: both are where the step is done, each place names its own
    assert [p[3] for p in places(got[1])] == [None, "npc:327"]
    assert places(got[2]) == [(1429, 0.7, 0.7, None, None)]  # the quest's own spot, by its bit
    assert [p[3] for p in places(got[3])] == ["npc:327"]  # the loot group of number 0
    assert [p[3] for p in places(got[4])] == ["npc:448"]  # of number 1: not the wolf of its row
    # a loot group beyond the required items: an item the pack does not name
    extra = steps_of(wow, "{ objectives = { { 'loot', 'npc:327', 0 } } }")
    assert [(s.step, s.nth, s.ref) for s in extra[1:-1]] == [("get", 1, None)]
    assert list(extra[1].refs.values()) == ["npc:327"] and len(places(extra[1])) == 1
    assert wow.errors == []


def test_a_required_item_is_a_thing_to_do_without_a_row(wow: WowRuntime):
    """649 quests of the installed Forever pack bring items and list no objective: the required
    item is the step, placed by the item's own loot record."""
    boot(wow)
    got = steps_of(wow, "{ requiredItems = { { 2589, 5 }, { 77, 1 } } }")
    assert [(s.step, s.ref, s.count) for s in got[1:-1]] == [
        ("get", "item:2589", 5),
        ("get", "item:77", 1),
    ]
    assert [p[3] for p in places(got[1])] == ["npc:448", "npc:327"]
    assert places(got[2]) == []  # nobody is known to have it: no place
    # beside plain rows only what no row names
    plain = steps_of(
        wow,
        "{ objectives = { { 'loot', 'item:2589' } }, requiredItems = { { 2589, 5 }, { 77, 1 } } }",
    )
    assert [s.ref for s in plain[1:-1]] == ["item:2589", "item:77"]
    assert wow.errors == []


def test_the_clients_areas_are_steps_by_the_clients_numbers(wow: WowRuntime):
    """An `area` spot's bits are the client's objective numbers, not the pack's: a `reach` step
    per number. A spot nothing claims stays, as one step at the end."""
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'slay', 'npc:448' } }, spots = { [1429] = { "
        "{ 0.43, 0.66, 'area', 1 }, { 0.44, 0.6, 'area', 5 }, { 0.4, 0.62, 'mystery', 1 }, "
        "{ 0.41, 0.6, 'slay', 0 } } } }",
    )
    assert [(s.step, s.n, s.ref) for s in got] == [
        ("take", None, None),
        ("slay", None, "npc:448"),
        ("reach", 1, None),
        ("reach", 3, None),
        ("reach", None, None),
        ("handin", None, None),
    ]
    assert [p[1] for p in places(got[2])] == [0.43, 0.44]
    assert [p[1] for p in places(got[3])] == [0.44]
    assert [p[1] for p in places(got[4])] == [0.4, 0.41]
    assert wow.errors == []


def test_a_pack_with_steps_is_only_unpacked(wow: WowRuntime):
    """Shape 2 (data.md): the build resolved the places; `objectives` and `spots` are not read."""
    boot(wow)
    got = steps_of(
        wow,
        "{ objectives = { { 'slay', 'npc:448' } }, steps = { "
        "{ 1, 'get', 'item:7206', 1, 'make', { 'item:7207', 'object:174794' }, "
        "{ [1429] = { { 0.2857, 0.6139, 'object:174794' } } }, 'classic' }, "
        "{ nil, 'reach', 'area:18', nil, nil, nil, { [1433] = { { 0.5, 0.5 } }, [1429] = { { 0.3, 0.3 } } }, 'fdb' }, "
        "{ 2, 'get', 'item:5', 3, 'reward', { 'quest:9' } } } }",
    )
    assert [s.step for s in got] == ["take", "get", "reach", "get", "handin"]
    flask = got[1]
    assert (flask.n, flask.ref, flask.count, flask.how, flask.src) == (
        1,
        "item:7206",
        1,
        "make",
        "classic",
    )
    assert list(flask.via.values()) == ["item:7207", "object:174794"]
    # the place's source is the waterwall's own: a place row of the pack is { x, y, ref }
    assert places(flask) == [(1429, 0.2857, 0.6139, "object:174794", "classic")]
    assert [p[0] for p in places(got[2])] == [1429, 1433]  # the maps in order: the same every time
    assert (got[3].how, places(got[3])) == ("reward", [])
    assert wow.errors == []


def test_the_service_and_the_facet_answer_without_quests(wow: WowRuntime):
    boot(wow)
    got = list(wow.eval("Bastians:GetService('data'):Steps('quest:176')").values())
    assert [s.step for s in got] == ["take", "get", "handin"]
    assert [(p.x, p.y) for p in got[1].places.values()] == [(0.25, 0.93), (0.4, 0.7)]
    assert wow.eval("Bastians:GetService('data'):Steps('quest:424242')") is None
    assert wow.eval("Bastians:GetService('data'):Steps('npc:448')") is None
    facet = wow.eval("Bastians:Entity('quest:176'):Facet('steps')")
    assert facet.state is None and len(list(facet.values())) == 3
    # without a state every step counts: the giver, the targets, the hand-in
    kinds = [p.kind for p in wow.eval("Bastians:Entity('quest:176'):Locations()").values()]
    assert kinds == ["giver", "objective", "objective", "turnin"]
    assert wow.eval("Bastians:Entity('quest:176'):Locations()[2].step") == 2
    assert wow.errors == []


def test_a_steps_row_carries_its_number_within_the_kind_and_every_subject(wow: WowRuntime):
    """Package QD3: `nth` (the ninth field) joins a step to the client's objective of its kind,
    and `more` (the tenth) names the other creatures that count for it; an item no source names
    has no subject of its own, only who has it."""
    boot(wow)
    got = steps_of(
        wow,
        "{ steps = { "
        "{ nil, 'slay', 'npc:448', 10, nil, nil, { [1429] = { { 0.25, 0.93 } } }, 'eq', 2, "
        "{ 'npc:327' } }, "
        "{ nil, 'get', nil, nil, 'loot', { 'npc:448' }, nil, nil, 1, { 'npc:448', 'npc:327' } }, "
        "{ nil, 'cast', 'object:174794', nil, nil, { 'item:7207' } } } }",
    )
    slay, loot, cast = got[1], got[2], got[3]
    assert (slay.step, slay.ref, slay.nth, slay.count, slay.src) == (
        "slay",
        "npc:448",
        2,
        10,
        "eq",
    )
    assert list(slay.refs.values()) == ["npc:448", "npc:327"]  # the subject first
    assert (loot.ref, loot.nth) == (None, 1)
    assert list(loot.refs.values()) == ["npc:448", "npc:327"]
    assert (cast.step, cast.ref, cast.refs, cast.nth) == ("cast", "object:174794", None, None)
    assert wow.errors == []


# ---- the data contract (data.md "Links and steps", acceptance): the build's steps in the pack


def contract_world():
    """Quests whose things to do the old fields can express, and one they cannot."""
    from bastians_build.model import World

    w = World(client="forever", build="test", sources=[])
    w.add("zone", 1429, {"name": "Elwynn Forest"})
    w.add("npc", 1, {"name": "Kobold", "spawns": [[1429, 0.1, 0.1, "eq"]]})
    # with its height and the yards it roams: a place's details are the creature's own
    w.add("npc", 2, {"name": "Old Kobold", "spawns": [[1429, 0.2, 0.2, "classic", 31.0, 12.5]]})
    w.add("npc", 3, {"name": "Giver", "spawns": [[1429, 0.42, 0.65, "eq"]]})
    w.add("object", 10, {"name": "Chest", "spawns": [[1436, 0.3, 0.3, "classic"]]})
    w.add("object", 11, {"name": "Waterwall", "spawns": [[1429, 0.2857, 0.6139, "classic"]]})
    w.add("item", 20, {"name": "Dropped", "drops": [["npc:1", 40.0, False], ["npc:2", 5.0]]})
    w.add("item", 21, {"name": "In a chest", "drops": [["object:10", 100.0]]})
    w.add("item", 22, {"name": "Flask"})
    w.add("item", 23, {"name": "Sample", "ways": [["make", "item:22", None, "object:11"]]})
    quest = {"starts": ["npc:3"], "ends": ["npc:3"]}
    # Everything Quests' shape: numbered rows, its own spots with the bit within the kind
    w.add(
        "quest",
        1,
        quest
        | {
            "objectives": [["slay", "npc:1", 0], ["slay", "npc:2", 0], ["loot", "npc:2", 0]],
            "requiredItems": [[20, 4]],
            "spots": {1429: [[0.5, 0.5, "slay", 1], [0.6, 0.6, "loot", 1]]},
        },
    )
    # QuestieDB's shape: plain rows, no spots: the subjects' own places
    w.add(
        "quest",
        2,
        quest | {"objectives": [["slay", "npc:2"], ["object", "object:10"], ["loot", "item:21"]]},
    )
    # the client's areas beside a subject, and a spot nothing claims
    w.add(
        "quest",
        3,
        quest
        | {
            "objectives": [["slay", "npc:1"]],
            "spots": {1429: [[0.3, 0.3, "area", 1], [0.7, 0.7, "area", 2], [0.8, 0.8, "odd", 0]]},
        },
    )
    # what only the build knows: the handed flask is filled at the waterwall (item.ways)
    w.add("quest", 1861, quest | {"requiredItems": [[23, 1]], "gives": [[22, 1]]})
    return w


def boot_contract(wow: WowRuntime, tmp_path) -> None:
    from bastians_build.build import build
    from bastians_build.config import load_config

    result = build(contract_world(), load_config(), tmp_path)
    assert result.ok, result.problems
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in result.packs:
        if pack.pack.name in ("world", "quests", "items"):
            wow.execute(pack.path.read_text(encoding="utf-8"))
    wow.execute("Bastians.Deliver()")
    wow.run_frames(5)
    wow.execute('d = Bastians:GetService("data")')


def things(wow: WowRuntime, quest: int, old: bool) -> list[tuple]:
    """A quest's things to do as the addon answers them: from the pack's `steps`, or (`old`) from
    the same record without them, as an installed suite or a shape 1 pack reads it."""
    wow.execute(
        f"""local r = d:Get("quest", {quest})
        local copy = {{}}
        for k, v in pairs(r) do copy[k] = v end
        if {str(old).lower()} then copy.steps = nil end
        got = Bastians.Data.Steps.Of(copy, {{
          spawns = function(ref) return d:Spawns(ref) end,
          item = function(id) return d:Get("item", id) end,
          places = function(ref) return Bastians:Entity(ref):Locations() end,
        }})"""
    )
    out = []
    for step in list(wow.eval("got").values())[1:-1]:
        where = sorted(
            (p.map, p.x, p.y, p.ref, p.wz, p.r, p.src or "") for p in step.places.values()
        )
        refs = list(step.refs.values()) if step.refs else None
        via = list(step.via.values()) if step.via else None
        out.append((step.step, step.ref, refs, step.n, step.nth, step.count, step.how, via, where))
    return out


def test_the_packs_steps_are_what_the_old_fields_say_where_they_can_say_it(
    wow: WowRuntime, tmp_path
):
    """The build's resolver and the addon's reader of `objectives` and `spots` are two readers
    of one meaning: for a quest the old fields can express, a pack with `steps` answers the same
    things to do, subjects, numbers, counts, ways and places."""
    boot_contract(wow, tmp_path)
    for quest in (1, 2, 3):
        new, old = things(wow, quest, old=False), things(wow, quest, old=True)
        assert new == old, f"quest {quest}: {new} is not {old}"
    eq = things(wow, 1, old=False)
    assert [(s[0], s[1], s[2], s[4], s[5]) for s in eq] == [
        ("slay", "npc:1", ["npc:1", "npc:2"], 1, None),
        ("get", "item:20", None, 1, 4),
    ]
    assert eq[1][6:8] == ("loot", ["npc:1", "npc:2"])
    own = (None, None, None, "")  # no creature stands at the quest's own spot
    assert [s[8] for s in eq] == [[(1429, 0.5, 0.5, *own)], [(1429, 0.6, 0.6, *own)]]
    # where the creature itself stands, the place has its height, its roaming and its source
    assert things(wow, 2, old=False)[0][8] == [(1429, 0.2, 0.2, None, 31, 12.5, "classic")]
    assert [(s[0], s[3]) for s in things(wow, 3, old=False)] == [
        ("slay", None),
        ("reach", 1),
        ("reach", 2),
        ("reach", None),
    ]
    # the source of a step's own places is named by the build; the old reader says `data`
    things(wow, 1, old=False)
    assert wow.eval("got[2].src") == "eq"
    things(wow, 1, old=True)
    assert wow.eval("got[2].src") == "data"
    # what the old fields cannot say: a pack without `steps` knows no place for the sample
    assert things(wow, 1861, old=True) == [("get", "item:23", None, None, None, 1, None, None, [])]
    sample = things(wow, 1861, old=False)[0]
    assert sample[:8] == ("get", "item:23", None, None, None, 1, "make", ["item:22", "object:11"])
    assert sample[8] == [(1429, 0.2857, 0.6139, "object:11", None, None, "classic")]
    assert wow.eval("d:Get('quest', 1861).gives[1][1]") == 22
    assert wow.errors == []


def test_a_pack_of_a_newer_shape_is_not_loaded_and_says_so(wow: WowRuntime, tmp_path):
    """data.md "Old and new packs": a Data edition from after this suite left out something it
    reads; wrong quests would be worse than none, so the pack stays out with one note."""
    boot_contract(wow, tmp_path)
    assert wow.eval("Bastians.Data.packs.quests.shape") == wow.eval("Bastians.Data.SHAPE") == 2
    assert wow.eval("Bastians.Data.NewerNote()") is None
    wow.execute(
        """Bastians.Data.RegisterPack("future", { shape = 3, schema = { quest = { "name" } },
          quest = { [1] = "{ 'From the future' }" } })
        Bastians.Data.RegisterPack("fine", { schema = { thing = { "name" } }, thing = {} })"""
    )
    wow.advance(0.6)
    wow.run_frames(3)
    assert wow.eval("Bastians.Data.packs.future") is None
    assert wow.eval("Bastians.Data.loaded.future") is None
    assert wow.eval("Bastians.Data.packs.fine ~= nil") is True  # a pack without a shape is 1
    assert wow.eval("d:Get('quest', 1).steps ~= nil") is True  # the quests it had stay
    note = wow.eval("Bastians.Data.NewerNote()")
    assert note == "This Data edition needs a newer Bastian's suite: future."
    assert any(note in line for line in wow.chat)
    # the same pack in a shape this suite reads takes its place
    wow.execute(
        """Bastians.Data.RegisterPack("future", { shape = 2, schema = { thing2 = { "name" } },
          thing2 = {} })"""
    )
    assert wow.eval("Bastians.Data.NewerNote()") is None
    assert wow.errors == []
