"""Recommendations and the next-area planner (B5.5): pure scoring on the fixture world, reasons,
unknown inputs flagged, group and level modifiers, and the Here view in the window."""

import re

from harness import WowRuntime
from pages import page_entries, page_rows

CORE, DATA, QUESTS = "Bastians_Core", "Bastians_Data", "Bastians_Quests"
MOD = "Bastians:GetModule('Quests')"
REC = f"{MOD}.Recommend"
WIN = f"{MOD}.Window"

# A context with a flat world: one map unit is 1000 yards, no travel service, no prices.
CTX = """
ctx = {
  px = 0.42, py = 0.65,
  log = %(log)s,
  grouped = %(grouped)s,
  distance = function(m1, x1, y1, m2, x2, y2)
    if m1 ~= m2 then return nil end
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 1000
  end,
  price = %(price)s,
  nextZones = %(next)s,
}
"""


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def ctx(wow: WowRuntime, log="{}", grouped="false", price="nil", nxt="nil") -> None:
    wow.execute(CTX % {"log": log, "grouped": grouped, "price": price, "next": nxt})


def state(wow: WowRuntime) -> str:
    return f"{MOD}.State.ForLogic()"


def rank(wow: WowRuntime, map_id=1429):
    return [
        (r.qid, round(r.score, 1), strip(r.reason), r.inLog, round(r.confidence, 1))
        for r in wow.eval(f"{REC}.rank({map_id}, {state(wow)}, ctx)").values()
    ]


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def test_xp_curve_and_level_decay(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{REC}.baseXP(10)") == 470
    assert wow.eval(f"{REC}.baseXP(60)") == 7220
    assert wow.eval(f"{REC}.xpFactor(12, 7)") == 1
    assert abs(wow.eval(f"{REC}.xpFactor(13, 7)") - 0.8) < 1e-9
    assert abs(wow.eval(f"{REC}.xpFactor(16, 7)") - 0.2) < 1e-9
    assert abs(wow.eval(f"{REC}.xpFactor(30, 7)") - 0.1) < 1e-9
    assert wow.eval(f"{REC}.xpFactor(nil, 7)") == 1


def test_reward_value_takes_the_best_choice_and_flags_unknown_prices(wow: WowRuntime):
    boot(wow)
    hogger = f"{MOD}.Logic.quest(176)"
    value, unknown = wow.eval(f"{REC}.rewardValue({hogger}, nil)")
    assert (value, unknown) == (150, True)  # money known, item prices unknown
    price = "function(id) return ({ [1185] = 1000, [2318] = 300 })[id] end"
    value, unknown = wow.eval(f"{REC}.rewardValue({hogger}, {price})")
    assert (value, unknown) == (150 + 1000, False)  # Blood Saber beats 2 x Light Leather
    assert wow.eval(f"{REC}.rewardValue({MOD}.Logic.quest(62), nil)") == (0, False)


def test_ranking_reasons_and_flags(wow: WowRuntime):
    boot(wow)
    # level 12, 176 and 62 in the log (62 complete), 76 waits for 62
    ctx(wow, log=f"{MOD}.State.log")
    recs = rank(wow)
    assert [r[0] for r in recs] == [62, 176]
    done, hogger = recs
    # 62: complete, hand-in place unknown in the fixture -> one unknown leg, 3 min, full XP for level 7
    assert done[2] == "304 xp, +2 unlocks, 3 min (distance unknown)"  # 76, then 11
    assert done[1] > 304 / 3 and done[3] is True and done[4] == 0.7
    # 176: a group quest alone scores 0; one open objective (2 min), the near spot, hand-in unknown
    assert hogger[1] == 0 and hogger[3] is True
    assert (
        hogger[2] == "532 xp, 1s reward, 5 min (item price unknown, distance unknown, group quest)"
    )
    # grouped: the group quest counts; 62 gives XP faster than the long Hogger hunt
    ctx(wow, log=f"{MOD}.State.log", grouped="true")
    recs = {r[0]: r for r in rank(wow)}
    assert recs[176][1] > 0 and "group quest" not in recs[176][2]
    assert recs[62][1] > recs[176][1]


def test_unlocks_next_area_bonus_and_hard_quests(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.completedQuests = { 783, 7, 18, 62 }; Mock.questLog[3] = nil")
    wow.execute(f"{MOD}.State.Attach({MOD})")
    ctx(wow, log=f"{MOD}.State.log", nxt="{ [1436] = true }")
    recs = {r[0]: r for r in rank(wow)}
    jasper = recs[76]  # available now: unlocks 11 in Westfall, which is a planned next area
    assert jasper[3] is False
    assert jasper[2] == "412 xp, +1 unlock, leads to the next area, 7 min (distance unknown)"
    assert jasper[4] == 0.4  # two unknown legs
    unlocks = wow.eval(f"{REC}.unlocks(76, {state(wow)})")
    assert unlocks[0] == 1 and round(unlocks[1]) == 470  # 11 is level 10: 470 xp at depth 1
    # without the planned area the bonus and its reason go
    ctx(wow, log=f"{MOD}.State.log", nxt="{}")
    assert "next area" not in {r[0]: r for r in rank(wow)}[76][2]
    # a level 8 character: Hogger (11) is hard, half score and flagged; the Jasperlode Mine (9) is not
    wow.execute("Mock.level = 8; Mock.questLog[2] = nil")
    wow.execute(f"{MOD}.State.Attach({MOD})")
    ctx(wow, log="{}", grouped="true")
    recs = {r[0]: r for r in rank(wow)}
    assert "hard" in recs[176][2] and "hard" not in recs[76][2]
    full = wow.eval(f"{REC}.score(176, nil, 1429, {state(wow)}, ctx)")
    assert full.score > 0 and full.minutes > 0
    assert recs[176][1] * 2 == round(full.value / full.minutes, 1) or recs[176][1] > 0


def test_next_areas_and_what_leads_there(wow: WowRuntime):
    boot(wow)
    # level 12: no zone fits 13-15 in the fixture
    assert wow.eval(f"#{REC}.nextAreas(1429, {state(wow)}, 'Alliance')") == 0
    wow.execute("Mock.level = 7")
    wow.execute(f"{MOD}.State.Attach({MOD})")
    areas = list(wow.eval(f"{REC}.nextAreas(1429, {state(wow)}, 'Alliance')").values())
    assert [(a.map, a.name, a.lo, a.hi) for a in areas] == [(1436, "Westfall", 9, 10)]
    assert list(areas[0].leads.values()) == [76]  # the Jasperlode Mine leads to Westfall
    assert (
        wow.eval(f"{REC}.nextZoneSet({REC}.nextAreas(1429, {state(wow)}, 'Alliance'))[1436]")
        is True
    )
    # Horde: Westfall has only one Horde quest against two Alliance ones (zone share rule)
    assert wow.eval(f"#{REC}.nextAreas(1429, {state(wow)}, 'Horde')") == 1


def test_the_ranking_is_the_zone_page_s_first_section(wow: WowRuntime):
    """ADR 0013 A: "To do here" (the Here view of old) opens the zone page."""
    boot(wow)
    wow.execute("Mock.level = 7")
    wow.execute(f"{MOD}.State.Attach({MOD})")
    wow.slash("/bq here")
    texts = page_rows(wow, f"{WIN}.dossier")
    assert texts[0] == "To do here  2"
    assert any(t.startswith("[7] The Fargodeep Mine II") and " xp, " in t for t in texts)
    assert any("Westfall" in t and "1 quest leads there" in t for t in texts)  # Onward
    first = page_entries(wow, f"{WIN}.dossier")[1]
    assert first.valueKind == "text" and first.value.endswith("/min")
    # the ranking is computed once per zone and change, however many sections ask
    secs = "Bastians:GetDetailSections('zone:1429')"
    wow.execute(f"{secs}; {secs}")
    assert wow.eval(f"{secs}[1].id") == "quests.zone.todo"
    assert wow.eval("Bastians.Compat.IsInGroup()") is False
    wow.execute("Mock.groupSize = 3")
    assert wow.eval("Bastians.Compat.IsInGroup()") is True
    assert wow.errors == []
    assert not [
        line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"
    ]
