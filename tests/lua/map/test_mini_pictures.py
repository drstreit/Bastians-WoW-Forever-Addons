"""Pictures in the chosen map style for the suite's pages (ADR 0056, PA6): the Map offers its cells
through the service `mapPicture`; the kit cuts them to a map box and filters them; the far cells
unless a picture asks for more; the physical map and a missing Map leave the client's painting."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from mapstyle.emit import style_lua
from test_overview import MAP_, boot

SC = "Bastians.UI.Scenery"
# the mock places Elwynn (1429) around the world's origin, 400 yards a side, where four far
# cells and four near cells meet
FAR = {0: [(3, 3), (3, 4), (4, 3), (4, 4)]}
NEAR = {0: [(7, 7), (7, 8), (8, 7), (8, 8)]}
PICTURE = """
  PIC = CreateFrame("Frame", nil, UIParent)
  POOL = {}
  DRAWN = %s.DrawPicture(PIC, POOL, 1429, %s)
"""


def style(wow: WowRuntime, key: str = "pencil") -> None:
    wow.execute(style_lua(key, wow.client, "test", NEAR, FAR))
    wow.execute("Bastians.Deliver()")
    wow.execute(f"{MAP_}.SetStyle('{key}')")


def textures(wow: WowRuntime) -> list:
    return [t for t in wow.eval("POOL").values() if t.IsShown(t)]


def test_the_cuts_of_cells_cover_a_window_exactly(wow: WowRuntime):
    """Scenery.CellCuts, pure: north up, west left; a cell's share of the window and its texture
    coordinates; a cell beside the window gives no cut."""
    boot(wow)
    wow.execute(
        f"""
        CUTS = {SC}.CellCuts({{
          {{ path = "nw", x1 = 0, x2 = 100, y1 = 0, y2 = 100 }},
          {{ path = "se", x1 = -100, x2 = 0, y1 = -100, y2 = 0 }},
          {{ path = "away", x1 = 500, x2 = 600, y1 = 0, y2 = 100 }},
        }}, {{ north = 50, south = -50, west = 50, east = -50 }})
        """
    )
    cuts = list(wow.eval("CUTS").values())
    assert [c.path for c in cuts] == ["nw", "se"]
    nw, se = cuts
    assert (nw.left, nw.right, nw.top, nw.bottom) == (0, 0.5, 0, 0.5)
    assert (nw.u1, nw.u2, nw.v1, nw.v2) == (0.5, 1, 0.5, 1)  # the cell's south-east corner
    assert (se.left, se.right, se.top, se.bottom) == (0.5, 1, 0.5, 1)
    assert (se.u1, se.u2, se.v1, se.v2) == (0, 0.5, 0, 0.5)  # the cell's north-west corner
    assert wow.errors == []


def test_a_picture_comes_from_the_chosen_style_filtered(wow: WowRuntime):
    boot(wow, tiles=True)
    style(wow)
    wow.execute(PICTURE % (SC, "0, 0, 1, 1, 240, 160"))
    assert wow.eval("DRAWN") is True
    shown = textures(wow)
    assert len(shown) == 4
    assert all("Bastians_Map_Pencil\\Generated\\" in t.GetTexture(t) for t in shown)
    assert all(t.filter == "TRILINEAR" for t in shown)
    area = sum(t.GetWidth(t) * t.GetHeight(t) for t in shown)
    assert abs(area - 240 * 160) < 1  # no gap, no overlap
    assert wow.errors == []


def test_the_far_cells_unless_a_picture_asks_for_more(wow: WowRuntime):
    """Near cells only where the far cells cannot fill the picture: here the zone is 400 yards
    wide, so even a small picture asks for more than 0.12 px a yard; a world window of the far
    cells' own density stays far."""
    boot(wow, tiles=True)
    style(wow)
    service = "Bastians:GetService('mapPicture')"
    near = wow.eval(f"{service}:Cells(0, -200, -200, 200, 200, 240)")
    assert all("\\Near\\" in c.path for c in near.values())
    far = wow.eval(f"{service}:Cells(0, -200, -200, 200, 200, 40)")
    assert all("\\Far\\" in c.path for c in far.values())
    # a world without near cells there falls back to the far ones
    wow.execute(
        "for k in pairs(Bastians:GetModule('Map').Styles.Get('pencil').near.cells[0]) do"
        " Bastians:GetModule('Map').Styles.Get('pencil').near.cells[0][k] = nil end"
    )
    back = wow.eval(f"{service}:Cells(0, -200, -200, 200, 200, 240)")
    assert all("\\Far\\" in c.path for c in back.values())
    assert wow.errors == []


