"""The focus (ADR 0013 D, N6): one selection for map and Browser. A pin click focuses the entity
(ring on its pin, the context strip with name, status words and Open / Route / Play, the Browser's
page), a Browser row click focuses it too (the ring, no flight), Esc on the map clears it, and the
Follow toggle makes the map fly to the Browser's page on every page change."""

import re

from harness import WowRuntime
from pages import click_ref

CORE, DATA, QUESTS, BROWSER, MAP, ROUTE = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
    "Bastians_Map",
    "Bastians_Route",
)
MOD = "Bastians:GetModule('Map')"
MAP_ = f"{MOD}.Map"
PINS = f"{MOD}.Pins"
FOCUS = f"{MOD}.Focus"
BR = "Bastians:GetModule('Browser')"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, QUESTS, BROWSER, MAP)))
    wow.run_frames(10)
    wow.slash("/bmap")
    wow.execute(f"{MAP_}.clip:SetSize(600, 400); {MAP_}.ViewChanged()")
    wow.execute(f"{MAP_}.Fly(0, 0, 0, 6)")  # Elwynn at 2 px per yard: no clustering
    wow.advance(0.3)
    return wow


def strip(text: str) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def pin(wow: WowRuntime, ref: str):
    return next(
        p
        for p in wow.eval(f"{PINS}.pinPool").values()
        if p.IsShown(p) and p.pin and p.pin.ref == ref
    )


def rings(wow: WowRuntime) -> list[str]:
    return [
        p.pin.ref
        for p in wow.eval(f"{PINS}.pinPool").values()
        if p.IsShown(p) and p.ring.IsShown(p.ring)
    ]


def strip_buttons(wow: WowRuntime) -> list[str]:
    s = wow.eval(f"{MAP_}.strip")
    return [strip(b.label.GetText(b.label)) for b in s.buttons.values() if b.IsShown(b)]


def test_a_pin_click_focuses_rings_and_fills_the_strip(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MAP_}.strip:IsShown()") is False
    assert wow.eval("Bastians:Focused()") is None
    marshal = pin(wow, "npc:240")
    marshal.GetScript(marshal, "OnClick")(marshal, "LeftButton")
    assert wow.eval("Bastians:Focused()") == "npc:240"
    assert rings(wow) == ["npc:240"]
    assert wow.eval(f"{MAP_}.strip:IsShown()") is True
    assert wow.eval(f"{MAP_}.strip.name:GetText()") == "Marshal Dughan"
    assert strip(wow.eval(f"{MAP_}.strip.words:GetText()")) == "Level 10, Elwynn Forest"
    assert strip_buttons(wow) == ["Open in Browser"]  # no Route, no line to play
    # the page opened in the Browser with the pin click
    assert wow.eval(f"{BR}.Browser.Current().ref") == "npc:240"
    # the strip as data, and the Open button runs the action
    data = wow.eval(f"{FOCUS}.StripData('quest:62')")
    assert data.name == "The Fargodeep Mine" and "complete" in strip(data.words)
    wow.execute(f"{BR}.Browser.Open('npc:448')")
    wow.execute(f"{MAP_}.strip.buttons[1]:Click()")
    assert wow.eval(f"{BR}.Browser.Current().ref") == "npc:240"
    assert wow.errors == []


