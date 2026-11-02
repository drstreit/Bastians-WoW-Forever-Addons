"""The map's own layers: zone names as text
pins, points of interest by the poi facet's role groups, on the fixture world (Elwynn Forest has
transforms in the mock; Westfall has none, so its places stay off the map)."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
WORLD = "{ continent = 0, x1 = -20000, y1 = -20000, x2 = 20000, y2 = 20000, level = %d }"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(10)
    return wow


def query(wow: WowRuntime, layer: str, level: int) -> list:
    pins = wow.eval(f"Bastians:QueryLayer('{layer}', {WORLD % level})")
    return sorted((p.ref, p.label, p.sub) for p in pins.values())


def test_zone_names_are_text_pins_with_the_level_band_at_low_zoom(wow: WowRuntime):
    boot(wow)
    assert query(wow, "map.zones", 1) == [("zone:1429", "Elwynn Forest", "7-11")]
    # at every zoom, the map's only zone names
    assert query(wow, "map.zones", 5) == [("zone:1429", "Elwynn Forest", "7-11")]
    pins = wow.eval(f"Bastians:QueryLayer('map.zones', {WORLD % 1})")
    assert pins[1].kind == "text"
    # drawn as words: the name and its band under it, no pin frame
    wow.execute(f"{MOD}.Map.Fly(0, 0, 0, 2)")
    wow.advance(0.2)
    texts = [t for t in wow.eval(f"{MOD}.Pins.textPool").values() if t.IsShown(t)]
    assert [(t.GetText(t), t.sub.GetText(t.sub)) for t in texts] == [("Elwynn Forest", "7-11")]
    # dark on every map style
    style = "Bastians.UI.Style.C"
    name, band = texts[0], texts[0].sub
    assert list(name.GetTextColor(name))[:3] == list(wow.eval(f"{style}.mapText").values())[:3]
    assert list(band.GetTextColor(band))[:3] == list(wow.eval(f"{style}.mapTextDim").values())[:3]
    # and a light rim around them
    rims = list(name.rims.values())
    rim = list(wow.eval(f"{style}.mapTextRim").values())[:3]
    assert len(rims) == 8 and all(r.IsShown(r) and r.GetText(r) == "Elwynn Forest" for r in rims)
    assert all(list(r.GetTextColor(r))[:3] == rim for r in rims)
    assert all(r.GetText(r) == "7-11" for r in band.rims.values())
    wow.execute(f"{MOD}.Pins.SetLayerOn('map.zones', false)")
    wow.advance(0.2)
    assert not any(r.IsShown(r) for r in rims)  # gone with the words
    assert wow.errors == []


def test_points_of_interest_come_by_their_role_group(wow: WowRuntime):
    boot(wow)
    travel = [ref for ref, _, _ in query(wow, "map.travel", 5)]
    assert "flightpath:2" in travel and "transport:tram-goldshire-stormwind" in travel
    assert [r for r, _, _ in query(wow, "map.services", 5)] == [
        "npc:295",
        "npc:8719",
    ]  # the innkeeper and the auctioneer
    assert [r for r, _, _ in query(wow, "map.vendors", 6)] == ["npc:54"]
    assert [r for r, _, _ in query(wow, "map.trainers", 5)] == ["npc:198"]
    assert query(wow, "map.services", 1) == []  # below its level
    minimap = WORLD.replace("level = %d", "level = 5, minimap = true") % ()
    # on the minimap too
    assert len(wow.eval(f"Bastians:QueryLayer('map.travel', {minimap})")) > 0
    on = {
        layer: wow.eval(f"{MOD}.Pins.IsLayerOn(Bastians:GetMapLayer('{layer}'))")
        for layer in ("map.zones", "map.travel", "map.services", "map.vendors", "map.nodes")
    }
    assert on == {
        "map.zones": True,  # on by default (owner)
        "map.travel": True,
        "map.services": True,
        "map.vendors": False,
        "map.nodes": False,
    }
    pills = [i.text for i in wow.eval(f"{MOD}.LayerBar.Items()").values() if i.kind == "pill"]
    assert {
        "Zone information",
        "Travel",
        "Services",
        "Vendors",
        "Trainers",
        "Crafting",
        "Resource nodes",
    } <= set(pills)
    assert wow.errors == []


def test_zone_information_names_creature_levels_and_the_lore(wow: WowRuntime):
    boot(wow)
    info = list(wow.eval(f"{MOD}.Layers.ZoneInfo(1429)").values())
    assert any(line.startswith("Creatures: level ") for line in info)
    assert not any("Lore" in line for line in info)  # no LoreForever
    actions = [
        a.id for a in wow.eval("Bastians:GetActions('zone:1429', { source = 'test' })").values()
    ]
    # the Spoken lore is Bastian's Voice's Play button since 01.11.2026 (voice.md); the Map's own
    # `map.lore` is gone (it called a global of Spoken before 3.0)
    assert "map.lore" not in actions
    # with LoreForever: the hint to its command
    wow.execute(
        """Mock.addons.LoreForever = { meta = { Title = "LoreForever" }, files = {}, dir = "x", loaded = true }
        Bastians:GetModule('Map').Layers.Reset()"""
    )
    wow.execute("Mock.loaded = Mock.loaded or {}; Mock.loaded.LoreForever = true")
    info = list(wow.eval(f"{MOD}.Layers.ZoneInfo(1429)").values())
    if any("LoreForever" in line for line in info):
        # the zone's words on the map carry the lines into the card
        data = wow.eval(
            f"{MOD}.Pins.MiniCardData(Bastians:QueryLayer('map.zones', {WORLD % 1})[1])"
        )
        assert info[-1] in list(data.lines.values())
    assert wow.errors == []


def test_an_npc_walking_about_is_one_pin_and_a_faint_line(wow: WowRuntime):
    boot(wow)
    # Hogger's two places lie 25 yards apart: made a vendor here, he is one pin and his walk
    wow.execute(
        """local r = Bastians:GetService('data'):Get('npc', 448)
        r.flags = { 'vendor' }
        Bastians:Fire('BASTIANS_DATA_LOADED', 'world')"""
    )
    pins = list(wow.eval(f"Bastians:QueryLayer('map.vendors', {WORLD % 6})").values())
    hogger = [p for p in pins if p.ref == "npc:448"]
    lines = [p for p in pins if p.kind == "path"]
    assert len(hogger) == 1 and len(lines) == 1
    assert len(list(lines[0].points.values())) == 2 and lines[0].style == "dashed"
    assert wow.errors == []


def test_a_roaming_creature_gets_a_soft_area_from_its_spawn_radius(wow: WowRuntime):
    """W5 "area runs" (26.10.2026): the spawn row's sixth field is the yards the creature roams;
    `Places()` gives it as `r`, a service pin draws it as a soft area from 15 yards on."""
    boot(wow)
    wow.execute(
        """local rec = Bastians:GetService('data'):Get('npc', 295)
        rec.spawns[1][6] = 30
        rec._spawns = nil
        Bastians:GetService('data'):Get('npc', 8719).spawns[1][6] = 5"""
    )
    wow.execute("Bastians:GetService('data'):Get('npc', 8719)._spawns = nil")
    places = wow.eval("Bastians:Entity('npc:295'):Places()")
    assert places[1].r == 30
    pins = {
        p.ref: p for p in wow.eval(f"Bastians:QueryLayer('map.services', {WORLD % 5})").values()
    }
    assert pins["npc:295"].radius == 30 and pins["npc:8719"].radius is None  # 5 yards: no area
    assert wow.errors == []


def test_the_dungeon_doors_are_a_layer_of_their_own(wow: WowRuntime):
    """31.10.2026: the doors left Travel for "Dungeons and raids"; the fixture's Deadmines door
    stands in Westfall, placed in the mock here and listed under Elwynn's zone for the query."""
    wow.execute(
        "Mock.maps[1436] = { name = 'Westfall', mapType = 3, parent = 1415,"
        " c00 = { 0, -200, 200 }, c11 = { 0, -600, -200 } }"
    )
    boot(wow)
    wow.execute(
        "local idx = Bastians:GetService('data'):Index('entrance.byZone')"
        " idx[1429] = idx[1429] or {} table.insert(idx[1429], '36-1')"
    )
    assert query(wow, "map.dungeons", 5) == [("dungeon:36", "The Deadmines", None)]
    assert not any(ref.startswith("entrance:") for ref, _, _ in query(wow, "map.travel", 5))
    # a door of an instance without a dungeon record keeps its own name and page
    wow.execute("Bastians:GetService('data'):Get('entrance', '36-1').instance = 9999")
    assert query(wow, "map.dungeons", 5) == [("entrance:36-1", "Deadmines", None)]
    assert query(wow, "map.dungeons", 0) == []  # below its level
    pills = [i.text for i in wow.eval(f"{MOD}.LayerBar.Items()").values() if i.kind == "pill"]
    assert "Dungeons and raids" in pills
    assert wow.errors == []


def test_a_trainer_pin_says_what_it_trains(wow: WowRuntime):
    """ "I see the trainer names - but not what they train"."""
    boot(wow)
    assert query(wow, "map.trainers", 5) == [("npc:198", "Zaldimar Wefhellt (Mage)", None)]
