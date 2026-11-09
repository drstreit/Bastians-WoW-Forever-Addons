"""The developer probe's `/bprobe minimaps` (ADR 0056, PA6): a zone drawn small from a map style's
cells. On the mock it must cut the cells to the zone by texture coordinates, cover the picture
without a gap, count what it drew and record the frames; what it looks like and what it costs is
for the client."""

import sys
from pathlib import Path

from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from mapstyle.emit import style_lua
from test_overview import boot

RESULT = "BastiansProbeDB.results.minimaps"
# the mock places Elwynn (1429) around the world's origin, 400 yards a side: the four far
# cells and the four near cells that meet there
FAR = {0: [(3, 3), (3, 4), (4, 3), (4, 4)]}
NEAR = {0: [(7, 7), (7, 8), (8, 7), (8, 8)]}


def register(wow: WowRuntime, style: str = "pencil") -> None:
    wow.execute(style_lua(style, wow.client, "test", NEAR, FAR))
    wow.execute("Bastians.Deliver()")


def run(wow: WowRuntime, arg: str = "") -> None:
    wow.slash(f"/bprobe minimaps {arg}".strip())
    wow.run_frames(5, dt=0.5)  # the frames before
    wow.run_frames(5, dt=0.5)  # the frames with the window


def test_the_probe_draws_a_zone_from_the_styles_cells(wow: WowRuntime):
    boot(wow, tiles=True)
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    register(wow, "pencil")
    run(wow, "1429 pencil")
    out = wow.eval(RESULT)
    assert out is not None, list(wow.eval("Mock.chat").values())[-3:]
    assert (out.map, out.style) == (1429, "pencil")
    variants = {v.name: v for v in out.variants.values()}
    assert set(variants) == {
        f"{part}, {size}"
        for part in ("far", "far trilinear", "near", "near trilinear")
        for size in ("large", "medium", "tile")
    }
    large = variants["far, large"]
    assert large.textures == 4 and large.missing == 0  # the zone lies on the corner of four cells
    assert variants["near, large"].textures == 4
    assert out.before.frames > 0 and out.after.frames > 0
    assert out.many.zones >= 1 and out.many.textures >= out.many.zones
    # the far picture of the zone: the cells' cuts tile the rectangle (250 by 167 at 10, 30)
    wow.execute(
        """
        PROBE_AREA, PROBE_BAD = 0, 0
        local win = BastiansProbeMinimaps
        for i = 1, win.usedTextures do
          local t = win.textures[i]
          local _, _, _, x, y = t:GetPoint(1)
          local w, h = t:GetSize()
          if y == -30 or (y < -30 and y > -197 and x >= 10 and x < 260) then
            if x >= 10 and x + w <= 260.01 and -y + h <= 197.01 then
              PROBE_AREA = PROBE_AREA + w * h
              local u1, u2, v1, v2 = t:GetTexCoord()
              if not (u1 >= 0 and u2 <= 1 and u1 < u2 and v1 >= 0 and v2 <= 1 and v1 < v2) then
                PROBE_BAD = PROBE_BAD + 1
              end
            end
          end
        end
        """
    )
    assert wow.eval("PROBE_BAD") == 0
    assert wow.eval("#BastiansProbeDB.results.minimapRuns") == 1  # every run is kept
    assert abs(wow.eval("PROBE_AREA") - 250 * 167) < 1  # no gap, no overlap
    assert wow.errors == []


def test_the_probe_says_what_is_missing(wow: WowRuntime):
    boot(wow, tiles=True)
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    run(wow, "1429")  # no style of Bastian's is registered
    assert wow.eval(RESULT) is None
    assert any("no map style" in line for line in wow.eval("Mock.chat").values())
    register(wow, "pencil")
    run(wow, "99999")  # a map the client cannot place
    assert wow.eval(RESULT) is None
    assert wow.errors == []
