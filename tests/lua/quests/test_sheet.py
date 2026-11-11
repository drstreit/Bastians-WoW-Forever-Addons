"""The quest sheet and the client's rewards (ADR 0053): what the game says a quest pays is kept for
the account and wins over the pack; the sheet draws the task, the story and the rewards; the chain
symbol opens the chain's page; the map gives one quest its targets."""

import re

from harness import WowRuntime
from test_steps import MIRROR_LAKE

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
MOD = "Bastians:GetModule('Quests')"
SHEET = f"{MOD}.Sheet"
ELWYNN_VIEW = "{ continent = 0, level = 5, x1 = -2000, x2 = 2000, y1 = -2000, y2 = 2000 }"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def settle(wow: WowRuntime) -> None:
    wow.fire("QUEST_LOG_UPDATE")
    wow.advance(0.3)
    wow.run_frames(5)


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def drawn(wow: WowRuntime) -> list[str]:
    """The words on the sheet, top down."""
    wow.execute(
        """
        words = {}
        for _, region in ipairs({ BastiansQuestSheet:GetRegions() }) do
          if region.GetText and region:IsShown() and region:GetText() then
            local _, _, _, _, y = region:GetPoint(1)
            words[#words + 1] = { y or 0, region:GetText() }
          end
        end
        table.sort(words, function(a, b) return a[1] > b[1] end)
        """
    )
    return [strip(w[2]) for w in wow.eval("words").values()]


