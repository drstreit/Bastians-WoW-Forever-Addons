"""The quest round (route.md "Several stops", R26.4; one stop per open step since ADR 0069): the
mock log's open quest 176 (spots in Elwynn) and complete quest 62 (hand in at Marshal Dughan,
npc:240) become stops, the hand-in of 176 after its own stop; without Route the round says what
it needs."""

from harness import WowRuntime

CORE, DATA, QUESTS, ROUTE = "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Route"
ROUND = "Bastians:GetModule('Quests').Round"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.fire("QUEST_LOG_UPDATE")
    wow.run_frames(5)
    return wow


def test_the_open_quests_and_hand_ins_become_stops(wow: WowRuntime):
    boot(wow)
    stops, left = wow.eval(f"{ROUND}.Stops()")
    by_id = {s.id: s for s in stops.values()}
    # 176's thing to do is the second step of its facet (take, get the claw, hand in)
    assert set(by_id) == {"176:2", "176:in", "62:in"} and left == 0
    assert by_id["176:2"].ref == "quest:176" and by_id["176:2"].place.map == 0
    hand_in = by_id["176:in"]
    assert hand_in.ref == "npc:240" and list(hand_in.after.values()) == ["176:2"]
    assert hand_in.name == "The Fargodeep Mine (hand in)"
    assert by_id["62:in"].after is None  # complete: only the hand-in
    assert wow.errors == []


