"""The Alts window (alts.md "The window", "make this one window - the
alts are on the top, then a search, then one large window"): the characters as pills, a search
over everything they hold, the views as tabs, one wide list."""

from harness import WowRuntime
from test_alts import ALTS, CORE, DATA, ME, G, boot, strip, with_alts

W = "Bastians:GetModule('Alts').Window"


def flat(wow: WowRuntime) -> list:
    wow.execute(f"{W}.tree.scroll:SetSize(560, 360); {W}.tree:Refresh()")
    return list(wow.eval(f"{W}.tree.flat").values())


def pills(wow: WowRuntime) -> list[tuple[str, bool]]:
    return [
        (strip(p.spec.label), p.spec.on is True)
        for p in wow.eval(f"{W}.pills").values()
        if p.IsShown(p)
    ]


def test_the_window_shows_the_characters_on_top_and_the_chosen_ones_view(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    wow.slash("/balts")
    wow.run_frames(3)
    assert wow.eval("BastiansAltsFrame:IsShown()") is True
    # this character first and lit, the others of its realm by name
    assert pills(wow) == [("Mockchar", True), ("Bankalt", False), ("Orcalt", False)]
    assert wow.eval(f"{W}.pills[1].spec.count") == 12  # the level after the name
    assert wow.eval(f"{W}.Character()") == ME
    # the overview of this character by default, the tab lit
    tabs = {t.view: t.spec.on is True for t in wow.eval(f"{W}.tabs").values()}
    assert tabs == {
        "overview": True,
        "equipment": False,
        "bags": False,
        "bank": False,
        "mail": False,
        "requests": False,
    }
    texts = [strip(r.text) for r in flat(wow)]
    assert texts[0] == "Level" and "Money" in texts
    # another character's bags: a click on its pill, then the tab
    wow.execute(f"{W}.pills[2]:Click()")
    wow.execute(f"{W}.Open(nil, 'bags')")
    assert wow.eval(f"{W}.Character()") == "Bankalt-Mock Realm"
    assert pills(wow)[1] == ("Bankalt", True)
    got = [(strip(r.text), r.value) for r in flat(wow)]
    assert got == [("Blood Saber", 1), ("Linen Cloth", 40)]  # stacks summed, by name
    assert strip(wow.eval(f"{W}.summary:GetText()")).startswith("Bags")
    assert "2 rows" in strip(wow.eval(f"{W}.summary:GetText()"))
    # a place not read yet says so instead of showing nothing
    wow.execute(f"{W}.Open(nil, 'mail')")
    assert [strip(r.text) for r in flat(wow)] == [
        "The mailbox was not read yet: open one on this character."
    ]
    # the chosen character and view come back
    assert wow.eval("Bastians:GetModule('Alts').db.profile.character") == "Bankalt-Mock Realm"
    assert wow.eval("Bastians:GetModule('Alts').db.profile.view") == "mail"
    # the launcher's open toggles (7fce01a)
    wow.execute("Bastians:GetModule('Alts').def.open()")
    assert wow.eval("BastiansAltsFrame:IsShown()") is False
    wow.execute("Bastians:GetModule('Alts').def.open()")
    assert wow.eval("BastiansAltsFrame:IsShown()") is True
    assert wow.errors == []


def test_the_search_lists_what_every_character_holds(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    wow.slash("/balts")
    wow.run_frames(3)
    wow.execute(f"{W}.search:SetText('linen')")
    wow.execute(f"local b = {W}.search; b:GetScript('OnTextChanged')(b, true)")
    wow.advance(0.1)
    wow.run_frames(2)
    got = flat(wow)
    assert len(got) == 1 and got[0].ref == "item:2589" and got[0].value == 174  # 20 + 55 + 99
    words = strip(got[0].text)
    assert words.startswith("Linen Cloth  ")
    assert "Orcalt: bags 99" in words and "Bankalt: bags 40, bank 15" in words
    assert strip(wow.eval(f"{W}.summary:GetText()")) == "1 items on 3 characters"
    # the tabs step back while a search shows
    assert all(t.spec.on is not True for t in wow.eval(f"{W}.tabs").values())
    wow.execute(f"{W}.search:SetText('zzz')")
    wow.execute(f"local b = {W}.search; b:GetScript('OnTextChanged')(b, true)")
    wow.advance(0.1)
    wow.run_frames(2)
    assert [strip(r.text) for r in flat(wow)] == ["Nothing matches."]
    # clearing it brings the view back
    wow.execute(f"{W}.search.clear:Click()")
    wow.advance(0.1)
    wow.run_frames(2)
    assert strip(flat(wow)[0].text) == "Level"
    assert wow.errors == []


def test_a_second_realm_gets_its_name_before_its_characters(wow: WowRuntime):
    boot(wow)
    with_alts(wow)
    wow.execute(
        f"{G}.characters['Farling-Other Realm'] = {{ name = 'Farling', realm = 'Other Realm', level = 5 }}"
    )
    wow.execute("Bastians:Fire('BASTIANS_ALTS_CHANGED')")
    wow.slash("/balts")
    wow.run_frames(3)
    groups = [(g.realm, list(g.chars.values())) for g in wow.eval(f"{W}.Groups()").values()]
    assert groups[0][0] == "Mock Realm" and groups[0][1][0] == ME
    assert groups[1] == ("Other Realm", ["Farling-Other Realm"])
    labels = [
        strip(fs.GetText(fs)) for fs in wow.eval(f"{W}.realmLabels").values() if fs.IsShown(fs)
    ]
    assert labels == ["Mock Realm", "Other Realm"]
    # the pills flow into a second line when the window is narrow
    wow.execute("BastiansAltsFrame:SetWidth(240)")
    wow.execute(f"{W}.Render()")
    shown = [i for i, p in wow.eval(f"{W}.pills").items() if p.IsShown(p)]
    tops = {round(wow.eval(f"select(5, {W}.pills[{i}]:GetPoint(1))")) for i in shown}
    assert len(tops) >= 2  # the y offsets differ: more than one line
    assert wow.errors == []


def test_without_the_browser_the_window_still_lists_the_pages(wow: WowRuntime):
    boot(wow, CORE, DATA, ALTS)
    with_alts(wow)
    assert wow.eval("Bastians:GetModule('Alts').Alts.Open()") is True
    wow.run_frames(3)
    wow.execute(f"{W}.Open('Bankalt-Mock Realm', 'equipment')")
    assert [strip(r.text) for r in flat(wow)] == ["Blood Saber  Main hand"]
    assert wow.errors == []


def test_the_grip_sizes_a_never_moved_window_from_its_top_left(wow: WowRuntime):
    """ "when I click the scaling button bottom right on the alt window,
    the window jumps to a large size, then can be scaled": the window sat at the screen's centre
    (its profile kept no place); the grip anchors it at its top left before sizing, and the
    profile keeps the place."""
    boot(wow)
    wow.slash("/balts")
    wow.run_frames(3)
    assert wow.eval("(BastiansAltsFrame:GetPoint(1))") == "CENTER"
    wow.execute(f"local g = {W}.win.grip; g:GetScript('OnMouseDown')(g, 'LeftButton')")
    assert wow.eval("(BastiansAltsFrame:GetPoint(1))") == "TOPLEFT"
    wow.execute(f"local g = {W}.win.grip; g:GetScript('OnMouseUp')(g, 'LeftButton')")
    assert wow.eval("Bastians:GetModule('Alts').db.profile.window.size") is not None
    assert wow.errors == []
