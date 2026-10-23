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


def band(wow: WowRuntime, dossier: str) -> dict:
    b = wow.eval(f"{dossier}.band")
    return {
        "shown": b.IsShown(b),
        "name": b.name.GetText(b.name),
        "badge": b.badge.label.GetText(b.badge.label),
        "summary": b.meta.GetText(b.meta) if b.meta.IsShown(b.meta) else "",
        "status": strip(b.status.GetText(b.status)) if b.status.IsShown(b.status) else None,
        "height": b.GetHeight(b),
    }


def band_buttons(wow: WowRuntime, dossier: str) -> list[str]:
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


def menu(wow: WowRuntime, tree: str, dim: str) -> list[str]:
    """Opens the dropdown of a pill (by dimension id) and returns its entries: "label  count"."""
    wow.execute(f"{tree}.filterBar:Pill('{dim}'):Click()")
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
    wow.execute(f"{tree}.filterBar:Pill('{dim}'):Click()")
    wow.execute(
        "for _, b in ipairs(Bastians.UI.FilterMenuFrame().items) do "
        f"if b:IsShown() and b.label:GetText() == {label!r} then b:Click() return end end "
        f"error('no entry {label} in the {dim} dropdown')"
    )


def clear(wow: WowRuntime, tree: str, dim: str) -> None:
    """Clicks the pill's "x"."""
    wow.execute(f"{tree}.filterBar:Pill('{dim}').clear:Click()")


# ---- the Browser's navigation pane (ADR 0018) ---------------------------------------------------

BROWSER = "Bastians:GetModule('Browser')"


def nav_rows(wow: WowRuntime) -> list[tuple[str, str]]:
    """The navigation's visible rows as (id, text), group headers included."""
    return [(str(r.id), strip(r.text)) for r in wow.eval(f"{BROWSER}.navTree.flat").values()]


def nav_lists(wow: WowRuntime) -> list[str]:
    """The list entries of the navigation, in order."""
    return [text for rid, text in nav_rows(wow) if rid.startswith("nav:list:")]


def nav_active(wow: WowRuntime) -> str | None:
    """The id of the accented navigation row."""
    return wow.eval(f"{BROWSER}.navTree.selectedID")


def nav_click(wow: WowRuntime, row_id: str, button: str = "LeftButton") -> None:
    """Clicks the navigation row `row_id` as the tree does."""
    wow.execute(
        f"local t = {BROWSER}.navTree "
        f"for _, r in ipairs(t.flat) do if r.id == {row_id!r} then "
        f"t:Select(r) t.opts.onClick(r, {button!r}, t) return end end "
        f"error('no navigation row {row_id}')"
    )
