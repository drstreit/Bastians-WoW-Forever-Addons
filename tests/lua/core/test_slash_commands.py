"""Slash commands are unique across the suite: two addons that register the same command leave it to
chance which one answers (the book took Core's `/bs` on 23.10.2026; it is `/bbook` since)."""

import re
from collections import defaultdict
from pathlib import Path

ADDONS = Path(__file__).resolve().parents[3] / "addons"
SLASH = re.compile(r'^\s*SLASH_(\w+?)(\d+)\s*=\s*"([^"]+)"', re.M)


def commands() -> dict[str, list[str]]:
    seen: dict[str, list[str]] = defaultdict(list)
    for path in sorted(ADDONS.rglob("*.lua")):
        if "Generated" in path.parts:
            continue
        for name, n, command in SLASH.findall(path.read_text(encoding="utf-8")):
            seen[command.lower()].append(f"{path.relative_to(ADDONS).as_posix()}: SLASH_{name}{n}")
    return seen


def test_no_two_addons_share_a_slash_command():
    seen = commands()
    assert "/bs" in seen and "/bbook" in seen  # the scan finds them
    shared = {c: where for c, where in seen.items() if len(where) > 1}
    assert shared == {}, shared
