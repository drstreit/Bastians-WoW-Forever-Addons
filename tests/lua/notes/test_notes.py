"""Bastian's Notes, stage N1 (notes.md): the model (pure), the editor, the page and tooltip section,
the actions, spot notes on the map, the search, both reminders, the Lists window, and life without
the Map."""

from harness import WowRuntime

CORE, DATA, MAP, NOTES = "Bastians_Core", "Bastians_Data", "Bastians_Map", "Bastians_Notes"
MOD = "Bastians:GetModule('Notes')"
N = f"{MOD}.Notes"
M = f"{MOD}.Model"
ED = "Bastians:GetModule('Notes').Editor"


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*(addons or (CORE, DATA, MAP, NOTES)))
    wow.run_frames(5)
    return wow


def logged_errors(wow: WowRuntime) -> list:
    return [line.text for line in wow.eval("Bastians:GetLog()").values() if line.level == "error"]


def test_the_model_keeps_moves_finds_and_removes(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""G = {M}.Ensure({{}})
        A = {M}.Save(G, {{ on = 'npc:240', title = '  Gives Hogger ', text = 'bring friends',
          colour = 'note3', symbol = 'quest', remind = 'target' }}, 'my', 100)
        B = {M}.Save(G, {{ on = {{ map = 0, wx = -9460, wy = 60 }}, title = 'Peacebloom' }}, 'my', 200)"""
    )
    a = wow.eval("A")
    assert (a.title, a.colour, a.symbol, a.share, a.remind) == (
        "Gives Hogger",
        "note3",
        "quest",
        "private",
        "target",
    )
    b = wow.eval("B")
    assert (b.symbol, b.colour, b.remind) == ("spot", "note1", None)  # defaults for a spot
    assert wow.eval(f"{M}.Save(G, {{ on = 'npc:240', title = '  ' }}, 'my', 1)") == (None, "title")
    assert wow.eval(f"{M}.Save(G, {{ on = 'nothing', title = 'x' }}, 'my', 1)") == (None, "place")
    assert [n.title for n in wow.eval(f"{M}.On(G, 'npc:240')").values()] == ["Gives Hogger"]
    # a new list; the spot note moves there; hidden lists keep their spots off the map
    wow.execute(
        f"L1 = {M}.NewList(G, 'Herbs'); {M}.Save(G, {{ id = B.id, on = B.on, title = B.title }}, L1.id, 300)"
    )
    assert wow.eval("G.lists.my.notes[B.id]") is None and wow.eval("L1.notes[B.id] ~= nil") is True
    assert len(wow.eval(f"{M}.Spots(G, 0)")) == 1
    wow.execute("L1.hidden = true")
    assert len(wow.eval(f"{M}.Spots(G, 0)")) == 0 and len(wow.eval(f"{M}.Spots(G, 0, true)")) == 1
    # search by a word of the text; the title ranks higher
    hits = list(wow.eval(f"{M}.Search(G, 'friends')").values())
    assert [h.note.title for h in hits] == ["Gives Hogger"] and hits[0].score == 0.5
    assert wow.eval(f"{M}.Search(G, 'peace')")[1].score == 0.8
    # removing a list moves its notes home; "My notes" stays
    assert wow.eval(f"{M}.RemoveList(G, 'my')") is False
    assert wow.eval(f"{M}.RemoveList(G, L1.id)") is True and wow.eval(
        "G.lists.my.notes[B.id] ~= nil"
    )
    assert wow.eval(f"{M}.Remove(G, A.id)") is True and len(wow.eval(f"{M}.On(G, 'npc:240')")) == 0
    assert wow.errors == [] and logged_errors(wow) == []


def test_the_editor_keeps_a_note_that_shows_on_tooltip_and_page(wow: WowRuntime):
    boot(wow)
    wow.execute("Bastians:RunAction('notes.add', 'npc:240', { source = 'test' })")
    assert wow.eval(f"{ED}.IsShown()") is True
    wow.execute(
        f"""{ED}.title:SetText('Gives Hogger'); {ED}.body:SetText('bring friends')
        local b = {ED}.colourButtons.note4; b:GetScript('OnClick')(b)"""
    )
    note = wow.eval(f"{ED}.Keep()")
    assert note.title == "Gives Hogger" and note.colour == "note4" and note.symbol == "note"
    assert wow.eval(f"{ED}.IsShown()") is False
    rows = [
        r
        for s in wow.eval("Bastians:GetDetailSections('npc:240')").values()
        if s.id == "notes.mine"
        for r in s.rows.values()
    ]
    assert len(rows) == 1 and "Gives Hogger" in rows[0].text and rows[0].meta == "bring friends"
    tip = [r.text for r in wow.eval("Bastians:GetTooltipRows('npc:240')").values()]
    assert any("Gives Hogger" in t for t in tip)
    # a click on the row opens it again, Remove takes it away
    wow.execute(
        "for _, s in ipairs(Bastians:GetDetailSections('npc:240')) do "
        "if s.id == 'notes.mine' then s.rows[1].onClick() end end"
    )
    assert wow.eval(f"{ED}.state.fields.title") == "Gives Hogger"
    wow.execute(f"{ED}.RemoveShown()")
    assert len(wow.eval(f"{M}.On({N}.Global(), 'npc:240')")) == 0
    assert wow.errors == [] and logged_errors(wow) == []


def test_a_spot_note_is_a_map_pin_and_is_found(wow: WowRuntime):
    boot(wow)
    wow.execute(
        "Bastians:RunAction('notes.here', 'zone:1429', { source = 'map', point = { 0, -9460, 60 } })"
    )
    wow.execute(f"{ED}.title:SetText('Peacebloom'); {ED}.Keep()")
    view = "{ continent = 0, x1 = -50000, y1 = -50000, x2 = 50000, y2 = 50000, level = 3 }"
    pins = list(wow.eval(f"Bastians:QueryLayer('notes.spots', {view})").values())
    assert [p.label for p in pins] == ["Peacebloom"] and (pins[0].wx, pins[0].wy) == (-9460, 60)
    assert pins[0].color is not None and pins[0].card(pins[0]).hint == "Click to edit"
    wow.execute(
        """RESULTS = nil
        Bastians:Search('peace', { limit = 10 }, function(r, done) if done then RESULTS = r end end)"""
    )
    wow.run_frames(5)
    labels = [r.label for r in wow.eval("RESULTS").values()]
    assert "Peacebloom" in labels
    assert wow.errors == [] and logged_errors(wow) == []


def test_reminders_speak_once_near_and_on_target(wow: WowRuntime):
    boot(wow)
    here = wow.eval("{ Bastians.Coords.Player() }")
    wow.execute(
        f"""{N}.Save({{ on = {{ map = {here[1]}, wx = {here[2]} + 20, wy = {here[3]} }},
          title = 'Chest', text = 'behind the rock', remind = 'near' }})
        {N}.Save({{ on = 'npc:240', title = 'Marshal', remind = 'target' }})"""
    )
    assert wow.eval(f"{N}.ArmReminders()") is True  # a near note on this continent: the ticker runs
    before = len(wow.chat)
    wow.execute(f"{N}.CheckNear(); {N}.CheckNear()")
    said = [line for line in wow.chat[before:] if "Chest" in line]
    assert len(said) == 1 and "behind the rock" in said[0]
    wow.execute("Mock.guids = { target = 'Creature-0-1-0-1-240-0000000001' }")
    wow.fire("PLAYER_TARGET_CHANGED")
    assert any("Marshal" in line for line in wow.chat[-2:])
    # reminders off: no ticker
    wow.execute(f"{MOD}.db.profile.reminders = false")
    assert wow.eval(f"{N}.ArmReminders()") is False
    assert wow.errors == [] and logged_errors(wow) == []


def test_the_lists_window_and_the_slash_command(wow: WowRuntime):
    boot(wow)
    wow.slash("/bnotes add Mailbox here")
    assert any("Mailbox here" in line for line in wow.chat[-1:])
    wow.slash("/bnotes")
    rows = list(wow.eval(f"{MOD}.Lists.tree.rows").values())
    assert rows[0].text.startswith("My notes") and len(rows[0].children) == 1
    # hide the list from the map with its row button
    wow.execute(f"local r = {MOD}.Lists.tree.rows[1]; r.button.onClick(r)")
    assert wow.eval(f"{N}.Global().lists.my.hidden") is True
    assert wow.errors == [] and logged_errors(wow) == []


def test_the_lists_window_draws_every_note_row(wow: WowRuntime):
    """ "My notes (3)" showed one row with its symbol over the title. The
    rows carried the note as `note`, which the tree draws as a text column: SetText(table) stopped
    the tree at the first note row, before the title was placed right of the symbol."""
    boot(wow)
    for title in ("Anvil", "Bank", "Cook"):
        wow.slash(f"/bnotes add {title}")
    wow.slash("/bnotes")
    tree = f"{MOD}.Lists.tree"
    # the mock lays nothing out: give the view the size the window gives it in game
    wow.execute(f"{tree}.scroll:SetSize(380, 300); {tree}:Refresh()")
    shown = wow.eval(
        f"""(function()
          local out = {{}}
          for _, f in ipairs({tree}.pool) do
            if f:IsShown() and f.row then out[#out + 1] = f.text:GetText() end
          end
          return out
        end)()"""
    )
    texts = list(shown.values())
    assert texts[0].startswith("My notes") and "(3)" in texts[0]
    assert all(any(name in t for t in texts[1:]) for name in ("Anvil", "Bank", "Cook"))
    # the title starts right of the symbol, not under it
    left = wow.eval(f"(select(4, {tree}.pool[2].text:GetPoint(1)))")
    assert left == wow.eval(f"(select(4, {tree}.pool[2].icon:GetPoint(1)))") + 15
    assert wow.errors == [] and logged_errors(wow) == []


def test_without_the_map_notes_still_show_on_pages(wow: WowRuntime):
    boot(wow, CORE, DATA, NOTES)
    wow.execute(f"{N}.Save({{ on = 'npc:240', title = 'Alone' }})")
    rows = [
        r
        for s in wow.eval("Bastians:GetDetailSections('npc:240')").values()
        if s.id == "notes.mine"
        for r in s.rows.values()
    ]
    assert len(rows) == 1
    assert wow.errors == [] and logged_errors(wow) == []


def test_a_note_shows_on_every_page_it_can_be_added_on(wow: WowRuntime):
    """a note added on a dungeon's page was nowhere to see."""
    boot(wow)
    for ref in ("dungeon:36", "recipe:2549", "area:87"):
        wow.execute(f"{N}.Save({{ on = '{ref}', title = 'Mine {ref}' }})")
        rows = [
            r
            for s in wow.eval(f"Bastians:GetDetailSections('{ref}')").values()
            if s.id == "notes.mine"
            for r in s.rows.values()
        ]
        assert len(rows) == 1 and f"Mine {ref}" in rows[0].text, ref
    assert wow.errors == [] and logged_errors(wow) == []


def test_with_notes_the_bookmarks_live_in_the_lists(wow: WowRuntime):
    """N2 (E): the map's own bookmarks move into the list "Bookmarks" once, new ones go there, the
    title is renamed through the bar, a hidden list takes its bookmarks off the bar, and the Lists
    window shows them under their list."""
    boot(wow)
    bar = "Bastians:GetModule('Map').LayerBar"
    wow.slash("/bmap")
    # a bookmark the map kept before Notes was installed
    wow.execute(
        "Bastians:GetModule('Map').db.global.bookmarks = "
        "{ { name = 'Old camp', continent = 0, wx = -9000, wy = 500, level = 4 } }"
    )
    marks = list(wow.eval(f"{bar}.Bookmarks()").values())
    assert [m.name for m in marks] == ["Old camp"] and marks[0].id is not None
    assert len(wow.eval("Bastians:GetModule('Map').db.global.bookmarks")) == 0  # handed over
    wow.execute(f"{bar}.AddBookmark('Hogger')")
    assert [m.name for m in wow.eval(f"{bar}.Bookmarks()").values()] == ["Old camp", "Hogger"]
    wow.execute(f"{bar}.RenameBookmark(2, 'Hogger camp')")
    assert wow.eval(f"{bar}.Bookmarks()[2].name") == "Hogger camp"
    g = f"{N}.Global()"
    assert wow.eval(f"{g}.lists.bookmarks ~= nil") is True
    # the Lists window lists them under "Bookmarks"
    wow.slash("/bnotes")
    rows = list(wow.eval(f"{MOD}.Lists.tree.rows").values())
    books = next(r for r in rows if r.text.startswith("Bookmarks"))
    assert [c.text for c in books.children.values()] == ["Old camp", "Hogger camp"]
    # hidden: off the bar too
    wow.execute(f"{g}.lists.bookmarks.hidden = true")
    assert len(wow.eval(f"{bar}.Bookmarks()")) == 0
    wow.execute(f"{g}.lists.bookmarks.hidden = nil; {bar}.RemoveBookmark(1)")
    assert [m.name for m in wow.eval(f"{bar}.Bookmarks()").values()] == ["Hogger camp"]
    assert wow.errors == [] and logged_errors(wow) == []


SHARE = f"{MOD}.Share"


def seed_list(wow: WowRuntime) -> None:
    wow.execute(
        f"""G = {N}.Global(); L1 = {M}.NewList(G, 'Herbs')
        {M}.Save(G, {{ on = {{ map = 0, wx = -9460, wy = 60 }}, title = 'Peacebloom',
          share = 'shareable', colour = 'note2' }}, L1.id, 1)
        {M}.Save(G, {{ on = 'npc:240', title = 'Secret', share = 'private' }}, L1.id, 2)
        {M}.AddBookmark(G, {{ name = 'Goldshire', continent = 0, wx = -9460, wy = 60 }}, 3)
        G.lists.bookmarks.notes = G.lists.bookmarks.notes or {{}}
        L1.bookmarks = G.lists.bookmarks.bookmarks; G.lists.bookmarks = nil"""
    )


def test_a_shared_list_carries_its_shareable_notes_and_asks_the_receiver(wow: WowRuntime):
    """N3 (F, G, I): the private note stays home; the party gets the list in parts; on the other
    side nothing is kept before Accept, which makes a list with the sender's name kept locally."""
    boot(wow)
    seed_list(wow)
    offer, private = wow.eval(f"{N}.Payload(L1.id)")
    assert [n.title for n in offer.notes.values()] == ["Peacebloom"] and private == 1
    assert [b.name for b in offer.bookmarks.values()] == ["Goldshire"]
    assert wow.eval(f"{N}.Share(L1.id, 'PARTY')") is True
    wow.advance(2)
    sent = list(wow.eval("Mock.addonMessages").values())
    assert sent and all(m.channel == "PARTY" for m in sent)
    assert any("1 private notes stayed here" in line for line in wow.chat)
    # a friend's copy of the same messages arrives: the dialog asks, nothing is kept yet
    before = len(wow.eval(f"{M}.Lists({N}.Global())"))
    wow.execute(
        "for _, m in ipairs(Mock.addonMessages) do "
        "Bastians.Comm.Receive(m.prefix, m.text, 'PARTY', 'Friend-Realm') end"
    )
    assert wow.eval(f"{SHARE}.askWin:IsShown()") is True
    assert "Friend-Realm shares the list" in wow.eval(f"{SHARE}.askText:GetText()")
    assert len(wow.eval(f"{M}.Lists({N}.Global())")) == before
    wow.execute(f"{SHARE}.Answer(true)")
    lists = list(wow.eval(f"{M}.Lists({N}.Global())").values())
    got = next(x for x in lists if x["from"] == "Friend-Realm")
    notes = list(got.notes.values())
    assert [n.title for n in notes] == ["Peacebloom"] and notes[0].share == "private"
    assert [b.name for b in got.bookmarks.values()] == ["Goldshire"]
    assert wow.errors == [] and logged_errors(wow) == []


def test_the_text_form_imports_on_another_account_and_hostile_offers_are_cleaned(wow: WowRuntime):
    boot(wow)
    seed_list(wow)
    text = wow.eval(f"{N}.ExportText(L1.id)")
    assert text.startswith("!BN1!")
    wow.execute(f"{SHARE}.OpenImport(); {SHARE}.importBox:SetText({text!r})")
    assert wow.eval(f"{SHARE}.Read()") is True
    assert "a pasted text shares" in wow.eval(f"{SHARE}.askText:GetText()")
    wow.execute(f"{SHARE}.Answer(false)")  # declined: nothing kept
    assert not any(x["from"] for x in wow.eval(f"{M}.Lists({N}.Global())").values())
    # a hostile offer: wrong fields dropped, lengths cut, nothing that is not ours
    wow.execute(
        f"""CLEAN, WHY = {M}.CleanOffer({{ v = 1, name = string.rep('x', 300),
          notes = {{ {{ title = 'ok', on = 'npc:1' }}, {{ title = 'bad on', on = 'loadstring(x)' }},
            {{ title = '', on = 'npc:2' }}, {{ title = 'spot', on = {{ map = 0, wx = 1, wy = 2 }},
            text = string.rep('t', 900), colour = 'red', run = 'os.exit()' }} }},
          bookmarks = {{ {{ name = 'b', continent = 0, wx = 1, wy = 'x' }} }} }})"""
    )
    clean = wow.eval("CLEAN")
    assert len(clean.name) == 60 and [n.title for n in clean.notes.values()] == ["ok", "spot"]
    spot = clean.notes[2]
    assert len(spot.text) == 500 and spot.colour is None and spot.run is None
    assert len(clean.bookmarks) == 0
    assert wow.eval(f"{M}.CleanOffer({{ v = 2, name = 'x' }})") == (None, "version")
    assert wow.eval(f"{M}.CleanOffer({{ v = 1, name = 'x', notes = {{}} }})") == (None, "empty")
    assert wow.eval(f"{N}.ImportText('nonsense')") == (None, "not a Bastian's text")
    assert wow.errors == [] and logged_errors(wow) == []


def test_a_place_goes_to_the_group_and_comes_back_as_a_pin(wow: WowRuntime):
    """N4 (R26.9): alone nothing is sent; in a party a map spot or a thing's place goes to PARTY;
    a friend's place is a pin on "From my group" for half an hour, kept in memory only."""
    boot(wow)
    point = "{ source = 'map', point = { 0, -9460, 60 } }"
    assert wow.eval(f"Bastians:GetActions('zone:1429', {point})") is not None
    actions = [a.id for a in wow.eval(f"Bastians:GetActions('zone:1429', {point})").values()]
    assert "notes.sendhere" not in actions  # alone: no group to send to
    wow.execute("Mock.groupSize = 2; Mock.unitNames = { party1 = 'Friend' }")
    wow.execute(f"Bastians:RunAction('notes.sendhere', 'zone:1429', {point})")
    wow.advance(1)
    sent = list(wow.eval("Mock.addonMessages").values())
    assert sent and sent[-1].channel == "PARTY" and "notes.pin" in sent[-1].text
    # the friend's copy arrives: a pin and a chat line
    wow.execute(
        "local m = Mock.addonMessages[#Mock.addonMessages]; "
        "Bastians.Comm.Receive(m.prefix, m.text, 'PARTY', 'Friend-Realm')"
    )
    assert any("Friend-Realm:" in line for line in wow.chat[-2:])
    view = "{ continent = 0, x1 = -50000, y1 = -50000, x2 = 50000, y2 = 50000, level = 3 }"
    pins = list(wow.eval(f"Bastians:QueryLayer('notes.shared', {view})").values())
    assert len(pins) == 1 and (pins[0].wx, pins[0].wy) == (-9460, 60)
    assert "From Friend-Realm" in pins[0].card(pins[0]).lines[1].text
    assert wow.eval(f"{MOD}.db.global.shared") is None  # nothing saved
    wow.advance(31 * 60)
    assert len(wow.eval(f"Bastians:QueryLayer('notes.shared', {view})")) == 0
    # a hostile pin is no pin
    assert (
        wow.eval(f"{M}.CleanPin({{ v = 1, name = 'x', continent = 0, wx = 'a', wy = 1 }})") is None
    )
    assert wow.errors == [] and logged_errors(wow) == []


def test_route_to_a_member_of_the_group(wow: WowRuntime):
    wow.start(CORE, DATA, MAP, "Bastians_Route", NOTES)
    wow.run_frames(5)
    wow.slash("/broute member Friend")
    assert "No member of your group called Friend." in wow.chat[-1]
    wow.execute(
        "Mock.groupSize = 2; Mock.unitNames = { party1 = 'Friend' }; "
        "Mock.unitMaps = { party1 = { map = 1429, x = 0.45, y = 0.6 } }"
    )
    wow.slash("/broute member friend")
    route = wow.eval("Bastians:GetModule('Route').Route.Active()")
    assert route is not None and route.goal.name == "Friend"
    assert wow.errors == [] and logged_errors(wow) == []


def test_a_saved_bookmarks_list_without_notes_is_repaired(wow: WowRuntime):
    """a bookmarks list saved by an earlier build had only `bookmarks`;
    the reminder scan failed on it ('bad argument #1 to pairs'). Ensure gives every list its notes."""
    boot(wow)
    wow.execute(
        f"""G = {M}.Ensure({{ nextId = 2, lists = {{ my = {{ id = 'my', notes = {{}} }},
          bookmarks = {{ id = 'bookmarks', bookmarks = {{ b1 = {{ id = 'b1', name = 'Pier' }} }} }},
          old = {{ name = 'Old list' }} }} }})"""
    )
    assert wow.eval("type(G.lists.bookmarks.notes)") == "table"
    assert wow.eval("G.lists.old.id") == "old" and wow.eval("type(G.lists.old.notes)") == "table"
    assert wow.eval("G.lists.bookmarks.bookmarks.b1.name") == "Pier"  # the bookmarks are kept
    assert wow.eval(f"#{M}.Reminders(G)") == 0
    assert wow.errors == []