def test_the_clients_rewards_win_and_stay_after_the_hand_in(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.questRewards[176] = { money = 110, xp = 700, items = { { 2589, 2 } } }")
    wow.execute(f"{MOD}.Rewards.Forget()")
    settle(wow)
    rw = wow.eval(f"{MOD}.Logic.rewards(176)")
    assert (rw.money, rw.xp, rw.src) == (110, 700, "client")
    assert list(rw["items"][1].values()) == [2589, 2]
    # the account remembers: the quest gone from the log keeps what the game said
    assert wow.eval(f"{MOD}.db.global.rewards[176].xp") == 700
    wow.execute("Mock.questLog[2] = nil")
    settle(wow)
    assert wow.eval(f"{MOD}.Logic.rewards(176).money") == 110
    assert wow.errors == []


def test_the_reward_reads_answer_for_the_right_quest_and_restore_the_selection(wow: WowRuntime):
    """The mock's functions ignore their argument, as Era's do: only the selection counts."""
    boot(wow)
    wow.execute(
        """
        Mock.questRewards[176] = { money = 5 }
        Mock.questRewards[62] = { money = 9 }
        C_QuestLog.SetSelectedQuest(62)
        """
    )
    assert wow.eval("Bastians.Compat.GetQuestLogRewards(176).money") == 5
    assert wow.eval("C_QuestLog.GetSelectedQuest()") == 62
    assert wow.eval("Bastians.Compat.GetQuestLogRewards(12345)") is None  # not in the log
    assert wow.errors == []


def test_nothing_said_stays_unknown_never_zero(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians.Compat.GetQuestLogRewards(176)") is None
    wow.execute("Mock.questRewards[176] = { money = 0, xp = 0 }")
    assert wow.eval("Bastians.Compat.GetQuestLogRewards(176)") is None
    assert wow.errors == []


def test_rewards_are_not_read_in_combat(wow: WowRuntime):
    boot(wow)
    wow.execute(f"Mock.questRewards[176] = {{ xp = 700 }}; {MOD}.Rewards.Forget()")
    wow.set_combat(True)
    settle(wow)
    assert wow.eval(f"{MOD}.db.global.rewards[176]") is None
    wow.set_combat(False)
    settle(wow)
    assert wow.eval(f"{MOD}.db.global.rewards[176].xp") == 700
    assert wow.errors == []


def test_what_a_giver_offers_is_learned_before_the_quest_is_taken(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        Mock.questFrame.questID = 76
        Mock.questFrame.rewardMoney = 300
        Mock.questFrame.rewardXP = 450
        Mock.questFrame.rewards = { { 2589, 3 } }
        Mock.questFrame.choices = { { 1177, 5 }, { 2454, 2 } }
        """
    )
    wow.fire("QUEST_DETAIL")
    rw = wow.eval(f"{MOD}.Logic.rewards(76)")
    assert (rw.money, rw.xp) == (300, 450)
    assert [list(c.values()) for c in rw.choices.values()] == [[1177, 5], [2454, 2]]
    assert wow.errors == []


def test_the_sheet_draws_task_story_and_rewards_in_that_order(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        Mock.questLog[2].details = 'Are you looking for an opportunity?'
        Mock.questLog[2].objectivesText = 'Skin wolves around Elwynn Forest.'
        Mock.questRewards[176] = { money = 110, xp = 700 }
        """
    )
    wow.execute(f"{MOD}.Rewards.Forget()")
    settle(wow)
    wow.execute(f"{SHEET}.Open(176)")
    assert wow.eval(f"{SHEET}.IsShown()") is True
    words = drawn(wow)
    task = words.index("Skin wolves around Elwynn Forest.")
    story = words.index("Are you looking for an opportunity?")
    assert words.index("What to do") < task < words.index("The story") < story
    assert story < words.index("You will receive")
    wow.execute(f"{SHEET}.Close()")
    assert wow.eval("BastiansQuestSheet:IsShown()") is False
    assert wow.errors == []


def test_a_click_on_a_quest_opens_its_sheet_and_the_next_closes_it(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{SHEET}.Toggle(176)")
    assert wow.eval(f"{SHEET}.IsShown()") is True
    wow.execute(f"{SHEET}.Toggle(62)")  # another quest takes the page
    assert wow.eval(f"{SHEET}.IsShown()") is True and wow.eval(f"{SHEET}.Model(62).qid") == 62
    wow.execute(f"{SHEET}.Toggle(62)")
    assert wow.eval(f"{SHEET}.IsShown()") is False
    assert wow.errors == []


def test_the_sheet_shows_the_giver_and_the_target_as_figures(wow: WowRuntime):
    boot(wow)
    who = f"{SHEET}.TargetOf"
    assert wow.eval(f"({who}({{ objectives = {{ {{ 'kill', 'npc:97' }} }} }}))") == 97
    assert (
        wow.eval(f"({who}({{ objectives = {{ {{ 'loot', 'item:782', 0, 'npc:97' }} }} }}))") == 97
    )
    assert wow.eval(f"({who}({{ objectives = {{ {{ 'loot', 'item:782' }} }} }}))") is None
    assert wow.eval(f"({who}({{}}))") is None  # no objectives known: no second figure
    assert wow.eval(f"{SHEET}.Model(62).giverID") == 240
    wow.execute(f"{SHEET}.Open(62)")
    assert wow.errors == []


def test_a_done_quest_says_so_and_who_takes_it(wow: WowRuntime):
    boot(wow)
    model = wow.eval(f"{SHEET}.Model(62)")
    assert model.ready is True and model.handIn == "Hand in to Marshal Dughan"
    wow.execute(f"{SHEET}.Open(62)")
    assert "Done. Hand in to Marshal Dughan" in drawn(wow)
    assert "You receive" in drawn(wow)
    assert wow.errors == []


def test_a_quest_nobody_told_us_about_says_the_giver_will(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{SHEET}.Open(76)")
    assert "The giver tells you the rewards when you speak to them." in drawn(wow)
    assert wow.errors == []


def test_where_a_place_lies_in_words(wow: WowRuntime):
    boot(wow)
    compass = f"{SHEET}.Compass"
    assert wow.eval(f"{compass}(1, 0)") == "East"
    assert wow.eval(f"{compass}(0, 1)") == "South"  # y grows south on a map
    assert wow.eval(f"{compass}(-1, -1)") == "North-west"
    words = f"{SHEET}.WhereWords"
    here = "{ map = 1429, x = 0.5, y = 0.5 }"
    there = "{ map = 1429, x = 0.8, y = 0.5 }"
    assert wow.eval(f"{words}({here}, {there}, 296)") == "East, about 300 yards"
    assert wow.eval(f"{words}({here}, {there}, 12)") == "Right here"
    assert wow.eval(f"{words}({here}, {there}, nil)") == "East"
    assert wow.eval(f"{words}({here}, {{ map = 1453, x = 0.1, y = 0.1 }}, nil)").startswith("In ")
    assert wow.eval(f"{words}({here}, {{}}, nil)") is None  # unknown stays unsaid
    assert wow.errors == []


def test_the_chain_symbol_opens_the_chains_page_in_quests_own_window(wow: WowRuntime):
    """ADR 0055: the chain is a subject. Without the Browser its page is Quests' own window: the
    way, then where it goes, as rows in the reading column. No chain window exists any more."""
    boot(wow)
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    assert wow.eval("Bastians:RunAction('quests.chain', 'quest:62', { source = 'test' })") is True
    wow.advance(0.3)
    wow.run_frames(3)
    assert wow.eval("BastiansQuestChain") is None
    assert wow.eval("BastiansQuestSheet") is None  # the sheet was not touched
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == f"chain:{root}"
    data = wow.eval(f"{MOD}.Window.dossier.data")
    assert [(c.id, c.title) for c in data.chapters.values()] == [
        ("steps", "The way"),
        ("zones", "Where it goes"),
    ]
    way = next(iter(data.chapters.values())).blocks[1].rows
    assert [(r.ref, strip(r.text)) for r in way.values()] == [
        ("quest:62", "1. The Fargodeep Mine"),
        ("quest:76", "2. The Jasperlode Mine"),
        ("quest:11", "3. Riverpaw Gnoll Bounty"),
    ]
    assert wow.errors == []


def test_the_chain_symbol_opens_the_chains_page_in_the_browser(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map", "Bastians_Browser")
    root = wow.eval(f"{MOD}.Logic.chainRoot(76)")
    # from any quest of the chain, not only its first
    assert wow.eval("Bastians:RunAction('quests.chain', 'quest:76', { source = 'test' })") is True
    wow.advance(0.3)
    wow.run_frames(3)
    assert wow.eval("Bastians:GetModule('Browser').Browser.PageRef()") == f"chain:{root}"
    assert wow.eval("BastiansQuestChain") is None
    assert wow.errors == []


def test_the_way_says_a_step_ready_to_hand_in_and_what_is_still_ahead(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map", "Bastians_Browser")
    root = wow.eval(f"{MOD}.Logic.chainRoot(62)")
    wow.execute(f"Bastians:GetModule('Browser').Browser.Open('chain:{root}')")
    wow.advance(0.3)
    wow.run_frames(3)
    canvas = f"{SHEET}.Canvas(Bastians:GetModule('Browser').dossier.content)"
    first = wow.eval(f"{canvas}.steps[1]")
    assert first.sub.GetText(first.sub) == "Level 7 - You are here: hand it in"  # 62 is complete

    def words() -> list[str]:
        return [t.GetText(t) for t in wow.eval(f"{canvas}.texts").values() if t.IsShown(t)]

    # no reward is known for a step: nothing is said (unknown is not zero)
    assert not any(w.startswith("Still ahead") for w in words())
    wow.execute(f"Mock.questRewards[62] = {{ xp = 450, money = 300 }}; {MOD}.Rewards.Forget()")
    settle(wow)
    wow.execute("Bastians:GetModule('Browser').dossier:Layout()")
    wow.run_frames(3)
    assert "Still ahead: 450 XP, 3s 00c." in [strip(w) for w in words()]
    assert wow.errors == []


STRIP = """
(function()
  local out = { links = {}, dots = {} }
  local canvas = %s
  for key, b in pairs(canvas.links) do
    if b:IsShown() then
      out.links[key] = { text = b.text:GetText(), mouse = b:IsMouseEnabled(), tip = b.tip }
    end
  end
  for _, d in ipairs(canvas.dots) do
    if d:IsShown() then out.dots[#out.dots + 1] = d:GetWidth() end
  end
  return out
end)()
"""


def test_a_quest_in_a_chain_says_its_step_under_its_name(wow: WowRuntime):
    """quests.md "On a quest": the strip under the name. The step and the chain's name, a dot per
    step (the quest of the sheet larger), the step before and the step after."""
    boot(wow)
    strip = wow.eval(f"{SHEET}.Strip(76, {MOD}.State.ForLogic())")
    assert (strip.words, strip.name, strip.step) == ("Step 2 of 3", "The Fargodeep Mine", 2)
    assert list(strip.kinds.values()) == ["now", "later", "later"]
    assert (strip.prev, strip.prevStep, strip.next, strip.nextStep) == (62, 1, 11, 3)
    first = wow.eval(f"{SHEET}.Strip(62, {MOD}.State.ForLogic())")
    assert (first.prev, first.next) == (None, 76)
    assert wow.eval(f"{SHEET}.Strip(176, {MOD}.State.ForLogic())") is None  # no chain, no strip
    wow.execute(f"{SHEET}.Open(76)")
    wow.execute(f"BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    drawn_strip = wow.eval(STRIP % "BST_CANVAS")
    links = {k: (v.text, v.mouse) for k, v in drawn_strip.links.items()}
    assert links == {
        "strip.chain": ("Step 2 of 3 - The Fargodeep Mine", True),
        "strip.prev": ("< 1. The Fargodeep Mine", True),
        "strip.next": ("3. Riverpaw Gnoll Bounty >", True),
    }
    dots = list(drawn_strip.dots.values())
    assert len(dots) == 3 and dots[1] > dots[0] == dots[2]  # the second step is this quest
    labels = [b.label.GetText(b.label) for b in wow.eval("BST_CANVAS.buttons").values()]
    assert "Chain" not in labels  # the strip is the way to the chain
    # the step after opens that quest's sheet
    wow.execute("BST_CANVAS.links['strip.next']:Click()")
    assert drawn(wow)[0] == "Riverpaw Gnoll Bounty"
    assert wow.eval(STRIP % "BST_CANVAS").links["strip.chain"].text == (
        "Step 3 of 3 - The Fargodeep Mine"
    )
    assert "strip.next" not in wow.eval(STRIP % "BST_CANVAS").links  # the last step has none
    # the chain's name opens the chain's page
    wow.execute("BST_CANVAS.links['strip.chain']:Click()")
    wow.advance(0.3)
    root = wow.eval(f"{MOD}.Logic.chainRoot(76)")
    assert wow.eval("Bastians:GetService('views'):CurrentPage()") == f"chain:{root}"
    # a quest alone: the strip's parts are gone
    wow.execute(f"{SHEET}.Open(176)")
    alone = wow.eval(STRIP % "BST_CANVAS")
    assert len(alone.links) == 0 and len(alone.dots) == 0
    # on a hover the mouse cannot reach the words
    wow.execute(f"{SHEET}.Preview(76, {{}})")
    assert wow.eval(STRIP % "BST_CANVAS").links["strip.chain"].mouse is False
    assert wow.errors == []


def test_the_strip_in_a_hosts_page_opens_the_chain_there(wow: WowRuntime):
    boot(wow, CORE, DATA, QUESTS, "Bastians_Map", "Bastians_Browser")
    browser = "Bastians:GetModule('Browser')"
    wow.execute(f"{browser}.Browser.Open('quest:76')")
    wow.advance(0.3)
    wow.run_frames(3)
    canvas = f"{SHEET}.Canvas({browser}.dossier.content)"
    assert wow.eval(STRIP % canvas).links["strip.chain"].text == "Step 2 of 3 - The Fargodeep Mine"
    wow.execute(f"{canvas}.links['strip.prev']:Click()")
    wow.run_frames(3)
    assert wow.eval(f"{browser}.Browser.PageRef()") == "quest:62"
    wow.execute(f"{canvas}.links['strip.chain']:Click()")
    wow.run_frames(3)
    root = wow.eval(f"{MOD}.Logic.chainRoot(76)")
    assert wow.eval(f"{browser}.Browser.PageRef()") == f"chain:{root}"
    assert wow.errors == []


def test_a_side_quest_and_a_long_chain_on_the_strip(wow: WowRuntime):
    """A side quest says the step it hangs under; beyond twelve steps the dots are a bar."""
    boot(wow)
    wow.execute(
        """
        local quests = { [50] = { name = "A Letter", zone = 10, level = 5, pre = { 3 } } }
        for i = 1, 14 do
          quests[i] = { name = "The Long Road", zone = 10, level = 5, pre = i > 1 and { i - 1 } or nil }
        end
        quests[60] = { name = "A Rumour", zone = 10, level = 5 }
        quests[2].preAny = { 60 }
        local ids = {}
        for id in pairs(quests) do ids[#ids + 1] = id end
        table.sort(ids)
        Bastians:GetModule('Quests').Logic.SetData({
          Get = function(_, typ, id) return typ == "quest" and quests[id] or nil end,
          Index = function(_, name, key)
            if name == "quest.byZone" then
              if key == nil then return { [1] = ids } end
              return key == 1 and ids or nil
            end
            return nil
          end,
        })
        """
    )
    state = f"{MOD}.State.ForLogic()"
    side = wow.eval(f"{SHEET}.Strip(50, {state})")
    assert (side.words, side.step, side.prev, side.next) == (
        "Side quest after step 3 of 14",
        None,
        3,
        None,
    )
    assert wow.eval(f"{SHEET}.Strip(60, {state})").words == "Another way into the chain"
    assert len(wow.eval(f"{SHEET}.Strip(7, {state})").kinds) == 14
    wow.execute(f"{SHEET}.Open(7)")
    wow.execute(f"BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    bar = list(wow.eval(STRIP % "BST_CANVAS").dots.values())
    # the track, and over it what is done (the mock's character has done one of the fourteen)
    assert bar[0] == 96 and [round(w, 1) for w in bar[1:]] == [round(96 / 14, 1)]
    assert wow.errors == []


def test_the_chain_symbol_is_offered_only_for_a_chain(wow: WowRuntime):
    boot(wow)
    ids = "local out = {} for _, d in ipairs(Bastians:GetActions('quest:%d', {})) do out[d.id] = true end return out"
    assert wow.eval(f"(function() {ids % 62} end)()")["quests.chain"] is True
    assert wow.eval(f"(function() {ids % 176} end)()")["quests.chain"] is None
    assert wow.errors == []


def test_the_map_gives_one_quest_its_targets(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 76, title = 'The Jasperlode Mine', level = 9,"
        " complete = false, objectives = {} }"
    )
    settle(wow)
    assert wow.eval(f"{MOD}.Registrations.FocusQuest()") == 176  # the nearest open one with a spot
    wow.execute("Bastians:Focus('quest:76', { source = 'test' })")
    assert wow.eval(f"{MOD}.Registrations.FocusQuest()") == 76  # the focused quest takes the map
    pins = wow.eval(f"Bastians:QueryLayer('quests.objectives', {ELWYNN_VIEW})")
    assert not any(p.ref == "quest:176" for p in pins.values())
    assert wow.errors == []


def test_an_open_quests_hand_in_shows_only_in_focus(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.questLog[2].complete = false; Mock.questLog[3].complete = false")
    settle(wow)
    wow.execute("Bastians:Focus('quest:62', { source = 'test' })")
    pins = wow.eval(f"Bastians:QueryLayer('quests.turnin', {ELWYNN_VIEW})")
    assert [p.ref for p in pins.values()] == ["npc:240"]
    wow.execute("Bastians:Focus(nil)")
    assert wow.errors == []


def test_a_quest_without_a_spot_takes_the_clients_poi(wow: WowRuntime):
    """Forever's own quests have no spots in any source; the client's POI says where."""
    boot(wow)
    wow.execute(
        """
        Mock.questLog[#Mock.questLog + 1] = { questID = 99999, title = 'Rough Wolf Pelts', level = 8,
          complete = false, objectives = {} }
        Mock.waypoints[99999] = { map = 1429, x = 0.42, y = 0.65 }
        """
    )
    settle(wow)
    assert wow.eval(f"{MOD}.Registrations.FocusQuest()") == 99999
    assert wow.errors == []


def test_quests_loads_without_data_and_the_sheet_still_opens(wow: WowRuntime):
    boot(wow, CORE, QUESTS)
    wow.execute(f"{SHEET}.Open(176)")
    assert wow.eval("BastiansQuestSheet:IsShown()") is True
    assert wow.errors == []


def test_disabling_quests_takes_the_service_away(wow: WowRuntime):
    boot(wow)
    assert wow.eval("Bastians:GetService('questSheet') ~= nil") is True
    wow.execute("Bastians:GetModule('Quests'):Disable()")
    assert wow.eval("Bastians:GetService('questSheet') == nil") is True
    wow.execute("Bastians:GetModule('Quests'):Enable()")
    assert wow.eval("Bastians:GetService('questSheet') ~= nil") is True
    assert wow.errors == []


def test_a_preview_opens_on_the_side_of_its_anchor_that_has_room(wow: WowRuntime):
    """the Orbiter can stand anywhere, so the sheet beside it "is not
    static": right of an anchor in the left half of the screen, left of one in the right half."""
    boot(wow)
    assert wow.eval(f"{SHEET}.Side(300, 1920)") == "RIGHT"
    assert wow.eval(f"{SHEET}.Side(1500, 1920)") == "LEFT"
    assert wow.eval(f"{SHEET}.Side(nil, 1920)") == "RIGHT"  # an anchor without a place yet
    # the mock's frames have no place on the screen: the anchor says its centre itself
    wow.execute(
        """Anchor = CreateFrame("Frame", nil, UIParent)
        Anchor:SetSize(100, 100)
        Anchor.GetCenter = function() return 200, 500 end"""
    )
    wow.execute(f"{SHEET}.Preview(176, {{ anchor = Anchor }})")
    point = wow.eval("BastiansQuestSheet.points[1]")
    assert (point.point, point.relPoint, point.x) == ("LEFT", "RIGHT", 12)
    wow.execute("Anchor.GetCenter = function() return UIParent:GetWidth() - 200, 500 end")
    wow.execute(f"{SHEET}.Preview(176, {{ anchor = Anchor }})")
    point = wow.eval("BastiansQuestSheet.points[1]")
    assert (point.point, point.relPoint, point.x) == ("RIGHT", "LEFT", -12)
    # a caller that knows the side says it (the Orbiter keeps its centre in UI units)
    wow.execute(f"{SHEET}.Preview(176, {{ anchor = Anchor, side = 'RIGHT' }})")
    assert wow.eval("BastiansQuestSheet.points[1].point") == "LEFT"
    wow.execute(f"{SHEET}.EndPreview()")
    assert wow.errors == []


def test_the_sheet_draws_into_a_hosts_frame_in_the_hosts_colours(wow: WowRuntime):
    """ADR 0056, one quest sheet: the same drawing in a frame a host gives (the Browser's page
    tile). There it takes the page's own colours and width, carries the host's buttons after the
    quest's, and leaves the sheet's own window alone."""
    boot(wow)
    style = "Bastians.UI.Style"
    wow.execute(
        f"""
        page = CreateFrame("Frame", nil, UIParent)
        page:SetSize(900, 600)
        ran = {{}}
        host = {{ frame = page, width = 900, ctx = {{ source = "browser" }},
          buttons = {{ {{ key = "host1", label = "Bookmark", run = function() ran[#ran + 1] = "bookmark" end }} }} }}
        height = {SHEET}.DrawInto("quest:176", host)
        canvas = {SHEET}.Canvas(page)
        """
    )
    assert wow.eval("height") > 100 and wow.eval("canvas.frame:GetParent() == page") is True
    assert wow.eval("canvas.width") == 640  # a line stays readable on a wide page
    assert wow.eval("canvas.frame:GetHeight()") == wow.eval("height")
    title = "canvas.texts[1]"
    assert wow.eval(f"{title}:GetText()") == "The Fargodeep Mine"  # as the log names it
    ink = [round(v, 3) for v in wow.eval(f"{{ {title}:GetTextColor() }}").values()][:3]
    accent = [round(v, 3) for v in wow.eval(f"{style}.C.accent").values()][:3]
    paper = [round(v, 3) for v in wow.eval(f"{style}.C.sheetTitle").values()][:3]
    assert ink == accent and ink != paper  # the page's colours, not the sheet's own paper
    labels = [b.label.GetText(b.label) for b in wow.eval("canvas.buttons").values() if b.IsShown(b)]
    assert "Bookmark" in labels and "Track" in labels
    wow.execute("canvas.buttons.host1:Click()")
    assert list(wow.eval("ran").values()) == ["bookmark"]
    # a narrow host: the sheet takes its width
    wow.execute(f"host.width = 300; {SHEET}.DrawInto('quest:176', host)")
    assert wow.eval("canvas.width") == 300
    # the sheet's own window draws beside it, on its own paper, untouched by the host's draw
    wow.execute(f"{SHEET}.Open(176)")
    words = drawn(wow)
    assert words[0] == "The Fargodeep Mine" and "What to do" in words
    own = [
        round(v, 3)
        for v in wow.eval(
            "(function() for _, r in ipairs({ BastiansQuestSheet:GetRegions() }) do "
            "if r.GetText and r:GetText() == 'The Fargodeep Mine' then return { r:GetTextColor() } end "
            "end end)()"
        ).values()
    ][:3]
    assert own == paper
    assert wow.eval("canvas.frame:IsShown()") is True
    # the host shows something else: the hosted parts go, the window stays
    wow.execute(f"{SHEET}.HideIn(host)")
    assert wow.eval("canvas.frame:IsShown()") is False and wow.eval(f"{SHEET}.IsShown()") is True
    assert wow.eval(f"{SHEET}.DrawInto('npc:240', host)") == 0  # no quest, nothing drawn
    assert wow.errors == []


def test_the_giver_has_a_way_there(wow: WowRuntime):
    """ "im quest detail window sollte der questgeber eine route to haben"."""
    boot(wow)
    wow.execute(f"{SHEET}.Open(62) ; BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    assert wow.eval("BST_CANVAS.buttons['route.giver']") is None  # no Route: no button
    wow.execute(
        """Ran = nil
        Bastians:RegisterAction(Bastians:GetModule('Quests'), { id = 'route.to', label = 'Route to',
          types = { 'npc', 'quest', 'item', 'object', 'spot', 'zone' }, order = 1,
          run = function(ref) Ran = ref end })"""
    )
    wow.execute(f"{SHEET}.Close() ; {SHEET}.Open(62)")
    button = "BST_CANVAS.buttons['route.giver']"
    assert wow.eval(f"{button}.label:GetText()") == "Route to the giver"
    wow.execute(f"{button}:Click()")
    assert wow.eval("Ran") == "npc:240"
    assert wow.errors == []


SPIDER_MEAT = """
STEP = { step = "get", ref = "item:1080", places = {
  { map = 1433, x = 0.1, y = 0.1 }, { map = 1433, x = 0.2, y = 0.2, ref = "npc:547" },
  { map = 1436, x = 0.4, y = 0.4 }, { map = 1424, x = 0.5, y = 0.5 },
} }
function XS(where, home)
  local places, map = Bastians:GetModule('Quests').Logic.StepPlaces(STEP, where, home)
  if not places then return nil end
  local out = {}
  for _, p in ipairs(places) do out[#out + 1] = p.map .. ":" .. p.x end
  return table.concat(out, " ") .. " on " .. map
end
"""


def test_a_steps_places_show_on_one_map(wow: WowRuntime):
    """ "for all parts of the quest a map link to open the map with that
    monster spawn visible. Or if I collect an items, then that." Spider meat drops in twelve
    zones: the map must not fly to the wrong one. The player's map, where the quest lives, the
    nearest, else the lowest id."""
    boot(wow)
    wow.execute(SPIDER_MEAT)
    assert wow.eval("XS({ map = 1436 })") == "1436:0.4 on 1436"  # where the player is
    assert wow.eval("XS({ map = 1 }, { 1433 })") == "1433:0.1 1433:0.2 on 1433"  # the quest's own
    assert wow.eval("XS({ map = 1 }, { 9, 1424 })") == "1424:0.5 on 1424"  # its hand-in's
    wow.execute(
        "NEAR = { map = 1, yards = function(map) return ({ [1433] = 900, [1436] = 300 })[map] end }"
    )
    assert wow.eval("XS(NEAR)") == "1436:0.4 on 1436"  # a measured one before an unmeasured
    # an unknown distance is no distance: the lowest map, so the same every time
    assert wow.eval("XS({ map = 1 })") == "1424:0.5 on 1424"
    # a step without a place has none: a wrong map is worse than no link
    logic = f"{MOD}.Logic.StepPlaces"
    assert wow.eval(f"{logic}({{ step = 'get', places = {{}} }}, {{ map = 1433 }})") is None
    assert wow.eval(f"{logic}(nil, {{}})") is None
    assert wow.errors == []


def test_the_nearest_place_is_on_the_viewed_map_before_any_other(wow: WowRuntime):
    """What every reader of Quests takes of a quest's places (ADR 0069): one rule, so the log's
    row, the sheet's line and the map's quest agree."""
    boot(wow)
    wow.execute(
        """
        PLACES = { { map = 1436, x = 0.5, y = 0.5 }, { map = 1429, x = 0.9, y = 0.9 },
          { map = 1429, x = 0.3, y = 0.3 }, { map = 1424, x = 0.1, y = 0.1 } }
        function NP(where)
          local p, d = Bastians:GetModule('Quests').Logic.NearestPlace(PLACES, where)
          return p and (p.map .. ":" .. p.x) or nil, d
        end
        """
    )
    near, d = wow.eval("NP({ map = 1429, x = 0.2, y = 0.3 })")
    assert near == "1429:0.3" and abs(d - 0.01) < 1e-9  # squared map fractions, for sorting
    # on the viewed map without a position: the first there
    assert wow.eval("NP({ map = 1429 })") == ("1429:0.9", float("inf"))
    # not on the viewed map: by yards, where they are known
    wow.execute("YARDS = function(map) return ({ [1436] = 800, [1424] = 200 })[map] end")
    assert wow.eval("(NP({ map = 1, x = 0.5, y = 0.5, yards = YARDS }))") == "1424:0.1"
    wow.execute("YARDS = function(map) return ({ [1436] = 800 })[map] end")
    assert wow.eval("(NP({ map = 1, yards = YARDS }))") == "1436:0.5"  # a measured one first
    assert wow.eval("(NP({ map = 1 }))") == "1424:0.1"  # nothing measured: the lowest map id
    assert wow.eval(f"{MOD}.Logic.NearestPlace({{}}, {{ map = 1 }})") is None
    assert wow.eval(f"{MOD}.Logic.NearestPlace(nil)") is None
    assert wow.errors == []


def show_on_map_stand_in(wow: WowRuntime) -> None:
    wow.execute(
        """Ran = nil
        Bastians:RegisterAction(Bastians:GetModule('Quests'), { id = 'map.show', label = 'Show on map',
          short = 'Map', types = '*', order = 10,
          when = function(ref, ctx)
            return (ctx and ctx.points ~= nil) or #Bastians:Entity(ref):Locations() > 0
          end,
          run = function(ref, ctx) Ran = { ref = ref, points = ctx.points } end })"""
    )


def route_to_stand_in(wow: WowRuntime) -> None:
    wow.execute(
        """Routed = nil
        Bastians:RegisterAction(Bastians:GetModule('Quests'), { id = 'route.to', label = 'Route to',
          types = '*', order = 15,
          when = function(ref) return #Bastians:Entity(ref):Locations() > 0 end,
          run = function(ref) Routed = ref end })"""
    )


LINEN = """Mock.questLog[2].objectives = {
  { text = "Linen Cloth: 2/5", type = "item", finished = false, numFulfilled = 2, numRequired = 5 },
}"""


def test_every_objective_line_has_its_map_button(wow: WowRuntime):
    boot(wow)
    wow.execute(LINEN)
    wow.execute(
        """table.insert(Mock.questLog[2].objectives,
          { text = "Find the cave", type = "event", finished = false })"""
    )
    settle(wow)
    show_on_map_stand_in(wow)
    wow.execute(f"{SHEET}.Open(176) ; BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    button = "BST_CANVAS.buttons['objective.map.1']"
    assert wow.eval(f"{button}.label:GetText()") == "Map"
    assert wow.eval(f"{button}.tip") == "Show on map"
    assert wow.eval("BST_CANVAS.buttons['objective.map.2']") is None  # nothing to show: no button
    wow.execute(f"{button}:Click()")
    # the step with the client's number: the item it asks for, at the places of the step
    assert wow.eval("Ran.ref") == "item:1931"
    assert wow.eval("#Ran.points") == 2 and wow.eval("Ran.points[1].map") == 1429
    places, ref = wow.eval(f"{SHEET}.ObjectivePlaces(176, 1)")
    assert ref == "item:1931" and len(list(places.values())) == 2
    # the exploration is a step the data does not know: no place
    assert wow.eval(f"({SHEET}.ObjectivePlaces(176, 2))") is None
    assert wow.eval(f"({SHEET}.ObjectivePlaces(176, 3))") is None  # no step is that objective
    assert wow.eval(f"({SHEET}.ObjectivePlaces(424242, 1))") is None
    assert "2/5 Linen Cloth" in drawn(wow)
    assert wow.errors == []


def test_no_map_button_on_a_hover_or_without_the_map(wow: WowRuntime):
    boot(wow)
    wow.execute(LINEN)
    settle(wow)
    wow.execute(f"{SHEET}.Open(176) ; BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    assert wow.eval("BST_CANVAS.buttons['objective.map.1']") is None  # no Map addon, no button
    show_on_map_stand_in(wow)
    wow.execute(f"{SHEET}.Close() ; {SHEET}.Preview(176, {{}})")
    assert wow.eval("BST_CANVAS.buttons['objective.map.1']") is None  # the mouse cannot reach it
    assert "2/5 Linen Cloth" in drawn(wow)
    assert wow.errors == []


def test_a_place_nobody_knows_is_said_and_map_and_route_are_greyed(wow: WowRuntime):
    """("Mirror Lake": Map and Route led back to the giver): "no place
    and grayed buttons". The sheet says so in one line; "Route to the giver" stays."""
    boot(wow)
    show_on_map_stand_in(wow)
    route_to_stand_in(wow)
    wow.execute(MIRROR_LAKE)
    settle(wow)
    wow.execute(f"{SHEET}.Open(76) ; BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    assert "Where this is done is not known" in drawn(wow)
    for key in ("map.show", "route.to"):
        button = f"BST_CANVAS.buttons['{key}']"
        assert wow.eval(f"{button}:IsShown()") is True
        assert wow.eval(f"{button}.enabledFlat") is False and wow.eval(f"{button}:GetAlpha()") < 1
        assert wow.eval(f"{button}.tip") == "Where this is done is not known"
        wow.execute(f"{button}:Click()")
    assert wow.eval("Ran") is None and wow.eval("Routed") is None  # nothing to run
    giver = "BST_CANVAS.buttons['route.giver']"
    assert wow.eval(f"{giver}.enabledFlat") is not False
    wow.execute(f"{giver}:Click()")
    assert wow.eval("Routed") == "npc:240"
    model = wow.eval(f"{SHEET}.Model(76)")
    assert model.unplaced is True and model.where == "Where this is done is not known"
    # the client knows the place: the line is a direction again, the buttons run
    wow.execute("Mock.waypoints[76] = { map = 1429, x = 0.29, y = 0.61 }")
    settle(wow)
    wow.execute(f"{SHEET}.Close() ; {SHEET}.Open(76)")
    model = wow.eval(f"{SHEET}.Model(76)")
    assert model.unplaced is None and "yards" in model.where
    assert "Where this is done is not known" not in drawn(wow)
    wow.execute("BST_CANVAS.buttons['route.to']:Click()")
    assert wow.eval("BST_CANVAS.buttons['route.to'].enabledFlat") is True
    assert wow.eval("Routed") == "quest:76"
    assert wow.errors == []


def test_no_greyed_button_without_the_apps(wow: WowRuntime):
    boot(wow)
    wow.execute(MIRROR_LAKE)
    settle(wow)
    wow.execute(f"{SHEET}.Open(76) ; BST_CANVAS = {SHEET}.Canvas(BastiansQuestSheet)")
    assert "Where this is done is not known" in drawn(wow)  # the line needs no app
    assert wow.eval("BST_CANVAS.buttons['map.show']") is None
    assert wow.eval("BST_CANVAS.buttons['route.to']") is None
    assert wow.errors == []


def test_a_done_quest_nobody_can_place_keeps_its_done_line(wow: WowRuntime):
    """Complete, in no source, and the client names no place: Map and Route are greyed, and the
    sheet does not say "where this is done" of a quest that is done."""
    boot(wow)
    wow.execute(
        "Mock.questLog[#Mock.questLog + 1] = { questID = 99999, title = 'A Song for Our Future', "
        "level = 10, complete = true, objectives = {} }"
    )
    settle(wow)
    model = wow.eval(f"{SHEET}.Model(99999)")
    assert (model.ready, model.unplaced, model.where) == (True, True, None)
    wow.execute(f"{SHEET}.Open(99999)")
    assert "Where this is done is not known" not in drawn(wow)
    assert wow.errors == []


def test_the_map_shows_what_has_no_place_of_its_own_at_the_places_named(wow: WowRuntime):
    """An item has no spawns: "Show on map" of a collect objective lives on the places it is given."""
    boot(wow, CORE, DATA, "Bastians_Map", QUESTS)
    ctx = "{ source = 'sheet', points = { { map = 1429, x = 0.4, y = 0.7 } } }"
    assert wow.eval(f"Bastians:GetAction('map.show').when('item:2589', {ctx})") is True
    wow.execute(f"Bastians:RunAction('map.show', 'item:2589', {ctx})")
    assert wow.eval("Bastians:Focused()") == "item:2589"
    # without places an item stays what it was: not offered
    assert (
        wow.eval("Bastians:GetAction('map.show').when('item:2589', { source = 'sheet' })") is False
    )
    assert wow.errors == []
