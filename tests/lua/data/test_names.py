"""Data.Names (data.md "Retail data"): names the packs lack come from the client, the pack's own
names win, late answers invalidate the entity cache once, unknown stays nil."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    wow.execute("""
      Mock.questTitles[9001] = "The Late Title"
      Mock.unitNames[424242] = "Deputy Willem"
      Mock.lateItems[777] = { name = "Late Lantern", quality = 1, level = 1, class = "Miscellaneous", sell = 5, stack = 1, icon = 1 }
      _G.changes = {}
      Bastians:NewModule("NamesProbe", { addon = "Bastians_Core", OnEnable = function(self)
        self:On("BASTIANS_ENTITY_CHANGED", function(_, _, typ) changes[#changes + 1] = typ end)
      end })
    """)
    wow.run_frames(2)
    return wow


def test_pack_names_win_and_known_client_names_answer_at_once(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:Entity('quest:176'):Name()") == "The Fargodeep Mine"  # from the pack
    assert wow.eval("Bastians:Entity('npc:424242'):Name()") == "Deputy Willem"  # client, no record
    assert wow.eval("Bastians:Entity('item:6948'):Name()") == "Hearthstone"  # cached item
    assert wow.eval("Bastians:Entity('npc:999'):Name()") is None  # the client has no name either
    assert wow.eval("Bastians:Entity('zone:5'):Name()") is None  # zones are not asked
    assert wow.errors == []


def test_quest_and_item_names_arrive_with_the_load_events(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:Entity('quest:9001'):Name()") is None  # not loaded yet: requested
    assert wow.eval("Bastians:Entity('item:777'):Name()") is None
    assert wow.eval("Bastians.Data.Names.requested['quest:9001']") is True
    assert wow.eval("#Mock.questLoadRequests") == 1 and wow.eval("#Mock.itemLoadRequests") == 1
    wow.eval("Bastians:Entity('quest:9001'):Name()")  # asking again does not ask the client again
    assert wow.eval("#Mock.questLoadRequests") == 1
    wow.advance(0.5)  # the mock answers the load requests
    wow.run_frames(2)
    assert wow.eval("Bastians:Entity('quest:9001'):Name()") == "The Late Title"
    assert wow.eval("Bastians:Entity('item:777'):Name()") == "Late Lantern"
    changed = list(wow.eval("changes").values())
    assert changed.count("quest") == 1 and changed.count("item") == 1  # one coalesced invalidation
    assert wow.eval("Bastians.Data.Names.requested['quest:9001']") is None
    assert wow.errors == []


def test_unknown_after_a_failed_load_stays_nil_without_a_second_request(wow: WowRuntime):
    boot(wow)
    assert (
        wow.eval("Bastians:Entity('quest:9002'):Name()") is None
    )  # the client knows no such quest
    wow.advance(0.5)
    wow.run_frames(2)
    assert wow.eval("Bastians.Data.Names.cache['quest:9002']") is False
    assert wow.eval("Bastians:Entity('quest:9002'):Name()") is None
    assert wow.eval("#Mock.questLoadRequests") == 1
    assert wow.errors == []


def test_answered_names_are_stored_searched_and_known_after_a_reload(wow: WowRuntime):
    """R4: a name the client answers goes into
    BastiansDataDB.global.names; the search finds it, and the next session knows it without a
    client call; the store is capped."""
    boot(wow)
    wow.eval("Bastians:Entity('quest:9001'):Name()")
    wow.advance(0.5)
    wow.run_frames(2)
    assert wow.eval("Bastians:Entity('npc:424242'):Name()") == "Deputy Willem"
    hits = wow.eval("Bastians:GetService('data'):Find('quest', 'late', 10)")
    assert [(h.id, h.name, h.stored) for h in hits.values()] == [(9001, "The Late Title", True)]
    hits = wow.eval("Bastians:GetService('data'):Find('npc', 'willem', 10)")
    assert [h.id for h in hits.values()] == [424242]
    # pack names still win and are not doubled by a stored copy (no app names a pack here, so
    # the quests pack is loaded by hand)
    wow.execute("Bastians:GetService('data'):LoadPack('quests')")
    hits = wow.eval("Bastians:GetService('data'):Find('quest', 'fargodeep', 10)")
    assert [h.stored for h in hits.values()] == [None]
    assert wow.eval("BastiansDataDB.global.names.quest[9001]") == "The Late Title"
    assert wow.eval("#BastiansDataDB.global.names.order") == 2  # the quest and the NPC
    # the next session: no client answer any more, the store knows the name at once
    fresh = wow.reload()
    fresh.run_frames(5)
    assert fresh.eval("Mock.questTitles[9001]") is None
    assert fresh.eval("Bastians:Entity('quest:9001'):Name()") == "The Late Title"
    assert fresh.eval("#Mock.questLoadRequests") == 0
    assert fresh.eval("Bastians:Entity('npc:424242'):Name()") == "Deputy Willem"
    hits = fresh.eval("Bastians:GetService('data'):Find('quest', 'late title', 10)")
    assert [h.id for h in hits.values()] == [9001]
    # the cap: past it the oldest fifth goes
    fresh.execute("""
      Bastians.Data.Names.STORE_CAP = 10
      for i = 1, 12 do Mock.unitNames[500000 + i] = "Guard " .. i; Bastians:Entity("npc:" .. (500000 + i)):Name() end
    """)
    assert fresh.eval("#BastiansDataDB.global.names.order") <= 10
    assert fresh.eval("BastiansDataDB.global.names.quest[9001]") is None  # the oldest went
    assert fresh.eval("BastiansDataDB.global.names.npc[500012]") == "Guard 12"
    assert fresh.errors == []
