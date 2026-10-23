"""The glyph set (styling round ST4): reproducible, inside its canvas, white body and dark rim, and
the preview sheet carries every glyph."""

import glyph_sheet
import glyphs


def test_every_glyph_is_reproducible_and_fits_its_canvas():
    size = glyphs.SIZE
    for kind in glyphs.GLYPHS:
        pixels = glyphs.draw(kind)
        assert pixels == glyphs.draw(kind), f"{kind} is not deterministic"
        assert len(pixels) == size * size
        # two pixels of air on every side: the rim fits, and the game's bilinear filter never
        # pulls a neighbour texel in
        drawn = [(i % size, i // size) for i, (_, alpha) in enumerate(pixels) if alpha > 0]
        xs, ys = [x for x, _ in drawn], [y for _, y in drawn]
        assert min(xs) >= 2 and min(ys) >= 2, f"{kind} reaches the top or left edge"
        assert max(xs) <= size - 3 and max(ys) <= size - 3, (
            f"{kind} reaches the bottom or right edge"
        )
        # a white body and a dark rim, both present
        assert any(grey == 255 and alpha == 255 for grey, alpha in pixels), f"{kind} has no body"
        assert any(grey == 0 and alpha == 255 for grey, alpha in pixels), f"{kind} has no rim"


def test_tga_and_png_headers():
    pixels = glyphs.draw("gold")
    tga = glyphs.tga(pixels)
    assert tga[2] == 2 and tga[16] == 32 and tga[17] == 0x28  # true colour, 32 bit, top-left
    assert len(tga) == 18 + glyphs.SIZE * glyphs.SIZE * 4
    png = glyph_sheet.png(pixels)
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and png == glyph_sheet.png(pixels)


def test_the_preview_sheet_carries_every_glyph(tmp_path):
    out = tmp_path / "icons.html"
    assert glyph_sheet.main(["--out", str(out)]) == 0
    text = out.read_text(encoding="utf-8")
    assert "__GLYPHS__" not in text and text.startswith("<title>Bastian's Glyphs</title>")
    for kind in glyphs.GLYPHS:
        assert f'"{kind}": {{"src": "data:image/png;base64,' in text
