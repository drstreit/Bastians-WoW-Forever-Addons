"""The website (site/, GitHub Pages): every image it names exists, it loads nothing from other
hosts, the SVGs carry no script, no event handler and no link out, and the avatars CurseForge takes
are 512 px squares. The owner's artwork in site/media is the master (23.10.2026)."""

import re
from pathlib import Path

import pytest

SITE = Path(__file__).resolve().parents[2] / "site"
PAGE = SITE / "index.html"
SVGS = sorted((SITE / "media").glob("*.svg"))


def test_every_image_the_page_names_exists():
    html = PAGE.read_text(encoding="utf-8")
    named = set(re.findall(r'(?:src|href)="(media/[^"]+)"', html))
    assert named, "the page names no image"
    assert sorted(n for n in named if not (SITE / n).is_file()) == []


def test_the_page_loads_nothing_from_other_hosts():
    html = PAGE.read_text(encoding="utf-8")
    assert not re.search(r'<script[^>]+src="https?:', html)
    assert not re.search(r'<link[^>]+rel="(?:stylesheet|preconnect)"[^>]+href="https?:', html)
    assert not re.search(r'<img[^>]+src="https?:', html)
    assert "@import" not in html and "url(http" not in html


@pytest.mark.parametrize("svg", SVGS, ids=lambda p: p.name)
def test_the_svgs_carry_no_script_and_no_link_out(svg: Path):
    text = svg.read_text(encoding="utf-8")
    assert not re.search(r"<script|<foreignObject|\son[a-z]+\s*=", text, re.I)
    assert not re.search(r'(?:xlink:)?href\s*=\s*"(?!#|data:)', text), "an external reference"
    assert "url(http" not in text


def test_the_avatars_are_512_px_squares():
    from PIL import Image

    for name in ("bastians-suite.png", "bastians-suite-black.png", "bastians-data.png"):
        with Image.open(SITE / "media" / name) as im:
            assert im.size == (512, 512), name
