"""Core kernel (B2.3): lifecycle, events, bus, Coalesce, error isolation, Jobs, DB, profiles."""

from harness import WowRuntime
from lupa import lua51


def log(app: WowRuntime) -> list[str]:
    return list(app.g.TestLog.values())


def test_lifecycle_runs_in_order_and_exposes_versions(app: WowRuntime):
    assert log(app) == ["init", "enable", "sub-enable"]
    assert app.eval("Bastians.API_VERSION") == 1
    assert app.eval("Bastians.Client") == app.client
    assert app.eval("Bastians:GetModule('TestApp').state") == "enabled"
    assert app.eval("Bastians:GetModule('TestApp.Sub'):IsEnabled()") is True
    assert app.errors == []


def test_events_and_bus_reach_the_module(app: WowRuntime):
    app.fire("TEST_EVENT", 7)
    app.execute("Bastians:GetModule('TestApp'):Fire('TEST_MSG', 'x')")
    assert log(app)[-2:] == ["event:7", "msg:x"]


def test_disable_removes_registrations_and_enable_restores_them(app: WowRuntime):
    app.execute("Bastians:GetModule('TestApp'):Disable()")
    assert log(app)[-2:] == ["sub-disable", "disable"]
    app.fire("TEST_EVENT", 1)
    app.execute("Bastians:Fire('TEST_MSG', 'y')")
    assert log(app)[-1] == "disable"  # nothing reached the module
    assert app.eval("Bastians:GetModule('TestApp').db.profile.enabled") is False
    app.execute("Bastians:GetModule('TestApp'):Enable()")
    assert log(app)[-2:] == ["enable", "sub-enable"]  # the child kept its own switch
    app.fire("TEST_EVENT", 2)
    assert log(app)[-1] == "event:2"


def test_module_state_messages_fire(app: WowRuntime):
    app.execute(
        """
        states = {}
        local probe = Bastians:NewModule("Probe", { addon = "Bastians_TestApp" })
        probe:On("BASTIANS_MODULE_STATE", function(_, _, name, on)
          states[#states + 1] = name .. "=" .. tostring(on)
        end)
        Bastians:GetModule("TestApp.Sub"):Disable()
        """
    )
    assert list(app.g.states.values()) == ["TestApp.Sub=false"]


def test_error_isolation_disables_a_module_after_ten_errors_in_a_minute(app: WowRuntime):
    app.execute(
        """
        otherLog = {}
        local other = Bastians:NewModule("Other", { addon = "Bastians_TestApp" })
        other:RegisterEvent("TEST_EVENT", function(_, _, arg) otherLog[#otherLog + 1] = arg end)
        TestThrow = true
        """
    )
    before = len(app.chat)  # the login's optional-addons line (ADR 0015) came already
    for i in range(10):
        app.fire("TEST_EVENT", i)
    assert app.eval("Bastians:GetModule('TestApp').state") == "enabled"
    app.fire("TEST_EVENT", 10)
    assert app.eval("Bastians:GetModule('TestApp').state") == "disabled"
    assert app.eval("Bastians:GetModule('TestApp').disabledByErrors") is True
    assert app.eval("Bastians:GetModule('TestApp').db.profile.enabled") is True  # session only
    assert len(app.chat) == before + 1 and "disabled after 10 errors" in app.chat[-1]
    assert len(app.g.otherLog) == 11  # the other module kept working
    assert (
        len([line for line in app.eval("Bastians:GetLog()").values() if line.level == "error"])
        == 11
    )
    assert app.errors == []  # nothing escaped to the client's error handler


def test_errors_outside_the_window_do_not_count(app: WowRuntime):
    app.execute("TestThrow = true")
    for i in range(10):
        app.fire("TEST_EVENT", i)
    app.advance(61)
    app.fire("TEST_EVENT", 99)
    assert app.eval("Bastians:GetModule('TestApp').state") == "enabled"


def test_coalesce_runs_once_after_the_last_call(app: WowRuntime):
    app.execute(
        """
        hits = 0
        local m = Bastians:GetModule("TestApp")
        for i = 1, 3 do m:Coalesce("refresh", 0.5, function() hits = hits + 1 end) end
        """
    )
    app.advance(0.4)
    assert app.g.hits == 0
    app.advance(0.2)
    assert app.g.hits == 1
    app.execute(
        "Bastians:GetModule('TestApp'):Coalesce('refresh', 0.5, function() hits = hits + 1 end)"
    )
    app.execute("Bastians:GetModule('TestApp'):Disable()")
    app.advance(1)
    assert app.g.hits == 1  # cancelled by Disable


def test_defaults_are_readable_but_never_saved(app: WowRuntime):
    assert app.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 16
    assert app.eval("Bastians:GetModule('TestApp').db.profile.colors.accent") == "blue"
    assert app.eval("Bastians:GetModule('TestApp.Sub').db.profile.volume") == 5
    app.execute("Bastians:GetModule('TestApp').db.profile.pinSize = 20")
    app.execute("Bastians:GetModule('TestApp').db.char.seen = 3")
    app.execute("Bastians:GetModule('TestApp').db.profile.colors.accent = 'blue'")  # equals default
    fresh = app.reload()
    saved = fresh.saved_variables("Bastians_TestApp")
    assert "pinSize" in saved and "seen" in saved
    assert "accent" not in saved and "volume" not in saved and "installs" not in saved
    assert fresh.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 20
    assert fresh.eval("Bastians:GetModule('TestApp').db.profile.colors.accent") == "blue"
    assert fresh.eval("Bastians:GetModule('TestApp').db.char.seen") == 3