def test_the_round_asks_for_route(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{ROUND}.Start()") is False
    assert "needs Bastian's Route" in wow.chat[-1]
    wow.execute(f"{ROUND}.MAX = 2")
    stops, _ = wow.eval(f"{ROUND}.Stops()")
    ids = [s.id for s in stops.values()]
    assert len(ids) == 2 and (
        "176:in" not in ids or "176:2" in ids
    )  # a hand-in only with its quest


def test_with_route_the_stops_go_to_the_route_service(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, ROUTE)
    wow.execute(
        """GOT = nil
        local real = Bastians:GetService('route')
        real.Tour = function(_, stops, name) GOT = { n = #stops, name = name } return true end"""
    )
    assert wow.eval(f"{ROUND}.Start()") is True
    assert wow.eval("GOT.n") == 3 and wow.eval("GOT.name") == "Quest round"
    wow.slash("/bq round")
    assert wow.errors == []


# The fixture map 1429 is 400 yards wide: 0.05 of it are 20 yards, 0.5 are 200.
ROUND_STEPS = """
AT = { continent = 0, wx = -60, wy = 32 }
function facet(state, todo, handin, waypoint)
  local steps = { state = state, waypoint = waypoint, { step = "take", done = true } }
  for _, s in ipairs(todo) do steps[#steps + 1] = s end
  steps[#steps + 1] = handin or { step = "handin", ref = "npc:240",
    places = { { map = 1429, x = 0.42, y = 0.65 } } }
  return steps
end
function stops(steps)
  local got = Bastians:GetModule('Quests').Round.QuestStops(7, "Kobolds", steps, AT)
  if not got then return nil end
  local out = {}
  for _, st in ipairs(got) do
    out[#out + 1] = st.id .. "=" .. st.name .. (st.after and (" after " .. table.concat(st.after, ",")) or "")
  end
  return table.concat(out, " | ")
end
MINERS = { step = "slay", open = true, text = "Kobold Miner slain 2/8",
  places = { { map = 1429, x = 0.95, y = 0.95 }, { map = 1429, x = 0.2, y = 0.2 } } }
CANDLES = { step = "get", open = true, text = "Candles 0/5", places = { { map = 1429, x = 0.25, y = 0.2 } } }
DUST = { step = "get", open = true, text = "Gold Dust 0/3", places = { { map = 1429, x = 0.7, y = 0.2 } } }
DONE = { step = "slay", done = true, places = { { map = 1429, x = 0.9, y = 0.9 } } }
LOST = { step = "do", open = true, how = "unknown" }
"""


def test_a_quest_gives_one_stop_per_open_step(wow: WowRuntime):
    """(ADR 0069): one stop per open step at its nearest place; steps whose
    nearest places lie within 100 yards share a stop; the hand-in after all of them."""
    boot(wow)
    wow.execute(ROUND_STEPS)
    # the miners' camp and the candles 20 yards from it are one stop, the dust 200 yards on another
    assert wow.eval("stops(facet('active', { MINERS, CANDLES, DUST, DONE }))") == (
        "7:2=Kobolds: Kobold Miner slain 2/8 | 7:4=Kobolds: Gold Dust 0/3 | "
        "7:in=Kobolds (hand in) after 7:2,7:4"
    )
    wow.execute(f"{ROUND}.SHARE_YARDS = 10")
    assert wow.eval("stops(facet('active', { MINERS, CANDLES }))").startswith(
        "7:2=Kobolds: Kobold Miner slain 2/8 | 7:3=Kobolds: Candles 0/5 | 7:in="
    )
    wow.execute(f"{ROUND}.SHARE_YARDS = 100")
    # a step nobody can place beside one that has a place: the placed one is the stop
    assert wow.eval("stops(facet('active', { LOST, DUST }))") == (
        "7:3=Kobolds: Gold Dust 0/3 | 7:in=Kobolds (hand in) after 7:3"
    )
    # no step has a place: the client's place for the quest, else the quest is left out
    waypoint = "{ map = 1429, x = 0.3, y = 0.3, src = 'client' }"
    assert wow.eval(f"stops(facet('active', {{ LOST }}, nil, {waypoint}))") == (
        "7:do=Kobolds | 7:in=Kobolds (hand in) after 7:do"
    )
    assert wow.eval("stops(facet('active', { LOST }))") is None
    # complete, and a delivery (nothing to do: the hand-in is open): the hand-in alone
    assert wow.eval("stops(facet('complete', { MINERS }))") == "7:in=Kobolds (hand in)"
    delivery = "{ step = 'handin', open = true, places = { { map = 1429, x = 0.1, y = 0.1 } } }"
    assert wow.eval(f"stops(facet('active', {{}}, {delivery}))") == "7:in=Kobolds (hand in)"
    # a hand-in nobody can place: the things to do stay, a complete quest is left out
    nowhere = "{ step = 'handin', places = {} }"
    assert (
        wow.eval(f"stops(facet('active', {{ DUST }}, {nowhere}))") == "7:2=Kobolds: Gold Dust 0/3"
    )
    assert wow.eval(f"stops(facet('complete', {{}}, {nowhere}))") is None
    assert wow.errors == []


def test_a_hand_in_goes_only_with_all_of_its_quests_stops(wow: WowRuntime):
    """More stops than the round holds: the nearest are kept, and a hand-in whose quest lost a
    stop to the limit is left out."""
    boot(wow)
    wow.execute(
        """
        local q = Bastians:GetModule('Quests').Logic.quest(176)
        q.objectives = { { 'slay', 'npc:448', 0 }, { 'slay', 'npc:234', 1 } }
        q.requiredItems = nil
        q.spots = { [1429] = { { 0.4, 0.7, 'slay', 1 }, { 0.9, 0.1, 'slay', 2 } } }
        q.steps = nil -- the record is rewritten in the old fields: the build's steps go with it
        Mock.questLog[2].objectives = {
          { text = 'Hogger slain', type = 'monster', finished = false, numFulfilled = 0, numRequired = 1 },
          { text = 'Gryan slain', type = 'monster', finished = false, numFulfilled = 0, numRequired = 1 },
        }
        Mock.questLog[3].complete = false -- 62 is a delivery now: its hand-in alone
        """
    )
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.run_frames(5)
    stops, left = wow.eval(f"{ROUND}.Stops()")
    ids = [s.id for s in stops.values()]
    assert set(ids) == {"176:2", "176:3", "176:in", "62:in"} and left == 0
    assert ids.index("176:in") > max(ids.index("176:2"), ids.index("176:3"))
    by_id = {s.id: s for s in stops.values()}
    assert by_id["176:2"].name == "The Fargodeep Mine: Hogger slain"
    assert list(by_id["176:in"].after.values()) == ["176:2", "176:3"]
    # room for three: the far stop of 176 is cut, and with it 176's hand-in
    wow.execute(f"{ROUND}.MAX = 3")
    stops, _ = wow.eval(f"{ROUND}.Stops()")
    ids = [s.id for s in stops.values()]
    assert "176:in" not in ids and "62:in" in ids and "176:2" in ids
    assert wow.errors == []
