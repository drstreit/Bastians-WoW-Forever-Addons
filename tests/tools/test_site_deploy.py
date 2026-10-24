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
