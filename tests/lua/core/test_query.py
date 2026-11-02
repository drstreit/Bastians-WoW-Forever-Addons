"""The one search syntax of the suite: Bastians.Query compiles a box's
text into a query: words, phrases, OR, NOT, groups, wildcards, Lua patterns, fields with numbers
and money, three-valued logic for unknown values, never an error while typing; the world search's
`type:` words; the kit's search box with its keys, tooltip and query look."""

import pytest
from harness import WowRuntime


def test_narrows_says_when_typing_on_keeps_the_rows_within_the_last_ones(wow: WowRuntime):
    """typed on at the end of a filter, a list tests only the rows it kept."""
    wow.start("Bastians_Core")
    fields = "{ fields = { type = {}, level = { kind = 'number' } } }"
    narrows = lambda a, b: wow.eval(f"Bastians.Query.Narrows({a!r}, {b!r}, {fields})")  # noqa: E731
    assert narrows("wol", "wolf") is True
    assert narrows("wolf", "wolf r") is True
    assert narrows("wolf r", "wolf rabid") is True
    assert narrows("type:ven", "type:vendor") is True
    assert narrows("type:vendor aar", "type:vendor aaro") is True
    assert narrows('"den mo', '"den mot') is False  # a broken quote: no shortcut
    assert narrows("wolf", "wolf") is True
    assert narrows("", "wolf") is False
    assert narrows("wolf", "wol") is False  # shorter: wider
    assert narrows("wolf", "wolf -rabid") is False  # NOT widens nothing but is no plain AND
    assert narrows("wolf", "wolf OR boar") is False
    assert narrows("typ", "type:vendor") is False  # a word became a field
    assert narrows("level>3", "level>30") is False  # numbers compare, they do not grow
    assert narrows("heal", "heal*") is False
    assert wow.errors == []


# the test's fields over a record { name, level, price, kind, tags }
FIELDS = """
ChatQ = {}
ChatQ.fields = {
  level = { kind = 'number', get = function(r) return r.level end },
  price = { kind = 'money', get = function(r) return r.price end },
  kind = { get = function(r) return r.kind end },
  tag = { get = function(r) return r.tags end },
  has = { kind = 'flag', get = function(r, v) if v == 'link' then return r.link == true end end },
}
ChatQ.opts = { fields = ChatQ.fields, text = function(r) return r.name end }
function ChatQ.m(query, rec) return Bastians.Query.Compile(query, ChatQ.opts):Match(rec) end
"""


def match(core: WowRuntime, query: str, text: str) -> bool:
    return core.eval(f"Bastians.Query.Compile({query!r}):Match({text!r})")


@pytest.mark.parametrize(
    ("query", "text", "want"),
    [
        ("", "anything", True),  # an empty query matches all
        ("wolf", "Rabid Wolf", True),
        ("wolf den", "the den of the wolf", True),  # every word, any order
        ("wolf den", "a wolf", False),
        ('"den mother"', "the Den Mother", True),
        ('"den mother"', "mother of the den", False),
        ("wolf OR boar", "a boar", True),
        ("wolf | boar", "a boar", True),
        ("wolf or boar", "a boar", False),  # lower case "or" is a word
        ("wolf -rabid", "Grey Wolf", True),
        ("wolf -rabid", "Rabid Wolf", False),
        ("wolf !rabid", "Rabid Wolf", False),
        ("wolf NOT rabid", "Rabid Wolf", False),
        ("wolf AND den", "wolf den", True),
        ("wolf & den", "wolf", False),
        ("(wolf OR boar) -rabid", "rabid boar", False),
        ("(wolf OR boar) -rabid", "old boar", True),
        ("heal*", "healer", True),
        ("b*r", "boar", True),
        ("b*r", "b r", False),  # the wildcard stays inside one word
        ("/^wt[bs]/", "WTS linen", True),
        ("/^wt[bs]/", "I wts", False),
        ("12:30", "meet at 12:30", True),  # an unknown field stays text
        ("wolf-den", "the wolf-den", True),  # a dash inside a word is no NOT
        ("a.b", "axb", False),  # plain words are no patterns
    ],
)
def test_the_syntax(core: WowRuntime, query: str, text: str, want: bool):
    assert match(core, query, text) is want


