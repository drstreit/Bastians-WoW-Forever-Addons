"""The Helpers feed (ADR 0043, S12): the last notice on the bar, the session's notices in the
tooltip, newest first, at most eight, with their age."""

from harness import WowRuntime
from test_helpers import CORE, HELPERS, boot, strip

FEED = "Bastians:FeedObject('Helpers')"
TIP = (
    "TipLines = {} ; local tt = { AddLine = function(_, t) TipLines[#TipLines + 1] = t end,"
    " AddDoubleLine = function(_, a, b) TipLines[#TipLines + 1] = a .. ' | ' .. tostring(b) end }"
    f" ; {FEED}.OnTooltipShow(tt)"
)


def tip(wow: WowRuntime) -> list[str]:
    wow.execute(TIP)
    return [strip(x) for x in wow.eval("TipLines").values()]


def test_the_feed_shows_the_last_notice_and_the_session_history(wow: WowRuntime):
    boot(wow, CORE, HELPERS)
    assert wow.eval(f"{FEED}.text") == ""  # nothing yet: not a made-up line
    assert "Nothing done yet this session." in tip(wow)
    wow.execute("Bastians:GetModule('Helpers').Helpers.Notice('Sold 3 items')")
    wow.advance(0.5)
    assert wow.eval(f"{FEED}.text") == "Sold 3 items"
    wow.execute("Bastians:GetModule('Helpers').Helpers.Notice('Repaired')")
    wow.advance(0.5)
    assert wow.eval(f"{FEED}.text") == "Repaired"
    lines = tip(wow)
    assert lines[0] == "Bastian's Helpers"
    assert lines[1].startswith("Repaired") and lines[1].endswith("just now")
    assert lines[2].startswith("Sold 3 items")
    assert lines[-1].startswith("Click")
    wow.advance(180)
    assert tip(wow)[1].endswith("3 min ago")
    assert wow.errors == []


def test_the_history_keeps_eight_and_a_click_opens_the_panel(wow: WowRuntime):
    boot(wow, CORE, HELPERS)
    for i in range(1, 11):
        wow.execute(f"Bastians:GetModule('Helpers').Helpers.Notice('Notice {i}')")
    lines = tip(wow)
    assert len(lines) == 1 + 8 + 1  # title, eight notices, the hint
    assert lines[1].startswith("Notice 10") and lines[8].startswith("Notice 3")
    wow.execute(f"{FEED}.OnClick(nil, 'LeftButton')")
    assert wow.eval("BastiansHelpersPanel:IsShown()") is True
    assert wow.errors == []
