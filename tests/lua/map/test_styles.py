"""Bastian's map styles (ADR 0027, map.md "Bastian's styles"): a style addon's generated table (the
shape tools/mapstyle/emit.py writes) registers per client; the style joins the bar's pills and the
settings; chosen, its far cells cover the view at every level and its near cells come in from
NEAR_LEVEL, while the overview, the native tiles and the zone paintings stay off; a style whose
addon is gone falls back to the physical map."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from mapstyle.emit import style_lua
from test_overview import MAP_, MOD, OV, TILES, boot

ST = f"{MOD}.Styles"
BAR = f"{MOD}.LayerBar"

# Elwynn's corner of Eastern Kingdoms: near cells (7..8, 11..12), far cells (3..4, 5..6)
NEAR = {0: [(7, 11), (7, 12), (8, 11), (8, 12)]}
FAR = {0: [(3, 5), (3, 6), (4, 5), (4, 6)]}


def register(wow: WowRuntime, style: str = "pencil", client: str | None = None) -> None:
    wow.execute(style_lua(style, client or wow.client, "test", NEAR, FAR))
    wow.execute("Bastians.Deliver()")


def pills(wow: WowRuntime) -> list[tuple[str, str, bool]]:
    items = list(wow.eval(f"{BAR}.StyleItems()").values())  # the style menu's entries (R27.8)
    return [(i.id, i.text, i.on) for i in items]


def test_a_style_registers_for_its_client_and_joins_the_pills(wow: WowRuntime):
    boot(wow, tiles=True)
    register(wow, "pencil", client="other")
    assert wow.eval(f"{ST}.Get('pencil')") is None  # built for the other client: kept out
    register(wow, "pencil")
    register(wow, "modern")
    assert [s.key for s in wow.eval(f"{ST}.List()").values()] == ["modern", "pencil"]
    assert wow.eval(f"{ST}.Count('pencil', 'near', 0)") == 4
    assert pills(wow) == [
        ("style:physical", "Physical", True),
        ("style:modern", "Modern", False),
        ("style:pencil", "Pencil", False),
    ]
    values = wow.eval(f"{MOD}.options[2].values()")
    assert values["pencil"] == "Pencil" and values["physical"] == "Physical"
    assert wow.errors == []


def test_the_style_draws_far_cells_then_near_cells_and_nothing_else(wow: WowRuntime):
    boot(wow, tiles=True)
    register(wow)
    # Goldshire, zoomed out: the far cells around it, the game's ground off
    wow.execute(f"{MAP_}.SetStyle('pencil')")
    assert wow.eval(f"{MOD}.db.profile.mapStyle") == "pencil"
    wow.execute(f"{MAP_}.Fly(0, -9460, 60, 1)")
    far = {t.GetTexture(t) for t in wow.eval(f"{ST}.far.live").values()}
    assert far and all("Bastians_Map_Pencil\\Generated\\Far\\0_" in f for f in far)
    assert wow.eval(f"{ST}.near.stats.shown") == 0
    assert wow.eval(f"{OV}.stats.shown") == 0 and wow.eval(f"{TILES}.stats.shown") == 0
    assert wow.eval(f"{MOD}.Imagery.stats.textures") == 0  # no paintings, the names stay
    # close: the near cells above the far ones
    wow.execute(f"{MAP_}.Fly(0, -9460, 60, 4)")
    near = [t for t in wow.eval(f"{ST}.near.live").values()]
    assert near and all("\\Near\\0_" in t.GetTexture(t) for t in near)
    assert wow.eval(f"{ST}.near.sublevel") > wow.eval(f"{ST}.far.sublevel")
    # back to the ground
    wow.execute(f"{MAP_}.SetStyle('physical')")
    assert wow.eval(f"{ST}.far.stats.shown") == 0 and wow.eval(f"{ST}.near.stats.shown") == 0
    assert wow.errors == []


def test_a_style_whose_addon_is_gone_falls_back_to_the_physical_map(wow: WowRuntime):
    boot(wow, tiles=True)
    wow.execute(f"{MOD}.db.profile.mapStyle = 'parchment'")  # chosen once, its addon not installed
    assert wow.eval(f"{MAP_}.Style()") == "physical"
    wow.execute(f"{MAP_}.SetStyle('parchment')")  # not offered, so not taken
    assert wow.eval(f"{MAP_}.Style()") == "physical"
    register(wow, "parchment")
    assert wow.eval(f"{MAP_}.Style()") == "parchment"  # installed again: the choice comes back
    assert wow.errors == []


def test_a_new_style_repaints_the_cells_in_place_without_a_zoom(wow: WowRuntime):
    """(R27.7): a new style showed only after a zoom, and zooming out and
    in could show two styles. Cells are kept by position: a kept cell now takes the new file."""
    boot(wow, tiles=True)
    register(wow, "pencil")
    register(wow, "modern")
    wow.execute(f"{MAP_}.SetStyle('pencil'); {MAP_}.Fly(0, -9460, 60, 4)")
    files = lambda which: {t.GetTexture(t) for t in wow.eval(f"{ST}.{which}.live").values()}  # noqa: E731
    assert files("far") and all("Map_Pencil" in f for f in files("far") | files("near"))
    wow.execute(f"{MAP_}.SetStyle('modern')")  # no fly, no zoom
    assert files("far") and files("near")
    assert all("Map_Modern" in f for f in files("far") | files("near"))
    wow.execute(f"{MAP_}.Fly(0, -9460, 60, 1)")  # zooming out keeps the one style
    assert all("Map_Modern" in f for f in files("far"))
    assert wow.errors == []


def test_the_sea_lies_under_the_zone_paintings(wow: WowRuntime):
    """(R27.5): the paintings showed parchment only; the paintings and
    the sea share the clip frame and the sea had the default sublevel 0, above the paintings."""
    boot(wow, tiles=True)
    layer, sub = wow.eval(f"{MAP_}.clip.sea:GetDrawLayer()")
    assert layer == "BACKGROUND" and sub == -8
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 3)")  # the physical map over the mock's painted Elwynn
    subs = [t.sublevel for t in wow.eval(f"{MOD}.Imagery.pool").values() if t.IsShown(t)]
    assert subs and min(subs) > sub
    assert wow.errors == []


LABELS = {
    0: [
        {
            "text": "Goldshire",
            "kind": "place",
            "wx": -9460,
            "wy": 60,
            "height": 40,
            "area": 87,
            "level": 2,
        },
        {
            "text": "Stormwind",
            "kind": "city",
            "wx": -8900,
            "wy": 500,
            "height": 90,
            "area": 1519,
            "level": 1,
        },
        {
            "text": "The Great\nSea",
            "kind": "sea",
            "wx": -10000,
            "wy": 3000,
            "height": 120,
            "area": None,
            "level": 0,
        },
    ]
}


def register_blizzard(wow: WowRuntime) -> None:
    wow.execute(style_lua("blizzard", wow.client, "test", NEAR, FAR, LABELS))
    wow.execute("Bastians.Deliver()")


def test_the_blizzard_style_is_a_baked_style_first_in_the_menu(wow: WowRuntime):
    """ADR 0036: the runtime Blizzard map (one painting at a time, explored
    areas cut live) is gone; Bastians_Map_Blizzard registers its cells like our styles, first after
    the physical map. Without the addon there is no Blizzard entry."""
    boot(wow, tiles=True)
    assert [p[0] for p in pills(wow)] == ["style:physical"]
    register(wow, "modern")
    register_blizzard(wow)
    assert pills(wow) == [
        ("style:physical", "Physical", True),
        ("style:blizzard", "Blizzard", False),
        ("style:modern", "Modern", False),
    ]
    wow.execute(f"{MAP_}.SetStyle('blizzard'); {MAP_}.Fly(0, -9460, 60, 4)")
    far = {t.GetTexture(t) for t in wow.eval(f"{ST}.far.live").values()}
    near = {t.GetTexture(t) for t in wow.eval(f"{ST}.near.live").values()}
    assert far and near and all("Bastians_Map_Blizzard" in f for f in far | near)
    assert wow.eval(f"{TILES}.stats.shown") == 0  # the game's ground stays off
    assert wow.errors == []


def test_the_blizzard_style_sets_blizzards_names_where_the_paintings_had_them(wow: WowRuntime):
    """ADR 0036: the paintings' lettering is painted out; the names come back as text at Blizzard's
    places and line breaks, as tall against the map as Blizzard's letters (within bounds), each
    from its own zoom level; another language's client names the areas in its own words."""
    boot(wow, tiles=True)
    register_blizzard(wow)
    wow.execute(f"{MAP_}.SetStyle('blizzard')")
    names = f"{MOD}.Names"
    view = {"continent": 0, "x1": -20000, "x2": 0, "y1": -5000, "y2": 5000}

    def query(level):
        v = dict(view, level=level)
        lua = "{" + ", ".join(f"{k} = {val}" for k, val in v.items()) + "}"
        return {p.label: p for p in wow.eval(f"{names}.Query({lua})").values()}

    assert set(query(0)) == {"The Great\nSea"}  # the sea from the start, the city from 1
    assert set(query(1)) == {"The Great\nSea", "Stormwind"}
    at4 = query(4)
    assert set(at4) == {"The Great\nSea", "Stormwind", "Goldshire"}
    gold = at4["Goldshire"]
    # dark words without an outline in every style
    assert gold.outline is None and gold.ink == "text"
    assert at4["The Great\nSea"].outline is None
    # 40 yards tall at level 4 (1/2 px per yard) at 0.9: 18 points; closer, capped
    assert gold.size == 18 and query(7)["Goldshire"].size == wow.eval(f"{names}.LABEL_MAX")
    # a German client: the client's own name for the area, the sea (no area) stays as it was
    wow.execute("Mock.locale = 'deDE'; Mock.areas = { [87] = 'Goldhain' }")
    at4 = query(4)
    assert "Goldhain" in at4 and "Goldshire" not in at4 and "The Great\nSea" in at4
    wow.execute("Mock.locale = nil; Mock.areas = nil")
    assert wow.errors == []
