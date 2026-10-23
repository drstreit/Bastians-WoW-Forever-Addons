"""The Data loader and the pack's client (data.md, ADR 0010): a pack built for the other client
loads but is flagged. The fixture packs are built for forever, so the retail run is the foreign case."""

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    return wow


def test_pack_from_the_other_client_loads_but_is_flagged(wow: WowRuntime):
    boot(wow)
    meta = wow.eval("Bastians:GetService('data'):Meta()")
    assert meta.client == wow.client
    assert meta.packs.world.client == "forever"
    foreign = dict(meta.foreign)
    note = wow.eval("Bastians:GetModule('Data').options[1].text()")
    warns = [e.text for e in wow.eval("Bastians:GetLog()").values() if e.level == "warn"]
    if wow.client == "forever":
        assert foreign == {}
        assert note == "Packs are built for this client."
        assert not any("was built for" in w for w in warns)
    else:
        assert foreign["world"] == "forever" and foreign["quests"] == "forever"
        assert note.startswith(
            "Packs built for another client: items (forever), quests (forever), world (forever)."
        )
        assert any(w == "pack world was built for forever, this client is retail" for w in warns)
    # the data is there either way: the loader never drops a pack over its client
    assert wow.eval("Bastians:GetService('data'):Get('npc', 448).name") == "Hogger"


def test_records_are_compiled_on_first_access_and_table_rows_still_load(wow: WowRuntime):
    """Format A (data.md): a pack row is the record's literal as a string; a table row (an older
    pack, a test) is read as is, and a search over such a pack decodes the names itself."""
    boot(wow)
    assert wow.eval("type(Bastians.Data.packs.world.npc[448])") == "string"
    assert wow.eval("Bastians.Data.packs.world.names.npc[448]") == "Hogger"
    hits = wow.eval("Bastians:GetService('data'):Find('npc', 'hogg', 5)")
    assert [h.name for h in hits.values()] == ["Hogger"]
    wow.execute("""
      Bastians.Data.RegisterPack("items", { schema = { item = { "name", "quality" } },
        item = { [1] = { "Table Row", 2 }, [2] = "{ \\"String Row\\", 3 }", [3] = "not a table" } })
    """)
    data = "Bastians:GetService('data')"
    assert wow.eval(f"{data}:Get('item', 1).quality") == 2
    assert wow.eval(f"{data}:Get('item', 2).name") == "String Row"
    assert wow.eval(f"{data}:Get('item', 3)") is None  # logged, never raised
    assert any("pack record item:3" in e.text for e in wow.eval("Bastians:GetLog()").values())
    names = sorted(h.name for h in wow.eval(f"{data}:Find('item', 'row', 5)").values())
    assert names == ["String Row", "Table Row"]  # no names table: decoded record by record
    assert wow.errors == []
