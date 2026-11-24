"""The Atlas with filters, its window part (W8 of plan-suite-waves.md, R4.12; book.md "The Atlas
with filters"; book-look.md 10.10): the band filters and is the legend, a disc opens its zone, the
card stands in the tooltip's place, tokens keep their size when the window grows; and what the
other addons lay on it, each only while it is there: Notes' layer, the suite's menu, a round with
the route service."""

from harness import WowRuntime
from test_atlas import WORLD
from test_book_pages import FRONT, MOD, WIN, boot

MAP = f"{MOD}.AtlasMap"
V = f"{WIN}.atlas"

ENTRIES = """
  E("story", "gold", "farming", 7, 0.5, 0.25, { page = true, levelMin = 20, levelMax = 24, hook = "A line." }),
  E("chain:x", "secrets", "chain", 7, 0.2, 0.2, { hook = "Never shown while sealed." }),
  E("chain:camp", "camp", "camping", 8, 0.5, 0.5),
  E("rare:1", "rares", "rare", 7, 0.3, 0.6, { npc = 1 }),
  E("rare:2", "rares", "rare elite", 7, 0.7, 0.4, { npc = 2 }),
  E("rare:3", "rares", "rare", 7, 0.8, 0.8, { npc = 3 }),
  E("mount:4", "collections", "mount", 7),
  E("rare:unseen", "rares", "rare", 12, 0.5, 0.5, { state = "unknown" }),
  E("rare:done", "rares", "rare", 13, 0.5, 0.5),
  E("title:1", "collections", "title"),
"""

HELPERS = f"""
function MARK(key)
  for _, b in ipairs({V}.marks) do
    if b:IsShown() and ((b.entry and b.entry.id == key) or (b.disc and b.disc.zone == key)
        or (b.pin and b.pin.label == key)) then
      return b
    end
  end
end
function WORDS()
  local out = {{}}
  for _, pool in pairs({V}.words) do
    for i = 1, pool.n do out[#out + 1] = pool[i]:GetText() end
  end
  for _, pool in pairs({V}.links) do
    for i = 1, pool.n do out[#out + 1] = pool[i].text:GetText() end
  end
  return out
end
function LINK(words)
  for _, pool in pairs({V}.links) do
    for i = 1, pool.n do
      if pool[i].text:GetText() == words then return pool[i] end
    end
  end
end
function PILL(label)
  for i = 1, {V}.npills do
    if {V}.pills[i].spec.label == label then return {V}.pills[i] end
  end
end
"""


def open_atlas(wow: WowRuntime, entries: str = ENTRIES, w: int = 1520, h: int = 800) -> None:
    """The Atlas over a small world of its own (test_atlas.WORLD) in place of the pack's."""
    boot(wow)
    wow.execute(WORLD + f"\nLIST = {{ {entries} }}" + HELPERS)
    wow.execute(
        f"""
        CTX.done["rare:done"] = true
        {FRONT}.Entries = function() return LIST end
        {FRONT}.Ctx = function() return CTX end
        {MAP}.Reset()
        """
    )
    wow.slash("/bbook map")
    render(wow, w, h)


def render(wow: WowRuntime, w: int = 1520, h: int = 800) -> None:
    wow.execute(f"{V}:SetSize({w}, {h}); {WIN}.Render()")


def marks(wow: WowRuntime) -> dict:
    out = {}
    for m in wow.eval(f"{MAP}.Marks()").values():
        out[m.id or m.zone or m.pin] = m
    return out


def words(wow: WowRuntime) -> list[str]:
    return [w.lower() for w in wow.eval("WORDS()").values() if w]


