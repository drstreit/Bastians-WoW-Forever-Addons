"""UI kit (B2.6): Money, Icons, Window, Tree (virtual rows, folds, search, chips), EntityMenu."""

import time

from harness import WowRuntime
from pages import clear, menu, pick, pills

TREE = """
host = CreateFrame("Frame", nil, UIParent)
host:SetSize(400, 200)
treeDB = {}
tree = Bastians.UI.Tree(host, { db = treeDB })
tree.scroll:SetSize(386, 200)
"""


def test_money_formats_and_keeps_unknown_unknown(core: WowRuntime):
    assert core.eval("Bastians.UI.Money(123456)") == "12|cffffd700g|r 34|cffc7c7cfs|r"
    assert core.eval("Bastians.UI.Money(3456)") == "34|cffc7c7cfs|r 56|cffeda55fc|r"
    assert core.eval("Bastians.UI.Money(56)") == "56|cffeda55fc|r"
    assert core.eval("Bastians.UI.Money(0)") == "0|cffeda55fc|r"
    assert core.eval("Bastians.UI.Money(-150)") == "-1|cffc7c7cfs|r 50|cffeda55fc|r"
    assert core.eval("Bastians.UI.Money(nil)") is None
    assert core.eval("Bastians.UI.MoneyShort(123456)") == "12.3|cffffd700g|r"
    assert core.eval("Bastians.UI.FormatValue(42, 'percent')") == "42 %"
    assert core.eval("Bastians.UI.FormatValue(nil, 'money')") is None


def test_icon_paths_keep_their_backslashes(core: WowRuntime):
    inline = core.eval("Bastians.UI.Icon('herb')")
    glyphs = "Interface\\AddOns\\Bastians_Core\\Media\\Glyphs\\"  # one backslash each in Lua
    # the glyph is white; the inline escape carries the kind's tint as 0..255 rgb
    assert inline.startswith("|T" + glyphs + "herb:12:12:0:0:64:64:0:64:0:64:")
    assert inline.endswith("|t ")
    assert core.eval("Bastians.UI.IconTexture('quest')") == glyphs + "quest"
    assert core.eval("Bastians.UI.Icon('nope')") == ""
    assert core.eval("Bastians.UI.InlineTexture(135812, 16)") == "|T135812:16:16|t "
    paths = core.eval("Bastians.UI.ICON_PATHS")
    assert all("\\" in p for p in paths.values())


def test_highlight_keeps_escape_sequences(core: WowRuntime):
    hl = "Bastians.UI.TreeUtil.highlight(%r, %r)"
    acc = core.eval("Bastians.UI.Style.accent()")
    assert core.eval(hl % ("Hogger", "hog")) == f"{acc}Hog|rger"
    assert core.eval(hl % ("|cffff0000Hogger|r", "gge")) == f"|cffff0000Ho{acc}gge|r|cffff0000r|r"
    text = "|TInterface\\Icons\\X:12:12|t Hogger"
    assert core.eval(hl % (text, "x")) == text.replace(
        "Hogger", "Hogger"
    )  # 'x' only inside the texture
    assert core.eval(hl % ("Hogger", "")) == "Hogger"


def test_window_persists_place_and_closes_on_escape(core: WowRuntime):
    core.execute(
        """
        winDB = {}
        win = Bastians.UI.Window("BastiansTestWindow", { title = "Test", width = 300, height = 200, db = winDB })
        """
    )
    assert core.eval("win:IsShown()") is False
    core.execute("win:Show()")
    assert (
        core.eval("win:IsShown()") is True
        and core.eval("win.frame:GetFrameStrata()") == "FULLSCREEN_DIALOG"
    )
    assert core.eval("win.title:GetText()") == "Test"
    core.execute("win.head:GetScript('OnDragStop')(win.head)")
    assert core.eval("winDB.size[1]") == 300 and core.eval("winDB.pos ~= nil") is True
    core.execute("Mock.PressEscape()")
    assert core.eval("win:IsShown()") is False
    core.execute("win.close:Click()")
    assert core.eval("win:IsShown()") is False
    assert core.eval("tContains(UISpecialFrames, 'BastiansTestWindow')") is True
    core.execute("winDB.pos = { 50, -60 }; win2 = Bastians.UI.Window('W2', { db = winDB })")
    assert core.eval("select(4, win2.frame:GetPoint(1))") == (50, -60)


