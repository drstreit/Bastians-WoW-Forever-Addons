"""Registries and services (B2.5): entities, actions, layers, sections, search, services, ownership."""

from harness import WowRuntime

NEW_MODULE = "local m = Bastians:NewModule(%r, { addon = 'Bastians_TestApp' })"


def events(app: WowRuntime, name: str = "changes") -> list[str]:
    return list(app.g[name].values())


def watch_registry(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Watcher"
        + """
        changes = {}
        m:On("BASTIANS_REGISTRY_CHANGED", function(_, _, kind, id, added)
          changes[#changes + 1] = kind .. ":" .. tostring(id) .. ":" .. tostring(added)
        end)
        """
    )


def test_entity_refs_parse_and_build(app: WowRuntime):
    assert app.eval("Bastians.Entity.Parse('npc:448')") == ("npc", 448)
    assert app.eval("Bastians.Entity.Parse('node:herb-2')") == ("node", "herb-2")
    assert app.eval("Bastians.Entity.Parse('nonsense')") is None
    assert app.eval("Bastians.Entity.Make('quest', 176)") == "quest:176"


def test_entity_providers_answer_in_priority_order_and_merge_locations(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Prov"
        + """
        answer = "Hogger"
        Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
          name = function(id) return id == 448 and answer or nil end,
          locations = function(id) return { { map = 1429, x = 0.27, y = 0.86, src = "data" } } end })
        local bridge = Bastians:NewModule("Bridge", { addon = "Bastians_TestApp" })
        Bastians:RegisterEntityType(bridge, { type = "npc", priority = 50,
          name = function(id) return "Bridge name " .. id end,
          summary = function(id) return "from bridge" end,
          locations = function(id) return { { map = 1429, x = 0.3, y = 0.8, src = "questie" } } end })
        """
    )
    assert app.eval("Bastians:Entity('npc:448'):Name()") == "Hogger"
    assert app.eval("Bastians:Entity('npc:449'):Name()") == "Bridge name 449"  # first non-nil wins
    assert app.eval("Bastians:Entity('npc:448'):Summary()") == "from bridge"
    assert app.eval("Bastians:Entity('npc:1'):Icon()") is None
    srcs = [p.src for p in app.eval("Bastians:Entity('npc:448'):Locations()").values()]
    assert srcs == ["data", "questie"]
    assert (
        app.eval("Bastians:Entity('npc:448') == Bastians:Entity('npc:448')") is True
    )  # facade cached
    assert app.eval("Bastians.Entity('npc:448'):Name()") == "Hogger"  # dot call works too


def test_entity_answers_are_cached_until_invalidated(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Prov"
        + """
        answer = nil
        invalidations = {}
        m:On("BASTIANS_ENTITY_CHANGED", function(_, _, t) invalidations[#invalidations + 1] = tostring(t) end)
        Bastians:RegisterEntityType(m, { type = "item", name = function() return answer end })
        """
    )
    assert app.eval("Bastians:Entity('item:1'):Name()") is None
    app.execute("answer = 'Linen'")
    assert (
        app.eval("Bastians:Entity('item:1'):Name()") is None
    )  # the nil stays cached in this generation
    app.execute("Bastians:Fire('BASTIANS_DATA_LOADED', 'items')")
    assert app.eval("Bastians:Entity('item:1'):Name()") == "Linen"
    app.execute("answer = 'Wool'; Bastians:InvalidateEntities('item')")
    assert app.eval("Bastians:Entity('item:1'):Name()") == "Wool"
    assert events(app, "invalidations") == [
        "item",
        "nil",
        "item",
    ]  # register, data loaded, explicit