def test_broken_parts_are_read_and_named_never_raised(core: WowRuntime):
    def compiled(text: str) -> tuple:
        q = core.eval(f"Bastians.Query.Compile({text!r})")
        return q.error, q.empty

    assert compiled('"den mo') == ("quote", False)
    assert match(core, '"den mo', "the den mother")  # read to the end
    assert compiled("(wolf OR boar") == ("bracket", False)
    assert match(core, "(wolf OR boar", "boar")
    assert compiled("wolf)") == ("stray", False)
    assert compiled("/[broken/") == ("pattern", False)
    assert match(core, "/[broken/", "a /[broken/ text")  # read as plain text
    assert compiled("wolf OR") == (None, False)  # while typing
    assert match(core, "wolf OR", "wolf")
    assert compiled("-") == (None, False)
    assert compiled("()") == (None, True)
    assert compiled("   ") == (None, True)


def test_fields_numbers_money_and_flags(core: WowRuntime):
    core.execute(FIELDS)
    rec = "{ name = 'Gnoll Brute', level = 24, price = 12500, kind = 'Hostile', tags = { 'gnoll', 'elite' } }"

    def m(query: str) -> bool:
        return core.eval(f"ChatQ.m({query!r}, {rec})")

    assert m("gnoll level>20")
    assert m("level>=24") and m("level:24") and m("level=24") and m("level:>20")
    assert not m("level<24")
    assert m("level:20..30") and not m("level:25..30")
    assert m("price>1g") and m("price<1g50s") and not m("price>1g50s")
    assert m("price:1g25s") and m("price<2")  # a bare number is gold
    assert m("kind:host") and not m("kind:friendly")
    assert m('kind:"hostile"')
    assert m("tag:elite") and not m("tag:rare")  # a list of texts: any of them
    assert m("-has:link")
    assert m("Level>20")  # field names any case
    assert core.eval("Bastians.Query.ParseMoney('1g 50s 3c')") == 15003
    assert core.eval("Bastians.Query.ParseMoney('lots')") is None


def test_unknown_is_neither_true_nor_false(core: WowRuntime):
    """CLAUDE.md §4.2: an item without a price matches neither price<5g nor its NOT."""
    core.execute(FIELDS)
    nothing = "{ name = 'Odd Stone' }"

    def m(query: str) -> bool:
        return core.eval(f"ChatQ.m({query!r}, {nothing})")

    assert not m("price<5g")
    assert not m("-price<5g")
    assert not m("level>1 OR level<=1")
    assert m("stone OR price<5g")  # a true branch wins over an unknown one
    assert not m("stone price<5g")  # true AND unknown is unknown
    assert not m("-has:other")  # the flag answers nil for what it does not know
    assert m("odd -level>1 OR odd")


def test_scores_for_names(core: WowRuntime):
    def score(query: str, name: str):
        return core.eval(f"Bastians.Query.Compile({query!r}):Score({name!r})")

    assert score("hogger", "Hogger") == 1
    assert score("hog", "Hogger") == 0.9
    assert score("gger", "Hogger") == 0.7
    assert score("gunther weller", "Gunther Weller") == 1
    assert score("wel -x", "Weller") == 0.9
    assert score("x OR eller", "Weller") == 0.6
    assert score("boar", "Hogger") is None


def test_plain_words_and_the_cache(core: WowRuntime):
    q = core.eval("Bastians.Query.Compile('Wolf den')")
    assert q.plain is True and list(q.words.values()) == ["wolf", "den"]
    assert core.eval("Bastians.Query.Compile('wolf -den').plain") is False
    assert list(
        core.eval("Bastians.Query.Compile('wolf -den OR \"big boar\"').words").values()
    ) == [
        "wolf",
        "big boar",
    ]
    assert core.eval("Bastians.Query.Compile('wolf') == Bastians.Query.Compile(' wolf ')")
    assert core.eval(
        "Bastians.Query.Of(Bastians.Query.Compile('wolf')) == Bastians.Query.Compile('wolf')"
    )


def test_the_world_search_reads_type_fields(core: WowRuntime):
    query, types = core.eval("Bastians.ParseSearch('type:npc wel')")
    assert query == "wel" and dict(types) == {"npc": True}
    query, types = core.eval("Bastians.ParseSearch('wel t:items')")
    assert query == "wel" and dict(types) == {"item": True}
    query, types = core.eval("Bastians.ParseSearch('type:nonsense wel')")
    assert query == "type:nonsense wel" and types is None


