"""tools/curseforge.py and tools/curseforge.toml (ADR 0015, ADR 0019): two projects, the suite and
its data; the relations agree with the TOCs, each client's file relates only to what exists for
that client, Data's file carries its packs, and nothing is sent while a slug, a project id or the
client's game version is unknown."""

import json
import zipfile
from pathlib import Path

import curseforge
import pytest
from check_toc import parse_toc

ROOT = Path(__file__).resolve().parents[2]
ADDONS = ROOT / "addons"
COMPANION_OF = {"Spoken_Quests": "Spoken"}  # an app's optional addon -> the companion it belongs to


def config() -> dict:
    return curseforge.load_config()


def project_of(cfg: dict) -> dict[str, str]:
    return {folder: name for name, p in cfg["projects"].items() for folder in p["folders"]}


def toc_fields(folder: str) -> dict:
    fields, _ = parse_toc((ADDONS / folder / f"{folder}.toc").read_text(encoding="utf-8"))
    return fields


def split(value: str | None) -> list[str]:
    return [v.strip() for v in (value or "").split(",") if v.strip()]


def test_every_released_folder_belongs_to_one_project():
    cfg = config()
    folders = [f for p in cfg["projects"].values() for f in p["folders"]]
    assert len(folders) == len(set(folders))
    released = {
        d.name
        for d in ADDONS.iterdir()
        if d.is_dir() and d.name not in ("Bastians_Probe", "Bastians_Data_Nav")
    }
    assert set(folders) == released  # Nav ships no file yet (release.py skips it)


def test_the_relations_cover_every_toc_dependency():
    cfg = config()
    owner = project_of(cfg)
    for name, p in cfg["projects"].items():
        related = set(p.get("required", [])) | set(p.get("optional", []))
        for folder in p["folders"]:
            fields = toc_fields(folder)
            for dep in split(fields.get("Dependencies")):
                if owner.get(dep) == name:
                    continue  # inside the project's own file: a pack on Data, an app on Core
                other = cfg["projects"][owner[dep]]
                if name in other.get("required", []):
                    # Data needs Core, the suite requires Data: the way back is optional, a
                    # required relation both ways would be a cycle (ADR 0019)
                    assert owner[dep] in p.get("optional", []), f"{folder} needs {dep}"
                else:
                    assert owner[dep] in p.get("required", []), f"{folder} needs {dep}"
            for dep in split(fields.get("OptionalDeps")):
                dep = COMPANION_OF.get(dep, dep)
                if dep in cfg["external"]:
                    assert dep in related, f"{folder}: optional {dep} has no relation"
                elif dep in owner and owner[dep] != name:
                    assert owner[dep] in related, f"{folder}: optional {dep} has no relation"


def test_two_projects_the_suite_requires_its_data():
    cfg = config()
    assert set(cfg["projects"]) == {"Bastians_Suite", "Bastians_Data"}
    assert cfg["projects"]["Bastians_Suite"]["required"] == ["Bastians_Data"]
    assert cfg["projects"]["Bastians_Suite"]["folders"][0] == "Bastians_Core"  # its version
    assert all(f.startswith("Bastians_Data") for f in cfg["projects"]["Bastians_Data"]["folders"])


def test_each_clients_file_relates_only_to_what_exists_there():
    cfg = config()
    forever, _ = curseforge.relations(cfg, "Bastians_Suite", "forever")
    retail, _ = curseforge.relations(cfg, "Bastians_Suite", "retail")
    slug = {
        n: (cfg["projects"].get(n) or cfg["external"][n])["slug"] for n in ("QuestieDB", "Spoken")
    }
    assert {"slug": slug["QuestieDB"], "type": "optionalDependency"} in forever
    assert {"slug": slug["Spoken"], "type": "optionalDependency"} in forever
    assert all(r["slug"] not in slug.values() for r in retail)
    data = cfg["projects"]["Bastians_Data"]["slug"]
    assert {"slug": data, "type": "requiredDependency"} in retail
    assert {"slug": "tomtom", "type": "optionalDependency"} in retail
    suite = cfg["projects"]["Bastians_Suite"]["slug"]
    data_retail, _ = curseforge.relations(cfg, "Bastians_Data", "retail")
    assert data_retail == [{"slug": suite, "type": "optionalDependency"}]


def test_release_type_follows_the_version():
    assert curseforge.release_type("1.0.0-beta.5") == "beta"
    assert curseforge.release_type("1.0.0-alpha.1") == "alpha"
    assert curseforge.release_type("1.0.0") == "release"


