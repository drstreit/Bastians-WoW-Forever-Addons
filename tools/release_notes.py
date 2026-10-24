"""Release notes from commit trailers (ADR 0020 decision 5): `Release-note: <kind>: <sentence>`.

A commit that changes a shipped path carries one or more trailers; `Release-note: none` says that
players notice nothing. The tracks' paths come from tools/curseforge.toml (the projects' folders)
plus the pipeline: the parts that write the Suite's generated files belong to the Suite, the rest
to Data. Used by tools/data_update.py (the Data edition's changelog) and tools/suite_release.py
(the step and the Suite's changelog).
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KINDS = ("breaking", "format", "feature", "fix", "none")  # the strongest first
TRAILER = re.compile(r"^Release-note:\s*(\w+)\s*(?::\s*(.*\S))?\s*$", re.I)
# the pipeline parts whose output ships in the Suite's folders (Map's tiles, Map Art's overview,
# Core's themes); every other pipeline file writes Data's packs
SUITE_PIPELINE = (
    "pipeline/bastians_build/mapart.py",
    "pipeline/bastians_build/mapart_art.py",
    "pipeline/bastians_build/overview.py",
    "pipeline/bastians_build/themes.py",
    "pipeline/config/themes",
)
# the subject's prefix names the app whose What's new gets the sentence (CLAUDE.md section 9)
APPS = {
    "core": "Bastians_Core",
    "ui": "Bastians_Core",
    "quests": "Bastians_Quests",
    "map": "Bastians_Map",
    "map art": "Bastians_Map_Art",
    "map_art": "Bastians_Map_Art",
    "browser": "Bastians_Browser",
    "gold": "Bastians_Gold",
    "route": "Bastians_Route",
    "strategies": "Bastians_Strategies",
    "book": "Bastians_Strategies",
    "data": "Bastians_Data",
    "pipeline": "Bastians_Data",
}
SEP, END = "\x1f", "\x1e"


class NotesError(Exception):
    pass


@dataclass(frozen=True)
class Note:
    kind: str
    text: str
    app: str | None  # the addon folder from the subject's prefix, None for the suite as a whole
    commit: str


@dataclass
class Commit:
    sha: str
    subject: str
    date: str  # ISO-8601 with offset, the author date
    notes: list[Note] = field(default_factory=list)

    @property
    def classified(self) -> bool:
        return bool(self.notes)

    @property
    def app(self) -> str | None:
        return app_of(self.subject)


def app_of(subject: str) -> str | None:
    prefix = subject.split(":", 1)[0].strip().lower() if ":" in subject else ""
    return APPS.get(prefix)


def parse_notes(sha: str, subject: str, body: str) -> list[Note]:
    """The trailers of one message; an unknown kind is an error (a typo must not hide a note)."""
    out = []
    for line in body.splitlines():
        m = TRAILER.match(line.strip())
        if not m:
            continue
        kind = m.group(1).lower()
        if kind not in KINDS:
            raise NotesError(f"{sha[:7]}: Release-note kind {kind!r} is not one of {KINDS}")
        text = (m.group(2) or "").strip()
        if kind != "none" and not text:
            raise NotesError(f"{sha[:7]}: Release-note {kind} without a sentence")
        out.append(Note(kind, text, app_of(subject), sha))
    return out


def track_paths(config: dict, track: str) -> list[str]:
    """git pathspecs of a track: its project's folders, and its part of the pipeline."""
    project = {"suite": "Bastians_Suite", "data": "Bastians_Data"}[track]
    folders = [f"addons/{f}" for f in config["projects"][project]["folders"]]
    if track == "suite":
        return [*folders, *SUITE_PIPELINE]
    return [*folders, "pipeline/bastians_build", "pipeline/config"] + [
        f":(exclude){p}" for p in SUITE_PIPELINE
    ]


def git(*args: str, root: Path = ROOT) -> str:
    try:
        run = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        raise NotesError(f"git {' '.join(args[:2])}: {detail.strip()[:300]}") from exc
    return run.stdout


def commits(since: str | None, paths: list[str], root: Path = ROOT) -> list[Commit]:
    """The commits after `since` (exclusive; None: the whole history) that touch the paths, oldest
    first, with their notes."""
    span = f"{since}..HEAD" if since else "HEAD"
    out = git(
        "log", "--reverse", f"--format=%H{SEP}%s{SEP}%aI{SEP}%b{END}", span, "--", *paths, root=root
    )
    found = []
    for chunk in out.split(END):
        chunk = chunk.strip("\n")
        if not chunk:
            continue
        sha, subject, date, body = [*chunk.split(SEP), "", "", ""][:4]
        c = Commit(sha, subject, date)
        c.notes = parse_notes(sha, subject, body)
        found.append(c)
    return found


def head(root: Path = ROOT) -> str:
    return git("rev-parse", "HEAD", root=root).strip()


def last_change(paths: list[str], root: Path = ROOT) -> str | None:
    """The newest commit that touched the paths (the inputs a build reads), or None."""
    return git("log", "-1", "--format=%H", "--", *paths, root=root).strip() or None


def player_notes(found: list[Commit]) -> list[Note]:
    """The notes players read, oldest first (`none` left out)."""
    return [n for c in found for n in c.notes if n.kind != "none"]
