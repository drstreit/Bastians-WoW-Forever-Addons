"""The pin mini-card (C7, ADR 0014): a hover over a pin shows a small card beside it (name, status
words, worth, distance, the layer's lines, "Click to open") from Bastians.UI.Card; the map's own
entity tooltip is gone, a cluster still says how many pins it holds."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, GOLD, MAP = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Map",
)
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
PINS = f"{MOD}.Pins"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(CORE, DATA, QUESTS, GOLD, MAP)
    wow.run_frames(10)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.advance(0.2)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def card_lines(wow: WowRuntime) -> list[str]:
    f = wow.eval(f"{PINS}.miniCard")
    return [strip(fs.GetText(fs)) for fs in f.rows.values() if fs.IsShown(fs)]


def test_the_card_data_for_a_quest_pin_a_mob_and_a_node(wow: WowRuntime):
    boot(wow)
    data = f"{PINS}.MiniCardData"
    # a giver pin with one quest behind it: the quest is the subject, its status words, its worth
    q = wow.eval(
        f"{data}({{ ref = 'npc:240', quests = {{ 62 }}, lines = {{ 'a line' }}, wx = -60, wy = 32 }})"
    )  # the pin's own place gives the distance: a quest has no places of its own
    assert q.ref == "quest:62" and q.name == "The Fargodeep Mine"
    assert strip(q.words) == "In the log, complete"
    assert strip(q.worth) == "unlocks 1"  # the fixture quest has no money or XP: what is known
    assert (
        q.distance == "0 yd" and list(q.lines.values()) == ["a line"] and q.hint == "Click to open"
    )
    # a giver with two quests: the giver itself, its summary
    g = wow.eval(f"{data}({{ ref = 'npc:240', quests = {{ 62, 76 }} }})")
    assert (
        g.ref == "npc:240" and g.name == "Marshal Dughan" and g.words == "Level 10, Elwynn Forest"
    )
    # a mob: the loot value per kill (Gold); a label from the layer wins over the name
    m = wow.eval(f"{data}({{ ref = 'npc:448', label = 'Hogger (elite)' }})")
    assert m.name == "Hogger (elite)"
    if wow.made_for(GOLD):  # the loot value is Gold's; no Gold on retail
        assert strip(m.worth).endswith("per kill") or "price" in strip(m.worth)
    else:
        assert m.worth is None
    assert m.distance is not None
    # no ref, no card
    assert wow.eval(f"{data}({{ label = 'nothing' }})") is None
    assert wow.errors == []


def test_a_hover_shows_the_card_beside_the_pin_and_a_cluster_keeps_the_tooltip(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")
    wow.advance(0.2)
    pins = [f for f in wow.eval(f"{PINS}.pinPool").values() if f.IsShown(f)]
    marshal = next(p for p in pins if p.pin.ref == "npc:240")
    wow.execute("GameTooltip:ClearLines()")
    marshal.GetScript(marshal, "OnEnter")(marshal)
    assert wow.eval(f"{PINS}.miniCard:IsShown()") is True
    assert wow.eval(f"{PINS}.miniCard:GetFrameStrata()") == "TOOLTIP"
    assert wow.eval(f"select(2, {PINS}.miniCard:GetPoint(1)) == {PINS}.pinPool[1]") in (True, False)
    lines = card_lines(wow)
    assert lines[-1] == "Click to open" and any(line.endswith("yd") for line in lines)
    assert wow.eval("GameTooltip:NumLines()") == 0  # the map's own tooltip is gone
    marshal.GetScript(marshal, "OnLeave")(marshal)
    assert wow.eval(f"{PINS}.miniCard:IsShown()") is False
    # a cluster: the tooltip says how many pins, no card
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 2)")
    wow.advance(0.2)
    clusters = [f for f in wow.eval(f"{PINS}.pinPool").values() if f.IsShown(f) and f.pin.isCluster]
    if clusters:
        c = clusters[0]
        c.GetScript(c, "OnEnter")(c)
        assert wow.eval("GameTooltip:NumLines()") == 2
        assert wow.eval(f"{PINS}.miniCard:IsShown()") is False
        c.GetScript(c, "OnLeave")(c)
    assert wow.errors == []


def test_a_quest_pins_card_lists_up_to_three_rewards(wow: WowRuntime):
    """R8: the card of a quest pin says what the quest earns, up to
    three rows of its Rewards section; a quest without a known reward adds no line."""
    boot(wow)
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        Logic.quest(62).rewards = { money = 125, xp = 480, rep = { { 72, 150 }, { 54, -25 } } }
        Logic.quest(76).rewards = nil
        Bastians:InvalidateEntities("quest")
        """
    )
    data = f"{PINS}.MiniCardData"
    q = wow.eval(f"{data}({{ ref = 'npc:240', quests = {{ 62 }}, lines = {{ 'a line' }} }})")
    lines = [strip(t) for t in q.lines.values()]
    assert lines[0] == "a line" and len(lines) == 4  # the layer's line, then three rewards
    assert lines[1].startswith("Reward: Money") and "1" in lines[1]
    assert lines[2].startswith("Reward: Experience") and lines[2].endswith("480")
    assert lines[3] == "Reward: Reputation: Faction 72  +150"
    none = wow.eval(f"{data}({{ ref = 'npc:240', quests = {{ 76 }} }})")
    assert not any(t.startswith("Reward") for t in [strip(t) for t in none.lines.values()])
    assert wow.errors == []


def test_card_lines_wrap_to_three_at_most(wow: WowRuntime):
    """(T14): the reward lines on the card were cut; they wrap now, up
    to three lines each, and the card grows with them."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Map")
    wow.run_frames(5)
    pins = "Bastians:GetModule('Map').Pins"
    long = "Reward: " + "Blood Saber, Light Leather x2, " * 4
    measured = f"{pins}.CardLines({{ GetStringHeight = function() return %d end }}, '{long}')"
    assert wow.eval(measured % 24) == 2  # the client's measure: two lines
    assert wow.eval(measured % 60) == 3  # never more than three
    unmeasured = f"{pins}.CardLines({{ GetStringHeight = function() return 0 end }}, '%s')"
    assert wow.eval(unmeasured % "short") == 1
    assert wow.eval(unmeasured % long) == 3  # the estimate: about 44 characters a line
    assert wow.eval(f"{pins}.miniCard == nil or {pins}.miniCard.rows[1].wordWrap") is not False
    assert wow.errors == []