def test_window_full_screen_and_sizing_flag(core: WowRuntime):
    """Full screen covers UIParent and comes back to the saved place (Map toolbar, owner wish
    21.10.2026); onResize learns whether the grip is still held."""
    core.execute(
        """
        resizes = {}
        fsDB = { pos = { 50, -60 }, size = { 300, 200 } }
        fs = Bastians.UI.Window("BastiansFullTest", { db = fsDB, width = 300, height = 200,
          onResize = function(w, sizing) resizes[#resizes + 1] = sizing end })
        fs:Show()
        """
    )
    assert core.eval("fs:IsFullScreen()") is False and core.eval("fs:IsSizing()") is False
    core.execute("fs:ToggleFullScreen()")
    assert core.eval("fs:IsFullScreen()") is True and core.eval("fsDB.full") is True
    assert core.eval("fs.frame:GetWidth()") == 1920 and core.eval("fs.frame:GetHeight()") == 1080
    assert core.eval("select(4, fs.frame:GetPoint(1))") == (0, 0)
    assert core.eval("fs.grip:IsShown()") is False
    core.execute("fs.head:GetScript('OnDragStop')(fs.head)")  # a drag in full screen saves nothing
    assert core.eval("fsDB.size[1]") == 300 and core.eval("fsDB.pos[1]") == 50
    core.execute("fs:ToggleFullScreen()")
    assert core.eval("fs:IsFullScreen()") is False and core.eval("fsDB.full") is None
    assert core.eval("fs.frame:GetWidth()") == 300 and core.eval("fs.grip:IsShown()") is True
    assert core.eval("select(4, fs.frame:GetPoint(1))") == (50, -60)
    # the grip: the client fires a size change per frame while the mouse is down; the content
    # hears one coalesced call (sizing = true) per 0.1 s, then false at the end (owner, retail
    # 22.10.2026: a refresh per frame made the resize crawl)
    core.execute("resizes = {}; fs.grip:GetScript('OnMouseDown')(fs.grip)")
    assert core.eval("fs:IsSizing()") is True
    for w in (310, 315, 320):
        core.execute(f"fs.frame:SetSize({w}, 220); fs.frame:GetScript('OnSizeChanged')(fs.frame)")
    assert list(core.eval("resizes").values()) == []  # nothing yet: the timer is pending
    core.advance(0.15)
    assert list(core.eval("resizes").values()) == [True]  # three changes, one refresh
    core.execute("fs.grip:GetScript('OnMouseUp')(fs.grip)")
    assert core.eval("fs:IsSizing()") is False
    flags = list(core.eval("resizes").values())
    assert flags == [True, False] and core.eval("fsDB.size[1]") == 320
    core.advance(0.2)  # a pending timer after the release calls nothing more
    assert list(core.eval("resizes").values()) == [True, False]
    # a window remembered as full screen opens full screen
    core.execute("fs3 = Bastians.UI.Window('BastiansFullTest3', { db = { full = true } })")
    assert core.eval("fs3:IsFullScreen()") is True and core.eval("fs3.frame:GetWidth()") == 1920
    assert core.errors == []


def test_windows_dock_side_by_side_and_remember_it(core: WowRuntime):
    """ADR 0013 E: Window:DockWith keeps two windows side by side at one height; the follower
    goes with the leader's moves and height, a drag or full screen undocks, the profile remembers."""
    core.execute(
        """
        leadDB, followDB = { pos = { 100, -100 }, size = { 600, 400 } }, { pos = { 900, -50 }, size = { 400, 500 } }
        lead = Bastians.UI.Window("BastiansDockLead", { db = leadDB, width = 600, height = 400 })
        follow = Bastians.UI.Window("BastiansDockFollow", { db = followDB, width = 400, height = 500,
          onResize = function() resized = (resized or 0) + 1 end })
        lead:Show(); follow:Show()
        """
    )
    assert core.eval("Bastians.UI.Windows.BastiansDockLead == lead") is True
    assert core.eval("follow:DockWith(lead, 'right')") is True
    assert core.eval("follow:IsDocked()") is True and core.eval("lead:IsDocked()") is False
    point = core.eval("{ follow.frame:GetPoint(1) }")
    assert (point[1], point[3], point[4]) == ("TOPLEFT", "TOPRIGHT", 2)
    assert core.eval("follow.frame:GetHeight()") == 400  # the leader's height
    assert core.eval("followDB.dock.with") == "BastiansDockLead"
    assert core.eval("followDB.dock.side") == "right"
    assert core.eval("resized") == 1
    # the leader's size change reaches the follower; the follower's place in the db stays
    core.execute("lead.frame:SetSize(600, 450); lead.frame:GetScript('OnSizeChanged')(lead.frame)")
    assert core.eval("follow.frame:GetHeight()") == 450
    core.execute("follow.head:GetScript('OnDragStop')(follow.head)")
    assert core.eval("followDB.pos[1]") == 900 and core.eval("followDB.size[2]") == 500
    # undock: the windowed place and size come back
    core.execute("follow:Undock()")
    assert core.eval("follow:IsDocked()") is False and core.eval("followDB.dock") is None
    assert core.eval("select(4, follow.frame:GetPoint(1))") == (900, -50)
    assert core.eval("follow.frame:GetHeight()") == 500
    # a drag of a docked window undocks it; full screen on the leader undocks the follower
    core.execute("follow:DockWith(lead, 'left')")
    assert core.eval("({ follow.frame:GetPoint(1) })[3]") == "TOPLEFT"
    core.execute("follow.head:GetScript('OnDragStart')(follow.head)")
    assert core.eval("follow:IsDocked()") is False
    core.execute("follow:DockWith(lead, 'right'); lead:ToggleFullScreen()")
    assert core.eval("follow:IsDocked()") is False and core.eval("lead:IsFullScreen()") is True
    core.execute("lead:ToggleFullScreen()")
    # a dock remembered in the profile comes back once both windows exist, whichever builds first
    core.execute(
        """
        lateDB = { dock = { with = "BastiansDockLead", side = "right" } }
        late = Bastians.UI.Window("BastiansDockLate", { db = lateDB })
        """
    )
    assert core.eval("late:IsDocked()") is True
    core.execute(
        """
        earlyDB = { dock = { with = "BastiansDockLeader2", side = "right" } }
        early = Bastians.UI.Window("BastiansDockEarly", { db = earlyDB })
        leader2 = Bastians.UI.Window("BastiansDockLeader2", { db = {} })
        """
    )
    assert core.eval("early:IsDocked()") is True
    assert core.eval("early.dock.with == leader2") is True
    assert core.eval("late:IsDocked()") is True
    assert core.errors == []


