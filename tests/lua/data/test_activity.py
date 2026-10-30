"""The activity facet of quests (ADR 0026, world-graph.md §10): the quest record as something a
character spends time on, one record and one facet."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    for pack in ("world", "quests"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    return wow


def test_a_quest_is_an_activity_with_its_places_needs_and_gains(wow: WowRuntime):
    boot(wow)
    a = wow.eval("Bastians:Entity('quest:176'):Facet('activity')")
    assert a.kind == "quest" and a.src == "forever"
    gives = [(g.kind, g.amount, g.id, g.choice) for g in a.gives.values()]
    assert ("copper", 150, None, None) in gives
    assert ("item", 1, 1185, True) in gives and ("item", 2, 2318, True) in gives
    assert not any(g[0] == "xp" for g in gives)  # the record has no XP: none, never 0
    assert a.needs.level == 5
    assert a.takes is None  # no source times quests yet
    kinds = {p.kind for p in a.places.values()}
    assert {"giver", "objective", "turnin"} <= kinds
    assert wow.eval("Bastians:Entity('quest:999999'):Facet('activity')") is None
    assert wow.eval("Bastians:Entity('npc:448'):Facet('activity')") is None  # quests only, so far


def test_prerequisites_are_quest_refs(wow: WowRuntime):
    boot(wow)
    found = wow.eval(
        """(function()
          local data = Bastians:GetService("data")
          for _, id in ipairs(data:Each("quest")) do
            local r = data:Get("quest", id)
            if r.preAny then return id, r.preAny[1] end
          end
        end)()"""
    )
    quest_id, pre = found
    a = wow.eval(f"Bastians:Entity('quest:{quest_id}'):Facet('activity')")
    assert list(a.needs.anyQuest.values()) == [f"quest:{pre}"]
