"""TOC check (nfr.md gate 5): interface, version, listed files exist, all Lua/XML files listed."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
CODE_SUFFIXES = {".lua", ".xml"}
GENERATED_DIR = "Generated"
DIRECTIVE = re.compile(r"^##\s*([^:]+?)\s*:\s*(.*?)\s*$")


def parse_toc(text: str) -> tuple[dict[str, str], list[str]]:
    """Return (directives, listed files) of a TOC text."""
    meta: dict[str, str] = {}
    files: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            match = DIRECTIVE.match(line)
            if match:
                meta[match.group(1)] = match.group(2)
        elif not line.startswith("#"):
            files.append(line)
    return meta, files


def _norm(name: str) -> str:
    return name.replace("\\", "/").lower()


def check_addon(folder: Path) -> list[str]:
    """Return a list of problems for one addon folder (empty when fine)."""
    name = folder.name
    toc = folder / f"{name}.toc"
    if not toc.is_file():
        return [f"{name}: missing {name}.toc"]
    meta, files = parse_toc(toc.read_text(encoding="utf-8"))
    problems: list[str] = []
    if not meta.get("Interface"):
        problems.append(f"{name}: no '## Interface' line")
    if not meta.get("Version"):
        problems.append(f"{name}: no '## Version' line")
    listed = {_norm(f) for f in files}
    seen: set[str] = set()
    for entry in files:
        if _norm(entry) in seen:
            problems.append(f"{name}: file listed twice in TOC: {entry}")
        seen.add(_norm(entry))
    for entry in files:
        parts = entry.replace("\\", "/").split("/")
        if GENERATED_DIR in parts[:-1]:
            continue  # build output (python -m bastians_build); absent in a fresh checkout
        if not (folder / "/".join(parts)).is_file():
            problems.append(f"{name}: listed file does not exist: {entry}")
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in CODE_SUFFIXES:
            continue
        rel = path.relative_to(folder)
        if GENERATED_DIR in rel.parts:
            continue
        if rel.as_posix().lower() == "bindings.xml":
            continue  # the client loads Bindings.xml by name; it is never listed in the TOC
        if rel.as_posix().lower() not in listed:
            problems.append(f"{name}: file not listed in TOC: {rel.as_posix()}")
    return problems


def check_all(addons_dir: Path = ADDONS) -> list[str]:
    """Check every addon folder that has a TOC or looks like an addon folder."""
    problems: list[str] = []
    for folder in sorted(p for p in addons_dir.iterdir() if p.is_dir()):
        problems.extend(check_addon(folder))
    return problems


def main() -> int:
    problems = check_all()
    for problem in problems:
        print(problem)
    if problems:
        return 1
    count = sum(1 for p in ADDONS.iterdir() if p.is_dir())
    print(f"TOC check OK ({count} addons)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
