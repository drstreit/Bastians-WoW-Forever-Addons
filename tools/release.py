"""Release zips (nfr.md "Release", roadmap B11.2, plan C10): one deterministic zip per addon, one
bundle per client, and a boot of the result on the WoW mock.

Usage: python tools/release.py --client forever|retail [--addons-dir addons] [--out build/release]
       [--generated-dir <build root>] [--only Bastians_Core,...] [--stamp 2026-11-03T20:00:00Z]
       [--verify]

Code addons are zipped as they are in `addons/` (the packager on GitHub does the same from a tag;
these zips are the GitHub backup and the way to install without CurseForge). Addons whose TOC lists
a `Generated/` file (the data packs, the Data loader's transform table, the Map's tile table and
Map_Art's overview textures) ship that folder, which only exists after a local pipeline build for
one client, so their zips carry the client in the name, are skipped with a note when the folder is
empty and refused when a generated file names the other client (or none). `--generated-dir` takes
the `Generated/` folders from another build root (`tools/build_client.py --out <root>`), so the
Forever release is built while `addons/` holds the retail files. The bundle
`Bastians-v<Core version>-<client>.zip` holds every zipped addon folder: unzip one file into
`Interface/AddOns`. Zips are byte-identical for the same input (sorted entries, fixed timestamps
and modes); `manifest.json` lists every zip with its sha256, version and the git commit.
Developer-only folders (Bastians_Probe) and addons whose TOC lists no file are never packaged.

`--verify` unzips the result into a temporary AddOns folder and boots it on the WoW mock of
tests/lua as the release client: every file compiles and runs in dependency order, the windows
open and close without a Lua error, every generated entry reached its module, every pack names
this client. The exit code is 1 when a check fails.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from check_toc import parse_toc

ROOT = Path(__file__).resolve().parent.parent
ADDONS_DIR = ROOT / "addons"
CLIENTS = ("forever", "retail")
DEV_ONLY = {"Bastians_Probe"}
DATA_PREFIX = "Bastians_Data_"
GENERATED = "Generated"
BUNDLE = "Bastians"  # the suite's bundle zip is listed under this name
SKIP_SUFFIXES = {".tmp", ".pyc"}
SKIP_NAMES = {".luacheckrc", ".styluaignore", "__pycache__", ".DS_Store", "Thumbs.db"}
DEFAULT_STAMP = (1980, 1, 1, 0, 0, 0)  # the earliest time zip files can hold
# The slash command that opens each app's window; verify opens and closes every installed one.
WINDOW_COMMANDS = {
    "Bastians_Quests": "/bq",
    "Bastians_Gold": "/bgold",
    "Bastians_Browser": "/bb",
    "Bastians_Map": "/bmap",
    "Bastians_Route": "/broute",
    "Bastians_Strategies": "/bbook",
}


class ReleaseError(Exception):
    pass


@dataclass(frozen=True)
class Package:
    addon: str
    version: str
    client: str | None  # set for addons with generated (per-client) files, and for the bundle
    path: Path
    sha256: str
    files: int


Entry = tuple[str, Path]  # (path inside the zip, file on disk)


def is_data_pack(name: str) -> bool:
    return name.startswith(DATA_PREFIX)


def toc_files(folder: Path) -> list[str]:
    toc = folder / f"{folder.name}.toc"
    if not toc.is_file():
        raise ReleaseError(f"{folder.name}: no {toc.name}")
    _, files = parse_toc(toc.read_text(encoding="utf-8"))
    return files


def is_per_client(folder: Path) -> bool:
    """An addon whose TOC lists a Generated/ file ships pipeline output built for one client."""
    return any(f.replace("\\", "/").startswith(GENERATED + "/") for f in toc_files(folder))


# The client name in the first lines of every generated Lua file the pipeline writes: packs ("pack
# quests for retail, build ..."), the empty market stub ("no data in this retail build"), the tile
# table and the overview ("minimap tiles for retail (..."), MapTransforms ("...; retail; from ...")
# and the registered table's own `client = "retail"` field.
CLIENT_MARKS = (
    re.compile(r'client = "(forever|retail)"'),
    re.compile(r"; (forever|retail); "),
    re.compile(r"\bfor (forever|retail)\b"),
    re.compile(r"\bin this (forever|retail) build\b"),
)


def generated_client(path: Path) -> str | None:
    """The client a generated Lua file names in its first lines, or None when it names none."""
    with path.open(encoding="utf-8") as fh:
        head = "".join(fh.readline() for _ in range(8))
    for mark in CLIENT_MARKS:
        found = mark.search(head)
        if found:
            return found.group(1)
    return None


def addon_version(folder: Path) -> str:
    toc = folder / f"{folder.name}.toc"
    if not toc.is_file():
        raise ReleaseError(f"{folder.name}: no {toc.name}")
    meta, _ = parse_toc(toc.read_text(encoding="utf-8"))
    version = meta.get("Version")
    if not version:
        raise ReleaseError(f"{folder.name}: no ## Version in the TOC")
    return version


def shippable(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    return not (any(part in SKIP_NAMES for part in rel.parts) or path.suffix in SKIP_SUFFIXES)


def addon_entries(folder: Path, generated: Path | None) -> list[Entry]:
    """Every file of the addon worth shipping, sorted by its path inside the zip. With a separate
    generated folder, the addon's own Generated/ (built for whatever client) is left out."""
    out: list[Entry] = []
    own = folder / GENERATED
    for p in folder.rglob("*"):
        if not p.is_file() or not shippable(p, folder):
            continue
        if generated is not None and generated != own and own in p.parents:
            continue
        out.append((f"{folder.name}/{p.relative_to(folder).as_posix()}", p))
    if generated is not None and generated != own and generated.is_dir():
        for p in generated.rglob("*"):
            if p.is_file() and shippable(p, generated):
                out.append((f"{folder.name}/{GENERATED}/{p.relative_to(generated).as_posix()}", p))
    return sorted(out)


