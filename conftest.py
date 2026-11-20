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
"""

import atexit
import os
import shutil
import tempfile

_HOME = tempfile.mkdtemp(prefix="bastians-test-home-")
atexit.register(shutil.rmtree, _HOME, ignore_errors=True)
for _name in ("HOME", "USERPROFILE"):  # POSIX, Windows (Path.home() reads these)
    os.environ[_name] = _HOME
for _name in ("HOMEDRIVE", "HOMEPATH"):  # Windows' fallback when USERPROFILE is unset
    os.environ.pop(_name, None)
