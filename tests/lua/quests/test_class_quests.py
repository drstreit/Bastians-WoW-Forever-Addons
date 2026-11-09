"""The class quests view (quests.md "Class quests", catalog review A3.1, 07.11.2026): every quest
the data restricts to classes that this character may take, under the status headers, with the
done count; another class sees none and the summary names the class; the Browser hosts it."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Quests')"
WIN = f"{MOD}.Window"
SIZE = f"{WIN}.tree.scroll:SetSize(500, 400); {WIN}.tree:Refresh()"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[tuple[str, str | None]]:
    return [(strip(r.text), r.ref) for r in wow.eval(f"{WIN}.tree.flat").values()]


def open_class(wow: WowRuntime) -> None:
    wow.slash("/bq class")
    wow.run_frames(30)  # the list is built in a job
    wow.execute(SIZE)


def test_the_view_lists_the_characters_class_quests_under_the_status_headers(wow: WowRuntime):
    boot(wow)
    open_class(wow)  # the mock's character is a mage (Mock.classID 8)
    rows = flat(wow)
    assert rows[0][0] == "Available" and rows[0][1] is None  # the status header
    assert rows[1] == ("A Mage's Errand", "quest:2000")
    assert [r for r in rows if r[1] in ("quest:1000", "quest:62", "quest:176")] == []
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "0 of 1 class quests done"
    assert wow.eval("Bastians:GetModule('Quests').Logic.isClassQuest({ classes = 128 })") is True
    assert wow.eval("Bastians:GetModule('Quests').Logic.isClassQuest({ classes = 0 })") is False
    assert (
        wow.eval("Bastians:GetModule('Quests').Logic.isClassQuest({ flags = { 'class' } })") is True
    )
    assert wow.errors == []


def test_another_class_sees_none_and_the_summary_names_the_class(wow: WowRuntime):
    wow.execute("Mock.classID = 7")  # a shaman
    boot(wow)
    open_class(wow)
    assert flat(wow) == []
    assert strip(wow.eval(f"{WIN}.summary:GetText()")) == "No class quests known for Shaman."
    assert wow.errors == []


def test_the_browser_hosts_the_view(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    wow.execute("Bastians:GetModule('Browser').Browser.ShowView('quests.class')")
    wow.run_frames(30)
    texts = [strip(r.text) for r in wow.eval("Bastians:GetModule('Browser').tree.flat").values()]
    assert any(t.startswith("A Mage's Errand") for t in texts), texts
    assert wow.eval("BastiansQuestsFrame == nil or not BastiansQuestsFrame:IsShown()") is True
    assert wow.errors == []


def test_a_click_in_the_view_keeps_its_rows_and_scans_no_more(wow: WowRuntime):
    """ "when I click on a class quest in the left pane, the right panel
    loads correctly, but the left pane switches to something unrelated". Every render after a
    click emptied the list to "Building the list ..." and scanned every quest again. The ids are
    built once per data generation and character; a click keeps the view, its rows and no scan."""
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    br = "Bastians:GetModule('Browser')"
    wow.execute(f"{br}.Browser.ShowView('quests.class')")
    wow.run_frames(30)
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        local all = Logic.allQuestIDs
        SCANS = 0
        Logic.allQuestIDs = function() SCANS = SCANS + 1 return all() end
        """
    )
    row = next(
        f"{br}.tree.flat[{i}]"
        for i, r in wow.eval(f"{br}.tree.flat").items()
        if r.ref == "quest:2000"
    )
    wow.execute(f"local row = {row} {br}.tree.opts.onClick(row, 'LeftButton', {br}.tree)")
    wow.run_frames(10)
    assert wow.eval(f"{br}.Browser.PageRef()") == "quest:2000"
    assert wow.eval(f"{br}.Browser.ListEntry().id") == "quests.class"
    assert wow.eval("SCANS") == 0
    summary = strip(wow.eval(f"{br}.summary:GetText()") or "")
    assert summary == "0 of 1 class quests done", summary
    texts = [strip(r.text) for r in wow.eval(f"{br}.tree.flat").values()]
    assert any(t.startswith("A Mage's Errand") for t in texts), texts
    # new data: built again
    wow.execute("Bastians:GetModule('Quests').Logic.Reset()")
    wow.execute(f"{br}.Browser.Render()")
    wow.run_frames(30)
    assert wow.eval("SCANS") == 1
    assert wow.errors == []