def test_actions_filter_by_type_and_when_at_call_time(app: WowRuntime):
    watch_registry(app)
    app.execute(
        NEW_MODULE % "Acts"
        + """
        allowed = false
        ran = {}
        Bastians:RegisterAction(m, { id = "map.show", label = "Show on map", types = { "npc", "quest" }, order = 10,
          when = function(ref, ctx) return allowed end, run = function(ref, ctx) ran[#ran + 1] = ref .. "@" .. ctx.source end })
        Bastians:RegisterAction(m, { id = "browser.open", label = "Open", types = "*", order = 20,
          run = function(ref) ran[#ran + 1] = "open " .. ref end })
        Bastians:RegisterAction(m, { id = "gold.prices", label = "Prices", types = { "item" }, order = 50,
          run = function() end })
        """
    )
    ids = [a.id for a in app.eval("Bastians:GetActions('npc:448', { source = 'map' })").values()]
    assert ids == ["browser.open"]
    app.execute("allowed = true")
    ids = [a.id for a in app.eval("Bastians:GetActions('npc:448', { source = 'map' })").values()]
    assert ids == ["map.show", "browser.open"]
    assert app.eval("Bastians:GetPrimaryAction('npc:448', {}).id") == "map.show"
    assert app.eval("Bastians:GetPrimaryAction('item:5', {}).id") == "browser.open"
    assert app.eval("Bastians:RunAction('map.show', 'npc:448', { source = 'browser' })") is True
    assert app.eval("Bastians:RunAction('nope', 'npc:448', {})") is False
    assert events(app)[-1] == "action:gold.prices:true"
    assert list(app.g.ran.values()) == ["npc:448@browser"]


def test_map_layers_are_listed_and_queried_within_their_levels(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Lay"
        + """
        Bastians:RegisterMapLayer(m, { id = "quests.givers", label = "Quest givers", minLevel = 2,
          query = function(view) return { { ref = "npc:448", wx = view.x1, wy = view.y1 } } end })
        Bastians:RegisterMapLayer(m, { id = "gold.spots", label = "Farm spots", defaultOn = false,
          query = function() error("layer boom") end })
        """
    )
    layers = app.eval("Bastians:GetMapLayers()")
    assert [layer.id for layer in layers.values()] == ["gold.spots", "quests.givers"]
    assert layers[1].defaultOn is False and layers[2].defaultOn is True
    view = "{ continent = 0, x1 = 10, y1 = 20, x2 = 30, y2 = 40, level = %d }"
    assert len(app.eval(f"Bastians:QueryLayer('quests.givers', {view % 1})")) == 0  # below minLevel
    pins = app.eval(f"Bastians:QueryLayer('quests.givers', {view % 3})")
    assert (pins[1].ref, pins[1].wx) == ("npc:448", 10)
    assert len(app.eval(f"Bastians:QueryLayer('gold.spots', {view % 3})")) == 0  # error isolated
    assert len(app.eval(f"Bastians:QueryLayer('missing', {view % 3})")) == 0
    assert app.errors == []


def test_detail_sections_cache_and_invalidate(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Sec"
        + """
        builds = 0
        Bastians:RegisterDetailSection(m, { id = "quests.starts", title = "Starts quests", types = { "npc" },
          order = 20, invalidateOn = { "BASTIANS_QUESTS_CHANGED" },
          build = function(ref) builds = builds + 1; return { { text = "Quest A", ref = "quest:1" }, { text = "Quest B" }, { text = "Quest C" } } end,
          tooltip = { max = 2 } })
        Bastians:RegisterDetailSection(m, { id = "data.overview", title = "Overview", types = { "npc", "item" },
          order = 10, build = function(ref) return { { text = "Level 11", value = 1100, valueKind = "money" } } end })
        Bastians:RegisterDetailSection(m, { id = "empty", title = "Nothing", types = "*", order = 1,
          build = function() return {} end })
        """
    )
    sections = app.eval("Bastians:GetDetailSections('npc:448')")
    assert [s.id for s in sections.values()] == [
        "data.overview",
        "quests.starts",
    ]  # empty hidden, by order
    assert sections[2].rows[1].ref == "quest:1"
    app.eval("Bastians:GetDetailSections('npc:448')")
    assert app.g.builds == 1  # cached
    app.execute("Bastians:Fire('BASTIANS_ENTITY_CHANGED', 'item')")
    app.eval("Bastians:GetDetailSections('npc:448')")
    assert app.g.builds == 1  # another type: untouched
    app.execute("Bastians:Fire('BASTIANS_QUESTS_CHANGED')")
    app.eval("Bastians:GetDetailSections('npc:448')")
    assert app.g.builds == 2
    app.execute("Bastians:Fire('BASTIANS_DATA_LOADED', 'world')")
    app.eval("Bastians:GetDetailSections('npc:448')")
    assert app.g.builds == 3
    tips = app.eval("Bastians:GetTooltipRows('npc:448')")
    assert [t.text for t in tips.values()] == [
        "Quest A",
        "Quest B",
    ]  # capped at max 2, only tooltip sections
    assert app.eval("#Bastians:GetTooltipRows('item:2589')") == 0