def test_switch_persists_across_reload(app: WowRuntime):
    app.execute("Bastians:GetModule('TestApp.Sub'):Disable()")
    fresh = app.reload()
    assert "sub-enable" not in log(fresh)
    assert fresh.eval("Bastians:GetModule('TestApp.Sub').state") == "initialized"
    assert fresh.eval("Bastians:GetModule('TestApp').state") == "enabled"


def test_profiles_switch_for_the_whole_suite(app: WowRuntime):
    app.execute("Bastians:GetModule('TestApp').db.profile.pinSize = 20")
    app.execute("Bastians:SetProfile('Alt')")
    assert app.eval("Bastians:GetProfile()") == "Alt"
    assert app.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 16
    assert app.eval("Bastians:GetModule('TestApp'):IsEnabled()") is True
    assert log(app)[-4:] == ["sub-disable", "disable", "enable", "sub-enable"]
    app.execute("Bastians:GetModule('TestApp').db.profile.pinSize = 30")
    app.execute("Bastians:SetProfile('Default')")
    assert app.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 20
    assert "Alt" in app.eval("Bastians:GetProfiles()").values()
    fresh = app.reload()
    assert fresh.eval("Bastians:GetProfile()") == "Default"
    assert fresh.eval("Bastians:GetModule('TestApp').db.sv.profiles.Alt.pinSize") == 30


def test_migrations_run_only_for_existing_data(wow: WowRuntime):
    wow.execute(
        "BastiansTestAppDB = { __schema = 1, global = {}, "
        "profiles = { Default = { oldSize = 24 } } }"
    )
    wow.start("Bastians_Core", "Bastians_TestApp")
    assert "migrate2" in log(wow)
    assert wow.eval("Bastians:GetModule('TestApp').db.profile.pinSize") == 24
    assert wow.eval("BastiansTestAppDB.__schema") == 2


def test_fresh_install_skips_migrations(app: WowRuntime):
    assert "migrate2" not in log(app)
    assert app.eval("BastiansTestAppDB.__schema") == 2


def test_jobs_run_across_frames_within_budget(app: WowRuntime):
    app.execute(
        """
        steps = 0
        Mock.cpuStep = 1  -- every debugprofilestop() call costs 1 ms of mock CPU
        job = Bastians.Jobs:Run(Bastians:GetModule("TestApp"), "count", function(yield)
          for i = 1, 10 do steps = i; yield() end
        end, { budgetMs = 4, onDone = function() finished = true end })
        """
    )
    assert app.eval("job:IsDone()") is False
    app.run_frames(1)
    assert 0 < app.g.steps < 10
    app.run_frames(10)
    assert app.g.steps == 10 and app.g.finished is True
    assert app.eval("Bastians.Jobs:Pending()") == 0


def test_jobs_are_cancelled_when_the_owner_is_disabled(app: WowRuntime):
    app.execute(
        """
        steps = 0
        Bastians.Jobs:Run(Bastians:GetModule("TestApp"), "count", function(yield)
          for i = 1, 100 do steps = i; yield() end
        end, { budgetMs = 0 })
        """
    )
    app.run_frames(2)
    app.execute("Bastians:GetModule('TestApp'):Disable()")
    before = app.g.steps
    app.run_frames(5)
    assert app.g.steps == before
    assert app.eval("Bastians.Jobs:Pending()") == 0


def test_job_errors_are_isolated(app: WowRuntime):
    app.execute(
        "Bastians.Jobs:Run(Bastians:GetModule('TestApp'), 'bad', function() error('job boom') end)"
    )
    app.run_frames(2)
    lines = [line.text for line in app.eval("Bastians:GetLog()").values()]
    assert any("job boom" in text for text in lines)
    assert app.errors == []


def test_module_needing_a_newer_core_is_refused(app: WowRuntime):
    result = app.eval(
        "Bastians:NewModule('Future', { addon = 'Bastians_TestApp', apiVersion = 99 })"
    )
    assert result is None
    assert "needs Core API 99" in app.eval("Bastians:GetLog(1)[1].text")


def test_bad_module_definitions_raise(app: WowRuntime):
    for code in (
        "Bastians:NewModule('TestApp', { addon = 'x' })",
        "Bastians:NewModule('Nope.Child', { addon = 'x' })",
        "Bastians:NewModule('NoAddon', {})",
        "Bastians:NewModule('bad name', { addon = 'x' })",
    ):
        try:
            app.execute(code)
        except lua51.LuaError:
            continue
        raise AssertionError(f"expected an error from {code}")


def test_log_ring_buffer_keeps_the_newest_500(app: WowRuntime):
    app.execute("for i = 1, 600 do Bastians:Log(nil, 'info', 'line %d', i) end")
    lines = app.eval("Bastians:GetLog()")
    assert len(lines) == 500
    assert lines[1].text == "line 101" and lines[500].text == "line 600"
    assert app.eval("#Bastians:GetLog(3)") == 3
    assert app.eval("Bastians:GetLog(3)[3].text") == "line 600"


def test_unknown_bus_message_is_logged_once(app: WowRuntime):
    app.execute("Bastians:Fire('BASTIANS_TYPO', 1); Bastians:Fire('BASTIANS_TYPO', 2)")
    warnings = [line for line in app.eval("Bastians:GetLog()").values() if line.level == "warn"]
    assert len(warnings) == 1 and "BASTIANS_TYPO" in warnings[0].text


def test_locale_falls_back_to_the_english_key(app: WowRuntime):
    assert app.eval("Bastians.L['Show on map']") == "Show on map"
    app.execute("Bastians.L:Register('enUS', { ['Show on map'] = 'Show it' })")
    assert app.eval("Bastians.L['Show on map']") == "Show it"
    app.execute("Bastians.L:Register('deDE', { ['Route here'] = 'Hierher' })")
    assert app.eval("Bastians.L['Route here']") == "Route here"
