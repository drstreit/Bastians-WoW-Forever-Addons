"""Timers on Bastian's minimap: stopwatches and
countdowns, as many as wanted, named, kept across a reload; a countdown that ends says so in the
chat, plays the raid warning and lights the tools button until the window is opened."""

import pytest
from harness import WowRuntime
from test_mini import MINI, MOD, boot

T = f"{MOD}.Timers"


@pytest.mark.parametrize(
    ("text", "seconds"),
    [
        ("5m", 300),
        ("1:30", 90),
        ("90", 90),
        ("90s", 90),
        ("2h", 7200),
        ("1h 20m", 4800),
        ("1:02:03", 3723),
        ("1.5m", 90),
        ("", None),
        ("soon", None),
        ("1:2:3:4", None),
        ("0", None),
    ],
)
def test_the_model_reads_a_duration(wow: WowRuntime, text: str, seconds: int | None):
    boot(wow)
    assert wow.eval(f"{T}.Model.Parse('{text}')") == seconds


def test_the_model_formats_runs_pauses_and_rings(wow: WowRuntime):
    boot(wow)
    m = f"{T}.Model"
    assert wow.eval(f"{m}.Format(7)") == "0:07"
    assert wow.eval(f"{m}.Format(754)") == "12:34"
    assert wow.eval(f"{m}.Format(3723)") == "1:02:03"
    wow.execute(f"ST = {{ list = {{}}, nextID = 1 }}; W = {m}.Add(ST, 'watch', 'Run', nil)")
    wow.execute(f"{m}.Start(W, 100)")
    assert wow.eval(f"{m}.Elapsed(W, 130)") == 30 and wow.eval(f"{m}.Left(W, 130)") is None
    wow.execute(f"{m}.Pause(W, 130); {m}.Start(W, 200)")
    assert wow.eval(f"{m}.Elapsed(W, 210)") == 40  # the pause does not count
    wow.execute(f"D = {m}.Add(ST, 'down', 'Rest', 60); {m}.Start(D, 0)")
    assert wow.eval(f"{m}.Left(D, 45)") == 15 and wow.eval(f"{m}.Due(D, 45)") is False
    assert wow.eval(f"{m}.Due(D, 61)") is True and wow.eval(f"{m}.Left(D, 61)") == 0
    wow.execute(f"{m}.Ring(D)")
    assert wow.eval("D.rang") is True and wow.eval("D.startedAt") is None
    wow.execute(f"{m}.Start(D, 100)")  # again from the top
    assert wow.eval("D.rang") is None and wow.eval(f"{m}.Left(D, 110)") == 50
    assert wow.eval(f"{m}.DefaultName(ST, 'down')") == "Countdown 2"
    assert wow.eval(f"{m}.Remove(ST, 1)") is True and wow.eval("#ST.list") == 1
    assert wow.errors == []


def test_a_countdown_rings_in_the_chat_with_the_alarm_and_lights_the_button(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{MINI}.tools.timers ~= nil") is True
    wow.execute(f"T1 = {T}.Add('down', 'Rest', '2s')")
    assert wow.eval("T1.kind") == "down" and wow.eval("T1.total") == 2
    assert wow.eval(f"{T}.Model.Running(T1)") is True
    assert wow.eval(f"{MINI}.tools.timers.glow:IsShown()") is False
    wow.advance(1)
    assert not any("is up" in line for line in wow.eval("Mock.chat").values())
    wow.advance(1.2)
    assert any("Rest is up." in line for line in wow.eval("Mock.chat").values())
    assert 8959 in list(wow.eval("Mock.kits").values())
    assert wow.eval("T1.rang") is True
    assert wow.eval(f"{MINI}.tools.timers.glow:IsShown()") is True
    # the tools button's tip names it
    assert wow.eval(f"select(2, {MINI}.tools.timers.tip())") == "Rest: Done"
    # opening the window takes the light off
    wow.execute(f"{MINI}.tools.timers:Click()")
    assert wow.eval(f"{T}.Window():IsShown()") is True
    assert wow.eval(f"{MINI}.tools.timers.glow:IsShown()") is False
    rows = [r for r in wow.eval(f"{T}.rows").values() if r.IsShown(r)]
    assert len(rows) == 1 and rows[0].time.GetText(rows[0].time) == "Done"
    # a bad duration is refused with a word in the chat
    assert wow.eval(f"{T}.Add('down', 'x', 'soon')") is None
    assert any("could not read that time" in line for line in wow.eval("Mock.chat").values())
    wow.execute(f"{MINI}.tools.timers:Click()")
    assert wow.eval(f"{T}.Window():IsShown()") is False
    assert wow.errors == []


def test_the_window_adds_pauses_resets_and_removes(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{T}.Open()")
    win = f"{T}.Window()"
    assert wow.eval(f"{win}.empty:IsShown()") is True
    wow.execute(f"{win}.adder.name:SetText('Lap'); {win}.adder.watch:Click()")
    assert wow.eval(f"{win}.empty:IsShown()") is False
    assert wow.eval(f"{win}.adder.name:GetText()") == ""
    row = f"{T}.rows[1]"
    assert wow.eval(f"{row}.name:GetText()") == "Lap"
    wow.advance(2)
    wow.run_frames(15)  # the window ticks while it shows (every 0.2 s)
    assert wow.eval(f"{row}.time:GetText()") == "0:02"
    wow.execute(f"{row}.toggle:Click()")  # pause
    wow.advance(5)
    wow.run_frames(15)
    assert wow.eval(f"{row}.time:GetText()") == "0:02"
    assert wow.eval(f"{row}.toggle.spec.icon") == "play"
    wow.execute(f"{row}.reset:Click()")
    assert wow.eval(f"{row}.time:GetText()") == "0:00"
    # a countdown from the adding line, Enter in the duration box adds it
    wow.execute(f"{win}.adder.how:SetText('5m'); {win}.adder.name:SetText('Rested')")
    wow.execute(f"local b = {win}.adder.how; b:GetScript('OnEnterPressed')(b)")
    assert wow.eval(f"#{MOD}.db.profile.timers.list") == 2
    assert wow.eval(f"{T}.rows[2].time:GetText()") == "5:00"
    lines = list(wow.eval(f"{T}.Lines()").values())
    assert lines == ["Rested: 5:00 left"]  # the paused stopwatch is not running
    # a name typed in the row is kept
    wow.execute(
        f"local b = {T}.rows[2].name; b:SetText('Food'); b:GetScript('OnTextChanged')(b, true)"
    )
    assert wow.eval(f"{MOD}.db.profile.timers.list[2].name") == "Food"
    wow.execute(f"{T}.rows[1].remove:Click()")
    assert wow.eval(f"#{MOD}.db.profile.timers.list") == 1
    assert wow.eval(f"{T}.rows[1].name:GetText()") == "Food"
    # nothing ticks once the window is closed
    wow.execute(f"{win}:Hide()")
    assert wow.eval(f"{win}.frame:GetScript('OnUpdate')") is None
    assert wow.errors == []


def test_a_running_countdown_survives_a_reload_and_rings_on_time(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{T}.Add('down', 'Bread', '3s')")
    wow.advance(1)
    # the module goes down and up: the kept list is re-armed
    wow.execute(f"{MOD}:Disable()")
    wow.execute(f"{MOD}:Enable()")
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.run_frames(3)
    assert not any("Bread is up." in line for line in wow.eval("Mock.chat").values())
    wow.advance(2.2)
    assert any("Bread is up." in line for line in wow.eval("Mock.chat").values())
    assert wow.errors == []