def test_tree_renders_only_visible_rows_and_fast(core: WowRuntime):
    core.execute(TREE)
    core.execute(
        """
        rows = {}
        for i = 1, 200 do
          rows[i] = { text = "Row " .. i, value = i * 100, valueKind = "money", ref = "npc:" .. i }
        end
        """
    )
    start = time.perf_counter()
    core.execute("tree:SetRows(rows)")
    elapsed = (time.perf_counter() - start) * 1000
    assert elapsed < 16, f"200 rows took {elapsed:.1f} ms"
    assert core.eval("#tree.flat") == 200
    visible = core.eval("tree.visibleCount")
    assert 11 <= visible <= 14  # 200 px / 18 px per row plus overscan
    assert core.eval("#tree.pool") == visible
    assert core.eval("tree.pool[1].row.text") == "Row 1"
    assert core.eval("tree.pool[1].value:GetText()") == "1|cffc7c7cfs|r 00|cffeda55fc|r"
    core.execute("tree:ScrollTo(18 * 100)")
    assert core.eval("tree.pool[1].row.text") == "Row 99"  # overscan of 2 rows above row 101
    pool = core.eval("#tree.pool")
    assert visible <= pool <= visible + 2  # the pool grows to the largest window once
    core.execute("tree:ScrollTo(0); tree:ScrollTo(18 * 150); tree:ScrollTo(0)")
    assert core.eval("#tree.pool") == pool  # frames re-used, none created
    assert core.eval("tree.pool[1].row.text") == "Row 1"
    assert core.errors == []


def test_tree_draws_a_rule_row_as_a_thin_line(core: WowRuntime):
    """A "rule" row (the Browser's divider between prefix matches and the rest, 21.10.2026)."""
    core.execute(TREE)
    core.execute(
        """
        tree:SetRows({ { text = "Hogger", ref = "npc:448" }, { kind = "rule", text = "" },
          { text = "Big Hog", ref = "npc:449" } })
        """
    )
    assert core.eval("#tree.flat") == 3 and core.eval("tree.visibleCount") == 3
    assert core.eval("tree.pool[2].rule:IsShown()") is True
    assert core.eval("tree.pool[1].rule:IsShown()") is False
    assert core.eval("tree.pool[3].rule:IsShown()") is False
    assert core.eval("tree.heights[2]") == 9 and core.eval("tree.heights[3]") == 18
    assert core.errors == []


def test_tree_folds_searches_and_selects(core: WowRuntime):
    core.execute(TREE)
    core.execute(
        """
        rows = {
          { id = "a", text = "Alpha", kind = "section", children = {
            { text = "Hogger", ref = "npc:448" },
            { text = "Goldtooth", ref = "npc:327" } } },
          { id = "b", text = "Beta", collapsed = true, children = { { text = "Hidden Hog" } } },
          { text = "Gamma" },
        }
        tree:SetRows(rows)
        """
    )
    assert [r.text for r in core.eval("tree.flat").values()] == [
        "Alpha",
        "Hogger",
        "Goldtooth",
        "Beta",
        "Gamma",
    ]
    assert core.eval("tree.pool[1].fold.label:GetText()") == "-"
    core.execute("tree:ToggleFold(rows[1])")
    assert [r.text for r in core.eval("tree.flat").values()] == ["Alpha", "Beta", "Gamma"]
    assert core.eval("treeDB.collapsed.a") is True  # persisted fold state
    core.execute("tree:ToggleFold(rows[2])")
    assert "Hidden Hog" in [r.text for r in core.eval("tree.flat").values()]
    core.execute("tree:SetQuery(' HOG ')")
    texts = [r.text for r in core.eval("tree.flat").values()]
    assert texts == [
        "Alpha",
        "Hogger",
        "Beta",
        "Hidden Hog",
    ]  # folds ignored, the way to a match kept
    assert "|cff" in core.eval("tree.pool[2].text:GetText()")  # highlighted
    core.execute("tree:SetQuery('')")
    core.execute("tree.pool[1]:Click('LeftButton')")  # Alpha: no ref, has children -> fold toggles
    assert core.eval("tree:GetSelected().text") == "Alpha"
    assert core.eval("tree.pool[1].sel:IsShown()") is True


def test_tree_rows_run_the_primary_action_and_open_the_menu(core: WowRuntime):
    core.execute(TREE)
    core.execute(
        """
        local m = Bastians:NewModule("Acts", { addon = "Bastians_Core" })
        ran = {}
        Bastians:RegisterAction(m, { id = "map.show", label = "Show on map", types = { "npc" }, order = 10,
          run = function(ref, ctx) ran[#ran + 1] = ref .. "/" .. ctx.source end })
        Bastians:RegisterAction(m, { id = "browser.open", label = "Open", types = "*", order = 20, run = function() end })
        tree:SetRows({ { text = "Hogger", ref = "npc:448" }, { text = "Plain" } })
        tree.pool[1]:Click("LeftButton")
        """
    )
    assert list(core.g.ran.values()) == ["npc:448/tree"]
    core.execute("tree.pool[1]:Click('RightButton')")
    assert core.eval("Bastians.UI.EntityMenuFrame():IsShown()") is True
    labels = [
        b.label.GetText(b.label)
        for b in core.eval("Bastians.UI.EntityMenuFrame().items").values()
        if b.IsShown(b)
    ]
    assert labels == ["Show on map", "Open"]
    core.execute("Bastians.UI.EntityMenuFrame().items[1]:Click()")
    assert list(core.g.ran.values()) == ["npc:448/tree", "npc:448/tree"]
    assert core.eval("Bastians.UI.EntityMenuFrame():IsShown()") is False
    assert core.eval("Bastians.UI.EntityMenu('item:1', nil, {})") == 1  # only the "*" action
    assert core.eval("Bastians.UI.EntityMenu('zone:1429', nil, { source = 'x' })") == 1
    core.execute("Bastians:GetModule('Acts'):Disable()")
    assert core.eval("Bastians.UI.EntityMenu('npc:448', nil, {})") == 0


