"""A giver who offers quests to one faction only (Everything Quests' `giverSide`, 2.17.0): its
place row carries the side, and a quest's start places leave out the other faction's ("The
Islander": the warrior trainers of both sides). use the new fields."""

from harness import WowRuntime

CORE, DATA = "Bastians_Core", "Bastians_Data"
ROWS = "{ { 1453, 0.8, 0.3, 'eq', 'A' }, { 1454, 0.4, 0.7, 'eq', 'H' }, { 1429, 0.5, 0.5, 'eq' } }"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA)
    wow.run_frames(10)
    return wow


def maps(wow: WowRuntime, rows: str = ROWS) -> list[int]:
    return [p[1] for p in wow.eval(f"Bastians.Data.OwnSide({rows})").values()]


def test_each_side_sees_its_own_givers_and_the_ones_of_both(wow: WowRuntime):
    boot(wow)
    assert maps(wow) == [1453, 1429]  # the mock's player is of the Alliance
    wow.execute("function UnitFactionGroup() return 'Horde', 'Horde' end")
    assert maps(wow) == [1454, 1429]


def test_an_unknown_side_or_no_row_left_keeps_them_all(wow: WowRuntime):
    boot(wow)
    assert maps(wow, "{ { 1454, 0.4, 0.7, 'eq', 'H' } }") == [1454]  # nothing would be left
    wow.execute("function UnitFactionGroup() return nil end")
    assert maps(wow) == [1453, 1454, 1429]
    assert wow.eval("Bastians.Data.OwnSide(nil)") is None
