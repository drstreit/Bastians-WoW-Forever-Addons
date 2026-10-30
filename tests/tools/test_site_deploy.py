"""tools/site_deploy.py without the network: the secrets come from the environment before the file,
and only the site's own files are staged (no hidden files, no caches)."""

import importlib.util
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[2] / "tools" / "site_deploy.py"
spec = importlib.util.spec_from_file_location("site_deploy", TOOL)
site_deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site_deploy)


def test_the_secrets_file_is_read_and_the_environment_wins(tmp_path: Path):
    secret = tmp_path / ".cloudflare-secret"
    secret.write_text('ACCOUNT_ID=acc\nAPI_TOKEN="tok"\nS3_SECRET_ACCESS_KEY=x\n', encoding="utf-8")
    assert site_deploy.read_secrets(secret, {}) == ("acc", "tok")
    env = {"CLOUDFLARE_API_TOKEN": "env-tok"}
    assert site_deploy.read_secrets(secret, env) == ("acc", "env-tok")


def test_missing_secrets_stop_the_tool(tmp_path: Path):
    with pytest.raises(site_deploy.SiteError):
        site_deploy.read_secrets(tmp_path / "none", {})


def test_only_the_sites_own_files_are_staged(tmp_path: Path):
    site = tmp_path / "site"
    for rel in ("index.html", "wow/index.html", "media/a.svg", ".hidden", "wow/__pycache__/x.pyc"):
        (site / rel).parent.mkdir(parents=True, exist_ok=True)
        (site / rel).write_text(rel, encoding="utf-8")
    files = site_deploy.collect(site)
    assert list(files) == ["index.html", "media/a.svg", "wow/index.html"]
    out = tmp_path / "out"
    site_deploy.stage(files, out)
    staged = sorted(p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file())
    assert staged == list(files)


def test_the_real_site_has_its_two_pages():
    assert {"index.html", "wow/index.html"} <= set(site_deploy.collect())


def test_the_overlay_joins_the_site_and_must_exist(tmp_path: Path):
    overlay = tmp_path / "built"
    (overlay / "wow" / "my-gold-diary").mkdir(parents=True)
    (overlay / "wow" / "my-gold-diary" / "index.html").write_text("diary", encoding="utf-8")
    files = site_deploy.site_files(overlay)
    assert "wow/my-gold-diary/index.html" in files and "wow/index.html" in files
    with pytest.raises(site_deploy.SiteError):
        site_deploy.site_files(tmp_path / "missing")


class FakeApi:
    """Cloudflare's API as a dict of canned answers: (method, path) -> response; every call is
    recorded with its body. A path without an answer fails like the real API."""

    def __init__(self, answers: dict):
        self.answers, self.calls = answers, []

    def __call__(self, token, method, path, body=None):
        self.calls.append((method, path, body))
        return self.answers.get((method, path), {"success": False, "errors": [{"code": 7003}]})

    def writes(self):
        return [(m, p, b) for m, p, b in self.calls if m != "GET"]


ZONE = "z1"
RECORDS = f"/zones/{ZONE}/dns_records"
ENTRY = f"/zones/{ZONE}/rulesets/phases/http_request_dynamic_redirect/entrypoint"
NO_ENTRY = {"success": False, "errors": [{"code": 10003, "message": "could not find entrypoint"}]}
OK = {"success": True, "errors": [], "result": {}}


def test_www_sets_up_the_redirect_rule_then_the_record():
    fake = FakeApi(
        {
            ("GET", f"{RECORDS}?name=www.bastians.dev"): {"success": True, "result": []},
            ("GET", ENTRY): NO_ENTRY,
            ("PUT", ENTRY): OK,
            ("POST", RECORDS): OK,
        }
    )
    site_deploy.www(ZONE, "tok", fake)
    (m1, p1, rule), (m2, p2, record) = fake.writes()
    assert (m1, p1) == ("PUT", ENTRY) and (m2, p2) == ("POST", RECORDS)  # the rule first
    (r,) = rule["rules"]
    assert r["expression"] == '(http.host eq "www.bastians.dev")' and r["action"] == "redirect"
    target = r["action_parameters"]["from_value"]
    assert target["status_code"] == 301 and target["preserve_query_string"] is True
    assert target["target_url"]["expression"] == (
        'concat("https://bastians.dev", http.request.uri.path)'
    )
    assert record == {
        "type": "AAAA",
        "name": "www.bastians.dev",
        "content": "100::",
        "proxied": True,
    }


def test_www_is_idempotent_and_adds_to_an_existing_ruleset():
    rule = dict(site_deploy.WWW_RULE)
    done = FakeApi(
        {
            ("GET", f"{RECORDS}?name=www.bastians.dev"): {"success": True, "result": [{"id": "r"}]},
            ("GET", ENTRY): {"success": True, "result": {"id": "rs", "rules": [rule]}},
        }
    )
    site_deploy.www(ZONE, "tok", done)
    assert done.writes() == []
    other = FakeApi(
        {
            ("GET", f"{RECORDS}?name=www.bastians.dev"): {"success": True, "result": [{"id": "r"}]},
            ("GET", ENTRY): {
                "success": True,
                "result": {"id": "rs", "rules": [{"expression": "x"}]},
            },
            ("POST", f"/zones/{ZONE}/rulesets/rs/rules"): OK,
        }
    )
    site_deploy.www(ZONE, "tok", other)
    assert [(m, p) for m, p, _ in other.writes()] == [("POST", f"/zones/{ZONE}/rulesets/rs/rules")]


def test_a_missing_permission_is_named_and_nothing_is_written():
    no = {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}
    fake = FakeApi(
        {
            ("GET", f"{RECORDS}?name=www.bastians.dev"): {"success": True, "result": []},
            ("GET", ENTRY): NO_ENTRY,
            ("PUT", ENTRY): no,
        }
    )
    with pytest.raises(site_deploy.SiteError, match="Single Redirect / Edit"):
        site_deploy.www(ZONE, "tok", fake)
    assert [m for m, _, _ in fake.writes()] == ["PUT"]  # the record was not made
    reads = FakeApi({("GET", f"{RECORDS}?name=www.bastians.dev"): no})
    with pytest.raises(site_deploy.SiteError, match="DNS / Edit"):
        site_deploy.www(ZONE, "tok", reads)
    assert reads.writes() == []
