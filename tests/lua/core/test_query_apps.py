"""The search syntax in the apps' own filters (ADR 0045): the Browser's list filter with the list's
fields, Bastian's Chat's tab filters and spam words with from:, in: and has:, Notes and the book's
search with OR and NOT, the Map's button box. Every name is invented (CLAUDE.md §8)."""

import sys
from pathlib import Path

import pytest
from harness import WowRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "chat"))
try:
    from test_chat import M as CHAT
    from test_chat import boot as boot_chat
except ImportError:  # Bastian's Chat's tests stay private (tools/publish.py PRIVATE): skip theirs
    CHAT = boot_chat = None

needs_chat = pytest.mark.skipif(boot_chat is None, reason="Bastian's Chat's tests are private")

BR = "Bastians:GetModule('Browser').Browser"

LIST = """
ChatQ = { list = {
  n = 3, names = { 'Rabid Wolf', 'Grey Wolf', 'Old Boar' }, nears = { 'all', 'all', 'all' },
  levels = { 10, 30, 50 }, zones = {},
  dims = { { id = 'kind', title = 'Kind', labels = function(k) return k == 'v' and 'Vendor' or 'Trainer' end } },
  values = { { 'v', 't', 'v' } },
} }
"""


def test_the_browser_list_filter_reads_the_lists_fields(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Browser")
    wow.execute(LIST)

    def rows(text: str) -> list[str]:
        out = wow.eval(f"{BR}.Filter(ChatQ.list, {{ filterText = {text!r} }})")
        return [wow.eval(f"ChatQ.list.names[{i}]") for i in out.rows.values()]

    assert rows("wolf") == ["Rabid Wolf", "Grey Wolf"]
    assert rows("wolf -rabid") == ["Grey Wolf"]
    assert rows("level>20") == ["Grey Wolf", "Old Boar"]
    assert rows("lvl:5..15") == ["Rabid Wolf"]
    assert rows("kind:vendor") == ["Rabid Wolf", "Old Boar"]  # the key's label
    assert rows("kind:t OR boar") == ["Grey Wolf", "Old Boar"]
    assert rows("zone:elwynn") == []  # no zone known: unknown, never a match
    assert wow.eval(f"{BR}.ListFieldNames(ChatQ.list)") == "kind, level, type, zone"
    assert wow.errors == []


@needs_chat
def test_chat_filters_read_the_line(wow: WowRuntime):
    boot_chat(wow)
    m = f"{CHAT}.Model"
    wow.execute(f"ChatQ = {{ w = {m}.Words('from:stranger, in:trade lfg -wts, has:item') }}")

    def hit(line: str):
        found = wow.eval(f"{m}.MatchWords(ChatQ.w, ({line}).plain, {line})")
        return found.word if found else None

    trade = "{ cat = 'channel', channel = 'Trade', sender = 'Seller-Realm', plain = 'lfg dm tank' }"
    assert hit(trade) == "in:trade lfg -wts"
    wts = "{ cat = 'channel', channel = 'Trade', sender = 'Seller-Realm', plain = 'lfg wts boost' }"
    assert hit(wts) is None
    assert hit("{ cat = 'say', sender = 'Stranger-Realm', plain = 'hello' }") == "from:stranger"
    item = (
        "{ cat = 'say', sender = 'X-Realm', plain = 'look', text = 'look |Hitem:2589|h[Linen]|h' }"
    )
    assert hit(item) == "has:item"
    # the old way of writing a pattern still works
    wow.execute(f"ChatQ.old = {m}.Words('~^wts%s')")
    assert wow.eval(f"{m}.MatchWords(ChatQ.old, 'wts linen', {{}})") is not None
    assert wow.errors == []


def test_notes_and_the_book_search_with_or_and_not(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data", "Bastians_Notes", "Bastians_Strategies")
    wow.execute(
        """
        local Model = Bastians:GetModule('Notes').Model
        ChatQ = { g = { lists = { l1 = { notes = {
          a = { title = 'Wolf den', text = 'grey wolves', created = 1 },
          b = { title = 'Boar camp', text = 'rabid boars', created = 2 },
        } } } } }
        function ChatQ.notes(query)
          local out = {}
          for _, hit in ipairs(Model.Search(ChatQ.g, query)) do out[#out + 1] = hit.note.title end
          table.sort(out)
          return out
        end
        """
    )
    assert list(wow.eval("ChatQ.notes('wolf OR boar')").values()) == ["Boar camp", "Wolf den"]
    assert list(wow.eval("ChatQ.notes('-rabid')").values()) == ["Wolf den"]
    assert list(wow.eval("ChatQ.notes('wolf grey')").values()) == ["Wolf den"]
    book = "Bastians:GetModule('Strategies').Book"
    if wow.eval("Bastians:GetModule('Strategies')") is None:
        return  # the book is Forever's only
    wow.execute(
        f"""
        ChatQ.pages = {{ p1 = {{ name = 'Linen' }}, p2 = {{ name = 'Wool' }} }}
        ChatQ.text = {{ p1 = 'cloth from humanoids', p2 = 'cloth from trolls' }}
        function ChatQ.book(query)
          local out = {{}}
          for _, h in ipairs({book}.Search(ChatQ.pages, query, function(id) return ChatQ.text[id] end)) do
            out[#out + 1] = h.name
          end
          table.sort(out)
          return out
        end
        """
    )
    assert list(wow.eval("ChatQ.book('cloth')").values()) == ["Linen", "Wool"]
    assert list(wow.eval("ChatQ.book('cloth -trolls')").values()) == ["Linen"]
    assert list(wow.eval("ChatQ.book('linen OR wool')").values()) == ["Linen", "Wool"]
    assert wow.errors == []
