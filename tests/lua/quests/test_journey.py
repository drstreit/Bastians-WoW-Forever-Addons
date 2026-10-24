"""Journey (quests.md "Journey", S3, 22.10.2026): per session and zone the XP, gold, kills and
turned-in quests, one entry per session and zone in the global saved variables in the shape
AHSync's journey.py reads; a zone change closes the entry; the Journey block on the zone page
and in the Here column; `/bq journey`; the setting off records nothing."""

import re

from harness import WowRuntime
from pages import block_rows, block_titles

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Quests')"
J = f"{MOD}.Journey"
HD = "Bastians:GetModule('Browser').hereDossier"
DS = "Bastians:GetModule('Browser').dossier"


def boot(wow: WowRuntime, *addons: str, journey: bool = True) -> WowRuntime:
    wow.execute("Mock.money = 10000; Mock.xp = 100; Mock.xpMax = 1000; Mock.level = 5")
    wow.start(*(addons or (CORE, DATA, QUESTS)))
    wow.run_frames(10)
    wow.advance(0.3)
    if not journey:
        wow.execute(f"{MOD}.db.profile.journey = false")
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def entries(wow: WowRuntime) -> list[dict]:
    """The entries in list order (a reloaded table iterates its hash part in no order)."""
    out = []
    lst = wow.eval(f"{MOD}.db.global.journey.entries")
    for i in range(1, len(lst) + 1):
        e = lst[i]
        d = {k: e[k] for k in ("c", "cls", "s", "m", "mn", "t0", "t1", "lv", "xp", "gold", "kills")}
        d["q"] = list(e["q"].values()) if e["q"] else None
        out.append(d)
    return out


def test_events_fill_one_entry_per_zone_and_session_in_ahsync_shape(wow: WowRuntime):
    boot(wow)
    # the login opens the entry of the zone without attributing the first readings to it
    assert len(entries(wow)) == 1
    wow.fire("ZONE_CHANGED_NEW_AREA")  # the first touch after the packs loaded names the zone
    e = entries(wow)[0]
    assert (e["c"], e["cls"], e["m"], e["mn"], e["lv"]) == (
        "Mockchar-Mock Realm",
        "MAGE",
        1429,
        "Elwynn Forest",
        5,
    )
    assert (e["xp"], e["gold"], e["kills"], e["q"]) == (0, 0, 0, None)
    assert e["s"] == e["t0"] and e["t1"] >= e["t0"]
    # XP: the difference to the last reading; across a level-up the rest of the old bar plus the new
    wow.execute("Mock.xp = 350")
    wow.fire("PLAYER_XP_UPDATE")
    wow.execute("Mock.xp = 40; Mock.xpMax = 2000; Mock.level = 6")
    wow.fire("PLAYER_LEVEL_UP", 6)
    wow.fire("PLAYER_XP_UPDATE")
    # money: every delta counts, signed
    wow.execute("Mock.money = 12500")
    wow.fire("PLAYER_MONEY")
    wow.execute("Mock.money = 12000")
    wow.fire("PLAYER_MONEY")
    # kills and quests
    wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Mangy Wolf dies, you gain 45 experience.")
    wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 40 experience.")
    wow.fire("QUEST_TURNED_IN", 62, 300, 150)
    e = entries(wow)[0]
    assert (e["xp"], e["gold"], e["kills"], e["q"]) == (250 + 650 + 40, 2000, 2, [62])
    assert e["lv"] == 5  # the level at the start of the entry
    # a zone change closes the entry and opens the next one; the first stays (it holds figures)
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    wow.advance(0.5)
    wow.execute("Mock.money = 12100")
    wow.fire("PLAYER_MONEY")
    es = entries(wow)
    assert (
        [x["m"] for x in es] == [1429, 1436] and es[1]["gold"] == 100 and es[1]["mn"] == "Westfall"
    )
    assert es[0]["s"] == es[1]["s"]
    # back to Elwynn with nothing happening: a short empty entry is dropped at the next change
    wow.execute("Mock.playerMap = 1429")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    assert [x["m"] for x in entries(wow)] == [1429, 1436, 1429]
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")
    assert [x["m"] for x in entries(wow)] == [1429, 1436, 1436]
    # the summary of this session per zone, zones in the order first entered
    rows = [(z.mn, z.xp, z.gold, z.kills, z.quests) for z in wow.eval(f"{J}.Summary()").values()]
    assert rows == [("Elwynn Forest", 940, 2000, 2, 1), ("Westfall", 0, 100, 0, 0)]
    assert wow.eval(f"{MOD}.db.global.journey.version") == 1
    assert wow.errors == []