def test_search_merges_ranks_and_reports_progress(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Srch"
        + """
        calls = {}
        Bastians:RegisterSearchProvider(m, { id = "data.names", label = "World database", priority = 100,
          search = function(q, limit, yield)
            local out = {}
            for i = 1, 3 do yield(); out[#out + 1] = { ref = "npc:" .. i, label = "Hog " .. i, score = 0.5 + i / 10 } end
            out[#out + 1] = { ref = "quest:9", label = "Hogger quest", score = 0.4 }
            return out
          end })
        Bastians:RegisterSearchProvider(m, { id = "quests.text", label = "Quest text", priority = 50,
          search = function(q) return { { ref = "quest:9", label = "Hogger quest", score = 0.9 } } end })
        handle = Bastians:Search("  HOGG ", { limit = 10 }, function(results, done)
          local ids = {}
          for _, r in ipairs(results) do ids[#ids + 1] = r.ref end
          calls[#calls + 1] = table.concat(ids, ",") .. (done and " done" or "")
        end)
        """
    )
    app.run_frames(20)
    calls = list(app.g.calls.values())
    assert calls[-1].endswith(" done")
    # quest:9 keeps the higher-ranked copy (0.9*1.05) and sorts first; npc:3 (0.8*1.1) next
    assert calls[-1] == "quest:9,npc:3,npc:2,npc:1 done"
    assert calls[0] == "npc:3,npc:2,npc:1,quest:9"  # after the first provider only
    app.execute(
        "Bastians:Search('', {}, function(results, done) emptyDone = done and #results end)"
    )
    assert app.g.emptyDone == 0


def test_a_new_search_cancels_the_previous_one(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Srch"
        + """
        Bastians:RegisterSearchProvider(m, { id = "slow", label = "Slow", search = function(q, limit, yield)
          for i = 1, 5 do yield() end
          return { { ref = "npc:1", label = q, score = 1 } }
        end })
        first, second = {}, {}
        Bastians:Search("one", {}, function(results, done) first[#first + 1] = done end)
        Bastians:Search("two", {}, function(results, done) second[#second + 1] = done end)
        """
    )
    app.run_frames(30)
    assert len(app.g.first) == 0
    assert list(app.g.second.values())[-1] is True


def test_services_pick_the_highest_priority_provider(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Gold"
        + """
        changes = {}
        local watcher = Bastians:NewModule("Watcher", { addon = "Bastians_TestApp" })
        watcher:On("BASTIANS_SERVICE_CHANGED", function(_, _, name) changes[#changes + 1] = name end)
        Bastians:ProvideService(m, "prices", { Price = function() return "gold" end }, { priority = 100 })
        market = Bastians:NewModule("Market", { addon = "Bastians_TestApp" })
        Bastians:ProvideService(market, "prices", { Price = function() return "market" end }, { priority = 10 })
        """
    )
    assert app.eval("Bastians:GetService('prices').Price()") == "gold"
    app.execute("Bastians:GetModule('Gold'):Disable()")
    assert app.eval("Bastians:GetService('prices').Price()") == "market"
    app.execute("market:Disable()")
    assert app.eval("Bastians:GetService('prices')") is None
    assert app.eval("Bastians:GetService('travel')") is None
    assert events(app) == ["prices", "prices", "prices"]
    try:
        app.execute("Bastians:ProvideService(market, 'weather', {})")
    except Exception as exc:
        assert "service table" in str(exc)
    else:
        raise AssertionError("unknown service name must raise")