def test_tree_rows_show_action_icons_on_hover_and_on_the_focused_row(core: WowRuntime):
    """ADR 0013 C: up to four icons from the registered actions, on hover and on the focused row."""
    core.execute(TREE)
    core.execute(
        """
        local m = Bastians:NewModule("Acts", { addon = "Bastians_Core" })
        ran = {}
        Bastians:RegisterAction(m, { id = "map.show", label = "Show on map", types = "*", order = 10,
          icon = "Interface\\Icons\\INV_Misc_Map_01",
          when = function(ref) return ref ~= "npc:1" end,
          run = function(ref, ctx) ran[#ran + 1] = "locate " .. ref end })
        Bastians:RegisterAction(m, { id = "quests.voice", label = "Play the voice line", types = { "quest" },
          order = 80, has = function(ref) return ref == "quest:2" end,
          when = function(ref) return ref == "quest:2" end,
          active = function(ref) return playing == ref end,
          run = function(ref) playing = ref ran[#ran + 1] = "play " .. ref end })
        Bastians:RegisterAction(m, { id = "browser.open", label = "Open", types = "*", order = 20,
          run = function(ref) ran[#ran + 1] = "open " .. ref end })
        tree:SetRows({ { text = "Hogger", ref = "npc:448" }, { text = "A quest", ref = "quest:2" },
          { text = "Silent", ref = "quest:3" }, { text = "Nowhere", ref = "npc:1" }, { text = "Plain" } })
        """
    )
    # three of the four slots are registered: that much space is kept free right of every ref row
    assert core.eval("Bastians.UI.TreeUtil.actionSlots()") == 3
    assert core.eval("tree.pool[1].iconRight") == 6
    assert core.eval("tree.pool[5].iconCount") == 0
    # nothing shows until the mouse is there; hover shows the icons the actions allow now
    assert core.eval("tree.pool[1].iconCount") == 0
    core.execute("tree.pool[1]:GetScript('OnEnter')(tree.pool[1])")
    assert core.eval("tree.pool[1].iconCount") == 2  # locate, open (no voice on an NPC)
    assert [b.action.id for b in core.eval("tree.pool[1].icons").values() if b.IsShown(b)] == [
        "map.show",
        "browser.open",
    ]
    core.execute("tree.pool[2]:GetScript('OnEnter')(tree.pool[2])")
    assert [b.action.id for b in core.eval("tree.pool[2].icons").values() if b.IsShown(b)] == [
        "map.show",
        "quests.voice",
        "browser.open",
    ]
    core.execute("tree.pool[3]:GetScript('OnEnter')(tree.pool[3])")
    assert core.eval("tree.pool[3].iconCount") == 2  # no line: no play icon
    core.execute("tree.pool[4]:GetScript('OnEnter')(tree.pool[4])")
    assert [b.action.id for b in core.eval("tree.pool[4].icons").values() if b.IsShown(b)] == [
        "browser.open"
    ]  # `when` said no to map.show
    core.execute("tree.pool[5]:GetScript('OnEnter')(tree.pool[5])")
    assert core.eval("tree.pool[5].iconCount") == 0
    # a click runs the action with the tree's context; the active one is tinted
    core.execute("tree.pool[2].icons[2]:Click()")
    assert list(core.g.ran.values()) == ["play quest:2"]
    core.execute("tree.pool[2]:GetScript('OnEnter')(tree.pool[2])")
    r, g, b = core.eval("tree.pool[2].icons[2].tex:GetVertexColor()")[:3]
    # the same icon in green while on
    assert (r, g, b) == tuple(
        list(core.eval("Bastians.UI.Style.C.on").values())[:3]
    )  # the theme's on colour (ST3)
    core.execute("tree.pool[1].icons[1]:Click()")
    assert list(core.g.ran.values())[-1] == "locate npc:448"
    # leaving hides them, unless the row is the focused one
    core.execute("tree.pool[1]:GetScript('OnLeave')(tree.pool[1])")
    assert core.eval("tree.pool[1].iconCount") == 0
    core.execute("Bastians:Focus('npc:448', { source = 'test' })")
    core.execute("tree:Render()")
    assert core.eval("tree.pool[1].iconCount") == 2
    assert core.eval("tree.pool[2].iconCount") == 0
    core.execute("tree.pool[1]:GetScript('OnLeave')(tree.pool[1])")
    assert core.eval("tree.pool[1].iconCount") == 2
    assert core.eval("Bastians:Focused()") == "npc:448"
    core.execute("Bastians:Focus(nil)")
    core.execute("tree:Render()")
    assert core.eval("tree.pool[1].iconCount") == 0
    # without any of the four actions no space is kept
    core.execute("Bastians:GetModule('Acts'):Disable()")
    core.execute("tree:Render()")
    assert core.eval("Bastians.UI.TreeUtil.actionSlots()") == 0
    assert core.errors == []


def test_tree_chips_are_one_pill_with_a_dropdown(core: WowRuntime):
    """ADR 0016: the old chip groups render as the filter bar, one pill per group; the dropdown
    lists All and the choices with counts; one choice is nothing to choose."""
    core.execute(TREE)
    core.execute(
        """
        picked = {}
        tree:SetChips({ { key = "vendor", label = "Vendors", count = 3 }, { key = "trainer", label = "Trainers" } },
          "vendor", function(key) picked[#picked + 1] = tostring(key) end, nil, "Service")
        """
    )
    assert pills(core, "tree") == ["Service: Vendors"]
    assert menu(core, "tree", "chips1") == ["All", "Vendors  3", "Trainers"]
    pick(core, "tree", "chips1", "Trainers")
    clear(core, "tree", "chips1")  # the x: back to All
    assert list(core.g.picked.values()) == ["trainer", "nil"]
    core.execute("tree:SetChips({ { key = 'only', label = 'Only one' } }, nil, nil)")
    assert pills(core, "tree") == []  # a single facet shows no pill
    assert core.eval("tree.chips:GetHeight()") == 1


