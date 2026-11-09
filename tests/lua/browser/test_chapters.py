"""The sheets' chapters across the suite (ADR 0054, AT1.4): Bastian's Data declares the reading
order of its types, every app names the chapter of each of its sections. A section that became a
chapter of its own by accident shows here."""

from pathlib import Path

from harness import WowRuntime

ADDONS = Path(__file__).resolve().parents[3] / "addons"
APPS = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Map",
    "Bastians_Browser",
    "Bastians_Gold",
    "Bastians_Route",
    "Bastians_Strategies",
    "Bastians_Notes",
    "Bastians_Alts",
    "Bastians_Helpers",
    "Bastians_Voice",
)
DS = "Bastians:GetModule('Browser').dossier"
BR = "Bastians:GetModule('Browser').Browser"

# every section of a type with a reading order sits in one of its chapters or under the figure;
# not asked: links, the status words (`card`), the Here column's own, the tooltip-only hint
STRAYS = """
strays = {}
local Util = Bastians.UI.DossierUtil
for _, typ in ipairs({ "npc", "item", "object", "node", "quest", "zone", "area", "dungeon" }) do
  local known = { facts = true }
  for _, c in ipairs(Bastians:GetChapters(typ, 0)) do
    known[c.id] = true
  end
  for _, def in ipairs(Bastians:GetDetailSectionDefs(typ .. ":0")) do
    local skip = def.link or def.card or (def.here and def.here.only) or def.id == "browser.hint"
    local chapter = Util.chapterOf(def, typ)
    if not skip and not (chapter and known[chapter]) then
      strays[#strays + 1] = typ .. " " .. def.id .. " -> " .. tostring(chapter)
    end
  end
end
table.sort(strays)
"""

MONSTER = 448  # Hogger: no service, no faction
# the fixture's pages: (chapter, its sections) in the reading order of the type
PAGES = {
    "npc:240": [("quests", ["quests.starts", "quests.ends"]), ("where", ["data.spawns"])],
    "item:2589": [("get", ["data.sources", "data.where"])],
    "zone:1429": [
        (
            "quests",
            ["quests.zone.todo", "quests.zone.turnin", "quests.zone.active", "quests.zone.onward"],
        ),
        ("chains", ["quests.zone.chains"]),
        ("places", ["data.areas"]),  # the fixture zone has no gathering nodes
        ("people", ["data.people"]),
        ("monsters", ["data.monsters"]),
        ("roads", ["quests.zone.neighbours"]),
    ],
    "quest:62": [
        ("people", ["quests.givers", "quests.enders"]),
        ("rewards", ["quests.rewards"]),
        ("text", ["quests.text"]),
    ],
    "quest:176": [
        ("todo", ["quests.objectives"]),
        ("people", ["quests.givers", "quests.enders"]),
        ("rewards", ["quests.rewards", "quests.choice"]),
        ("text", ["quests.text"]),
    ],
}


def boot(wow: WowRuntime, *addons: str) -> WowRuntime:
    wow.start(*addons)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def chapters(wow: WowRuntime, ref: str) -> list[tuple]:
    data = wow.eval(f"Bastians.UI.DossierData('{ref}', nil, {{ source = 'browser' }})")
    return [(c.id, c.title, [b.id for b in c.blocks.values()]) for c in data.chapters.values()]


def test_no_section_is_a_chapter_of_its_own_by_accident(wow: WowRuntime):
    apps = [a for a in APPS if (ADDONS / a).is_dir()]
    if (ADDONS / "Bastians_Library").is_dir():
        apps.append("Bastians_Library")
    boot(wow, *apps)
    wow.execute(STRAYS)
    assert list(wow.eval("strays").values()) == []
    assert wow.errors == []


def test_the_fixtures_pages_read_in_their_types_order(wow: WowRuntime):
    boot(wow, "Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Browser")
    order = "Bastians:GetChapters('npc', %d)"
    # the two orders of an NPC: a monster reads its drops first
    assert [c.id for c in wow.eval(order % 240).values()][:4] == [
        "sells",
        "teaches",
        "quests",
        "drops",
    ]
    assert [c.id for c in wow.eval(order % MONSTER).values()][:2] == ["drops", "quests"]
    for ref, expected in PAGES.items():
        assert [(c[0], c[2]) for c in chapters(wow, ref)] == expected, ref
    # the facts stand under the figure, in no chapter: the overview, an item's stats
    facts = "Bastians.UI.DossierData('item:2589', nil, { source = 'browser' }).facts"
    assert [b.id for b in wow.eval(facts).values()] == ["data.overview", "data.stats"]
    titles = [c[1] for c in chapters(wow, "quest:62")]
    assert titles == ["Giver and hand-in", "Rewards", "Quest text"]
    assert wow.errors == []