def test_the_band_filters_and_is_the_legend(wow: WowRuntime):
    open_atlas(wow)
    shown = marks(wow)
    # a page, a secret and a camp as themselves; the zone's three rares and its mount as one disc
    assert sorted(str(k) for k in shown) == ["7", "chain:camp", "chain:x", "story"]
    assert shown[7].form == "disc" and shown[7].count == 4
    assert shown["story"].form == "story" and shown["story"].size == 46
    assert shown["chain:x"].form == "seal" and shown["chain:camp"].form == "camp"
    assert wow.eval(f"{V}.count:GetText()") == "7 on the map, 1 without a place"
    # one row: the five chapters with their pictogram and count, level, unconfirmed
    assert wow.eval(f"{V}.bandH") == 41
    for label, count in (
        ("Gold", 1),
        ("Secrets", 1),
        ("Collections", 1),
        ("Camp", 1),
        ("Rares", 3),
    ):
        assert wow.eval(f"PILL('{label}').spec.count") == count, label
        assert wow.eval(f"PILL('{label}').spec.kind") is not None
    assert wow.eval("PILL('unconfirmed').spec.count") == 1
    assert wow.eval("PILL('My notes')") is None  # Notes is not installed
    assert wow.eval("PILL('rare')") is None  # a chapter's kinds only when it alone is chosen
    wow.execute("PILL('Rares').spec.onClick()")
    assert sorted(str(k) for k in marks(wow)) == ["7"]
    assert marks(wow)[7].count == 3
    assert wow.eval("PILL('Rares').spec.on") is True
    assert (
        wow.eval("PILL('rare').spec.count") == 2 and wow.eval("PILL('rare elite').spec.count") == 1
    )
    wow.execute("PILL('rare elite').spec.onClick()")
    assert sorted(str(k) for k in marks(wow)) == ["rare:2"]  # one wonder is itself, small
    assert marks(wow)["rare:2"].size == 26
    # unconfirmed and done: off until asked for
    wow.execute("PILL('rare elite').spec.onClick(); PILL('unconfirmed').spec.onClick()")
    assert "rare:unseen" in marks(wow)
    assert wow.eval("MARK('rare:unseen'):GetAlpha()") == 0.62
    assert "rare:done" not in marks(wow)
    assert wow.eval(f"{V}.done.text:GetText()") == "1 done, in Your diary"
    wow.execute(f"{V}.hide:Click()")
    assert "rare:done" in marks(wow)
    assert wow.eval("MARK('rare:done').stamp:IsShown()") is True
    assert wow.eval("MARK('rare:unseen').stamp:IsShown()") is False
    assert wow.errors == []


def test_a_disc_opens_its_zone_and_the_column_counts(wow: WowRuntime):
    open_atlas(wow)
    wow.execute("MARK(7):Click()")
    assert wow.eval(f"{MAP}.State().zone") == 7
    shown = marks(wow)
    assert sorted(shown) == ["chain:x", "rare:1", "rare:2", "rare:3", "story"]
    assert shown["rare:1"].size == 33  # in a zone a rare is its full size
    # the painting takes three quarters of the picture, the column one
    pw, ph = wow.eval(f"{V}.pw"), wow.eval(f"{V}.ph")
    col = pw // 4
    assert (
        wow.eval(f"{V}.column:GetWidth()") == col and wow.eval(f"{V}.paint:GetWidth()") == pw - col
    )
    assert shown["story"].x == col + 0.5 * (pw - col) and shown["story"].y == 0.25 * ph
    said = words(wow)
    assert "zone 7" in said and "6 wonders with this filter" in said
    assert "somewhere in the zone" in said and "mount:4" in said
    assert "they name the zone and no spot, so they get none." in said
    assert "a round" not in said and wow.eval(f"{V}.plan:IsShown()") is False  # no route service
    # the world's boards and its count are not a zone's
    assert wow.eval(f"{V}.boards.right:IsShown()") is False
    # back to the world
    wow.execute("LINK('< The world'):Click()")
    assert wow.eval(f"{MAP}.State().zone") is None and 7 in marks(wow)
    assert wow.eval(f"{V}.column:IsShown()") is False
    assert wow.errors == []


def test_what_has_no_place_stands_on_the_boards(wow: WowRuntime):
    open_atlas(
        wow,
        ENTRIES
        + """
        E("auction", "gold", "auction", nil, nil, nil, { page = true }),
        E("cooking", "gold", "trades", nil, nil, nil, { page = true }),
        """,
    )
    shown = marks(wow)
    assert shown["auction"].onBoard is True and shown["auction"].size == 33
    assert shown["cooking"].onBoard is True
    pw = wow.eval(f"{V}.pw")
    assert shown["auction"].x < pw * 0.17 + 10  # on the left board, in the ocean
    assert wow.eval(f"{V}.boards.left:IsShown()") is True
    said = words(wow)
    assert "the market" in said and "making and gathering" in said and "without a place" in said
    assert "collections" in said  # the title without a place: a row that opens its shelf
    wow.execute("LINK('Collections'):Click()")
    assert (
        wow.eval(f"{WIN}.Current().kind") == "shelf"
        and wow.eval(f"{WIN}.Current().id") == "collections"
    )
    assert wow.errors == []


