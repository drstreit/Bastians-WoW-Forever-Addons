"""Helpers for tests that read an entity page: since C2 (ADR 0014) a page is a dossier, not a tree.

`page_rows` lists what the page shows the way the old section tree did (a section title, then its
rows, children flattened), so a test can keep asking "is Chain on the quest page"; `band` reads the
header band; `band_buttons` its labelled buttons; `block_rows` the rows one block draws now.
"""

import re

from harness import WowRuntime


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    text = re.sub(r"\|c[0-9a-fA-F]{8}", "", text)
    return text.replace("|r", "")


def _flatten(rows, out: list) -> None:
    for key, row in rows.items():
        if not isinstance(key, int):  # a rows table may carry `count` and the like
            continue
        out.append(row)
        if (
            row.children and not row.collapsed
        ):  # as the old tree listed a page (folded groups closed)
            _flatten(row.children, out)


def page_entries(wow: WowRuntime, dossier: str) -> list:
    """The page as the old flat tree: section rows (`kind = "section"`) and their rows, in order;
    the blocks first, then the links."""
    data = wow.eval(f"{dossier}.data")
    out: list = []
    if data is None:
        return out
    for block in list(data.blocks.values()) + list(data.links.values()):
        out.append({"text": block.title, "kind": "section", "id": block.id})
        rows: list = []
        _flatten(block.rows, rows)
        out.extend(rows)
    return out


def page_rows(wow: WowRuntime, dossier: str) -> list[str]:
    return [strip(e["text"] if isinstance(e, dict) else e.text) for e in page_entries(wow, dossier)]


def page_refs(wow: WowRuntime, dossier: str) -> list:
    """The rows with a ref, as Lua tables (status, ref, text ...)."""
    return [e for e in page_entries(wow, dossier) if not isinstance(e, dict) and e.ref]


def hosted_sheet(wow: WowRuntime, dossier: str) -> dict | None:
    """What a hosted sheet draws at the top of a page (ADR 0056, one quest sheet: a quest's page
    is Quests' own drawing), or None on a page with the kit's head: its words top down, its
    buttons in reading order, the creatures of its figures, the words to click of its strip."""
    wow.execute(
        f"""
        PageSheet = nil
        local d = {dossier}
        local quests = d.sheet and Bastians:GetModule('Quests')
        local c = quests and quests.Sheet and quests.Sheet.Canvas(d.content)
        if c and c.frame:IsShown() then
          local words, buttons, figures = {{}}, {{}}, {{}}
          for i = 1, c.used.text do
            local fs = c.texts[i]
            local _, _, _, _, y = fs:GetPoint(1)
            words[#words + 1] = {{ y or 0, fs:GetText() }}
          end
          table.sort(words, function(a, b) return a[1] > b[1] end)
          for _, b in pairs(c.buttons) do
            if b:IsShown() then
              local _, _, _, x, y = b:GetPoint(1)
              buttons[#buttons + 1] = {{ y or 0, x or 0, b.label:GetText() }}
            end
          end
          table.sort(buttons, function(a, b)
            if a[1] ~= b[1] then return a[1] > b[1] end
            return a[2] < b[2]
          end)
          for i = 1, c.used.figure do figures[i] = c.figures[i].creature end
          local links = {{}}
          for _, b in pairs(c.links) do
            if b:IsShown() then
              local _, _, _, x, y = b:GetPoint(1)
              links[#links + 1] = {{ y or 0, x or 0, b.text:GetText() }}
            end
          end
          table.sort(links, function(a, b)
            if a[1] ~= b[1] then return a[1] > b[1] end
            return a[2] < b[2]
          end)
          PageSheet = {{ words = words, buttons = buttons, figures = figures, links = links }}
        end
        """
    )
    sheet = wow.eval("PageSheet")
    if sheet is None:
        return None
    return {
        "words": [strip(w[2]) for w in sheet.words.values()],
        "buttons": [strip(b[3]) for b in sheet.buttons.values()],
        "figures": list(sheet.figures.values()),
        "links": [strip(x[3]) for x in sheet.links.values()],
    }


def band(wow: WowRuntime, dossier: str) -> dict:
    sheet = hosted_sheet(wow, dossier)
    if sheet:
        # the head of a hosted sheet: its title, and under it the line of zone and level
        words = sheet["words"]
        return {
            "shown": True,
            "name": words[0],
            "badge": wow.eval(f"{dossier}.data.card.typeLabel"),
            "summary": words[1] if len(words) > 1 else "",
            "status": None,
            "height": 0,
        }
    b = wow.eval(f"{dossier}.band")
    return {
        "shown": b.IsShown(b),
        "name": b.name.GetText(b.name),
        "badge": b.badge.label.GetText(b.badge.label),
        "summary": b.meta.GetText(b.meta) if b.meta.IsShown(b.meta) else "",
        "status": strip(b.status.GetText(b.status)) if b.status.IsShown(b.status) else None,
        "height": b.GetHeight(b),
    }


