"""Copy the Bastians_Probe saved variables of a client into data/probe/<date>-<client>-<build>.lua.

Usage: python tools/probe_import.py --client forever|retail [--wow <client folder>]
The client folder is remembered by tools/install.py in .local/install.toml.
"""

import argparse
import re
import sys
from pathlib import Path

from install import CONFIG_PATH, ROOT, InstallError, resolve_client_dir

OUT_DIR = ROOT / "data" / "probe"
SV_NAME = "Bastians_Probe.lua"
META_RE = {
    "client": re.compile(r'\["client"\]\s*=\s*"([a-z]+)"'),
    "build": re.compile(r'\["build"\]\s*=\s*"(\d+)"'),
    "updated": re.compile(r'\["updated"\]\s*=\s*"(\d{4}-\d{2}-\d{2})T'),
}


def find_saved_variables(client_dir: Path) -> Path:
    """The newest Bastians_Probe.lua below WTF/Account/*/SavedVariables."""
    candidates = sorted(
        (client_dir / "WTF" / "Account").glob(f"*/SavedVariables/{SV_NAME}"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise InstallError(
            f"No {SV_NAME} below {client_dir / 'WTF' / 'Account'}. "
            "Run /bprobe in game, then /reload or log out so WoW writes the file."
        )
    return candidates[0]


def read_meta(text: str) -> dict[str, str]:
    """client, build and date of the probe run, read from the saved file."""
    meta = {}
    for key, pattern in META_RE.items():
        match = pattern.search(text)
        if not match:
            raise InstallError(f"The saved file has no meta.{key}; was /bprobe run?")
        meta[key] = match.group(1)
    return meta


def import_probe(source: Path, out_dir: Path) -> tuple[Path, bool]:
    """Copy source to out_dir under its canonical name. Returns (path, changed)."""
    text = source.read_text(encoding="utf-8")
    meta = read_meta(text)
    target = out_dir / f"{meta['updated']}-{meta['client']}-{meta['build']}.lua"
    if target.is_file() and target.read_text(encoding="utf-8") == text:
        return target, False
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".lua.tmp")
    tmp.write_text(text, encoding="utf-8", newline="")
    tmp.replace(target)
    return target, True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import Bastians_Probe results into data/probe.")
    parser.add_argument("--client", required=True, choices=("forever", "retail"))
    parser.add_argument("--wow", help="client folder that contains Interface/AddOns (remembered)")
    args = parser.parse_args(argv)
    try:
        client_dir = resolve_client_dir(args.client, args.wow, CONFIG_PATH)
        target, changed = import_probe(find_saved_variables(client_dir), OUT_DIR)
    except InstallError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    print(f"{'written' if changed else 'unchanged'}: {target.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
