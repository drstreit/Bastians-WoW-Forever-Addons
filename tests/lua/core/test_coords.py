"""Bastians.Coords (B2.5): map fractions to world yards and back, best map, player position, distance."""

from harness import WowRuntime

# continent 1: map 900 covers world x 0..1000, y 0..1000; map 901 is the quarter 0..500 x 0..500
TABLE = "{ [900] = { 1, 0, 0, 1000, 0, 1000, 0 }, [901] = { 1, 0, 0, 500, 0, 500, 0 } }"


def test_to_world_uses_the_client_api_for_known_maps(core: WowRuntime):
    assert core.eval("Bastians.Coords.ToWorld(1429, 0.25, 0.5)") == (0, 0, 100)
    assert core.eval("Bastians.Coords.ToWorld(999, 0.25, 0.5)") is None


def test_round_trip_through_the_transform_table(core: WowRuntime):
    core.execute(f"Bastians.Coords.SetTransforms({TABLE})")
    assert core.eval("Bastians.Coords.ToWorld(901, 0.2, 0.6)") == (1, 300, 100)
    assert core.eval("Bastians.Coords.ToMap(1, 300, 100, 901)") == (0.2, 0.6)
    assert core.eval("Bastians.Coords.ToMap(1, 300, 100, 900)") == (0.1, 0.3)
    assert core.eval("Bastians.Coords.ToMap(0, 300, 100, 901)") is None  # wrong continent
    assert core.eval("Bastians.Coords.HasTransform(901)") is True


def test_to_map_falls_back_to_the_client_api(core: WowRuntime):
    assert core.eval("Bastians.Coords.ToMap(0, 0, 100, 1429)") == (0.25, 0.5)


def test_continent_names_come_with_the_transform_table(core: WowRuntime):
    """coordinates.md: a continent is a Map.db2 id; names arrive with the table (every world map
    with a zone on retail), the two Azeroth continents without one."""
    assert dict(core.eval("Bastians.Coords.Continents()")) == {0: "Eastern Kingdoms", 1: "Kalimdor"}
    core.execute(
        f"Bastians.Coords.SetTransforms({TABLE}, {{ [0] = 'Eastern Kingdoms', [530] = 'Outland' }})"
    )
    assert dict(core.eval("Bastians.Coords.Continents()")) == {
        0: "Eastern Kingdoms",
        530: "Outland",
    }
    assert core.eval("Bastians.Coords.ContinentName(530)") == "Outland"
    assert core.eval("Bastians.Coords.ContinentName(1)") is None
    core.execute(f"Bastians.Coords.SetTransforms({TABLE})")  # a table without names: the default
    assert core.eval("Bastians.Coords.ContinentName(1)") == "Kalimdor"


def test_best_map_is_the_smallest_containing_map(core: WowRuntime):
    core.execute(f"Bastians.Coords.SetTransforms({TABLE})")
    assert core.eval("Bastians.Coords.BestMap(1, 300, 100)") == 901
    assert core.eval("Bastians.Coords.BestMap(1, 800, 900)") == 900
    assert core.eval("Bastians.Coords.BestMap(1, 5000, 100)") is None
    assert core.eval("Bastians.Coords.BestMap(0, 300, 100)") is None


def test_player_position(core: WowRuntime):
    continent, wx, wy, map_id, x, y = core.eval("Bastians.Coords.Player()")
    assert (continent, map_id, x, y) == (0, 1429, 0.42, 0.65)
    assert (round(wx, 6), round(wy, 6)) == (
        -60,
        32,
    )  # elwynn mock: wx = 200 - 400*y, wy = 200 - 400*x
    core.execute("Mock.playerMap = nil")
    assert core.eval("Bastians.Coords.Player()") is None


def test_round_trip_for_every_mock_map_within_a_hundredth_of_a_percent(core: WowRuntime):
    """map.md acceptance 1: fraction -> world -> fraction within 0.01 % for every map with a transform."""
    maps = [m for m, info in core.eval("Mock.maps").items() if info.c00 is not None]
    assert len(maps) >= 3
    for map_id in maps:
        for x, y in ((0.0, 0.0), (0.42, 0.65), (1.0, 1.0), (0.123456, 0.987654)):
            continent, wx, wy = core.eval(f"Bastians.Coords.ToWorld({map_id}, {x}, {y})")
            bx, by = core.eval(f"Bastians.Coords.ToMap({continent}, {wx}, {wy}, {map_id})")
            assert abs(bx - x) < 1e-4 and abs(by - y) < 1e-4, (map_id, x, y, bx, by)


def test_distance(core: WowRuntime):
    assert core.eval("Bastians.Coords.Distance({ 0, 0, 0 }, { 0, 30, 40 })") == 50
    assert core.eval("Bastians.Coords.Distance({ 0, 0, 0 }, { 1, 30, 40 })") is None


def test_best_map_prefers_the_map_where_the_point_is_central(core: WowRuntime):
    """coordinates.md: zone rectangles overlap, the most central containing map wins over the smallest."""
    core.execute(
        """
        Bastians.Coords.SetTransforms({
          [10] = { 0, 1000, 0, -1000, 1000, -1000, 0 },  -- a large zone
          [11] = { 0, 800, 0, -500, 750, -500, 0 },      -- a small one overlapping its edge
          [12] = { 0, 20000, 0, -40000, 20000, -40000, 0 }, -- the continent map
        })
        """
    )
    assert core.eval("Bastians.Coords.BestMap(0, 500, 740)") == 10  # at the small map's edge
    assert core.eval("Bastians.Coords.BestMap(0, 550, 500)") == 11  # central in both: the smaller
    assert (
        core.eval("Bastians.Coords.BestMap(0, 15000, 15000)") == 12
    )  # only the continent holds it