def test_the_card_stands_in_the_tooltips_place(wow: WowRuntime):
    open_atlas(wow)
    card = f"{V}.card"
    wow.execute("B1 = MARK('story'); B1:GetScript('OnEnter')(B1)")
    assert wow.eval(f"{card}:IsShown()") is True and wow.eval(f"{card}:GetWidth()") == 232
    assert wow.eval(f"{card}.said.title") == "story" and wow.eval(f"{card}.said.line") == "A line."
    assert "level 20 to 24" in wow.eval(f"{card}.said.kind")
    assert wow.eval(f"{card}.said.foot").startswith("Click: open the page.")
    # under the mouse the ring is 2 wider and bright
    assert wow.eval("(select(4, B1.ring:GetPoint(1)))") == -5
    wow.execute("B1:GetScript('OnLeave')(B1)")
    assert wow.eval(f"{card}:IsShown()") is False
    assert wow.eval("(select(4, B1.ring:GetPoint(1)))") == -3
    # a sealed secret names nothing of its way
    wow.execute("B2 = MARK('chain:x'); B2:GetScript('OnEnter')(B2)")
    assert wow.eval(f"{card}.said.line") == "Sealed until you open its page."
    wow.execute("CTX.opened['chain:x'] = true")
    render(wow)
    wow.execute("B2 = MARK('chain:x'); B2:GetScript('OnEnter')(B2)")
    assert wow.eval(f"{card}.said.line") == "Never shown while sealed."
    assert wow.eval("B2.form.form") == "opened"
    # a zone's card counts its kinds, the most first
    wow.execute("B3 = MARK(7); B3:GetScript('OnEnter')(B3)")
    assert wow.eval(f"{card}.said.title") == "Zone 7"
    assert wow.eval(f"{card}.said.kind") == "a zone  -  4 wonders"
    assert wow.eval(f"{card}.said.line").startswith("2 ")
    assert wow.eval(f"{card}.said.foot").startswith("Click: the zone.")
    assert wow.errors == []


def test_a_right_click_opens_the_suites_menu(wow: WowRuntime):
    open_atlas(wow)
    wow.execute(
        "Bastians.UI.EntityMenu = function(ref, anchor, ctx) MENU = { ref = ref, ctx = ctx } end"
    )
    # a gold page with a spot: the spot is the menu's point (Show on map, Route here, a note here)
    wow.execute("local b = MARK('story'); b:GetScript('OnClick')(b, 'RightButton')")
    assert wow.eval("MENU.ref") == "zone:7" and wow.eval("MENU.ctx.source") == "strategies"
    assert wow.eval("MENU.ctx.point[4]") == "story"
    # a zone's disc: the zone
    wow.execute("local b = MARK(7); b:GetScript('OnClick')(b, 'RightButton')")
    assert wow.eval("MENU.ref") == "zone:7" and wow.eval("MENU.ctx.point") is None
    assert wow.eval(f"{MAP}.State().zone") is None  # a right click does not open the zone
    # a creature: the creature itself
    wow.execute(
        "MARK(7):Click(); local b = MARK('rare:1'); b:GetScript('OnClick')(b, 'RightButton')"
    )
    assert wow.eval("MENU.ref") == "npc:1" and wow.eval("MENU.ctx.point") is None
    # the zone's name is the book's link, with the menu on a right click
    wow.execute("local l = LINK('Zone 7'); l:GetScript('OnClick')(l, 'RightButton')")
    assert wow.eval("MENU.ref") == "zone:7"
    assert wow.errors == []


