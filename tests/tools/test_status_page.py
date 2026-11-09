"""The status page (catalog review B1, 07.11.2026): rendered from the daily run's records in a temp
root, never from the repository's .local; unknown stays unknown; local paths never go public; the
verdict follows the last run and the owner's list."""

import json
from datetime import UTC, datetime
from pathlib import Path

import status_page

NOW = datetime(2026, 11, 7, 18, 30, tzinfo=UTC)


def records(root: Path, *, log: str, attention: str | None = None) -> None:
    local = root / ".local"
    (local / "logs").mkdir(parents=True)
    (local / "data-editions.json").write_text(
        json.dumps(
            {
                "editions": [
                    {
                        "date": "2026-11-05",
                        "n": 1,
                        "sent": True,
                        "file_id": 1,
                        "curseforge": "live",
                    },
                    {
                        "date": "2026-11-07",
                        "n": 1,
                        "sent": True,
                        "sent_at": "2026-11-07T07:12:25Z",
                        "file_id": 9487791,
                        "curseforge": "pending",
                        "export": "20261107T0709Z",
                    },
                    {"date": "2026-11-07", "n": 2, "sent": False},
                ]
            }
        ),
        encoding="utf-8",
    )
    (local / "logs" / "daily.log").write_text(log, encoding="utf-8")
    if attention is not None:
        (local / "logs" / "ATTENTION.md").write_text(attention, encoding="utf-8")
    snaps = local / "companions" / "forever" / "ForeverDB"
    snaps.mkdir(parents=True)
    (snaps / "2026-11-05.json").write_text(json.dumps({"version": "0.55.0"}), encoding="utf-8")
    (snaps / "2026-11-07.json").write_text(json.dumps({"version": "0.57.0"}), encoding="utf-8")
    gone = local / "companions" / "retail" / "Questie"
    gone.mkdir(parents=True)
    (gone / "2026-11-07.json").write_text(json.dumps({"gone": True}), encoding="utf-8")


def test_the_page_shows_the_last_sent_edition_the_runs_and_the_companions(tmp_path: Path):
    records(
        tmp_path,
        log=(
            "2026-11-05T17:05:01Z done edition 2026-11-05.1, 1111 s: CurseForge, file 1: live\n"
            "2026-11-07T06:45:41Z failed, 10 s: error: uncommitted changes in C:\\Users\\x\\repo\n"
            "2026-11-07T07:09:25Z done edition 2026-11-07.1, 789 s: CurseForge, file 9487791\n"
        ),
    )
    target = status_page.build(tmp_path, tmp_path / "site", NOW)
    assert target == tmp_path / "site" / "status" / "index.html"
    page = target.read_text(encoding="utf-8")
    assert '<span class="verdict running">running</span>' in page
    assert "2026-11-07.1" in page and "9487791" in page and "pending" in page
    assert "2026-11-07.2" not in page  # the unsent edition is not the one players have
    # the runs, newest first, the failure marked, the machine's path scrubbed
    assert page.index("2026-11-07T07:09:25Z") < page.index("2026-11-07T06:45:41Z")
    assert '<td class="failed">failed</td>' in page
    assert "C:\\Users" not in page and "(a path on the build machine)" in page
    # the newest snapshot per companion; a gone one reads as missing
    assert '<td>ForeverDB</td><td class="num">0.57.0</td>' in page and "0.55.0" not in page
    assert '<td>Questie</td><td class="num">missing</td>' in page
    assert "<p>Nothing.</p>" in page
    assert "rendered 2026-11-07 18:30 UTC" in page


def test_the_verdict_names_a_failure_the_owners_list_and_a_stale_run(tmp_path: Path):
    records(
        tmp_path,
        log="2026-11-07T06:45:41Z failed, 10 s: error: the export is missing\n",
        attention="# Attention\n- the companions' watch: ForeverDB below min\n",
    )
    page = status_page.render(status_page.collect(tmp_path), NOW)
    assert 'verdict attention">attention' in page and "The last run failed." in page
    assert "<li>the companions&#x27; watch: ForeverDB below min</li>" in page
    state = status_page.collect(tmp_path)
    state["runs"][0]["status"] = "done"
    assert status_page.verdict(state, NOW) == ("attention", "1 items wait for the owner.")
    late = datetime(2026, 11, 12, tzinfo=UTC)
    word, sentence = status_page.verdict(state, late)
    assert word == "stale" and "more than 3 days ago" in sentence


def test_without_records_everything_reads_unknown(tmp_path: Path):
    page = status_page.render(status_page.collect(tmp_path), NOW)
    assert 'verdict unknown">unknown' in page and "No record of a run yet." in page
    assert "No edition recorded yet." in page and "No companion watched yet." in page
    assert "0" not in page.split("<h2>The last Data edition</h2>")[1].split("<h2>")[0]
