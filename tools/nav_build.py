"""Build the walk network of one client (ADR 0025, route.md "Walk network"): the terrain cells and
the graph per continent, into .local/out/nav_<client>/ (<continent>.json and .png, meta.json).

Usage: python tools/nav_build.py --client forever|retail [--install <client folder>]
       [--continent 0 ...] [--force] [--navmesh] [--emit [--out addons]]

Steps, each skipped when its output is current:
1. `clientdump db2 LiquidType` (the liquids that block, from their names) and `clientdump terrain`
   per continent into .local/out/terrain_<client>/: first without roads (to learn the ground
   textures), then with the road textures (their listfile names match nav.toml [roads]).
2. The nodes: build/nav-nodes-<client>.json, which the data build writes (run
   tools/build_client.py --client <client> first), plus the connector ends of nav_<client>.toml.
3. `clientdump navgraph` per continent: the graph JSON and a picture to look at.
   With --navmesh, also `clientdump navmesh` per continent (ADR 0026, the movement mesh) into
   .local/out/navmesh_<client>/ (<Directory>.navmesh and .navmesh.json), same road textures, and
   `clientdump navnet` (W3a, the local level) into .local/out/navnet_<client>/<continent>.json.
4. With --emit: `python -m bastians_build nav` into --out (addons/ holds one client at a time:
   tools/build_client.py runs that step too).

The client folder comes from .local/install.toml [clients] unless --install names it; the tool
refuses a folder whose build does not belong to the client (a Forever build is 1.x). The listfile
(wowdev/wow-listfile, build time only, nothing from it ships) is
.local/listfile/community-listfile.csv:
    gh release download -R wowdev/wow-listfile --pattern community-listfile.csv -D .local/listfile
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline"))

from bastians_build.files import write_text  # noqa: E402
from bastians_build.nav import graph_nodes, load_links  # noqa: E402

OUT = ROOT / ".local" / "out"
INSTALL = ROOT / ".local" / "install.toml"
LISTFILE = ROOT / ".local" / "listfile" / "community-listfile.csv"
CONFIG = ROOT / "pipeline" / "config"
PROJECT = ROOT / "tools" / "clientdump"
CLIENTS = ("forever", "retail")
GRAPH_KEYS = (
    "max_slope",
    "swim_depth",
    "swim_factor",
    "road_factor",
    "road_min",
    "deep_blocked",
    "lattice",
    "lattice_snap",
    "road_snap",
    "neighbours",
    "radius",
    "prune",
    "simplify",
    "min_island",
    "height_tolerance",
)


class NavBuildError(Exception):
    pass


def navnet_config(settings: dict, client: str, path: Path) -> list[str]:
    """`clientdump navnet --config` when this client has ground to leave out, else nothing."""
    hidden = (settings.get("hidden") or {}).get(client) or []
    if not hidden:
        return []
    keep = ("continent", "wx", "wy", "z")
    write_text(
        path, json.dumps({"hidden": [{k: h[k] for k in keep} for h in hidden]}, indent=1) + "\n"
    )
    return ["--config", str(path)]


def clientdump(*args: str) -> str:
    cmd = ["dotnet", "run", "--project", str(PROJECT), "-c", "Release", "--no-build", "--", *args]
    run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=False)
    if run.returncode:
        raise NavBuildError(
            f"clientdump {args[0]} failed: {run.stderr.strip() or run.stdout[-400:]}"
        )
    return run.stdout


def check_client(client: str, info: str) -> str:
    """The client build the folder holds; refuses a folder of the other client (25.10.2026: the
    old _classic_beta_ folder lost its .flavor.info and silently opened retail)."""
    m = re.search(r"product=(\S+) version=(\S+)", info)
    if not m:
        raise NavBuildError("clientdump info printed no product and version")
    version = m.group(2)
    is_forever = version.startswith("1.")
    if (client == "forever") != is_forever:
        raise NavBuildError(f"that folder holds {m.group(1)} {version}, not a {client} client")
    return version


def road_textures(textures_tsv: Path, listfile: Path, patterns: list[str]) -> list[str]:
    """`fdid<TAB>path` of the ground textures whose file name matches a road pattern."""
    used = {line.split("\t")[0] for line in textures_tsv.read_text(encoding="utf-8").splitlines()}
    pat = re.compile("|".join(re.escape(p) for p in patterns), re.IGNORECASE)
    out = []
    with listfile.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            fdid, _, path = line.rstrip("\n").partition(";")
            if fdid in used and pat.search(path.rsplit("/", 1)[-1]):
                out.append(f"{fdid}\t{path}")
    return sorted(out)


def liquids(liquid_json: Path, blocked: list[str], ocean: list[str]) -> tuple[list[int], list[int]]:
    data = json.loads(liquid_json.read_text(encoding="utf-8"))
    rows = data["rows"] if isinstance(data, dict) and "rows" in data else data
    items = rows.items() if isinstance(rows, dict) else [(r["ID"], r) for r in rows]

    def match(words: list[str]) -> list[int]:
        pat = re.compile("|".join(re.escape(w) for w in words), re.IGNORECASE)
        return sorted(int(k) for k, r in items if pat.search(str(r.get("Name") or "")))

    return match(blocked), match(ocean)


def continent_maps(client: str, prefix: str) -> dict[int, tuple[str, int]]:
    """Map.db2 id -> (directory, WDT FileDataID) from the clientdump Map JSON."""
    path = OUT / f"{prefix}_Map.json"
    if not path.is_file():
        raise NavBuildError(f"{path} missing: dump Map.db2 first (tools/mapart_extract.py)")
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data["rows"] if isinstance(data, dict) and "rows" in data else data
    items = rows.items() if isinstance(rows, dict) else [(r["ID"], r) for r in rows]
    return {int(k): (r["Directory"], int(r.get("WdtFileDataID") or 0)) for k, r in items}


def install_for(client: str, given: Path | None) -> tuple[Path, str]:
    if given:
        return given, "beta" if client == "forever" else "retail"
    raw = tomllib.loads(INSTALL.read_text(encoding="utf-8")) if INSTALL.is_file() else {}
    folder = (raw.get("clients") or {}).get(client)
    if not folder:
        raise NavBuildError(f"no client folder for {client}: pass --install")
    prefix = ((raw.get("build") or {}).get("dump_prefix") or {}).get(client)
    return Path(folder), prefix or ("beta" if client == "forever" else "retail")


def build(
    client: str,
    install: Path,
    prefix: str,
    continents: list[int],
    force: bool,
    navmesh: bool = False,
) -> Path:
    settings = tomllib.loads((CONFIG / "nav.toml").read_text(encoding="utf-8"))
    continents = continents or list(settings.get("continents") or [0])
    version = check_client(client, clientdump("info", "--install", str(install)))
    print(f"{client}: {install} build {version}")
    terrain_dir = OUT / f"terrain_{client}"
    nav_dir = OUT / f"nav_{client}"
    nav_dir.mkdir(parents=True, exist_ok=True)
    meta_path = nav_dir / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.is_file() else {}
    stale = force or meta.get("build") != version

    liquid_json = OUT / f"{client}_LiquidType.json"
    if stale or not liquid_json.is_file():
        clientdump(
            "db2", "--install", str(install), "--table", "LiquidType", "--out", str(liquid_json)
        )
    blocked, ocean = liquids(
        liquid_json, settings["liquids"]["blocked"], settings["liquids"]["ocean"]
    )

    if not LISTFILE.is_file():
        raise NavBuildError(f"{LISTFILE} missing (see the tool's docstring)")
    maps = continent_maps(client, prefix)
    nodes_path = ROOT / "build" / f"nav-nodes-{client}.json"
    if not nodes_path.is_file():
        raise NavBuildError(f"{nodes_path} missing: run tools/build_client.py --client {client}")
    given = json.loads(nodes_path.read_text(encoding="utf-8"))
    links = load_links(CONFIG / f"nav_{client}.toml")
    graph_cfg = {k: settings["graph"][k] for k in GRAPH_KEYS if k in settings["graph"]}
    graph_cfg |= {"blocked_liquids": blocked, "ocean_liquids": ocean}
    config_path = nav_dir / "config.json"
    write_text(config_path, json.dumps(graph_cfg, indent=1, sort_keys=True) + "\n")

    for continent in continents:
        directory, wdt = maps[continent]
        terrain = terrain_dir / f"{directory}_terrain.bin.gz"
        textures = terrain_dir / f"{directory}_textures.tsv"
        roads_path = terrain_dir / f"{directory}_roads.txt"
        common = [
            "--install",
            str(install),
            "--map",
            str(continent),
            "--wdt-fdid",
            str(wdt),
            "--out",
            str(terrain_dir),
        ]
        if stale or not textures.is_file():
            print(f"  terrain {directory}: learning the ground textures")
            clientdump("terrain", *common)
        roads = road_textures(textures, LISTFILE, settings["roads"]["patterns"])
        old_roads = roads_path.read_text(encoding="utf-8") if roads_path.is_file() else None
        roads_text = "\n".join(roads) + "\n"
        if stale or old_roads != roads_text or not terrain.is_file():
            write_text(roads_path, roads_text)
            print(f"  terrain {directory}: {len(roads)} road textures")
            clientdump("terrain", *common, "--roads", str(roads_path))
        mesh_dir = OUT / f"navmesh_{client}"
        if navmesh and (stale or not (mesh_dir / f"{directory}.navmesh").is_file()):
            print(f"  navmesh {directory}")
            blocked_words = ",".join(settings["liquids"]["blocked"])
            out = clientdump(
                "navmesh",
                *common[:-1],
                str(mesh_dir),
                "--roads",
                str(roads_path),
                "--listfile",
                str(LISTFILE),
                "--blocked",
                blocked_words,
            )
            print(f"  {directory}: " + out.strip().splitlines()[-1])
        if navmesh:
            # the local level of the world graph (W3a) from the mesh and the nodes; reads no client
            net = OUT / f"navnet_{client}" / f"{continent}.json"
            out = clientdump(
                "navnet",
                "--navmesh",
                str(mesh_dir / f"{directory}.navmesh"),
                "--nodes",
                str(nodes_path),
                "--client",
                client,
                "--out",
                str(net),
                *navnet_config(settings, client, OUT / f"navnet_{client}" / "config.json"),
            )
            print(f"  {directory}: " + out.strip().splitlines()[-1])
        nodes_json = nav_dir / f"{continent}.nodes.json"
        write_text(nodes_json, json.dumps(graph_nodes(given, links, continent), indent=1) + "\n")
        out = clientdump(
            "navgraph",
            "--terrain",
            str(terrain),
            "--nodes",
            str(nodes_json),
            "--config",
            str(config_path),
            "--out",
            str(nav_dir / f"{continent}.json"),
            "--png",
            str(nav_dir / f"{continent}.png"),
        )
        for line in out.splitlines():
            if line.startswith(("navgraph:", "nodes:", "edges:")):
                print(f"  {directory}: {line}")
    write_text(meta_path, json.dumps({"build": version, "client": client}, indent=1) + "\n")
    return nav_dir


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--client", required=True, choices=CLIENTS)
    ap.add_argument("--install", type=Path, help="the client folder (default: .local/install.toml)")
    ap.add_argument("--continent", type=int, action="append", default=[], help="Map.db2 id")
    ap.add_argument("--force", action="store_true", help="extract the terrain again")
    ap.add_argument(
        "--navmesh",
        action="store_true",
        help="also build the movement mesh and its local level (ADR 0026)",
    )
    ap.add_argument("--emit", action="store_true", help="write Nav.lua into --out afterwards")
    ap.add_argument("--out", type=Path, default=ROOT / "addons", help="output root for --emit")
    args = ap.parse_args(argv)
    try:
        install, prefix = install_for(args.client, args.install)
        nav_dir = build(args.client, install, prefix, args.continent, args.force, args.navmesh)
    except (NavBuildError, OSError, KeyError, ValueError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print(f"graphs: {nav_dir}")
    if args.emit:
        cmd = [
            sys.executable,
            "-m",
            "bastians_build",
            "nav",
            "--client",
            args.client,
            "--out",
            str(args.out),
        ]
        return subprocess.run(cmd, cwd=ROOT, check=False).returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
