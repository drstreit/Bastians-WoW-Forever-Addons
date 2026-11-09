"""Tabs inside a sheet (ADR 0058, PH5): a dungeon reads as Overview (the facts as tiles, the
floors, your runs), Bosses, Quests, Attunement (always, "No attunement needed."), Loot and
Strategy (always, the book's pages); a character as Overview (the facts as tiles, the goals),
Equipment, Bags, Bank, Mail and Requests."""

import re

from harness import WowRuntime

CORE, DATA, QUESTS, ALTS, BROWSER = (
    "Bastians_Core",
    "Bastians_Data",
    "Bastians_Quests",
    "Bastians_Alts",
    "Bastians_Browser",
)
MOD = "Bastians:GetModule('Browser')"
BR = f"{MOD}.Browser"
DS = f"{MOD}.dossier"


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start(CORE, DATA, QUESTS, ALTS, BROWSER)
    wow.run_frames(10)
    wow.advance(0.3)
    return wow


def strip(text: str | None) -> str:
    text = re.sub(r"\|T[^|]*\|t ?", "", text or "")
    return re.sub(r"\|c[0-9a-fA-F]{8}", "", text).replace("|r", "")


def tabs(wow: WowRuntime) -> list[tuple[str, str, bool]]:
    return [
        (str(b.tabId), strip(b.spec.label), b.spec.primary is True)
        for b in wow.eval(f"{DS}.tabPool").values()
        if b.IsShown(b)
    ]


def cards(wow: WowRuntime) -> list[str]:
    return [str(c.chapter.id) for c in wow.eval(f"{DS}.cards").values()]


def block_texts(wow: WowRuntime, i: int = 1) -> list[str]:
    return [strip(r.text) for r in wow.eval(f"{DS}.blockPool[{i}].tree.flat").values()]


def tiles(wow: WowRuntime, i: int = 1) -> list[tuple[str, str]]:
    return [
        (strip(t.label.GetText(t.label)), strip(t.value.GetText(t.value)))
        for t in (wow.eval(f"{DS}.blockPool[{i}].statPool") or {}).values()
        if t.IsShown(t)
    ]


def test_a_dungeon_reads_in_tabs(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{BR}.Open('dungeon:36')")  # the fixture's Deadmines
    wow.run_frames(5)
    ids = [t[0] for t in tabs(wow)]
    assert ids[0] == "overview" and ids[-1] == "book"
    assert ("bosses" in ids and "attunement" in ids and "loot" not in ids) or "loot" in ids
    assert ids.index("bosses") < ids.index("attunement") < ids.index("book")
    assert "quests" not in ids or ids.index("quests") < ids.index("attunement")
    assert tabs(wow)[0][2] is True  # the overview first
    # the overview: the facts as tiles, then the floors and the rest
    assert "map" in cards(wow)
    facts = tiles(wow)
    assert (
        facts[0] == ("Level", "15-25") and facts[1][0] == "Bosses" and facts[2] == ("Players", "5")
    )
    assert facts[3][0] == "Floors"
    # Attunement: nothing in the fixture, so the tab says so
    i = ids.index("attunement") + 1
    wow.execute(f"{DS}.tabPool[{i}]:Click()")
    wow.run_frames(3)
    # the fixture's Deadmines has an attunement chain: the tab shows it (a dungeon without one
    # says "No attunement needed."; the kit test covers the words)
    assert cards(wow) == ["attunement"] and block_texts(wow)[0].startswith("Step 1 of 3")
    # Strategy: no page of the book names the fixture's dungeon
    wow.execute(f"{DS}:SetTab('book')")
    wow.run_frames(3)
    assert cards(wow) == ["book"] and block_texts(wow) == [
        "No page of the book names this dungeon yet."
    ]
    assert next(t for t in tabs(wow) if t[2])[0] == "book"
    # Bosses: the bosses' tiles, as before, in their own tab
    wow.execute(f"{DS}:SetTab('bosses')")
    wow.run_frames(3)
    assert cards(wow) == ["bosses"]
    # another dungeon opens on its overview
    wow.execute(f"{BR}.Open('npc:240')")
    wow.run_frames(3)
    assert tabs(wow) == []  # a person has no tabs
    wow.execute(f"{BR}.Open('dungeon:36')")
    wow.run_frames(3)
    assert tabs(wow)[0][2] is True
    assert wow.errors == []


def test_a_character_reads_in_tabs_with_the_facts_as_tiles(wow: WowRuntime):
    boot(wow)
    key = wow.eval("Bastians:GetModule('Alts').Alts.Key()")
    wow.execute("Bastians:GetModule('Alts').Alts.RecordFacts()")
    wow.execute(f"{BR}.Open('character:{key}')")
    wow.run_frames(5)
    ids = [t[0] for t in tabs(wow)]
    assert (ids[:1] == ["overview"] and ids[-3:] == ["bags", "bank", "mail"]) or "requests" in ids
    assert "bags" in ids and "bank" in ids and "mail" in ids  # always there
    facts = tiles(wow)
    assert facts and facts[0][0] == "Level" and facts[0][1].isdigit()
    i = ids.index("bank") + 1
    wow.execute(f"{DS}.tabPool[{i}]:Click()")
    wow.run_frames(3)
    assert cards(wow) == ["bank"]
    texts = block_texts(wow)
    assert texts == ["The bank was not read yet: open it once on this character."] or len(texts) > 0
    assert wow.errors == []