def test_notes_lie_on_the_atlas_as_a_layer(wow: WowRuntime):
    """ "my notes should be visible as layer if installed (and if there are
    any on the current view)". The Atlas asks Core for the layers; it knows no addon."""
    open_atlas(wow)
    wow.execute(
        f"""
        ASKED = 0
        Bastians:RegisterMapLayer({MOD}, {{ id = "notes.spots", label = "Notes", query = function(view)
          ASKED = ASKED + 1
          if view.continent ~= 0 then return {{}} end
          local _, wx, wy = CTX.worldOf(7, 0.4, 0.4)
          return {{ {{ wx = wx, wy = wy, label = "My spot", size = 20,
            card = function() return {{ title = "My spot", lines = {{ {{ text = "Fish here." }} }}, hint = "Click to edit" }} end,
            onClick = function() CLICKED = true end }} }}
        end }})
        Bastians:RegisterMapLayer({MOD}, {{ id = "notes.shared", label = "From others",
          query = function() error("a layer that fails") end }})
        Bastians:RegisterMapLayer({MOD}, {{ id = "quests.givers", label = "Not hosted",
          query = function() OTHER = true; return {{}} end }})
        """
    )
    render(wow)
    assert wow.eval("ASKED") == 2  # once a continent, when the view settled
    assert wow.eval("OTHER") is None  # a layer the Atlas does not host is never asked
    assert (
        wow.eval("PILL('My notes').spec.count") == 1
        and wow.eval("PILL('My notes').spec.on") is True
    )
    pin = marks(wow)["My spot"]
    assert pin.form == "pin" and pin.size == 20
    # the layer's own card and its own click
    wow.execute("P = MARK('My spot'); P:GetScript('OnEnter')(P)")
    assert wow.eval(f"{V}.card.said.title") == "My spot"
    assert wow.eval(f"{V}.card.said.line") == "Fish here."
    assert wow.eval(f"{V}.card.said.foot") == "Click to edit"
    assert wow.eval(f"{V}.card.said.kind") == "Notes"
    wow.execute("P:Click()")
    assert wow.eval("CLICKED") is True
    # in its zone the note lies on the painting; in another zone the chip is gone
    wow.execute(f"{MAP}.OpenZone(7)")
    pw, ph = wow.eval(f"{V}.pw"), wow.eval(f"{V}.ph")
    col = pw // 4
    pin = marks(wow)["My spot"]
    assert abs(pin.x - (col + 0.4 * (pw - col))) < 1e-6 and abs(pin.y - 0.4 * ph) < 1e-6
    wow.execute(f"{MAP}.OpenZone(8)")
    assert wow.eval("PILL('My notes')") is None and "My spot" not in marks(wow)
    # the chip switches the layer
    wow.execute(f"{MAP}.OpenWorld(); PILL('My notes').spec.onClick()")
    assert "My spot" not in marks(wow) and wow.eval("PILL('My notes').spec.on") is False
    wow.execute("PILL('My notes').spec.onClick()")
    assert "My spot" in marks(wow)
    assert wow.errors == []


def test_a_round_goes_to_the_route_service(wow: WowRuntime):
    """ "we can define a route". With the route service a zone has a round:
    the wonders shown or the stops picked, the nearest first, at most twelve."""
    open_atlas(wow)
    wow.execute(
        f"""
        Bastians:ProvideService({MOD}, "route", {{
          Tour = function(self, stops, name) TOUR = {{ stops = stops, name = name }} return true end,
        }}, {{ priority = 100 }})
        {MAP}.OpenZone(7)
        """
    )
    assert wow.eval(f"{V}.plan:IsShown()") is True and wow.eval(f"{V}.forget:IsShown()") is False
    said = words(wow)
    assert "a round" in said
    assert "through the 5 shown, the nearest first. shift and a click picks single stops." in said
    assert wow.eval("MARK('rare:1').no:IsShown()") is False  # no numbers before a round
    wow.execute(f"{V}.plan:Click()")
    assert wow.eval("#TOUR.stops") == 5 and wow.eval("TOUR.name") == "Zone 7: a round"
    assert (
        wow.eval("TOUR.stops[1].place.map") == 0 and wow.eval("TOUR.stops[1].place.wx") is not None
    )
    assert wow.eval(f"{MAP}.State().planned") == 7
    assert "route has the round: 5 stops." in words(wow)
    assert wow.eval(f"{V}.plan:IsShown()") is False
    numbers = sorted(
        wow.eval(f"MARK('{i}').no.text:GetText()")
        for i in ("story", "chain:x", "rare:1", "rare:2", "rare:3")
    )
    assert numbers == ["1", "2", "3", "4", "5"]
    # single stops: shift and a click
    wow.execute("IsShiftKeyDown = function() return true end")
    wow.execute("MARK('rare:1'):Click()")
    wow.execute("MARK('rare:3'):Click()")
    assert wow.eval(f"{MAP}.State().planned") is None
    assert wow.eval(f"{WIN}.Current().kind") == "atlas"  # the click picked, it opened no page
    assert (
        "through your 2 stops, the nearest first. shift and a click picks single stops."
        in words(wow)
    )
    assert (
        wow.eval("MARK('rare:1').no:IsShown()") is True
        and wow.eval("MARK('rare:2').no:IsShown()") is False
    )
    wow.execute(f"{V}.plan:Click()")
    assert wow.eval("#TOUR.stops") == 2
    ids = sorted(wow.eval(f"TOUR.stops[{i}].id") for i in (1, 2))
    assert ids == ["rare:1", "rare:3"] and wow.eval("TOUR.stops[1].ref") in ("npc:1", "npc:3")
    # forget them: the round is the zone's again
    wow.execute("MARK('rare:2'):Click()")
    assert wow.eval(f"{V}.forget:IsShown()") is True
    wow.execute(f"{V}.forget:Click()")
    assert wow.eval(f"next({MAP}.State().picked)") is None
    assert wow.errors == []


