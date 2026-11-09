"""A window that is opened comes to the front, also one that was open behind another (owner,
Forever 08.11.2026: "every window that is newly opened should always be on top of all others")."""

from harness import WowRuntime


def test_opening_a_window_that_is_already_open_brings_it_to_the_front(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.run_frames(3)
    wow.execute(
        """
        First = Bastians.UI.Window("TestFirst", { title = "First", db = {} })
        Second = Bastians.UI.Window("TestSecond", { title = "Second", db = {} })
        First:Show()
        Second:Show()
        """
    )

    def order() -> tuple[int, int]:
        return wow.eval("First.frame.raisedAt"), wow.eval("Second.frame.raisedAt")

    first, second = order()
    assert first < second  # the one opened last is in front
    wow.execute("First:Show()")  # opened again while it stands behind the other
    first, second = order()
    assert first > second
    assert wow.errors == []


def test_a_window_on_top_stays_in_its_own_strata(wow: WowRuntime):
    wow.start("Bastians_Core")
    wow.run_frames(3)
    wow.execute(
        """
        Top = Bastians.UI.Window("TestTop", { title = "Top", db = {}, onTop = true })
        Top:Show()
        Top:Show()
        """
    )
    assert wow.eval("Top.frame:GetFrameStrata()") == "TOOLTIP"
    assert wow.eval("Top.frame.raisedAt") is None
    assert wow.errors == []
