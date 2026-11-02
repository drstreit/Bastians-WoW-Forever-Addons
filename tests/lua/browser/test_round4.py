"""Bastian's Browser, the owner's round 4 (retail, 31.10.2026 night; docs/plan-round4.md C and D1):
the filter bar laid out again at the pane's width with the rows under its real height, the Mobs
list's search by its data type and keep rule, the hover preview only with Shift, one row per zone
name, a note saved on the shown page shown at once."""

from harness import WowRuntime
from pages import page_rows
from test_filters import BR, boot, flat, open_list

MOD = "Bastians:GetModule('Browser')"


def test_the_filter_bar_lays_out_again_at_the_panes_width(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    bar = f"{MOD}.tree.filterBar"
    assert wow.eval(f"{bar}.laidOutAt") is not None
    # the bar's frame grows: a frame later the pills are laid out at the new width
    wow.execute(
        f"{bar}.frame:SetWidth(900) {bar}.frame:GetScript('OnSizeChanged')({bar}.frame, 900)"
    )
    wow.advance(0.01)
    wow.run_frames(3)
    assert wow.eval(f"{bar}.laidOutAt") == 900
    # the rows start under the bar: the chips frame is as high as the bar says
    assert wow.eval(f"{MOD}.tree.chips:GetHeight()") == wow.eval(f"{bar}:Height()")
    wow.execute(
        f"{bar}.frame:SetWidth(120) {bar}.frame:GetScript('OnSizeChanged')({bar}.frame, 120)"
    )
    wow.advance(0.01)
    wow.run_frames(3)
    assert wow.eval(f"{bar}:Height()") > 30  # more lines at 120 px
    assert wow.eval(f"{MOD}.tree.chips:GetHeight()") == wow.eval(f"{bar}:Height()")
    assert wow.errors == []


def test_the_mobs_search_finds_mobs_only(wow: WowRuntime):
    boot(wow)
    open_list(wow, "mob")
    word = flat(wow)[0].split(" ")[0].lower()  # the first mob's first word
    wow.execute(f"{MOD}.search:SetText({word!r})")
    wow.run_frames(30)
    wow.advance(0.5)
    wow.run_frames(30)
    rows = flat(wow)
    assert rows and all(word in r.lower() for r in rows), (word, rows)
    assert wow.eval(f"{BR}.HomeType()") == "npc"
    # the NPCs with a service stay out: the keep rule of the Mobs list
    d = "Bastians:GetService('data')"
    refs = [r.ref for r in wow.eval(f"{MOD}.tree.flat").values() if r.ref]
    for ref in refs:
        typ, rid = ref.split(":")
        assert wow.eval(f"{BR}.IsMob({d}:Get('{typ}', {rid}))") is True
    assert wow.errors == []


def test_the_preview_needs_shift(wow: WowRuntime):
    boot(wow)
    open_list(wow, "npc")
    row = wow.eval(f"{MOD}.tree.flat[1]")
    assert row.ref
    wow.execute(f"{BR}.OnRowHover({MOD}.tree.flat[1], true)")
    wow.advance(2)
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Previewing()") is None
    wow.execute(f"Mock.shift = true {BR}.OnRowHover({MOD}.tree.flat[1], true)")
    wow.advance(2)
    wow.run_frames(5)
    assert wow.eval(f"{BR}.Previewing()") == row.ref
    wow.execute("Mock.shift = nil")
    assert wow.errors == []


def test_a_zone_name_has_one_row(wow: WowRuntime):
    boot(wow)
    # a second zone of the first one's name under another parent with nothing of its own, as
    # retail holds Badlands (15 and 1245, measured 31.10.2026)
    wow.execute(
        """
        local d = Bastians:GetService('data')
        local firstId, firstRec
        for _, id in ipairs(d:Each('zone')) do
          local r = d:Get('zone', id)
          if r and r.name and r.mapType == 3 and (r.levelLo or r.questsA or r.questsH) then
            firstId, firstRec = id, r
            break
          end
        end
        Twin = { id = firstId, name = firstRec.name, rec = { name = firstRec.name, continent = firstRec.continent, mapType = 3, parent = 9999 } }
        local each, get = d.Each, d.Get
        d.Each = function(self, typ)
          local ids = each(self, typ)
          if typ == 'zone' then
            local out = { 999999 } -- the empty twin first: the richer one must still win
            for _, id in ipairs(ids) do out[#out + 1] = id end
            return out
          end
          return ids
        end
        d.Get = function(self, typ, id)
          if typ == 'zone' and id == 999999 then return Twin.rec end
          return get(self, typ, id)
        end
        """
    )
    open_list(wow, "zone")
    name = wow.eval("Twin.name")
    first = wow.eval("Twin.id")
    rows = [r for r in wow.eval(f"{MOD}.tree.flat").values() if r.ref]
    same = [r for r in rows if r.text.split("  ")[0] == name]
    assert len(same) == 1, [r.text for r in same]
    assert same[0].ref == f"zone:{first}"
    assert wow.errors == []


def test_a_note_saved_on_the_shown_page_shows_at_once(wow: WowRuntime):
    boot(wow, "Bastians_Core", "Bastians_Data", "Bastians_Browser", "Bastians_Notes")
    open_list(wow, "npc")
    ref = wow.eval(f"{MOD}.tree.flat[1].ref")
    wow.execute(f"{BR}.Open({ref!r})")
    wow.run_frames(10)
    before = page_rows(wow, f"{MOD}.dossier")
    assert not any("Remember this" in t for t in before)
    wow.execute(
        f"Bastians:GetModule('Notes').Notes.Save({{ title = 'Remember this', text = 'a note', on = {ref!r} }})"
    )
    wow.advance(0.01)
    wow.run_frames(10)
    after = page_rows(wow, f"{MOD}.dossier")
    assert any("Remember this" in t for t in after), after
    assert wow.errors == []
