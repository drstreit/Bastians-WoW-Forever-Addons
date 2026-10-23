"""Generate API stubs and luacheck globals from Blizzard's generated API documentation.

Source: Blizzard_APIDocumentationGenerated of the `forever` and `live` (retail) branches of
Gethe/wow-ui-source. This is documentation, not a runtime measurement (docs/forever-api.md).

Usage:
  python tools/api_stubs.py fetch    [--cache DIR]   sparse-clone or update both branches
  python tools/api_stubs.py generate [--cache DIR]   write stubs, globals, .luacheckrc, diff report
  python tools/api_stubs.py check    [--cache DIR]   exit 1 if a committed generated file is stale
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/Gethe/wow-ui-source.git"
DOCS_DIR = "Interface/AddOns/Blizzard_APIDocumentationGenerated"
DEFAULT_CACHE = ROOT / ".local" / "wow-ui-source"
BRANCH_FOREVER = "forever"
BRANCH_RETAIL = "live"
BRANCHES = (BRANCH_FOREVER, BRANCH_RETAIL)

GEN_DIR = Path("tests/lua/mock/Generated")
REPORT_PATH = Path("data/api/diff_forever_vs_retail.md")
LUACHECKRC = Path(".luacheckrc")
BEGIN_MARK = "-- BEGIN GENERATED GLOBALS"
END_MARK = "-- END GENERATED GLOBALS"

LUA_KEYWORDS = frozenset(
    {
        "and",
        "break",
        "do",
        "else",
        "elseif",
        "end",
        "false",
        "for",
        "function",
        "if",
        "in",
        "local",
        "nil",
        "not",
        "or",
        "repeat",
        "return",
        "then",
        "true",
        "until",
        "while",
    }
)
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Directories whose files may use API names that only one of the two clients has.
COMPAT_PATHS = ("addons/Bastians_Core/Compat/", "addons/Bastians_Probe/")


class ApiStubsError(Exception):
    """A problem the user can fix (missing cache, git failure)."""


# --------------------------------------------------------------------------- fetch


def git(args: list[str], cwd: Path | None = None) -> str:
    try:
        done = subprocess.run(
            ["git", *args],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        raise ApiStubsError(f"git {' '.join(args)} failed: {detail.strip()}") from exc
    return done.stdout


def read_git_meta(branch_dir: Path) -> dict[str, str]:
    out = git(["log", "-1", "--format=%H%n%cI%n%s"], cwd=branch_dir)
    commit, date, subject = out.rstrip("\n").split("\n", 2)
    return {"commit": commit, "date": date, "subject": subject}


def load_meta(branch_dir: Path) -> dict[str, str]:
    """Commit hash, date and subject of a branch checkout (meta.json wins over git)."""
    meta_file = branch_dir / "meta.json"
    if meta_file.is_file():
        return json.loads(meta_file.read_text(encoding="utf-8"))
    return read_git_meta(branch_dir)


def fetch_branch(cache: Path, branch: str) -> dict[str, str]:
    """Sparse-clone `branch` into cache/branch, or update an existing clone."""
    dest = cache / branch
    if (dest / ".git").is_dir():
        git(["fetch", "--depth", "1", "origin", branch], cwd=dest)
        git(["reset", "--hard", "FETCH_HEAD"], cwd=dest)
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)
        git(
            [
                "clone",
                "--filter=blob:none",
                "--no-checkout",
                "--depth",
                "1",
                "--single-branch",
                "--branch",
                branch,
                REPO_URL,
                str(dest),
            ]
        )
        git(["sparse-checkout", "set", DOCS_DIR], cwd=dest)
        git(["checkout", branch], cwd=dest)
    meta = read_git_meta(dest)
    write_atomic(dest / "meta.json", json.dumps(meta, indent=2, sort_keys=True) + "\n")
    return meta


def cmd_fetch(cache: Path) -> int:
    for branch in BRANCHES:
        meta = fetch_branch(cache, branch)
        print(f"{branch}: {meta['commit']} {meta['date']} {meta['subject']}")
    return 0


# --------------------------------------------------------------------------- parsing


def lua_list(table) -> list:
    """Items of a Lua array table in order; empty for nil."""
    if table is None:
        return []
    return [table[i] for i in range(1, len(table) + 1)]


def as_number(value):
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def load_documentation_tables(docs_dir: Path) -> list:
    """Run every documentation file in a Lua 5.1 runtime and collect the system tables."""
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        COLLECTED = {}
        local function zero() return 0 end
        local meta = {
          __add = zero, __sub = zero, __mul = zero, __div = zero, __mod = zero, __pow = zero,
          __unm = zero, __concat = function() return "" end,
        }
        meta.__index = function() return setmetatable({}, meta) end
        local function deep() return setmetatable({}, meta) end
        Enum = deep()
        Constants = deep()
        APIDocumentation = {
          AddDocumentationTable = function(self, t) COLLECTED[#COLLECTED + 1] = t end,
        }
        """
    )
    for path in sorted(docs_dir.glob("*.lua")):
        try:
            lua.execute(path.read_text(encoding="utf-8-sig"))
        except Exception as exc:  # a broken file must not stop the others
            print(f"skipped {path.name}: {exc}", file=sys.stderr)
    return lua_list(lua.globals().COLLECTED)


