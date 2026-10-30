"""The place names: the subzone names leave the style cells and
become a layer of words, the bigger place kept where two would overlap, switched on the layer bar,
for this client's table only. Since 29.10.2026 (owner: "a wider zoom only shows me the main cities,
but zooming in gives me details ... I want the same for all") every style names the map as the
Blizzard style does: Blizzard's labels each from its level, the other subzones closer in, each as
tall against the map as its place is big."""

from harness import WowRuntime

CORE, DATA, MAP = "Bastians_Core", "Bastians_Data", "Bastians_Map"
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
NAMES = f"{MOD}.Names"
PINS = f"{MOD}.Pins"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, MAP)
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    # the names alone: the fixture world's pins and their labels would claim the same spots
    wow.execute(
        f"for _, def in ipairs(Bastians:GetMapLayers()) do "
        f"if def.id ~= 'map.names' then {PINS}.SetLayerOn(def.id, false) end end"
    )
    return wow


def register(wow: WowRuntime, client: str) -> None:
    # Goldshire's patch is bigger than the camp's beside it: where the words overlap, Goldshire stays
    wow.execute(
        "Bastians.Map.RegisterNames({ client = '" + client + "', continents = { [0] = {"
        " { 'Goldshire', 200, 200, 400 }, { 'Tiny Camp', 202, 204, 20 }, { 'Westbrook', 300, -300, 100 },"
        " { 'Far Away', 9000, 9000, 50 } } } })"
    )


def shown(wow: WowRuntime) -> dict[str, int]:
    out = {}
    for fs in wow.eval(f"{PINS}.textPool").values():
        if fs.IsShown(fs):
            out[fs.GetText(fs)] = fs.size
    return out


def settle(wow: WowRuntime, level: float, wx: float = 250, wy: float = -50) -> None:
    # between Goldshire and Westbrook, away from the zone's middle (its name, priority 40, wins there)
    wow.execute(f"{MAP_}.Fly(0, {wx}, {wy}, {level})")
    wow.advance(0.2)


def test_a_bigger_place_shows_earlier_and_every_name_grows_with_the_zoom(wow: WowRuntime):
    boot(wow)
    register(wow, "other")
    assert wow.eval(f"{NAMES}.Count(0)") == 0  # built for the other client: kept out
    register(wow, wow.client)
    assert wow.eval(f"{NAMES}.Count(0)") == 4
    # the level a name reads from follows its patch: 400 chunks at 2, 100 at 3, 20 at 5
    reads = {
        n: wow.eval(f"{NAMES}.ReadsFrom({NAMES}.DetailHeight({c}))")
        for n, c in (("Goldshire", 400), ("Westbrook", 100), ("Tiny Camp", 20))
    }
    assert reads == {"Goldshire": 2, "Westbrook": 3, "Tiny Camp": 5}
    settle(wow, 1)
    assert shown(wow) == {}  # wide: no village yet
    settle(wow, 2)
    assert set(shown(wow)) == {"Goldshire"}
    settle(wow, 3)
    names = shown(wow)
    assert "Goldshire" in names and "Westbrook" in names and "Far Away" not in names
    assert "Tiny Camp" not in names
    small = names["Goldshire"]
    settle(wow, 5, 200, 200)
    assert shown(wow)["Goldshire"] > small  # closer, larger
    assert (
        wow.eval(f"{NAMES}.LabelSize(10, 0)") == 9 and wow.eval(f"{NAMES}.LabelSize(400, 9)") == 24
    )
    assert wow.errors == []


def test_every_style_shows_blizzards_labels_and_the_other_places_closer_in(wow: WowRuntime):
    """Names.lua with Blizzard's labels (Forever's build): the city from level 1, Goldshire as
    Blizzard set it from 2 and only once, Westbrook (no label of Blizzard's) from level 3."""
    boot(wow)
    wow.execute(
        "Bastians.Map.RegisterNames({ client = '" + wow.client + "', continents = { [0] = {"
        " { 'Goldshire', 200, 200, 400 }, { 'Westbrook', 300, -300, 400 } } },"
        " labels = { [0] = { { 'Stormwind', 800, 900, 200, 'city', false, 1 },"
        " { 'Goldshire', 210, 190, 60, 'place', 87, 2 } } } })"
    )
    assert wow.eval(f"{NAMES}.LabelCount(0)") == 2
    settle(wow, 1, 500, 500)
    assert set(shown(wow)) == {"Stormwind"}  # wide: the main city
    settle(wow, 2, 250, 0)
    names = shown(wow)
    assert "Goldshire" in names and "Westbrook" not in names
    settle(wow, 3, 250, 0)
    names = shown(wow)
    assert "Westbrook" in names and list(names).count("Goldshire") == 1
    goldshire = [
        fs
        for fs in wow.eval(f"{PINS}.textPool").values()
        if fs.IsShown(fs) and fs.GetText(fs) == "Goldshire"
    ]
    assert len(goldshire) == 1 and goldshire[0].pin.priority > 20  # Blizzard's, not the subzone
    assert wow.errors == []


def test_the_layer_bar_switches_the_names(wow: WowRuntime):
    boot(wow)
    register(wow, wow.client)
    items = {i.id: i for i in wow.eval(f"{MOD}.LayerBar.Items()").values() if i.kind == "pill"}
    assert items["map.names"].on is True and items["map.names"].text == "Place names"
    wow.execute(f"{PINS}.SetLayerOn('map.names', false)")
    settle(wow, 4)
    assert "Goldshire" not in shown(wow)
    wow.execute(f"{PINS}.SetLayerOn('map.names', true)")
    settle(wow, 4)
    assert "Goldshire" in shown(wow)
    assert wow.errors == []
