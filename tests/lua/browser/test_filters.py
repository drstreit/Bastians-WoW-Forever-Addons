"""The filter bar of the lists (ADR 0016, the styling round ST2): choices remembered per list type
with a fallback when they keep nothing, the sorts apps register (Gold's loot per kill computed as
a job, Quests' most XP), a facet an app registers as a pill of its own (several keys per row), the
registry's rules, and the kind words of Data."""

import re

from harness import WowRuntime
from pages import clear, menu, pick, pills

CORE, DATA, QUESTS, GOLD, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Gold",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
TREE = f"{MOD}.tree"
SIZE = f"{TREE}.scroll:SetSize(440, 400); {TREE}:Refresh()"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.execute('function GetRealmName() return "Classic Beta PvE" end')
    wow.start(*(addons or (CORE, DATA, QUESTS, GOLD, BROWSER)))
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def flat(wow: WowRuntime) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{TREE}.flat").values()]


def open_list(wow: WowRuntime, typ: str) -> None:
    wow.execute(f"{BR}.List('{typ}')")
    wow.run_frames(10)
    wow.execute(SIZE)


def test_choices_are_remembered_per_list_and_fall_back_when_empty(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    pick(wow, TREE, "service", "Quest giver")
    pick(wow, TREE, "where", "Continent")
    open_list(wow, "item")
    assert pills(wow, TREE)[0] == "Class: All"  # another list keeps its own choices
    open_list(wow, "npc")  # a new history entry: the remembered choices
    assert pills(wow, TREE)[:2] == ["Where: Continent", "Service: Quest giver"]
    assert flat(wow) == ["Gryan Stoutmantle  20", "Marshal Dughan  10"]
    saved = wow.eval(f"{MOD}.db.profile.listFilters.npc")
    assert saved.near == "continent" and saved.picks.service == "Quest giver"
    # a remembered choice that keeps nothing here (no banker in the fixture world): All, and
    # the list is not empty; the memory itself stays
    wow.execute(f"{MOD}.db.profile.listFilters.npc.picks.service = 'Banker'")
    open_list(wow, "npc")
    assert pills(wow, TREE)[1] == "Service: All" and len(flat(wow)) == 6
    assert wow.eval(f"{MOD}.db.profile.listFilters.npc.picks.service") == "Banker"
    # the x clears a choice and the memory follows
    pick(wow, TREE, "rank", "Elite")
    assert flat(wow) == ["Hogger  11"]
    clear(wow, TREE, "rank")
    assert wow.eval(f"{MOD}.db.profile.listFilters.npc.picks.rank") is None
    assert wow.errors == []


def test_gold_sorts_npcs_by_loot_per_kill_as_a_job(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    assert "Loot per kill" in menu(wow, TREE, "sort")
    pick(wow, TREE, "sort", "Loot per kill")
    assert "Sorting ..." in strip(wow.eval(f"{MOD}.summary:GetText()"))  # a job, not a freeze
    wow.run_frames(10)
    rows = flat(wow)
    assert rows[0].startswith("Hogger  11") and "per kill" in rows[0]  # the only NPC with loot
    assert not any("per kill" in r for r in rows[1:])  # no loot: no value, after the rest
    assert pills(wow, TREE)[-1] == "Sort: Loot per kill"
    gen = wow.eval("Bastians:FilterGeneration('gold.lootPerKill')")
    wow.execute("Bastians:Fire('BASTIANS_PRICES_UPDATED')")
    assert wow.eval("Bastians:FilterGeneration('gold.lootPerKill')") == gen + 1
    # without Gold the sort is gone and a remembered one falls back to the name order
    wow.execute("Bastians:GetModule('Gold'):Disable()")
    open_list(wow, "npc")
    assert "Loot per kill" not in menu(wow, TREE, "sort")
    assert pills(wow, TREE)[-1] == "Sort: Name"
    assert wow.errors == []


def test_quests_sort_by_xp_and_reputation(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local Logic = Bastians:GetModule('Quests').Logic
        -- Data keeps decoded records weakly: hold them, or a collection brings back the pack's
        keptQuests = { Logic.quest(62), Logic.quest(176) }
        keptQuests[1].rewards = { xp = 450, rep = { { 72, 250 }, { 54, 75 } } }
        keptQuests[2].rewards = { xp = 900, money = 150 }
        """
    )
    xp = "Bastians:GetFilter('quests.xp')"
    rep = "Bastians:GetFilter('quests.rep')"
    assert wow.eval(f"{xp}.value('quest:176')") == 900
    assert wow.eval(f"{rep}.value('quest:62')") == 250  # the largest gain
    assert wow.eval(f"{rep}.value('quest:176')") is None  # no reputation: no value, never 0
    open_list(wow, "quest")
    clear(wow, TREE, "where")
    pick(wow, TREE, "sort", "Most XP")
    wow.run_frames(10)
    rows = flat(wow)
    assert rows[0].startswith('Wanted: "Hogger"') and rows[0].endswith("900 XP")
    assert rows[1].startswith("The Fargodeep Mine") and rows[1].endswith("450 XP")
    assert wow.errors == []


def test_an_app_facet_is_a_pill_and_a_row_may_count_for_two_keys(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """
        local mod = Bastians:NewModule("FacetApp", { addon = "Bastians_TestApp" })
        Bastians:RegisterFilter(mod, {
          id = "test.side", kind = "facet", types = { "npc" }, label = "Side",
          value = function(ref, r)
            if ref == "npc:240" then return { "Guard", "Friend" } end
            return r and r.flags == "elite" and "Foe" or "Friend"
          end,
        })
        """
    )
    open_list(wow, "npc")
    assert "Side: All" in pills(wow, TREE)
    assert menu(wow, TREE, "test.side") == ["All  6", "Friend  5", "Foe  1", "Guard  1"]
    pick(wow, TREE, "test.side", "Guard")
    assert flat(wow) == ["Marshal Dughan  10"]
    assert wow.errors == []


def test_register_filter_checks_its_definition(wow: WowRuntime):
    boot(wow, CORE, "Bastians_TestApp")  # the module's addon is loaded, so it is enabled
    wow.execute(
        """
        mod = Bastians:NewModule("Filters", { addon = "Bastians_TestApp" })
        ok, err = pcall(Bastians.RegisterFilter, Bastians, mod,
          { id = "x", types = "*", label = "X", value = function() end })
        Bastians:RegisterFilter(mod, { id = "b", kind = "sort", types = { "npc" }, label = "B",
          value = function() error("broken") end })
        Bastians:RegisterFilter(mod, { id = "a", kind = "sort", types = "*", label = "A",
          value = function() return 1 end })
        """
    )
    assert wow.eval("ok") is False and "kind" in wow.eval("err")
    assert [d.id for d in wow.eval("Bastians:GetFilters('npc', 'sort')").values()] == ["a", "b"]
    assert [d.id for d in wow.eval("Bastians:GetFilters('item')").values()] == ["a"]
    # a provider that fails gives nil, the error is logged, the list goes on
    assert wow.eval("Bastians:FilterValue(Bastians:GetFilter('b'), 'npc:1', {})") is None
    wow.execute("mod:Disable()")
    assert wow.eval("Bastians:GetFilter('a')") is None


def test_data_names_the_kinds(wow: WowRuntime):
    boot(wow)  # an app that names the World pack, so Data loads it
    d = "Bastians:GetService('data')"
    assert list(wow.eval(f"{{ {d}:Kind('object', 'mailbox') }}").values()) == ["Mailbox", "Mailbox"]
    assert list(wow.eval(f"{{ {d}:Kind('object', 'door') }}").values()) == ["Door", "Other"]
    assert list(wow.eval(f"{{ {d}:Kind('object', 'fire and forge') }}").values()) == [
        "Fire and forge",
        "Fire and forge",
    ]
    assert list(wow.eval(f"{{ {d}:Kind('npc', 'flightmaster') }}").values()) == [
        "Flight master",
        "Flight master",
    ]
    assert list(wow.eval(f"{{ {d}:Kind('object', nil) }}").values()) == []  # unknown stays unknown
    # the object's summary says what it is
    assert wow.eval("Bastians:Entity('object:1734'):Summary()") == "Quest object, Elwynn Forest"
    assert wow.errors == []


def test_a_dimension_whose_rows_share_one_key_shows_no_pill(wow: WowRuntime):
    """Retail objects have no kinds and retail quests no levels (measured on the retail packs,
    23.10.2026: "Kind: All" offered only "Other"). The fixture's one object is a quest object."""
    boot(wow)
    open_list(wow, "object")
    assert pills(wow, TREE) == ["Where: Here", "Sort: Name"]
    # a remembered choice keeps its pill, so it can be cleared
    wow.execute(f"{MOD}.db.profile.listFilters.object = {{ picks = {{ kind = 'Quest object' }} }}")
    open_list(wow, "object")
    assert "Kind: Quest object" in pills(wow, TREE)
    assert wow.errors == []
