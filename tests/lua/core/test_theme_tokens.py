"""Themes (ST3, ADR 0017): the tokens come from the active theme, a switch writes the new values into
the same tables (kept references follow), re-colours what the kit drew, updates the text codes,
announces itself and is kept per profile; and no addon file carries a raw colour any more."""

import re
from pathlib import Path

from harness import WowRuntime

ROOT = Path(__file__).resolve().parents[3]
S = "Bastians.UI.Style"


def rgb(wow: WowRuntime, expr: str) -> list[float]:
    return [round(v, 3) for v in list(wow.eval(expr).values())[:3]]


def test_a_theme_switch_writes_into_the_same_tables_and_recolours(core: WowRuntime):
    assert core.eval(f"{S}.ThemeId()") == "teal"
    assert [t.id for t in core.eval(f"{S}.Themes()").values()] == [
        "teal",
        "parchment",
        "blizzard",
        "contrast",
    ]
    core.execute(
        f"""
        kept = {S}.C.accent
        panel = CreateFrame("Frame", nil, UIParent)
        fill = {S}.fill(panel, {S}.C.panel)
        label = {S}.text(panel, 12, {S}.C.text)
        seen = {{}}
        local m = Bastians:NewModule("ThemeWatch", {{ addon = "Bastians_TestApp" }})
        m:On("BASTIANS_THEME_CHANGED", function(_, _, id) seen[#seen + 1] = id end)
        """
    )
    teal_accent = rgb(core, "kept")
    assert core.eval(f"{S}.H.muted") == "|cff808080"
    core.execute(f"{S}.ApplyTheme('parchment')")
    assert core.eval(f"{S}.ThemeId()") == "parchment"
    assert rgb(core, "kept") != teal_accent  # the kept reference follows the theme
    assert rgb(core, "kept") == rgb(core, f"{S}.C.accent")
    r, g, b, _ = core.eval("fill:GetVertexColor()")
    assert [round(v, 3) for v in (r, g, b)] == rgb(core, f"{S}.C.panel")
    r, g, b, _ = core.eval("label:GetTextColor()")
    assert [round(v, 3) for v in (r, g, b)] == rgb(core, f"{S}.C.text")
    assert core.eval(f"{S}.H.muted") != "|cff808080"  # the text codes follow too
    assert core.eval(f"{S}.SHAPE.radius") == 6
    core.execute(f"{S}.ApplyTheme('nonsense')")  # unknown: the first theme
    assert core.eval(f"{S}.ThemeId()") == "teal" and rgb(core, "kept") == teal_accent
    assert list(core.eval("seen").values()) == ["parchment", "teal"]
    assert core.errors == []


def pick_scheme(wow: WowRuntime, name: str) -> None:
    """Chooses a scheme in the hub's General page, as the player does."""
    wow.execute("Bastians.UI.Hub.Open('Core')")
    wow.execute(
        "local picked = false "
        "for _, w in ipairs(Bastians.UI.Hub.canvas.widgets) do "
        "  if w.label and w.label:GetText() == 'Colour scheme' then w:Open() "
        "    for _, item in ipairs(w.list.items) do "
        f"      if item:IsShown() and item.label:GetText() == '{name}' then item:Click() picked = true end "
        "    end "
        "  end "
        "end "
        f"assert(picked, 'no {name} in the Colour scheme select')"
    )


def test_the_general_page_keeps_the_scheme_per_profile(core: WowRuntime):
    pick_scheme(core, "High contrast")
    assert core.eval(f"{S}.ThemeId()") == "contrast"
    assert core.eval("Bastians:GetModule('Core').db.profile.theme") == "contrast"
    core.execute("Bastians:SetProfile('Second')")
    assert core.eval(f"{S}.ThemeId()") == "teal"  # a new profile starts on the default
    core.execute("Bastians:SetProfile('Default')")
    assert core.eval(f"{S}.ThemeId()") == "contrast"
    assert core.errors == []


# A raw colour in an addon file (ADR 0017): an inline code, a literal { r, g, b } table, or a colour
# call with numbers. Allowed: the generated themes, the probe (developer only), and resetting a
# texture to its own colours through S.untint.
RAW = [
    re.compile(r"\|c[fF][fF][0-9a-fA-F]{6}"),
    re.compile(r"\{ ?[01]?\.?\d*, ?[01]?\.?\d*, ?[01]?\.?\d*(, ?[01]?\.?\d*)? ?\}"),
    re.compile(
        r"(SetTextColor|SetVertexColor|SetColorTexture|AddLine|AddDoubleLine)\([^)]*\b[01]?\.\d+"
    ),
]
ALLOWED = {"Bastians_Core/UI/Themes.lua", "Bastians_Core/UI/Style.lua"}


def test_no_addon_file_carries_a_raw_colour():
    found = []
    for path in sorted((ROOT / "addons").rglob("*.lua")):
        rel = path.relative_to(ROOT / "addons").as_posix()
        if "/Generated/" in rel or "/Libs/" in rel or rel.startswith("Bastians_Probe/"):
            continue
        if rel in ALLOWED:
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("--", 1)[0]
            if any(p.search(code) for p in RAW):
                found.append(f"{rel}:{n}: {line.strip()}")
    assert found == [], "use a token of Bastians.UI.Style (S.C, S.H):\n" + "\n".join(found)


def test_the_guard_sees_what_it_should():
    # the patterns match the shapes that were in the code before ST3 (a vacuous guard is no guard)
    samples = [
        '"  |cff808080" .. x',
        "local GOLD = { 1, 0.82, 0 }",
        "t:SetVertexColor(1, 1, 1, 0.25)",
        "color = { 0.6, 0.6, 0.6 }",
        "GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)",
    ]
    assert all(any(p.search(s) for p in RAW) for s in samples)
    clean = ["S.tint(t, S.C.grid)", "text = S.H.muted .. x", "local spots = { 1, 2 }"]
    assert not any(any(p.search(s) for p in RAW) for s in clean)
