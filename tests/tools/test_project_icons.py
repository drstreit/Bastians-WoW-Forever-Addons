"""tools/project_icons.py: the CurseForge avatars in site/media are what the generator
draws (pixels, not bytes: PNG compression may differ between zlib builds), all of them 512 px
squares without transparency."""

from pathlib import Path

import pytest

PIL = pytest.importorskip("PIL")
import project_icons  # noqa: E402
from PIL import Image, ImageChops  # noqa: E402

MEDIA = Path(__file__).resolve().parents[2] / "site" / "media"


@pytest.mark.parametrize("name", ["bastians-suite", "bastians-data"])
def test_the_projects_avatars_are_the_generators(name):
    committed = Image.open(MEDIA / f"{name}.png").convert("RGB")
    drawn = project_icons.icons()[name]()
    assert drawn.size == (512, 512) and drawn.mode == "RGB"
    assert ImageChops.difference(drawn, committed).getbbox() is None, (
        f"{name}.png is stale: python tools/project_icons.py"
    )


def test_every_icon_is_committed():
    assert {p.stem for p in MEDIA.glob("*.png")} == set(project_icons.icons())