def test_a_round_holds_twelve_stops(wow: WowRuntime):
    rares = "\n".join(
        f'E("rare:{i:02d}", "rares", "rare", 7, 0.{i:02d}, 0.5),' for i in range(5, 95, 5)
    )
    open_atlas(wow, rares)
    wow.execute(
        f"""
        Bastians:ProvideService({MOD}, "route", {{
          Tour = function(self, stops) TOUR = stops return true end,
        }}, {{ priority = 100 }})
        {MAP}.OpenZone(7)
        """
    )
    assert (
        "through the 12 nearest of the 18 shown: a round holds no more. shift and a click picks single stops."
        in (words(wow))
    )
    wow.execute(f"{V}.plan:Click()")
    assert wow.eval("#TOUR") == 12
    assert wow.errors == []


def test_tokens_keep_their_size_when_the_window_grows(wow: WowRuntime):
    open_atlas(wow, w=928, h=560)
    band = wow.eval(f"{V}.bandH")
    assert wow.eval(f"{V}.pw") == 928 and wow.eval(f"{V}.ph") == 464
    small = marks(wow)["story"]
    # while the grip is held the picture scales as one piece: one SetScale, no new layout
    wow.execute(f"{V}:SetSize(1800, 600); {V}:GetScript('OnSizeChanged')({V})")
    assert wow.eval(f"{V}.picture:GetWidth()") == 928
    assert abs(wow.eval(f"{V}.picture:GetScale()") - (600 - band) * 2 / 928) < 1e-9
    # when the size settles the picture is laid out anew, the tokens at their own size
    wow.execute(f"{WIN}.Render()")
    assert wow.eval(f"{V}.picture:GetScale()") == 1
    assert wow.eval(f"{V}.pw") == (600 - wow.eval(f"{V}.bandH")) * 2  # the wider band is one row
    large = marks(wow)["story"]
    assert large.size == small.size == 46
    assert large.x > small.x
    # the count and the mill are no part of the land
    assert wow.eval(f"{V}.mill:GetParent() == {V}.room") is True
    assert wow.eval(f"{V}.countPlate:GetParent() == {V}.room") is True
    assert wow.errors == []


def test_the_window_takes_the_maps_shape_under_the_band(wow: WowRuntime):
    open_atlas(wow, w=928, h=560)
    wow.execute(f"{WIN}.win.frame:SetSize(1200, 700); {V}:SetSize(1188, 620)")
    wow.execute(f"{WIN}.win.opts.onResize(nil, false)")
    w, h = wow.eval(f"{WIN}.win.frame:GetSize()")
    band = wow.eval(f"{V}.bandH")
    assert (w, h) == (1200, 1188 / 2 + 80 + band)  # the window adds 80 and the band
    assert wow.errors == []


