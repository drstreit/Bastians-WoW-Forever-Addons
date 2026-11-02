"""The welcome window's two pictures (plan-launch-version.md section 2.5): the Wanderer's valley
(candidates from the image model), the Scholar's edit of the picked one, our real glyph tiles laid
over it in Pillow, and the game textures. Each model call is paid: run it only on the owner's
command. Reads the key at call time, prints and writes no secret.

Usage:
  python tools/welcome_art.py wanderer --out DIR [--n 4]
  python tools/welcome_art.py scholar --from PICKED --out DIR [--n 4]
  python tools/welcome_art.py backgrounds --style REF --out DIR [--n 4]
  python tools/welcome_art.py pair --background FILE --race RACE --out DIR
  python tools/welcome_art.py overlay --image PICK --spots FILE|default --out FILE
  python tools/welcome_art.py textures --wanderer FILE --scholar FILE [--out DIR]
"""

from __future__ import annotations

import argparse
import base64
import io
import itertools
import json
import math
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

SECRETS = Path.home() / ".google" / ".google-secrets"
NAME = "GOOGLE_AI_STUDIO_NANO_API_KEY_DRSTREIT"
MODEL = "gemini-nano-banana-2.1"
ASPECT, SIZE = "16:9", "1K"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "addons" / "Bastians_Core" / "Media" / "Welcome"

PROMPT_BASE = (
    "A breathtaking valley in World of Warcraft's hand-painted art style, like a loading screen: "
    "green slopes, a winding river, old trees, distant snowy peaks, warm late-afternoon light, a "
    "faint footpath; nothing built, no text, no interface. Over the shoulder of a {cls} standing "
    "on a rock ledge in the foreground, seen from behind, looking down the valley."
)
WANDERER_CLASSES = [
    "night elf hunter with a bow",
    "tauren druid",
    "dwarf hunter with a rifle",
    "human warrior with a shield on the back",
]
SCHOLAR_CLASSES = [
    "human mage holding an open book",
    "human mage holding an open book",
    "gnome scholar holding an open book",
    "gnome scholar holding an open book",
]
EDIT_TEXT = (
    "Keep the landscape, the light, the colours and the camera of this picture exactly as they "
    "are, in the same hand-painted style. Replace only the character on the rock ledge with a "
    "{cls}, seen from behind over the shoulder, in the same place and size. Do not draw any "
    "symbols, icons, labels or text anywhere."
)

BG_TEXT = (
    "The same hand-painted World of Warcraft loading-screen style, saturation and warm light "
    "as this picture, but a new breathtaking valley ({valley}): a river, old trees, "
    "distant snowy peaks, a faint footpath; nothing built, no text, no interface, "
    "NO person and no creature. A mossy rock ledge in the lower right "
    "foreground where a figure could stand."
)
VALLEYS = [
    "morning mist lying in the valley, soft low sun",
    "golden afternoon light, long warm shadows",
    "an autumn forest in red and gold",
    "a lake valley with a still mirror-like lake",
]
WANDERER_TEXT = (
    "Keep the landscape, the light and the camera of this picture exactly as they are. Add one "
    "{race} traveller standing on the rock ledge, seen from behind, over the shoulder, looking "
    "down the valley: a hooded travelling cloak, a walking staff, a small pack; no armour, "
    "no weapons, nothing that shows a class. No text, no symbols, no interface."
)
SCHOLAR_TEXT = (
    "Keep everything exactly as it is (landscape, light, camera, the figure's place, pose and "
    "race). Change only what the figure carries and wears: a scholar's long coat, an open journal "
    "in one hand, a rolled map and a brass spyglass at the belt; no class markers; no text, no "
    "symbols, no interface."
)
RACES = {
    "human": "human",
    "dwarf": "dwarf (short, stocky, bearded)",
    "nightelf": "night elf (tall, violet-skinned, long pointed ears)",
    "gnome": "gnome (very small)",
    "orc": "orc (green-skinned, broad and muscular)",
    "undead": "Forsaken (undead)",
    "tauren": "tauren (large bull-headed)",
    "troll": "troll (tall, blue-skinned, tusked, with a mohawk)",
}

