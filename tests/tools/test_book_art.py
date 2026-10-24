"""tools/book_art.py: a picture becomes a 512 x 256 BLP2 with DXT1 and its mipmaps (the header the
map art's check reads, a texture Pillow decodes back to the picture) and a 1024 x 512 JPEG, both
cut to 2:1 from the middle; only pictures of pages are installed, stale textures go, and the same
picture gives the same bytes."""

import importlib.util
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))
spec = importlib.util.spec_from_file_location("book_art", ROOT / "tools" / "book_art.py")
book_art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(book_art)

Image = pytest.importorskip("PIL.Image")


def picture(path: Path, size=(1376, 768)) -> Path:
    """A 16:9 test picture: a red band in the middle third, blue above and below it."""
    im = Image.new("RGB", size, (30, 60, 200))
    w, h = size
    for y in range(h // 3, 2 * h // 3):
        for x in range(0, w, 1):
            im.putpixel((x, y), (200, 40, 30))
    im.save(path, "JPEG", quality=95)
    return path


def test_the_game_texture_is_a_dxt1_blp_with_its_mipmaps(tmp_path):
    from bastians_build.overview import texture_size

    data = book_art.game_texture(picture(tmp_path / "p.jpg"))
    blp = tmp_path / "p.blp"
    blp.write_bytes(data)
    assert texture_size(blp) == (512, 256)
    sizes = struct.unpack("<16I", data[20 + 64 : 20 + 128])
    assert [s for s in sizes if s] == [
        max(1, (512 >> i) // 4) * max(1, (256 >> i) // 4) * 8 for i in range(10)
    ]
    with Image.open(blp) as im:
        decoded = im.convert("RGB")
    assert decoded.size == (512, 256)
    r, _, b = decoded.getpixel((256, 128))  # the red band survives the compression
    assert r > 150 and b < 90
    assert book_art.game_texture(tmp_path / "p.jpg") == data  # deterministic


def test_a_flat_block_has_one_colour_and_the_web_picture_is_1024_by_512(tmp_path):
    flat = book_art.dxt1_block([(10, 20, 30)] * 16)
    c0, c1, bits = struct.unpack("<HHI", flat)
    assert c0 == c1 and bits == 0
    with Image.open(
        __import__("io").BytesIO(book_art.web_image(picture(tmp_path / "w.jpg")))
    ) as im:
        assert im.format == "JPEG" and im.size == (1024, 512)


def test_install_takes_pages_only_and_removes_stale_textures(tmp_path):
    art = tmp_path / "art"
    art.mkdir()
    picture(art / "baeldun-dig.jpg", (320, 180))
    picture(art / "not-a-page.jpg", (320, 180))
    packs = tmp_path / "packs"
    stale = packs / book_art.ADDON / book_art.ART_DIR / "retired-page.blp"
    stale.parent.mkdir(parents=True)
    stale.write_bytes(b"old")
    done = book_art.install(art, packs, {"baeldun-dig", "bandage-bargain"})
    assert done == ["baeldun-dig"]
    target = packs / book_art.ADDON / book_art.ART_DIR
    assert sorted(p.name for p in target.iterdir()) == ["baeldun-dig.blp"]
    first = (target / "baeldun-dig.blp").stat().st_mtime_ns
    assert book_art.install(art, packs, {"baeldun-dig"}) == ["baeldun-dig"]
    assert (target / "baeldun-dig.blp").stat().st_mtime_ns == first  # unchanged picture: kept
    assert book_art.install(tmp_path / "none", packs, {"baeldun-dig"}) == []
    assert not (target / "baeldun-dig.blp").exists()


def test_the_page_ids_are_the_books_pages():
    ids = book_art.page_ids()
    assert {"baeldun-dig", "preface"} <= ids and "README" not in ids