def test_disabling_a_module_removes_everything_it_registered(app: WowRuntime):
    """core.md acceptance 2."""
    watch_registry(app)
    app.execute(
        NEW_MODULE % "Full"
        + """
        Bastians:RegisterEntityType(m, { type = "spot", name = function() return "Spot" end })
        Bastians:RegisterAction(m, { id = "gold.farm", label = "Farm", types = "*", run = function() end })
        Bastians:RegisterMapLayer(m, { id = "gold.farmspots", label = "Farm spots", query = function() return {} end })
        Bastians:RegisterDetailSection(m, { id = "gold.price", title = "Price", types = "*", build = function() return { { text = "x" } } end })
        Bastians:RegisterSearchProvider(m, { id = "gold.strategies", label = "Strategies", search = function() return {} end })
        Bastians:ProvideService(m, "prices", { Price = function() end })
        """
    )
    assert app.eval("Bastians:Entity('spot:1'):Name()") == "Spot"
    assert len(app.eval("Bastians:GetActions('spot:1', {})")) == 1
    assert app.eval("Bastians:GetService('prices')") is not None
    app.execute("Bastians:GetModule('Full'):Disable()")
    assert app.eval("Bastians:HasEntityType('spot')") is False
    assert app.eval("Bastians:Entity('spot:1'):Name()") is None
    assert len(app.eval("Bastians:GetActions('spot:1', {})")) == 0
    assert app.eval("Bastians:GetMapLayer('gold.farmspots')") is None
    assert len(app.eval("Bastians:GetDetailSections('spot:1')")) == 0
    assert app.eval("Bastians:GetService('prices')") is None
    removed = [c for c in events(app) if c.endswith(":false")]
    assert sorted(removed) == sorted(
        [
            "entity:spot:false",
            "action:gold.farm:false",
            "layer:gold.farmspots:false",
            "section:gold.price:false",
            "search:gold.strategies:false",
        ]
    )
    assert app.errors == []


def test_views_register_sort_render_and_open_in_the_views_host(app: WowRuntime):
    """ADR 0012: views are a Core registry, the host is the `views` service (core-contracts §7b)."""
    watch_registry(app)
    app.execute(
        NEW_MODULE % "ViewApp"
        + """
        rendered = {}
        Bastians:RegisterView(m, { id = "test.b", title = "B", group = "Test", order = 20,
          render = function(host, args) rendered[#rendered + 1] = "b:" .. tostring(args.x) end })
        Bastians:RegisterView(m, { id = "test.a", title = "A", group = "Test", order = 10,
          render = function(host) host:SetRows({ { text = "row" } }) end })
        Bastians:RegisterView(m, { id = "test.boom", title = "Boom", group = "Test",
          render = function() error("boom") end })
        viewApp = m
        """
    )
    assert [v.id for v in app.eval("Bastians:GetViews()").values()] == [
        "test.a",
        "test.b",
        "test.boom",
    ]
    assert "view:test.a:true" in events(app)
    assert app.eval("Bastians:ShowView('test.a')") is False  # no host yet
    app.execute(
        NEW_MODULE % "Host"
        + """
        shown = {}
        Bastians:ProvideService(m, "views", {
          Show = function(self, id, args)
            local host = { args = args, SetRows = function(h, rows) h.rows = rows end }
            shown[#shown + 1] = id .. ":" .. tostring(Bastians:RenderView(id, host))
          end,
        }, { priority = 100 })
        """
    )
    assert app.eval("Bastians:ShowView('test.b', { x = 7 })") is True
    assert app.eval("Bastians:ShowView('test.missing')") is False
    assert app.eval("Bastians:ShowView('test.boom')") is True
    assert list(app.eval("shown").values()) == ["test.b:true", "test.boom:false"]  # error guarded
    assert list(app.eval("rendered").values()) == ["b:7"]
    app.execute("viewApp:Disable()")
    assert app.eval("#Bastians:GetViews()") == 0 and "view:test.a:false" in events(app)


