"""Bastian's Book: the record (book.md "The record"): a mark hides a wonder here and shows it on
another character as done by them; the game's answers mark wonders found; nil answers change
nothing; the envelopes stay opened."""

from harness import WowRuntime

CORE, DATA, STRAT = "Bastians_Core", "Bastians_Data", "Bastians_Strategies"
REC = "Bastians:GetModule('Strategies').Record"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, STRAT)
    wow.run_frames(5)
    wow.execute(
        f"""
        G = {{}}
        {REC}.Bind(G, "Thalia-Realm", {{ name = "Thalia", class = "MAGE", faction = "Alliance", level = 24 }})
        """
    )
    return wow


def check(wow: WowRuntime, rule: str, answers: str, side: str = '"A"'):
    return wow.eval(f"{REC}.Check({rule}, {answers}, {side})")


ANSWERS = """{
  quest = function(id) return id == 7 end,
  item = function(id) return id == 5 and 1 or 0 end,
  spell = function(id) return id == 9 end,
  title = function(id) return id == 3 end,
}"""
UNSURE = """{
  quest = function() return nil end, item = function() return nil end,
  spell = function() return nil end, title = function() return nil end,
}"""


def test_a_rule_asks_the_game(wow: WowRuntime):
    boot(wow)
    assert check(wow, "{ item = 5 }", ANSWERS) is True
    assert check(wow, "{ item = 6 }", ANSWERS) is False  # none in the bags or the bank
    assert check(wow, "{ spell = 9, item = 6 }", ANSWERS) is True  # a mount: its spell known
    assert check(wow, "{ title = 3 }", ANSWERS) is True
    assert check(wow, "{ title = 4 }", ANSWERS) is False
    assert check(wow, "{ quests = { A = { 1, 7 } } }", ANSWERS) is True  # any one of the side's
    assert check(wow, "{ quests = { H = { 7 } } }", ANSWERS) is False  # not this side's
    assert check(wow, "{ quests = { A = { 7 } } }", ANSWERS, "nil") is None  # no side known
    assert check(wow, "nil", ANSWERS) is None  # a mark by hand
    assert check(wow, "{ item = 5 }", UNSURE) is None  # the client cannot tell: nothing changes
    assert check(wow, "{ quests = { A = { 1 } } }", UNSURE) is None


def test_a_mark_is_this_characters_and_an_alts_shows(wow: WowRuntime):
    boot(wow)
    wow.execute(f'{REC}.Mark("chain:sleeping-bag")')
    assert wow.eval(f'{REC}.IsDone("chain:sleeping-bag")') is True
    assert wow.eval(f'{REC}.Entry("chain:sleeping-bag").how') == "mark"
    assert list(wow.eval(f'{REC}.Alts("chain:sleeping-bag")').values()) == []
    # the next character of the account
    wow.execute(f'{REC}.Bind(G, "Bran-Realm", {{ name = "Bran", faction = "Alliance" }})')
    assert wow.eval(f'{REC}.IsDone("chain:sleeping-bag")') is False
    assert list(wow.eval(f'{REC}.Alts("chain:sleeping-bag")').values()) == ["Thalia"]
    lists = wow.eval(f"{REC}.Lists()")
    assert [a.id for a in lists.alts.values()] == ["chain:sleeping-bag"]
    assert list(lists.mine.values()) == []
    wow.execute(f'{REC}.Mark("chain:sleeping-bag")')
    assert list(wow.eval(f'{REC}.Alts("chain:sleeping-bag")').values()) == []  # done here too
    wow.execute(f'{REC}.Unmark("chain:sleeping-bag")')
    assert wow.eval(f'{REC}.IsDone("chain:sleeping-bag")') is False
    assert wow.eval('G.record["Thalia-Realm"].done["chain:sleeping-bag"].how') == "mark"


def test_the_envelope_stays_opened_for_the_account(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f'{REC}.IsOpened("chain:lyn-the-ignored")') is False
    wow.execute(f'{REC}.Open("chain:lyn-the-ignored")')
    wow.execute(f'{REC}.Bind(G, "Bran-Realm", {{ name = "Bran" }})')
    assert wow.eval(f'{REC}.IsOpened("chain:lyn-the-ignored")') is True


def test_the_scan_marks_what_the_game_shows(wow: WowRuntime):
    boot(wow)
    # the mock's quest history holds 783, 7 and 18; its bags item 2589 (the mock's Mock.bags)
    wow.execute(
        f"""
        Mock.bags[2589] = 3
        local shelf = {{
          {{ id = "a", done = {{ quests = {{ A = {{ 783 }}, H = {{ 783 }} }} }} }},
          {{ id = "b", done = {{ quests = {{ A = {{ 999 }} }} }} }},
          {{ id = "c", done = {{ item = 2589 }} }},
          {{ id = "d" }},
        }}
        found = 0
        {REC}.Scan(Bastians:GetModule("Strategies"), shelf, function(n) found = n end)
        """
    )
    wow.run_frames(3)
    assert wow.eval("found") == 2
    assert wow.eval(f'{REC}.Entry("a").how') == "found"
    assert wow.eval(f'{REC}.IsDone("b")') is False
    assert wow.eval(f'{REC}.IsDone("c")') is True
    assert wow.eval(f'{REC}.IsDone("d")') is False
    assert wow.errors == []


def test_a_mark_keeps_the_wonders_name(wow: WowRuntime):
    """Round 4's risk (plan-book-round4.md section 8): a wonder that is not obtainable leaves the
    pack; a mark for it stays in the record with the name it was made under."""
    boot(wow)
    wow.execute(
        f"""
        local R = {REC}
        R.Mark("mount:10795", "mark", 100, "Ivory Raptor")
        R.Mine().done["pet:1"] = {{ how = "found", at = 50 }}  -- a mark of before round 4
        R.Mine().done["pet:2"] = {{ how = "mark", at = 60 }}   -- its wonder left the pack
        R.KeepNames({{ {{ id = "pet:1", title = "Mechanical Squirrel Box" }}, {{ id = "rare:9", title = "X" }} }})
        """
    )
    assert wow.eval(f'{REC}.Entry("mount:10795").name') == "Ivory Raptor"
    assert wow.eval(f'{REC}.Entry("pet:1").name') == "Mechanical Squirrel Box"
    assert wow.eval(f'{REC}.Entry("pet:1").at') == 50  # nothing else of the mark changes
    assert wow.eval(f'{REC}.Entry("pet:2").name') is None  # unknown stays unknown
    assert wow.eval(f'{REC}.Entry("rare:9")') is None  # a name makes no mark
    assert wow.eval(f'{REC}.IsDone("mount:10795")') is True  # the mark stays, the wonder gone
    # the game's own finding keeps the name too
    wow.execute(
        f"""
        Bastians.Compat.GetItemCount = function(id) return id == 5 and 1 or 0 end
        {REC}.Scan(Bastians:GetModule("Strategies"), {{ {{ id = "pet:5", title = "A Found Pet", done = {{ item = 5 }} }} }})
        """
    )
    assert wow.eval(f'{REC}.Entry("pet:5").how') == "found"
    assert wow.eval(f'{REC}.Entry("pet:5").name') == "A Found Pet"
    assert wow.errors == []
