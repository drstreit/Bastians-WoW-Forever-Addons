"""Words: the suite's own words
(a notice, a reminder, a route step, an arrival) go to text, to the voice or to both, as the
General page says per kind; the voice is the `voice` service the Orbiter provides; without it
voice falls back to text; the Wanderer preset hears, the Scholar reads."""

from harness import WowRuntime

CORE, DATA, VOICE = "Bastians_Core", "Bastians_Data", "Bastians_Voice"
P = "Bastians:GetModule('Core').db.profile"


def tab(wow: WowRuntime) -> list[str]:
    lines = wow.eval("Mock.chatTabs['Addons']")
    return [str(x) for x in lines.values()] if lines is not None else []


def test_without_a_voice_every_kind_is_text(wow: WowRuntime):
    wow.start(CORE)
    wow.run_frames(5)
    wow.execute("Mock.AddChatTab(2, 'Addons')")
    wow.execute(f"{P}.wordsNotice = 'voice'")
    assert wow.eval("Bastians:Tell(Bastians:GetModule('Core'), 'notice', 'Sold 3 items')") is False
    assert any("Sold 3 items" in line for line in tab(wow))  # the text form, no voice to speak
    shown = []
    wow.execute("Bastians.__shown = {}")
    wow.execute(
        "Bastians:Tell(Bastians:GetModule('Core'), 'arrival', 'You are there', function(t) "
        "Bastians.__shown[#Bastians.__shown + 1] = t end)"
    )
    shown = list(wow.eval("Bastians.__shown").values())
    assert shown == ["You are there"]  # the app's own text form is used when given
    assert wow.errors == []


def test_the_orbiter_speaks_what_the_setting_sends_to_the_voice(wow: WowRuntime):
    wow.start(CORE, DATA, VOICE)
    wow.run_frames(5)
    wow.execute("Mock.AddChatTab(2, 'Addons')")
    assert wow.eval("Bastians:GetService('voice') ~= nil") is True
    # text: nothing spoken
    wow.execute(
        "Bastians:Tell(Bastians:GetModule('Core'), 'reminder', 'Marshal Dughan. Ask about the mine')"
    )
    assert wow.eval("#Mock.tts") == 0
    # voice: spoken, not shown
    wow.execute(f"{P}.wordsReminder = 'voice'")
    before = len(tab(wow))
    assert (
        wow.eval(
            "Bastians:Tell(Bastians:GetModule('Core'), 'reminder', 'Marshal Dughan. Ask about the mine')"
        )
        is True
    )
    assert wow.eval("Mock.tts[1].text") == "Marshal Dughan. Ask about the mine"
    assert len(tab(wow)) == before
    # both: spoken and shown
    wow.execute(f"{P}.wordsReminder = 'both'")
    wow.execute("Bastians:Tell(Bastians:GetModule('Core'), 'reminder', 'Both ways')")
    assert wow.eval("Mock.tts[2].text") == "Both ways"
    assert any("Both ways" in line for line in tab(wow))
    # the Orbiter's own switch off: back to text
    wow.execute("Bastians:GetModule('Voice').db.profile.tts = false")
    wow.execute(f"{P}.wordsReminder = 'voice'")
    assert wow.eval("Bastians:Tell(Bastians:GetModule('Core'), 'reminder', 'Quiet now')") is False
    assert wow.eval("#Mock.tts") == 2
    assert any("Quiet now" in line for line in tab(wow))
    # the Orbiter switched off: the service is gone, text again
    wow.execute("Bastians:GetModule('Voice').db.profile.tts = true")
    wow.execute("Bastians:GetModule('Voice'):Disable()")
    assert wow.eval("Bastians:GetService('voice')") is None
    assert wow.errors == []


def test_the_wanderer_hears_and_the_scholar_reads(wow: WowRuntime):
    wow.start(CORE, DATA, VOICE)
    wow.run_frames(5)
    wow.execute("Bastians.UI.Settings.ApplyPlay('wanderer')")
    p = wow.eval(P)
    assert p.wordsReminder == "voice" and p.wordsStep == "voice" and p.wordsArrival == "voice"
    assert p.wordsNotice == "text"
    wow.execute("Bastians.UI.Settings.ApplyPlay('scholar')")
    p = wow.eval(P)
    assert p.wordsReminder == "text" and p.wordsArrival == "text"
    # the four selects are on the General page
    wow.execute("Bastians.UI.Hub.Open('Core')")
    labels = []
    for w in wow.eval("Bastians.UI.Hub.canvas.widgets").values():
        if w.label is not None:
            labels.append(str(w.label.GetText(w.label)))
    assert any(t.startswith("Words") for t in labels)
    assert any(t.startswith("Arrivals") for t in labels)
    assert wow.errors == []
