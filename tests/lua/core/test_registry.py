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
    assert app.eval("Bastians.Entity.Parse('gatherplus.route:7')") == ("gatherplus.route", 7)
    assert app.eval("Bastians.Entity.Parse('entrance:36-1')") == ("entrance", "36-1")
    assert app.eval("Bastians.Entity.Parse('npc.:1')") is None
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


def test_places_are_world_positions_derived_from_locations(app: WowRuntime):
    """ADR 0026, W5: Places() converts the locations through Coords.ToWorld and keeps the map
    fractions for drawing; a map without a transform keeps ui, x, y and has no world position."""
    app.execute(
        NEW_MODULE % "Prov"
        + """
        Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
          locations = function(id) return {
            { map = 1429, x = 0.25, y = 0.5, src = "classic", wz = 56.1, kind = "spawn" },
            { map = 999, x = 0.4, y = 0.6, src = "questie" },
          } end })
        Bastians:RegisterLocationFilter(m, { id = "first", types = { "npc" },
          filter = function(ref, points) return { points[1] } end })
        """
    )
    places = list(app.eval("Bastians:Entity('npc:448'):Places()").values())
    assert len(places) == 1
    p = places[0]
    assert (p.map, p.wx, p.wy, p.wz) == (0, 0, 100, 56.1)
    assert (p.ui, p.x, p.y, p.src, p.kind) == (1429, 0.25, 0.5, "classic", "spawn")
    every = list(app.eval("Bastians:Entity('npc:448'):AllPlaces()").values())
    assert len(every) == 2
    unplaced = every[1]
    assert (unplaced.map, unplaced.wx, unplaced.wy, unplaced.wz) == (None, None, None, None)
    assert (unplaced.ui, unplaced.x, unplaced.y) == (999, 0.4, 0.6)


def test_places_are_cached_until_the_entities_are_invalidated(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Prov"
        + """
        where = 0.25
        Bastians:RegisterEntityType(m, { type = "npc", priority = 100,
          locations = function(id) return { { map = 1429, x = where, y = 0.5, src = "data" } } end })
        """
    )
    assert (
        app.eval("Bastians:Entity('npc:448'):Places() == Bastians:Entity('npc:448'):Places()")
        is True
    )
    app.execute("where = 0.5; Bastians:InvalidateEntities('npc')")
    assert app.eval("Bastians:Entity('npc:448'):Places()[1].x") == 0.5
    assert app.eval("Bastians:Entity('npc:1'):Places()[1].wx") == 0


def test_facets_answer_by_priority_and_type_and_cache_per_generation(app: WowRuntime):
    """ADR 0026: RegisterFacet; the first table answer by priority wins, nil passes on."""
    watch_registry(app)
    app.execute(
        NEW_MODULE % "Prov"
        + """
        calls = 0
        Bastians:RegisterFacet(m, { facet = "poi", types = { "npc" }, priority = 100,
          invalidateOn = { "TEST_POI" },
          rule = function(ref) calls = calls + 1
            if ref == "npc:1" then return { roles = { "rest.inn" } } end end })
        local low = Bastians:NewModule("Low", { addon = "Bastians_TestApp" })
        Bastians:RegisterFacet(low, { facet = "poi", types = "*", priority = 10,
          rule = function(ref) return { roles = { "fallback" } } end })
        """
    )
    assert list(app.eval("Bastians:Entity('npc:1'):Facet('poi').roles").values()) == ["rest.inn"]
    assert list(app.eval("Bastians:Entity('npc:2'):Facet('poi').roles").values()) == ["fallback"]
    assert list(app.eval("Bastians:Entity('quest:5'):Facet('poi').roles").values()) == ["fallback"]
    assert app.eval("Bastians:Entity('npc:1'):Facet('activity')") is None
    assert "facet:poi:true" in events(app)
    calls = app.eval("calls")
    app.eval("Bastians:Entity('npc:1'):Facet('poi')")
    assert app.eval("calls") == calls  # cached
    app.execute("Bastians:Fire('TEST_POI')")
    app.eval("Bastians:Entity('npc:1'):Facet('poi')")
    assert app.eval("calls") == calls + 1  # the message bumped the facet's generation
    app.execute("Bastians:InvalidateFacet(nil)")
    app.eval("Bastians:Entity('npc:1'):Facet('poi')")
    assert app.eval("calls") == calls + 2
    assert app.eval("Bastians:HasFacet('poi', 'npc')") is True
    app.execute("Bastians:GetModule('Low'):Disable()")
    assert app.eval("Bastians:Entity('npc:2'):Facet('poi')") is None
    assert "facet:poi:false" in events(app)