def fake_release(tmp_path: Path, client: str) -> Path:
    """A release dir with the manifest and zips release.py would write, one file per folder."""
    rel = tmp_path / client
    rel.mkdir()
    packages = []
    folders = [f for p in config()["projects"].values() for f in p["folders"]]
    for folder in folders:
        if folder == "Bastians_Data_Market":
            continue  # an optional pack without data: no zip
        name = f"{folder}-v1.0.0-beta.5.zip"
        with zipfile.ZipFile(rel / name, "w") as zf:
            zf.writestr(f"{folder}/{folder}.toc", f"## Title: {folder}\n")
        packages.append({"addon": folder, "version": "1.0.0-beta.5", "file": name})
    manifest = {"client": client, "packages": packages}
    (rel / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return rel


def test_the_plan_merges_datas_packs_and_names_what_blocks_an_upload(tmp_path: Path):
    rel = fake_release(tmp_path, "forever")
    uploads = {u.project: u for u in curseforge.plan(config(), "forever", rel, None, "")}
    assert set(uploads) == set(config()["projects"])
    data = uploads["Bastians_Data"]
    assert data.zip_path.name == "Bastians_Data-v1.0.0-beta.5-forever.zip"
    with zipfile.ZipFile(data.zip_path) as zf:
        tops = sorted({n.split("/")[0] for n in zf.namelist()})
    assert tops == [
        "Bastians_Data",
        "Bastians_Data_Items",
        "Bastians_Data_Quests",
        "Bastians_Data_Strategies",
        "Bastians_Data_Text_enUS",
        "Bastians_Data_World",
    ]
    assert data.metadata["releaseType"] == "beta"
    assert data.metadata["displayName"] == "Bastian's Data 1.0.0-beta.5 (WoW Forever)"
    suite = uploads["Bastians_Suite"]
    with zipfile.ZipFile(suite.zip_path) as zf:
        assert {n.split("/")[0] for n in zf.namelist()} == set(
            config()["projects"]["Bastians_Suite"]["folders"]
        )
    # Forever is listed as 1.60.1 (23.10.2026); an empty list still refuses the upload
    assert "no CurseForge game version known for WoW Forever" not in data.problems
    empty = config()
    empty["game_versions"]["forever"] = []
    (blocked,) = curseforge.plan(empty, "forever", rel, {"Bastians_Data"}, "")
    assert "no CurseForge game version known for WoW Forever" in blocked.problems
    assert "no CurseForge project id (roadmap B1.8)" in data.problems
    assert any("relation QuestieDB" in p for p in uploads["Bastians_Suite"].problems)
    # the zip is the same for the same input
    first = data.zip_path.read_bytes()
    curseforge.plan(config(), "forever", rel, {"Bastians_Data"}, "")
    assert data.zip_path.read_bytes() == first


def test_a_dry_run_sends_nothing_and_send_refuses_while_not_ready(tmp_path: Path, capsys):
    rel = fake_release(tmp_path, "retail")
    calls = []

    def transport(request):
        calls.append(request)
        return b"[]"

    assert curseforge.main(["--client", "retail", "--release-dir", str(rel)], transport) == 0
    out = capsys.readouterr().out
    assert "dry run: nothing sent" in out and "not ready:" in out
    assert (
        curseforge.main(["--client", "retail", "--release-dir", str(rel), "--send"], transport) == 1
    )
    assert "not ready, nothing sent" in capsys.readouterr().err
    assert calls == []
    # a manifest of the other client is refused
    assert curseforge.main(["--client", "forever", "--release-dir", str(rel)], transport) == 2


def test_send_resolves_the_game_versions_and_posts_each_file(tmp_path: Path, monkeypatch, capsys):
    rel = fake_release(tmp_path, "retail")
    cfg = config()
    for p in cfg["projects"].values():
        p["id"], p["verified"] = 1000 + len(p["slug"]), True
    for e in cfg["external"].values():
        e["verified"] = True
    path = tmp_path / "cf.toml"
    path.write_text(_toml(cfg), encoding="utf-8")
    monkeypatch.setenv("CF_API_KEY", "test-token")
    posts = []

    def transport(request):
        assert request.headers["X-api-token"] == "test-token"
        if request.full_url.endswith("/api/game/versions"):
            return json.dumps([{"id": 7, "name": "11.2.0"}, {"id": 13, "name": "12.1.5"}]).encode()
        posts.append(request)
        return json.dumps({"id": len(posts)}).encode()

    args = ["--client", "retail", "--release-dir", str(rel), "--config", str(path), "--send"]
    args += ["--only", "Bastians_Suite,Bastians_Data"]
    assert curseforge.main(args, transport) == 0
    assert len(posts) == 2
    body = posts[0].data
    meta = json.loads(
        body.split(b"Content-Type: application/json\r\n\r\n", 1)[1].split(b"\r\n--", 1)[0]
    )
    assert meta["gameVersions"] == [13] and "gameVersionNames" not in meta
    assert meta["releaseType"] == "beta"
    assert b'filename="Bastians_Data-v1.0.0-beta.5-retail.zip"' in body or b"Bastians_Suite" in body
    assert "sent Bastians_Data: file id" in capsys.readouterr().out


def _toml(cfg: dict) -> str:
    """A minimal TOML writer for the test's config copy (tables of scalars and string lists)."""

    def value(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, int):
            return str(v)
        if isinstance(v, list):
            return "[" + ", ".join(json.dumps(x) for x in v) + "]"
        return json.dumps(v)

    lines = ["[game_versions]"] + [f"{k} = {value(v)}" for k, v in cfg["game_versions"].items()]
    for section in ("projects", "external"):
        for name, table in cfg[section].items():
            lines.append(f"[{section}.{name}]")
            lines += [f"{k} = {value(v)}" for k, v in table.items()]
    return "\n".join(lines) + "\n"


@pytest.mark.parametrize("client", ["forever", "retail"])
def test_the_real_config_loads_for_both_clients(client):
    cfg = config()
    for name in cfg["projects"]:
        curseforge.relations(cfg, name, client)
