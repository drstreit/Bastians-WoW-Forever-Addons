"""The developer probe's resize recorder and `/bprobe booktech` (plan-book-round3.md R3.1 and
docs/addons/book-look.md section 8; the book "jumps to full screen when
starting to change the size").

The recorder arms every suite window's grip by itself and keeps, per drag, the frame before
StartSizing, right after it, at the first size changes, at mouse up and half a second later. On
the mock it must leave Core's own grip working, name a jump, and keep only the last drags. What
the real client does at the grip is for the client."""

from harness import WowRuntime

DRAGS = "BastiansProbeDB.results.resize.drags"


def arm(core: WowRuntime) -> None:
    core.execute(
        """
        rzDB = { pos = { 50, -60 }, size = { 300, 200 } }
        rz = Bastians.UI.Window("BastiansResizeProbeTest", { db = rzDB, width = 300, height = 200,
          maxWidth = Bastians.UI.NO_LIMIT, maxHeight = Bastians.UI.NO_LIMIT })
        rz:Show()
        """
    )
    core.load_addon("Bastians_Probe")
    core.fire("ADDON_LOADED", "Bastians_Probe")
    core.slash("/bprobe resize")


def drag(core: WowRuntime, sizes) -> None:
    core.execute("rz.grip:GetScript('OnMouseDown')(rz.grip)")
    for w, h in sizes:
        core.execute(f"rz.frame:SetSize({w}, {h}); rz.frame:GetScript('OnSizeChanged')(rz.frame)")
    core.execute("rz.grip:GetScript('OnMouseUp')(rz.grip)")
    core.advance(0.6)


def test_a_drag_is_recorded_and_the_grip_still_works(core: WowRuntime):
    arm(core)
    core.execute("rz.grip:GetScript('OnMouseDown')(rz.grip)")
    assert core.eval("rz:IsSizing()") is True  # Core's own handler ran under the probe's
    core.execute("rz.grip:GetScript('OnMouseUp')(rz.grip)")
    core.advance(0.6)
    # the width only: the mock has no layout, its GetTop follows the height
    drag(core, [(310, 200), (320, 200)])
    assert core.eval(f"#{DRAGS}") == 2
    d = f"{DRAGS}[2]"
    assert core.eval(f"{d}.window") == "BastiansResizeProbeTest"
    assert core.eval(f"{d}.before.width") == 300 and core.eval(f"{d}.before.height") == 200
    assert core.eval(f"{d}.before.points[1].point") == "TOPLEFT"
    assert core.eval(f"{d}.before.points[1].rel") == "UIParent"
    assert core.eval(f"{d}.after.sizing") is True
    assert core.eval(f"#{d}.sizes") == 2 and core.eval(f"{d}.sizes[2].width") == 320
    assert core.eval(f"{d}.up.width") == 320 and core.eval(f"{d}.settled.height") == 200
    assert core.eval(f"{d}.up.sizing") is False
    assert core.eval(f"{d}.bounds.ret[3]") == 100000  # as large as the player drags it
    assert core.eval(f"{d}.screen.width") == 1920
    assert core.eval(f"{d}.jump") is None  # ten px a step is no jump
    assert core.eval("rzDB.size[1]") == 320  # and the window saved its place as before
    # the whole drag: where the mouse was let go, the path, and Lua's own calls with their callers
    assert core.eval(f"{d}.release.width") == 320 and core.eval(f"{d}.release.sizing") is True
    assert core.eval(f"{d}.trail[1].width") == 310
    assert core.eval(f"{d}.steps") is None
    assert core.eval(f"{d}.calls[1].fn") == "SetSize" and core.eval(f"{d}.calls[1].args[1]") == 310
    assert core.eval(f"{d}.calls[1].phase") == "drag"


def test_a_jump_at_the_first_size_change_is_named(core: WowRuntime):
    arm(core)
    drag(core, [(1900, 1000), (1905, 1000)])
    d = f"{DRAGS}[1]"
    assert core.eval(f"{d}.jump.step") == "the first size change"
    assert core.eval(f"{d}.jump.grew") is True
    assert core.eval(f"{d}.jump.dw") == 1600 and core.eval(f"{d}.jump.dh") == 800


def test_a_step_the_cursor_does_not_explain_is_kept_with_the_state_before(core: WowRuntime):
    """The first drags in the game began smoothly and went wrong later (17.11.2026)."""
    arm(core)
    drag(core, [(310, 200), (320, 200), (900, 200), (905, 200)])
    d = f"{DRAGS}[1]"
    assert core.eval(f"{d}.jump") is None  # the start was smooth
    assert core.eval(f"#{d}.steps") == 1
    assert (
        core.eval(f"{d}.steps[1].from.width") == 320 and core.eval(f"{d}.steps[1].to.width") == 900
    )
    assert core.eval(f"{d}.steps[1].grew") is True


def test_only_the_last_drags_are_kept_and_a_window_is_armed_once(core: WowRuntime):
    arm(core)
    core.slash("/bprobe resize")  # a second arming wraps nothing twice
    for i in range(14):
        drag(core, [(300 + i, 200)])
    assert core.eval(f"#{DRAGS}") == 12
    assert core.eval(f"{DRAGS}[12].sizes[1].width") == 313
    assert core.eval(f"#{DRAGS}[12].sizes") == 1  # one hook, one record per size change
    core.slash("/bprobe resize clear")
    assert core.eval(f"#{DRAGS}") == 0


def test_booktech_records_each_call_and_takes_its_picture(core: WowRuntime):
    core.load_addon("Bastians_Probe")
    core.fire("ADDON_LOADED", "Bastians_Probe")
    core.slash("/bprobe booktech")
    core.advance(0.6)
    out = "BastiansProbeDB.results.booktech"
    assert core.eval(f"type({out}.rotation.set.ok)") == "boolean"
    assert core.eval(f"type({out}.gradient.set.ok)") == "boolean"
    assert core.eval(f"{out}.lineCreate ~= nil") is True
    assert core.eval(f"{out}.screenshot ~= nil") is True
