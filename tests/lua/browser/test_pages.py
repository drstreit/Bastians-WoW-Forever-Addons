"""Pages, not scrolls (ADR 0058, PH3): the list tile shows a page of as many tiles as fit its
height; the foot says where you are, its arrows, the wheel and the page keys turn the page; a new
list or a filter opens on the first page; the pool is the page."""

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
TREE = f"{MOD}.tree"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def rows(wow: WowRuntime, n: int, prefix: str = "r") -> None:
    wow.execute(
        f"""
        local refs = {{ "npc:240", "quest:62", "item:2589", "zone:1429", "npc:448", "quest:76", "npc:295" }}
        PAGE_ROWS = {{}}
        for i = 1, {n} do
          PAGE_ROWS[i] = {{ id = "{prefix}:" .. i, ref = refs[(i - 1) % #refs + 1], text = "Row " .. i }}
        end
        {TREE}:SetRows(PAGE_ROWS)
        """
    )
    wow.run_frames(2)


def page(wow: WowRuntime) -> tuple[int, int, int, int, int]:
    return tuple(wow.eval(f"{{ {TREE}:Page() }}").values())


def test_a_page_holds_what_fits_and_the_foot_says_where_you_are(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npcs")
    wow.run_frames(10)
    assert wow.eval(f"{TREE}.opts.pages") is True and wow.eval(f"{TREE}.bar:IsShown()") is False
    wow.execute(f"{TREE}.scroll:SetSize(440, 400)")  # seven tiles of 56 fit, with the gaps
    rows(wow, 50)
    index, count, first, last, n = page(wow)
    assert (index, first, n) == (1, 1, 50) and count > 1 and 6 <= last <= 8
    per = last
    assert count == -(-50 // per)  # the pages cut the list evenly
    assert wow.eval(f"{MOD}.pager:IsShown()") is True
    assert wow.eval(f"{MOD}.pager.text:GetText()") == f"1-{per} of 50"
    assert (
        wow.eval(f"{MOD}.pager.prev.enabledFlat") is False
        and wow.eval(f"{MOD}.pager.next.enabledFlat") is True
    )
    # the rows stop above the foot
    assert wow.eval(f"select(2, {TREE}.scroll:GetPoint(2)) == {MOD}.pager") is True
    # only the page's rows have frames
    shown = [f for f in wow.eval(f"{TREE}.pool").values() if f.IsShown(f)]
    assert len(shown) == per
    # the arrows turn the page; the last page starts at its own top and is padded
    wow.execute(f"{MOD}.pager.next:Click()")
    wow.run_frames(1)
    index, _, first, last, _ = page(wow)
    assert (index, first) == (2, per + 1) and wow.eval(
        f"{MOD}.pager.text:GetText()"
    ) == f"{per + 1}-{last} of 50"
    wow.execute(f"{TREE}:SetPage(99)")
    wow.run_frames(1)
    index, count2, first, last, _ = page(wow)
    assert index == count2 == count and last == 50
    assert (
        wow.eval(f"{TREE}.pool[1].row.id") == f"r:{first}"
    )  # the first frame is the page's first row
    assert wow.eval(f"{MOD}.pager.next.enabledFlat") is False
    assert wow.eval(f"{TREE}.total") >= wow.eval(f"{TREE}.offsets[{first}]") + 400  # padded
    # the wheel and the page keys turn too
    wow.execute(f"{TREE}.scroll:GetScript('OnMouseWheel')({TREE}.scroll, 1)")
    wow.run_frames(1)
    assert page(wow)[0] == count - 1
    wow.execute(f"{MOD}.search:GetScript('OnKeyDown')({MOD}.search, 'PAGEDOWN')")
    wow.run_frames(1)
    assert page(wow)[0] == count
    wow.execute(f"{BR}.TurnPage(-1)")
    wow.run_frames(1)
    assert page(wow)[0] == count - 1
    # the keyboard's row lands on its page
    wow.execute(f"{TREE}:SetKeyRow({TREE}.flat[1])")
    wow.run_frames(1)
    assert page(wow)[0] == 1
    assert wow.errors == []


def test_a_new_list_opens_on_the_first_page_and_a_short_one_has_no_foot(wow: WowRuntime):
    boot(wow)
    wow.slash("/bb npcs")
    wow.run_frames(10)
    wow.execute(f"{TREE}.scroll:SetSize(440, 400)")
    rows(wow, 50)
    wow.execute(f"{TREE}:SetPage(3)")
    wow.run_frames(1)
    assert page(wow)[0] == 3
    rows(wow, 50)  # the same rows again (a staged fill): the page stays
    assert page(wow)[0] == 3
    rows(wow, 50, "other")  # another list: the first page
    assert page(wow)[0] == 1
    wow.execute(f"{TREE}:SetPage(3)")
    wow.run_frames(1)
    rows(wow, 9, "other")  # the list shrinks under the open page: its last page
    index, count, _, last, n = page(wow)
    assert (index, count, last, n) == (2, 2, 9, 9)
    rows(wow, 3, "few")
    assert page(wow)[1] == 1 and wow.eval(f"{MOD}.pager:IsShown()") is False
    assert wow.eval(f"select(2, {TREE}.scroll:GetPoint(2)) == {MOD}.listPane") is True
    # the real list: People opens on its first page and the summary keeps no count of its own
    wow.execute(f"{BR}.List('npc')")
    wow.run_frames(10)
    assert page(wow)[0] == 1
    assert wow.eval(f"{MOD}.summary:GetText()") == ""
    # a taller view: more rows on a page, fewer pages
    rows(wow, 50)
    pages_short = page(wow)[1]
    wow.execute(
        f"{TREE}.scroll:SetSize(440, 800); {TREE}.scroll:GetScript('OnSizeChanged')({TREE}.scroll)"
    )
    wow.run_frames(1)
    assert page(wow)[1] < pages_short
    assert wow.errors == []
