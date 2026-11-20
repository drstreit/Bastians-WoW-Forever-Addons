"""Core's own cost (ADR 0082, plan-suite-waves.md W1): Core alone on the mock, its Lua heap after
loading. The one look moves the book's parts into Core (W4, W5) while the boundary rules want Core
lean, so the heap has a ceiling. Measured 17.11.2026 before the look moved in (PUC Lua 5.1, lupa):
2,429 KB after load, 2,509 KB after login and ten frames, the same on every run; the files load in
about 53 ms on the desktop (reported, not held: a time on a shared machine proves nothing). In the
game the figure is `/bastians perf` and tools/perf_report.py (nfr.md)."""

from harness import WowRuntime

BASELINE_KB = 2429  # 17.11.2026, before W4
CEILING_KB = 3000  # ADR 0082: the kit and the frame may add under a quarter


def heap_kb(wow: WowRuntime) -> float:
    wow.execute("collectgarbage('collect') collectgarbage('collect')")
    return float(wow.eval("collectgarbage('count')"))


def test_core_alone_stays_under_its_ceiling(wow: WowRuntime):
    before = heap_kb(wow)
    wow.load_addon("Bastians_Core")
    loaded = heap_kb(wow) - before
    wow.login()
    wow.run_frames(10)
    assert wow.errors == []
    print(f"Core alone: {loaded:.0f} KB after load, {heap_kb(wow) - before:.0f} KB after login")
    assert loaded < CEILING_KB, (
        f"Core alone takes {loaded:.0f} KB after load (baseline {BASELINE_KB}, ceiling "
        f"{CEILING_KB}): move what one app uses into that app, or change ADR 0082's number on purpose"
    )
    # a Core that shrank this far lost something: the baseline is then measured again
    assert loaded > BASELINE_KB * 0.5