# overlay -------------------------------------------------------------------------------------
GLYPH_FRACTION = 0.025  # a tile's width as a fraction of the picture's width
DEFAULT_SPOTS = {
    "glyphs": [
        {"kind": "quest", "x": 0.62, "y": 0.50, "label": "Quest"},
        {"kind": "questActive", "x": 0.42, "y": 0.58, "label": "In your log"},
        {"kind": "spot", "x": 0.76, "y": 0.38, "label": "Map pin"},
        {"kind": "herb", "x": 0.30, "y": 0.66, "label": "Herb"},
        {"kind": "mine", "x": 0.84, "y": 0.58, "label": "Ore"},
        {"kind": "gold", "x": 0.55, "y": 0.72, "label": "Price"},
        {"kind": "rare", "x": 0.70, "y": 0.28, "label": "Rare"},
        {"kind": "flight", "x": 0.20, "y": 0.34, "label": "Flight point"},
    ],
    "route": [[0.50, 0.92], [0.47, 0.80], [0.50, 0.68], [0.56, 0.58], [0.60, 0.51], [0.64, 0.44]],
}

# textures ------------------------------------------------------------------------------------
HEADER_SIZE = (512, 256)
CARD_SIZE = (256, 384)
TEXTURES = {"header": HEADER_SIZE, "card": CARD_SIZE}


# ---- the model call ---------------------------------------------------------------------------


def key() -> str:
    for line in SECRETS.read_text(encoding="utf-8").splitlines():
        k, sep, v = line.partition("=")
        if sep and k.strip() == NAME:
            return v.strip().strip('"').strip("'")
    raise SystemExit(f"{NAME} not in {SECRETS}")


