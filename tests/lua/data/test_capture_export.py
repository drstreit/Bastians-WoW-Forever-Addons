"""Copy my captures (catalog review B5, 07.11.2026; Data's Export.lua): the learned walks, flight
times, ride waits and (version 2, package QK1) quest step places as a text with a line count and
a checksum, the same lines
tools/capture_import.py reads; the window shows it selected for Ctrl+C and undoes a change;
nothing learned is a line in the chat, never an empty text."""

from harness import WowRuntime

EXPORT = "Bastians.Data.Export"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    return wow


def test_the_text_is_the_learned_table_line_by_line_with_its_checksum(wow: WowRuntime):
    boot(wow)
    text = wow.eval(
        f"""{EXPORT}.Text({{
          walk = {{ {{ map = 1429, len = 2140.46, at = 1762000000, points = {{ {{ 1000, -300.5 }}, {{ 600, 900 }}, {{ 100, -300 }} }} }},
                   {{ map = "x", points = {{}} }} }},
          taxi = {{ ["taxinode:2>taxinode:4"] = 95, ["taxinode:1>taxinode:2"] = 61.26, bad = "x" }},
          ride = {{ ["transport:176495"] = {{ 12, 30.5 }}, ["transport:1"] = {{}} }},
          steps = {{ ["1861:1"] = {{ {{ 1429, 0.2857, 0.6139 }}, {{ 1453, 0.5, 0.25 }}, {{ 1429, 0.3, 0.6 }}, "x" }},
                    ["176:2"] = {{ {{ 1429, 0.4, 0.7 }} }}, ["176:10"] = {{ {{ 1429, 1, 0 }} }},
                    ["1861:x"] = {{ {{ 1429, 0.1, 0.1 }} }}, ["9:1"] = {{}} }},
        }}, "forever", 70790, "2026-11-07T20:00:00Z")"""
    )
    lines = text.splitlines()
    assert lines[0] == "BASTIANS CAPTURE 2 forever 70790 2026-11-07T20:00:00Z"
    body = [
        "walk 1429 2140.5 1762000000 1000.0,-300.5;600.0,900.0;100.0,-300.0",
        "taxi taxinode:1>taxinode:2 61.3",
        "taxi taxinode:2>taxinode:4 95.0",
        "ride transport:176495 12.0,30.5",
        # by quest and objective number, one line per map; a key or a place that is none is left out
        "step 176 2 1429 0.4000,0.7000",
        "step 176 10 1429 1.0000,0.0000",
        "step 1861 1 1429 0.2857,0.6139;0.3000,0.6000",
        "step 1861 1 1453 0.5000,0.2500",
    ]
    assert lines[1:9] == body
    checksum = sum("\n".join(body).encode("utf-8")) % 65536  # tools/capture_import.checksum
    assert lines[9] == f"END 8 {checksum}" and text.endswith("\n")
    # step places alone are a text too
    only = wow.eval(
        f"{EXPORT}.Text({{ steps = {{ ['5:1'] = {{ {{ 1, 0.5, 0.5 }} }} }} }}, 'forever', 1, 'x')"
    )
    assert only.splitlines()[1] == "step 5 1 1 0.5000,0.5000"
    assert wow.eval(f'{EXPORT}.Sum("abc")') == 294
    # nothing learned: no text
    assert (
        wow.eval(f"{EXPORT}.Text({{ walk = {{}}, taxi = {{}}, ride = {{}} }}, 'forever', 1, 'x')")
        is None
    )
    assert wow.eval(f"{EXPORT}.Text(nil, 'forever', 1, 'x')") is None
    assert wow.errors == []


def test_the_window_shows_the_text_selected_and_the_hub_offers_it(wow: WowRuntime):
    boot(wow)
    # nothing learned yet: a line in the chat, no window
    assert wow.eval(f"{EXPORT}.Show()") is False
    assert any("Nothing learned yet" in m for m in wow.chat)
    assert wow.eval(f"{EXPORT}.Window()") is None
    wow.execute(
        "local g = Bastians:GetService('graph'); g:Learn({ kind = 'taxi', from = 2, to = 4, seconds = 95 })"
    )
    assert wow.eval(f"{EXPORT}.Show()") is True
    assert wow.eval(f"{EXPORT}.Window():IsShown()") is True
    text = wow.eval(f"{EXPORT}.Window().box:GetText()")
    assert (
        text.startswith("BASTIANS CAPTURE 2 forever ") and "taxi taxinode:2>taxinode:4 95.0" in text
    )
    # the box is read-only: a change puts the text back
    wow.execute(
        f"local b = {EXPORT}.Window().box; b:SetText('x'); b:GetScript('OnTextChanged')(b, true)"
    )
    assert wow.eval(f"{EXPORT}.Window().box:GetText()") == text
    wow.execute(f"local b = {EXPORT}.Window().box; b:GetScript('OnEscapePressed')(b)")
    assert wow.eval(f"{EXPORT}.Window():IsShown()") is False
    # the hub's Data page offers it as a button
    option = wow.eval(
        "(function() for _, o in ipairs(Bastians:GetModule('Data').options) do "
        "if o.type == 'execute' then return o end end end)()"
    )
    assert option is not None and option.label == "Copy my captures" and option.desc
    wow.execute(
        "local m = Bastians:GetModule('Data') for _, o in ipairs(m.options) do if o.type == 'execute' then o.func(m) end end"
    )
    assert wow.eval(f"{EXPORT}.Window():IsShown()") is True
    assert wow.errors == []
