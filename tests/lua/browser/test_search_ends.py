"""A search always ends, on the screen ("when I am in the browser and
search something with the top search, I never get any result", the list on "Searching ..." with a
story open beside it; "we tried that already and it did not work").

The earlier tests could not see it: the mock's CPU clock stands still, so a job ran to its end in
one frame and nothing could reach a search in between. In the game a search takes 13 to 30 frames
on the real packs (measured 06.11.2026). These tests slice the jobs as the client does and type
into the real box, and each route to the stuck screen has its own test."""

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
SLICED = "Mock.cpuStep = 3"  # every clock reading costs 3 ms: a 4 ms budget is two readings
PATIENCE_FRAMES = 40


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute(f"{BR}.Home()")
    wow.execute(f"{TREE}.scroll:SetSize(440, 400); {TREE}:Refresh()")
    wow.run_frames(5)
    wow.execute(SLICED)
    return wow


def slow_provider(wow: WowRuntime) -> None:
    """A provider that takes many slices, as the names of the real packs do."""
    wow.execute(
        """
        Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
          id = "t.slow", label = "Slow", priority = 50,
          search = function(_, _, yield)
            for _ = 1, 20 do yield() end
            return {}
          end })
        """
    )


def typed(wow: WowRuntime, text: str) -> None:
    """Letter by letter into the box, the way a player types."""
    for i in range(1, len(text) + 1):
        wow.execute(f"{MOD}.search:SetText({text[:i]!r})")
        wow.run_frames(1)


def summary(wow: WowRuntime) -> str:
    return str(wow.eval(f"{MOD}.summary:GetText()"))


def rows(wow: WowRuntime) -> list[str]:
    return [str(r.title or r.text) for r in wow.eval(f"{TREE}.flat").values()]


def found(wow: WowRuntime, name: str) -> bool:
    return any(name in r for r in rows(wow)) and "Searching" not in summary(wow)


def test_the_slices_are_real(wow: WowRuntime):
    """The guard of these tests: a search must span frames here, or they prove nothing."""
    boot(wow)
    slow_provider(wow)
    typed(wow, "hogger")
    assert "Searching" in summary(wow)
    wow.run_frames(PATIENCE_FRAMES)
    assert found(wow, "Hogger")


def test_a_render_in_every_frame_does_not_restart_the_search(wow: WowRuntime):
    """Any event renders the Browser again; a render used to cancel the search and start it over,
    so events a little faster than a search left it on "Searching ..." for good."""
    boot(wow)
    slow_provider(wow)
    typed(wow, "hogger")
    for _ in range(PATIENCE_FRAMES):
        wow.execute(f"{BR}.Render()")
        wow.run_frames(1)
    assert found(wow, "Hogger")
    assert wow.errors == []


def test_a_render_after_the_end_draws_without_a_new_search(wow: WowRuntime):
    boot(wow)
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    wow.execute(
        """
        RUNS = 0
        local real = Bastians.Search
        function Bastians:Search(...) RUNS = RUNS + 1 return real(self, ...) end
        """
    )
    wow.execute(f"{BR}.Render()")
    wow.run_frames(PATIENCE_FRAMES)
    assert wow.eval("RUNS") == 0
    assert found(wow, "Hogger")


def test_new_data_searches_again(wow: WowRuntime):
    boot(wow)
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    wow.execute(
        """
        RUNS = 0
        local real = Bastians.Search
        function Bastians:Search(...) RUNS = RUNS + 1 return real(self, ...) end
        Bastians:Fire("BASTIANS_DATA_LOADED")
        """
    )
    wow.advance(0.3)
    wow.run_frames(PATIENCE_FRAMES)
    assert wow.eval("RUNS") == 1
    assert found(wow, "Hogger")


def test_another_search_leaves_this_one_alone(wow: WowRuntime):
    """The map's box and the omnibox search too; a new search used to cancel every other."""
    boot(wow)
    slow_provider(wow)
    typed(wow, "hogger")
    wow.execute(
        """
        OTHER = {}
        Bastians:Search("wolf", {}, function(_, done) OTHER[#OTHER + 1] = done end)
        """
    )
    wow.run_frames(PATIENCE_FRAMES)
    assert found(wow, "Hogger")
    assert list(wow.eval("OTHER").values())[-1] is True