def test_the_routes_line_and_a_trail_are_dots(wow: WowRuntime):
    open_atlas(
        wow,
        ENTRIES
        + """
        E("chain:open", "secrets", "chain", 7, 0.1, 0.9,
          { steps = { { place = { 7, 0.1, 0.9 } }, { place = { 7, 0.6, 0.9 } } } }),
        """,
    )
    wow.execute(
        f"""
        CTX.opened["chain:open"] = true
        ASKED = 0
        Bastians:RegisterMapLayer({MOD}, {{ id = "route.path", label = "Route", query = function(view)
          ASKED = ASKED + 1
          if view.continent ~= 0 then return {{}} end
          local _, ax, ay = CTX.worldOf(7, 0.2, 0.2)
          local _, bx, by = CTX.worldOf(7, 0.9, 0.3)
          return {{ {{ kind = "path", points = {{ {{ ax, ay }}, {{ bx, by }} }} }} }}
        end }})
        function SHOWN(pool)
          local n = 0
          for _, t in ipairs(pool) do if t:IsShown() then n = n + 1 end end
          return n
        end
        """
    )
    render(wow)
    assert wow.eval(f"SHOWN({V}.lineDots)") > 0  # Route's line on the world
    assert wow.eval(f"SHOWN({V}.hoverDots)") == 0
    # an opened secret's trail on the world: while the mouse is on its token
    wow.execute("T = MARK('chain:open'); T:GetScript('OnEnter')(T)")
    assert wow.eval(f"SHOWN({V}.hoverDots)") > 0
    wow.execute("T:GetScript('OnLeave')(T)")
    assert wow.eval(f"SHOWN({V}.hoverDots)") == 0
    # in the zone its steps stand numbered, and the line is longer there
    world_dots = wow.eval(f"SHOWN({V}.lineDots)")
    wow.execute(f"{MAP}.OpenZone(7)")
    assert wow.eval(f"{V}.nsteps") == 2 and wow.eval(f"{V}.steps[2].text:GetText()") == "2"
    assert wow.eval(f"SHOWN({V}.lineDots)") > world_dots
    # a change of a hosted layer asks again; another layer's change does not
    asked = wow.eval("ASKED")
    wow.execute('Bastians:Fire("BASTIANS_LAYER_CHANGED", "quests.givers")')
    wow.advance(0.2)
    wow.run_frames(3)
    assert wow.eval("ASKED") == asked
    wow.execute('Bastians:Fire("BASTIANS_LAYER_CHANGED", "route.path")')
    wow.advance(0.2)
    wow.run_frames(3)
    assert wow.eval("ASKED") > asked
    assert wow.errors == []


def test_the_game_keeps_the_mockups_look(wow: WowRuntime):
    """ "your mockups are really good looking, make sure that we stick to
    them in game as much as possible"."""
    open_atlas(wow)
    # the chips are the legend: a token's small copy stands where Core's pill has its tile
    for label in ("Gold", "Secrets", "Collections", "Camp", "Rares"):
        assert wow.eval(f"PILL('{label}').mark:IsShown()") is True, label
        assert wow.eval(f"PILL('{label}').tile:IsShown()") is False, label
    assert wow.eval("PILL('any').mark") is None
    assert wow.eval("PILL('Gold').mark.outer:IsShown()") is True  # a ring around a drawing
    assert wow.eval("PILL('Collections').mark.mat:IsShown()") is True  # the album's frame
    assert wow.eval("PILL('Camp').mark.glyph:IsShown()") is True  # the flame
    # a row of the board *Without a place* carries its chapter's mark too
    assert wow.eval(f"{V}.nlegends") == 1 and wow.eval(f"{V}.legends[1]:IsShown()") is True
    # the seal wears Bastian's crest
    assert wow.eval("MARK('chain:x').glyph:GetTexture()").endswith("Crest")
    # an unconfirmed token: dimmed, in a ring of dots; no other token has one
    wow.execute("PILL('unconfirmed').spec.onClick()")
    assert wow.eval("#MARK('rare:unseen').dashes") == 18
    assert wow.eval("MARK('rare:unseen').dashes[1]:IsShown()") is True
    assert wow.eval("MARK('story').dashes") is None
    # the character is an arrow on the world and in his zone, and gone where he is not
    wow.execute(
        """
        local c, wx, wy = CTX.worldOf(7, 0.25, 0.75)
        CTX.here = { map = 7, continent = c, wx = wx, wy = wy }
        """
    )
    render(wow)
    you = f"{V}.you"
    assert wow.eval(f"{you}:IsShown()") is True and wow.eval(f"{you}.face:GetTexture()").endswith(
        "Arrow"
    )
    pw, ph = wow.eval(f"{V}.pw"), wow.eval(f"{V}.ph")
    wow.execute(f"{MAP}.OpenZone(7)")
    col = pw // 4
    assert abs(wow.eval(f"{you}.x") - (col + 0.25 * (pw - col))) < 1e-6
    assert abs(wow.eval(f"{you}.y") - 0.75 * ph) < 1e-6
    said = words(wow)
    assert any(line.startswith("you are here") for line in said)
    # the zone's rows carry their marks
    assert wow.eval(f"{V}.nlegends") == 4  # gold, secrets, collections, rares
    wow.execute(f"{MAP}.OpenZone(8)")
    assert wow.eval(f"{you}:IsShown()") is False
    # a rare's card shows its model: the mockup's word for a token without a round portrait
    wow.execute(f"{MAP}.OpenZone(7); R = MARK('rare:1'); R:GetScript('OnEnter')(R)")
    card = f"{V}.card"
    if wow.eval(f"{card}.model ~= nil"):
        assert (
            wow.eval(f"{card}.model:IsShown()") is True
            and wow.eval(f"{card}.mat:IsShown()") is True
        )
        assert wow.eval(f"{card}.model:GetHeight()") == 104
    wow.execute("S1 = MARK('story'); S1:GetScript('OnEnter')(S1)")
    assert wow.eval(f"{card}.mat:IsShown()") is False
    # the card's foot names what a right click offers, in the menu's own words
    wow.execute(
        f"""
        Bastians:RegisterAction({MOD}, {{ id = "test.show", label = "Show on map", types = {{ "zone" }},
          order = 10, run = function() end }})
        Bastians:RegisterAction({MOD}, {{ id = "test.note", label = "Add a note here", types = {{ "zone" }},
          order = 60, run = function() end }})
        S1:GetScript('OnEnter')(S1)
        """
    )
    foot = wow.eval(f"{card}.said.foot")
    assert foot.startswith("Click: open the page. Right click: Show on map, ") and foot.endswith(
        "."
    )
    assert "Add a note here" in foot
    assert wow.errors == []


