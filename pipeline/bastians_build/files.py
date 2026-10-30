"""Atomic, idempotent file writes (CLAUDE.md §6): temp file next to the target, then replace."""

from __future__ import annotations

import time
from collections.abc import Callable
from pathlib import Path

# The repository lives in OneDrive: right after a build wrote a large file, OneDrive holds it while
# it uploads, and the next build's replace fails with "access denied" (the beta.13 release,
# 29.10.2026, twice in a row). The replace is tried again for a while before it gives up.
REPLACE_TRIES = 40
REPLACE_WAIT_S = 0.5


def replace(tmp: Path, path: Path, sleep: Callable[[float], None] | None = None) -> None:
    """`tmp.replace(path)`, tried again while Windows refuses it (a file held by a sync client)."""
    sleep = sleep or time.sleep
    for _ in range(REPLACE_TRIES - 1):
        try:
            tmp.replace(path)
            return
        except PermissionError:
            sleep(REPLACE_WAIT_S)
    tmp.replace(path)


def write_text(path: Path, text: str) -> bool:
    """Write UTF-8 text with LF line endings. Returns True when the file changed."""
    return write_bytes(path, text.encode("utf-8"))


def write_bytes(path: Path, data: bytes) -> bool:
    """Write bytes as they are. Returns True when the file changed."""
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as fh:
        fh.write(data)
    replace(tmp, path)
    return True
