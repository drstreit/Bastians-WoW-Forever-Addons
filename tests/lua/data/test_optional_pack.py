"""An optional pack without generated data is noted once in the log, however often a consumer
asks for it."""

from harness import WowRuntime


def test_an_optional_pack_without_data_is_logged_once(wow: WowRuntime):
    wow.start("Bastians_Core", "Bastians_Data")
    wow.run_frames(5)
    wow.advance(0.5)
    data = "Bastians:GetService('data')"
    assert wow.eval(f"{data}:PackLoaded('nav')") is False
    for _ in range(3):
        wow.execute(f"{data}:LoadPack('nav')")
    assert wow.eval(f"{data}:PackLoaded('nav')") is False
    lines = [line.text for line in wow.eval("Bastians:GetLog()").values()]
    assert sum("Bastians_Data_Nav has no generated data" in line for line in lines) == 1
    assert wow.errors == []
