"""Item sets for the bag addons (ADR 0043 decision 7, core-contracts §7f): an app's item lists
reach BetterBags as categories, Baganator as a junk plugin or a corner mark, AdiBags as filters,
each through a stand-in of the addon (their code is not ours to copy); nothing is asked while no
bag addon is loaded; a switched-off app's set empties."""

from harness import WowRuntime

# Stand-ins with the calls ADR 0043 read in their sources (31.10.2026).
STANDINS = """
BB = { categories = {}, created = {} }
local Categories = {
  CreateCategory = function(_, ctx, c) BB.created[#BB.created + 1] = c.name ; BB.categories[c.name] = {} end,
  WipeCategory = function(_, ctx, name) BB.categories[name] = {} end,
  AddItemToCategory = function(_, ctx, id, name) BB.categories[name][id] = true end,
}
local Context = { New = function(_, name) return { name = name } end }
local BetterBags = { GetModule = function(_, name) return ({ Categories = Categories, Context = Context })[name] end }
AdiState = { filters = {}, changed = 0 }
local AdiBags = {
  RegisterFilter = function(_, name, priority)
    local f = { name = name, priority = priority }
    function f:SendMessage(msg) if msg == "AdiBags_FiltersChanged" then AdiState.changed = AdiState.changed + 1 end end
    AdiState.filters[name] = f
    return f
  end,
}
local ace = LibStub:NewLibrary("AceAddon-3.0", 1)
function ace:GetAddon(name) return ({ BetterBags = BetterBags, AdiBags = AdiBags })[name] end
BagState = { junk = {}, corners = {}, refreshed = 0 }
Baganator = { API = {
  RegisterJunkPlugin = function(label, id, cb) BagState.junk[id] = cb end,
  RegisterCornerWidget = function(label, id, onUpdate, onInit) BagState.corners[id] = onUpdate end,
  RequestItemButtonsRefresh = function() BagState.refreshed = BagState.refreshed + 1 end,
} }
C_Item = C_Item or {}
C_Item.GetItemInfoInstant = function(id) return id end
"""

APP = """
Asked, Sold = 0, { [2589] = true, [2592] = true }
SetApp = Bastians:NewModule("Setapp", {
  addon = "Bastians_Core",
  OnEnable = function(self)
    Bastians:RegisterItemSet(self, {
      id = "test.vendor", label = "Bastian's: vendor", kind = "junk",
      items = function() Asked = Asked + 1 ; return Sold end,
      on = { "BASTIANS_PRICES_UPDATED" },
    })
    Bastians:RegisterItemSet(self, {
      id = "test.ah", label = "Bastian's: sell on AH", kind = "category",
      items = function() return { [4306] = true } end,
    })
  end,
})
"""


def start(wow: WowRuntime, standins: bool = True) -> None:
    wow.load_addon("Bastians_Core")
    if standins:
        wow.execute(STANDINS)
    wow.login()
    wow.execute(APP)
    wow.advance(1.5)


def test_item_sets_reach_every_bag_addon(wow: WowRuntime):
    start(wow)
    # BetterBags: a category per set with its items
    assert sorted(wow.eval("BB.created").values()) == ["Bastian's: sell on AH", "Bastian's: vendor"]
    assert dict(wow.eval('BB.categories["Bastian\'s: vendor"]').items()) == {2589: True, 2592: True}
    assert dict(wow.eval('BB.categories["Bastian\'s: sell on AH"]').items()) == {4306: True}
    # Baganator: the junk set is a junk plugin, the category a corner mark
    assert wow.eval("BagState.junk['bastians_test.vendor'](0, 1, 2589)") is True
    assert wow.eval("BagState.junk['bastians_test.vendor'](0, 1, 117)") is False
    assert wow.eval("BagState.corners['bastians_test.ah'](nil, { itemID = 4306 })") is True
    assert wow.eval("BagState.corners['bastians_test.ah'](nil, {})") is None  # not known yet
    assert wow.eval("BagState.refreshed") >= 1
    # AdiBags: a filter per set that names the item's section
    f = "AdiState.filters['Bastians_test.vendor']"
    assert wow.eval(f"{f}:Filter({{ itemId = 2592 }})") == "Bastian's: vendor"
    assert wow.eval(f"{f}:Filter({{ itemId = 117 }})") is None
    # a message asks again, coalesced, and the bags follow
    asked = wow.eval("Asked")
    wow.execute("Sold = { [117] = true }")
    for _ in range(3):
        wow.execute("Bastians:Fire('BASTIANS_PRICES_UPDATED', 'scan')")
    wow.advance(1.5)
    assert wow.eval("Asked") == asked + 1
    assert dict(wow.eval('BB.categories["Bastian\'s: vendor"]').items()) == {117: True}
    assert wow.eval("BagState.junk['bastians_test.vendor'](0, 1, 117)") is True
    # a switched-off app's sets empty
    wow.execute("SetApp:Disable()")
    assert dict(wow.eval('BB.categories["Bastian\'s: vendor"]').items()) == {}
    assert wow.errors == []


def test_nothing_is_asked_without_a_bag_addon(wow: WowRuntime):
    start(wow, standins=False)
    wow.execute("Bastians:Fire('BASTIANS_PRICES_UPDATED', 'scan')")
    wow.advance(1.5)
    assert wow.eval("Asked") == 0
    assert wow.errors == []


def test_the_apps_offer_their_sets(wow: WowRuntime):
    wow.load_addon("Bastians_Core")
    wow.execute(STANDINS)
    for name in ("Bastians_Data", "Bastians_Quests", "Bastians_Gold"):
        wow.load_addon(name)
    wow.login()
    wow.advance(1.5)
    names = set(wow.eval("BB.created").values())
    assert "Bastian's: quest items" in names
    if wow.made_for("Bastians_Gold"):  # no Gold on retail (ADR 0022)
        assert {"Bastian's: sell on AH", "Bastian's: vendor"} <= names
    assert wow.errors == []
