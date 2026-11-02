"""Owner round 5 (retail, 31.10.2026), the Browser's lists: the monsters in a Mobs list of their
own; a filter box in the list pane that narrows the rows as you type; the chains' levels as chips;
the Quests list with the All quests view's Status and Type filters, which then covers that view."""

import re

from harness import WowRuntime
from pages import chip, chips, menu, pick, pills

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
TREE = f"{MOD}.tree"
SIZE = f"{TREE}.scroll:SetSize(440, 400); {TREE}:Refresh()"
BOX = f"{MOD}.filterBox"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{TREE}.flat").values()]


def open_list(wow: WowRuntime, typ: str) -> None:
    wow.execute(f"{BR}.List('{typ}')")
    wow.run_frames(10)
    wow.execute(SIZE)


def type_filter(wow: WowRuntime, text: str) -> None:
    wow.execute(f"{BOX}:SetText('{text}')")
    wow.execute(SIZE)


def test_the_monsters_have_their_own_list(wow: WowRuntime):
    boot(wow)
    open_list(wow, "mob")
    assert wow.eval(f"{MOD}.win.title:GetText()") == "Mobs"
    pick(wow, TREE, "where", "All")
    rows = flat(wow)
    assert "Hogger  11" in rows and "Goldtooth  8" in rows
    assert any(r.startswith("Edwin VanCleef") for r in rows)  # a boss is a monster too
    assert not any(r.startswith("Marshal Dughan") for r in rows)
    first = wow.eval(f"{TREE}.flat[1]")
    assert first.ref.startswith("npc:")  # the rows open the NPC's page
    assert pills(wow, TREE)[:2] == ["Where: All", "Rank: All"]
    open_list(wow, "npc")
    pick(wow, TREE, "where", "All")
    assert not any(r.startswith("Hogger") for r in flat(wow))
    assert wow.eval(f"{BR}.IsMob({{ flags = 'elite' }})") is True
    assert wow.eval(f"{BR}.IsMob({{ flags = 'vendor' }})") is False
    assert wow.eval(f"{BR}.IsMob({{ faction = 'A' }})") is False  # a guard belongs to a side
    assert wow.errors == []


def test_the_filter_box_narrows_the_rows_as_you_type(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    pick(wow, TREE, "where", "All")
    type_filter(wow, "far")
    assert flat(wow) == ["Innkeeper Farley  6"]
    assert strip(wow.eval(f"{MOD}.summary:GetText()")).startswith("1 of 1 shown")
    assert chips(wow)[0] == ("All", 1, True)  # the counts follow the text
    type_filter(wow, "")
    assert len(flat(wow)) == 6
    # another list starts without the text; Back brings the list and its text back
    type_filter(wow, "steele")
    assert flat(wow) == ["Corina Steele  15"]
    open_list(wow, "item")
    assert wow.eval(f"{BOX}:GetText()") == "" and len(flat(wow)) > 1
    wow.execute(f"{BR}.Back()")
    wow.execute(SIZE)
    assert wow.eval(f"{BOX}:GetText()") == "steele" and flat(wow) == ["Corina Steele  15"]
    # a view filters the rows it shows
    wow.slash("/bq log")
    wow.run_frames(5)
    wow.execute(SIZE)
    before = flat(wow)
    type_filter(wow, "zzzz")
    assert flat(wow) == [] and before != []
    assert wow.eval(f"{BOX}.count:GetText()") == "0"
    # the arrows and Enter work from the filter box too
    open_list(wow, "npc")
    type_filter(wow, "")
    wow.execute(f"{BOX}:GetScript('OnKeyDown')({BOX}, 'DOWN')")
    assert wow.eval(f"{TREE}:KeyIndex()") == 1
    assert wow.errors == []


def test_the_chains_levels_are_chips(wow: WowRuntime):
    boot(wow)
    assert (
        wow.eval(
            f"(function() for _, d in ipairs({BR}.Lists()) do if d.type == 'chain' then "
            f"return {BR}.Dims(d)[1].chips end end end)()"
        )
        is True
    )
    assert wow.errors == []


def test_the_quests_list_has_status_and_type(wow: WowRuntime):
    boot(wow)
    open_list(wow, "quest")
    pick(wow, TREE, "where", "All")
    labels = [c[0] for c in chips(wow)]
    assert labels[0] == "All" and "In log" in labels and "Blocked" in labels
    total = chips(wow)[0][1]
    chip(wow, "In log")
    wow.execute(SIZE)
    available = flat(wow)  # the two quests of the mock log
    assert 0 < len(available) < total
    assert "Type: All" in pills(wow, TREE)
    assert menu(wow, TREE, "quests.kind") == ["All  2", "Group  1", "Normal  1"]  # Hogger: a group
    # a quest event moves the status: the list builds again, the old rows stay meanwhile
    gen = wow.eval("Bastians:FilterGeneration('quests.status')")
    wow.execute("Bastians:Fire('BASTIANS_QUESTS_CHANGED')")
    assert wow.eval("Bastians:FilterGeneration('quests.status')") == gen + 1
    wow.execute(f"{BR}.Render()")
    wow.execute(SIZE)
    assert flat(wow) == available  # not "Building the list ..."
    wow.run_frames(10)
    wow.execute(SIZE)
    assert flat(wow) == available
    assert wow.eval(f"{BR}.listCache.quest.gen") == f"quests.status={gen + 1},quests.kind=1"
    assert wow.errors == []


def test_all_quests_builds_once_whatever_the_events(wow: WowRuntime):
    """Retail 31.10.2026: "All the quests does not load any quests after 60 sec": every quest
    event and every name that arrived started the build again. In Quests' own window (no Browser)
    a build that runs for the same filters now stays."""
    boot(wow)
    wow.execute(f"{MOD}:Disable()")
    wow.slash("/bq all")
    w = "Bastians:GetModule('Quests').Window"
    first = wow.eval(f"tostring({w}.allJob)")
    wow.execute(f"{w}.Render()")
    wow.execute("Bastians:Fire('BASTIANS_ENTITY_CHANGED')")
    wow.execute(f"{w}.Render()")
    assert wow.eval(f"tostring({w}.allJob)") == first
    wow.run_frames(20)
    assert wow.eval(f"{w}.allRows") is not None
    assert wow.errors == []
