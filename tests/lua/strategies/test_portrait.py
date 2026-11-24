"""A creature's round portrait (ADR 0090; book.md "A rare's portrait"): the display is learned
from the client when the creature's model has loaded, one creature after the other on a model
nobody sees; what the client cannot answer is given up and not asked again; a client without the
portrait call is asked nothing."""

from harness import WowRuntime
from test_book_pages import MOD
from test_book_pages import boot as boot_book

P = f"{MOD}.Portrait"

# the game's own call, as the mock's stand-in: the texture remembers whose portrait it is
CALL = """
SetPortraitTextureFromCreatureDisplayID = function(texture, displayID)
  DRAWN = (DRAWN or 0) + 1
  texture:SetTexture("portrait:" .. displayID)
end
KNOWN = {}
PORTRAIT.OnKnown = function(npcID) KNOWN[#KNOWN + 1] = npcID end
T = UIParent:CreateTexture()
"""


def boot(wow: WowRuntime, call: bool = True) -> None:
    boot_book(wow)
    wow.execute(f"PORTRAIT = {P}")
    if call:
        wow.execute(CALL)


def load(wow: WowRuntime, display: int) -> None:
    """The creature on the model has loaded: the client knows its display now."""
    wow.execute(f"local m = {P}.Model(); m.display = {display}; m:GetScript('OnModelLoaded')(m)")


def test_a_client_without_the_call_is_asked_nothing(wow: WowRuntime):
    boot(wow, call=False)
    # the mock stands in for every global of the client's list: take this one away
    wow.execute("SetPortraitTextureFromCreatureDisplayID = nil; T = UIParent:CreateTexture()")
    assert wow.eval(f"{P}.Can()") is False
    assert wow.eval(f"{P}.Set(T, 521)") is False
    assert wow.eval(f"{P}.Model()") is None  # no model was made
    assert wow.errors == []


def test_the_display_comes_when_the_model_has_loaded(wow: WowRuntime):
    boot(wow)
    assert wow.eval(f"{P}.Can()") is True
    assert wow.eval(f"{P}.Set(T, 521)") is False  # not known yet: asked
    model = f"{P}.Model()"
    assert wow.eval(f"{model}.creature") == 521 and wow.eval(f"{model}:IsShown()") is True
    assert wow.eval(f"{model}:GetWidth()") == 1 and wow.eval(f"{model}:GetAlpha()") == 0
    assert wow.eval(f"{P}.Known(521)") is None and wow.eval("#KNOWN") == 0
    load(wow, 3211)
    assert wow.eval(f"{P}.Known(521)") == 3211
    assert wow.eval("KNOWN[1]") == 521
    assert wow.eval(f"{model}:IsShown()") is False  # nothing left to load: the model rests
    assert wow.eval(f"{P}.Set(T, 521)") is True
    assert wow.eval("T:GetTexture()") == "portrait:3211" and wow.eval("DRAWN") == 1
    assert wow.errors == []


def test_creatures_are_taken_in_turn_and_asked_once(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{P}.Ask(1); {P}.Ask(2); {P}.Ask(2); {P}.Ask(3)")
    model = f"{P}.Model()"
    assert wow.eval(f"{model}.creature") == 1
    load(wow, 101)
    assert wow.eval(f"{model}.creature") == 2
    load(wow, 102)
    assert wow.eval(f"{model}.creature") == 3
    load(wow, 103)
    assert list(wow.eval("KNOWN").values()) == [1, 2, 3]
    assert wow.eval(f"{P}.Known(2)") == 102
    # a creature known is not set on the model again
    wow.execute(f"{model}.creature = nil; {P}.Ask(2)")
    assert wow.eval(f"{model}.creature") is None
    assert wow.errors == []


def test_what_the_client_knows_at_once_is_drawn_at_once(wow: WowRuntime):
    boot(wow)
    wow.execute("Mock.displays = { [7] = 700, [9] = 900 }")
    assert wow.eval(f"{P}.Set(T, 7)") is True  # asked and answered in one go
    assert wow.eval("T:GetTexture()") == "portrait:700"
    # one that has to load does not hold up the ones behind it for good
    wow.execute(f"{P}.Ask(8); {P}.Ask(9)")
    assert wow.eval(f"{P}.Known(9)") is None and wow.eval(f"{P}.Model().creature") == 8
    load(wow, 800)
    assert wow.eval(f"{P}.Known(9)") == 900
    assert wow.errors == []


def test_a_creature_that_never_loads_is_given_up(wow: WowRuntime):
    boot(wow)
    wow.execute(f"{P}.Ask(40); {P}.Ask(41)")
    model = f"{P}.Model()"
    assert wow.eval(f"{model}.creature") == 40
    wow.advance(3.1)
    wow.run_frames(2)
    assert wow.eval(f"{P}.Known(40)") is None
    assert wow.eval(f"{model}.creature") == 41  # the next one's turn
    load(wow, 410)
    assert wow.eval(f"{P}.Known(41)") == 410
    # given up for the session: not asked again, and its late answer changes nothing
    wow.execute(f"{model}.creature = nil; {P}.Ask(40)")
    assert wow.eval(f"{model}.creature") is None
    assert wow.eval(f"{P}.Set(T, 40)") is False
    # a model that loaded without a display (0) is given up too
    wow.execute(f"{P}.Ask(42)")
    wow.execute(f"local m = {model}; m:GetScript('OnModelLoaded')(m)")
    assert wow.eval(f"{P}.Known(42)") is None
    assert list(wow.eval("KNOWN").values()) == [41]
    assert wow.errors == []


def test_the_probe_records_what_the_client_answers(wow: WowRuntime):
    """`/bprobe portrait`: per creature a seen and an unseen model, the display at once and when
    loaded, the portrait call's result; the record closes after five seconds."""
    boot(wow)
    wow.execute("Mock.displays = { [521] = 3211 }")
    wow.load_addon("Bastians_Probe")
    wow.fire("ADDON_LOADED", "Bastians_Probe")
    wow.slash("/bprobe portrait")
    out = "BastiansProbeDB.results.portrait"
    assert wow.eval(f"{out}.call") == "function"
    lupos = f"{out}.tests['521']"
    assert wow.eval(f"{lupos}.seen.atOnce") == 3211 and wow.eval(f"{lupos}.unseen.atOnce") == 3211
    assert (
        wow.eval(f"{lupos}.portrait.ok") is True and wow.eval(f"{lupos}.portrait.display") == 3211
    )
    assert wow.eval(f"{lupos}.portrait.texture") == "portrait:3211"
    other = f"{out}.tests['100']"
    assert wow.eval(f"{other}.seen.atOnce") == 0 and wow.eval(f"{other}.portrait") is None
    wow.advance(5.2)
    wow.run_frames(2)
    assert wow.eval(f"{out}.summary.creatures") == 6
    assert wow.eval(f"{out}.summary.seenLoaded") == 1 and wow.eval(f"{out}.summary.portraits") == 1
    assert wow.eval(f"{other}.seen.atEnd") == 0
    assert wow.errors == []
