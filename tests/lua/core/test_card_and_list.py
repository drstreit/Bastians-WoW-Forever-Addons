"""Chat version 3, package V2 (plan-chat-v3.md §8, §9; ADR 0075): the card widget of the look
engine in all four looks, the chat's new theme tokens, and Core's virtual list (only the rows in
view have frames, a row is measured once, a chat list sticks to its end and counts what came
below)."""

from harness import WowRuntime

S = "Bastians.UI.Style"
CORE = "Bastians:GetModule('Core')"
SET = "Bastians.UI.Settings"
PAINTED = f"{S}.painted"
VL = "Bastians.UI.VirtualList"
TOKENS = (
    "tier0",
    "tier1",
    "tier2",
    "tier3",
    "tier4",
    "tier5",
    "cardHot",
    "roleTank",
    "roleHeal",
    "roleDps",
    "offerSell",
    "offerBuy",
)


def boot(wow: WowRuntime) -> WowRuntime:
    wow.start("Bastians_Core")
    wow.run_frames(3)
    return wow


def painted(wow: WowRuntime, region: str):
    return wow.eval(f"{PAINTED}[{region}]")


def is_token(wow: WowRuntime, region: str, token: str) -> bool:
    return wow.eval(f"{PAINTED}[{region}][1] == {S}.C.{token}")


def test_every_theme_names_the_chats_tokens(wow: WowRuntime):
    boot(wow)
    for token in TOKENS:
        assert wow.eval(f"{S}.C.{token}") is not None, token
    assert wow.errors == []


def test_a_card_has_its_plate_edge_and_stripe_in_modern(wow: WowRuntime):
    boot(wow)
    wow.execute(
        f"""
        CardTest = {{}}
        CardTest.c = {S}.card(UIParent, {{ stripe = 'tier0', onClick = function() CardTest.clicked = true end }})
        CardTest.c:SetSize(240, 60)
        """
    )
    c = "CardTest.c"
    assert wow.eval(f"{S}.widgets[{c}]") == "card"
    assert wow.eval(f"{c}.face:IsShown()") is True
    assert is_token(wow, f"{c}.face", "card") and painted(wow, f"{c}.face")[2] == 1
    assert is_token(wow, f"{c}.edges", "cardEdge")
    assert wow.eval(f"{c}.stripe:IsShown()") is True and is_token(wow, f"{c}.stripe", "tier0")
    # the body is the owner's, inside the padding and the stripe
    assert wow.eval(f"{c}.body ~= nil")
    wow.execute(f"{c}:Click()")
    assert wow.eval("CardTest.clicked") is True
    # hover lights a card that can be clicked
    wow.execute(f"{c}:GetScript('OnEnter')({c})")
    assert is_token(wow, f"{c}.face", "hover")
    wow.execute(f"{c}:GetScript('OnLeave')({c})")
    assert is_token(wow, f"{c}.face", "card")
    # fresh: the edge in cardHot; flat: no plate, no edge; no stripe: none drawn
    wow.execute(f"{c}:SetCard({{ stripe = 'tier3', hot = true }})")
    assert is_token(wow, f"{c}.edges", "cardHot") and is_token(wow, f"{c}.stripe", "tier3")
    wow.execute(f"{c}:SetCard({{ flat = true }})")
    assert wow.eval(f"{c}.face:IsShown()") is False
    assert painted(wow, f"{c}.edges")[2] == 0
    assert wow.eval(f"{c}.stripe:IsShown()") is False
    assert wow.errors == []


