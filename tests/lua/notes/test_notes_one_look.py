"""Notes' lists window in the one look (ADR 0084, W9 of plan-suite-waves.md; notes.md "The one
look"): New list, Import and Share as the head's tools, a list's name as a quiet heading, the
chosen list with Rename and Remove list in the foot. The numbers are the suite's board's."""

from harness import WowRuntime

CORE, NOTES = "Bastians_Core", "Bastians_Notes"
MOD = "Bastians:GetModule('Notes')"
N = f"{MOD}.Notes"
LISTS = f"{MOD}.Lists"
W = "Bastians.UI.Widgets"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, "Bastians_Data", NOTES)))
    wow.run_frames(5)
    return wow


def test_the_heads_tools_and_the_foot(wow: WowRuntime):
    boot(wow)
    wow.slash("/bnotes add Mailbox here")
    wow.slash("/bnotes")
    win = f"{LISTS}.win"
    assert wow.eval(f"{win}.headKind") == "tall" and wow.eval(f"{win}.title:GetText()") == "Notes"
    # the head: New list and Import as words in an outline, Share the one filled plate
    new, imp, share = f"{LISTS}.newButton", f"{LISTS}.importButton", f"{LISTS}.shareButton"
    for tool in (new, imp, share):
        assert wow.eval(f"{tool}:GetParent() == {win}.head") is True
        assert wow.eval(f"{tool}:GetHeight()") == 28
    assert wow.eval(f"{new}.spec.boxed") is True and wow.eval(f"{new}.spec.label") == "New list"
    assert wow.eval(f"{share}.spec.primary") is True and wow.eval(f"{new}.spec.primary") is None
    assert wow.eval(f"select(2, {share}:GetPoint(1)) == {win}.options") is True
    assert wow.eval(f"select(2, {imp}:GetPoint(1)) == {share}") is True
    # the foot names the chosen list; "My notes" can be neither renamed nor removed
    foot = f"{LISTS}.foot"
    assert wow.eval(f"{foot}:GetHeight()") == 34 and wow.eval(f"{foot}:GetText()") == "My notes"
    assert wow.eval(f"{LISTS}.renameButton:IsShown()") is False
    assert wow.eval(f"{LISTS}.removeButton:IsShown()") is False
    # New list asks for a name over the foot; the new list is the chosen one, with its tools
    wow.execute(f"{new}:Click()")
    assert wow.eval(f"{LISTS}.nameBox:IsShown()") is True
    assert wow.eval(f"select(2, {LISTS}.nameBox:GetPoint(1)) == {foot}") is True
    wow.execute(
        f"local b = {LISTS}.nameBox; b:SetText('Elwynn herbs'); b:GetScript('OnEnterPressed')(b)"
    )
    wow.run_frames(3)
    assert wow.eval(f"{foot}:GetText()") == "Elwynn herbs"
    rename, remove = f"{LISTS}.renameButton", f"{LISTS}.removeButton"
    assert wow.eval(f"{rename}:IsShown()") is True and wow.eval(f"{remove}:IsShown()") is True
    for tool in (rename, remove):
        assert wow.eval(f"{tool}:GetParent() == {foot}") is True
        assert wow.eval(f"{tool}:GetHeight()") == 22
    # Remove list at the foot's end, clear of the grip; Rename before it; the name before both
    point = tuple(wow.eval(f"{{ {remove}:GetPoint(1) }}").values())
    assert (point[0], point[2], point[3]) == ("RIGHT", "RIGHT", -18)
    assert wow.eval(f"select(2, {rename}:GetPoint(1)) == {remove}") is True
    assert wow.eval(f"select(2, {foot}.text:GetPoint(2)) == {rename}") is True
    # removing it goes back to "My notes"
    wow.execute(f"{remove}:Click()")
    wow.run_frames(3)
    assert wow.eval(f"{foot}:GetText()") == "My notes"
    assert wow.eval(f"{remove}:IsShown()") is False
    assert wow.errors == []


def test_a_lists_name_is_a_quiet_heading_with_its_count(wow: WowRuntime):
    boot(wow)
    for title in ("Anvil", "Bank"):
        wow.slash(f"/bnotes add {title}")
    wow.slash("/bnotes")
    tree = f"{LISTS}.tree"
    wow.execute(f"{tree}.scroll:SetSize(380, 300); {tree}:Refresh()")
    assert wow.eval(f"{tree}.opts.capsSections") is True
    row = wow.eval(f"{tree}.flat[1]")
    assert row.kind == "section" and row.title == "My notes" and row.count == 2
    assert row.button.label == "on"  # the list's switch for the map stays on its row
    assert wow.eval(f"{tree}.heights[1]") == 24
    assert wow.errors == []


def test_notes_works_with_core_alone(wow: WowRuntime):
    """W9's gate (ADR 0083): the app loads and works with Core alone: no Data, no Map."""
    boot(wow, CORE, NOTES)
    assert wow.eval(f"{MOD}:IsEnabled()") is True
    wow.slash("/bnotes add A place")
    wow.slash("/bnotes")
    assert wow.eval(f"{LISTS}.win:IsShown()") is True
    assert wow.eval(f"{LISTS}.foot:GetText()") == "My notes"
    assert wow.errors == []