def test_a_search_replaced_by_its_own_caller_stops(wow: WowRuntime):
    wow.start(CORE)
    wow.execute(
        """
        SEEN = {}
        Bastians:RegisterSearchProvider(Bastians:GetModule('Core') or {}, {
          id = "t.words", label = "Words", priority = 1,
          search = function(query) return { { ref = "npc:1", label = query, score = 1 } } end })
        local first = Bastians:Search("one", {}, function() SEEN[#SEEN + 1] = "one" end)
        first:Cancel()
        Bastians:Search("two", {}, function() SEEN[#SEEN + 1] = "two" end)
        """
    )
    wow.run_frames(10)
    assert set(wow.eval("SEEN").values()) == {"two"}


def test_a_failing_draw_says_so_instead_of_searching_on(wow: WowRuntime):
    """Since "a search always ends" the callback's error was swallowed and the screen stayed."""
    boot(wow)
    wow.execute(f"{BR}.HomeRows = function() error('a draw that fails') end")
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert "Searching" not in summary(wow)
    assert "failed" in summary(wow)
    assert not any("Searching" in r for r in rows(wow))
    log = [line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"]
    assert any("a draw that fails" in line for line in log)


def test_a_provider_with_a_wrong_answer_costs_only_itself(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
          id = "t.number", label = "Number", priority = 500,
          search = function() return 7 end })
        Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
          id = "t.word", label = "Word", priority = 400,
          search = function() return { "not a result" } end })
        """
    )
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert found(wow, "Hogger")


def test_a_provider_that_never_ends_is_given_up(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        Bastians:RegisterSearchProvider(Bastians:GetModule('Browser'), {
          id = "t.forever", label = "Forever", priority = 500,
          search = function(_, _, yield) while true do yield() end end })
        """
    )
    typed(wow, "hogger")
    wow.run_frames(100, 0.25)  # 25 seconds, more than a provider's patience
    assert found(wow, "Hogger")
    assert wow.eval("Bastians.Jobs:Pending()") == 0
    log = [line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"]
    assert any("t.forever" in line for line in log)


def test_a_job_that_dies_still_ends_the_search(wow: WowRuntime):
    wow.start(CORE)
    wow.execute(
        """
        DONE = 0
        Bastians.Jobs:Run(nil, "dies", function() error("a job that dies") end, {
          onFail = function() DONE = DONE + 1 end })
        """
    )
    wow.run_frames(5)
    assert wow.eval("DONE") == 1
    assert wow.eval("Bastians.Jobs:Pending()") == 0


def test_typing_on_a_list_with_a_page_open_finds(wow: WowRuntime):
    """The owner's screen: a list, its page beside it, then the type word and a name in the box."""
    boot(wow)
    slow_provider(wow)
    wow.execute(f"{BR}.Navigate({{ kind = 'list', type = 'quest' }})")
    wow.run_frames(5)
    first = wow.eval(f"{TREE}.flat[1] and {TREE}.flat[2].ref")
    wow.execute(f"{BR}.Open({first!r})")
    wow.run_frames(5)
    typed(wow, "npc hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert found(wow, "Hogger")
    assert wow.eval(f"{BR}.PageRef()") == first  # the page stays


def test_a_search_typed_on_a_list_looks_in_every_list(wow: WowRuntime):
    """ "wolf" typed on Zones found nothing and offered "284 in the other
    lists. Click to look in all" - "it does not make sense to have to click there". The search is
    always global: "hogger" typed on the items' list finds Hogger at once, with no offer row."""
    boot(wow)
    wow.execute(f"{BR}.Navigate({{ kind = 'list', type = 'item' }})")
    wow.run_frames(5)
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert found(wow, "Hogger")
    assert not [r for r in wow.eval(f"{TREE}.flat").values() if str(r.id) == "s:others"]
    assert wow.errors == []


def test_a_type_word_with_no_hit_offers_nothing(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Navigate({{ kind = 'list', type = 'item' }})")
    wow.run_frames(5)
    typed(wow, "zone hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert not any(str(r.id) == "s:others" for r in wow.eval(f"{TREE}.flat").values())


def test_an_error_reaches_the_players_error_list(wow: WowRuntime):
    """The stuck search left BugSack empty: our errors stood only in /bastians log."""
    boot(wow)
    wow.execute(
        """
        BugGrabber, SEEN = {}, {}
        geterrorhandler = function() return function(e) SEEN[#SEEN + 1] = e end end
        """
    )
    wow.execute(f"{BR}.HomeRows = function() error('a draw that fails') end")
    typed(wow, "hogger")
    wow.run_frames(PATIENCE_FRAMES)
    assert any("a draw that fails" in str(e) for e in wow.eval("SEEN").values())