def test_the_card_in_every_theme(wow: WowRuntime):
    """One look (ADR 0084): a card's plate and edge are the theme's tokens in every theme, the
    fresh one's edge in `cardHot`. ~~WoW's gilt edge, Glass's plate and sheen, Parchment's sepia
    edge~~ (until 20.11.2026)."""
    boot(wow)
    wow.execute(f"CardTest = {{ c = {S}.card(UIParent, {{ stripe = 'tier1' }}) }}")
    c = "CardTest.c"
    for theme in ("folio", "parchment", "teal"):
        wow.execute(f"{S}.ApplyTheme('{theme}'); {S}.ApplyLook()")
        wow.execute(f"{c}:SetCard({{ stripe = 'tier1' }})")
        assert is_token(wow, f"{c}.face", "card") and painted(wow, f"{c}.face")[2] == 1, theme
        assert is_token(wow, f"{c}.edges", "cardEdge") and painted(wow, f"{c}.edges")[2] == 1, theme
        wow.execute(f"{c}:SetCard({{ stripe = 'tier1', hot = true }})")
        assert is_token(wow, f"{c}.edges", "cardHot"), theme
        assert wow.eval(f"{c}.sheen") is None, theme  # no glass any more
    assert wow.errors == []


def test_the_span_is_the_rows_a_view_shows(wow: WowRuntime):
    boot(wow)
    tops, hs = "{ 0, 20, 40, 60 }", "{ 20, 20, 20, 20 }"
    assert list(wow.eval(f"{{ {VL}.Span({tops}, {hs}, 25, 30) }}").values()) == [2, 3]
    assert list(wow.eval(f"{{ {VL}.Span({tops}, {hs}, 0, 200) }}").values()) == [1, 4]
    assert list(wow.eval(f"{{ {VL}.Span({tops}, {hs}, 60, 20) }}").values()) == [4, 4]
    assert wow.eval(f"{VL}.Span({{}}, {{}}, 0, 100)") is None
    assert wow.eval(f"{VL}.Span({tops}, {hs}, 0, 0)") is None


LIST = f"""
ListTest = {{ fills = 0, made = 0, below = {{}} }}
ListTest.parent = CreateFrame("Frame", nil, UIParent)
ListTest.parent:SetSize(210, 100)
ListTest.parent:SetPoint("CENTER")
ListTest.kinds = {{
  line = {{
    make = function(parent)
      ListTest.made = ListTest.made + 1
      local f = CreateFrame("Frame", nil, parent)
      f.text = f:CreateFontString(nil, "ARTWORK")
      return f
    end,
    fill = function(f, item, width)
      ListTest.fills = ListTest.fills + 1
      f.text:SetText(item.text)
      return item.tall and 40 or 20
    end,
  }},
}}
function ListTest.items(n, from)
  local out = {{}}
  for i = 1, n do out[i] = {{ kind = "line", text = "line " .. ((from or 0) + i) }} end
  return out
end
function ListTest.new(opts)
  opts.kinds = ListTest.kinds
  opts.onBelow = function(n) table.insert(ListTest.below, n) end
  ListTest.list = {VL}.New(ListTest.parent, opts)
  -- the mock lays out no anchors: the scroll frame gets the size the client would give it
  ListTest.list.scroll:SetSize(200, 100)
  return ListTest.list
end
"""


def test_only_the_rows_in_view_have_frames_and_a_row_is_measured_once(wow: WowRuntime):
    boot(wow)
    wow.execute(LIST)
    wow.execute("ListTest.new({ gap = 2 }); ListTest.list:SetItems(ListTest.items(100))")
    lst = "ListTest.list"
    assert wow.eval(f"{lst}.total") == 100 * 20 + 99 * 2
    rows = list(wow.eval(f"{lst}:Rows()").values())
    assert 4 <= len(rows) <= 10  # a 100 px view of 22 px rows, two more at each edge
    assert rows[0].text.GetText(rows[0].text) == "line 1"
    measured = wow.eval("ListTest.fills")
    wow.execute(f"{lst}:Layout()")  # the same width: no row is measured again
    assert wow.eval("ListTest.fills") - measured == len(rows)  # only the rows in view filled
    # scrolled to the middle, the same few frames show other items (pooled)
    made = wow.eval("ListTest.made")
    wow.execute(f"{lst}.bar.ScrollTo(1000)")
    texts = [r.text.GetText(r.text) for r in wow.eval(f"{lst}:Rows()").values()]
    assert "line 46" in texts
    assert wow.eval("ListTest.made") <= made + 2
    # an item that grew is measured again and moves those below it
    wow.execute(f"local it = {lst}.items[3]; it.tall = true; {lst}:Invalidate(it)")
    assert wow.eval(f"{lst}.tops[4]") == 20 + 2 + 20 + 2 + 40 + 2
    assert wow.errors == []


