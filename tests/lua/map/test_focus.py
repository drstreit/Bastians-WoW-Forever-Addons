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


def test_follow_flies_to_the_browser_page(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{FOCUS}.IsFollowing()") is False
    assert wow.eval(f"{MOD}.db.profile.follow") is False
    cx, cy = wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")
    wow.execute(f"{BR}.Browser.Open('npc:448')")  # Hogger, far from the view's centre
    assert (wow.eval(f"{MAP_}.Camera().wx"), wow.eval(f"{MAP_}.Camera().wy")) == (cx, cy)
    wow.execute(f"{MAP_}.toolbar.follow:Click()")
    assert wow.eval(f"{FOCUS}.IsFollowing()") is True
    assert wow.eval(f"{MOD}.db.profile.follow") is True
    wow.execute(f"{BR}.Browser.Open('npc:240')")
    wow.execute(f"{BR}.Browser.Open('npc:448')")
    hx, hy = wow.eval("Bastians.Coords.ToWorld(1429, 0.27, 0.86)")[1:3]
    assert (
        round(wow.eval(f"{MAP_}.Camera().wx")),
        round(wow.eval(f"{MAP_}.Camera().wy")),
    ) == (round(hx), round(hy))
    assert wow.eval(f"{MOD}.Waypoints.Get().label") == "Hogger"
    # a page without a place does not move the map; off again, nothing follows
    wow.execute(f"{BR}.Browser.Open('item:2589')")
    assert round(wow.eval(f"{MAP_}.Camera().wx")) == round(hx)
    wow.execute(f"{MAP_}.toolbar.follow:Click()")
    wow.execute(f"{BR}.Browser.Open('npc:240')")
    assert round(wow.eval(f"{MAP_}.Camera().wx")) == round(hx)
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
    # the Browser's button undocks; the map's full screen undocks too
    wow.execute(f"{BR}.toolbar.dock:Click()")
    assert wow.eval("Bastians.UI.IsDocked()") is False
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
    boot(wow, CORE, DATA, "Spoken", "Spoken_Quests", QUESTS, BROWSER, MAP, ROUTE)
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
