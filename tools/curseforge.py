"""CurseForge upload per client (ADR 0015, ADR 0019): one file per project with that client's game
versions and relations; two projects, the suite and its data, and the suite requires the data, so
the CurseForge app installs both with one click.

Usage: python tools/curseforge.py --client forever|retail [--release-dir build/release/<client>]
       [--only Bastians_Quests,...] [--changelog <file>] [--send]

Reads `tools/curseforge.toml` and the release manifest that `tools/release.py` wrote for the
client. For every project it writes the upload zip (the project's folders from the release zips;
Data's file carries its packs) to `<release-dir>/curseforge/` and prints the metadata. Without
`--send` nothing leaves the machine. `--send` needs the upload token (CF_API_KEY, else the
API-TOKEN line of ~/.curseforge/.secrets; never stored in the repo), a project id and a verified
slug for every project and relation it touches, and at least one game version name for the
client; it resolves
the names to ids (`GET /api/game/versions`) and posts each file (`POST /api/projects/<id>/
upload-file`). The release type follows the version: `beta` or `alpha` in it, else `release`.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tomllib
import urllib.error
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
# the owner's upload token, outside the repo: a line API-TOKEN=<token> (the environment wins)
SECRETS = Path.home() / ".curseforge" / ".secrets"
STAMP = (1980, 1, 1, 0, 0, 0)
# a copy of the last file sent per project and client: what players have (the daily Data edition
# boots its packs with the Suite kept here, tools/data_update.py)
RELEASED = ROOT / ".local" / "released"


class UploadError(Exception):
    pass


def _secret(variable: str, line: str, env: dict | None, secrets: Path) -> str | None:
    env = os.environ if env is None else env
    if env.get(variable):
        return env[variable]
    if secrets.is_file():
        for text in secrets.read_text(encoding="utf-8").splitlines():
            m = re.match(rf"\s*{re.escape(line)}\s*[=:]\s*(\S+)", text)
            if m:
                return m.group(1).strip("\"'")
    return None


def api_token(env: dict | None = None, secrets: Path = SECRETS) -> str | None:
    """The upload token: CF_API_KEY from the environment, else the API-TOKEN line of the owner's
    secrets file (generated at authors.curseforge.com, settings, API tokens; never in the repo)."""
    return _secret("CF_API_KEY", "API-TOKEN", env, secrets)


# ---- the read API: whether a sent file went live, and the
# projects' download counts. Its key is not the upload token: CF_CORE_API_KEY, else the
# CURSEFORGE-API-FOR-STUDIOS line of the secrets file (console.curseforge.com). It reads only.
CORE_API = "https://api.curseforge.com"
FILE_STATUS = {
    1: "processing",
    2: "changes required",
    3: "under review",
    4: "approved",
    5: "rejected",
    6: "malware detected",
    7: "deleted",
    8: "archived",
    9: "testing",
    10: "released",
    11: "ready for review",
    12: "deprecated",
    13: "baking",
    14: "awaiting publishing",
    15: "failed publishing",
}
LIVE = frozenset({4, 10})  # players get the file
REFUSED = frozenset({2, 5, 6, 7, 8, 12, 15})  # they never will


def core_key(env: dict | None = None, secrets: Path = SECRETS) -> str | None:
    return _secret("CF_CORE_API_KEY", "CURSEFORGE-API-FOR-STUDIOS", env, secrets)


def core_get(path: str, key: str, transport: Transport) -> dict:
    request = urllib.request.Request(
        f"{CORE_API}{path}", headers={"x-api-key": key, "Accept": "application/json"}
    )
    return json.loads(transport(request))


def file_state(project_id: int, file_id: int, key: str, transport: Transport) -> tuple[int, bool]:
    """(fileStatus, isAvailable) of a project's file."""
    data = core_get(f"/v1/mods/{project_id}/files/{file_id}", key, transport)["data"]
    return int(data["fileStatus"]), bool(data.get("isAvailable"))


def download_count(project_id: int, key: str, transport: Transport) -> int:
    return int(core_get(f"/v1/mods/{project_id}", key, transport)["data"]["downloadCount"])


# A project's own status in the read API (`data.status`). Measured 11.11.2026: Bastian's Suite,
# approved since 24.10.2026, answers 4 with isAvailable true; Bastian's Maps answered 1 on
# 10.11.2026 (new) and 2 with isAvailable false the day after. The names are CurseForge's
# documented ones (assumed for the values not seen here).
PROJECT_STATUS = {
    1: "new",
    2: "changes required",
    3: "under soft review",
    4: "approved",
    5: "rejected",
    6: "changes made",
    7: "inactive",
    8: "abandoned",
    9: "deleted",
    10: "under review",
}
PROJECT_LIVE = 4


def project_state(project_id: int, key: str, transport: Transport) -> tuple[int, bool]:
    """(status, isAvailable) of a project: whether a player can install it."""
    data = core_get(f"/v1/mods/{project_id}", key, transport)["data"]
    return int(data["status"]), bool(data.get("isAvailable"))


@dataclass
class Upload:
    project: str
    project_id: int
    version: str
    zip_path: Path
    metadata: dict
    problems: list[str] = field(default_factory=list)
    later: list[str] = field(default_factory=list)  # relations that wait for an approval


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
    A project of ours that CurseForge has not approved yet (`approved = false`) is left out too:
    CurseForge refuses a relation to it ("does not exist, is not accessible"); `pending` names it.
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
            if target.get("approved", True) is False:
                continue  # pending(): added once CurseForge approves the project
            entry: dict = {"slug": target["slug"], "type": kind}
            if target.get("id"):
                entry["projectID"] = target["id"]  # an exact match, as the upload API allows
            out.append(entry)
            if not target.get("verified", False):
                unverified.append(f"{name} ({target['slug']})")
    return out, unverified