def test_filter_bar_pills_wrap_clear_and_close(core: WowRuntime):
    """The filter bar (ADR 0016): "Title: Choice" pills, the x only on a choice of the player's
    (a sort's default has none), the counts in the dropdown, a second line when narrow, the
    dropdown closes on a click elsewhere."""
    core.execute(
        """
        local parent = CreateFrame("Frame", nil, UIParent)
        parent:SetSize(500, 300)
        bar = Bastians.UI.FilterBar(parent)
        bar.frame:SetPoint("TOPLEFT"); bar.frame:SetWidth(500)
        got = {}
        local function pick(id) return function(key) got[#got + 1] = id .. "=" .. tostring(key) end end
        bar:SetDims({
          { id = "where", title = "Where", active = "here", all = { label = "All", count = 9 },
            choices = { { key = "here", label = "Here", count = 4 }, { key = "continent", label = "Continent", count = 7 } },
            onSelect = pick("where") },
          { id = "kind", title = "Kind", choices = { { key = "Mailbox", label = "Mailbox", count = 2 } },
            all = { count = 9 }, onSelect = pick("kind") },
          { id = "empty", title = "Empty", choices = {}, all = false, onSelect = pick("empty") },
          { id = "sort", title = "Sort", active = "name", default = "name", all = false,
            choices = { { key = "name", label = "Name" }, { key = "near", label = "Nearest" } },
            onSelect = pick("sort") },
        })
        """
    )
    assert [str(s) for s in core.eval("bar:Labels()").values()] == [
        "Where: Here",
        "Kind: All",
        "Sort: Name",
    ]  # the dimension without choices is left out
    assert core.eval("bar:Pill('where').clear:IsShown()") is True
    assert core.eval("bar:Pill('kind').clear:IsShown()") is False
    assert core.eval("bar:Pill('sort').clear:IsShown()") is False  # the default sort
    core.execute("bar:Pill('where').clear:Click()")
    core.execute("bar:Pill('sort'):Click()")
    m = core.eval("Bastians.UI.FilterMenuFrame()")
    assert m.IsShown(m) is True
    entries = [b.label.GetText(b.label) for b in m["items"].values() if b.IsShown(b)]
    assert entries == ["Name", "Nearest"]  # no All in a sort
    core.execute("Bastians.UI.FilterMenuFrame().items[2]:Click()")
    assert list(core.g.got.values()) == ["where=nil", "sort=near"]
    assert m.IsShown(m) is False
    # one line at 500 px; a narrow bar wraps onto a second line
    one = core.eval("bar:Height()")
    core.execute("bar.frame:SetWidth(120); bar:Layout()")
    assert core.eval("bar:Height()") > one
    # a click elsewhere closes the dropdown
    core.execute("bar:Pill('kind'):Click()")
    core.execute("Mock.cursorX, Mock.cursorY = -5000, -5000")
    core.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    assert core.eval("Bastians.UI.FilterMenuFrame():IsShown()") is False
    assert core.errors == []


def test_docked_window_resizes_in_width_only_and_stays_docked(core: WowRuntime):
    """the grip of a docked window changes its width only, and the
    pair stays docked through a resize of either window."""
    core.execute(
        """
        leadDB2, followDB2 = { size = { 600, 400 } }, { size = { 400, 500 } }
        lead2 = Bastians.UI.Window("BastiansDockLead2", { db = leadDB2, width = 600, height = 400 })
        follow2 = Bastians.UI.Window("BastiansDockFollow2", { db = followDB2, width = 400, height = 500 })
        lead2:Show(); follow2:Show(); follow2:DockWith(lead2, "right")
        """
    )
    core.execute("follow2.grip:GetScript('OnMouseDown')(follow2.grip)")
    assert core.eval("follow2.frame.sizingEdge") == "RIGHT"
    core.execute("follow2.grip:GetScript('OnMouseUp')(follow2.grip)")
    assert core.eval("follow2:IsDocked()") is True
    core.execute("follow2:Undock(); follow2:DockWith(lead2, 'left')")
    core.execute("follow2.grip:GetScript('OnMouseDown')(follow2.grip)")
    assert core.eval("follow2.frame.sizingEdge") == "LEFT"
    core.execute("follow2.grip:GetScript('OnMouseUp')(follow2.grip)")
    # the leader's grip keeps both axes, and its size change still reaches the follower
    core.execute("lead2.grip:GetScript('OnMouseDown')(lead2.grip)")
    assert core.eval("lead2.frame.sizingEdge") == "BOTTOMRIGHT"
    core.execute(
        "lead2.frame:SetSize(620, 430); lead2.frame:GetScript('OnSizeChanged')(lead2.frame)"
    )
    core.execute("lead2.grip:GetScript('OnMouseUp')(lead2.grip)")
    assert core.eval("follow2:IsDocked()") is True and core.eval("follow2.frame:GetHeight()") == 430
    assert core.errors == []


