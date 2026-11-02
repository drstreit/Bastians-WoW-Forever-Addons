"""The search syntax in the Browser: `type:vendor` in the world
search and in a list's filter, the rows back when a box is emptied, `+word`."""

from harness import WowRuntime
from test_filters import BR, TREE, boot, flat, open_list

MOD = "Bastians:GetModule('Browser')"


def type_in(wow: WowRuntime, box: str, text: str) -> None:
    wow.execute(f"{MOD}.{box}:SetText({text!r})")
    wow.run_frames(10)
    wow.advance(0.3)
    wow.run_frames(10)


def test_type_vendor_in_a_list_filter_and_the_rows_back_when_emptied(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    every = flat(wow)
    assert len(every) > 2
    wow.execute(f"{BR}.FilterList('type:vendor')")
    wow.run_frames(10)
    vendors = flat(wow)
    assert 0 < len(vendors) < len(every)
    wow.execute(f"{BR}.FilterList('')")
    wow.run_frames(10)
    assert flat(wow) == every
    assert wow.errors == []


def test_type_vendor_in_the_world_search(wow: WowRuntime):
    boot(wow)
    got = []
    wow.execute(
        """
        _G.got = nil
        Bastians:Search('type:vendor', { limit = 50 }, function(results, done)
          if done then _G.got = results end
        end)
        """
    )
    wow.run_frames(30)
    got = [r.ref for r in wow.eval("got").values()]
    assert got and all(ref.startswith("npc:") for ref in got)
    d = "Bastians:GetService('data')"
    for ref in got:
        typ, rid = ref.split(":")
        words = list(wow.eval(f"{d}:KindWords('{typ}', {rid})").values())
        assert any("vendor" in w for w in words)
    assert wow.errors == []


def test_the_search_box_emptied_shows_the_start_again(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Home()")
    wow.run_frames(10)
    type_in(wow, "search", "")
    start = flat(wow)
    type_in(wow, "search", "wel")
    assert flat(wow) != start
    type_in(wow, "search", "")
    assert flat(wow) == start
    open_list(wow, "npc")
    type_in(wow, "search", "wel")
    type_in(wow, "search", "")
    assert flat(wow) != [] and wow.errors == []


def test_the_search_typed_on_a_list_and_emptied_shows_the_list_again(wow: WowRuntime):
    """ "the middle tile should again show the full list of the currently
    selected left menu item"."""
    boot(wow)
    open_list(wow, "npc")
    every = flat(wow)
    type_in(wow, "search", "wel")
    assert wow.eval(f"{BR}.Current().kind") == "home"
    type_in(wow, "search", "")
    assert wow.eval(f"{BR}.Current().kind") == "list"
    assert flat(wow) == every
    assert wow.errors == []


def test_typing_on_filters_within_the_rows_kept(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    wow.execute(f"{BR}.FilterList('w')")
    wow.run_frames(10)
    kept = wow.eval(f"{BR}.Current().textKept")
    size = wow.eval(
        f"(function() local n = 0 for _ in pairs({BR}.Current().textKept.set) do n = n + 1 end return n end)()"
    )
    assert kept and kept.text == "w" and size > 0
    wide = flat(wow)
    wow.execute(f"{BR}.FilterList('we')")
    wow.run_frames(10)
    narrow = flat(wow)
    assert 0 < len(narrow) <= len(wide)
    # the same rows as a fresh filter of the whole list
    wow.execute(f"{BR}.Current().textKept = nil {BR}.FilterList('we')")
    wow.run_frames(10)
    assert flat(wow) == narrow
    assert wow.errors == []


def test_a_plus_word_is_needed(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians.Query.Compile('wolf +rabid'):Match('rabid wolf')") is True
    assert wow.eval("Bastians.Query.Compile('wolf +rabid'):Match('grey wolf')") is False
    assert wow.eval("Bastians.Query.Compile('c++'):Match('c++ guide')") is True
    assert TREE
