"""The suite's transport between players (Core Comm.lua, notes.md N3): a serialization that never
runs code, the copyable text form, sending cut into throttled addon messages, and receiving them
back together (in any order) for the app that registered the kind."""

from harness import WowRuntime

C = "Bastians.Comm"

VALUE = """{ name = 'Herbs | of Elwynn: 1', n = 3, f = 0.1, neg = -9460.5, yes = true, no = false,
  notes = { { title = 'Peace', on = { map = 0, wx = -9460, wy = 60 } }, { title = 'Silver' } } }"""


def test_values_go_through_the_serialization_unchanged(core: WowRuntime):
    core.execute(f"V = {VALUE}; S = {C}.Serialize(V); R = {C}.Deserialize(S)")
    assert core.eval(f"{C}.Serialize(R) == S") is True
    r = core.eval("R")
    assert r.name == "Herbs | of Elwynn: 1" and r.f == 0.1 and r.neg == -9460.5
    assert r.yes is True and r.no is False and r.notes[1].on.wx == -9460
    # deterministic: the same value, the same text
    assert core.eval(f"{C}.Serialize({VALUE}) == S") is True


def test_a_damaged_or_hostile_text_is_refused_and_never_run(core: WowRuntime):
    for text, why in (
        ("s5:abc", "bad string"),
        ("nabc;", "bad number"),
        ("ts1:a", "unexpected end"),
        ("TT", "trailing data"),
        ("x", "unknown tag"),
        ("return os.exit()", "unknown tag"),
    ):
        assert core.eval(f"{C}.Deserialize({text!r})") == (None, why), text
    deep = "t" + "s1:at" * 12 + "e" * 13
    assert core.eval(f"{C}.Deserialize('{deep}')") == (None, "too deep")
    assert core.eval(f"select(2, {C}.Deserialize(nil))") == "not a string"


def test_the_text_form_to_copy_and_paste(core: WowRuntime):
    core.execute(f"T = {C}.Encode({VALUE})")
    text = core.eval("T")
    assert text.startswith("!BN1!") and " " not in text
    assert core.eval(f"{C}.Decode(T).notes[2].title") == "Silver"
    assert core.eval(f"{C}.Decode('  ' .. T .. '\\n').n") == 3  # pasted with spaces around
    assert core.eval(f"{C}.Decode('hello')") == (None, "not a Bastian's text")
    assert core.eval(f"{C}.Decode('!BN1!abc')") == (None, "damaged text")


def test_a_long_value_goes_out_in_parts_and_comes_back_whole(core: WowRuntime):
    core.execute(
        """GOT = {}
        local m = Bastians:GetModule("Core") -- enabled from the start (a disabled app gets nothing)
        Bastians.Comm.Register(m, "test.list", function(value, sender, channel)
          GOT[#GOT + 1] = { value = value, sender = sender, channel = channel }
        end)
        BIG = { text = string.rep("abcdefghij", 90) }"""
    )
    assert core.eval(f"{C}.Send('test.list', BIG, 'SHOUT')") == (None, "channel")
    assert core.eval(f"{C}.Send('test.list', BIG, 'WHISPER')") == (None, "target")
    n = core.eval(f"{C}.Send('test.list', BIG, 'PARTY')")
    assert n == 5  # 900 characters and the header, 200 a part
    assert len(core.eval("Mock.addonMessages")) == 1  # the first at once, the rest throttled
    core.advance(2)
    sent = list(core.eval("Mock.addonMessages").values())
    assert len(sent) == 5 and all(m.prefix == "Bastians" and m.channel == "PARTY" for m in sent)
    assert all(len(m.text) <= 255 for m in sent)
    # our own echo is ignored; a friend's parts, in any order, make one value
    core.execute(
        "for _, m in ipairs(Mock.addonMessages) do Bastians.Comm.Receive(m.prefix, m.text, 'PARTY', "
        "'Mockchar-Realm') end"
    )
    assert len(core.eval("GOT")) == 0
    for i in (3, 1, 5, 2, 4):
        core.execute(
            f"local m = Mock.addonMessages[{i}]; "
            "Bastians.Comm.Receive(m.prefix, m.text, 'PARTY', 'Friend-Realm')"
        )
    got = core.eval("GOT")
    assert len(got) == 1 and got[1].sender == "Friend-Realm" and got[1].channel == "PARTY"
    assert core.eval("GOT[1].value.text == BIG.text") is True
    # another prefix or a broken header is no message
    assert core.eval(f"{C}.Receive('Other', '1|1|1/1|test.list|s1:a', 'PARTY', 'X')") is None
    assert core.eval(f"{C}.Receive('Bastians', 'garbage', 'PARTY', 'X')") is None
    assert core.errors == []


def test_a_custom_channel_reaches_only_a_kind_registered_as_public(core: WowRuntime):
    """#20: CHANNEL takes the channel's number; strangers can send there, so a kind that did not
    register as public drops what comes from a channel."""
    core.execute(
        """GOT = {}
        local m = Bastians:GetModule("Core")
        Bastians.Comm.Register(m, "test.private", function(value, sender, channel)
          GOT[#GOT + 1] = "private " .. channel
        end)
        Bastians.Comm.Register(m, "test.public", function(value, sender, channel)
          GOT[#GOT + 1] = "public " .. channel
        end, { public = true })"""
    )
    assert core.eval(f"{C}.Send('test.public', 1, 'CHANNEL')") == (None, "target")
    assert core.eval(f"{C}.Send('test.public', 1, 'CHANNEL', 4)") == 1
    sent = core.eval("Mock.addonMessages[1]")
    assert (sent.channel, sent.target) == ("CHANNEL", 4)
    core.execute(
        f"{C}.Receive('Bastians', '1|9|1/1|test.private|n1;', 'CHANNEL', 'Stranger-Realm')"
        f"; {C}.Receive('Bastians', '1|8|1/1|test.public|n1;', 'CHANNEL', 'Stranger-Realm')"
        f"; {C}.Receive('Bastians', '1|7|1/1|test.private|n1;', 'GUILD', 'Friend-Realm')"
    )
    assert list(core.eval("GOT").values()) == ["public CHANNEL", "private GUILD"]
    # the channel wrappers: joined, kept out of the chat windows, its number, left
    assert core.eval("Bastians.Compat.JoinChannel('BastiansCamp')") == 1
    assert core.eval("Bastians.Compat.ChannelNumber('BastiansCamp')") == 1
    assert core.eval("Bastians.Compat.LeaveChannel('BastiansCamp')") is True
    assert core.eval("Bastians.Compat.ChannelNumber('BastiansCamp')") is None
    assert core.errors == []
