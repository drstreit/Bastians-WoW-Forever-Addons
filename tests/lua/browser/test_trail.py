"""Links and the trail (C5, ADR 0014): the links region leads from page to page, the trail under it
is the way here as breadcrumbs (the last eight pages), a click goes back to that point and drops
what came after; Back and Forward keep working."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def trail(wow: WowRuntime) -> list[str]:
    return [i.name for i in wow.eval(f"{BR}.Trail()").values()]


def drawn(wow: WowRuntime) -> list[str]:
    return [
        strip(b.label.GetText(b.label))
        for b in wow.eval(f"{DS}.trailPool").values()
        if b.IsShown(b)
    ]


def test_the_trail_grows_with_every_page_and_a_click_goes_back_to_that_point(wow: WowRuntime):
    boot(wow)
    for ref in ("zone:1429", "npc:240", "quest:62", "item:2589", "npc:448"):
        wow.execute(f"{BR}.Open('{ref}')")
    assert trail(wow) == [
        "Elwynn Forest",
        "Marshal Dughan",
        "The Fargodeep Mine",
        "Linen Cloth",
        "Hogger",
    ]
    assert wow.eval(f"{DS}.trail:IsShown()") is True
    assert drawn(wow) == [
        "Elwynn Forest",
        "> Marshal Dughan",
        "> The Fargodeep Mine",
        "> Linen Cloth",
        "> Hogger",
    ]
    # the middle: back there, what came after is gone, Forward has nothing
    wow.execute(f"{DS}.trailPool[3]:Click()")
    assert wow.eval(f"{BR}.Current().ref") == "quest:62"
    history, cursor = wow.eval(f"{BR}.History()")
    assert [h.ref for h in history.values()] == ["zone:1429", "npc:240", "quest:62"] and cursor == 3
    assert trail(wow) == ["Elwynn Forest", "Marshal Dughan", "The Fargodeep Mine"]
    wow.execute(f"{BR}.Forward()")
    assert wow.eval(f"{BR}.Current().ref") == "quest:62"
    # Back and Forward still walk the history; the trail follows the cursor
    wow.execute(f"{BR}.Back()")
    assert wow.eval(f"{BR}.Current().ref") == "npc:240"
    assert trail(wow) == ["Elwynn Forest", "Marshal Dughan"]
    wow.execute(f"{BR}.Forward()")
    assert trail(wow) == ["Elwynn Forest", "Marshal Dughan", "The Fargodeep Mine"]
    assert wow.errors == []


def test_lists_are_not_on_the_trail_and_it_keeps_the_last_eight(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('npc:240')")
    wow.execute(f"{BR}.List('npc')")
    wow.execute(f"{BR}.Open('npc:448')")
    assert trail(wow) == ["Marshal Dughan", "Hogger"]  # the list in between is no breadcrumb
    for i in range(1, 11):
        wow.execute(f"{BR}.Open('quest:{i}')")
    names = trail(wow)
    assert (len(names) == 8 and names[-1] == "Quest 10") or names[-1].endswith("10")
    assert "Marshal Dughan" not in names
    # a link chip opens its page and extends the trail (the chips are the links region, C2)
    wow.execute(f"{BR}.Open('quest:62')")
    assert wow.eval(f"{DS}.chipCount") > 0
    wow.execute(f"{DS}.chipPool[1]:Click('LeftButton')")
    assert wow.eval(f"{BR}.Current().ref") != "quest:62"
    assert trail(wow)[-2] == "The Fargodeep Mine"
    assert wow.errors == []


def test_trail_lines_start_right_of_the_label(wow: WowRuntime):
    """the label keeps its column; every crumb line starts right of it."""
    boot(wow)
    wow.slash("/bb")
    wow.execute(
        f"{MOD}.win.frame:SetSize(700, 560); {MOD}.win.frame:GetScript('OnSizeChanged')({MOD}.win.frame)"
    )
    for ref in ("npc:240", "quest:176", "npc:448", "item:2589", "zone:1429", "npc:240", "quest:62"):
        wow.slash(f"/bb {ref}")
        wow.run_frames(3)
    buttons = [b for b in wow.eval(f"{DS}.trailPool").values() if b.IsShown(b)]
    assert len(buttons) >= 6
    points = [b.GetPoint(b, 1) for b in buttons]
    xs, ys = [p[3] for p in points], [p[4] for p in points]
    assert len(set(ys)) >= 2  # more than one line
    assert min(xs) == xs[0] > 0  # no line starts under the label
    assert wow.errors == []
