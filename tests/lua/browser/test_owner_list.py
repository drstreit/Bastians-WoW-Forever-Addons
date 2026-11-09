"""the farm spots' words and their way into the book, Gold Stories,
All Notes, the mini maps' own style."""

from harness import WowRuntime
from pages import nav_lists

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"
TREE = f"{MOD}.tree"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER, *addons)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def test_all_notes_lists_every_thing_with_a_note(wow: WowRuntime):
    boot(wow, "Bastians_Notes")
    notes = "Bastians:GetModule('Notes').Notes"
    wow.execute(f"{BR}.Open()")
    wow.run_frames(3)
    assert "All Notes" in nav_lists(wow)
    wow.execute(f"{notes}.Save({{ on = 'npc:240', title = 'Sells nothing good' }})")
    wow.execute(f"{notes}.Save({{ on = 'npc:240', title = 'A second one' }})")
    wow.execute(
        f"{notes}.Save({{ on = {{ map = 0, wx = -9460, wy = 60 }}, title = 'Chest', text = 'A hidden chest' }})"
    )
    wow.execute(f"{BR}.List('note')")
    wow.run_frames(20)
    rows = [r for r in wow.eval(f"{TREE}.flat").values() if r.ref]
    refs = [r.ref for r in rows]
    assert "npc:240" in refs and len(rows) == 2  # one row per thing
    spot = next(r for r in rows if r.ref != "npc:240")
    assert spot.ref.startswith("note:")
    # a note on a spot of the world: its page is its text
    wow.execute(f"{BR}.Open('{spot.ref}')")
    wow.run_frames(5)
    data = wow.eval(f"Bastians.UI.DossierData('{spot.ref}', nil, {{ source = 'browser' }})")
    words = [
        str(r.text)
        for c in data.chapters.values()
        for b in c.blocks.values()
        for r in b.rows.values()
    ]
    assert "A hidden chest" in words
    assert wow.errors == []


def test_the_mini_maps_have_a_style_of_their_own(wow: WowRuntime):
    boot(wow, "Bastians_Map")
    sc = "Bastians.UI.Scenery"
    wow.execute(f"{sc}.SetStyle('map')")
    assert wow.eval(f"{sc}.style") is None
    wow.execute(f"{sc}.SetStyle('pencil')")
    assert wow.eval(f"{sc}.style") == "pencil"
    wow.execute(f"{sc}.SetStyle('physical')")
    assert wow.eval(f"{sc}.style") == "physical"
    wow.execute(f"{sc}.SetStyle(nil)")
    assert wow.eval("Bastians:GetService('mapPicture'):Styles()") is not None
    values = wow.eval(
        f"(function() for _, o in ipairs({MOD}.options) do"
        " if o.key == 'miniMapStyle' then return o.values() end end end)()"
    )
    assert set(dict(values.items())) >= {"map", "physical"}
    assert wow.errors == []
