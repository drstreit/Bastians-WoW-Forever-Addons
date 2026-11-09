"""The CurseForge catalog survey: the search asks for Forever's game version
type with the Core API key, prints one table per term, strips a description to text, refuses
without a key, and never prints the key."""

import json
from pathlib import Path

import cf_survey


def fake_transport(calls: list):
    def transport(request):
        calls.append(request)
        path = request.full_url.split("api.curseforge.com", 1)[1]
        if path.startswith("/v1/mods/search"):
            if "pageSize=1&" in path or path.endswith("pageSize=1"):
                return json.dumps({"data": [], "pagination": {"totalCount": 752}}).encode()
            return json.dumps(
                {
                    "data": [
                        {
                            "id": 1234,
                            "name": "Quest Master",
                            "slug": "quest-master",
                            "downloadCount": 173000,
                            "dateCreated": "2026-09-14T10:00:00Z",
                            "dateModified": "2026-11-06T18:00:00Z",
                            "summary": "Quest journal, dungeon pages and more.",
                            "authors": [{"name": "someone"}],
                        }
                    ],
                    "pagination": {"totalCount": 752},
                }
            ).encode()
        if path == "/v1/mods/1234/description":
            return json.dumps(
                {"data": "<p>Hello &amp; welcome.</p><ul><li>one</li><li>two</li></ul>"}
            ).encode()
        raise AssertionError(path)

    return transport


def test_the_survey_asks_forever_with_the_key_and_prints_a_table(tmp_path: Path, capsys):
    calls: list = []
    env = {"CF_CORE_API_KEY": "secret-key"}
    out = tmp_path / "rows.json"
    code = cf_survey.main(
        ["quest", "--limit", "5", "--json", str(out), "--describe", "1234"],
        fake_transport(calls),
        env=env,
        secrets=tmp_path / "none",
    )
    assert code == 0
    search = calls[0]
    assert "gameVersionTypeId=88568" in search.full_url and "classId=1" in search.full_url
    assert "searchFilter=quest" in search.full_url and "pageSize=5" in search.full_url
    assert search.get_header("X-api-key") == "secret-key"
    printed = capsys.readouterr().out
    assert "secret-key" not in printed
    assert "== quest: 1 shown of 752 in the catalog" in printed
    assert "1234     173,000  2026-09-14  2026-11-06  Quest Master: Quest journal" in printed
    assert "== description of 1234\nHello & welcome.\none\ntwo" in printed
    assert json.loads(out.read_text(encoding="utf-8"))["quest"][0]["slug"] == "quest-master"


def test_without_a_key_or_a_term_nothing_is_asked(tmp_path: Path, capsys):
    calls: list = []
    assert cf_survey.main(["quest"], fake_transport(calls), env={}, secrets=tmp_path / "none") == 2
    assert "no CurseForge Core API key" in capsys.readouterr().err
    assert cf_survey.main([], fake_transport(calls), env={"CF_CORE_API_KEY": "k"}) == 2
    assert calls == []


def test_the_key_comes_from_the_secrets_file_line(tmp_path: Path):
    secrets = tmp_path / ".secrets"
    secrets.write_text("API-TOKEN=upload\nCURSEFORGE-API-FOR-STUDIOS=read-only\n", encoding="utf-8")
    calls: list = []
    assert cf_survey.main(["gold"], fake_transport(calls), env={}, secrets=secrets) == 0
    assert calls[0].get_header("X-api-key") == "read-only"