def param(entry) -> dict:
    out = {
        "name": str(entry["Name"]),
        "type": str(entry["Type"]),
        "nilable": bool(entry["Nilable"]),
    }
    if entry["InnerType"]:
        out["innerType"] = str(entry["InnerType"])
    return out


def parse_documentation(tables: list) -> dict:
    """Plain data from the collected documentation tables.

    functions: {"C_Map.GetMapInfo": {"args": [...], "returns": [...], "namespace": "C_Map"}}
    events:    {"QUEST_ACCEPTED": {"payload": [...]}}
    enums:     {"TooltipDataType": {"Item": 0}}
    """
    functions, events, enums = {}, {}, {}
    for system in tables:
        namespace = str(system["Namespace"]) if system["Namespace"] else None
        for fn in lua_list(system["Functions"]):
            name = str(fn["Name"])
            key = f"{namespace}.{name}" if namespace else name
            functions[key] = {
                "args": [param(a) for a in lua_list(fn["Arguments"])],
                "returns": [param(r) for r in lua_list(fn["Returns"])],
                "namespace": namespace,
            }
        for ev in lua_list(system["Events"]):
            events[str(ev["LiteralName"])] = {
                "payload": [param(p) for p in lua_list(ev["Payload"])]
            }
        for tbl in lua_list(system["Tables"]):
            if tbl["Type"] != "Enumeration":
                continue
            values = {}
            for field in lua_list(tbl["Fields"]):
                value = as_number(field["EnumValue"])
                if isinstance(value, int | float):
                    values[str(field["Name"])] = value
            enums[str(tbl["Name"])] = values
    return {"functions": functions, "events": events, "enums": enums}


def parse_branch(branch_dir: Path) -> dict:
    docs = branch_dir / DOCS_DIR
    if not docs.is_dir():
        raise ApiStubsError(f"{docs} not found. Run: python tools/api_stubs.py fetch")
    return parse_documentation(load_documentation_tables(docs))


# --------------------------------------------------------------------------- rendering


def lua_str(text: str) -> str:
    out = ['"']
    for byte in text.encode("utf-8"):
        ch = chr(byte)
        if ch in '"\\':
            out.append("\\" + ch)
        elif 32 <= byte < 127:
            out.append(ch)
        else:
            out.append(f"\\{byte:03d}")
    out.append('"')
    return "".join(out)


def lua_key(name: str) -> str:
    if IDENT_RE.match(name) and name not in LUA_KEYWORDS:
        return name
    return f"[{lua_str(name)}]"


def lua_number(value) -> str:
    if isinstance(value, int):
        return str(value)
    return repr(float(value))