def test_a_rare_is_its_round_portrait_once_the_client_answered(wow: WowRuntime):
    """ADR 0090: the mockup's token.
    Until the client has answered a creature's display, the suite's rare pictogram stands."""
    open_atlas(wow)
    wow.execute(
        """
        SetPortraitTextureFromCreatureDisplayID = function(texture, id) texture:SetTexture("portrait:" .. id) end
        Mock.displays = { [2] = 222 }
        """
    )
    wow.execute(f"{MAP}.OpenZone(7)")
    # asked for, one creature after the other: the pictogram until the answer
    assert (
        wow.eval("MARK('rare:1').glyph:IsShown()") is True
        and wow.eval("MARK('rare:1').portrait") is None
    )
    assert wow.eval("MARK('rare:2').glyph:IsShown()") is True
    model = f"{MOD}.Portrait.Model()"
    assert wow.eval(f"{model}.creature") == 1
    marks_before = wow.eval(f"{V}.nmarks")
    wow.execute(f"local m = {model}; m.display = 111; m:GetScript('OnModelLoaded')(m)")
    wow.run_frames(2)
    # the token turns into the portrait where it stands, without a new layout
    assert wow.eval("MARK('rare:1').pic:GetTexture()") == "portrait:111"
    assert wow.eval("MARK('rare:1').pic:IsShown()") is True
    assert (
        wow.eval("MARK('rare:1').glyph:IsShown()") is False
        and wow.eval(f"{V}.nmarks") == marks_before
    )
    # the next one's turn came with it, and the client knew that one at once
    assert wow.eval("MARK('rare:2').pic:GetTexture()") == "portrait:222"
    assert wow.eval("MARK('rare:2').glyph:IsShown()") is False
    # a new layout keeps the portraits: they are known now
    render(wow)
    assert (
        wow.eval("MARK('rare:2').portrait") is True
        and wow.eval("MARK('rare:2').glyph:IsShown()") is False
    )
    # a token with its portrait has the mockup's card: no model on it
    wow.execute("R1 = MARK('rare:1'); R1:GetScript('OnEnter')(R1)")
    assert wow.eval(f"{V}.card.mat:IsShown()") is False
    # another form never takes a portrait
    assert wow.eval("MARK('story').portrait") is None
    assert wow.errors == []
