"""Deploys the website to bastians.dev: Cloudflare Pages by direct upload, no git connection (owner,
24.10.2026). The site is what `site/` holds: the home page of every project and the suite's page
in `site/wow/`.

Usage: python tools/site_deploy.py [--overlay <dir>] [--list] [--setup] [--preview]

  --overlay  a built folder whose files join site/ (tools/diary_site.py writes the gold diary to
             build/data/site/wow/my-gold-diary; tools/daily.py deploys with it after each edition)
  --list     print the files that would be published and stop (nothing leaves the machine)
  --setup    create the Pages project and connect the domain when they are missing (idempotent);
             with --preview only the project
  --preview  deploy to the preview branch: a private-looking address, not bastians.dev

The account id and the API token come from CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN, else
from ~/.cloudflare/.cloudflare-secret (ACCOUNT_ID=..., API_TOKEN=...). Never from the repo. The
upload runs wrangler through npx, pinned below.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
SECRETS = Path.home() / ".cloudflare" / ".cloudflare-secret"
PROJECT = "bastians"
DOMAIN = "bastians.dev"
WRANGLER = "wrangler@4.148.0"
API = "https://api.cloudflare.com/client/v4"


class SiteError(Exception):
    pass


def read_secrets(path: Path = SECRETS, environ: dict | None = None) -> tuple[str, str]:
    """(account id, API token): the environment first, then the secrets file."""
    environ = os.environ if environ is None else environ
    values: dict[str, str] = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and not key.strip().startswith("#"):
                values[key.strip()] = value.strip().strip('"').strip("'")
    account = environ.get("CLOUDFLARE_ACCOUNT_ID") or values.get("ACCOUNT_ID")
    token = environ.get("CLOUDFLARE_API_TOKEN") or values.get("API_TOKEN")
    if not account or not token:
        raise SiteError(f"no Cloudflare account id or token (environment or {path})")
    return account, token


def collect(root: Path = SITE) -> dict[str, Path]:
    """The published path of every file under `root`, without hidden files and caches."""
    files = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if path.is_file() and not any(p.startswith(".") or p == "__pycache__" for p in rel.parts):
            files[rel.as_posix()] = path
    return files


def site_files(overlay: Path | None = None) -> dict[str, Path]:
    """site/ and, over it, the overlay's files (the generated diary)."""
    files = collect(SITE)
    if overlay is not None:
        if not overlay.is_dir():
            raise SiteError(f"no {overlay}: build it first (tools/diary_site.py)")
        files.update(collect(overlay))
    return dict(sorted(files.items()))


def stage(files: dict[str, Path], out: Path) -> None:
    """Copies exactly `files` into `out`, so nothing else in the folder can be uploaded."""
    for rel, src in files.items():
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)


def api(token: str, method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.load(e)


def setup(account: str, token: str, domain: bool = True) -> None:
    """The Pages project, its custom domain and the domain's DNS record, each only when missing.
    Without `domain` only the project: a preview never touches bastians.dev."""
    base = f"/accounts/{account}/pages/projects"
    got = api(token, "GET", f"{base}/{PROJECT}")
    if not got.get("success"):
        got = api(token, "POST", base, {"name": PROJECT, "production_branch": "main"})
        if not got.get("success"):
            raise SiteError(f"creating the project failed: {got.get('errors')}")
        print(f"project {PROJECT} created")
    subdomain = got["result"]["subdomain"]
    print(f"project {PROJECT}: {subdomain}")
    if not domain:
        return
    domains = api(token, "GET", f"{base}/{PROJECT}/domains").get("result") or []
    if DOMAIN not in {d["name"] for d in domains}:
        added = api(token, "POST", f"{base}/{PROJECT}/domains", {"name": DOMAIN})
        if not added.get("success"):
            raise SiteError(f"adding {DOMAIN} failed: {added.get('errors')}")
        print(f"domain {DOMAIN} added to the project")
    zones = api(token, "GET", f"/zones?name={DOMAIN}").get("result") or []
    if not zones:
        raise SiteError(f"the zone {DOMAIN} is not in this account")
    zone = zones[0]["id"]
    records = api(token, "GET", f"/zones/{zone}/dns_records?name={DOMAIN}").get("result") or []
    if not records:
        record = {"type": "CNAME", "name": DOMAIN, "content": subdomain, "proxied": True}
        made = api(token, "POST", f"/zones/{zone}/dns_records", record)
        if not made.get("success"):
            raise SiteError(f"the DNS record failed: {made.get('errors')}")
        print(f"DNS: {DOMAIN} CNAME {subdomain}")
    for d in api(token, "GET", f"{base}/{PROJECT}/domains").get("result") or []:
        print(f"domain {d['name']}: {d.get('status')}")


def deploy(folder: Path, branch: str, account: str, token: str) -> int:
    npx = shutil.which("npx")
    if not npx:
        raise SiteError("npx not found: wrangler needs Node.js")
    env = {**os.environ, "CLOUDFLARE_ACCOUNT_ID": account, "CLOUDFLARE_API_TOKEN": token}
    cmd = [npx, "--yes", WRANGLER, "pages", "deploy", str(folder)]
    cmd += ["--project-name", PROJECT, "--branch", branch, "--commit-dirty=true"]
    return subprocess.run(cmd, env=env, check=False).returncode


def publish(overlay: Path | None = None, preview: bool = False) -> int:
    """Deploys site/ with the overlay (production, or the preview branch). -> wrangler's exit."""
    files = site_files(overlay)
    account, token = read_secrets()
    with tempfile.TemporaryDirectory(prefix="bastians-site-") as tmp:
        stage(files, Path(tmp))
        return deploy(Path(tmp), "preview" if preview else "main", account, token)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--overlay", type=Path, help="a built folder whose files join site/")
    ap.add_argument("--list", action="store_true", help="print the files and stop")
    ap.add_argument("--setup", action="store_true", help="create the project and the domain")
    ap.add_argument("--preview", action="store_true", help="deploy to the preview branch")
    args = ap.parse_args(argv)
    try:
        if args.list:
            files = site_files(args.overlay)
            for rel, src in files.items():
                print(f"{src.stat().st_size:>9}  {rel}")
            print(f"{len(files)} files")
            return 0
        if args.setup:
            setup(*read_secrets(), domain=not args.preview)
        return publish(args.overlay, args.preview)
    except SiteError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
