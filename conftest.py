"""The tests never read the machine they run on: the user's home is an empty folder for the run.

20.11.2026: on its first day the notebook tested every push (tools/ops_ci.py), as the user the
loops run as. A test of the daily run's exit codes builds its configuration without a file, so
the mail account fell back to `~/.bastians/mail.toml`, which exists there, and every test run
mailed "the daily run refused: CurseForge, file 43: REFUSED" to the owner. On the desktop and on
GitHub's runners that file had never existed, so nobody saw the hole.

Every tool finds its settings and keys under the home folder (`Path.home()`: the loops'
ops.toml and mail account, CurseForge's and Cloudflare's keys, the responder's keys). This file
is loaded before any of them is imported and points the home at a fresh temp folder, so what a
tool would find there is nothing, on every machine alike. A test that needs such a file writes
it into its own tmp_path and names it.

One thing of the real home stays reachable: DuckDB's extension cache (`~/.duckdb`, 45 MB, no
settings in it). Without it every run fetched the extensions from the network again and, on
Windows, left them behind in the temp folder (measured the same day: five such folders).
"""

import atexit
import contextlib
import os
import shutil
import sys
import tempfile
from pathlib import Path

_REAL = Path.home()
_HOME = Path(tempfile.mkdtemp(prefix="bastians-test-home-"))
_CACHE = _HOME / ".duckdb"


def _link(source: Path, link: Path) -> None:
    """A folder link: a junction on Windows (a symlink needs a privilege there), else a symlink."""
    with contextlib.suppress(OSError):
        if sys.platform == "win32":
            import _winapi

            _winapi.CreateJunction(str(source), str(link))
        else:
            link.symlink_to(source, target_is_directory=True)


def _clean() -> None:
    with contextlib.suppress(OSError):  # the link itself, never what it points at
        if sys.platform == "win32":
            _CACHE.rmdir()
        else:
            _CACHE.unlink()
    shutil.rmtree(_HOME, ignore_errors=True)


if (_REAL / ".duckdb").is_dir():
    _link((_REAL / ".duckdb").resolve(), _CACHE)
atexit.register(_clean)
for _name in ("HOME", "USERPROFILE"):  # POSIX, Windows (Path.home() reads these)
    os.environ[_name] = str(_HOME)
for _name in ("HOMEDRIVE", "HOMEPATH"):  # Windows' fallback when USERPROFILE is unset
    os.environ.pop(_name, None)
