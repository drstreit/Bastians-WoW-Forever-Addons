"""The status page of bastians.dev (/status/, catalog review B1, 07.11.2026): one glance at whether
the suite still runs without a hand. The last Data edition and whether CurseForge took it, the last
daily runs, the companions' versions per client, and what needs the owner. Rendered by
tools/daily.py into the site overlay before every deploy, from the daily run's own records
(.local/data-editions.json, .local/logs/daily.log, .local/companions/*, ATTENTION.md); nothing is
measured here, and what a record does not say shows as unknown, never as a number.

Usage: python tools/status_page.py [--out build/data/site] [--root .]
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "data" / "site"
CLIENTS = ("forever", "retail")
RUNS_SHOWN = 7
STALE_DAYS = 3  # no run for this long: the page says so first
LOCAL_PATH = re.compile(r"[A-Za-z]:[\\/][^\s`'\"]*")  # a machine's own paths never go public


# -- reading the records -------------------------------------------------------------------------


def last_edition(ledger_path: Path) -> dict | None:
    """The last edition the ledger sent, else its last entry; None without a ledger."""
    if not ledger_path.is_file():
        return None
    try:
        editions = json.loads(ledger_path.read_text(encoding="utf-8")).get("editions") or []
    except OSError, ValueError:
        return None
    sent = [e for e in editions if e.get("sent")]
    pick = (sent or editions)[-1] if (sent or editions) else None
    if not pick:
        return None
    return {
        "edition": f"{pick.get('date')}.{pick.get('n')}",
        "sent_at": pick.get("sent_at"),
        "file_id": pick.get("file_id"),
        "curseforge": pick.get("curseforge"),
        "export": pick.get("export"),
    }


def runs(log_path: Path, limit: int = RUNS_SHOWN) -> list[dict]:
    """The last daily runs, newest first: { at, status, text } from the log's
    `<ISO> <status>[ edition x], ...` lines."""
    if not log_path.is_file():
        return []
    out = []
    for line in log_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"(\S+Z)\s+(done|dry run|nothing new|failed|refused)\b,?\s*(.*)", line)
        if m:
            out.append({"at": m.group(1), "status": m.group(2), "text": m.group(3).strip()})
    return list(reversed(out[-limit:]))


def companions(snapshots: Path) -> list[dict]:
    """The newest snapshot of every companion per client: { client, folder, version, at }."""
    out = []
    for client in CLIENTS:
        base = snapshots / client
        if not base.is_dir():
            continue
        for folder in sorted(p for p in base.iterdir() if p.is_dir()):
            files = sorted(folder.glob("*.json"))
            if not files:
                continue
            try:
                snap = json.loads(files[-1].read_text(encoding="utf-8"))
            except OSError, ValueError:
                snap = {}
            out.append(
                {
                    "client": client,
                    "folder": folder.name,
                    "version": snap.get("version") if isinstance(snap, dict) else None,
                    "at": files[-1].stem,
                }
            )
    return out


def alerts(*paths: Path) -> list[str]:
    """The lines of the owner's attention files (ATTENTION.md, the companions' ALERT.md), local
    paths scrubbed; an empty list when all is well."""
    lines = []
    for path in paths:
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("#"):
                continue  # a heading, not an item
            text = line.strip().lstrip("-* ").strip()
            if text:
                lines.append(LOCAL_PATH.sub("(a path on the build machine)", text))
    return lines


def verdict(state: dict, now: datetime) -> tuple[str, str]:
    """(word, sentence): "stale" without a run for STALE_DAYS, "attention" when the last run
    failed or something waits for the owner, "unknown" without any record, else "running"."""
    last = state["runs"][0] if state["runs"] else None
    if not last and not state["edition"]:
        return "unknown", "No record of a run yet."
    if last:
        try:
            at = datetime.fromisoformat(last["at"].replace("Z", "+00:00"))
        except ValueError:
            at = None
        if at and now - at > timedelta(days=STALE_DAYS):
            return (
                "stale",
                f"The last run was on {last['at'][:10]}, more than {STALE_DAYS} days ago.",
            )
        if last["status"] in ("failed", "refused"):
            return "attention", f"The last run {last['status']}."
    if state["alerts"]:
        return "attention", f"{len(state['alerts'])} items wait for the owner."
    return "running", "The daily run works, nothing waits for the owner."


def collect(root: Path) -> dict:
    local = root / ".local"
    return {
        "edition": last_edition(local / "data-editions.json"),
        "runs": runs(local / "logs" / "daily.log"),
        "companions": companions(local / "companions"),
        "alerts": alerts(local / "logs" / "ATTENTION.md", local / "companions" / "ALERT.md"),
    }


# -- the page ------------------------------------------------------------------------------------

# the site's own palette (site/index.html): Dark teal, Parchment in the light scheme
STYLE = """
:root { --bg: #14110f; --panel: #1a1816; --line: rgba(255,255,255,.1); --text: #ebebeb;
  --dim: #a39c93; --accent: #0cd29d; --warn: #e0a84a; --bad: #e06a5a; color-scheme: dark;
  --body: system-ui, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --display: "Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif; }
@media (prefers-color-scheme: light) { :root:not([data-theme="dark"]) {
  --bg: #efe4c8; --panel: #e6d7b0; --line: rgba(59,42,23,.2); --text: #2e2014; --dim: #5e4a33;
  --accent: #8c2f1a; --warn: #8a5a12; --bad: #a3321f; color-scheme: light; } }
:root[data-theme="light"] {
  --bg: #efe4c8; --panel: #e6d7b0; --line: rgba(59,42,23,.2); --text: #2e2014; --dim: #5e4a33;
  --accent: #8c2f1a; --warn: #8a5a12; --bad: #a3321f; color-scheme: light; }
body { margin: 0; background: var(--bg); color: var(--text); font-family: var(--body);
  line-height: 1.5; }
main { max-width: 860px; margin: 0 auto;
  padding: 32px max(16px, env(safe-area-inset-right, 0px)) 64px
  max(16px, env(safe-area-inset-left, 0px)); }
h1, h2 { font-family: var(--display); font-weight: 600; margin: 0 0 8px; }
h1 { font-size: 30px; } h2 { font-size: 20px; margin-top: 32px; }
.verdict { display: inline-block; padding: 2px 10px; border-radius: 999px; font-weight: 600;
  color: #0b0a09; }
.running { background: var(--accent); } .attention, .stale { background: var(--warn); }
.unknown { background: var(--dim); }
p.lede { color: var(--dim); margin: 6px 0 0; }
table { width: 100%; border-collapse: collapse; font-size: 14px; background: var(--panel); }
th, td { text-align: left; padding: 8px 10px; border-top: 1px solid var(--line);
  vertical-align: top; }
th { color: var(--dim); font-weight: 600; font-size: 12px; letter-spacing: .04em;
  text-transform: uppercase; border-top: 0; }
td.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
.failed, .refused { color: var(--bad); font-weight: 600; }
ul { margin: 0; padding-left: 20px; } li { margin-bottom: 4px; }
footer { margin-top: 40px; color: var(--dim); font-size: 13px; border-top: 1px solid var(--line);
  padding-top: 12px; }
a { color: var(--accent); }
"""


def _e(value: object) -> str:
    return html.escape("unknown" if value in (None, "") else str(value))


def render(state: dict, now: datetime) -> str:
    word, sentence = verdict(state, now)
    e = state["edition"]
    parts = [
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n',
        '<meta name="viewport" content="width=device-width, initial-scale=1, '
        'viewport-fit=cover">\n',
        "<title>Status of Bastian's suite</title>\n",
        '<meta name="description" content="Whether Bastian\'s WoW Forever addons and their daily '
        'data edition still run: the last edition, the daily runs, the companions, what waits.">\n',
        '<link rel="icon" type="image/svg+xml" href="../media/bastians-dev.svg">\n',
        f"<style>{STYLE}</style>\n</head>\n<body>\n<main>\n",
        f'<span class="verdict {word}">{_e(word)}</span>\n',
        "<h1>Status of Bastian's suite</h1>\n",
        f'<p class="lede">{_e(sentence)} Written by the daily run; this page was rendered '
        f"{_e(now.strftime('%Y-%m-%d %H:%M'))} UTC.</p>\n",
        "<h2>The last Data edition</h2>\n",
    ]
    if e:
        parts.append(
            "<table><tr><th>Edition</th><th>Sent</th><th>CurseForge file</th><th>Its state</th>"
            "<th>Built from export</th></tr>"
            f'<tr><td class="num">{_e(e["edition"])}</td><td class="num">{_e(e["sent_at"])}</td>'
            f'<td class="num">{_e(e["file_id"])}</td><td>{_e(e["curseforge"])}</td>'
            f'<td class="num">{_e(e["export"])}</td></tr></table>\n'
        )
    else:
        parts.append("<p>No edition recorded yet.</p>\n")
    parts.append("<h2>The daily runs</h2>\n")
    if state["runs"]:
        parts.append("<table><tr><th>When (UTC)</th><th>Result</th><th>What it said</th></tr>")
        for r in state["runs"]:
            parts.append(
                f'<tr><td class="num">{_e(r["at"])}</td>'
                f'<td class="{_e(r["status"]).replace(" ", "-")}">{_e(r["status"])}</td>'
                f"<td>{_e(LOCAL_PATH.sub('(a path on the build machine)', r['text']))}</td></tr>"
            )
        parts.append("</table>\n")
    else:
        parts.append("<p>No run recorded yet.</p>\n")
    parts.append("<h2>The companions the data is read from</h2>\n")
    if state["companions"]:
        parts.append("<table><tr><th>Client</th><th>Addon</th><th>Version</th><th>Seen</th></tr>")
        for c in state["companions"]:
            parts.append(
                f"<tr><td>{_e(c['client'])}</td><td>{_e(c['folder'])}</td>"
                f'<td class="num">{_e(c["version"] or "missing")}</td>'
                f'<td class="num">{_e(c["at"])}</td></tr>'
            )
        parts.append("</table>\n")
    else:
        parts.append("<p>No companion watched yet.</p>\n")
    parts.append("<h2>What waits for the owner</h2>\n")
    if state["alerts"]:
        parts.append("<ul>" + "".join(f"<li>{_e(a)}</li>" for a in state["alerts"]) + "</ul>\n")
    else:
        parts.append("<p>Nothing.</p>\n")
    parts.append(
        '<footer>Part of <a href="../">bastians.dev</a>. The addons: '
        '<a href="../wow/">Bastian\'s WoW Forever addons</a>. The figures are the build '
        "machine's own records; what a record does not say reads as unknown.</footer>\n"
        "</main>\n</body>\n</html>\n"
    )
    return "".join(parts)


def build(root: Path = ROOT, out: Path = OUT, now: datetime | None = None) -> Path:
    """Writes `out`/status/index.html from the records under `root`/.local. -> the file."""
    now = now or datetime.now(UTC)
    page = render(collect(root), now)
    target = out / "status" / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(page, encoding="utf-8", newline="\n")
    tmp.replace(target)
    return target


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--root", type=Path, default=ROOT, help="the repository (its .local records)")
    ap.add_argument("--out", type=Path, default=OUT, help="the site folder to write into")
    args = ap.parse_args(argv)
    target = build(args.root, args.out)
    print(f"status page: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