def click_sheet_button(wow: WowRuntime, dossier: str, label: str) -> None:
    """Clicks the button of a hosted sheet that reads `label`."""
    wow.execute(
        f"""
        local d = {dossier}
        local c = Bastians:GetModule('Quests').Sheet.Canvas(d.content)
        for _, b in pairs(c.buttons) do
          if b:IsShown() and b.label:GetText() == {label!r} then b:Click() return end
        end
        error('no button {label} on the hosted sheet')
        """
    )


def band_buttons(wow: WowRuntime, dossier: str) -> list[str]:
    sheet = hosted_sheet(wow, dossier)
    if sheet:
        return sheet["buttons"]
    return [
        strip(x.label.GetText(x.label))
        for x in wow.eval(f"{dossier}.buttons").values()
        if x.IsShown(x)
    ]


def block_titles(wow: WowRuntime, dossier: str) -> list[str]:
    """The drawn block titles, with the count the dossier prints beside a title ("DO HERE  2")."""
    return [
        block_title(bf, True) for bf in wow.eval(f"{dossier}.blockPool").values() if bf.IsShown(bf)
    ]


def block_title(bf, with_count: bool) -> str:
    """A block's title as drawn; with the count the dossier prints beside it when asked."""
    text = strip(bf.title.GetText(bf.title))
    if with_count and bf.count.IsShown(bf.count):
        text += "  " + strip(bf.count.GetText(bf.count))
    return text


def block_rows(wow: WowRuntime, dossier: str, title: str) -> list[str]:
    """The rows the block with this (upper-cased) title draws now, "+N more" included. The title
    may carry the count ("My quests here  2"): the dossier prints it beside Here block titles."""
    wanted = title.upper()
    for bf in wow.eval(f"{dossier}.blockPool").values():
        if bf.IsShown(bf) and wanted in (block_title(bf, False), block_title(bf, True)):
            return [strip(r.text) for r in bf.tree.flat.values()]
    return []


def block_controls(wow: WowRuntime, dossier: str, title: str) -> list[tuple[str, bool]]:
    """The toggles on a block's title line as (label, on)."""
    wanted = title.upper()
    for bf in wow.eval(f"{dossier}.blockPool").values():
        if bf.IsShown(bf) and wanted in (block_title(bf, False), block_title(bf, True)):
            return [
                (strip(b.label.GetText(b.label)), b.control.on is True)
                for b in bf.controls.values()
                if b.IsShown(b)
            ]
    return []


def click_ref(wow: WowRuntime, dossier: str, ref: str, button: str = "LeftButton") -> bool:
    """Clicks the first row (block or link, children included) whose ref is `ref` the way the
    host's handler would be called; False when the page has no such row."""
    return bool(
        wow.eval(
            f"""(function()
              local d = {dossier}
              if not d.data then return false end
              local function walk(rows)
                for _, r in ipairs(rows) do
                  if r.ref == "{ref}" then d.opts.onClick(r, "{button}", d) return true end
                  if r.children and walk(r.children) then return true end
                end
                return false
              end
              for _, b in ipairs(d.data.blocks) do if walk(b.rows) then return true end end
              for _, l in ipairs(d.data.links) do if walk(l.rows) then return true end end
              return false
            end)()"""
        )
    )


# The filter bar (ADR 0016): `tree` is a Lua expression for a Tree whose chips became the bar.


def pills(wow: WowRuntime, tree: str) -> list[str]:
    """The shown pills' words, "Title: Choice", without colours."""
    if wow.eval(f"{tree}.filterBar") is None:
        return []
    return [str(s) for s in wow.eval(f"{tree}.filterBar:Labels()").values()]


def _pill(tree: str, dim: str) -> str:
    """A Lua expression for a dimension's pill. The Browser's "where" is no pill of the bar since
    ADR 0056 (PA1.2): it is the scope chip inside the search box, which clicks and clears alike."""
    return (
        f"({tree}.filterBar:Pill('{dim}') "
        f"or ('{dim}' == 'where' and {tree} == {BROWSER}.tree and {BROWSER}.scope) or nil)"
    )


def scope(wow: WowRuntime) -> str | None:
    """The words of the Browser's scope chip ("in Elwynn Forest"), None while it is hidden."""
    return wow.eval(f"({BROWSER}.Browser.Scope())")


def menu(wow: WowRuntime, tree: str, dim: str) -> list[str]:
    """Opens the dropdown of a pill (by dimension id) and returns its entries: "label  count"."""
    wow.execute(f"{_pill(tree, dim)}:Click()")
    frame = wow.eval("Bastians.UI.FilterMenuFrame()")
    out = []
    for item in frame["items"].values():  # lupa: `items` is a method name, index it
        if item.IsShown(item):
            label, count = item.label.GetText(item.label), item.count.GetText(item.count)
            out.append(f"{label}  {count}" if count else str(label))
    wow.execute("Bastians.UI.HideFilterMenu()")
    return out