def test_on_the_physical_map_a_picture_is_the_painting(wow: WowRuntime):
    boot(wow, tiles=True)
    assert wow.eval("Bastians:GetService('mapPicture'):Cells(0, -200, -200, 200, 200, 240)") is None
    wow.execute(PICTURE % (SC, "0, 0, 1, 1, 240, 160"))
    assert wow.eval("DRAWN") is True
    assert not any("Bastians_Map" in str(t.GetTexture(t)) for t in textures(wow))
    assert all(t.filter is None for t in textures(wow))  # the painting is not touched
    # the style chosen, and back: a pooled texture takes each in turn
    style(wow)
    wow.execute(f"DRAWN = {SC}.DrawPicture(PIC, POOL, 1429, 0, 0, 1, 1, 240, 160)")
    assert len(textures(wow)) == 4
    wow.execute(f"{MAP_}.SetStyle('physical')")
    wow.execute(f"DRAWN = {SC}.DrawPicture(PIC, POOL, 1429, 0, 0, 1, 1, 240, 160)")
    assert all("Bastians_Map" not in str(t.GetTexture(t)) for t in textures(wow))
    assert wow.errors == []


def test_pixels_follow_the_screen_and_the_scale(wow: WowRuntime):
    """As measured on the client: 2160 / 768 x 0.64 = 1.8 px a unit, 1080 / 768 = 1.41."""
    boot(wow)
    wow.execute(
        "F = CreateFrame('Frame', nil, UIParent); F.GetEffectiveScale = function() return 0.64 end"
    )
    wow.execute("Mock.screen = { 5120, 2160 }")
    assert round(wow.eval(f"{SC}.PixelsPerUnit(F)"), 2) == 1.8
    wow.execute("Mock.screen = { 1920, 1080 }; F.GetEffectiveScale = function() return 1 end")
    assert round(wow.eval(f"{SC}.PixelsPerUnit(F)"), 2) == 1.41
    assert wow.errors == []


def test_the_mini_maps_may_have_another_style_than_the_large_map(wow: WowRuntime):
    """The Browser's option: the large map stays physical, the pictures are
    Pencil; "physical" is the painting whatever the large map shows."""
    boot(wow, tiles=True)
    style(wow)
    wow.execute(f"{MAP_}.SetStyle('physical')")
    wow.execute(f"{SC}.SetStyle('pencil')")
    wow.execute(PICTURE % (SC, "0, 0, 1, 1, 240, 160"))
    assert all("Bastians_Map_Pencil" in str(t.GetTexture(t)) for t in textures(wow))
    wow.execute(f"{MAP_}.SetStyle('pencil')")
    wow.execute(f"{SC}.SetStyle('physical')")
    wow.execute(f"DRAWN = {SC}.DrawPicture(PIC, POOL, 1429, 0, 0, 1, 1, 240, 160)")
    assert all("Bastians_Map" not in str(t.GetTexture(t)) for t in textures(wow))
    keys = [s.key for s in wow.eval("Bastians:GetService('mapPicture'):Styles()").values()]
    assert keys == ["pencil"]
    wow.execute(f"{SC}.SetStyle(nil)")
    assert wow.errors == []