def header(sources: list[tuple[str, dict]]) -> str:
    parts = [f"{b} {m['commit']} ({m['subject']})" for b, m in sources]
    return (
        f"-- GENERATED by tools/api_stubs.py from Gethe/wow-ui-source {' and '.join(parts)}, "
        "do not edit\n"
    )


def render_params(items: list[dict]) -> str:
    if not items:
        return "{}"
    lines = ["{"]
    for p in items:
        inner = f", innerType = {lua_str(p['innerType'])}" if "innerType" in p else ""
        lines.append(
            f"        {{ name = {lua_str(p['name'])}, type = {lua_str(p['type'])}, "
            f"nilable = {'true' if p['nilable'] else 'false'}{inner} }},"
        )
    lines.append("      }")
    return "\n".join(lines)


def render_api(data: dict, branch: str, meta: dict) -> str:
    out = [header([(branch, meta)]), "return {\n", "  functions = {\n"]
    for key in sorted(data["functions"]):
        fn = data["functions"][key]
        out.append(f"    [{lua_str(key)}] = {{\n")
        out.append(f"      args = {render_params(fn['args'])},\n")
        out.append(f"      returns = {render_params(fn['returns'])},\n")
        out.append("    },\n")
    out.append("  },\n  events = {\n")
    for key in sorted(data["events"]):
        out.append(f"    [{lua_str(key)}] = {{\n")
        out.append(f"      payload = {render_params(data['events'][key]['payload'])},\n")
        out.append("    },\n")
    out.append("  },\n  enums = {\n")
    for key in sorted(data["enums"]):
        values = data["enums"][key]
        out.append(f"    {lua_key(key)} = {{\n")
        for name in sorted(values):
            out.append(f"      {lua_key(name)} = {lua_number(values[name])},\n")
        out.append("    },\n")
    out.append("  },\n}\n")
    return "".join(out)


def global_names(data: dict) -> set[str]:
    """Global functions and API namespaces (C_*), plus Enum."""
    names = {"Enum"}
    for key, fn in data["functions"].items():
        names.add(fn["namespace"] or key)
    return names


def global_sets(forever: dict, retail: dict) -> dict[str, list[str]]:
    a, b = global_names(forever), global_names(retail)
    return {
        "shared": sorted(a & b),
        "forever_only": sorted(a - b),
        "retail_only": sorted(b - a),
    }


def render_name_list(names: list[str], hdr: str) -> str:
    body = "".join(f"  {lua_str(n)},\n" for n in names)
    return f"{hdr}return {{\n{body}}}\n"


# --------------------------------------------------------------------------- luacheckrc


def wrap_names(names: list[str], indent: str = "  ", width: int = 100) -> list[str]:
    lines, cur = [], indent
    for name in names:
        item = lua_str(name) + ","
        if len(cur) + len(item) + 1 > width and cur.strip():
            lines.append(cur.rstrip())
            cur = indent
        cur += item + " "
    if cur.strip():
        lines.append(cur.rstrip())
    return lines


def render_rc_block(sets: dict[str, list[str]], hdr: str) -> str:
    out = [BEGIN_MARK + "\n", "-- " + hdr.removeprefix("-- ").rstrip("\n") + "\n"]
    for var, key in (
        ("api_shared", "shared"),
        ("api_forever_only", "forever_only"),
        ("api_retail_only", "retail_only"),
    ):
        out.append(f"local {var} = {{\n")
        out.extend(line + "\n" for line in wrap_names(sets[key]))
        out.append("}\n")
    out.append(
        "\n"
        "local function extend(...)\n"
        "  local result = {}\n"
        "  for _, list in ipairs({ ... }) do\n"
        "    for _, name in ipairs(list) do\n"
        "      result[#result + 1] = name\n"
        "    end\n"
        "  end\n"
        "  return result\n"
        "end\n"
        "\n"
        "read_globals = extend(api_shared, handwritten_globals)\n"
        "\n"
        "-- Compat and the probe may touch API that exists on one client only.\n"
    )
    for path in COMPAT_PATHS:
        out.append(
            f'files["{path}"] = {{\n'
            "  read_globals = extend(api_shared, handwritten_globals, "
            "api_forever_only, api_retail_only),\n"
            "}\n"
        )
    out.append(END_MARK + "\n")
    return "".join(out)


