"""The player button's menu (map.md "The player button", R26.16): the last place of every character
of the account is remembered and listed (newest first, a click flies there), drawn as the layer "My
characters" without the one playing; my location goes to the group, the guild or an online friend
through the notes service; without Notes the share entries say so."""

from harness import WowRuntime

CORE, DATA, MAP, NOTES = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Notes"
MOD = "Bastians:GetModule('Map')"
CH = f"{MOD}.Characters"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, NOTES)))
    wow.run_frames(5)
    wow.slash("/bmap")
    wow.run_frames(2)
    return wow


def labels(wow: WowRuntime) -> list[str]:
    return [i.label for i in wow.eval(f"{CH}.MenuItems()").values()]


def test_the_characters_of_the_account_are_remembered_and_listed(wow: WowRuntime):
    boot(wow)
    me = wow.eval(f"{CH}.Remember()")
    assert me.name == wow.eval("UnitName('player')") and me.continent == 0 and me.zone
    assert me.at == wow.eval("GetServerTime()") and me.level == wow.eval("UnitLevel('player')")
    # another character of the account, seen two hours ago in Westfall
    wow.execute(
        f"""{MOD}.db.global.characters["Nixie-Realm"] = {{ name = "Nixie", realm = GetRealmName(),
          continent = 0, wx = -10600, wy = 1000, map = 1436, zone = "Westfall",
          at = GetServerTime() - 7200, level = 12 }}"""
    )
    items = labels(wow)
    assert items[0] == "My characters"
    assert items[1].startswith(me.name) and items[1].endswith("just now")
    assert items[2] == "Nixie: Westfall, 2 h ago"
    # the entry flies to the character
    wow.execute(f"{CH}.MenuItems()[3].onClick()")
    cam = wow.eval(f"{MOD}.Map.Camera()")
    assert (cam.continent, round(cam.wx), round(cam.wy), cam.level) == (0, -10600, 1000, 3)
    # the layer draws the other character, not me
    pins = list(
        wow.eval(
            "Bastians:QueryLayer('map.characters', { continent = 0, x1 = -20000, y1 = -20000, x2 = 20000, y2 = 20000, level = 1 })"
        ).values()
    )
    assert [p.label for p in pins] == ["Nixie"]
    assert pins[0].card().lines[1].text == "Westfall, 2 h ago"
    # the menu opens on the button's right click
    wow.execute(f"local b = {MOD}.Map.toolbar.player; b:GetScript('OnClick')(b, 'RightButton')")
    assert wow.eval("Bastians.UI.MenuFrame():IsShown()") is True
    assert wow.eval(f"{CH}.Ago(GetServerTime() - 3 * 86400)") == "3 d ago"
    assert wow.errors == []


def test_my_location_goes_to_the_group_the_guild_or_a_friend(wow: WowRuntime):
    boot(wow)
    assert [t.label for t in wow.eval(f"{CH}.ShareTargets()").values()] == [
        "No group, guild or friend online."
    ]
    wow.execute(
        "Mock.groupSize = 2; Mock.inGuild = true; "
        "Mock.friends = { { name = 'Ally' }, { name = 'Gone', online = false }, { name = 'Bob' } }"
    )
    targets = [(t.label, t.channel, t.target) for t in wow.eval(f"{CH}.ShareTargets()").values()]
    assert targets == [
        ("With my group", "PARTY", None),
        ("With my guild", "GUILD", None),
        ("With Ally", "WHISPER", "Ally"),
        ("With Bob", "WHISPER", "Bob"),
    ]
    assert wow.eval(f"{CH}.Share('WHISPER', 'Ally')")[0] is True
    wow.advance(2)
    sent = list(wow.eval("Mock.addonMessages").values())
    assert sent and sent[-1].channel == "WHISPER" and sent[-1].target == "Ally"
    assert "notes.pin" in sent[-1].text
    assert any("Sent to Ally:" in line for line in wow.chat[-2:])
    assert wow.eval(f"{CH}.Share('GUILD')")[0] is True
    wow.advance(2)
    assert any("Sent to your guild:" in line for line in wow.chat[-2:])
    assert wow.errors == []


def test_without_notes_the_menu_says_so(wow: WowRuntime):
    boot(wow, CORE, DATA, MAP)
    assert [t.label for t in wow.eval(f"{CH}.ShareTargets()").values()] == [
        "Bastian's Notes is needed to share."
    ]
    assert wow.eval(f"{CH}.Share('GUILD')") == (None, "notes")
    items = wow.eval(f"{CH}.MenuItems()")
    assert items[len(items)].disabled is True and items[len(items)].onClick is None
    assert wow.errors == []


def test_the_menu_closes_with_the_map_on_esc_and_on_a_click_elsewhere(wow: WowRuntime):
    """(R27.3): the player menu stayed open forever when Esc closed the map;
    it hid only when the mouse left it. Now it goes with its anchor, on Esc and on a click elsewhere."""
    boot(wow)
    open_menu = f"local b = {MOD}.Map.toolbar.player; b:GetScript('OnClick')(b, 'RightButton')"
    shown = "Bastians.UI.MenuFrame():IsShown()"
    wow.execute(open_menu)
    assert wow.eval(shown) is True
    wow.execute("Mock.PressEscape()")  # Esc: the map and the menu close together
    assert wow.eval(shown) is False
    wow.slash("/bmap")
    wow.execute(open_menu)
    # the anchor hides (its window closed by any means): the client runs its OnHide, the menu goes
    wow.execute(f"local b = {MOD}.Map.toolbar.player; b:GetScript('OnHide')(b)")
    assert wow.eval(shown) is False
    # a click elsewhere closes it; a click on the menu or on its button does not
    wow.execute(open_menu)
    wow.execute(
        "Mock.mouseOverFrame = Bastians.UI.MenuFrame(); Mock.Fire('GLOBAL_MOUSE_DOWN', 'LeftButton')"
    )
    assert wow.eval(shown) is True
    wow.execute(
        f"Mock.mouseOverFrame = {MOD}.Map.toolbar.player; Mock.Fire('GLOBAL_MOUSE_DOWN', 'LeftButton')"
    )
    assert wow.eval(shown) is True
    wow.execute("Mock.mouseOverFrame = nil; Mock.Fire('GLOBAL_MOUSE_DOWN', 'LeftButton')")
    assert wow.eval(shown) is False
    assert wow.errors == []