def test_the_store_is_capped_and_survives_a_reload_and_a_login_attributes_nothing(
    wow: WowRuntime,
):
    boot(wow)
    wow.execute(
        f"local s = {J}.Store(); for i = 1, 520 do s.entries[#s.entries + 1] = "
        "{ c = 'Old-Realm', cls = 'MAGE', s = 1, m = 1429, mn = 'Elwynn Forest', t0 = i, t1 = i + 60, "
        "lv = 3, xp = 10, gold = 0, kills = 1 } end"
    )
    wow.execute("Mock.playerMap = 1436")
    wow.fire("ZONE_CHANGED_NEW_AREA")  # a new entry trims the list to the newest 500
    assert wow.eval(f"#{J}.Store().entries") == 500
    assert entries(wow)[-1]["m"] == 1436
    # every entry of the account counts for the zone, this session apart
    this, all_ = wow.eval(f"{J}.Zone(1429)")
    assert this is None or this.entries == 1
    assert (
        all_.entries >= 499 and all_.xp >= 4990 and all_.sessions == 1
    )  # the empty one counts nowhere
    # a reload keeps the entries; the login reading attributes neither XP nor money
    wow = wow.reload()
    wow.execute("Mock.money = 99999; Mock.xp = 900")
    boot(wow)
    es = entries(wow)
    assert len(es) == 500 and es[-1]["m"] == 1429 and es[-1]["xp"] == 0 and es[-1]["gold"] == 0
    assert wow.errors == []


def test_the_journey_block_on_the_zone_page_and_the_here_column_and_the_chat(wow: WowRuntime):
    # the mock's time() is the wall clock: a second passing in this test made the rate 3899/h
    # (seen 24.10.2026, about one run in ten); frozen here, the session lasts no time at all
    wow.execute("local t0 = os.time(); function time(t) return t and os.time(t) or t0 end")
    boot(wow, CORE, DATA, QUESTS, BROWSER)
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.slash("/bq journey")
    assert wow.chat[-1].endswith("Journey: nothing recorded yet this session")
    # nothing recorded: no block
    wow.slash("/bq here")
    wow.run_frames(5)
    assert "Journey" not in [t.split("  ")[0] for t in block_titles(wow, DS)]
    # a kill and some gold: the block names this session's figures
    wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Mangy Wolf dies, you gain 45 experience.")
    wow.execute("Mock.money = 10550")
    wow.fire("PLAYER_MONEY")
    wow.execute("Mock.xp = 400")
    wow.fire("PLAYER_XP_UPDATE")
    wow.advance(20)  # BASTIANS_JOURNEY_CHANGED is coalesced (15 s)
    wow.run_frames(5)
    rows = [strip(r) for r in block_rows(wow, DS, "Journey")]
    assert len(rows) == 1 and rows[0].startswith(
        "This session  0 min, 300 xp, +5s 50c, 1 kills, 0 quests"
    )
    here = [strip(r) for r in block_rows(wow, HD, "Journey")]
    assert here == rows
    wow.slash("/bq journey")
    assert "Elwynn Forest: 0 min, 300 xp, +5s 50c, 1 kills, 0 quests" in strip(wow.chat[-1])
    # an older session of another character on the same zone: a second row with every session
    wow.execute(
        f"local s = {J}.Store(); table.insert(s.entries, 1, {{ c = 'Other-Realm', cls = 'WARRIOR', s = 1, "
        "m = 1429, mn = 'Elwynn Forest', t0 = 1000, t1 = 4600, lv = 3, xp = 3600, gold = -100, kills = 30, "
        "q = { 7, 62 } })"
    )
    wow.execute("Mock.money = 10560")
    wow.fire("PLAYER_MONEY")
    wow.advance(20)
    wow.slash("/bq here")
    wow.run_frames(5)
    rows = [strip(r) for r in block_rows(wow, DS, "Journey")]
    assert len(rows) == 2 and rows[1].startswith("2 sessions  60 min, 3900 xp (3900/h)")
    assert "31 kills, 2 quests" in rows[1] and "+4s 60c" in rows[1]
    assert [strip(r) for r in block_rows(wow, HD, "Journey")] == rows
    assert wow.errors == []


def test_the_setting_off_records_nothing_and_on_again_starts_a_fresh_entry(wow: WowRuntime):
    boot(wow, journey=False)
    wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "x")
    wow.execute("Mock.money = 11000")
    wow.fire("PLAYER_MONEY")
    assert entries(wow) == [] or all(e["kills"] == 0 and e["gold"] == 0 for e in entries(wow))
    assert wow.eval(f"{J}.Current()") is None
    wow.execute(f"{MOD}.db.profile.journey = true")
    wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "x")
    assert wow.eval(f"{J}.Current().kills") == 1
    # the module disabled: the entry is closed, nothing more is written
    wow.execute(f"{MOD}:Disable()")
    assert wow.eval(f"{J}.Current()") is None
    assert wow.errors == []
