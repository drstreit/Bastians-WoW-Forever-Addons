"""tools/welcome_art.py: request shape, default spots, overlay and textures (no network)."""

import base64
import json
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import welcome_art  # noqa: E402
from PIL import Image  # noqa: E402


def make_picture(path: Path, size=(320, 180)) -> Path:
    im = Image.new("RGB", size)
    px = im.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = (x * 255 // size[0], y * 255 // size[1], (x + y) % 256)
    im.save(path)
    return path


def test_request_body_text_only():
    body = welcome_art.request_body("hello")
    cfg = body["generationConfig"]["imageConfig"]
    assert cfg == {"aspectRatio": "16:9", "imageSize": "1K"}
    assert body["contents"][0]["parts"] == [{"text": "hello"}]


def test_request_body_edit_has_image_part_first():
    body = welcome_art.request_body("edit", b"\x89PNGdata", "image/png")
    parts = body["contents"][0]["parts"]
    assert len(parts) == 2
    assert base64.b64decode(parts[0]["inline_data"]["data"]) == b"\x89PNGdata"
    assert parts[0]["inline_data"]["mime_type"] == "image/png"
    assert parts[1] == {"text": "edit"}


def test_wanderer_prompts_four_classes():
    prompts = welcome_art.wanderer_prompts(4)
    assert list(prompts) == [f"wanderer-{i}" for i in range(1, 5)]
    text = " ".join(prompts.values())
    for cls in ("night elf hunter", "tauren druid", "dwarf hunter", "human warrior"):
        assert cls in text
    assert all("no text, no interface" in p for p in prompts.values())


def test_wanderer_command_saves_requests_and_images(tmp_path, monkeypatch):
    seen = []

    def fake_call(body, api_key):
        seen.append(body)
        return b"\xff\xd8\xff" + b"jpeg"

    monkeypatch.setattr(welcome_art, "key", lambda: "k")
    monkeypatch.setattr(welcome_art, "call", fake_call)
    assert welcome_art.main(["wanderer", "--out", str(tmp_path), "--n", "4"]) == 0
    assert len(seen) == 4
    assert all(b["generationConfig"]["imageConfig"]["aspectRatio"] == "16:9" for b in seen)
    assert (tmp_path / "wanderer-1.jpg").is_file()
    requests = json.loads((tmp_path / "requests.json").read_text(encoding="utf-8"))
    assert len(requests["prompts"]) == 4
    assert "api" not in json.dumps(requests).lower()


def test_failed_call_retries_once(tmp_path, monkeypatch):
    calls = []

    def fake_call(body, api_key):
        calls.append(1)
        raise RuntimeError("boom")

    monkeypatch.setattr(welcome_art, "call", fake_call)
    done = welcome_art.generate([("a", {})], tmp_path, "k")
    assert done == [] and len(calls) == 2


def test_scholar_command_sends_input_image(tmp_path, monkeypatch):
    src = make_picture(tmp_path / "pick.png")
    seen = []
    monkeypatch.setattr(welcome_art, "key", lambda: "k")
    monkeypatch.setattr(welcome_art, "call", lambda b, k: seen.append(b) or b"\x89PNG\r\n\x1a\nx")
    out = tmp_path / "out"
    assert welcome_art.main(["scholar", "--from", str(src), "--out", str(out), "--n", "2"]) == 0
    assert len(seen) == 2
    for body in seen:
        assert "inline_data" in body["contents"][0]["parts"][0]
        assert "Keep the landscape" in body["contents"][0]["parts"][-1]["text"]
    assert (out / "scholar-2.png").is_file()


def test_default_spots_are_valid():
    import glyphs

    spots = welcome_art.default_spots()
    assert len(spots["glyphs"]) >= 6 and len(spots["route"]) >= 2
    for g in spots["glyphs"]:
        assert g["kind"] in glyphs.GLYPHS
        assert 0 <= g["x"] <= 1 and 0 <= g["y"] <= 1
    assert all(0 <= x <= 1 and 0 <= y <= 1 for x, y in spots["route"])


def test_overlay_is_deterministic_and_changes_picture(tmp_path):
    src = make_picture(tmp_path / "in.png")
    a, b = tmp_path / "a.png", tmp_path / "b.png"
    assert (
        welcome_art.main(["overlay", "--image", str(src), "--spots", "default", "--out", str(a)])
        == 0
    )
    assert (
        welcome_art.main(["overlay", "--image", str(src), "--spots", "default", "--out", str(b)])
        == 0
    )
    assert a.read_bytes() == b.read_bytes()
    assert (tmp_path / "a-spots.json").is_file()
    with Image.open(a) as got, Image.open(src) as orig:
        assert got.size == orig.size
        assert got.convert("RGB").tobytes() != orig.convert("RGB").tobytes()


def test_textures_sizes_and_header(tmp_path):
    w = make_picture(tmp_path / "w.png", (640, 360))
    s = make_picture(tmp_path / "s.png", (640, 360))
    out1, out2 = tmp_path / "o1", tmp_path / "o2"
    for out in (out1, out2):
        assert (
            welcome_art.main(
                ["textures", "--wanderer", str(w), "--scholar", str(s), "--out", str(out)]
            )
            == 0
        )
    names = {
        "wanderer_header.blp": (512, 256),
        "wanderer_card.blp": (256, 384),
        "scholar_header.blp": (512, 256),
        "scholar_card.blp": (256, 384),
    }
    for name, (width, height) in names.items():
        data = (out1 / name).read_bytes()
        assert data[:4] == b"BLP2"
        _type, enc, _alpha, _aenc, mips, bw, bh = struct.unpack("<I4B2I", data[4:20])
        assert (enc, mips, bw, bh) == (2, 1, width, height)
        assert data == (out2 / name).read_bytes()


def test_backgrounds_send_style_reference(tmp_path, monkeypatch):
    style = make_picture(tmp_path / "style.jpg")
    seen = []
    monkeypatch.setattr(welcome_art, "key", lambda: "k")
    monkeypatch.setattr(welcome_art, "call", lambda b, k: seen.append(b) or b"\x89PNG\r\n\x1a\nx")
    out = tmp_path / "bg"
    assert welcome_art.main(["backgrounds", "--style", str(style), "--out", str(out)]) == 0
    assert len(seen) == 4
    texts = [b["contents"][0]["parts"][-1]["text"] for b in seen]
    assert len(set(texts)) == 4
    assert all("NO person" in t for t in texts)
    assert all("inline_data" in b["contents"][0]["parts"][0] for b in seen)
    assert (out / "background-4.png").is_file()


def test_pair_chains_wanderer_into_scholar(tmp_path, monkeypatch):
    bg = make_picture(tmp_path / "bg.png")
    seen = []

    def fake_call(body, api_key):
        seen.append(body)
        return b"\x89PNG\r\n\x1a\n" + bytes([len(seen)])

    monkeypatch.setattr(welcome_art, "key", lambda: "k")
    monkeypatch.setattr(welcome_art, "call", fake_call)
    out = tmp_path / "pairs"
    args = ["pair", "--background", str(bg), "--race", "tauren", "--out", str(out)]
    assert welcome_art.main(args) == 0
    assert len(seen) == 2
    first, second = (b["contents"][0]["parts"] for b in seen)
    assert "tauren (large bull-headed)" in first[-1]["text"]
    assert "nothing that shows a class" in first[-1]["text"]
    assert "scholar's long coat" in second[-1]["text"]
    # the second call's input is the first call's output
    assert base64.b64decode(second[0]["inline_data"]["data"]).endswith(b"\x01")
    assert (out / "tauren-wanderer.png").is_file() and (out / "tauren-scholar.png").is_file()


def test_pair_stops_when_wanderer_fails(tmp_path, monkeypatch):
    bg = make_picture(tmp_path / "bg.png")
    calls = []

    def fake_call(body, api_key):
        calls.append(1)
        raise RuntimeError("boom")

    monkeypatch.setattr(welcome_art, "key", lambda: "k")
    monkeypatch.setattr(welcome_art, "call", fake_call)
    args = ["pair", "--background", str(bg), "--race", "orc", "--out", str(tmp_path / "o")]
    assert welcome_art.main(args) == 1
    assert len(calls) == 2


def test_races_are_the_original_eight():
    assert set(welcome_art.RACES) == {
        "human",
        "dwarf",
        "nightelf",
        "gnome",
        "orc",
        "undead",
        "tauren",
        "troll",
    }


def test_callouts_are_deterministic_and_draw(tmp_path):
    src = make_picture(tmp_path / "in.png", (640, 360))
    spots = {
        "callouts": [
            {"x": 0.7, "y": 0.2, "kind": "peak", "name": "Peak", "lines": ["1,860 yd high"]},
            {"x": 0.3, "y": 0.6, "kind": "herb", "name": "Peacebloom", "lines": ["120 yd away"]},
        ]
    }
    sp = tmp_path / "spots.json"
    sp.write_text(json.dumps(spots), encoding="utf-8")
    a, b = tmp_path / "a.png", tmp_path / "b.png"
    for out in (a, b):
        assert (
            welcome_art.main(
                ["overlay", "--image", str(src), "--spots", str(sp), "--out", str(out)]
            )
            == 0
        )
    assert a.read_bytes() == b.read_bytes()
    with Image.open(a) as got, Image.open(src) as orig:
        assert got.convert("RGB").tobytes() != orig.convert("RGB").tobytes()


def test_race_textures_one_per_race_and_way_and_refuse_a_gap(tmp_path):
    src = tmp_path / "pairs"
    src.mkdir()
    for race in welcome_art.RACES:
        for way in ("wanderer", "scholar"):
            make_picture(src / f"{race}-{way}.png", (640, 360))
    out = tmp_path / "tex"
    assert welcome_art.main(["race-textures", "--dir", str(src), "--out", str(out)]) == 0
    names = sorted(p.name for p in out.glob("*.blp"))
    assert len(names) == 2 * len(welcome_art.RACES) and "undead_scholar.blp" in names
    data = (out / "orc_wanderer.blp").read_bytes()
    assert struct.unpack("<2I", data[12:20]) == (512, 256)
    (src / "troll-scholar.png").unlink()
    with pytest.raises(SystemExit):
        welcome_art.main(["race-textures", "--dir", str(src), "--out", str(tmp_path / "x")])