def test_worth_is_the_worth_facet(app: WowRuntime):
    app.execute(
        NEW_MODULE % "Prov"
        + """
        Bastians:RegisterWorth(m, { types = { "item" },
          worth = function(ref) return { text = "1s", copper = 100 } end })
        """
    )
    assert app.eval("Bastians:Entity('item:1'):Facet('worth').copper") == 100
    assert app.eval("Bastians:Entity('item:1'):Worth().text") == "1s"
    assert app.eval("Bastians:HasFacet('worth', 'item')") is True
    assert app.eval("Bastians:HasWorth('npc')") is False


EXTENSION = """
local ext = Bastians:NewModule("GatherPlus", { addon = "Bastians_TestApp" })
ok = Bastians:RegisterGraphExtension(ext, {
  ns = "gatherplus", version = 2,
  types = { route = {
    name = function(id) return "Herb round " .. id end,
    places = function(id) return { { map = 0, wx = 0, wy = 100, ui = 1429, src = "gatherplus" } } end,
  } },
  edges = { visits = { from = "gatherplus.route", to = "node" } },
  facets = {
    { facet = "activity", types = { "gatherplus.route" }, rule = function(ref) return { takes = 600 } end },
    { facet = "gatherplus.score", types = "*", rule = function(ref) return { score = 3 } end },
  },
  profiles = { avoidHorde = function(way, character) return nil end },
})
"""


def test_a_graph_extension_adds_types_facets_and_its_namespace(app: WowRuntime):
    """ADR 0026, core-contracts §4: an extension's types are entity types under its namespace,
    its facet rules join the registry, the rest waits for Data's graph in GraphExtensions()."""
    watch_registry(app)
    app.execute(EXTENSION)
    assert app.eval("ok") is True
    assert "graph:gatherplus:true" in events(app)
    route = "Bastians:Entity('gatherplus.route:7')"
    assert app.eval(f"{route}:Type()") == "gatherplus.route"
    assert app.eval(f"{route}:Name()") == "Herb round 7"
    # world places from the provider; map places for drawing derived from them
    assert app.eval(f"{route}:AllPlaces()[1].wy") == 100
    loc = app.eval(f"{route}:Locations()[1]")
    assert loc.map == 1429 and abs(loc.x - 0.25) < 1e-6 and abs(loc.y - 0.5) < 1e-6
    assert app.eval(f"{route}:Facet('activity').takes") == 600
    assert app.eval("Bastians:Entity('npc:1'):Facet('gatherplus.score').score") == 3
    ext = app.eval("Bastians:GraphExtensions().gatherplus")
    assert ext.version == 2 and ext.edges.visits.to == "node"
    app.execute("Bastians:GetModule('GatherPlus'):Disable()")
    assert app.eval("Bastians:GraphExtensions().gatherplus") is None
    assert app.eval("Bastians:HasEntityType('gatherplus.route')") is False
    assert app.eval("Bastians:Entity('npc:1'):Facet('gatherplus.score')") is None
    assert "graph:gatherplus:false" in events(app)


def test_a_taken_or_bad_namespace_is_refused(app: WowRuntime):
    app.execute(EXTENSION)
    app.execute(
        NEW_MODULE % "Second" + "second = Bastians:RegisterGraphExtension(m, { ns = 'gatherplus' })"
    )
    assert app.eval("second") is False
    warns = [e.text for e in app.eval("Bastians:GetLog()").values() if e.level == "warn"]
    assert any("graph extension namespace gatherplus is taken" in w for w in warns)
    for n, bad in enumerate(("'Gather'", "'gather.plus'", "nil")):
        err = app.eval(
            f"select(2, pcall(Bastians.RegisterGraphExtension, Bastians, "
            f"Bastians:NewModule('Bad{n}', {{ addon = 'Bastians_TestApp' }}), "
            f"{{ ns = {bad} }}))"
        )
        assert "RegisterGraphExtension" in str(err), bad
    err = app.eval(
        "select(2, pcall(Bastians.RegisterGraphExtension, Bastians, "
        "Bastians:NewModule('Thief', { addon = 'Bastians_TestApp' }), "
        "{ ns = 'thief', facets = { { facet = 'gatherplus.score', rule = function() end } } }))"
    )
    assert "neither ours nor under thief" in str(err)