def sniff(data: bytes) -> str:
    """The file extension of image bytes, by their magic."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if data[:3] == b"\xff\xd8\xff":
        return ".jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    return ".png"


def request_body(text: str, image: bytes | None = None, mime: str = "image/png") -> dict:
    """The generateContent body: the optional input image first, then the text."""
    parts: list[dict] = []
    if image is not None:
        parts.append({"inline_data": {"mime_type": mime, "data": base64.b64encode(image).decode()}})
    parts.append({"text": text})
    return {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": ASPECT, "imageSize": SIZE},
        },
    }


def call(body: dict, api_key: str) -> bytes:
    """One paid request -> the image bytes. Raises RuntimeError with a short, secret-free reason."""
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode(),
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            answer = json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} {e.read().decode()[:200]}") from None
    except (urllib.error.URLError, TimeoutError) as e:
        raise RuntimeError(f"request failed: {type(e).__name__}") from None
    for cand in answer.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            data = part.get("inline_data") or part.get("inlineData")
            if data:
                return base64.b64decode(data["data"])
    raise RuntimeError(f"no image ({json.dumps(answer)[:200]})")


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def generate(bodies: list[tuple[str, dict]], out: Path, api_key: str) -> list[Path]:
    """Makes one picture per (stem, body), one retry per failed call. -> the files written."""
    written: list[Path] = []
    for stem, body in bodies:
        data = None
        for attempt in (1, 2):
            try:
                data = call(body, api_key)
                break
            except RuntimeError as e:
                print(f"{stem}: attempt {attempt} failed: {e}", flush=True)
        if data is None:
            continue
        path = out / f"{stem}{sniff(data)}"
        write_atomic(path, data)
        written.append(path)
        print(f"{stem}: ok -> {path}", flush=True)
    return written


def save_requests(out: Path, prompts: dict[str, str]) -> None:
    text = json.dumps(
        {"model": MODEL, "aspect": ASPECT, "size": SIZE, "prompts": prompts}, indent=2
    )
    write_atomic(out / "requests.json", (text + "\n").encode())


def wanderer_prompts(n: int) -> dict[str, str]:
    return {
        f"wanderer-{i + 1}": PROMPT_BASE.format(cls=WANDERER_CLASSES[i % len(WANDERER_CLASSES)])
        for i in range(n)
    }


def scholar_prompts(n: int) -> dict[str, str]:
    return {
        f"scholar-{i + 1}": EDIT_TEXT.format(cls=SCHOLAR_CLASSES[i % len(SCHOLAR_CLASSES)])
        for i in range(n)
    }


def image_part(path: Path) -> tuple[bytes, str]:
    data = path.read_bytes()
    return data, {".jpg": "image/jpeg", ".webp": "image/webp"}.get(sniff(data), "image/png")


def background_prompts(n: int) -> dict[str, str]:
    return {
        f"background-{i + 1}": BG_TEXT.format(valley=VALLEYS[i % len(VALLEYS)]) for i in range(n)
    }


def cmd_backgrounds(style: Path, out: Path, n: int) -> int:
    image, mime = image_part(style)
    prompts = background_prompts(n)
    save_requests(out, prompts)
    bodies = [(stem, request_body(text, image, mime)) for stem, text in prompts.items()]
    return 0 if len(generate(bodies, out, key())) == n else 1


def cmd_pair(background: Path, race: str, out: Path) -> int:
    if race not in RACES:
        raise SystemExit(f"race must be one of {', '.join(RACES)}")
    api_key = key()
    image, mime = image_part(background)
    wtext = WANDERER_TEXT.format(race=RACES[race])
    save_requests(out, {f"{race}-wanderer": wtext, f"{race}-scholar": SCHOLAR_TEXT})
    got = generate([(f"{race}-wanderer", request_body(wtext, image, mime))], out, api_key)
    if not got:
        return 1
    wimg, wmime = image_part(got[0])
    done = generate([(f"{race}-scholar", request_body(SCHOLAR_TEXT, wimg, wmime))], out, api_key)
    return 0 if done else 1


def cmd_wanderer(out: Path, n: int) -> int:
    prompts = wanderer_prompts(n)
    save_requests(out, prompts)
    bodies = [(stem, request_body(text)) for stem, text in prompts.items()]
    done = generate(bodies, out, key())
    return 0 if len(done) == n else 1


def cmd_scholar(src: Path, out: Path, n: int) -> int:
    image = src.read_bytes()
    mime = {".jpg": "image/jpeg", ".webp": "image/webp"}.get(sniff(image), "image/png")
    prompts = scholar_prompts(n)
    save_requests(out, prompts)
    bodies = [(stem, request_body(text, image, mime)) for stem, text in prompts.items()]
    done = generate(bodies, out, key())
    return 0 if len(done) == n else 1


# ---- the overlay ------------------------------------------------------------------------------


def default_spots() -> dict:
    return json.loads(json.dumps(DEFAULT_SPOTS))


def load_spots(arg: str, out: Path) -> dict:
    if arg == "default":
        spots = default_spots()
        write_atomic(
            out.with_name(out.stem + "-spots.json"), (json.dumps(spots, indent=2) + "\n").encode()
        )
        return spots
    return json.loads(Path(arg).read_text(encoding="utf-8"))


def glyph_tile(kind: str, size: int):
    import glyphs
    from PIL import Image

    if kind not in glyphs.GLYPHS:
        raise SystemExit(f"no glyph kind '{kind}' in tools/glyphs.py")
    with Image.open(io.BytesIO(glyphs.tile(kind))) as im:
        tile = im.convert("RGBA")
    return tile.resize((size, size), Image.Resampling.LANCZOS), glyphs.TILE_COLOR.get(
        kind, (0.55, 0.58, 0.60)
    )


def overlay(image, spots: dict):
    """The picture (RGB) with the glyph tiles, glow, leader lines, labels and the dotted route."""
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    base = image.convert("RGBA")
    w, h = base.size
    size = max(16, round(w * GLYPH_FRACTION))
    font = ImageFont.load_default(max(9, round(w * 0.009)))

    route = [(x * w, y * h) for x, y in spots.get("route", [])]
    if len(route) >= 2:
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        step, r = size * 0.34, max(2, size * 0.09)
        carry = 0.0
        for (x0, y0), (x1, y1) in itertools.pairwise(route):
            length = math.hypot(x1 - x0, y1 - y0)
            t = carry
            while t <= length:
                px, py = x0 + (x1 - x0) * t / length, y0 + (y1 - y0) * t / length
                d.ellipse(
                    (px - r * 2, py - r * 2, px + r * 2, py + r * 2), fill=(102, 189, 242, 90)
                )
                d.ellipse((px - r, py - r, px + r, py + r), fill=(235, 248, 255, 255))
                t += step
            carry = t - length
        glow = layer.filter(ImageFilter.GaussianBlur(size * 0.12))
        base = Image.alpha_composite(Image.alpha_composite(base, glow), layer)

    for g in spots.get("glyphs", []):
        tile, (cr, cg, cb) = glyph_tile(g["kind"], size)
        cx, cy = g["x"] * w, g["y"] * h
        colour = (round(cr * 255), round(cg * 255), round(cb * 255))
        glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
        r = size * 0.85
        ImageDraw.Draw(glow).ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*colour, 150))
        glow = glow.filter(ImageFilter.GaussianBlur(size * 0.35))
        base = Image.alpha_composite(base, glow)
        label = g.get("label")
        draw = ImageDraw.Draw(base)
        if label:
            # the label sits to the right of the tile (to the left near the right edge), on a leader
            right = cx < w * 0.78
            lx = cx + size * 1.1 if right else cx - size * 1.1
            ly = cy - size * 0.9
            draw.line((cx, cy, lx, ly), fill=(255, 255, 255, 200), width=max(1, round(size / 40)))
            box = draw.textbbox((0, 0), label, font=font)
            tw, th = box[2] - box[0], box[3] - box[1]
            tx = lx if right else lx - tw
            pad = max(3, round(size * 0.08))
            bg = Image.new("RGBA", base.size, (0, 0, 0, 0))
            ImageDraw.Draw(bg).rounded_rectangle(
                (tx - pad, ly - th - pad * 2, tx + tw + pad, ly + pad),
                radius=pad,
                fill=(12, 16, 24, 170),
            )
            base = Image.alpha_composite(base, bg)
            draw = ImageDraw.Draw(base)
            draw.text((tx, ly - th - pad - box[1]), label, font=font, fill=(255, 255, 255, 255))
        base.alpha_composite(tile, (round(cx - size / 2), round(cy - size / 2)))
    for c in spots.get("callouts", []):
        base = draw_callout(base, c, size)
    return base.convert("RGB")


CALLOUT_FONT = ROOT / "addons" / "Bastians_Core" / "Fonts" / "Inter.ttf"


def callout_font(px: int):
    from PIL import ImageFont

    try:
        return ImageFont.truetype(str(CALLOUT_FONT), px)
    except OSError:
        return ImageFont.load_default(px)


def draw_callout(base, c: dict, size: int):
    """A marker (thin ring for a peak, the herb tile for a herb), a thin leader, a compact plate."""
    from PIL import Image, ImageDraw

    w, h = base.size
    cx, cy = c["x"] * w, c["y"] * h
    fpx = max(9, round(w * 0.0085))
    small, big = callout_font(fpx), callout_font(round(fpx * 1.1))
    herb = c.get("kind") == "herb"
    rows = [(c["name"], big)] if c.get("name") else []
    rows += [(t, small) for t in c.get("lines", [])]
    mark = size * 0.35
    # the plate goes up and to the side of the marker; to the left near the right edge
    right = c["side"] == "right" if c.get("side") else cx < w * 0.74
    pad = max(4, round(fpx * 0.5))
    draw = ImageDraw.Draw(base)
    boxes = [draw.textbbox((0, 0), t, font=f) for t, f in rows]
    gap = round(fpx * 0.25)
    tw = max((b[2] - b[0] for b in boxes), default=0)
    th = sum(b[3] - b[1] for b in boxes) + gap * max(0, len(boxes) - 1)
    lx = cx + fpx * 2.0 if right else cx - fpx * 2.0
    ly = cy - fpx * 1.8
    x0 = lx if right else lx - tw - pad * 2
    y0 = ly - th - pad * 2
    margin = round(fpx * 0.6)
    bw, bh = tw + pad * 2, th + pad * 2
    x0 = min(max(x0, margin), w - margin - bw)
    y0 = min(max(y0, margin), h - margin - bh)
    x1, y1 = x0 + bw, y0 + bh
    ex = min(max(cx, x0), x1)
    ey = y1 if cy >= y1 else y0
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lw = 1
    d.line((cx, cy, ex, ey), fill=(255, 255, 255, 190), width=lw)
    if not herb:
        r = mark
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 255, 255, 235), width=lw)
    d.rounded_rectangle((x0, y0, x1, y1), radius=pad, fill=(12, 16, 24, 165))
    base = Image.alpha_composite(base, layer)
    if herb:
        tile, _ = glyph_tile("herb", size)
        base.alpha_composite(tile, (round(cx - tile.width / 2), round(cy - tile.height / 2)))
    d = ImageDraw.Draw(base)
    ty = y0 + pad
    for (t, f), b in zip(rows, boxes, strict=True):
        d.text((x0 + pad - b[0], ty - b[1]), t, font=f, fill=(244, 240, 228, 255))
        ty += b[3] - b[1] + gap
    return base


def cmd_overlay(image: Path, spots_arg: str, out: Path) -> int:
    from PIL import Image

    spots = load_spots(spots_arg, out)
    with Image.open(image) as im:
        result = overlay(im, spots)
    buf = io.BytesIO()
    result.save(buf, "PNG")
    write_atomic(out, buf.getvalue())
    print(f"overlay -> {out}")
    return 0


# ---- the textures -----------------------------------------------------------------------------


def crop_middle(im, ratio: float):
    """The largest crop of `ratio` (width / height) from the middle."""
    w, h = im.size
    cw, ch = (round(h * ratio), h) if w / h >= ratio else (w, round(w / ratio))
    left, top = (w - cw) // 2, (h - ch) // 2
    return im.crop((left, top, left + cw, top + ch))


def texture(path: Path, kind: str) -> bytes:
    from book_art import blp_dxt1
    from PIL import Image

    size = TEXTURES[kind]
    with Image.open(path) as im:
        cut = crop_middle(im.convert("RGB"), size[0] / size[1])
    return blp_dxt1(cut.resize(size, Image.Resampling.LANCZOS))


def cmd_textures(wanderer: Path, scholar: Path, out: Path) -> int:
    for way, src in (("wanderer", wanderer), ("scholar", scholar)):
        for kind in TEXTURES:
            target = out / f"{way}_{kind}.blp"
            write_atomic(target, texture(src, kind))
            print(f"{target.name} <- {src.name}")
    return 0


# ---- the command line -------------------------------------------------------------------------


def cmd_race_textures(src: Path, out: Path) -> int:
    """The welcome v2's pictures by race: `<race>-<way>.<ext>` from `pair` in
    `src`, each as one 512 x 256 texture `<race>_<way>.blp` (the scene cut to 2:1 from its middle;
    Welcome.lua shows it whole on the cards and as a band in the headers). Missing pictures fail."""
    for race in RACES:
        for way in ("wanderer", "scholar"):
            found = sorted(p for p in src.glob(f"{race}-{way}.*") if p.suffix in (".jpg", ".png"))
            if not found:
                raise SystemExit(f"missing: {src / (race + '-' + way)}.jpg")
            target = out / f"{race}_{way}.blp"
            write_atomic(target, texture(found[0], "header"))
            print(f"{target.name} <- {found[0].name}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("wanderer", help="n candidates of the Wanderer's valley (paid calls)")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--n", type=int, default=4)
    p = sub.add_parser("scholar", help="n edits of the picked Wanderer (paid calls)")
    p.add_argument("--from", dest="src", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--n", type=int, default=4)
    p = sub.add_parser("backgrounds", help="n new valleys in the reference's style (paid calls)")
    p.add_argument("--style", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--n", type=int, default=4)
    p = sub.add_parser("pair", help="a race's Wanderer and Scholar on a background (2 paid calls)")
    p.add_argument("--background", type=Path, required=True)
    p.add_argument("--race", required=True, choices=list(RACES))
    p.add_argument("--out", type=Path, required=True)
    p = sub.add_parser("overlay", help="lay the suite's glyph tiles on the Scholar's pick")
    p.add_argument("--image", type=Path, required=True)
    p.add_argument("--spots", default="default", help="a JSON file, or 'default'")
    p.add_argument("--out", type=Path, required=True)
    p = sub.add_parser("textures", help="write the four game textures")
    p.add_argument("--wanderer", type=Path, required=True)
    p.add_argument("--scholar", type=Path, required=True)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p = sub.add_parser("race-textures", help="every race's two pictures as game textures")
    p.add_argument("--dir", type=Path, required=True, help="the folder of `pair`'s pictures")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args(argv)
    if args.cmd == "wanderer":
        return cmd_wanderer(args.out, args.n)
    if args.cmd == "scholar":
        return cmd_scholar(args.src, args.out, args.n)
    if args.cmd == "backgrounds":
        return cmd_backgrounds(args.style, args.out, args.n)
    if args.cmd == "pair":
        return cmd_pair(args.background, args.race, args.out)
    if args.cmd == "overlay":
        return cmd_overlay(args.image, args.spots, args.out)
    if args.cmd == "race-textures":
        return cmd_race_textures(args.dir, args.out)
    return cmd_textures(args.wanderer, args.scholar, args.out)


if __name__ == "__main__":
    raise SystemExit(main())
