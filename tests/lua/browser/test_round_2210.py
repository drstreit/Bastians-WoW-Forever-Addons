"""The owner's retail round of 22.10.2026 (roadmap "Owner feedback"): the type bar on every entry
(no Home click for the categories), slim mode as the tracker (the log view alone), a map button
on every quest and NPC row, "Show on map" fitting a quest's giver and targets or an NPC's spawn
areas."""

import re

from harness import WowRuntime
from pages import band, nav_active, nav_click, nav_lists

CORE, DATA, QUESTS, MAP, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
MAP_ = "Bastians:GetModule('Map').Map"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def test_the_navigation_is_there_on_every_entry(wow: WowRuntime):
    """The type bar of 22.10.2026 became the navigation's Lists (ADR 0018): there on a page, a
    list and a view, the shown list accented."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")  # a page: the navigation is there, Here accented
    assert nav_lists(wow) == [  # by name
        "Farm spots",
        "Items",
        "NPCs",
        "Nodes",
        "Objects",
        "Quest chains",
        "Quests",
        "Recipes",
        "Zones",
    ]
    assert wow.eval(f"{MOD}.nav:IsShown()") is True and nav_active(wow) == "nav:here"
    nav_click(wow, "nav:list:npc")  # NPCs, from the page, without Home
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().kind") == "list" and wow.eval(f"{BR}.Current().type") == "npc"
    assert nav_active(wow) == "nav:list:npc"
    assert band(wow, f"{MOD}.dossier")["name"] == "Marshal Dughan"  # the page stays beside it
    wow.slash("/bq log")
    assert wow.eval(f"{MOD}.nav:IsShown()") is True  # a view too
    assert nav_active(wow) == "nav:view:quests.log"
    assert wow.errors == []


def test_slim_is_the_tracker(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{BR}.SetSlim(true)")
    assert (
        wow.eval(f"{BR}.Current().kind") == "view"
        and wow.eval(f"{BR}.Current().id") == "quests.log"
    )
    assert (
        wow.eval(f"{MOD}.nav:IsShown()") is False and wow.eval(f"{MOD}.listPane:IsShown()") is True
    )
    assert (
        wow.eval(f"{MOD}.toolbar:IsShown()") is False
        and wow.eval(f"{MOD}.search:IsVisible()") is False
    )
    assert wow.eval(f"{MOD}.detailPane:IsShown()") is False
    assert wow.eval(f"{MOD}.win.frame:GetWidth()") == 260
    texts = [strip(r.text) for r in wow.eval(f"{MOD}.tree.flat").values()]
    assert texts[0] == "HAND IN HERE  1"  # the log view with its objectives
    # the target does not take the tracker over
    wow.execute('Mock.guids = { target = "Creature-0-4469-0-12-54-0000ABCDEF" }')
    wow.fire("PLAYER_TARGET_CHANGED")
    assert wow.eval(f"{BR}.Current().id") == "quests.log"
    # Wide brings the page back; a row click in the tracker widens and opens the page
    wow.execute(f"{BR}.SetSlim(false)")
    assert wow.eval(f"{BR}.Current().ref") == "npc:240" and wow.eval(f"{MOD}.nav:IsShown()") is True
    wow.execute(f"{BR}.SetSlim(true)")
    wow.execute(f"{BR}.Open('quest:62')")
    assert wow.eval(f"{BR}.IsSlim()") is False and wow.eval(f"{BR}.Current().ref") == "quest:62"
    assert wow.errors == []


def test_rows_show_their_map_button_without_a_hover(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, MAP, BROWSER)
    wow.execute(f"{BR}.Open('npc:240')")
    icons = wow.eval(
        f"""(function()
          local out = {{}}
          for _, bf in ipairs({MOD}.dossier.blockPool) do
            if bf:IsShown() then
              for _, f in ipairs(bf.tree.pool) do
                if f:IsShown() and f.row and f.row.ref then
                  local ids = {{}}
                  for _, b in ipairs(f.icons) do if b:IsShown() and b.action then ids[#ids + 1] = b.action.id end end
                  out[#out + 1] = f.row.ref .. "=" .. table.concat(ids, ",")
                end
              end
            end
          end
          return table.concat(out, ";")
        end)()"""
    )
    assert "quest:62=map.show" in icons  # the quest row's map button, shown without a hover
    assert band(wow, f"{MOD}.hereDossier")["name"] == "Elwynn Forest"
    assert wow.errors == []


def test_show_on_map_fits_a_quests_places_and_an_npcs_areas(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, MAP)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    # a quest has places now: its giver, its targets, its hand-in
    kinds = [p.kind for p in wow.eval("Bastians:Entity('quest:176'):AllLocations()").values()]
    assert kinds[0] == "giver" and kinds[-1] == "turnin" and "objective" in kinds
    assert wow.eval("Bastians:RunAction('map.show', 'quest:62', { source = 'test' })") is True
    # Hogger's two spawns (0.27,0.86) and (0.3,0.8): the view centres between them
    wow.execute("Bastians:RunAction('map.show', 'npc:448', { source = 'test' })")
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (round(cam.wx), round(cam.wy)) == (-132, 86)  # the box centre of the two places
    assert cam.level >= 5
    # one place: the camera flies there as before
    wow.execute("Bastians:RunAction('map.show', 'npc:240', { source = 'test' })")
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (round(cam.wx), round(cam.wy)) == (-60, 32)
    assert wow.errors == []
