"""The CurseForge catalog survey: nobody
states what addons exist for WoW Forever without this search. The catalog holds three to ten clones
of every cheap idea, so a claim like "no addon does X" is measured here first.

Usage: python tools/cf_survey.py <term> [<term> ...] [--limit 20] [--version-type 88568]
       [--json <file>] [--describe <mod id>]

Asks the read API (api.curseforge.com, game 1 = World of Warcraft, class 1 = addons, game version
type 88568 = WoW Forever) for every term, sorted by total downloads, and prints one table per term:
id, downloads, created, updated, name and summary. `--describe` prints a project's description as
text (its HTML stripped) for reading what it really does. `--json` keeps the rows. The key is the
Core API key tools/curseforge.py reads (CF_CORE_API_KEY, else the CURSEFORGE-API-FOR-STUDIOS line
of ~/.curseforge/.secrets); it is never printed and never stored in the repository.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.parse
from pathlib import Path

from curseforge import SECRETS, Transport, _urlopen, core_get, core_key

GAME_WOW = 1
CLASS_ADDONS = 1
FOREVER = 88568  # the game version type of WoW Forever (measured 07.11.2026)
SORT_DOWNLOADS = 6  # ModsSearchSortField.TotalDownloads
PAGE_MAX = 50  # the API's page size limit


def search(
    term: str,
    key: str,
    transport: Transport,
    version_type: int = FOREVER,
    limit: int = 20,
) -> list[dict]:
    """The addons matching `term` for the game version type, most downloaded first, as plain rows:
    { id, name, slug, downloads, created, updated, summary, authors }. Dates are the API's day."""
    query = urllib.parse.urlencode(
        {
            "gameId": GAME_WOW,
            "classId": CLASS_ADDONS,
            "gameVersionTypeId": version_type,
            "searchFilter": term,
            "sortField": SORT_DOWNLOADS,
            "sortOrder": "desc",
            "pageSize": max(1, min(PAGE_MAX, limit)),
        }
    )
    data = core_get(f"/v1/mods/search?{query}", key, transport)
    rows = []
    for mod in data.get("data") or []:
        rows.append(
            {
                "id": int(mod["id"]),
                "name": str(mod.get("name") or ""),
                "slug": str(mod.get("slug") or ""),
                "downloads": int(mod.get("downloadCount") or 0),
                "created": str(mod.get("dateCreated") or "")[:10],
                "updated": str(mod.get("dateModified") or "")[:10],
                "summary": str(mod.get("summary") or ""),
                "authors": [str(a.get("name") or "") for a in mod.get("authors") or []],
            }
        )
    return rows


def total(term: str, key: str, transport: Transport, version_type: int = FOREVER) -> int | None:
    """How many addons the catalog lists for the term (the search's pagination total), or None when
    the API does not say."""
    query = urllib.parse.urlencode(
        {
            "gameId": GAME_WOW,
            "classId": CLASS_ADDONS,
            "gameVersionTypeId": version_type,
            "searchFilter": term,
            "pageSize": 1,
        }
    )
    data = core_get(f"/v1/mods/search?{query}", key, transport)
    count = (data.get("pagination") or {}).get("totalCount")
    return int(count) if count is not None else None


def description(mod_id: int, key: str, transport: Transport) -> str:
    """A project's description as text: the HTML's tags dropped, entities unescaped, whitespace
    folded, so a reader sees what the addon says of itself."""
    data = core_get(f"/v1/mods/{mod_id}/description", key, transport)
    text = str(data.get("data") or "")
    text = re.sub(r"<\s*(br|/p|/div|/li|/h\d|/tr)\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def format_rows(term: str, rows: list[dict], count: int | None) -> list[str]:
    head = f"== {term}: {len(rows)} shown"
    if count is not None:
        head += f" of {count} in the catalog"
    out = [head]
    if not rows:
        out.append("  (none)")
        return out
    out.append(f"  {'id':>7}  {'downloads':>10}  {'created':10}  {'updated':10}  name: summary")
    for r in rows:
        summary = r["summary"].replace("\n", " ")
        if len(summary) > 90:
            summary = summary[:87] + "..."
        out.append(
            f"  {r['id']:>7}  {r['downloads']:>10,}  {r['created']:10}  {r['updated']:10}  "
            f"{r['name']}: {summary}"
        )
    return out


def main(
    argv: list[str] | None = None,
    transport: Transport = _urlopen,
    env: dict | None = None,
    secrets: Path = SECRETS,
) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("terms", nargs="*", help="search terms, one table each")
    ap.add_argument("--limit", type=int, default=20, help="rows per term (at most 50)")
    ap.add_argument(
        "--version-type", type=int, default=FOREVER, help="CurseForge game version type (Forever)"
    )
    ap.add_argument("--json", type=Path, help="write the rows per term to this file")
    ap.add_argument("--describe", type=int, help="print this project's description as text")
    args = ap.parse_args(argv)
    if not args.terms and args.describe is None:
        ap.print_usage()
        return 2
    key = core_key(env, secrets)
    if not key:
        print(
            "error: no CurseForge Core API key (CF_CORE_API_KEY, or the CURSEFORGE-API-FOR-STUDIOS "
            f"line of {secrets})",
            file=sys.stderr,
        )
        return 2
    kept: dict[str, list[dict]] = {}
    for term in args.terms:
        rows = search(term, key, transport, args.version_type, args.limit)
        count = total(term, key, transport, args.version_type)
        kept[term] = rows
        print("\n".join(format_rows(term, rows, count)))
    if args.describe is not None:
        print(f"== description of {args.describe}")
        print(description(args.describe, key, transport))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(kept, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print(f"rows written to {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
