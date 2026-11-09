"""A page on paper draws in the paper's colours only (ADR 0054; white,
yellow and teal words on parchment). Every text of the Browser's page is walked: its ink is a colour
of the paper's palette, and every colour code inside it is one of the paper's codes."""

from harness import WowRuntime

CORE, DATA, QUESTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
DS = f"{MOD}.dossier"

# Found = { "ink r,g,b :: text" | "code |cffrrggbb :: text" } for every text that is not the paper's
WALK = """
local S = Bastians.UI.Style
local paper = S.Palette("parchment")
local okCodes, okInk = {}, {}
for k, v in pairs(paper.H) do if type(v) == "string" then okCodes[v:lower()] = k end end
local function key(r, g, b) return math.floor(r * 255 + 0.5) .. "," .. math.floor(g * 255 + 0.5) .. "," .. math.floor(b * 255 + 0.5) end
for k, c in pairs(paper.C) do if type(c) == "table" then okInk[key(c[1], c[2], c[3])] = k end end
Found = {}
local function note(kind, what, text) Found[#Found + 1] = kind .. " " .. what .. " :: " .. tostring(text):sub(1, 60) end
local function walk(f, depth)
  if depth > 14 or not f.IsShown or not f:IsShown() then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetText and r:IsShown() and r:GetText() and r:GetText() ~= "" then
      local t = r:GetText()
      local cr, cg, cb = r:GetTextColor()
      if cr and not okInk[key(cr, cg, cb)] then note("ink", key(cr, cg, cb), t) end
      for code in t:gmatch("|c%x%x%x%x%x%x%x%x") do
        if not okCodes[code:lower()] then note("code", code, t) end
      end
    end
  end
  for _, c in ipairs({ f:GetChildren() }) do walk(c, depth + 1) end
end
walk(DOSSIER.frame, 0)
"""

HOVER = """
for _, bf in ipairs(DOSSIER.blockPool) do
  if bf:IsShown() and bf.tree and bf.tree.pool then
    for _, row in ipairs(bf.tree.pool) do
      if row:IsShown() and row:GetScript("OnEnter") then row:GetScript("OnEnter")(row) end
      if row:IsShown() and row:GetScript("OnLeave") then row:GetScript("OnLeave")(row) end
    end
    bf.tree:Render()
  end
end
"""


def foreign(wow: WowRuntime, ref: str, hover: bool = False) -> list[str]:
    """The texts of `ref`'s page that are not in the paper's colours."""
    wow.execute(f"Bastians:ShowPage('{ref}')")
    wow.run_frames(5)
    wow.advance(0.3)
    wow.execute(f"DOSSIER = {DS}")
    if hover:
        wow.execute(HOVER)
        wow.run_frames(3)
    wow.execute(WALK)
    return sorted(set(wow.eval("Found").values()))


def test_a_page_on_paper_holds_no_colour_of_the_theme(wow: WowRuntime):
    """The zone's quest rows were built once, by whoever asked first, and kept in Quests' own
    cache: the paper page got the theme's yellow, teal and grey. They are kept per colour set.
    A log quest's objective count ran on a fixed bright scale: on a light ground it runs between
    the colour set's own difficulty colours. The trail and every later draw stay on paper too."""
    wow.start(CORE, DATA, QUESTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    # the theme asks for the zone's rows first, as the dark panes and the map do in the game
    wow.execute("Bastians:GetDetailSections('zone:1429')")
    for ref in ("zone:1429", "quest:62", "quest:176", "npc:240", "zone:1429"):
        assert foreign(wow, ref) == [], ref
        assert foreign(wow, ref, hover=True) == [], ref + " after the mouse"
    assert wow.eval(f"{DS}.palette == Bastians.UI.Style.Palette('parchment')") is True
    assert wow.errors == []


def test_the_progress_scale_follows_a_light_ground(wow: WowRuntime):
    wow.start(CORE, DATA, QUESTS)
    wow.run_frames(5)
    wow.execute(
        """S = Bastians.UI.Style
        Rows = Bastians:GetModule('Quests').Rows
        paper = S.Palette('parchment')
        function onPaper(a, b) return S.WithPalette(paper, Rows.progressColor, a, b) end"""
    )
    assert wow.eval("Rows.progressColor(0, 4)") == "|cffff4040"  # the dark themes keep their scale
    assert wow.eval("onPaper(0, 4) == paper.H.diffRed") is True
    assert wow.eval("onPaper(2, 4) == paper.H.diffYellow") is True
    assert wow.eval("onPaper(4, 4) == paper.H.diffGreen") is True
    assert wow.eval("onPaper(1, 4) ~= onPaper(0, 4) and onPaper(1, 4) ~= Rows.progressColor(1, 4)")
    assert wow.errors == []