def test_providers_get_the_compiled_query(app: WowRuntime):
    app.execute(
        """
        local m = Bastians:GetModule('TestApp')
        _G.seen = {}
        Bastians:RegisterSearchProvider(m, { id = 'test.q', label = 'Q', priority = 10,
          search = function(query, limit, yield, q)
            _G.seen.query, _G.seen.q = query, q
            local out = {}
            for i, name in ipairs({ 'Rabid Wolf', 'Grey Wolf', 'Wolf Den' }) do
              local s = q:Score(name)
              if s then out[#out + 1] = { ref = 'npc:' .. i, label = name, score = s } end
            end
            return out
          end })
        _G.got = nil
        Bastians:Search('wolf -rabid type:npc', { limit = 10 }, function(results, done)
          if done then _G.got = results end
        end)
        """
    )
    app.run_frames(10)
    labels = sorted(r.label for r in app.eval("got").values())
    assert labels == ["Grey Wolf", "Wolf Den"]
    assert app.eval("seen.query") == "wolf -rabid"
    assert app.eval("seen.q.plain") is False
    assert app.errors == []


def test_tree_rows_filter_and_highlight_by_the_query(core: WowRuntime):
    rows = "{ { text = 'Rabid Wolf' }, { text = 'Grey Wolf' }, { text = 'Old Boar' } }"
    flat = core.eval(
        f"Bastians.UI.TreeUtil.flatten({rows}, '(wolf OR boar) -rabid', function() return true end)"
    )
    assert [r.text for r in flat.values()] == ["Grey Wolf", "Old Boar"]
    flat = core.eval(
        f"Bastians.UI.TreeUtil.flatten({rows}, 'Wolf OR Boar', function() return true end)"
    )
    assert len(flat) == 3  # the operator's case stays: SetQuery no longer lowers the text
    lit = core.eval("Bastians.UI.TreeUtil.highlight('Grey Wolf and Boar', 'wolf OR boar')")
    assert lit.count("|r") == 2 and "Wolf" in lit and "Boar" in lit


def test_the_search_box_keys_tooltip_and_look(core: WowRuntime):
    core.execute(
        """
        local S = Bastians.UI.Style
        _G.box = S.search(UIParent, 'Search')
        _G.heard = {}
        box:SetScript('OnTextChanged', function(self, user) heard[#heard + 1] = user end)
        box:SetScript('OnKeyDown', function(self, key) _G.appKey = key end)  -- an app's own
        """
    )
    core.execute("box:SetText('grey wolf den')")
    core.execute("Mock.ctrl = true box:GetScript('OnKeyDown')(box, 'BACKSPACE') Mock.ctrl = false")
    core.advance(0)
    assert core.eval("box:GetText()") == "grey wolf "
    assert core.eval("appKey") == "BACKSPACE"  # the app's handler still runs
    assert core.eval("heard[#heard]") is True  # heard as typed (a box searching on typing follows)
    core.execute(
        "box:SetCursorPosition(0) Mock.ctrl = true box:GetScript('OnKeyDown')(box, 'RIGHT') Mock.ctrl = false"
    )
    core.advance(0)
    assert core.eval("box.cursor") == 5
    core.execute("Mock.ctrl = true box:GetScript('OnKeyDown')(box, 'A') Mock.ctrl = false")
    core.advance(0)
    assert core.eval("box.cursor") == 5  # Ctrl+A is the client's select all in a search box
    title, text = core.eval("box.tip(box)")
    assert title == "Search syntax" and "OR" in text
    core.execute("box:SetText('\"open quote')")
    assert core.eval("box.queryError") == "quote"
    title, text = core.eval("box.tip(box)")
    assert "A quote is not closed." in text
    core.execute("box:SetText('fine')")
    assert core.eval("box.queryError") is None
    # a text field is no search: no tooltip, no query look
    core.execute("_G.field = Bastians.UI.Widgets.Edit(UIParent, 'Name') field:SetText('\"x')")
    assert core.eval("field.queryError") is None
    assert core.eval("field.tip(field)") is None
    assert core.errors == []
