"""Owner round 5 (retail, 31.10.2026), the Core parts: an item row's tooltip is the game's own
(every stat), a recipe row shows its product; boss pins on one spot of a dungeon floor move apart."""

from harness import WowRuntime


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    for pack in ("world", "items"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.run_frames(5)
    return wow


def test_an_item_or_recipe_row_shows_the_games_item_tooltip(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """S = Bastians.UI.Style
        GameTooltip.itemID = nil; GameTooltip.lines = {}
        S.EntityTip(GameTooltip, "item:2589", "Linen Cloth")
        ITEM = GameTooltip.itemID
        GameTooltip.itemID = nil; GameTooltip.lines = {}
        S.EntityTip(GameTooltip, "recipe:2152")
        PRODUCT = GameTooltip.itemID
        GameTooltip.itemID = nil; GameTooltip.lines = {}
        S.EntityTip(GameTooltip, "npc:448")
        NPC_ITEM, NPC_LINE = GameTooltip.itemID, GameTooltip.lines[1] and GameTooltip.lines[1].left"""
    )
    assert wow.eval("ITEM") == 2589
    assert wow.eval("PRODUCT") == 2304  # the Light Armor Kit's product, not the spell
    assert wow.eval("NPC_ITEM") is None and wow.eval("NPC_LINE") == "Hogger"
    assert wow.errors == []


def test_a_tree_row_with_an_item_hovers_the_games_tooltip(wow: WowRuntime):
    boot(wow)
    wow.execute(
        """local parent = CreateFrame("Frame", nil, UIParent)
        parent:SetSize(300, 200)
        T = Bastians.UI.Tree(parent, {})
        T.scroll:SetSize(300, 200)
        T:SetRows({ { ref = "item:1185", text = "Blood Saber" } })
        T:Refresh()
        GameTooltip.itemID = nil
        T.pool[1]:GetScript("OnEnter")(T.pool[1])"""
    )
    assert wow.eval("GameTooltip.itemID") == 1185
    assert wow.errors == []


def test_pins_on_one_spot_move_apart(core: WowRuntime):
    core.execute(
        """Sc = Bastians.UI.Scenery
        P = Sc.SpreadPins({ { 100, 100, "4" }, { 102, 101, "5" }, { 101, 99, "6" }, { 300, 50, "1" } })
        floor = { w = 1000, h = 500, bosses = { { 4, 20, 50, "A" }, { 5, 20.2, 50, "B" } } }
        H, T, FP = Sc.FloorLayout(floor, 400)"""
    )
    pins = [list(p.values()) for p in core.eval("P").values()]
    gap = core.eval("Sc.PIN_GAP")
    near = pins[:3]
    for i in range(3):
        for j in range(i + 1, 3):
            d = ((near[i][0] - near[j][0]) ** 2 + (near[i][1] - near[j][1]) ** 2) ** 0.5
            assert d >= gap - 0.01, (i, j, d)
    mid_x = sum(p[0] for p in near) / 3
    assert abs(mid_x - 101) < 0.01  # around their middle
    assert pins[0][1] < pins[1][1]  # the first on top
    assert pins[3][:2] == [300, 50]  # a pin alone stays where it is
    fp = [list(p.values()) for p in core.eval("FP").values()]
    d = ((fp[0][0] - fp[1][0]) ** 2 + (fp[0][1] - fp[1][1]) ** 2) ** 0.5
    assert d >= gap - 0.01  # the floor plate spreads its pins too
    assert core.errors == []
