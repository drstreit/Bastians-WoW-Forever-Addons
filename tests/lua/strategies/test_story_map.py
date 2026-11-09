"""The story map (ADR 0057): the stories on one picture of the world, a token each with its picture
and level, the general ones on two boards in the ocean; tokens never cover each other; a click opens
the story; the book reopens on what the reader left, a new reader starts on the map."""

import math
import re
import sys
from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from mapstyle.blizzard import WORLD  # noqa: E402
from mapstyle.scene import ORIGIN, TILE_YARDS  # noqa: E402

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
MOD = "Bastians:GetModule('Strategies')"
WIN = f"{MOD}.Window"
BOOK = f"{MOD}.Book"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute('Bastians:GetService("data"):LoadPack("book")')
    wow.run_frames(5)
    return wow


def size(wow: WowRuntime) -> None:
    wow.execute(f"{WIN}.atlas:SetSize(928, 560); {WIN}.Render()")


def tokens(wow: WowRuntime) -> list:
    return list(wow.eval(f"{WIN}.AtlasTokens()").values())


def test_the_lua_and_the_picture_share_their_numbers(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{BOOK}.WORLD.width") == WORLD["width"]
    assert wow.eval(f"{BOOK}.WORLD.height") == WORLD["height"]
    assert wow.eval(f"{BOOK}.WORLD.ppt") == WORLD["ppt"]
    for continent, spot in WORLD["continents"].items():
        w = wow.eval(f"{BOOK}.WORLD[{continent}]")
        assert (w.tx, w.ty, w.tx2, w.ty2) == spot["tiles"]
        assert (w.ox, w.oy) == spot["at"]


def test_a_world_point_lands_on_the_picture(wow: WowRuntime):
    boot(wow)
    spot = WORLD["continents"][0]
    x0, y0, _, _ = spot["tiles"]
    ox, oy = spot["at"]
    col, row = x0 + 2, y0 + 3
    wy, wx = ORIGIN - col * TILE_YARDS, ORIGIN - row * TILE_YARDS
    fx, fy = wow.eval(f"{BOOK}.WorldSpot(0, {wx}, {wy})")
    assert math.isclose(fx, (ox + 2 * WORLD["ppt"]) / WORLD["width"], abs_tol=1e-9)
    assert math.isclose(fy, (oy + 3 * WORLD["ppt"]) / WORLD["height"], abs_tol=1e-9)
    assert wow.eval(f"{BOOK}.WorldSpot(0, 99999, 0)") is None  # off the picture
    assert wow.eval(f"{BOOK}.WorldSpot(2991, {wx}, {wy})") is None  # no island on it


def test_stories_stand_where_the_page_says_or_on_a_board(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        local pages = {{
          exact = {{ shelf = "active", chapter = "farming", plate = {{ place = {{ 1, 0.5, 0.5 }} }} }},
          zone = {{ shelf = "active", chapter = "crafting", zones = {{ 2 }} }},
          auction = {{ shelf = "active", chapter = "auction" }},
          trade = {{ shelf = "active", chapter = "trades" }},
          nowhere = {{ shelf = "active", chapter = "flips", zones = {{ 3 }} }},
          preface = {{ shelf = "active", chapter = "front" }},
          old = {{ shelf = "back", chapter = "farming" }},
        }}
        local col, row = 30, 30
        local T = 1600 / 3
        local function toWorld(map)
          if map == 3 then return nil end
          return 0, 32 * T - row * T, 32 * T - col * T
        end
        SPOTS, BOARDS = {BOOK}.Atlas(pages, toWorld, "front")
        """
    )
    spots = {s.id: s for s in wow.eval("SPOTS").values()}
    assert sorted(spots) == ["exact", "zone"]
    assert spots["exact"].exact is True and spots["zone"].exact is False
    market = [s.id for s in wow.eval("BOARDS.market").values()]
    trades = [s.id for s in wow.eval("BOARDS.trades").values()]
    assert market == ["auction", "nowhere"] and trades == ["trade"]  # a place off the picture too


def test_tokens_never_cover_each_other(wow: WowRuntime):
    """Owner, on the mock: the pictures must not overlap. Six on one spot, a cluster, the box."""
    boot(wow)
    wow.execute(
        f"""
        P = {{}}
        for i = 1, 6 do P[i] = {{ x = 100, y = 100 }} end
        P[7] = {{ x = 104, y = 100 }}
        P[8] = {{ x = 300, y = 300 }}
        {BOOK}.Spread(P, 54, 20, 20, 500, 400)
        """
    )
    points = [(p.x, p.y) for p in wow.eval("P").values()]
    for i, a in enumerate(points):
        assert 20 <= a[0] <= 500 and 20 <= a[1] <= 400
        for b in points[i + 1 :]:
            assert math.dist(a, b) >= 54 - 1e-6, (a, b)
    assert points[7] == (300, 300)  # alone: it stays where it is
    first = points
    wow.execute(
        f"""
        Q = {{}}
        for i = 1, 6 do Q[i] = {{ x = 100, y = 100 }} end
        Q[7] = {{ x = 104, y = 100 }}
        Q[8] = {{ x = 300, y = 300 }}
        {BOOK}.Spread(Q, 54, 20, 20, 500, 400)
        """
    )
    assert [(p.x, p.y) for p in wow.eval("Q").values()] == first  # deterministic


def test_a_new_reader_starts_on_the_map_and_a_token_opens_its_story(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook")
    assert wow.eval(f"{WIN}.Current().kind") == "atlas"
    size(wow)
    assert wow.eval(f"{WIN}.atlas:IsShown()") is True
    assert wow.eval(f"{WIN}.left:IsShown()") is False  # the map takes the pages' place
    assert wow.eval(f"{WIN}.folio:IsShown()") is False
    shown = tokens(wow)
    assert "hogger-camp" in [t.id for t in shown]
    assert wow.eval(f"{WIN}.bar.map.spec.on") is True
    # no two tokens on the land cover each other
    land = [(t.x, t.y) for t in shown if not t.onBoard]
    for i, a in enumerate(land):
        for b in land[i + 1 :]:
            assert math.dist(a, b) >= 40 + 14 - 1e-6
    wow.execute(
        f"for _, b in ipairs({WIN}.atlas.tokens) do "
        "if b.story and b.story.id == 'hogger-camp' then b:Click() end end"
    )
    assert wow.eval(f"{WIN}.Current().id") == "hogger-camp"
    assert wow.eval(f"{WIN}.atlas:IsShown()") is False
    assert wow.eval(f"{WIN}.left:IsShown()") is True
    assert wow.errors == []


def test_the_map_is_the_books_front_door(wow: WowRuntime):
    """ "the map is really hard to find": the minimap button (the
    module's open), /bbook and the launcher open the map; the tabs lead into the book from there.
    ~~The reader's last place~~ (ADR 0057, point 4, until then)."""
    boot(wow)
    wow.slash("/bbook contents")
    assert wow.eval(f"{WIN}.Current().kind") == "contents"
    wow.execute(f"{WIN}.Hide()")
    wow.slash("/bbook")
    assert wow.eval(f"{WIN}.Current().kind") == "atlas"
    wow.execute(f"{WIN}.bar.title:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "title"
    assert wow.eval(f"{WIN}.bar.map.spec.on") is None
    wow.execute(f"{WIN}.Hide()")
    wow.execute(f"{MOD}.def.open()")  # the minimap button, the launcher, the feed
    assert wow.eval(f"{WIN}.Current().kind") == "atlas"
    assert wow.eval(f"{WIN}.bar.map.spec.on") is True
    wow.execute(f"{MOD}.def.open()")  # a second press closes the book
    assert wow.eval(f"{WIN}.IsShown()") is False
    assert wow.errors == []


def test_the_map_scales_as_one_piece_and_the_bar_does_not(wow: WowRuntime):
    """ "only the map scales, not the button row"; "scaling is bumpy":
    the picture is laid out at its base size and scaled into the atlas on every size event."""
    boot(wow)
    wow.slash("/bbook map")
    size(wow)  # 928 x 560: the width limits
    assert wow.eval(f"{WIN}.win.content:GetScale()") == 1
    assert wow.eval(f"{WIN}.atlas.picture:GetWidth()") == 900
    assert wow.eval(f"{WIN}.atlas.picture:GetHeight()") == 450
    assert math.isclose(wow.eval(f"{WIN}.atlas.picture:GetScale()"), 928 / 900)
    wow.execute(
        f"{WIN}.atlas:SetSize(1800, 500); {WIN}.atlas:GetScript('OnSizeChanged')({WIN}.atlas)"
    )
    assert math.isclose(wow.eval(f"{WIN}.atlas.picture:GetScale()"), 500 / 450)  # the height limits
    assert wow.eval(f"{WIN}.atlas.picture:GetWidth()") == 900  # the layout did not run again
    assert wow.eval(f"{WIN}.atlas.mill:GetParent() == {WIN}.atlas") is True  # a button, unscaled
    assert wow.eval(f"{WIN}.bar:GetParent() == {WIN}.win.frame") is True
    assert wow.errors == []


def test_the_window_takes_the_maps_proportions(wow: WowRuntime):
    """the window's size "bound to the map": after the grip and on the
    way onto the map the height follows the width, within the screen and the smallest height."""
    boot(wow)
    wow.slash("/bbook title")
    wow.execute(f"{WIN}.atlas:SetSize(928, 560)")  # the atlas' room in a 940 x 640 window
    wow.execute(f"{WIN}.bar.map:Click()")
    w, h = wow.eval(f"{WIN}.win.frame:GetSize()")
    assert (w, h) == (940, 928 / 2 + 80)  # the window adds 80 around the map's height
    assert wow.eval(f"{WIN}.win.db.size[2]") == h  # saved as after a drag
    # after a drag: the height follows the width again
    wow.execute(f"{WIN}.win.frame:SetSize(1200, 700); {WIN}.atlas:SetSize(1188, 620)")
    wow.execute(f"{WIN}.win.opts.onResize(nil, false)")
    w, h = wow.eval(f"{WIN}.win.frame:GetSize()")
    assert (w, h) == (1200, 1188 / 2 + 80)
    # too narrow for the smallest height: the width follows instead
    wow.execute(f"{WIN}.win.frame:SetSize(660, 600); {WIN}.atlas:SetSize(648, 520)")
    wow.execute(f"{WIN}.win.opts.onResize(nil, false)")
    w, h = wow.eval(f"{WIN}.win.frame:GetSize()")
    assert h == 420 and w == (420 - 80) * 2 + 12
    # the pages keep their size: nothing fits a page's window to the map
    wow.execute(f"{WIN}.bar.title:Click()")
    wow.execute(f"{WIN}.win.frame:SetSize(1000, 900); {WIN}.win.opts.onResize(nil, false)")
    assert wow.eval(f"{WIN}.win.frame:GetSize()") == (1000, 900)
    assert wow.errors == []


def test_a_token_lights_its_rim_under_the_cursor(wow: WowRuntime):
    """ "the button needs a hover effect, maybe lighting up their rim"."""
    boot(wow)
    wow.slash("/bbook map")
    size(wow)
    wow.execute(
        f"for _, b in ipairs({WIN}.atlas.tokens) do "
        "if b.story and b.story.id == 'hogger-camp' then T = b end end"
    )
    rest = wow.eval("(function() local r, g, b = T.ring:GetVertexColor() return { r, g, b } end)()")
    assert list(rest.values()) != [1, 1, 1]
    assert wow.eval("(select(4, T.ring:GetPoint(1)))") == -2
    wow.execute("T:GetScript('OnEnter')(T)")
    lit = wow.eval("(function() local r, g, b = T.ring:GetVertexColor() return { r, g, b } end)()")
    assert list(lit.values()) == [1, 1, 1]  # S.C.bright
    assert wow.eval("(select(4, T.ring:GetPoint(1)))") == -4  # and wider
    wow.execute("T:GetScript('OnLeave')(T)")
    back = wow.eval("(function() local r, g, b = T.ring:GetVertexColor() return { r, g, b } end)()")
    assert list(back.values()) == list(rest.values())
    assert wow.eval("(select(4, T.ring:GetPoint(1)))") == -2
    assert wow.errors == []


def test_without_the_picture_the_map_says_so_and_keeps_its_tokens(wow: WowRuntime):
    """A new file: the client answers GetTexture nil until a full restart (forever-api.md)."""
    boot(wow)
    wow.slash("/bbook map")
    size(wow)
    drawn = wow.eval(f"{WIN}.atlas.world:IsShown()")
    assert wow.eval(f"{WIN}.atlas.note:IsShown()") is (not drawn)
    assert tokens(wow)
    assert wow.errors == []


def test_every_key_of_the_map_is_translated():
    keys = ("The market", "Making and gathering", "Click: open the story", "Map")
    for path in (ROOT / "addons" / "Bastians_Strategies" / "Locales").glob("*.lua"):
        text = path.read_text(encoding="utf-8")
        for key in keys:
            assert re.search(r'\["' + re.escape(key) + r'"\] = "', text), (path.name, key)


def test_the_rumour_mill_is_one_click_from_the_map(wow: WowRuntime):
    boot(wow)
    wow.slash("/bbook map")
    size(wow)
    assert wow.eval(f"{WIN}.atlas.mill:IsShown()") is True
    wow.execute(f"{WIN}.atlas.mill:Click()")
    assert wow.eval(f"{WIN}.Current().kind") == "mill"
    assert wow.eval(f"{WIN}.Current().id") == "farming"
    assert wow.errors == []
