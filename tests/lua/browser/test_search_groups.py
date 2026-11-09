"""The search's results by list and the category buttons' counts (ADR 0056, PA1): hits of several
lists stand in a section each, the list of the best hit first; every category button says how many
the search found, also while the search keeps to one list; a type the limit cut says "100+"; a list
without a hit says nothing, which is not 0."""

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
TREE = f"{MOD}.tree"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute(f"{BR}.Open()")
    wow.run_frames(5)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def search(wow: WowRuntime, text: str) -> None:
    wow.execute(f"{MOD}.search:SetText('{text}')")
    wow.run_frames(30)


def sections(wow: WowRuntime) -> list[str]:
    rows = wow.eval(f"{TREE}.flat").values()
    return [strip(r.text) for r in rows if r.kind == "section"]


def count(wow: WowRuntime, word: str):
    """What the category button of the list `word` says."""
    return wow.eval(
        f"""(function()
          for _, cat in ipairs({BR}.Categories()) do
            if cat.text == {word!r} then return cat.count end
          end
        end)()"""
    )


def label(wow: WowRuntime, word: str):
    """What the tab of the list `word` reads (its count after two spaces), wherever its section."""
    return wow.eval(
        f"""(function()
          for _, s in ipairs({BR}.Sections()) do
            for _, c in ipairs(s.tabs) do
              if c.text == {word!r} then return c.count and (c.text .. "  " .. c.count) or c.text end
            end
          end
        end)()"""
    )


def click(wow: WowRuntime, word: str) -> None:
    wow.execute(
        f"""for _, cat in ipairs({BR}.Categories()) do
          if cat.text == {word!r} then {BR}.NavClick(cat.id) end
        end"""
    )
    wow.run_frames(30)


def test_hits_of_several_lists_stand_in_a_section_each(wow: WowRuntime):
    boot(wow)
    search(wow, "hog")
    heads = sections(wow)
    assert len(heads) >= 2
    assert any(h.startswith("Monsters") for h in heads) and any(
        h.startswith("Quests") for h in heads
    )
    # each head counts its rows, and the rows stand under their head
    heads = [r for r in wow.eval(f"{TREE}.rows").values() if r.kind == "section"]
    for row in heads:
        n = len(list(row.children.values()))
        assert n >= 1 and strip(row.text).endswith(f"  {n}")
    # the best hit's list first: the names that start with the text lead
    assert next(iter(heads[0].children.values())).title.lower().startswith("hog")


def test_one_list_stays_as_it_was(wow: WowRuntime):
    boot(wow)
    search(wow, "quest hog")
    assert sections(wow) == []


def test_every_button_says_what_the_search_found(wow: WowRuntime):
    boot(wow)
    assert count(wow, "Quests") is None
    search(wow, "hog")
    quests, mobs = count(wow, "Quests"), count(wow, "Monsters")
    assert quests and mobs == "1"
    assert label(wow, "Quests") == f"Quests  {quests}"
    # a list without a hit says nothing: not 0, a list no provider searches would say so too
    assert count(wow, "Zones") is None and label(wow, "Zones") == "Zones"
    # the search keeps to one list: the rows narrow, the other buttons keep their numbers
    click(wow, "Quests")
    assert sections(wow) == []
    assert count(wow, "Monsters") == "1" and count(wow, "Quests") == quests
    # the box emptied: the numbers go
    wow.execute(f"{MOD}.search:SetText('')")
    wow.run_frames(10)
    assert count(wow, "Monsters") is None and label(wow, "Monsters") == "Monsters"


def test_a_list_shows_no_numbers(wow: WowRuntime):
    boot(wow)
    search(wow, "hog")
    assert count(wow, "Monsters") == "1"
    wow.execute(f"{BR}.List('item')")
    wow.run_frames(10)
    assert count(wow, "Monsters") is None


def test_a_type_the_limit_cut_says_so(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
          id = "test.many", label = "many", priority = 1,
          search = function(query)
            local out = {}
            if query == "manyhits" then
              for i = 1, 100 do
                out[i] = { ref = "item:" .. i, label = "manyhits " .. i, score = 1 }
              end
            end
            return out
          end,
        })"""
    )
    search(wow, "manyhits")
    assert count(wow, "Items") == "100+"
