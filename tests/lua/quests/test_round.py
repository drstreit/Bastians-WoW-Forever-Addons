"""The quest round (route.md "Several stops", R26.4): the mock log's open quest 176 (spots in
Elwynn) and complete quest 62 (hand in at Marshal Dughan, npc:240) become stops, the hand-in of
176 after its own stop; without Route the round says what it needs."""

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
    assert set(by_id) == {"176:do", "176:in", "62:in"} and left == 0
    assert by_id["176:do"].ref == "quest:176" and by_id["176:do"].place.map == 0
    hand_in = by_id["176:in"]
    assert hand_in.ref == "npc:240" and list(hand_in.after.values()) == ["176:do"]
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
        "176:in" not in ids or "176:do" in ids
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
