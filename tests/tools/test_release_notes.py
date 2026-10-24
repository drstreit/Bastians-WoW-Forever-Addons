"""tools/release_notes.py (ADR 0020 decision 5): the Release-note trailers of the commits since a
release, by track; a typo in a kind or a note without a sentence is refused; the subject's
prefix names the app; the tracks' paths follow tools/curseforge.toml."""

import subprocess
from pathlib import Path

import curseforge
import pytest
import release_notes as rn


def test_trailers_parse_with_their_kind_sentence_and_app():
    body = (
        "Why it changed.\n\n"
        "Release-note: fix: Gold's tooltip shows unknown instead of 0c.\n"
        "Release-note: feature: A new map layer.\n"
        "Co-Authored-By: Someone <x@y>\n"
    )
    notes = rn.parse_notes("a" * 40, "Gold: unknown prices (B6.2)", body)
    assert [(n.kind, n.text, n.app) for n in notes] == [
        ("fix", "Gold's tooltip shows unknown instead of 0c.", "Bastians_Gold"),
        ("feature", "A new map layer.", "Bastians_Gold"),
    ]
    assert rn.parse_notes("b" * 40, "Docs: x", "Release-note: none\n")[0].kind == "none"
    assert rn.parse_notes("c" * 40, "Docs: x", "no trailer here\n") == []
    with pytest.raises(rn.NotesError, match="kind 'fixed'"):
        rn.parse_notes("d" * 40, "Map: x", "Release-note: fixed: typo\n")
    with pytest.raises(rn.NotesError, match="without a sentence"):
        rn.parse_notes("e" * 40, "Map: x", "Release-note: fix\n")
    assert rn.app_of("Map Art: coast masks") == "Bastians_Map_Art"
    assert rn.app_of("Release: beta.10") is None  # the suite as a whole


def test_the_tracks_cover_every_shipped_folder_once():
    cfg = curseforge.load_config()
    suite, data = rn.track_paths(cfg, "suite"), rn.track_paths(cfg, "data")
    shipped = {
        p.name
        for p in (rn.ROOT / "addons").iterdir()
        if p.is_dir() and p.name != "Bastians_Probe" and (p / f"{p.name}.toc").is_file()
    }
    folders = {p.split("/", 1)[1] for p in suite + data if p.startswith("addons/")}
    assert folders >= shipped - {"Bastians_Data_Nav"}  # the Nav pack has no generator yet
    assert not {p for p in suite if p.startswith("addons/")} & set(data)
    for p in rn.SUITE_PIPELINE:
        assert p in suite and f":(exclude){p}" in data
        assert (rn.ROOT / p).exists(), p


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
    ).stdout


def test_commits_since_a_release_on_a_track_with_their_notes(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@example.org")
    git(repo, "config", "user.name", "T")

    def commit(path: str, message: str) -> str:
        f = repo / path
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(message, encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", message)
        return git(repo, "rev-parse", "HEAD").strip()

    first = commit("addons/Bastians_Quests/Quests.lua", "Release: 1.0.0")
    commit("addons/Bastians_Quests/Quests.lua", "Quests: x\n\nRelease-note: fix: The log sorts.")
    commit("docs/a.md", "Docs: notes")
    commit("addons/Bastians_Map/Map.lua", "Map: y")
    found = rn.commits(first, ["addons/Bastians_Quests", "addons/Bastians_Map"], repo)
    assert [c.subject for c in found] == ["Quests: x", "Map: y"]  # oldest first, docs left out
    assert [c.classified for c in found] == [True, False]
    assert [n.text for n in rn.player_notes(found)] == ["The log sorts."]
    assert rn.last_change(["addons/Bastians_Map"], repo) == rn.head(repo)
    assert rn.last_change(["docs"], repo) != rn.head(repo)
    assert rn.last_change(["nothing"], repo) is None
    with pytest.raises(rn.NotesError):
        rn.commits("no-such-commit", ["addons"], repo)