def pending(config: dict, project: str) -> list[str]:
    """The relations left out while their project waits for CurseForge's approval."""
    p = config["projects"][project]
    return [
        f"{kind} {name}"
        for kind, names in (
            ("requires", p.get("required", [])),
            ("optional", p.get("optional", [])),
        )
        for name in names
        if config["projects"].get(name, {}).get("approved", True) is False
    ]


def carried_folders(config: dict, project: str) -> list[str]:
    """The folders a project's file carries: its own, and those of every project of ours it
    requires that CurseForge has not approved (`approved = false`).

    A player cannot install a project in review, and CurseForge refuses a relation to it. When
    the map's pictures became their own project (ADR 0068) the Suite's file dropped their five
    folders at once, while Bastian's Maps was still in review: 2.2.0 and 2.3.0 (11.11.2026) went
    out as a Suite without pictures and with no way for a player to get them. So until a
    required project is approved its folders ride in the file that requires it; with
    `approved = true` they leave and the relation takes their place (ADR 0074, decision 9)."""
    p = config["projects"][project]
    folders = list(p["folders"])
    for name in p.get("required", []):
        other = config["projects"].get(name)
        if other is not None and other.get("approved", True) is False:
            folders += [f for f in other["folders"] if f not in folders]
    return folders


def read_manifest(release_dir: Path, client: str) -> dict[str, dict]:
    path = release_dir / "manifest.json"
    if not path.is_file():
        raise UploadError(f"no {path}: run tools/release.py --client {client} first")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("client") != client:
        raise UploadError(f"{path} is for {manifest.get('client')}, not {client}")
    return {p["addon"]: p for p in manifest["packages"]}


def with_suffix(toc: bytes, suffix: str) -> bytes:
    """A TOC whose `## Version:` line carries the suffix (a Data edition's "+data.<date>.<n>")."""
    lines = toc.split(b"\n")
    for i, line in enumerate(lines):
        if line.startswith(b"## Version:"):
            end = b"\r" if line.endswith(b"\r") else b""
            lines[i] = line.rstrip(b"\r").rstrip() + suffix.encode() + end
    return b"\n".join(lines)


def project_zip(
    release_dir: Path,
    packages: dict[str, dict],
    folders: list[str],
    out: Path,
    version_suffix: str = "",
) -> int:
    """The project's upload zip: every folder's release zip merged, entries sorted, fixed times.
    A folder the release has no zip for (an optional pack without data) is left out. A version
    suffix goes into every folder's TOC too, so the game shows the edition (ADR 0021)."""
    entries: dict[str, bytes] = {}
    for folder in folders:
        pkg = packages.get(folder)
        if not pkg:
            continue
        with zipfile.ZipFile(release_dir / pkg["file"]) as zf:
            for name in zf.namelist():
                data = zf.read(name)
                if version_suffix and name == f"{folder}/{folder}.toc":
                    data = with_suffix(data, version_suffix)
                entries[name] = data
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
        folders = carried_folders(config, project)
        if not project_zip(release_dir, packages, folders, target, version_suffix):
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
        }
        if rels:  # CurseForge refuses an empty list (error 1002, 23.10.2026): no field then
            metadata["relations"] = {"projects": rels}
        uploads.append(
            Upload(
                project,
                int(p.get("id") or 0),
                version,
                target,
                metadata,
                problems,
                pending(config, project),
            )
        )
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


def keep_sent(upload: Upload, file_id: object, client: str, root: Path | None = None) -> Path:
    """Keeps the sent file as `<root>/<client>/<project>.zip` (default root: RELEASED) with its
    version and file id beside it (`<project>.json`), replacing the one before."""
    folder = (root or RELEASED) / client
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{upload.project}.zip"
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_bytes(upload.zip_path.read_bytes())
    tmp.replace(target)
    meta = {"project": upload.project, "version": upload.version, "file_id": file_id}
    (folder / f"{upload.project}.json").write_text(
        json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    return target


def kept(project: str, client: str, root: Path | None = None) -> Path | None:
    """The last sent file of a project for a client, or None when none was kept."""
    path = (root or RELEASED) / client / f"{project}.zip"
    return path if path.is_file() else None


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
        print("  " + json.dumps(u.metadata.get("relations", {}).get("projects", [])))
        for problem in u.problems:
            print(f"  not ready: {problem}")
        for later in u.later:
            print(f"  later: {later}, once CurseForge approves it")
    if not args.send:
        print("dry run: nothing sent (--send uploads)")
        return 0
    if args.client not in config.get("release_clients", CLIENTS):
        print(
            f"error: {args.client} is not a release client (release_clients in {args.config.name})",
            file=sys.stderr,
        )
        return 1
    blocked = [u for u in uploads if u.problems]
    if blocked:
        print(
            f"error: {len(blocked)} of {len(uploads)} files are not ready, nothing sent",
            file=sys.stderr,
        )
        return 1
    token = api_token()
    if not token:
        print(
            f"error: no upload token: set CF_API_KEY or write API-TOKEN=<token> to {SECRETS}",
            file=sys.stderr,
        )
        return 1
    try:
        ids = game_version_ids(config["game_versions"][args.client], token, transport)
        for u in uploads:
            answer = send(u, ids, token, transport)
            print(f"sent {u.project}: file id {answer.get('id')}")
            keep_sent(u, answer.get("id"), args.client)
    except urllib.error.HTTPError as err:
        # CurseForge says why in the body ({"errorCode": .., "errorMessage": ..})
        print(
            f"error: HTTP {err.code}: {err.read().decode('utf-8', 'replace')[:500]}",
            file=sys.stderr,
        )
        return 1
    except (UploadError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
