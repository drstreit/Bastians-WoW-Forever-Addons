"""A map drawn whole (R4.5 of plan-book-round4.md, W7): Bastian's Book shows a zone with every
area's overlay, from the World pack's `zone.overlays` (the client's WorldMapOverlay tables), not
only what the reader's character uncovered; the Map keeps what the character explored."""

from harness import WowRuntime

COORDS = "Bastians.Coords"
MAP = 1429  # Elwynn Forest: in the mock's maps and in the fixture world


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute('Bastians:GetService("data"):LoadPack("world")')
    wow.run_frames(5)
    return wow


def test_a_zone_is_whole_where_the_pack_names_its_overlays(wow: WowRuntime):
    boot(wow)
    # the character explored one area; the pack names two, the second of two files
    wow.execute(
        f"""
        Mock.explored[{MAP}] = {{ {{ textureWidth = 256, textureHeight = 256, offsetX = 10, offsetY = 20,
          fileDataIDs = {{ 501 }} }} }}
        ZONE = Bastians:GetService("data"):Get("zone", {MAP}) -- held: the cache is weak
        ZONE.overlays = {{ {{ 335, 139, 256, 256, 7958233 }}, {{ 584, 139, 256, 288, 7958235, 7958236 }} }}
        """
    )
    assert wow.eval("ZONE ~= nil") is True
    infos = wow.eval(f"{COORDS}.WholeOverlays({MAP})")
    assert len(list(infos.values())) == 2
    second = infos[2]
    assert (second.offsetX, second.offsetY, second.textureWidth, second.textureHeight) == (
        584,
        139,
        256,
        288,
    )
    assert list(second.fileDataIDs.values()) == [7958235, 7958236]
    # as the Map asks: what the character explored
    explored = wow.eval(f"{COORDS}.MapArt({MAP})")
    assert explored.whole is None
    assert [t.file for t in explored.explored.values()] == [501]
    # as the book asks: every overlay of the pack, cut into the client's tiles
    whole = wow.eval(f"{COORDS}.MapArt({MAP}, true)")
    assert whole.whole is True
    assert [t.file for t in whole.explored.values()] == [7958233, 7958235, 7958236]
    last = list(whole.explored.values())[-1]
    assert (last.px1, last.py1, last.px2, last.py2) == (584, 139 + 256, 584 + 256, 139 + 288)
    assert wow.errors == []


def test_without_overlays_in_the_pack_the_explored_areas_stay(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        Mock.explored[{MAP}] = {{ {{ textureWidth = 256, textureHeight = 256, offsetX = 10, offsetY = 20,
          fileDataIDs = {{ 501 }} }} }}
        """
    )
    assert wow.eval(f"{COORDS}.WholeOverlays({MAP})") is None  # the fixture pack names none
    art = wow.eval(f"{COORDS}.MapArt({MAP}, true)")
    assert art.whole is None and [t.file for t in art.explored.values()] == [501]
    # a map the pack does not know, and no data service at all
    assert wow.eval(f"{COORDS}.WholeOverlays(999999)") is None
    assert wow.errors == []


def test_the_painting_cut_passes_the_wish_on(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        ASKED = {{}}
        local real = {COORDS}.MapArt
        {COORDS}.MapArt = function(map, whole)
          ASKED[#ASKED + 1] = whole == true
          return real(map, whole)
        end
        local f = CreateFrame("Frame", nil, UIParent)
        POOL = {{}}
        Bastians.UI.Scenery.DrawCut(f, POOL, {MAP}, 0.5, 0.5, 200, 100, 0.3, 1, nil, true)
        Bastians.UI.Scenery.DrawCut(f, POOL, {MAP}, 0.5, 0.5, 200, 100, 0.3, 1)
        Bastians.UI.Scenery.DrawBox(f, POOL, {MAP}, 0.2, 0.2, 0.6, 0.6, 200, 100, 1, true)
        """
    )
    assert list(wow.eval("ASKED").values()) == [True, False, True]
    assert wow.errors == []
