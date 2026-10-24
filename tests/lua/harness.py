"""Runs the real addon files on Lua 5.1 (lupa) against the WoW mock in tests/lua/mock (ADR 0006).

A WowRuntime is one game client: it loads addons in TOC order with the `(ADDON, ns)` varargs the
game passes, dispatches events, advances the clock, toggles combat and can `reload()` with the
saved variables written and read back the way WoW does it.
"""

from pathlib import Path

from check_toc import parse_toc
from lupa import lua51

ROOT = Path(__file__).resolve().parents[2]
ADDONS = ROOT / "addons"
MOCK = Path(__file__).with_name("mock")
CLIENTS = ("forever", "retail")
INTERFACES = {"forever": "16001", "retail": "120105"}  # as tools/release.py
SAVED_VARIABLE_KEYS = ("SavedVariables", "SavedVariablesPerCharacter")


class LuaAddonError(Exception):
    """An addon file failed to compile or run."""


class WowRuntime:
    def __init__(
        self, client: str = "forever", addons_dir: Path = ADDONS, extra_dirs: tuple[Path, ...] = ()
    ) -> None:
        if client not in CLIENTS:
            raise ValueError(f"unknown client {client!r}, expected one of {CLIENTS}")
        self.client = client
        self.addons_dir = addons_dir
        self.extra_dirs = tuple(extra_dirs)
        self.dirs = (
            *self.extra_dirs,
            addons_dir,
        )  # a fixture addon replaces a real one of the same name
        self.loaded: list[str] = []
        self.skipped: list[str] = []  # addons not made for this client (their TOC interface)
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.BASTIANS_TEST_CLIENT = client
        self._run_file(MOCK / "wow.lua", "mock/wow.lua")
        self.mock = g.Mock
        self.mock.onAddonLoaded = self._note_loaded
        stubs = MOCK / "Generated" / f"api_{client}.lua"
        self.stub_count = 0
        if stubs.is_file():
            api = self._run_file(stubs, f"mock/Generated/api_{client}.lua")
            self.stub_count = int(self.mock.InstallStubs(api))
        self._register_addons()

    # -- loading -----------------------------------------------------------------------------

    def _compile(self, source: str, chunkname: str):
        """Compile Lua source with a chunk name, so errors point at the real file."""
        result = self.lua.globals().loadstring(source, f"@{chunkname}")
        if isinstance(result, tuple):  # (nil, message) on a syntax error
            raise LuaAddonError(result[1])
        return result

    def _run_file(self, path: Path, chunkname: str):
        return self._compile(path.read_text(encoding="utf-8"), chunkname)()

    def _register_addons(self) -> None:
        """Make every addon folder known to the mock (metadata, load-on-demand flag)."""
        for base in self.dirs:
            for folder in sorted(p for p in base.iterdir() if p.is_dir()):
                toc = folder / f"{folder.name}.toc"
                if not toc.is_file() or folder.name in self.mock.addons:
                    continue
                meta, files = parse_toc(toc.read_text(encoding="utf-8"))
                if base.resolve() == ADDONS.resolve():
                    # the repo's own addons: a locally built Generated/ file (packs, MapTransforms,
                    # MinimapTiles) is machine-specific and never test input; fixtures carry theirs
                    files = [f for f in files if not f.replace("\\", "/").startswith("Generated/")]
                self.mock.addons[folder.name] = self.lua.table(
                    meta=self.lua.table(**meta), files=self.lua.table(*files), dir=str(folder)
                )

    def addon_dir(self, name: str) -> Path:
        for base in self.dirs:
            if (base / name / f"{name}.toc").is_file():
                return base / name
        raise LuaAddonError(f"no addon {name} under {[str(d) for d in self.dirs]}")

    def toc(self, name: str) -> tuple[dict[str, str], list[str]]:
        toc = self.addon_dir(name) / f"{name}.toc"
        return parse_toc(toc.read_text(encoding="utf-8"))

    def made_for(self, name: str) -> bool:
        """Whether the addon's TOC names this client's interface (Gold and the book: Forever)."""
        interfaces = {v.strip() for v in self.toc(name)[0].get("Interface", "").split(",")}
        return interfaces in ({""}, set()) or INTERFACES[self.client] in interfaces

    def needs(self, *names: str) -> None:
        """Skips the test on a client the addons are not made for (no Gold
        and no book on retail)."""
        import pytest

        for name in names:
            if not self.made_for(name):
                pytest.skip(f"{name} is not made for {self.client}")

    def load_addon(self, name: str) -> None:
        """Load one addon's files in TOC order and fire ADDON_LOADED, as the client does (in Lua)."""
        if name in self.loaded:
            return
        self.addon_dir(name)  # a clear error for an unknown addon
        # the client loads only what names its interface (the Strategies book is Forever's only)
        interfaces = {v.strip() for v in self.toc(name)[0].get("Interface", "").split(",")}
        wanted = INTERFACES[self.client]
        if interfaces and interfaces != {""} and wanted not in interfaces:
            self.skipped.append(name)  # the game lists it as incompatible and loads nothing
            return
        try:
            self.mock.LoadAddOnFiles(name)
        except lua51.LuaError as exc:
            raise LuaAddonError(f"{name}: {exc}") from exc

    def _note_loaded(self, name: str) -> None:
        """Called from Lua after an addon's files ran; pure Python, so lupa stays out of trouble."""
        self.loaded.append(str(name))

    def is_load_on_demand(self, name: str) -> bool:
        meta, _ = self.toc(name)
        return meta.get("LoadOnDemand") == "1"

    def login(self) -> None:
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD", True, False)

    def start(self, *addons: str) -> None:
        """Load addons in order and log in: the usual test setup."""
        for name in addons:
            self.load_addon(name)
        self.login()

    # -- driving the mock --------------------------------------------------------------------

    def fire(self, event: str, *args) -> None:
        self.mock.Fire(event, *args)

    def advance(self, seconds: float) -> None:
        self.mock.Advance(seconds)

    def run_frames(self, count: int = 1, dt: float = 1 / 60) -> None:
        self.mock.RunFrames(count, dt)

    def set_combat(self, on: bool) -> None:
        self.mock.SetCombat(on)

    def slash(self, line: str):
        return self.mock.Slash(line)

    def tooltip(self, kind: str, entity_id: int, guid: str | None = None) -> list[dict]:
        kind_value = self.lua.globals().Enum.TooltipDataType[kind]
        lines = self.mock.Tooltip(kind_value, entity_id, guid)
        return [dict(line.items()) for line in lines.values()]

    @property
    def chat(self) -> list[str]:
        return list(self.mock.chat.values())

    @property
    def errors(self) -> list[str]:
        return list(self.mock.errors.values())

    def eval(self, code: str):
        return self.lua.eval(code)

    def execute(self, code: str):
        return self.lua.execute(code)

    @property
    def g(self):
        return self.lua.globals()

    # -- saved variables ---------------------------------------------------------------------

    def saved_variable_names(self, addon: str) -> list[str]:
        meta, _ = self.toc(addon)
        names: list[str] = []
        for key in SAVED_VARIABLE_KEYS:
            names += [n.strip() for n in meta.get(key, "").split(",") if n.strip()]
        return names

    def saved_variables(self, *addons: str) -> str:
        """The saved-variable files of these addons, serialized like WoW writes them."""
        names = [n for a in addons for n in self.saved_variable_names(a)]
        return str(self.mock.SerializeSavedVariables(self.lua.table(*names)))

    def reload(self) -> WowRuntime:
        """Simulate /reload: write saved variables, start a fresh client, read them back, reload."""
        self.fire("PLAYER_LOGOUT")  # the client fires it before writing the files
        saved = self.saved_variables(*self.loaded)
        fresh = WowRuntime(self.client, self.addons_dir, self.extra_dirs)
        fresh.execute(saved)
        fresh.start(*[name for name in self.loaded if not self.is_load_on_demand(name)])
        return fresh