def zip_name(addon: str, version: str, client: str | None) -> str:
    return f"{addon}-v{version}-{client}.zip" if client else f"{addon}-v{version}.zip"


def write_zip(target: Path, stamp: tuple, entries: list[Entry]) -> str:
    """Write the entries atomically with fixed times and modes; returns the sha256 of the zip."""
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for arcname, p in entries:
            info = zipfile.ZipInfo(arcname, stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, p.read_bytes())
    tmp.replace(target)
    return hashlib.sha256(target.read_bytes()).hexdigest()


def build_zip(
    folder: Path, out: Path, stamp: tuple, client: str | None, generated: Path | None
) -> tuple[Package, list[Entry]]:
    version = addon_version(folder)
    entries = addon_entries(folder, generated)
    target = out / zip_name(folder.name, version, client)
    digest = write_zip(target, stamp, entries)
    return Package(folder.name, version, client, target, digest, len(entries)), entries


def git_commit() -> str | None:
    try:
        return subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except OSError, subprocess.CalledProcessError:
        return None


def parse_stamp(text: str | None) -> tuple:
    if not text:
        return DEFAULT_STAMP
    dt = datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(UTC)
    if dt.year < 1980:
        raise ReleaseError("zip timestamps start at 1980")
    return (dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)


def release(
    client: str,
    addons_dir: Path = ADDONS_DIR,
    out: Path = ROOT / "build" / "release",
    only: set[str] | None = None,
    stamp: tuple = DEFAULT_STAMP,
    generated_dir: Path | None = None,
) -> tuple[list[Package], list[str]]:
    """Zip every releasable addon, then the bundle (when nothing was left out by `only`); returns
    the packages (the bundle last, under the addon name "Bastians") and the notes (skipped folders).
    """
    if client not in CLIENTS:
        raise ReleaseError(f"client must be one of {CLIENTS}")
    if not addons_dir.is_dir():
        raise ReleaseError(f"not a folder: {addons_dir}")
    if generated_dir is not None and not generated_dir.is_dir():
        raise ReleaseError(f"not a folder: {generated_dir}")
    packages, notes, bundle_entries = [], [], []
    for folder in sorted(p for p in addons_dir.iterdir() if p.is_dir()):
        name = folder.name
        if name in DEV_ONLY or not (folder / f"{name}.toc").is_file():
            continue
        if only and name not in only:
            continue
        if not toc_files(folder):
            notes.append(f"{name}: skipped, the TOC lists no file")
            continue
        per_client = is_per_client(folder)
        generated = None
        if per_client:
            generated = (generated_dir / name / GENERATED) if generated_dir else folder / GENERATED
            lua_files = sorted(generated.glob("*.lua")) if generated.is_dir() else []
            if not lua_files:
                notes.append(
                    f"{name}: skipped, no {GENERATED}/*.lua in {generated.parent} "
                    f"(build the {client} packs first)"
                )
                continue
            for lua in lua_files:
                built_for = generated_client(lua)
                if built_for is None:
                    raise ReleaseError(
                        f"{name}/{GENERATED}/{lua.name} names no client in its first lines: "
                        f"not a file this pipeline wrote"
                    )
                if built_for != client:
                    raise ReleaseError(
                        f"{name}/{GENERATED}/{lua.name} was built for {built_for}, not {client}: "
                        f"rebuild the {client} packs first"
                    )
        package, entries = build_zip(folder, out, stamp, client if per_client else None, generated)
        packages.append(package)
        bundle_entries += entries
    manifest = {
        "client": client,
        "commit": git_commit(),
        "created_at": datetime(*stamp, tzinfo=UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packages": [package_entry(p) for p in packages],
    }
    if only is None and packages:
        core = next((p for p in packages if p.addon == "Bastians_Core"), packages[0])
        target = out / zip_name(BUNDLE, core.version, client)
        digest = write_zip(target, stamp, sorted(bundle_entries))
        bundle = Package(BUNDLE, core.version, client, target, digest, len(bundle_entries))
        manifest["bundle"] = package_entry(bundle)
        packages.append(bundle)
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / "manifest.json.tmp"
    tmp.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    tmp.replace(out / "manifest.json")
    return packages, notes


def package_entry(p: Package) -> dict:
    return {
        "addon": p.addon,
        "version": p.version,
        "client": p.client,
        "file": p.path.name,
        "sha256": p.sha256,
        "files": p.files,
    }


# -- verify ---------------------------------------------------------------------------------------


def load_order(install: Path) -> list[str]:
    """The installed addons in dependency order (Dependencies, RequiredDeps and the OptionalDeps
    that are installed), names in alphabetical order where nothing decides."""
    deps: dict[str, list[tuple[str, bool]]] = {}  # name -> (dependency, required)
    for folder in sorted(p for p in install.iterdir() if p.is_dir()):
        toc = folder / f"{folder.name}.toc"
        if not toc.is_file():
            continue
        meta, _ = parse_toc(toc.read_text(encoding="utf-8"))
        wanted = []
        for key, required in (
            ("Dependencies", True),
            ("RequiredDeps", True),
            ("OptionalDeps", False),
        ):
            wanted += [(d.strip(), required) for d in meta.get(key, "").split(",") if d.strip()]
        deps[folder.name] = wanted

    def requires(name: str, seen: set[str]) -> set[str]:
        """Everything `name` needs through hard dependencies, transitively."""
        for dep, required in deps.get(name, ()):
            if required and dep not in seen:
                seen.add(dep)
                requires(dep, seen)
        return seen

    # The Data loader lists its packs as OptionalDeps while they require it: an optional edge that
    # points at an addon which (transitively) requires us is dropped, the hard edge decides the
    # order, as in the client. A cycle through the edges that remain is an error.
    edges = {
        name: [d for d, req in wanted if req or name not in requires(d, set())]
        for name, wanted in deps.items()
    }
    order: list[str] = []

    def visit(name: str, trail: tuple[str, ...]) -> None:
        if name in order or name not in deps:
            return
        if name in trail:
            raise ReleaseError(f"dependency cycle: {' > '.join((*trail, name))}")
        for dep in edges[name]:
            visit(dep, (*trail, name))
        order.append(name)

    for name in deps:
        visit(name, ())
    return order


PACK_NAME = re.compile(r'"Data\.RegisterPack",\s*"(\w+)"')


def verify(packages: list[Package], client: str, work: Path) -> list[str]:
    """Unzip the per-addon zips into work/AddOns and boot them on the WoW mock of tests/lua as this
    client. Returns the problems found (empty when the release boots clean)."""
    lua_tests = ROOT / "tests" / "lua"
    if str(lua_tests) not in sys.path:
        sys.path.insert(0, str(lua_tests))
    from harness import LuaAddonError, WowRuntime

    install = work / "AddOns"
    install.mkdir(parents=True, exist_ok=True)
    expected_packs: dict[str, str] = {}
    for p in packages:
        if p.addon == BUNDLE:
            continue
        with zipfile.ZipFile(p.path) as zf:
            zf.extractall(install)
            for name in zf.namelist():
                if f"/{GENERATED}/" in name and name.endswith(".lua"):
                    found = PACK_NAME.search(zf.read(name).decode("utf-8", "replace"))
                    if found:
                        expected_packs[found.group(1)] = p.addon
    problems: list[str] = []
    wow = WowRuntime(client, addons_dir=install)
    for name in load_order(install):
        try:
            wow.load_addon(name)
        except LuaAddonError as exc:
            problems.append(f"load: {exc}")
    wow.login()
    wow.run_frames(10)
    wow.advance(1)
    if wow.eval("Bastians") is None:
        return [*problems, "Bastians_Core did not create the Bastians global"]
    for addon, command in WINDOW_COMMANDS.items():
        if addon in wow.loaded:
            for _ in range(2):  # open, then close
                try:
                    wow.slash(command)
                except Exception as exc:  # lupa raises its own error class
                    problems.append(f"{command}: {exc}")
                wow.run_frames(2)
    wow.run_frames(5)
    wow.advance(2)
    problems += [f"lua error: {err}" for err in wow.errors]
    problems += [f"listed file missing: {f}" for f in wow.eval("Mock.missingFiles or {}").values()]
    pending = int(wow.eval("#Bastians.deferred"))
    if pending:
        targets = ", ".join(str(e[1]) for e in wow.eval("Bastians.deferred").values())
        problems.append(f"{pending} generated entries never reached their module: {targets}")
    data = wow.eval('Bastians:GetService("data")')
    packs = {} if data is None else {str(k): v for k, v in data.Meta(data).packs.items()}
    for pack_name, addon in sorted(expected_packs.items()):
        if pack_name not in packs:
            problems.append(f"{addon}: pack {pack_name!r} did not register")
        elif packs[pack_name].client not in (None, client):
            problems.append(
                f"{addon}: pack {pack_name!r} was built for {packs[pack_name].client}, not {client}"
            )
    if data is not None:
        for pack_name, built_for in data.Meta(data).foreign.items():
            problems.append(f"pack {pack_name!r} is flagged foreign ({built_for})")
    return problems


# -- CLI ------------------------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="release zips per addon and client (nfr.md)")
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--addons-dir", type=Path, default=ADDONS_DIR)
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "release")
    parser.add_argument(
        "--generated-dir",
        type=Path,
        help="a build root (tools/build_client.py --out) whose Generated/ folders ship instead "
        "of the ones under --addons-dir",
    )
    parser.add_argument("--only", help="comma-separated addon folders (no bundle then)")
    parser.add_argument("--stamp", help="ISO-8601 Z time for the zip entries (default 1980-01-01)")
    parser.add_argument(
        "--verify", action="store_true", help="unzip the result and boot it on the WoW mock"
    )
    args = parser.parse_args(argv)
    try:
        packages, notes = release(
            args.client,
            args.addons_dir,
            args.out,
            {s.strip() for s in args.only.split(",")} if args.only else None,
            parse_stamp(args.stamp),
            args.generated_dir,
        )
    except (ReleaseError, OSError, ValueError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    for note in notes:
        print(f"note: {note}")
    for p in packages:
        print(f"{p.path.name}  {p.files} files  sha256 {p.sha256[:12]}")
    print(f"manifest: {args.out / 'manifest.json'}")
    if args.verify:
        with tempfile.TemporaryDirectory(prefix="bastians-verify-") as tmp:
            problems = verify(packages, args.client, Path(tmp))
        booted = [p.addon for p in packages if p.addon != BUNDLE]
        if problems:
            for problem in problems:
                print(f"verify: {problem}", file=sys.stderr)
            return 1
        print(f"verify: OK, {len(booted)} addons booted on the mock as {args.client}")
    if packages:
        core = next((p for p in packages if p.addon == "Bastians_Core"), packages[0])
        tag = f"{core.addon}-v{core.version}"
        print(
            f"attach to a GitHub release with: gh release upload {tag} {args.out}/*.zip --clobber"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
