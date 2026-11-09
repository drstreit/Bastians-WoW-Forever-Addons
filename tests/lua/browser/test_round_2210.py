"""The owner's retail round of 22.10.2026 (roadmap "Owner feedback"): the type bar on every entry
(no Home click for the categories), ~~slim mode as the tracker~~ (gone with ADR 0056), a map button
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


def test_a_list_known_to_be_empty_has_no_button(wow: WowRuntime):
    """ADR 0054, B14 (kept by ADR 0056): a list with no rows stays hidden. Known means the pack
    is loaded and holds no record of the type; a pack not loaded yet is unknown, and its list
    shows. The list in the list tile keeps its button, and rows bring a button back."""
    boot(wow)
    wow.execute(f"{BR}.Open()")
    data = "Bastians:GetService('data')"
    # the fixture world has no gathering nodes; the farm spots' pack is not loaded: unknown
    assert wow.eval(f"{data}:Any('node')") is False and wow.eval(f"{data}:Any('npc')") is True
    assert wow.eval(f"{data}:Any('spot')") is None
    assert "Gathering" not in nav_lists(wow) and "Farm spots" in nav_lists(wow)
    assert wow.eval(f"{data}:Any('no such type')") is None  # unknown is not "none"
    empty = f"{BR}.ListIsEmpty"
    assert wow.eval(f"{empty}({{ type = 'node' }})") is True
    assert wow.eval(f"{empty}({{ type = 'mob', entity = 'npc' }})") is False
    assert wow.eval(f"{empty}({{ type = 'no such type' }})") is False
    # a registered list says it itself, or is shown
    assert wow.eval(f"{empty}({{ type = 'x', ids = function() return {{}} end }})") is False
    assert wow.eval(f"{empty}({{ type = 'x', empty = function() return true end }})") is True
    # the list that is shown keeps its button
    wow.execute(f"{BR}.List('node')")
    wow.run_frames(5)
    assert "Gathering" in nav_lists(wow) and nav_active(wow) == "nav:list:node"
    assert wow.errors == []


def test_the_navigation_is_there_on_every_entry(wow: WowRuntime):
    """The type bar of 22.10.2026 became the navigation's Lists (ADR 0018): there on a page, a
    list and a view, the shown list accented."""
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")  # a page: the navigation is there, Here accented
    assert nav_lists(wow) == [
        "Quests",
        "Chains",
        "Zones",
        "People",
        "Monsters",
        "Objects",
        "Dungeons",
        "Items",
        "Recipes",
        "Farm spots",  # its pack is not loaded here: unknown, so shown
    ]
    assert wow.eval(f"{MOD}.rail:IsShown()") is True and wow.eval(f"{MOD}.rail.active") == "here"
    nav_click(wow, "nav:list:npc")  # NPCs, from the page, without Home
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Current().kind") == "list" and wow.eval(f"{BR}.Current().type") == "npc"
    assert nav_active(wow) == "nav:list:npc"
    assert band(wow, f"{MOD}.dossier")["name"] == "Marshal Dughan"  # the page stays beside it
    wow.slash("/bq log")
    assert wow.eval(f"{MOD}.rail:IsShown()") is True  # a view too
    assert nav_active(wow) == "nav:view:quests.log"
    assert wow.errors == []


def test_a_sheets_rows_are_quiet_until_the_mouse_is_on_them(wow: WowRuntime):
    """ADR 0054: no icons on a row at rest, where the round of
    22.10.2026 showed the map button on every row. They show under the mouse and on the focused
    row; every action stays in the entity menu."""
    boot(wow, CORE, DATA, QUESTS, MAP, BROWSER)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute("Bastians:GetModule('Browser').Browser.SetListOpen(true)")  # out (R25.36)
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
    assert "quest:62=" in icons and "map.show" not in icons  # the rows are there, quiet
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
