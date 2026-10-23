"""Link addons/* into a WoW client's Interface/AddOns folder (junctions on Windows).

Usage: python tools/install.py --client forever|retail [--wow <client folder>] [--list] [--remove]
The client folder is the one that contains Interface/AddOns, e.g. ...\\World of Warcraft\\_retail_.
"""

import argparse
import os
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS_DIR = ROOT / "addons"
FIXTURE_ADDONS_DIR = ROOT / "tests" / "fixtures" / "addons"  # dev only, with --fixtures
CONFIG_PATH = ROOT / ".local" / "install.toml"
CLIENTS = ("forever", "retail")
EXTENDED_PREFIX = "\\\\?\\"


class InstallError(Exception):
    """A problem the user must fix; main() prints it and exits non-zero."""


def is_link(path: Path) -> bool:
    """True for a symlink or a Windows directory junction."""
    return path.is_symlink() or os.path.isjunction(path)


def link_target(path: Path) -> Path:
    """Resolved target of a link, with the Windows extended-length prefix removed."""
    raw = str(path.readlink())
    raw = raw.removeprefix(EXTENDED_PREFIX)
    return Path(raw).resolve()


def make_link(link: Path, target: Path) -> None:
    """Create a directory junction (Windows) or symlink (elsewhere) at link pointing to target."""
    if sys.platform == "win32":
        import _winapi

        _winapi.CreateJunction(str(target), str(link))
    else:
        link.symlink_to(target, target_is_directory=True)


def remove_link(link: Path) -> None:
    """Remove a link without touching its target."""
    if link.is_symlink():
        link.unlink()
    else:
        link.rmdir()


def addon_folders(addons_dir: Path) -> list[Path]:
    return sorted(p for p in addons_dir.iterdir() if p.is_dir())


def load_config(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    return {k: str(v) for k, v in data.get("clients", {}).items()}


def save_config(path: Path, clients: dict[str, str]) -> None:
    """Atomic write of the per-client folders."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["[clients]"]
    for key in sorted(clients):
        escaped = clients[key].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'{key} = "{escaped}"')
    tmp = path.with_suffix(".toml.tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    tmp.replace(path)


def resolve_client_dir(client: str, wow: str | None, config_path: Path) -> Path:
    """Client folder from --wow (remembered) or from the saved config."""
    clients = load_config(config_path)
    if wow:
        folder = Path(wow).expanduser().resolve()
        if not (folder / "Interface").is_dir():
            raise InstallError(
                f"{folder} has no Interface folder. Pass the client folder, e.g. _retail_."
            )
        clients[client] = str(folder)
        save_config(config_path, clients)
        return folder
    if client not in clients:
        raise InstallError(
            f"No WoW folder known for '{client}'. Run once with "
            '--wow "<folder that contains Interface/AddOns>".'
        )
    return Path(clients[client])


def addons_path(client_dir: Path) -> Path:
    path = client_dir / "Interface" / "AddOns"
    if not path.is_dir():
        raise InstallError(f"{path} does not exist. Check the client folder.")
    return path


def install(addons_dir: Path, dest: Path) -> list[str]:
    """Link every addon folder into dest. Returns one status line per addon."""
    report: list[str] = []
    refused = False
    for src in addon_folders(addons_dir):
        link = dest / src.name
        target = src.resolve()
        if is_link(link):
            if link_target(link) == target:
                report.append(f"ok       {src.name} (already linked)")
                continue
            remove_link(link)
            make_link(link, target)
            report.append(f"replaced {src.name} (pointed elsewhere)")
        elif link.exists():
            refused = True
            report.append(f"REFUSED  {src.name}: a real folder exists at {link}")
        else:
            make_link(link, target)
            report.append(f"linked   {src.name}")
    if refused:
        report.append(
            "Real folders were left alone. Move or delete them yourself "
            "(for example an installed release of the same addon), then run again."
        )
    return report


def remove(addons_dir: Path, dest: Path) -> list[str]:
    """Remove only links that point into our addons folder."""
    report: list[str] = []
    for src in addon_folders(addons_dir):
        link = dest / src.name
        if is_link(link) and link_target(link) == src.resolve():
            remove_link(link)
            report.append(f"removed  {src.name}")
        elif is_link(link) or link.exists():
            report.append(f"skipped  {src.name}: not our link")
    return report


def list_links(addons_dir: Path, dest: Path) -> list[str]:
    report: list[str] = []
    for src in addon_folders(addons_dir):
        link = dest / src.name
        if is_link(link):
            target = link_target(link)
            state = "linked" if target == src.resolve() else "linked elsewhere"
            report.append(f"{src.name}: {state} -> {target}")
        elif link.exists():
            report.append(f"{src.name}: real folder (not ours)")
        else:
            report.append(f"{src.name}: not installed")
    return report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Link the Bastians addons into a WoW client.")
    parser.add_argument("--client", required=True, choices=CLIENTS)
    parser.add_argument("--wow", help="client folder that contains Interface/AddOns (remembered)")
    parser.add_argument(
        "--fixtures",
        action="store_true",
        help="also link the fixture addons under tests/fixtures/addons (development installs only)",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--list", action="store_true", help="show which addons are linked")
    group.add_argument("--remove", action="store_true", help="remove our links")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        client_dir = resolve_client_dir(args.client, args.wow, CONFIG_PATH)
        dest = addons_path(client_dir)
        sources = [ADDONS_DIR] + ([FIXTURE_ADDONS_DIR] if args.fixtures else [])
        lines = []
        for source in sources:
            if args.list:
                lines += list_links(source, dest)
            elif args.remove:
                lines += remove(source, dest)
            else:
                lines += install(source, dest)
    except InstallError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print(f"{args.client}: {dest}")
    for line in lines:
        print(line)
    return 1 if any(line.startswith("REFUSED") for line in lines) else 0


if __name__ == "__main__":
    sys.exit(main())
