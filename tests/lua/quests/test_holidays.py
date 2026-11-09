"""Whether a world event runs (quests.md "What the game offers", ADR 0051): Everything Quests' rules
on plain tables. What cannot be told counts as running."""

import pytest
from harness import WowRuntime
from test_registrations import boot

H = "Bastians:GetModule('Quests').Holidays"


def running(wow: WowRuntime, name: str, now: str) -> bool:
    return wow.eval(f'{H}.Running("{name}", {now})')


def at(month: int, day: int, hour: int = 12, year: int = 2026, weekday: int = 1) -> str:
    return (
        f"{{ year = {year}, month = {month}, day = {day}, weekday = {weekday}, hour = {hour},"
        " minute = 0 }"
    )


@pytest.mark.parametrize(
    ("name", "month", "day", "hour", "on"),
    [
        ("Hallow's End", 10, 18, 9, False),
        ("Hallow's End", 10, 18, 10, True),
        ("Hallow's End", 11, 1, 11, True),
        ("Hallow's End", 11, 1, 12, False),
        ("Midsummer", 7, 1, 12, True),
        ("Children's Week", 11, 5, 12, False),
        # Winter Veil wraps the new year
        ("Winter Veil", 12, 31, 12, True),
        ("Winter Veil", 1, 2, 9, True),
        ("Winter Veil", 1, 2, 11, False),
        ("Winter Veil", 11, 5, 12, False),
    ],
)
def test_fixed_dates(wow: WowRuntime, name: str, month: int, day: int, hour: int, on: bool):
    boot(wow)
    assert running(wow, name, at(month, day, hour)) is on


def test_the_lunar_festival_moves_and_a_year_without_a_row_counts_as_running(wow: WowRuntime):
    boot(wow)
    assert running(wow, "Lunar Festival", at(2, 20, year=2026)) is True
    assert running(wow, "Lunar Festival", at(2, 20, year=2027)) is False
    assert running(wow, "Lunar Festival", at(11, 5, year=2026)) is False
    assert running(wow, "Lunar Festival", at(11, 5, year=2031)) is True


def test_the_darkmoon_faire_opens_on_the_first_monday_on_or_after_the_4th(wow: WowRuntime):
    boot(wow)
    # November 2026: the 1st is a Sunday, the fair opens on Monday the 9th at 03:00
    assert running(wow, "Darkmoon Faire", at(11, 2, weekday=2)) is False  # a Monday before the 4th
    assert running(wow, "Darkmoon Faire", at(11, 9, 2, weekday=2)) is False
    assert running(wow, "Darkmoon Faire", at(11, 9, 3, weekday=2)) is True
    assert running(wow, "Darkmoon Faire", at(11, 12, weekday=5)) is True
    assert running(wow, "Darkmoon Faire", at(11, 16, 2, weekday=2)) is True
    assert running(wow, "Darkmoon Faire", at(11, 16, 3, weekday=2)) is False
    # June 2026: the 1st is a Monday, too early: the 8th
    assert running(wow, "Darkmoon Faire", at(6, 1, weekday=2)) is False
    assert running(wow, "Darkmoon Faire", at(6, 8, 12, weekday=2)) is True


def test_what_cannot_be_told_counts_as_running(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f'{H}.Running("Hallow\'s End", nil)') is True  # no clock
    assert running(wow, "Peon Day", at(11, 5)) is True  # no dates
    no_weekday = "{ year = 2026, month = 11, day = 5, hour = 12, minute = 0 }"
    assert running(wow, "Darkmoon Faire", no_weekday) is True