def test_right_drag_gesture_goes_back_and_forward_with_an_arrow(core: WowRuntime):
    """a right-button drag over the window goes back (left) or
    forward (right), an arrow flashes, and B.UI.GestureRecent() swallows that right click."""
    core.execute(
        """
        moves = {}
        gw = Bastians.UI.Window("BastiansGestureTest", { db = {}, gestures = {
          back = function() moves[#moves + 1] = "back" end,
          forward = function() moves[#moves + 1] = "forward" end } })
        gw:Show()
        """
    )
    assert core.eval("gw.gestureWatcher:GetScript('OnUpdate') ~= nil") is True
    core.execute("Mock.mouseOverFrame = gw.frame; Mock.cursorX = 500")
    core.execute("Mock.SetMouseButton('RightButton', true)")
    core.run_frames(2)
    core.execute("Mock.cursorX = 470")  # 30 px: not yet
    core.run_frames(2)
    assert core.eval("gw.gestureArrow") is None
    core.execute("Mock.cursorX = 450")  # 50 px to the left: back
    core.run_frames(2)
    assert core.eval("gw.gestureArrow:IsShown()") is True
    # a real arrow texture with a shaft, mirrored for back
    assert core.eval("gw.gestureArrow.dir") == "back"
    assert core.eval("gw.gestureArrow.tex:GetTexture()") == core.eval("Bastians.UI.Style.ARROW")
    assert core.eval("gw.gestureArrow:GetWidth()") == 96
    assert core.eval("Bastians.UI.GestureRecent()") is True
    core.execute("Mock.SetMouseButton('RightButton', false)")
    core.run_frames(2)
    assert list(core.eval("moves").values()) == ["back"]
    core.advance(0.5)
    assert core.eval("gw.gestureArrow:IsShown()") is False
    core.advance(0.5)
    assert core.eval("Bastians.UI.GestureRecent()") is False
    # the other way; then a drag under the threshold does nothing
    core.execute("Mock.cursorX = 500; Mock.SetMouseButton('RightButton', true)")
    core.run_frames(2)
    core.execute("Mock.cursorX = 560")
    core.run_frames(2)
    core.execute("Mock.SetMouseButton('RightButton', false)")
    core.run_frames(2)
    assert list(core.eval("moves").values()) == ["back", "forward"]
    assert core.eval("gw.gestureArrow.dir") == "forward"
    core.execute("Mock.SetMouseButton('RightButton', true)")
    core.run_frames(2)
    core.execute("Mock.cursorX = 570; Mock.SetMouseButton('RightButton', false)")
    core.run_frames(2)
    assert list(core.eval("moves").values()) == ["back", "forward"]
    # the watcher stops with the window
    core.execute("gw:Hide()")
    assert core.eval("gw.gestureWatcher:GetScript('OnUpdate')") is None
    core.execute("Mock.mouseOverFrame = nil")
    assert core.errors == []


def test_tree_two_line_rows_draw_the_meta_under_the_name(core: WowRuntime):
    """R2: with `twoLine`, a row that carries `meta` takes two lines: the name
    (row.title when the one-line text has the meta too) and its icons on the first, the meta text
    and the value on the second, a divider below; rows without meta stay one line."""
    core.execute(TREE)
    core.execute(
        """
        tree2 = Bastians.UI.Tree(host, { db = {}, twoLine = true, iconsAlways = true })
        tree2.scroll:SetSize(386, 200)
        tree2:SetRows({
          { id = "a", text = "Quest A  Chain 1/4 - 52 xp", title = "Quest A", meta = "Chain 1/4 - 52 xp",
            value = 1500, valueKind = "money", ref = "npc:1" },
          { id = "b", text = "Plain row", ref = "npc:2" },
          { id = "c", text = "Quest C", meta = "4 min" },
        })
        """
    )
    assert list(core.eval("tree2.heights").values()) == [34, 18, 34]
    a, b, c = (core.eval(f"tree2.pool[{i}]") for i in (1, 2, 3))
    assert a.twoLine is True and not b.twoLine
    assert a.text.GetText(a.text) == "Quest A" and a.meta.GetText(a.meta) == "Chain 1/4 - 52 xp"
    assert a.meta.IsShown(a.meta) is True and a.div.IsShown(a.div) is True
    assert a.value.IsShown(a.value) is True
    assert a.value.GetPoint(a.value, 1)[0] == "BOTTOMRIGHT"  # the value on the second line
    assert b.meta.IsShown(b.meta) is False and b.div.IsShown(b.div) is False
    assert b.text.GetText(b.text) == "Plain row"
    assert (
        c.text.GetText(c.text) == "Quest C" and c.meta.GetText(c.meta) == "4 min"
    )  # no title: the text
    # one-line trees ignore meta
    core.execute(
        'tree:SetRows({ { id = "a", text = "Quest A  Chain 1/4", meta = "Chain 1/4", ref = "npc:1" } })'
    )
    assert list(core.eval("tree.heights").values()) == [18]
    assert core.eval("tree.pool[1].text:GetText()") == "Quest A  Chain 1/4"
    assert core.errors == []


def test_tree_with_icons_always_keeps_them_after_a_hover(core: WowRuntime):
    """the Chain rows lost their icons after one hover; a tree that
    shows icons always keeps them through OnEnter and OnLeave."""
    core.execute(TREE)
    core.execute(
        """
        local owner = Bastians:NewModule("IconTest", { addon = "Bastians_Core" })
        Bastians:RegisterAction(owner, { id = "map.show", label = "Go", types = "*", order = 10,
          run = function() end }) -- a row icon id (Tree.ROW_ACTIONS); no Map in this fixture
        tree3 = Bastians.UI.Tree(host, { db = {}, iconsAlways = true })
        tree3.scroll:SetSize(386, 200)
        tree3:SetRows({ { id = "a", text = "Hogger", ref = "npc:448" } })
        """
    )
    assert core.eval("tree3.pool[1].iconCount") >= 1
    core.execute("tree3.pool[1]:GetScript('OnEnter')(tree3.pool[1])")
    core.execute("tree3.pool[1]:GetScript('OnLeave')(tree3.pool[1])")
    assert core.eval("tree3.pool[1].icons[1]:IsShown()") is True
    # the icon button's own leave keeps them too
    core.execute("tree3.pool[1].icons[1]:GetScript('OnLeave')(tree3.pool[1].icons[1])")
    assert core.eval("tree3.pool[1].icons[1]:IsShown()") is True
    # a plain tree hides them on leave, as before
    core.execute('tree:SetRows({ { id = "a", text = "Hogger", ref = "npc:448" } })')
    core.execute("tree.pool[1]:GetScript('OnEnter')(tree.pool[1])")
    assert core.eval("tree.pool[1].icons[1]:IsShown()") is True
    core.execute("tree.pool[1]:GetScript('OnLeave')(tree.pool[1])")
    assert core.eval("tree.pool[1].icons[1]:IsShown()") is False
    assert core.errors == []