def update_luacheckrc(text: str, block: str) -> str:
    """Replace the generated section; add the markers and keep the hand-written globals."""
    begin, end = text.find(BEGIN_MARK), text.find(END_MARK)
    if begin != -1 and end != -1 and begin < end:
        end += len(END_MARK)
        if text[end : end + 1] == "\n":
            end += 1
        return text[:begin] + block + text[end:]
    # First run: turn the hand-written read_globals into `handwritten_globals`.
    if "handwritten_globals" not in text:
        converted, count = re.subn(
            r"^read_globals\s*=\s*\{", "local handwritten_globals = {", text, count=1, flags=re.M
        )
        text = converted if count else text.rstrip("\n") + "\n\nlocal handwritten_globals = {}\n"
    return text.rstrip("\n") + "\n\n" + block


# --------------------------------------------------------------------------- report


def signature(items: list[dict]) -> str:
    if not items:
        return "-"
    parts = []
    for p in items:
        inner = f"<{p['innerType']}>" if "innerType" in p else ""
        parts.append(f"{p['name']}: {p['type']}{inner}{'?' if p['nilable'] else ''}")
    return ", ".join(parts)


def group_by_namespace(keys: list[str], functions: dict) -> list[tuple[str, list[str]]]:
    groups: dict[str, list[str]] = {}
    for key in keys:
        groups.setdefault(functions[key]["namespace"] or "(global)", []).append(key)
    return [(ns, groups[ns]) for ns in sorted(groups)]


def md_escape(text: str) -> str:
    return text.replace("|", "\\|")


def render_report(forever: dict, retail: dict, metas: dict[str, dict]) -> str:
    ff, rf = forever["functions"], retail["functions"]
    only_f = sorted(set(ff) - set(rf))
    only_r = sorted(set(rf) - set(ff))
    common = sorted(set(ff) & set(rf))
    changed = [
        k for k in common if (ff[k]["args"], ff[k]["returns"]) != (rf[k]["args"], rf[k]["returns"])
    ]
    fe, re_ = set(forever["events"]), set(retail["events"])
    fen, ren = set(forever["enums"]), set(retail["enums"])
    out = [
        "# API documentation diff: Forever vs retail\n\n",
        "Generated by `tools/api_stubs.py`, do not edit. Source: "
        "Blizzard_APIDocumentationGenerated of\n"
        "Gethe/wow-ui-source. This is documentation, not runtime: it lists what Blizzard's docs\n"
        "declare, not what the client does.\n\n",
        "| Branch | Commit | Commit date | Build |\n|---|---|---|---|\n",
    ]
    for branch in BRANCHES:
        m = metas[branch]
        out.append(
            f"| `{branch}` | `{m['commit'][:10]}` | {m['date']} | {md_escape(m['subject'])} |\n"
        )
    out.append(
        "\n## Counts\n\n| | Forever | Retail | Both | Only Forever | Only retail |\n"
        "|---|---|---|---|---|---|\n"
    )
    out.append(
        f"| Functions | {len(ff)} | {len(rf)} | {len(common)} | {len(only_f)} | {len(only_r)} |\n"
    )
    out.append(
        f"| Events | {len(fe)} | {len(re_)} | {len(fe & re_)} | "
        f"{len(fe - re_)} | {len(re_ - fe)} |\n"
    )
    out.append(
        f"| Enums | {len(fen)} | {len(ren)} | {len(fen & ren)} | "
        f"{len(fen - ren)} | {len(ren - fen)} |\n"
    )
    out.append(
        f"\nFunctions in both with a different signature: {len(changed)} of {len(common)}.\n"
    )

    for title, keys, funcs in (
        ("Functions only in Forever", only_f, ff),
        ("Functions only in retail", only_r, rf),
    ):
        out.append(f"\n## {title} ({len(keys)})\n\n| Namespace | Functions |\n|---|---|\n")
        for ns, group in group_by_namespace(keys, funcs):
            names = ", ".join(f"`{k.split('.')[-1]}`" for k in group)
            out.append(f"| `{ns}` | {names} |\n")

    out.append(
        f"\n## Signature differences ({len(changed)})\n\n"
        "| Function | Side | Arguments | Returns |\n|---|---|---|---|\n"
    )
    for key in changed:
        for side, fn in (("Forever", ff[key]), ("retail", rf[key])):
            out.append(
                f"| `{key}` | {side} | {md_escape(signature(fn['args']))} | "
                f"{md_escape(signature(fn['returns']))} |\n"
            )

    for title, only in (
        ("Events only in Forever", fe - re_),
        ("Events only in retail", re_ - fe),
    ):
        out.append(f"\n## {title} ({len(only)})\n\n")
        out.append(", ".join(f"`{e}`" for e in sorted(only)) + "\n" if only else "None.\n")
    return "".join(out)