def test_a_browser_row_focuses_without_flying_and_esc_clears(wow: WowRuntime):
    boot(wow)
    cx, cy = wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")
    wow.execute(f"{BR}.Browser.Open('zone:1429')")
    assert click_ref(wow, f"{BR}.dossier", "npc:240") is True
    assert wow.eval("Bastians:Focused()") == "npc:240"
    assert wow.eval(f"{BR}.Browser.Current().ref") == "npc:240"
    assert rings(wow) == ["npc:240"]
    assert (wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")) == (cx, cy)
    assert wow.eval(f"{MAP_}.strip.name:GetText()") == "Marshal Dughan"
    # Esc on the map clears the focus and keeps the window; a second Esc is for the window
    wow.execute(f"{MAP_}.clip:GetScript('OnKeyDown')({MAP_}.clip, 'ESCAPE')")
    assert wow.eval("Bastians:Focused()") is None
    assert wow.eval(f"{MAP_}.IsShown()") is True
    assert wow.eval(f"{MAP_}.strip:IsShown()") is False
    assert rings(wow) == []
    assert wow.eval(f"{FOCUS}.Escape()") is False
    assert wow.errors == []


def test_the_map_no_longer_follows_the_browser_page(wow: WowRuntime):
    """Follow is gone; a page in the Browser leaves the map where it is."""
    boot(wow)
    assert wow.eval(f"{MAP_}.toolbar.follow") is None
    cx, cy = wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")
    wow.execute(f"{BR}.Browser.Open('npc:448')")
    assert (wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")) == (cx, cy)
    assert wow.errors == []


def test_the_map_grows_without_limit_and_dock_makes_room_for_the_browser(wow: WowRuntime):
    """the map stopped at half the screen; it grows as far as the player
    drags it, and Dock narrows a map too wide for the Browser beside it, then moves the pair onto
    the screen."""
    boot(wow)
    bounds = wow.eval("{ BastiansMapFrame:GetResizeBounds() }")
    assert bounds[3] >= 100000 and bounds[4] >= 100000
    wow.execute("BastiansMapFrame:SetWidth(1900)")  # UIParent is 1920 wide in the mock
    wow.execute(f"{MAP_}.toolbar.dock:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is True
    map_w = wow.eval("BastiansMapFrame:GetWidth()")
    browser_w = wow.eval("BastiansBrowserFrame:GetWidth()")
    assert map_w + 2 + browser_w <= 1920 and map_w >= 400
    assert wow.eval("Bastians:GetModule('Map').db.profile.window.size[1]") == map_w  # kept
    assert wow.errors == []


def test_dock_puts_the_browser_beside_the_map(wow: WowRuntime):
    """ADR 0013 E: a Dock button on the map and the Browser; the map leads, the Browser follows."""
    boot(wow)
    assert wow.eval("Bastians.UI.IsDocked()") is False
    assert wow.eval("BastiansBrowserFrame == nil or not BastiansBrowserFrame:IsShown()") is True
    wow.execute(f"{MAP_}.toolbar.dock:Click()")  # opens the Browser and docks it to the right
    assert wow.eval("Bastians.UI.IsDocked()") is True
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    point = wow.eval("{ BastiansBrowserFrame:GetPoint(1) }")
    assert (point[1], point[2].GetName(point[2]), point[3]) == (
        "TOPLEFT",
        "BastiansMapFrame",
        "TOPRIGHT",
    )
    assert wow.eval("BastiansBrowserFrame:GetHeight()") == wow.eval("BastiansMapFrame:GetHeight()")
    assert (
        wow.eval("Bastians:GetModule('Browser').db.profile.window.dock.with") == "BastiansMapFrame"
    )
    # closed by hand while docked: the next Dock docks again with both shown (owner, Forever
    # 07.11.2026: "the next dock does nothing - it still thinks it's open")
    wow.execute("BastiansBrowserFrame:Hide()")
    wow.execute(f"{MAP_}.toolbar.dock:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is True
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    # the Browser's button undocks where the window stands, at its docked size (owner: it
    # "scales large and strangely from top to bottom")
    seen = wow.eval("{ BastiansBrowserFrame:GetLeft(), BastiansBrowserFrame:GetTop() }")
    width = wow.eval("BastiansBrowserFrame:GetWidth()")
    wow.execute(f"{BR}.toolbar.dock:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is False
    point = wow.eval("{ BastiansBrowserFrame:GetPoint(1) }")
    assert (point[1], point[2].GetName(point[2]), point[3]) == ("TOPLEFT", "UIParent", "BOTTOMLEFT")
    assert (point[4], point[5]) == (seen[1], seen[2])
    assert wow.eval("BastiansBrowserFrame:GetWidth()") == width
    wow.execute(f"{BR}.toolbar.dock:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is True
    wow.execute(f"{MAP_}.toolbar.full:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is False
    assert wow.eval(f"{MAP_}.win:IsFullScreen()") is True
    wow.execute(f"{MAP_}.toolbar.full:Click()")
    # without the Browser the button says so
    wow.execute("Bastians:GetModule('Browser'):Disable()")
    assert wow.eval("Bastians.UI.ToggleDock()") is False
    assert any("Dock needs" in line for line in wow.chat)
    assert wow.errors == []


def test_the_strip_offers_route_and_play_when_their_apps_are_there(wow: WowRuntime):
    boot(wow, CORE, DATA, "Spoken", "Spoken_Quests", QUESTS, BROWSER, MAP, ROUTE, "Bastians_Voice")
    wow.execute(
        "Bastians:GetModule('Voice').Orbit.Hide()"
    )  # the strip, not the orbit, is under test
    wow.execute("Bastians:Focus('npc:240', { source = 'test' })")
    assert strip_buttons(wow) == ["Open in Browser", "Route to"]  # an NPC has a place: Route
    wow.execute("Bastians:Focus('quest:176', { source = 'test' })")
    assert strip_buttons(wow) == ["Open in Browser", "Route to", "Play"]  # a quest has places now
    wow.execute(f"{MAP_}.strip.buttons[3]:Click()")  # Play
    assert len(list(wow.eval("Spoken:GetQueue()").values())) == 1
    wow.execute("Spoken:Fire('AUDIO_CHANGED')")
    assert strip_buttons(wow)[2] == "Stop"
    wow.execute("Bastians:Focus('quest:999', { source = 'test' })")  # no line, no place: Open only
    assert strip_buttons(wow) == ["Open in Browser"]
    assert wow.errors == []


# Westfall placed in the mock and the Deadmines' door listed in Elwynn's zone too, so the fixture's
# dungeon stands in the zones the map queries
WESTFALL = (
    "Mock.maps[1436] = { name = 'Westfall', mapType = 3, parent = 1415,"
    " c00 = { 0, -200, 200 }, c11 = { 0, -600, -200 } }"
)
DOOR_IN_VIEW = (
    "local idx = Bastians:GetService('data'):Index('entrance.byZone')"
    " idx[1429] = idx[1429] or {} table.insert(idx[1429], '36-1')"
)


def test_a_dungeon_from_the_browser_switches_its_layer_on_and_is_ringed(wow: WowRuntime):
    """ "when I click in the browser on a dungeon, I expect to see it - so
    switch on the dungeon layer automatically"."""
    wow.execute(WESTFALL)
    boot(wow, CORE, DATA, BROWSER, MAP)
    wow.execute(DOOR_IN_VIEW)
    layer = f"{PINS}.IsLayerOn(Bastians:GetMapLayer('map.dungeons'))"
    assert wow.eval(layer) is True  # on by default, as Travel was for the doors
    wow.execute(f"{PINS}.SetLayerOn('map.dungeons', false)")
    wow.execute(f"{MAP_}.Fly(0, -300, 32, 5)")  # the door (-488, 32) and a part of Elwynn in view
    wow.advance(0.3)
    shown = [p.pin.ref for p in wow.eval(f"{PINS}.pinPool").values() if p.IsShown(p) and p.pin]
    assert "dungeon:36" not in shown
    # a click on the dungeon's row in the Browser (Browser.lua focuses it with source "browser")
    wow.execute("Bastians:Focus('dungeon:36', { source = 'browser' })")
    wow.advance(0.3)
    assert wow.eval(layer) is True
    door = pin(wow, "dungeon:36")  # the door's pin is the dungeon's: its page, its name
    assert door.pin.label == "The Deadmines" and rings(wow) == ["dungeon:36"]
    # "Show on map" on the dungeon's page switches it on too, from anywhere on the map
    wow.execute(f"{PINS}.SetLayerOn('map.dungeons', false); {MAP_}.Fly(0, 0, 0, 6)")
    wow.execute("Bastians:RunAction('map.show', 'dungeon:36', { source = 'browser' })")
    wow.advance(0.3)
    assert wow.eval(layer) is True
    cam = (wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy"))
    assert cam == (-488, 32)  # at the door
    assert wow.errors == []