def test_a_chat_list_sticks_to_its_end_and_counts_what_came_below(wow: WowRuntime):
    boot(wow)
    wow.execute(LIST)
    wow.execute("ListTest.new({ stick = true }); ListTest.list:SetItems(ListTest.items(30))")
    lst = "ListTest.list"
    assert wow.eval(f"{lst}:AtEnd()") is True
    assert wow.eval(f"{lst}:Offset()") == 30 * 20 - 100
    wow.execute(f"{lst}:Append({{ kind = 'line', text = 'new one' }})")
    assert wow.eval(f"{lst}:Offset()") == 31 * 20 - 100  # still at the end
    rows = list(wow.eval(f"{lst}:Rows()").values())
    assert rows[-1].text.GetText(rows[-1].text) == "new one"
    # the player scrolls up: the list stays where it is and counts the new rows
    wow.execute(f"{lst}.bar.ScrollTo(0)")
    assert wow.eval(f"{lst}.stuck") is False
    wow.execute(
        f"{lst}:Append({{ kind = 'line', text = 'a' }}); {lst}:Append({{ kind = 'line', text = 'b' }})"
    )
    assert wow.eval(f"{lst}:Offset()") == 0
    assert list(wow.eval("ListTest.below").values())[-2:] == [1, 2]
    # back at the end: stuck again, the count goes to 0
    wow.execute(f"{lst}:ScrollToEnd()")
    assert wow.eval(f"{lst}.stuck") is True and list(wow.eval("ListTest.below").values())[-1] == 0
    assert wow.errors == []


def test_a_short_chat_lies_at_the_foot_and_a_long_one_is_trimmed(wow: WowRuntime):
    boot(wow)
    wow.execute(LIST)
    wow.execute(
        "ListTest.new({ stick = true, bottomUp = true, max = 10 }); ListTest.list:SetItems(ListTest.items(2))"
    )
    lst = "ListTest.list"
    rows = list(wow.eval(f"{lst}:Rows()").values())
    # two 20 px rows in a 100 px view: the first starts 60 px down
    point = wow.eval(f"{{ {lst}:Rows()[1]:GetPoint(1) }}")
    assert list(point.values())[4] == -60
    assert len(rows) == 2
    for n in range(62):
        wow.execute(f"{lst}:Append({{ kind = 'line', text = 'x{n}' }})")
    assert wow.eval(f"#{lst}.items") <= 10 + wow.eval(f"{VL}.TRIM")
    rows = list(wow.eval(f"{lst}:Rows()").values())
    assert rows[-1].text.GetText(rows[-1].text) == "x61"
    assert wow.errors == []


def test_a_list_that_does_not_stick_keeps_the_readers_place(wow: WowRuntime):
    boot(wow)
    wow.execute(LIST)
    wow.execute("ListTest.new({}); ListTest.list:SetItems(ListTest.items(50))")
    lst = "ListTest.list"
    assert wow.eval(f"{lst}:Offset()") == 0
    wow.execute(f"{lst}.bar.ScrollTo(205)")  # line 11, 5 px into it
    top = wow.eval(f"{{ {lst}:TopItem() }}")
    assert list(top.values())[1] == 5
    anchor = wow.eval(f"{lst}:TopItem().text")
    # three new items above: the line that was at the top stays at the top
    wow.execute(
        f"local items = ListTest.items(3, 900); for _, it in ipairs({lst}.items) do items[#items + 1] = it end; "
        f"{lst}:SetItems(items)"
    )
    assert wow.eval(f"{lst}:TopItem().text") == anchor
    assert wow.eval(f"{lst}:Offset()") == 205 + 60
    assert wow.errors == []
