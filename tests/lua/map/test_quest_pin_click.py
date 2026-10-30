"""(R25.27): a click on a quest sign on the map (Isabel Jones's "?") gave
`Waypoints.lua:26: Entity: "nil" is not an entity reference`."""

from harness import WowRuntime

CORE, DATA, QUESTS, MAP, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
)
MAP_ = "Bastians:GetModule('Map').Map"
PINS = "Bastians:GetModule('Map').Pins"


def test_clicking_every_quest_sign_raises_nothing(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS, MAP, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    wow.execute(f"{MAP_}.Fly(0, -60, 32, 6)")
    wow.advance(0.3)
    frames = [f for f in wow.eval(f"{PINS}.pinPool").values() if f.IsShown(f)]
    assert frames
    for f in frames:
        for button in ("LeftButton", "RightButton"):
            f.GetScript(f, "OnClick")(f, button)
            f.GetScript(f, "OnEnter")(f)
            f.GetScript(f, "OnLeave")(f)
            wow.advance(0.2)
    assert wow.errors == []


def test_a_route_step_to_a_point_shows_on_the_map_without_an_entity(wow: WowRuntime):
    """The likely path of R25.27: a step to a spot ("Route here") has no entity."""
    wow.start(CORE, DATA, MAP)
    wow.run_frames(10)
    ctx = "{ source = 'route', point = { 0, 100, 120, 'Here' } }"
    assert wow.eval(f"Bastians:RunAction('map.show', nil, {ctx})") is not False
    cam = wow.eval(f"{MAP_}.Camera()")
    assert (cam.wx, cam.wy) == (100, 120)
    assert wow.eval("Bastians:GetModule('Map').Waypoints.Get().label") == "Here"
    assert wow.errors == []


def test_the_toolbar_offers_the_route_window_and_the_browser_when_they_are_there(wow: WowRuntime):
    """(R25.34, R25.35): coloured buttons with a symbol; Route and Browser
    one click away, shown only while those apps are there."""
    wow.start(CORE, DATA, MAP, BROWSER, "Bastians_Route")
    wow.run_frames(10)
    wow.slash("/bmap")
    bar = f"{MAP_}.toolbar"
    assert (
        wow.eval(f"{bar}.route:IsShown()") is True and wow.eval(f"{bar}.browser:IsShown()") is True
    )
    assert wow.eval(f"{bar}.player.icon ~= nil") is True  # a symbol on the button
    wow.execute(f"{bar}.browser:Click()")
    assert wow.eval("BastiansBrowserFrame:IsShown()") is True
    wow.execute(f"{bar}.route:Click()")
    assert wow.eval("Bastians:GetModule('Route').Window.IsShown()") is True
    wow.execute("Bastians:GetModule('Route'):Disable()")
    assert wow.eval(f"{bar}.route:IsShown()") is False  # the app went, its button too
    assert wow.eval("Bastians:OpenApp('Route')") is False
    assert wow.errors == []
