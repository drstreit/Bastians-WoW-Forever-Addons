"""Atomic, idempotent file writes (CLAUDE.md §6): temp file next to the target, then replace."""

from __future__ import annotations

from pathlib import Path


def write_text(path: Path, text: str) -> bool:
    """Write UTF-8 text with LF line endings. Returns True when the file changed."""
    data = text.encode("utf-8")
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as fh:
        fh.write(data)
    tmp.replace(path)
    return True
