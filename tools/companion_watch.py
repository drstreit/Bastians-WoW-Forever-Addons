"""The companions' watch (plan-second-wave.md S4, "a regular job looking at these
files and extracting into our node as reference, daily"; decision E: Spoken, "an addon we depend
100% on", checked every day).

Usage: python tools/companion_watch.py [--client forever|retail|all] [--today YYYY-MM-DD]
       python tools/companion_watch.py --diff <old.json> <new.json>

Reads the companion addons listed in `tools/companions.toml` from the clients' `Interface/AddOns`
folders (`[companions]` in `.local/install.toml`, else `[clients]`; the launch client first) and
writes, for each addon, what it is and what changed:

- a snapshot `.local/companions/<client>/<folder>/<date>.json` (the TOC fields, the code files with
  sizes and hashes, the public surface: `function Addon:Name`, top-level globals, slash commands,
  addon-message prefixes; the README's first lines), written only when it differs from the newest
  one there, so the folder is the addon's history;
- the reference page `docs/reference/companions/<folder>.md`: the current state per client and a
  dated change log (the page's earlier entries are kept);
- `.local/companions/ALERT.md` when a **required** companion is missing, below its `min` version or
  answers another API version than expected; the file is removed when nothing is wrong.

`daily_lines(root, today)` is the step `tools/daily.py` runs first in the 18:05 chain: one line
per addon that changed, a loud line for every alert, and "review <bridge files>" for a changed
addon one of our bridges reads. It reads files only, never the game, never the network, and never
stops the daily run: an error there is one line in the report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "tools" / "companions.toml"
INSTALL = ROOT / ".local" / "install.toml"
SNAPSHOTS = ROOT / ".local" / "companions"
PAGES = ROOT / "docs" / "reference" / "companions"
ALERT = SNAPSHOTS / "ALERT.md"
CODE_SUFFIXES = {".lua", ".toc", ".xml"}
# embedded libraries are not the addon's surface (their files still count and hash)
LIB_DIRS = {"libs", "lib", "libraries", "embeds", "ace3"}
README_LINES = 3
CHANGELOG_HEADING = "## Changes"
TOC_FIELDS = {
    "Version": "version",
    "Interface": "interface",
    "Dependencies": "deps",
    "RequiredDeps": "deps",
    "OptionalDeps": "optdeps",
    "SavedVariables": "saved",
    "Title": "title",
    "Notes": "notes",
}
SURFACE_RE = [
    re.compile(r"^\s*function\s+([A-Z][A-Za-z0-9_]*[:.][A-Za-z0-9_]+)\s*\(", re.M),
    re.compile(r"^([A-Z][A-Za-z0-9_]*)\s*=\s*(?!=)", re.M),
]
SLASH_RE = re.compile(r'^\s*SLASH_[A-Z0-9_]+\d\s*=\s*"(/[^"]+)"', re.M)
PREFIX_RE = re.compile(r'RegisterAddonMessagePrefix\(\s*"([^"]+)"\s*\)')


@dataclass
class Companion:
    folder: str
    required: bool = False
    min: str | None = None
    api_file: str | None = None
    api_var: str | None = None
    api_value: int | None = None
    bridge: list[str] = field(default_factory=list)
    about: str = ""


@dataclass
class Report:
    lines: list[str] = field(default_factory=list)
    alerts: list[str] = field(default_factory=list)
    changed: list[str] = field(default_factory=list)


# -- the configuration ----------------------------------------------------------------------------


def load_companions(path: Path = CONFIG) -> list[Companion]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    out = []
    for row in data.get("companion", []):
        api = row.get("api") or {}
        out.append(
            Companion(
                folder=row["folder"],
                required=bool(row.get("required", False)),
                min=row.get("min"),
                api_file=api.get("file"),
                api_var=api.get("var"),
                api_value=api.get("value"),
                bridge=list(row.get("bridge", [])),
                about=row.get("about", ""),
            )
        )
    return out


def client_folders(install: Path = INSTALL) -> dict[str, Path]:
    """client key -> its Interface/AddOns folder: install.toml [companions], else [clients]."""
    if not install.is_file():
        return {}
    data = tomllib.loads(install.read_text(encoding="utf-8"))
    clients = data.get("companions") or data.get("clients") or {}
    out = {}
    for key in ("forever", "retail"):
        if key in clients:
            out[key] = Path(clients[key]) / "Interface" / "AddOns"
    for key, value in clients.items():
        out.setdefault(key, Path(value) / "Interface" / "AddOns")
    return out


# -- reading an addon -----------------------------------------------------------------------------


def version_key(v: str | None) -> tuple[int, ...]:
    return tuple(int(n) for n in re.findall(r"\d+", v or ""))


def read_toc(folder: Path) -> dict:
    """The addon's main TOC (the file named after the folder, else the first .toc)."""
    toc = folder / f"{folder.name}.toc"
    if not toc.is_file():
        tocs = sorted(folder.glob("*.toc"))
        if not tocs:
            return {}
        toc = tocs[0]
    out: dict = {"toc": toc.name}
    for line in toc.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^##\s*([A-Za-z-]+)\s*:\s*(.*)$", line)
        if m and m.group(1) in TOC_FIELDS:
            key = TOC_FIELDS[m.group(1)]
            value = m.group(2).strip()
            if key in ("deps", "optdeps", "saved"):
                out.setdefault(key, [])
                out[key] += [v.strip() for v in value.split(",") if v.strip()]
            else:
                out[key] = value
    for key in ("deps", "optdoeps", "saved"):
        if key in out:
            out[key] = sorted(set(out[key]))
    return out