def test_row_tags_mark_and_dim_rows(core: WowRuntime):
    """R3: a registered row tag appends its word greyed to every row of that entity type."""
    core.execute(TREE)
    core.execute(
        """
        local owner = Bastians:NewModule("TagTest", { addon = "Bastians_Core" })
        Bastians:RegisterRowTag(owner, { id = "test.odd", types = { "npc" },
          tag = function(ref) return ref == "npc:1" and "odd" or nil end })
        tree:SetRows({ { id = "a", text = "One", ref = "npc:1" }, { id = "b", text = "Two", ref = "npc:2" },
          { id = "c", text = "Item", ref = "item:1" } })
        """
    )
    assert (
        core.eval("Bastians:RowTag('npc:1')") == "odd"
        and core.eval("Bastians:RowTag('npc:2')") is None
    )
    assert core.eval("Bastians:RowTag('item:1')") is None
    assert core.eval("tree.pool[1].text:GetText()") == "One|cff808080  (odd)|r"
    assert core.eval("tree.pool[2].text:GetText()") == "Two"
    assert core.errors == []


def test_a_docked_follower_refreshes_coalesced_while_the_leader_is_resized(core: WowRuntime):
    """(N1): resizing the map with the Browser docked crawled. Each of the
    leader's size events gave the follower two full refreshes (its own size event and the dock's
    placement). Now the follower refreshes coalesced while the leader's grip is held, and once in
    full after the release."""
    core.execute(
        """
        calls = {}
        leadDB, followDB = { pos = { 100, -100 }, size = { 600, 400 } }, { pos = { 900, -50 }, size = { 400, 500 } }
        lead = Bastians.UI.Window("BastiansDockLead3", { db = leadDB, width = 600, height = 400 })
        follow = Bastians.UI.Window("BastiansDockFollow3", { db = followDB, width = 400, height = 500,
          onResize = function(_, sizing) calls[#calls + 1] = sizing end })
        lead:Show(); follow:Show()
        follow:DockWith(lead, 'right')
        -- the client fires a frame's OnSizeChanged when its size changes: the mock does it here
        local setHeight = follow.frame.SetHeight
        follow.frame.SetHeight = function(f, h)
          setHeight(f, h)
          f:GetScript('OnSizeChanged')(f)
        end
        calls = {}
        lead.grip:GetScript('OnMouseDown')(lead.grip)
        """
    )
    for h in (410, 420, 430, 440):
        core.execute(
            f"lead.frame:SetSize(600, {h}); lead.frame:GetScript('OnSizeChanged')(lead.frame)"
        )
    assert list(core.eval("calls").values()) == []  # no full refresh per frame
    assert core.eval("follow.frame:GetHeight()") == 440  # the height follows at once
    core.advance(0.15)
    assert list(core.eval("calls").values()) == [True]  # four events, one coalesced refresh
    core.execute("lead.grip:GetScript('OnMouseUp')(lead.grip)")
    assert list(core.eval("calls").values()) == [True, False]  # one full refresh on release
    core.advance(0.2)
    assert list(core.eval("calls").values()) == [True, False]
    assert core.eval("follow.followSizing") is None
    assert core.errors == []


def test_buttons_explain_themselves_after_the_hover_delay(core: WowRuntime):
    """(N4): every button of every addon shows an explanation after the
    mouse rests on it for a while (one second by default, set on the General page; off hides
    them). Leaving before the delay shows nothing."""
    core.execute(
        """
        local S = Bastians.UI.Style
        tipB = S.button(UIParent, "Target", 54, 22)
        tipB.tip = function() return "Follow your target", "The page shows what you target." end
        plainB = S.button(UIParent, "Plain", 54, 22)
        function tipLines()
          local out = {}
          for _, l in ipairs(GameTooltip.lines) do out[#out + 1] = l.left end
          return out
        end
        GameTooltip:ClearLines(); GameTooltip:Hide()
        tipB:GetScript('OnEnter')(tipB)
        """
    )
    core.advance(0.5)
    assert core.eval("GameTooltip:IsShown()") is False  # not yet
    core.advance(0.6)
    assert core.eval("GameTooltip:IsShown()") is True
    assert core.eval("GameTooltip:GetOwner() == tipB") is True
    assert list(core.eval("tipLines()").values())[:2] == [
        "Follow your target",
        "The page shows what you target.",
    ]
    core.execute("tipB:GetScript('OnLeave')(tipB)")
    assert core.eval("GameTooltip:IsShown()") is False
    # leaving before the delay: nothing shows later
    core.execute("GameTooltip:ClearLines(); tipB:GetScript('OnEnter')(tipB)")
    core.advance(0.4)
    core.execute("tipB:GetScript('OnLeave')(tipB)")
    core.advance(1)
    assert core.eval("GameTooltip:IsShown()") is False
    # a button without a tip shows none; the delay 0 shows at once; tips off shows none
    core.execute("plainB:GetScript('OnEnter')(plainB)")
    core.advance(1.5)
    assert core.eval("GameTooltip:IsShown()") is False
    core.execute(
        "Bastians:GetModule('Core').db.profile.tipDelay = 0; tipB:GetScript('OnEnter')(tipB)"
    )
    assert core.eval("GameTooltip:IsShown()") is True
    core.execute(
        "tipB:GetScript('OnLeave')(tipB); Bastians:GetModule('Core').db.profile.tips = false;"
        " tipB:GetScript('OnEnter')(tipB)"
    )
    core.advance(1.5)
    assert core.eval("GameTooltip:IsShown()") is False
    assert core.errors == []


