"""CurseForge upload per client (ADR 0015, ADR 0019): one file per project with that client's game
versions and relations; two projects, the suite and its data, and the suite requires the data, so
the CurseForge app installs both with one click.

Usage: python tools/curseforge.py --client forever|retail [--release-dir build/release/<client>]
       [--only Bastians_Quests,...] [--changelog <file>] [--send]

Reads `tools/curseforge.toml` and the release manifest that `tools/release.py` wrote for the
client. For every project it writes the upload zip (the project's folders from the release zips;
Data's file carries its packs) to `<release-dir>/curseforge/` and prints the metadata. Without
`--send` nothing leaves the machine. `--send` needs the environment variable CF_API_KEY (a
CurseForge API token; never stored in the repo), a project id and a verified slug for every
project and relation it touches, and at least one game version name for the client; it resolves
the names to ids (`GET /api/game/versions`) and posts each file (`POST /api/projects/<id>/
upload-file`). The release type follows the version: `beta` or `alpha` in it, else `release`.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tomllib
import urllib.request
import uuid
import zipfile
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "tools" / "curseforge.toml"
CLIENTS = ("forever", "retail")
CLIENT_NAMES = {"forever": "WoW Forever", "retail": "retail"}
API = "https://wow.curseforge.com"
STAMP = (1980, 1, 1, 0, 0, 0)


class UploadError(Exception):
    pass


@dataclass
class Upload:
    project: str
    project_id: int
    version: str
    zip_path: Path
    metadata: dict
    problems: list[str] = field(default_factory=list)


def load_config(path: Path = CONFIG) -> dict:
    with path.open("rb") as f:
        config = tomllib.load(f)
    for key in ("projects", "external", "game_versions"):
        if key not in config:
            raise UploadError(f"{path.name}: no [{key}] section")
    return config


def release_type(version: str) -> str:
    v = version.lower()
    if "alpha" in v:
        return "alpha"
    if "beta" in v:
        return "beta"
    return "release"


def relations(config: dict, project: str, client: str) -> tuple[list[dict], list[str]]:
    """The relations of one project's file for one client, and the unverified names among them.
    A companion that does not exist for the client is left out: retail never relates to QuestieDB.
    """
    p = config["projects"][project]
    out: list[dict] = []
    unverified: list[str] = []
    for kind, names in (
        ("requiredDependency", p.get("required", [])),
        ("optionalDependency", p.get("optional", [])),
    ):
        for name in names:
            if name in config["projects"]:
                target = config["projects"][name]
            elif name in config["external"]:
                target = config["external"][name]
                if client not in target.get("clients", []):
                    continue
            else:
                raise UploadError(f"{project}: relation {name} is neither a project nor external")
            out.append({"slug": target["slug"], "type": kind})
            if not target.get("verified", False):
                unverified.append(f"{name} ({target['slug']})")
    return out, unverified


def read_manifest(release_dir: Path, client: str) -> dict[str, dict]:
    path = release_dir / "manifest.json"
    if not path.is_file():
        raise UploadError(f"no {path}: run tools/release.py --client {client} first")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("client") != client:
        raise UploadError(f"{path} is for {manifest.get('client')}, not {client}")
    return {p["addon"]: p for p in manifest["packages"]}


def project_zip(release_dir: Path, packages: dict[str, dict], folders: list[str], out: Path) -> int:
    """The project's upload zip: every folder's release zip merged, entries sorted, fixed times.
    A folder the release has no zip for (an optional pack without data) is left out."""
    entries: dict[str, bytes] = {}
    for folder in folders:
        pkg = packages.get(folder)
        if not pkg:
            continue
        with zipfile.ZipFile(release_dir / pkg["file"]) as zf:
            for name in zf.namelist():
                entries[name] = zf.read(name)
    if not entries:
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, entries[name])
    tmp.replace(out)
    return len(entries)


def plan(
    config: dict,
    client: str,
    release_dir: Path,
    only: set[str] | None,
    changelog: str,
    version_suffix: str = "",
) -> list[Upload]:
    """The uploads of one client. `version_suffix` follows the TOC version in the file's name and
    display name: the book's daily editions (tools/book_update.py) ship new data under the same
    code version."""
    packages = read_manifest(release_dir, client)
    uploads: list[Upload] = []
    for project, p in config["projects"].items():
        if only and project not in only:
            continue
        main = packages.get(p["folders"][0])
        if not main:
            continue  # not in this release
        version = main["version"] + version_suffix
        target = release_dir / "curseforge" / f"{project}-v{version}-{client}.zip"
        if not project_zip(release_dir, packages, p["folders"], target):
            continue
        rels, unverified = relations(config, project, client)
        problems = [f"relation {u} is not verified" for u in unverified]
        if not p.get("verified", False):
            problems.append(f"the project slug {p['slug']} is not verified")
        if not p.get("id"):
            problems.append("no CurseForge project id (roadmap B1.8)")
        if not config["game_versions"].get(client):
            problems.append(f"no CurseForge game version known for {CLIENT_NAMES[client]}")
        title = p.get("title", project)
        metadata = {
            "changelog": changelog or f"{title} {version} for {CLIENT_NAMES[client]}.",
            "changelogType": "markdown",
            "displayName": f"{title} {version} ({CLIENT_NAMES[client]})",
            "gameVersionNames": list(config["game_versions"].get(client, [])),
            "releaseType": release_type(version),
            "relations": {"projects": rels},
        }
        uploads.append(Upload(project, int(p.get("id") or 0), version, target, metadata, problems))
    return uploads


Transport = Callable[[urllib.request.Request], bytes]


def _urlopen(request: urllib.request.Request) -> bytes:
    with urllib.request.urlopen(request, timeout=120) as response:  # the fixed https API URL
        return response.read()


def game_version_ids(names: list[str], token: str, transport: Transport) -> list[int]:
    request = urllib.request.Request(f"{API}/api/game/versions", headers={"X-Api-Token": token})
    versions = json.loads(transport(request))
    ids = []
    for name in names:
        match = [v["id"] for v in versions if v.get("name") == name]
        if not match:
            raise UploadError(f"CurseForge lists no game version named {name}")
        ids.append(match[0])
    return ids


def send(upload: Upload, version_ids: list[int], token: str, transport: Transport) -> dict:
    metadata = {k: v for k, v in upload.metadata.items() if k != "gameVersionNames"}
    metadata["gameVersions"] = version_ids
    boundary = uuid.uuid4().hex
    body = b"".join(
        [
            f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n'.encode(),
            b"Content-Type: application/json\r\n\r\n",
            json.dumps(metadata).encode(),
            f"\r\n--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="file"; filename="',
            upload.zip_path.name.encode(),
            b'"\r\n',
            b"Content-Type: application/zip\r\n\r\n",
            upload.zip_path.read_bytes(),
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    request = urllib.request.Request(
        f"{API}/api/projects/{upload.project_id}/upload-file",
        data=body,
        method="POST",
        headers={"X-Api-Token": token, "Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    return json.loads(transport(request) or b"{}")


def main(argv: list[str] | None = None, transport: Transport = _urlopen) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--client", choices=CLIENTS, required=True)
    parser.add_argument("--release-dir", type=Path)
    parser.add_argument("--only", help="comma-separated project names")
    parser.add_argument("--changelog", type=Path)
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--send", action="store_true", help="upload; without it a dry run")
    args = parser.parse_args(argv)
    release_dir = args.release_dir or ROOT / "build" / "release" / args.client
    only = set(args.only.split(",")) if args.only else None
    changelog = args.changelog.read_text(encoding="utf-8") if args.changelog else ""
    try:
        config = load_config(args.config)
        uploads = plan(config, args.client, release_dir, only, changelog)
    except UploadError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    for u in uploads:
        print(f"{u.project} {u.version} -> {u.zip_path.name}")
        print("  " + json.dumps(u.metadata["relations"]["projects"]))
        for problem in u.problems:
            print(f"  not ready: {problem}")
    if not args.send:
        print("dry run: nothing sent (--send uploads)")
        return 0
    blocked = [u for u in uploads if u.problems]
    if blocked:
        print(
            f"error: {len(blocked)} of {len(uploads)} files are not ready, nothing sent",
            file=sys.stderr,
        )
        return 1
    token = os.environ.get("CF_API_KEY")
    if not token:
        print("error: CF_API_KEY is not set", file=sys.stderr)
        return 1
    try:
        ids = game_version_ids(config["game_versions"][args.client], token, transport)
        for u in uploads:
            answer = send(u, ids, token, transport)
            print(f"sent {u.project}: file id {answer.get('id')}")
    except (UploadError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
