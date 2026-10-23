"""Type-prefixed search: "npc wel" narrows to NPCs; Bastians.ParseSearch
and the `types` option of Bastians:Search."""

from harness import WowRuntime


def parse(core: WowRuntime, text: str):
    query, types = core.eval(f"Bastians.ParseSearch('{text}')")
    return query, (dict(types) if types is not None else None)


def test_parse_search_splits_a_leading_type_word(core: WowRuntime):
    assert parse(core, "npc wel") == ("wel", {"npc": True})
    assert parse(core, "  Quests  hogger ") == ("hogger", {"quest": True})
    assert parse(core, "herb peace") == ("peace", {"node": True})
    assert parse(core, "wel") == ("wel", None)
    assert parse(core, "npc") == ("npc", None)  # no space: a plain query
    assert parse(core, "gunther weller") == ("gunther weller", None)
    assert parse(core, "") == ("", None)


def test_parse_search_takes_the_type_word_last_too(core: WowRuntime):
    """ADR 0013 F: "coll quest" is "quest coll"."""
    assert parse(core, "coll quest") == ("coll", {"quest": True})
    assert parse(core, "wel npc") == ("wel", {"npc": True})
    assert parse(core, "gunther weller npcs") == ("gunther weller", {"npc": True})
    assert parse(core, "npc wel npc") == ("wel npc", {"npc": True})  # the first word wins
    assert parse(core, "big hog") == ("big hog", None)


def test_search_keeps_only_the_wanted_types(app: WowRuntime):
    app.execute(
        """
        local m = Bastians:GetModule('TestApp')
        Bastians:RegisterSearchProvider(m, { id = 'test.mixed', label = 'Mixed', priority = 10,
          search = function(query)
            return {
              { ref = 'npc:1', score = 0.9, label = 'Gunther Weller' },
              { ref = 'quest:2', score = 0.8, label = 'Wanted: Weller' },
              { ref = 'item:3', score = 0.7, label = 'Weller Ale' },
            }
          end })
        _G.got = nil
        Bastians:Search('wel', { limit = 10, types = { npc = true, item = true } }, function(results, done)
          if done then _G.got = results end
        end)
        """
    )
    app.run_frames(10)
    refs = [r.ref for r in app.eval("got").values()]
    assert refs == ["npc:1", "item:3"]
    app.execute(
        "_G.all = nil Bastians:Search('wel', { limit = 10 }, function(r, done) if done then _G.all = r end end)"
    )
    app.run_frames(10)
    assert [r.ref for r in app.eval("all").values()] == ["npc:1", "quest:2", "item:3"]
    assert app.errors == []
