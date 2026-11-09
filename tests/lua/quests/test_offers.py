"""What the game offers: Rema Schneider had a pin and no
yellow mark, Lieutenant Orrin a pin and no quest, Elder Stormbrow a pin and nobody there. The
fixture's Marshal Dughan (npc:240) gives quest 76 once 62 is handed in: level 12, nothing else."""

from harness import WowRuntime
from test_registrations import boot, errors, pins, sections, strip

QUESTS = "Bastians:GetModule('Quests')"
DUGHAN = "Creature-0-1-0-1-240-0000000001"
CHANGED = f"{QUESTS}:Fire('BASTIANS_QUESTS_CHANGED', nil, {{}})"
IN_SEASON = "{ year = 2026, month = 2, monthDay = 20, weekday = 6, hour = 12, minute = 0 }"
OUT_OF_SEASON = "{ year = 2026, month = 11, monthDay = 5, weekday = 5, hour = 12, minute = 0 }"


def open_76(wow: WowRuntime) -> None:
    """62 handed in: 76 is available at Marshal Dughan."""
    wow.execute("Mock.completedQuests = { 783, 7, 18, 62 }; table.remove(Mock.questLog, 3)")
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    wow.fire("QUEST_LOG_UPDATE")
    settle(wow)


def settle(wow: WowRuntime) -> None:
    wow.advance(0.2)
    wow.run_frames(2)


def patch_quest(wow: WowRuntime, fields: str) -> None:
    """Quest 76 with more fields than the fixture has, seen through the Logic layer's data."""
    wow.execute(
        f"""
        local d = Bastians:GetService("data")
        local proxy = setmetatable({{
          Get = function(_, kind, id)
            local r = d:Get(kind, id)
            if kind == "quest" and id == 76 and r then
              local copy = {{}}
              for k, v in pairs(r) do copy[k] = v end
              for k, v in pairs({{ {fields} }}) do copy[k] = v end
              return copy
            end
            return r
          end,
        }}, {{ __index = function(_, k)
          local v = d[k]
          if type(v) == "function" then
            return function(_, ...) return v(d, ...) end
          end
          return v
        end }})
        {QUESTS}.Logic.SetData(proxy)
        {CHANGED}
        """
    )
    settle(wow)


def giver_rows(wow: WowRuntime) -> list[str]:
    """The words of the quest rows on Marshal Dughan's page, under their headers."""
    out = []
    for header in sections(wow, "npc:240")["quests.starts"].rows.values():
        out.extend(strip(row.text) for row in header.children.values())
    return out


def status(wow: WowRuntime, qid: int = 76) -> str:
    return wow.eval(f"{QUESTS}.Logic.status({qid}, {QUESTS}.State.ForLogic())")


def page(wow: WowRuntime, *quests: tuple[int, str]) -> None:
    rows = ", ".join(f"{{ questID = {i}, title = '{t}' }}" for i, t in quests)
    wow.execute(
        f"Mock.guids = Mock.guids or {{}}; Mock.guids.npc = '{DUGHAN}';"
        f"Mock.gossip = {{ active = {{}}, available = {{ {rows} }}, options = {{}} }}"
    )
    wow.fire("GOSSIP_SHOW")
    settle(wow)


def close(wow: WowRuntime) -> None:
    wow.fire("GOSSIP_CLOSED")
    wow.advance(61)
    wow.run_frames(2)


def level_up(wow: WowRuntime, level: int) -> None:
    wow.fire("PLAYER_LEVEL_UP", level)
    settle(wow)