def test_every_toolbar_button_of_the_apps_has_a_tip(wow: WowRuntime):
    """N4: the Browser's, the Map's and the Gold window's buttons all carry an explanation."""
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Map", "Bastians_Gold")
    wow.run_frames(10)
    wow.slash("/bb")
    wow.slash("/bmap")
    wow.slash("/bgold")
    wow.run_frames(5)
    untipped = wow.eval(
        """(function()
          local out = {}
          local function check(name, b)
            if b and not b.tip then out[#out + 1] = name end
          end
          local Br = Bastians:GetModule('Browser').Browser
          local tb = Br.toolbar
          for _, k in ipairs({ 'back', 'forward', 'home', 'bookmarks', 'target', 'slim', 'dock' }) do
            check('browser.' .. k, tb[k])
          end
          local mt = Bastians:GetModule('Map').Map.toolbar
          for _, k in ipairs({ 'player', 'full', 'zoomIn', 'zoomOut', 'layers', 'follow', 'dock' }) do
            check('map.' .. k, mt[k])
          end
          return out
        end)()"""
    )
    assert list(untipped.values()) == []
    assert wow.errors == []


def test_a_long_worth_never_wraps_over_the_rows(app: WowRuntime):
    """(N5, T14): a long worth in the value column wrapped over the row's
    icons and the next rows. One-line rows keep it on one line, a third of the row at most (the
    client cuts it with an ellipsis); two-line rows give it one or two lines of its own."""
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterEntityType(m, { type = "quest", name = function(id) return "Quest " .. id end })
        Bastians:RegisterWorth(m, { types = { "quest" }, worth = function(ref)
          return { text = "1s 25c - 480 XP - +150 Stormwind - +75 Ironforge - reward 50s 00c - unlocks 2" }
        end })
        host1 = CreateFrame("Frame", nil, UIParent); host1:SetSize(300, 200)
        one = Bastians.UI.Tree(host1, {})
        one.scroll:SetSize(300, 200)
        one:SetRows({ { text = "Quest 1", ref = "quest:1" } })
        host2 = CreateFrame("Frame", nil, UIParent); host2:SetSize(300, 200)
        two = Bastians.UI.Tree(host2, { twoLine = true })
        two.scroll:SetSize(300, 200)
        two:SetRows({ { text = "Quest 2", title = "Quest 2", meta = "Chain 1/3 - 400 xp", ref = "quest:2" } })
        """
    )
    app.run_frames(2)
    f1 = app.eval("one.pool[1]")
    assert f1.value.IsShown(f1.value) and f1.value.wordWrap is False
    assert f1.value.GetWidth(f1.value) <= 100  # a third of 300
    f2 = app.eval("two.pool[1]")
    assert not f2.value.IsShown(f2.value) and f2.worth.IsShown(f2.worth)
    assert "unlocks 2" in f2.worth.GetText(f2.worth)
    assert f2.GetHeight(f2) == 34 + 24 + 2  # two worth lines at this width
    assert app.errors == []


def test_windows_step_aside_for_the_games_interaction_panels(app: WowRuntime):
    """(A3, severe): with the Gold window open the vendor's "I want to
    browse your goods" could not be clicked; our windows sit above every game panel. A window that
    overlaps a shown gossip or merchant panel steps to its right and comes back when it closes;
    moved by hand meanwhile, it stays where the player put it."""
    app.execute(
        """
        dw = Bastians.UI.Window("BastiansDodgeTest", { db = { pos = { 40, -80 } }, width = 300, height = 200 })
        dw:Show()
        GossipFrame:Show()
        Mock.Fire("GOSSIP_SHOW")
        """
    )
    app.advance(0.1)
    anchor = app.eval("{ dw.frame:GetPoint(1) }")
    assert anchor[1] == "TOPLEFT" and anchor[3] == "TOPRIGHT"
    assert app.eval("select(2, dw.frame:GetPoint(1)) == GossipFrame") is True
    app.execute("GossipFrame:Hide(); Mock.Fire('GOSSIP_CLOSED')")
    app.advance(0.1)
    assert app.eval("select(4, dw.frame:GetPoint(1))") == (40, -80)
    assert app.eval("dw.dodged") is None
    # moved by hand while aside: it stays there
    app.execute("MerchantFrame:Show(); Mock.Fire('MERCHANT_SHOW')")
    app.advance(0.1)
    assert app.eval("select(2, dw.frame:GetPoint(1)) == MerchantFrame") is True
    app.execute(
        "dw.head:GetScript('OnDragStart')(dw.head); dw.head:GetScript('OnDragStop')(dw.head)"
    )
    assert app.eval("dw.dodged") is None  # the hand's place is its place now
    app.execute("MerchantFrame:Hide(); Mock.Fire('MERCHANT_CLOSED')")
    app.advance(0.1)
    # nothing restored (the mock's drag keeps the anchor it had): not back to (40, -80)
    assert app.eval("select(4, dw.frame:GetPoint(1))") != (40, -80)
    assert app.errors == []


def test_the_entity_menu_is_opaque_one_line_per_entry_and_wide_enough(app: WowRuntime):
    """(W1): the right-click menu looked transparent and overlapped
    the frame below: its long labels wrapped over the next entries. Each entry is one line, the
    menu as wide as its widest entry (at most 380), the background opaque."""
    app.execute(
        """
        local m = Bastians:GetModule("TestApp")
        Bastians:RegisterEntityType(m, { type = "quest", name = function(id) return "Quest " .. id end })
        Bastians:RegisterAction(m, { id = "t.short", label = "Map", types = { "quest" }, run = function() end })
        Bastians:RegisterAction(m, { id = "t.long", label = "Show the quest's targets on the map, all of them",
          types = { "quest" }, run = function() end })
        Bastians.UI.EntityMenu("quest:1", UIParent, { source = "test" })
        """
    )
    menu = app.eval("Bastians.UI.EntityMenuFrame()")
    assert menu.IsShown(menu)
    labels = [b.label for b in menu["items"].values() if b.IsShown(b)]  # lupa: index items
    assert all(label.wordWrap is False for label in labels)
    longest = max(label.GetStringWidth(label) for label in labels)
    assert menu.GetWidth(menu) >= min(380, longest + 24)
    assert menu.bg.GetVertexColor(menu.bg)[3] == 1
    assert app.errors == []
