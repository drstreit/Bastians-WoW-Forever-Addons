"""Which APIs does a client have? Reads probe P1 (the `_G` and `C_*` dump) and answers for the APIs
the suite uses (roadmap B1.7, forever-api.md).

Usage: python tools/api_check.py data/probe/<dump>.lua [--names C_Map.GetWorldPosFromMapPos ...]
       [--compat] [--markdown]

Without --names the APIs come from the Compat layer (`addons/Bastians_Core/Compat/*.lua`: every
`C_Namespace.Function` and every bare WoW global the wrappers call) plus the names listed in
`docs/forever-api.md`. Output: one line per API, `present` (with the namespace's function count),
`absent` or `namespace missing`; `--markdown` prints rows for forever-api.md.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))

from bastians_build.sources import probe  # noqa: E402

COMPAT = ROOT / "addons" / "Bastians_Core" / "Compat"
API_DOC = ROOT / "docs" / "forever-api.md"
NAME_RE = re.compile(r"\b(C_[A-Z][A-Za-z0-9]*)\.([A-Z][A-Za-z0-9]*)\b")
GLOBAL_RE = re.compile(r"(?<![\w.:])([A-Z][A-Za-z0-9]{3,})\(")
LUA_KEYWORDS = {"CreateFrame", "GetTime", "GetServerTime", "UIParent", "Enum"}


def _items(value: object) -> list:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value[k] for k in sorted(k for k in value if isinstance(k, int))]
    return []


class ApiDump:
    """The P1 result: global function names and the functions of every C_* namespace."""

    def __init__(self, p1: dict):
        self.functions = {str(f) for f in _items(p1.get("functions"))}
        self.namespaces: dict[str, set[str]] = {}
        raw = p1.get("namespaces") or {}
        if isinstance(raw, dict):
            for name, functions in raw.items():
                self.namespaces[str(name)] = {str(f) for f in _items(functions)}
        self.enums = {str(e) for e in _items(p1.get("enums"))}
        self.tables = {str(t) for t in _items(p1.get("tables"))}

    def status(self, api: str) -> str:
        if "." in api:
            namespace, function = api.split(".", 1)
            functions = self.namespaces.get(namespace)
            if functions is None:
                return "namespace missing"
            if function in functions:
                return f"present ({namespace}: {len(functions)} functions)"
            return "absent"
        if api in self.functions:
            return "present"
        if api in self.tables or api in self.namespaces:
            return "present (table)"
        return "absent"


def compat_names() -> set[str]:
    names: set[str] = set()
    for path in sorted(COMPAT.glob("*.lua")):
        text = path.read_text(encoding="utf-8")
        names.update(f"{ns}.{fn}" for ns, fn in NAME_RE.findall(text))
        for match in GLOBAL_RE.findall(text):
            if match not in LUA_KEYWORDS and not match.startswith("C_"):
                names.add(match)
    return names


def doc_names() -> set[str]:
    text = API_DOC.read_text(encoding="utf-8")
    names = {f"{ns}.{fn}" for ns, fn in NAME_RE.findall(text)}
    names.update(m for m in re.findall(r"`([A-Z][A-Za-z0-9]{3,})`", text) if not m.startswith("C_"))
    return names


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dump", type=Path)
    parser.add_argument("--names", nargs="*", help="APIs to check instead of the Compat ones")
    parser.add_argument("--compat", action="store_true", help="only the Compat layer's APIs")
    parser.add_argument("--markdown", action="store_true", help="rows for forever-api.md")
    args = parser.parse_args(argv)
    try:
        dump = probe.read_probe_dump(args.dump)
    except (OSError, ValueError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    p1 = dump.results.get("P1")
    if not isinstance(p1, dict):
        print("error: the dump has no P1 result", file=sys.stderr)
        return 2
    api = ApiDump(p1)
    if args.names:
        names = set(args.names)
    else:
        names = compat_names()
        if not args.compat:
            names |= doc_names()
    label = f"{dump.client or '?'} {dump.build or '?'}"
    print(f"# {len(api.functions)} global functions, {len(api.namespaces)} namespaces ({label})")
    for name in sorted(names):
        status = api.status(name)
        if args.markdown:
            print(f"| `{name}` | {status} | P1, {args.dump.name} |")
        else:
            print(f"{name}: {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