def test_a_giver_who_does_not_list_the_quest_loses_its_pin_until_a_level_up(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    assert list(pins(wow, "quests.available")) == ["npc:240"]
    page(wow)  # Lieutenant Orrin's case: the page lists nothing
    assert status(wow) == "inactive"
    assert pins(wow, "quests.available") == {}
    words = giver_rows(wow)
    assert any("Not offered now" in strip(w) for w in words)  # the quest stays findable
    level_up(wow, 13)
    assert status(wow) == "available"  # a hidden prerequisite may be gone: asked again
    assert list(pins(wow, "quests.available")) == ["npc:240"]
    assert errors(wow) == []


def test_a_mark_survives_a_reload_and_a_later_offer_clears_it(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    page(wow)
    assert wow.eval(f"{QUESTS}.db.char.missed[76]") == 12
    close(wow)
    page(wow, (76, "The Jasperlode Mine"))
    assert status(wow) == "available"
    assert wow.eval(f"{QUESTS}.db.char.missed[76]") is None
    assert errors(wow) == []


def test_only_the_first_page_of_a_visit_counts(wow: WowRuntime):
    # an option's sub-page lists no quests: it must not teach that the giver offers nothing
    boot(wow)
    open_76(wow)
    page(wow, (76, "The Jasperlode Mine"))
    page(wow)  # the sub-page, the visit still open
    assert status(wow) == "available"
    wow.fire("GOSSIP_CLOSED")  # some clients close and reopen for a sub-page, within seconds
    page(wow)
    assert status(wow) == "available"
    close(wow)  # a new visit, a minute later
    page(wow)
    assert status(wow) == "inactive"
    assert errors(wow) == []


def test_nothing_is_learned_in_combat_or_from_a_low_level_quest(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    wow.set_combat(True)
    page(wow)
    assert status(wow) == "available"
    wow.set_combat(False)
    close(wow)
    # low level: the client may leave it out of the page
    wow.execute("Mock.trivialRange = 1")
    level_up(wow, 40)
    page(wow)
    assert status(wow) == "available"
    assert errors(wow) == []


def test_a_greeting_compares_by_title_and_a_title_it_cannot_match_teaches_nothing(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    wow.execute(
        f"Mock.guids = Mock.guids or {{}}; Mock.guids.npc = '{DUGHAN}';"
        "Mock.greeting = { active = {}, available = { { title = 'THE JASPERLODE MINE' } } }"
    )
    wow.fire("QUEST_GREETING")
    settle(wow)
    assert status(wow) == "available"  # listed: nothing against it
    wow.fire("QUEST_FINISHED")
    wow.advance(61)
    wow.execute(
        "Mock.greeting.available = { { title = 'Die Jaspisader' } }"
    )  # a name we do not know
    wow.fire("QUEST_GREETING")
    settle(wow)
    assert status(wow) == "available"
    wow.fire("QUEST_FINISHED")
    wow.advance(61)
    wow.execute("Mock.greeting.available = {}")
    wow.fire("QUEST_GREETING")
    settle(wow)
    assert status(wow) == "inactive"
    assert errors(wow) == []


def test_questies_flags_take_the_pin_and_what_the_game_offers_gives_it_back(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    patch_quest(wow, 'flags = { "dormant" }')  # Lieutenant Orrin: the Scourge Invasion
    assert status(wow) == "inactive"
    assert pins(wow, "quests.available") == {}
    page(wow, (76, "The Jasperlode Mine"))  # the event runs after all: the game wins, for good
    assert status(wow) == "available"
    wow.advance(40 * 24 * 3600)
    assert status(wow) == "available"
    assert wow.eval(f"{QUESTS}.db.char.offered[76] ~= nil") is True
    assert errors(wow) == []


def test_a_quest_detail_counts_as_an_offer_and_says_nothing_about_the_others(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    patch_quest(wow, 'flags = { "absent" }')
    wow.execute("Mock.questFrame.questID = 76")
    wow.fire("QUEST_DETAIL")
    settle(wow)
    assert status(wow) == "available"
    assert errors(wow) == []


def test_a_world_event_takes_the_pin_out_of_season(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    wow.execute(f"Mock.calendarTime = {OUT_OF_SEASON}")
    wow.advance(61)  # the answers about the events are kept a minute
    patch_quest(wow, 'holiday = "Lunar Festival"')  # Elder Stormbrow
    assert status(wow) == "inactive"
    assert pins(wow, "quests.available") == {}
    words = giver_rows(wow)
    assert any("Only during Lunar Festival" in strip(w) for w in words)
    wow.execute(f"Mock.calendarTime = {IN_SEASON}")
    wow.advance(61)
    wow.execute(CHANGED)
    settle(wow)
    assert status(wow) == "available"
    assert list(pins(wow, "quests.available")) == ["npc:240"]
    assert errors(wow) == []


def test_an_offer_against_an_events_dates_lasts_two_weeks(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    wow.execute(f"Mock.calendarTime = {OUT_OF_SEASON}")
    wow.advance(61)
    patch_quest(wow, 'holiday = "Lunar Festival"')
    page(wow, (76, "The Jasperlode Mine"))  # the dates are wrong this year: the game wins
    assert status(wow) == "available"
    wow.execute("local t = time(); time = function() return t + 15 * 24 * 3600 end")
    assert status(wow) == "inactive"  # the event has ended since
    assert errors(wow) == []


def test_without_a_clock_a_holiday_quest_stays_available(wow: WowRuntime):
    # a surplus pin is the failure, never a missing one
    boot(wow)
    open_76(wow)
    patch_quest(wow, 'holiday = "Lunar Festival"')
    assert status(wow) == "available"
    assert errors(wow) == []


def test_a_low_level_quest_keeps_its_pin_in_grey_and_says_so(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    pin = pins(wow, "quests.available")["npc:240"]
    assert pin.status == "available"
    # quest 76 is far below this character: the client's range says trivial
    wow.execute("Mock.trivialRange = 1")
    level_up(wow, 40)
    pin = pins(wow, "quests.available")["npc:240"]
    assert pin.status == "low"
    style = "Bastians.UI.Style.C.diffGrey"
    assert list(pin.color.values()) == list(wow.eval(style).values())
    assert strip(pin.card(pin).lines[1].text) == "Low level"
    assert any("Available, low level" in strip(line) for line in pin.lines.values())
    words = giver_rows(wow)
    assert any("Available, low level" in strip(w) for w in words)
    assert errors(wow) == []


def test_without_the_clients_range_no_quest_is_low_level(wow: WowRuntime):
    boot(wow)
    open_76(wow)
    level_up(wow, 40)  # far above the quest, and the client does not say
    assert pins(wow, "quests.available")["npc:240"].status == "available"
    assert errors(wow) == []