def pick(wow: WowRuntime, tree: str, dim: str, label: str) -> None:
    """Opens a pill's dropdown and clicks the entry whose label is `label`."""
    wow.execute(f"{_pill(tree, dim)}:Click()")
    wow.execute(
        "for _, b in ipairs(Bastians.UI.FilterMenuFrame().items) do "
        f"if b:IsShown() and b.label:GetText() == {label!r} then b:Click() return end end "
        f"error('no entry {label} in the {dim} dropdown')"
    )


def clear(wow: WowRuntime, tree: str, dim: str) -> None:
    """Clicks the pill's "x"."""
    wow.execute(f"{_pill(tree, dim)}.clear:Click()")


# ---- the Browser's navigation pane (ADR 0018) ---------------------------------------------------

BROWSER = "Bastians:GetModule('Browser')"


def chips(wow: WowRuntime, tree: str = "Bastians:GetModule('Browser').tree") -> list[tuple]:
    """The filter bar's chips (ADR 0038): (label, count, on) in their order."""
    return [(c.label, c.count, c.on) for c in wow.eval(f"{tree}.filterBar:Chips()").values()]


def chip(wow: WowRuntime, label: str, tree: str = "Bastians:GetModule('Browser').tree") -> None:
    """Clicks the chip with `label` ("All" clears the dimension)."""
    wow.execute(
        f"""
        local bar = {tree}.filterBar
        for i = 1, bar.chipCount do
          local c = bar.chips[i]
          if c.label:GetText() == '{label}' then c:Click() end
        end
        """
    )
    wow.run_frames(3)


def nav_rows(wow: WowRuntime) -> list[tuple[str, str]]:
    """Every tab of every rail section, in rail order, as (id, text): what the category bar
    listed until ADR 0058 (a tab says its search count after two spaces, as the bar did)."""
    wow.execute(
        f"NavRows = {{}} for _, s in ipairs({BROWSER}.Browser.Sections()) do "
        "for _, c in ipairs(s.tabs) do "
        "NavRows[#NavRows + 1] = { c.id, c.count and (c.text .. '  ' .. c.count) or c.text } end end"
    )
    return [(str(r[1]), strip(r[2])) for r in wow.eval("NavRows").values()]


def nav_lists(wow: WowRuntime) -> list[str]:
    """The list tabs of the rail's sections, in order."""
    return [text for rid, text in nav_rows(wow) if rid.startswith("nav:list:")]


def nav_active(wow: WowRuntime) -> str | None:
    """The id of the lit tab (the lit rail entry's section holds it)."""
    return wow.eval(f"{BROWSER}.tabs.active")


def rail_rows(wow: WowRuntime) -> list[tuple[str, str, bool, str | None]]:
    """The rail's seven entries as (id, label, lit, needs)."""
    wow.execute(
        f"RailRows = {{}} for _, b in ipairs({BROWSER}.rail.buttons) do "
        "if b:IsShown() and b.section then RailRows[#RailRows + 1] = "
        "{ b.section.id, b.section.label, b.spec.primary == true, b.section.needs or false } end end"
    )
    return [
        (str(r[1]), str(r[2]), bool(r[3]), (str(r[4]) if r[4] else None))
        for r in wow.eval("RailRows").values()
    ]


def tab_rows(wow: WowRuntime) -> list[tuple[str, str, bool]]:
    """The shown section's tabs as (id, label, lit); empty for a section of one list."""
    wow.execute(
        f"TabRows = {{}} for _, b in ipairs({BROWSER}.tabs.buttons) do "
        "if b:IsShown() and b.cat then TabRows[#TabRows + 1] = { b.cat.id, b.spec.label, b.spec.primary == true } end end"
    )
    return [(str(r[1]), strip(r[2]), bool(r[3])) for r in wow.eval("TabRows").values()]


def nav_click(wow: WowRuntime, row_id: str, button: str = "LeftButton") -> None:
    """Opens the tab `row_id` from whatever section holds it (a click on its rail entry, then on
    the tab), as a player would; `button` is kept for the old calls."""
    assert button == "LeftButton"
    wow.execute(f"assert({BROWSER}.Browser.NavClick({row_id!r}), 'no tab {row_id}')")


def rail_click(wow: WowRuntime, section: str) -> None:
    """Clicks a rail entry."""
    wow.execute(
        f"for _, b in ipairs({BROWSER}.rail.buttons) do if b:IsShown() and b.section and b.section.id == {section!r} then "
        "b:Click('LeftButton') return end end "
        f"error('no rail entry {section}')"
    )


def near_by_default(wow: WowRuntime) -> None:
    """Lists opened on the player's zone until 06.11.2026 (they open on everything now): for a test
    of the narrowing itself, the old default, so it starts narrowed."""
    wow.execute(
        f"""
        {BROWSER}.Browser.DefaultNear = function(counts)
          local near = counts and counts.near
          if near and near.here > 0 then return "here" end
          if near and near.continent > 0 then return "continent" end
          return nil
        end
        """
    )