# --------------------------------------------------------------------------- outputs


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(text.encode("utf-8"))
        Path(tmp_name).replace(path)
    except BaseException:
        Path(tmp_name).unlink(missing_ok=True)
        raise


def build_outputs(cache: Path, current_rc: str) -> dict[str, str]:
    """All generated files as {repo-relative posix path: text}."""
    parsed = {b: parse_branch(cache / b) for b in BRANCHES}
    metas = {b: load_meta(cache / b) for b in BRANCHES}
    forever, retail = parsed[BRANCH_FOREVER], parsed[BRANCH_RETAIL]
    both = header([(b, metas[b]) for b in BRANCHES])
    sets = global_sets(forever, retail)
    files = {
        (GEN_DIR / "api_forever.lua").as_posix(): render_api(
            forever, BRANCH_FOREVER, metas[BRANCH_FOREVER]
        ),
        (GEN_DIR / "api_retail.lua").as_posix(): render_api(
            retail, BRANCH_RETAIL, metas[BRANCH_RETAIL]
        ),
        REPORT_PATH.as_posix(): render_report(forever, retail, metas),
    }
    for key in sets:
        files[(GEN_DIR / f"globals_{key}.lua").as_posix()] = render_name_list(sets[key], both)
    files[LUACHECKRC.as_posix()] = update_luacheckrc(current_rc, render_rc_block(sets, both))
    return files


def read_current_rc(root: Path) -> str:
    path = root / LUACHECKRC
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def cmd_generate(cache: Path, root: Path) -> int:
    files = build_outputs(cache, read_current_rc(root))
    for rel, text in sorted(files.items()):
        write_atomic(root / rel, text)
        print(f"wrote {rel}")
    return 0


def cmd_check(cache: Path, root: Path) -> int:
    files = build_outputs(cache, read_current_rc(root))
    stale = []
    for rel, text in sorted(files.items()):
        path = root / rel
        old = path.read_bytes().decode("utf-8") if path.is_file() else None
        if old != text:
            stale.append((rel, old, text))
    if not stale:
        print("API stubs are up to date.")
        return 0
    print("API stubs are stale; run: python tools/api_stubs.py generate")
    for rel, old, new in stale:
        if old is None:
            print(f"  {rel}: missing")
        else:
            a, b = set(old.splitlines()), set(new.splitlines())
            print(f"  {rel}: {len(b - a)} lines added, {len(a - b)} lines removed")
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=("fetch", "generate", "check"))
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE, help="wow-ui-source cache")
    parser.add_argument("--root", type=Path, default=ROOT, help="repo root to write into")
    args = parser.parse_args(argv)
    try:
        if args.command == "fetch":
            return cmd_fetch(args.cache)
        if args.command == "generate":
            return cmd_generate(args.cache, args.root)
        return cmd_check(args.cache, args.root)
    except ApiStubsError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
