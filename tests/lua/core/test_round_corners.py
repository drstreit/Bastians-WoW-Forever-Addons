"""Round corners: the kit's fills and
outlines are made of quarter discs and rings at the theme's radius, laid out again on a theme
switch; pills are round at both ends; a header rounds only its top; windows, buttons and menus use
them."""

from harness import WowRuntime

S = "Bastians.UI.Style"
DISC = "Interface\\AddOns\\Bastians_Core\\Media\\Disc"


def shape_frame(core: WowRuntime, w: int = 100, h: int = 40) -> None:
    core.execute(
        f"""
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize({w}, {h})
        fill = {S}.roundFill(holder, {S}.C.panel)
        outline = {S}.roundEdges(holder, {S}.C.line)
        """
    )


def test_a_fill_is_four_quarter_discs_and_three_bands(core: WowRuntime):
    shape_frame(core)
    pieces = list(core.eval("fill.pieces").values())
    assert len(pieces) == 7 and core.eval("fill.r") == 6  # the teal theme's radius
    corner = pieces[0]
    assert corner.GetTexture(corner) == DISC
    assert corner.GetTexCoord(corner) == (0, 0.5, 0, 0.5)  # the top-left quarter
    assert (corner.GetWidth(corner), corner.GetHeight(corner)) == (6, 6)
    middle = pieces[4]
    assert middle.GetTexture(middle) == "Interface\\Buttons\\WHITE8X8"
    # every piece carries the token colour; a theme switch lays the corners out again
    r, g, b, _ = corner.GetVertexColor(corner)
    assert [round(v, 3) for v in (r, g, b)] == [
        round(v, 3) for v in list(core.eval(f"{S}.C.panel").values())[:3]
    ]
    core.execute(f"{S}.ApplyTheme('contrast')")
    assert core.eval("fill.r") == 3 and corner.GetWidth(corner) == 3
    r2, _, _, _ = corner.GetVertexColor(corner)
    assert round(r2, 3) == round(next(iter(core.eval(f"{S}.C.panel").values())), 3)
    core.execute(f"{S}.ApplyTheme('teal')")
    assert core.errors == []


def test_an_outline_uses_the_ring_that_keeps_a_one_pixel_line(core: WowRuntime):
    shape_frame(core)
    pieces = list(core.eval("outline.pieces").values())
    assert len(pieces) == 8
    assert pieces[0].GetTexture(pieces[0]) == core.eval(f"{S}.RINGS.M")  # 6 px corners
    top = pieces[4]
    assert top.GetHeight(top) == 1
    assert core.eval(f"{S}.RingFor(3)") == core.eval(f"{S}.RINGS.S")
    assert core.eval(f"{S}.RingFor(10)") == core.eval(f"{S}.RINGS.L")
    # S.setEdges recolours a shape like the old four edges
    core.execute(f"{S}.setEdges(outline, {S}.C.accent, 0.8)")
    _, g, _, a = pieces[2].GetVertexColor(pieces[2])
    assert round(a, 2) == 0.8 and round(g, 3) == round(
        list(core.eval(f"{S}.C.accent").values())[1], 3
    )
    assert core.errors == []


def test_pills_round_their_ends_headers_their_top_small_frames_clamp(core: WowRuntime):
    core.execute(
        f"""
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(80, 20)
        pill = {S}.roundFill(holder, {S}.C.panel, "pill")
        head = CreateFrame("Frame", nil, UIParent)
        head:SetSize(200, 30)
        top = {S}.roundFill(head, {S}.C.header, "radius", nil, "top")
        tiny = CreateFrame("Frame", nil, UIParent)
        tiny:SetSize(8, 8)
        small = {S}.roundFill(tiny, {S}.C.panel, 20)
        """
    )
    assert core.eval("pill.r") == 10  # half the height
    core.execute("holder:SetSize(80, 24); pill:Layout()")
    assert core.eval("pill.r") == 12
    pieces = list(core.eval("top.pieces").values())
    assert pieces[0].GetTexture(pieces[0]).endswith("Disc")  # top-left: rounded
    assert pieces[2].GetTexture(pieces[2]) == "Interface\\Buttons\\WHITE8X8"  # bottom-left square
    assert core.eval("small.r") == 4  # never more than half the frame
    assert core.errors == []


def test_windows_buttons_and_menus_are_rounded(core: WowRuntime):
    core.execute(
        """
        win = Bastians.UI.Window("BastiansRoundTest", { title = "Round" })
        win:Show()
        button = Bastians.UI.Style.button(UIParent, "OK", 60, 20)
        """
    )
    is_shape = "getmetatable({}) == Bastians.UI.Style.Shape"
    assert core.eval(is_shape.format("win.frame.bg")) is True
    assert (
        core.eval(is_shape.format("win.head.bg")) is True
        and core.eval("win.head.bg.corners") == "top"
    )
    assert (
        core.eval(is_shape.format("button.face")) is True
        and core.eval("button.face.radius") == "radiusSmall"
    )
    # hiding and showing a shape keeps its layout
    core.execute("button.face:Hide()")
    assert core.eval("button.face:IsShown()") is False
    core.execute("button.face:Show()")
    pieces = list(core.eval("button.face.pieces").values())
    assert all(p.IsShown(p) for p in pieces[:5])
    assert core.errors == []
