"""Follow (ADR 0055, C7; quests.md "Follow"): a followed chain tracks the step the character is
on, and the next one as soon as it is in the log after the hand-in; kept per character; a finished
chain is no longer followed."""

from harness import WowRuntime

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
MOD = "Bastians:GetModule('Quests')"
CHAINS = f"{MOD}.Chains"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def settle(wow: WowRuntime) -> None:
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.run_frames(5)


def watched(wow: WowRuntime) -> list[int]:
    return sorted(wow.eval("Mock.watched").values())


def test_the_plan_tracks_a_step_once_and_drops_a_finished_chain(wow: WowRuntime):
    """Chains.FollowPlan, pure."""
    boot(wow)
    wow.execute(
        f"""
        local sheets = {{
          [1] = {{ state = "on", now = 2, main = {{ 10, 11, 12 }} }},   -- its step is in the log
          [2] = {{ state = "on", now = 1, main = {{ 20, 21 }} }},       -- tracked for it before
          [3] = {{ state = "finished", main = {{ 30, 31 }} }},
          [4] = {{ state = "start", now = 1, main = {{ 40, 41 }} }},    -- not in the log yet
          [5] = {{ state = "later", main = {{ 50, 51 }} }},             -- nothing to take
        }}
        local store = {{ [1] = 10, [2] = 20, [3] = 31, [4] = true, [5] = true, [6] = true }}
        local inLog = {{ [11] = true, [20] = true }}
        TRACK, DROP = {CHAINS}.FollowPlan(store, function(root) return sheets[root] end,
          function(qid) return inLog[qid] == true end)
        """
    )
    assert [(t.root, t.qid) for t in wow.eval("TRACK").values()] == [(1, 11)]
    assert list(wow.eval("DROP").values()) == [3]  # 6 has no answer (no data): left alone
    assert wow.errors == []


def test_following_tracks_the_step_and_then_the_next_one(wow: WowRuntime):
    boot(wow)
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    ref = f"chain:{root}"
    wow.execute(f"{MOD}.db.profile.autoTrack = false")  # so the tracking below is Follow's
    wow.execute("Mock.watched = {}")
    settle(wow)
    actions = "local out = {} for _, d in ipairs(Bastians:GetActions('%s', {})) do out[d.id] = d end return out"
    follow = wow.eval(f"(function() {actions % ref} end)()")["quests.chain.follow"]
    assert follow.short == "Follow" and follow.main is True
    assert wow.eval(f"{CHAINS}.IsFollowed({root})") is False
    # Follow: the step the character is on (62, in the log) is tracked at once
    wow.execute(f"Bastians:RunAction('quests.chain.follow', '{ref}', {{ source = 'test' }})")
    settle(wow)
    assert wow.eval(f"{CHAINS}.IsFollowed({root})") is True
    assert wow.eval(f"{MOD}:GetDB().char.followed[{root}]") == 62
    assert watched(wow) == [62]
    assert wow.eval(f"Bastians:GetAction('quests.chain.follow').active('{ref}')") is True
    # the player untracks it: following does not track it again
    wow.execute("Bastians:RunAction('quests.untrack', 'quest:62', { source = 'test' })")
    settle(wow)
    assert watched(wow) == []
    # the step is handed in: nothing to track until the next one is in the log
    wow.execute(
        "table.remove(Mock.questLog, 3); Mock.completedQuests[#Mock.completedQuests + 1] = 62"
    )
    wow.execute(f"{MOD}.State.MarkDone(62)")
    settle(wow)
    assert watched(wow) == []
    assert wow.eval(f"{MOD}:GetDB().char.followed[{root}]") == 62
    # the next step is taken: tracked by itself
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 76, title = 'The Jasperlode Mine',"
        " level = 9, complete = false, objectives = {} }"
    )
    settle(wow)
    assert watched(wow) == [76]
    assert wow.eval(f"{MOD}:GetDB().char.followed[{root}]") == 76
    # a second click stops following
    wow.execute(f"Bastians:RunAction('quests.chain.follow', '{ref}', {{ source = 'test' }})")
    assert wow.eval(f"{CHAINS}.IsFollowed({root})") is False
    assert watched(wow) == [76]  # what is tracked stays tracked
    assert wow.errors == []


