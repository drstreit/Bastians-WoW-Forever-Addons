"""(R25.31): a "copy Wowhead link" icon on quests, items and NPCs, beside
hide, route and map; the link goes into the chat input (the game opens no browser)."""

from harness import WowRuntime

BR = "Bastians:GetModule('Browser').Browser"


def test_the_wowhead_link_is_offered_on_rows_and_lands_in_the_chat_input(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Quests", "Bastians_Browser")
    wow.run_frames(10)
    site = (
        "https://www.wowhead.com/classic/"
        if wow.client == "forever"
        else "https://www.wowhead.com/"
    )
    assert wow.eval(f"{BR}.WowheadLink('quest:176')") == site + "quest=176"
    assert wow.eval(f"{BR}.WowheadLink('npc:448')") == site + "npc=448"
    assert wow.eval(f"{BR}.WowheadLink('zone:1429')") is None  # no such page
    ids = [a.id for a in wow.eval("Bastians:GetActions('item:2589', { source = 'test' })").values()]
    assert "browser.wowhead" in ids
    row = [a.id for a in wow.eval("Bastians.UI.TreeUtil.rowActions('quest:176', {})").values()]
    assert "browser.wowhead" in row  # a row icon (Tree.ROW_ACTIONS)
    wow.execute("Bastians:RunAction('browser.wowhead', 'item:2589', { source = 'test' })")
    assert wow.eval("Mock.chatInput") == site + "item=2589"
    assert wow.errors == []
