"""Texture paths in the addon sources keep their backslashes (CLAUDE.md §12, the AHSyncGuide trap).

A Lua string "Interface\\AddOns\\..." whose backslashes were lost on the way into the file (a shell
heredoc, an editor) becomes "InterfaceAddOns..." and silently loads nothing: /bprobe mask tested
"InterfaceAddOnsBastians_Map_ArtGeneratedMasks\\" for two rounds on 22.10.2026. luacheck cannot see
it, because the source no longer holds a backslash at all.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# a quoted string starting with a texture root directly followed by a letter: the separator is gone
LOST = re.compile(r"[\"'](Interface|World|Textures)(?=[A-Za-z])")


def addon_sources():
    for path in sorted((ROOT / "addons").rglob("*.lua")):
        parts = path.relative_to(ROOT).parts
        if "Generated" in parts or "Libs" in parts:
            continue
        yield path


def test_no_texture_path_lost_its_backslashes():
    bad = []
    for path in addon_sources():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if LOST.search(line):
                bad.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
    assert bad == [], "texture paths without separators:\n" + "\n".join(bad)


def test_the_check_sees_a_broken_path():
    assert LOST.search('local P = "InterfaceAddOnsBastians_Map_Art"')
    assert not LOST.search('local P = "Interface\\\\AddOns\\\\Bastians_Map_Art"')
    assert not LOST.search('local P = "World\\\\Minimaps\\\\"')


def test_every_own_texture_exists_and_matches_its_generator():
    """The suite's own textures (tools/make_media.py, R3.3): each path to an addon's Media folder
    names a file that ships, and the files are what the script draws."""
    import subprocess
    import sys

    # the Lua source spells each separator as two backslashes; a path ending in a separator is a
    # constant prefix (GLYPHS .. kind) whose kinds are checked below
    own = re.compile(r"Interface\\\\AddOns\\\\(Bastians_\w+)\\\\Media\\\\((?:\w+\\\\)*)(\w*)")
    found, missing, prefixes = [], [], []
    for path in addon_sources():
        for addon, folder, name in own.findall(path.read_text(encoding="utf-8")):
            rel = folder.replace("\\\\", "/")
            if not name:
                prefixes.append((path, addon, rel))
                continue
            found.append(name)
            files = list((ROOT / "addons" / addon / "Media" / rel).glob(name + ".*"))
            if not files:
                missing.append(f"{path.relative_to(ROOT)}: {addon}/Media/{rel}{name}")
    assert "Arrow" in found  # the pattern sees the paths at all
    assert missing == []

    # every glyph path the code can build (the prefix plus a kind of the KINDS list) is a file that
    # exists and that make_media.py generates
    sys.path.insert(0, str(ROOT / "tools"))
    import make_media

    icons = (ROOT / "addons" / "Bastians_Core" / "UI" / "Icons.lua").read_text(encoding="utf-8")
    block = icons.split("local KINDS = {")[1].split("\n}")[0]
    kinds = re.findall(r'^  "(\w+)",$', block, re.M)
    assert len(kinds) >= 30
    assert any(rel == "Glyphs/" for _, _, rel in prefixes)
    for _, addon, rel in prefixes:
        for kind in kinds:
            assert (ROOT / "addons" / addon / "Media" / rel / f"{kind}.tga").exists(), kind
            assert f"{rel}{kind}.tga" in make_media.FILES, kind
    check = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "make_media.py"), "--check"],
        capture_output=True,
        text=True,
    )
    assert check.returncode == 0, check.stdout