def test_worth_providers_answer_by_type_and_cache_until_invalidated(app: WowRuntime):
    """§4 (C3): RegisterWorth, Entity:Worth() cached per generation, dropped by the provider's
    invalidateOn messages and by an entity invalidation; the card carries the line."""
    app.execute(
        NEW_MODULE % "Worthy"
        + """
        builds = 0
        Bastians:RegisterWorth(m, { types = { "npc" }, invalidateOn = { "TEST_PRICES" },
          worth = function(ref) builds = builds + 1; return { text = "1s per kill " .. builds, copper = 100 } end })
        Bastians:RegisterWorth(m, { types = { "npc" }, priority = 10,
          worth = function(ref) return { text = "never, lower priority" } end })
        Bastians:RegisterWorth(m, { types = { "item" }, worth = function(ref) return nil end })
        """
    )
    assert app.eval("Bastians:Entity('npc:448'):Worth().text") == "1s per kill 1"
    assert app.eval("Bastians:Entity('npc:448'):Worth().text") == "1s per kill 1"  # cached
    assert app.g.builds == 1
    assert app.eval("Bastians:Entity('item:1'):Worth()") is None  # a nil answer, cached too
    assert app.eval("Bastians:Entity('quest:1'):Worth()") is None  # no provider for the type
    assert (
        app.eval("Bastians:HasWorth('npc')") is True
        and app.eval("Bastians:HasWorth('quest')") is False
    )
    app.execute("Bastians:Fire('TEST_PRICES')")
    assert app.eval("Bastians:Entity('npc:448'):Worth().text") == "1s per kill 2"
    app.execute("Bastians:InvalidateEntities('npc')")
    assert app.eval("Bastians:Entity('npc:448'):Worth().text") == "1s per kill 3"
    app.execute("Bastians:InvalidateWorth()")
    assert app.eval("Bastians:Entity('npc:448'):Worth().text") == "1s per kill 4"
    assert app.eval("Bastians.UI.Card('npc:448', { source = 'test' }).worth.copper") == 100
    app.execute("Bastians:GetModule('Worthy'):Disable()")
    assert app.eval("Bastians:Entity('npc:448'):Worth()") is None
    assert app.errors == []


def test_location_filters_narrow_locations_and_all_locations_keeps_everything(app: WowRuntime):
    """R7 (22.10.2026): an app that knows which places matter now registers a location filter
    for a type; Locations() goes through it, AllLocations() does not; a filter that returns
    nothing usable leaves the list alone; the filter goes with its module."""
    app.execute(
        NEW_MODULE % "Places"
        + """
        Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
          locations = function(id) return {
            { map = 1429, x = 0.1, y = 0.1, kind = "a" }, { map = 1429, x = 0.2, y = 0.2, kind = "b" } } end })
        Bastians:RegisterLocationFilter(m, { id = "test.b", types = { "npc" },
          filter = function(ref, points)
            local out = {}
            for _, p in ipairs(points) do if p.kind == "b" then out[#out + 1] = p end end
            return out
          end })
        placesMod = m
        """
    )
    assert [p.kind for p in app.eval("Bastians:Entity('npc:7'):Locations()").values()] == ["b"]
    assert [p.kind for p in app.eval("Bastians:Entity('npc:7'):AllLocations()").values()] == [
        "a",
        "b",
    ]
    assert [p.kind for p in app.eval("Bastians:Entity('item:7'):Locations()").values()] == []
    app.execute("placesMod:Disable()")
    assert app.eval("#Bastians:Entity('npc:7'):Locations()") == 0  # the provider went with it
    assert app.errors == []


def test_detail_section_cache_keeps_the_newest_refs_only(app: WowRuntime):
    """R10 (22.10.2026): a session visits hundreds of pages; a section keeps the rows of the
    newest SECTION_CACHE_MAX refs, the oldest go, the ones at hand stay cached."""
    app.execute(
        NEW_MODULE % "Cap"
        + """
        builds = 0
        Bastians:RegisterDetailSection(m, { id = "test.cap", title = "Cap", types = { "npc" },
          build = function(ref) builds = builds + 1 return { { text = "row of " .. ref } } end })
        Bastians.SECTION_CACHE_MAX = 5
        for i = 1, 8 do Bastians:GetDetailSections("npc:" .. i) end
        """
    )
    assert app.eval("builds") == 8
    app.execute("Bastians:GetDetailSections('npc:8'); Bastians:GetDetailSections('npc:4')")
    assert app.eval("builds") == 8  # the newest five (4 to 8) are cached
    app.execute("Bastians:GetDetailSections('npc:1')")
    assert app.eval("builds") == 9  # the oldest went and is built again
    app.execute("Bastians.SECTION_CACHE_MAX = 64")
    assert app.errors == []
