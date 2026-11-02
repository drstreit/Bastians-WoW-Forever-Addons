"""Owner round 5 (retail, 31.10.2026), the item and recipe pages: a recipe shows what it makes with
its picture and the game's lines ("recipe information is extremely flat"), an item page its own
lines, the recipes that use it and the recipes that make it ("the item detail page should like
usage in recipes")."""

import re

from harness import WowRuntime

CORE, DATA, BROWSER = "Bastians_Core", "Bastians_Data", "Bastians_Browser"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, BROWSER)
    wow.run_frames(10)
    for pack in ("world", "items"):
        wow.execute(f'Bastians:GetService("data"):LoadPack("{pack}")')
    wow.run_frames(5)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def sections(wow: WowRuntime, ref: str) -> dict:
    return {s.id: s for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()}


def rows(wow: WowRuntime, ref: str, section: str) -> list:
    return list(sections(wow, ref)[section].rows.values())


SABER_LINES = """{
  { leftText = "Blood Saber", leftColor = { r = 0.12, g = 1, b = 0 } },
  { leftText = "Binds when equipped", leftColor = { r = 1, g = 1, b = 1 } },
  { leftText = "One-Hand", rightText = "Sword", leftColor = { r = 1, g = 1, b = 1 } },
  { leftText = "Equip: Improves your chance to hit by 1%.", leftColor = { r = 0, g = 1, b = 0 } },
  { leftText = "Requires Level 2", leftColor = { r = 1, g = 0.1, b = 0.1 } },
}"""


def test_an_item_page_shows_the_games_lines(wow: WowRuntime):
    boot(wow)
    wow.execute(f"Mock.itemTooltips[1185] = {SABER_LINES}")
    got = rows(wow, "item:1185", "data.stats")
    assert [strip(r.text) for r in got] == [  # the name is on the band, not here
        "Binds when equipped",
        "One-Hand",
        "Equip: Improves your chance to hit by 1%.",
        "Requires Level 2",
    ]
    assert got[1].value == "Sword" and got[1].kind is None  # right-hand words: a value
    assert got[2].kind == "para"  # a long line wraps
    S = "Bastians.UI.Style"
    assert got[2].text.startswith(wow.eval(f"{S}.H.good"))  # Equip in the theme's green
    assert got[3].text.startswith(wow.eval(f"{S}.H.bad"))  # a requirement not met in red
    assert got[0].text.startswith(wow.eval(f"{S}.H.text"))  # white becomes the theme's text
    assert wow.errors == []


def test_without_the_clients_lines_the_pack_speaks_and_the_item_is_asked_for(wow: WowRuntime):
    boot(wow)
    got = rows(wow, "item:2589", "data.stats")
    assert [(strip(r.text), r.value) for r in got] == [("Item level", 5), ("Vendor sell price", 13)]
    assert 2589 in list(wow.eval("Mock.itemLoadRequests").values())  # asked once
    n = len(wow.eval("Mock.itemLoadRequests"))
    wow.execute("Bastians:InvalidateEntities('item')")
    rows(wow, "item:2589", "data.stats")
    assert len(wow.eval("Mock.itemLoadRequests")) == n  # not again this session
    assert wow.errors == []


def test_a_recipe_shows_its_product_with_picture_and_lines(wow: WowRuntime):
    boot(wow)
    wow.execute(f"Mock.itemTooltips[2304] = {SABER_LINES}")
    got = rows(wow, "recipe:2152", "data.product")
    assert got[0].ref == "item:2304" and got[0].icon is not None  # the product first, its icon
    assert [strip(r.text) for r in got[1:3]] == ["Binds when equipped", "One-Hand"]
    reagents = rows(wow, "recipe:2152", "data.reagents")
    assert [(r.ref, r.value) for r in reagents] == [("item:2318", 1)] and reagents[0].icon
    # the band's portrait shows the product, not the spell
    wow.execute(
        """local parent = CreateFrame("Frame", nil, UIParent)
        ST = Bastians.UI.Stage(parent)
        W = ST:Show("recipe:2152", 96, "Interface\\\\Icons\\\\INV_Misc_QuestionMark")"""
    )
    assert wow.eval("W") == 96
    assert wow.errors == []


def test_an_item_lists_the_recipes_that_use_and_make_it(wow: WowRuntime):
    boot(wow)
    used = rows(wow, "item:2318", "data.usedin")  # Light Leather in the Light Armor Kit
    assert [(strip(r.text), r.ref, r.value) for r in used] == [
        ("Light Armor Kit  Leatherworking 1", "recipe:2152", 1)
    ]
    made = rows(wow, "item:2304", "data.madeby")
    assert [r.ref for r in made] == ["recipe:2152"] and made[0].value is None
    assert "data.usedin" not in sections(wow, "item:1185")  # no recipe takes a Blood Saber
    assert wow.errors == []


def test_an_item_says_what_it_disenchants_into(wow: WowRuntime):
    """ "add disenchant information to all items where possible" (the
    fixture's Blood Saber names CMaNGOS list 21, an uncommon weapon's)."""
    boot(wow)
    got = rows(wow, "item:1185", "data.disenchant")
    assert [(strip(r.text), r.ref, r.value, r.valueKind) for r in got] == [
        ("Item 10938  x1-2", "item:10938", 80, "percent"),  # the essence: not in the fixture
        ("Item 10940  x1-2", "item:10940", 20, "percent"),
    ]
    tips = [strip(r.text) for r in wow.eval("Bastians:GetTooltipRows('item:1185')").values()]
    assert any(t.startswith("Disenchant: ") for t in tips)  # the item tooltip says it too
    assert "data.disenchant" not in sections(wow, "item:2589")  # cloth: no list
    assert wow.errors == []