def read_surface(folder: Path) -> dict:
    functions: set[str] = set()
    commands: set[str] = set()
    prefixes: set[str] = set()
    for path in sorted(folder.rglob("*.lua")):
        if any(part.lower() in LIB_DIRS for part in path.relative_to(folder).parts[:-1]):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for rx in SURFACE_RE:
            functions.update(rx.findall(text))
        commands.update(SLASH_RE.findall(text))
        prefixes.update(PREFIX_RE.findall(text))
    functions = {f for f in functions if not f.startswith(("SLASH_", "BINDING_"))}
    return {
        "functions": sorted(functions),
        "commands": sorted(commands),
        "prefixes": sorted(prefixes),
    }


def read_api_value(folder: Path, companion: Companion) -> int | None:
    if not (companion.api_file and companion.api_var):
        return None
    path = folder / companion.api_file
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(re.escape(companion.api_var) + r"\s*=\s*(\d+)", text)
    return int(m.group(1)) if m else None


def snapshot(folder: Path, companion: Companion, client: str) -> dict | None:
    """What the addon is now, or None when the folder is missing."""
    if not folder.is_dir():
        return None
    files: dict[str, list] = {}
    other_files = other_bytes = 0
    for path in sorted(folder.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(folder).as_posix()
        if path.suffix.lower() in CODE_SUFFIXES or path.name.lower() == "readme.md":
            data = path.read_bytes()
            files[rel] = [len(data), hashlib.sha1(data).hexdigest()[:12]]
        else:
            other_files += 1
            other_bytes += path.stat().st_size
    readme = folder / "README.md"
    head = []
    if readme.is_file():
        for line in readme.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("<!--"):
                head.append(line[:200])
            if len(head) >= README_LINES:
                break
    return {
        "folder": folder.name,
        "client": client,
        **read_toc(folder),
        "files": files,
        "other_files": other_files,
        "other_bytes": other_bytes,
        "surface": read_surface(folder),
        "api_value": read_api_value(folder, companion),
        "readme": head,
    }


# -- comparing ------------------------------------------------------------------------------------


def diff(old: dict | None, new: dict | None) -> list[str]:
    """Human lines of what changed between two snapshots; empty when nothing did."""
    if old is None and new is None:
        return []
    if old is None:
        return [f"new: {new.get('version', '?')}"]
    if new is None:
        return ["missing: the folder is gone"]
    out = []
    for key, label in (("version", "version"), ("interface", "interface"), ("api_value", "API")):
        if old.get(key) != new.get(key):
            out.append(f"{label} {old.get(key, '?')} -> {new.get(key, '?')}")
    for key in ("deps", "optdeps", "saved"):
        a, b = set(old.get(key, [])), set(new.get(key, []))
        if a != b:
            out.append(
                f"{key}: "
                + ", ".join([f"+{x}" for x in sorted(b - a)] + [f"-{x}" for x in sorted(a - b)])
            )
    of, nf = old.get("files", {}), new.get("files", {})
    added, removed = sorted(set(nf) - set(of)), sorted(set(of) - set(nf))
    changed = sorted(k for k in set(of) & set(nf) if of[k] != nf[k])
    if added:
        out.append(
            f"+{len(added)} files: " + ", ".join(added[:8]) + (" ..." if len(added) > 8 else "")
        )
    if removed:
        out.append(
            f"-{len(removed)} files: "
            + ", ".join(removed[:8])
            + (" ..." if len(removed) > 8 else "")
        )
    if changed:
        out.append(
            f"{len(changed)} files changed: "
            + ", ".join(changed[:8])
            + (" ..." if len(changed) > 8 else "")
        )
    os_, ns_ = old.get("surface", {}), new.get("surface", {})
    for key, label in (
        ("functions", "functions"),
        ("commands", "commands"),
        ("prefixes", "message prefixes"),
    ):
        a, b = set(os_.get(key, [])), set(ns_.get(key, []))
        plus, minus = sorted(b - a), sorted(a - b)
        if plus or minus:
            out.append(
                f"{label}: "
                + ", ".join([f"+{x}" for x in plus[:10]] + [f"-{x}" for x in minus[:10]])
                + (" ..." if len(plus) + len(minus) > 10 else "")
            )
    return out


def newest_snapshot(folder: Path) -> tuple[Path | None, dict | None]:
    files = sorted(folder.glob("*.json")) if folder.is_dir() else []
    if not files:
        return None, None
    return files[-1], json.loads(files[-1].read_text(encoding="utf-8"))


def same(a: dict | None, b: dict | None) -> bool:
    if a is None or b is None:
        return a is b
    strip = {"client"}
    return {k: v for k, v in a.items() if k not in strip} == {
        k: v for k, v in b.items() if k not in strip
    }


def rules(companion: Companion, snap: dict | None, client: str) -> list[str]:
    """The alerts of a required companion on this client."""
    if not companion.required:
        return []
    name = companion.folder
    if snap is None:
        # the companions ship for Forever (core.md); retail has none since 29.10.2026
        return [f"{name} is missing on {client}"] if client == "forever" else []
    out = []
    if companion.min and version_key(snap.get("version")) < version_key(companion.min):
        out.append(f"{name} {snap.get('version', '?')} on {client} is older than {companion.min}")
    if companion.api_value is not None and snap.get("api_value") != companion.api_value:
        out.append(
            f"{name} on {client} answers API {snap.get('api_value')}, "
            f"the suite expects {companion.api_value}"
        )
    return out


# -- writing --------------------------------------------------------------------------------------


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(text.encode("utf-8"))
    tmp.replace(path)


def page_changes(path: Path) -> str:
    """The change log the page already has (its text after the heading), or ''."""
    if not path.is_file():
        return ""
    text = path.read_text(encoding="utf-8")
    i = text.find(CHANGELOG_HEADING)
    return text[i + len(CHANGELOG_HEADING) :].strip("\n") if i >= 0 else ""


def render_page(
    companion: Companion, states: dict[str, dict | None], changes: str, today: str
) -> str:
    lines = [f"# {companion.folder}", ""]
    lines.append(
        f"*Written by `tools/companion_watch.py` (plan-second-wave.md S4); last run {today}. "
        f"Facts read from the clients' AddOns folders; nothing here is verified in game.*"
    )
    if companion.about:
        lines += ["", companion.about]
    if companion.required:
        lines += [
            "",
            f"**Required** by the suite: at least {companion.min or '?'}"
            + (f", API {companion.api_value}" if companion.api_value is not None else "")
            + ".",
        ]
    if companion.bridge:
        lines += ["", "Read by: " + ", ".join(f"`{b}`" for b in companion.bridge)]
    lines += [
        "",
        "## State",
        "",
        "| Client | Version | Interface | API | Code files | Other files | Commands | Prefixes |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for client, snap in states.items():
        if snap is None:
            lines.append(f"| {client} | missing | | | | | | |")
            continue
        other = (
            f"{snap['other_files']} ({snap['other_bytes'] // 1024} KB)"
            if snap["other_files"]
            else "0"
        )
        api = snap.get("api_value")
        cells = [
            client,
            str(snap.get("version", "?")),
            str(snap.get("interface", "?")),
            "" if api is None else str(api),
            str(len(snap["files"])),
            other,
            ", ".join(snap["surface"]["commands"]),
            ", ".join(snap["surface"]["prefixes"]),
        ]
        lines.append("| " + " | ".join(cells) + " |")
    for client, snap in states.items():
        if snap and snap.get("readme"):
            lines += ["", f"README ({client}): " + " / ".join(snap["readme"])]
        if snap:
            fns = snap["surface"]["functions"]
            lines += [
                "",
                f"Public surface ({client}, {len(fns)} names): "
                + ", ".join(f"`{f}`" for f in fns[:60])
                + (" ..." if len(fns) > 60 else ""),
            ]
            break
    lines += ["", CHANGELOG_HEADING, ""]
    if changes:
        lines.append(changes)
    return "\n".join(lines).rstrip("\n") + "\n"


# -- the run --------------------------------------------------------------------------------------


def watch(
    clients: dict[str, Path],
    companions: list[Companion],
    *,
    snapshots: Path = SNAPSHOTS,
    pages: Path = PAGES,
    alert: Path = ALERT,
    today: str | None = None,
) -> Report:
    today = today or datetime.now(UTC).strftime("%Y-%m-%d")
    report = Report()
    for companion in companions:
        states: dict[str, dict | None] = {}
        entries: list[str] = []
        review = False
        for client, addons in clients.items():
            snap = snapshot(addons / companion.folder, companion, client)
            states[client] = snap
            _, previous = newest_snapshot(snapshots / client / companion.folder)
            what = diff(previous, snap)
            if previous is None and snap is None:
                continue  # never there, nothing to say
            if what and not same(previous, snap):
                if snap is not None:
                    write_atomic(
                        snapshots / client / companion.folder / f"{today}.json",
                        json.dumps(snap, indent=1, sort_keys=True) + "\n",
                    )
                report.changed.append(f"{companion.folder}@{client}")
                head = f"{companion.folder} ({client}): " + "; ".join(what)
                report.lines.append(("! " if companion.required else "  ") + head)
                entries.append(f"- {today}, {client}: " + "; ".join(what))
                surface_changed = any(
                    w.startswith(("functions", "commands", "prefixes", "API")) for w in what
                )
                if companion.bridge and previous is not None and (surface_changed or snap is None):
                    review = True
            report.alerts += rules(companion, snap, client)
        if review:
            report.lines.append(
                f"  review {', '.join(companion.bridge)}: {companion.folder}'s surface changed"
            )
        if any(states.values()) or entries:
            page = pages / f"{companion.folder}.md"
            old = page_changes(page)
            changes = "\n".join(entries + ([old] if old else []))
            write_atomic(page, render_page(companion, states, changes, today))
    if report.alerts:
        advice = (
            "The suite depends on these addons (tools/companions.toml). Install or update them "
            "in the client, then run `python tools/companion_watch.py`."
        )
        write_atomic(
            alert,
            f"# Companion alerts ({today})\n\n"
            + "".join(f"- {a}\n" for a in report.alerts)
            + f"\n{advice}\n",
        )
        report.lines = [f"! ALERT: {a}" for a in report.alerts] + report.lines
    elif alert.is_file():
        alert.unlink()
    if not report.lines:
        report.lines.append("companions unchanged")
    return report


def daily_lines(root: Path = ROOT, today: str | None = None) -> list[str]:
    """The daily chain's step: the report's lines, never an exception."""
    try:
        clients = client_folders(root / ".local" / "install.toml")
        if not clients:
            return [
                "companions: no client folders in .local/install.toml ([companions] or [clients])"
            ]
        companions = load_companions(root / "tools" / "companions.toml")
        report = watch(
            clients,
            companions,
            snapshots=root / ".local" / "companions",
            pages=root / "docs" / "reference" / "companions",
            alert=root / ".local" / "companions" / "ALERT.md",
            today=today,
        )
        return [
            "companions: " + line.lstrip() if line.startswith("  ") else "companions " + line
            for line in report.lines
        ]
    except (OSError, ValueError, KeyError, tomllib.TOMLDecodeError) as err:
        return [f"companions: the watch failed: {err}"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", default="all", help="forever, retail or all (default)")
    parser.add_argument(
        "--today", help="the date written into snapshots and pages (default: today, UTC)"
    )
    parser.add_argument(
        "--diff", nargs=2, metavar=("OLD", "NEW"), help="compare two snapshot files"
    )
    args = parser.parse_args(argv)
    if args.diff:
        old, new = (json.loads(Path(p).read_text(encoding="utf-8")) for p in args.diff)
        for line in diff(old, new) or ["no difference"]:
            print(line)
        return 0
    clients = client_folders()
    if args.client != "all":
        clients = {k: v for k, v in clients.items() if k == args.client}
    if not clients:
        print(
            'no client folders: add [companions] forever = "<client folder>" to .local/install.toml'
        )
        return 2
    report = watch(clients, load_companions(), today=args.today)
    for line in report.lines:
        print(line)
    return 1 if report.alerts else 0


if __name__ == "__main__":
    sys.exit(main())