def test_a_finished_chain_is_no_longer_followed(wow: WowRuntime):
    boot(wow)
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    wow.execute(f"{CHAINS}.SetFollowed({root}, true)")
    assert wow.eval(f"{CHAINS}.IsFollowed({root})") is True
    wow.execute("table.remove(Mock.questLog, 3)")
    for qid in (62, 76, 11):
        wow.execute(f"Mock.completedQuests[#Mock.completedQuests + 1] = {qid}")
        wow.execute(f"{MOD}.State.MarkDone({qid})")
    settle(wow)
    assert wow.eval(f"{CHAINS}.IsFollowed({root})") is False
    # a finished chain offers no Follow
    ids = "local out = {} for _, d in ipairs(Bastians:GetActions('chain:%d', {})) do out[d.id] = true end return out"
    assert wow.eval(f"(function() {ids % root} end)()")["quests.chain.follow"] is None
    assert wow.errors == []


def test_the_chains_sheet_carries_the_follow_button(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map", "Bastians_Browser")
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    browser = "Bastians:GetModule('Browser')"
    wow.execute(f"{browser}.Browser.Open('chain:{root}')")
    wow.advance(0.3)
    wow.run_frames(3)
    canvas = f"{MOD}.Sheet.Canvas({browser}.dossier.content)"

    def labels() -> list[str]:
        shown = [b for b in wow.eval(f"{canvas}.buttons").values() if b.IsShown(b)]
        shown.sort(key=lambda b: b.GetPoint(b, 1)[3])
        return [b.label.GetText(b.label) for b in shown]

    assert labels()[0] == "Follow"  # the first button, before the page's own
    wow.execute(f"{canvas}.buttons['quests.chain.follow']:Click()")
    wow.advance(0.3)
    wow.run_frames(3)
    assert wow.eval(f"{MOD}.Chains.IsFollowed({root})") is True
    assert labels()[0] == "Following"
    assert wow.errors == []


def test_a_followed_chain_says_so_on_its_tile(wow: WowRuntime):
    """ADR 0056, PA5: the list shows which chains you follow; Follow changes the mark at once."""
    boot(wow)
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    ref = f"chain:{root}"
    assert "Following" not in wow.eval(f"Bastians:Entity('{ref}'):Facet('tile').mark.text")
    wow.execute(f"{CHAINS}.SetFollowed({root}, true)")
    mark = wow.eval(f"Bastians:Entity('{ref}'):Facet('tile').mark")
    assert mark.text.startswith("Following ") and mark.token == "typeChain"
    wow.execute(f"{CHAINS}.SetFollowed({root}, false)")
    assert "Following" not in wow.eval(f"Bastians:Entity('{ref}'):Facet('tile').mark.text")


def test_a_chains_sheet_shows_the_map_and_the_route(wow: WowRuntime):
    """ADR 0056, PA5: the place of the step you are on, one click from the sheet."""
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map", "Bastians_Route")
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    main = wow.eval(
        f"""(function()
          local out = {{}}
          for _, a in ipairs(Bastians:GetActions("chain:{root}", {{}})) do
            if a.main then out[#out + 1] = a.id end
          end
          return table.concat(out, " ")
        end)()"""
    )
    assert "map.show" in main and "route.to" in main


def test_a_chains_sheet_says_what_the_way_pays(wow: WowRuntime):
    """ADR 0056, PA5: the main steps' items and choices, each thing once, in the way's order."""
    boot(wow)
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    wow.execute(
        f"""
        local rewards = {{
          [62] = {{ items = {{ {{ 2589, 1 }} }} }},
          [76] = {{ choices = {{ {{ 2318, 1 }}, {{ 2589, 1 }} }} }},
        }}
        local real = {MOD}.Logic.rewards
        {MOD}.Logic.rewards = function(id) return rewards[id] end
        ROWS = {CHAINS}.RewardRows("chain:{root}")
        {MOD}.Logic.rewards = function() return nil end
        NONE = {CHAINS}.RewardRows("chain:{root}")
        {MOD}.Logic.rewards = real
        """
    )
    assert [r.ref for r in wow.eval("ROWS").values()] == ["item:2589", "item:2318"]
    assert wow.eval("NONE") is None  # no rewards known: no card
