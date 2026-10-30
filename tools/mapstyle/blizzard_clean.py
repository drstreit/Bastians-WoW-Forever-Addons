"""The ML half of the seamless Blizzard map (ADR 0036), run in its own environment (Python 3.12,
CUDA PyTorch, spandrel, easyocr; on the owner's machine D:/bastians-ml/venv with the models in
D:/bastians-ml/models). Build time only: nothing of it ships.

  --sheets <paintings> <out> [ui...]   text boxes (EasyOCR's CRAFT detector) and numbered contact
                                       sheets, for reading the labels (data/mapstyle/blizzard)
  --clean <paintings> <out> [ui...]    the read labels painted out (LaMa) and the painting upscaled
                                       four times (Real-ESRGAN anime 6B) with its grain laid back:
                                       <out>/<ui>_x4.png
  --far <work dir>                     the far image's land gaps filled (LaMa, far_filled.png) and
                                       the result upscaled four times (far_x4.npy, uint8)

Models: --models <dir> with big-lama.pt and RealESRGAN_x4plus_anime_6B.pth.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
READINGS = ROOT / "data" / "mapstyle" / "blizzard"
DEV = "cuda" if torch.cuda.is_available() else "cpu"


def to_tensor(img: Image.Image) -> torch.Tensor:
    a = np.asarray(img, dtype=np.float32) / 255
    if a.ndim == 2:
        return torch.from_numpy(a)[None, None].to(DEV)
    return torch.from_numpy(a).permute(2, 0, 1)[None].to(DEV)


def to_image(t: torch.Tensor) -> Image.Image:
    a = t[0].clamp(0, 1).permute(1, 2, 0).cpu().numpy()
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8))


def load(models: Path, name: str):
    from spandrel import ModelLoader

    return ModelLoader().load_from_file(models / name).to(DEV).eval()


def detect(reader, img: Image.Image) -> list[list[int]]:
    """Text boxes [x0, y0, x1, y1] in painting pixels (boxes only; the reading is a person's or a
    language model's, from the sheets)."""
    horiz, free = reader.detect(
        np.asarray(img.convert("RGB")),
        text_threshold=0.6,
        low_text=0.3,
        link_threshold=0.3,
        canvas_size=2048,
        mag_ratio=2.0,
        slope_ths=0.3,
        width_ths=0.6,
    )
    boxes = [[int(x0), int(y0), int(x1), int(y1)] for x0, x1, y0, y1 in horiz[0]]
    for poly in free[0]:
        xs, ys = [p[0] for p in poly], [p[1] for p in poly]
        boxes.append([int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))])
    return boxes


def mask_of(size, boxes, pad=3) -> Image.Image:
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for x0, y0, x1, y1 in boxes:
        # the detector clips end letters now and then (Satyrnaar's S): half a letter height sideways
        side = max(pad, round(0.6 * (y1 - y0)))
        d.rectangle([x0 - side, y0 - pad, x1 + side, y1 + pad], fill=255)
    return m.filter(ImageFilter.MaxFilter(5))


@torch.inference_mode()
def inpaint(lama, img: Image.Image, mask: Image.Image) -> Image.Image:
    """LaMa over the mask; every pixel outside it stays exactly as it was."""
    w, h = img.size
    pw, ph = (w + 7) // 8 * 8, (h + 7) // 8 * 8
    src = Image.new("RGB", (pw, ph))
    src.paste(img.convert("RGB"))
    m = Image.new("L", (pw, ph), 0)
    m.paste(mask)
    out = to_image(lama(to_tensor(src), (to_tensor(m) > 0.5).float())).crop((0, 0, w, h))
    return Image.composite(out, img.convert("RGB"), mask)


def inpaint_tiled(lama, img: Image.Image, mask: Image.Image, tile=1024, overlap=192) -> Image.Image:
    """LaMa in overlapping tiles, only where the mask has pixels (a whole continent is too big)."""
    out = img.convert("RGB").copy()
    m = np.asarray(mask) > 127
    w, h = img.size
    step = tile - overlap
    for y in range(0, max(1, h - overlap), step):
        for x in range(0, max(1, w - overlap), step):
            x1, y1 = min(w, x + tile), min(h, y + tile)
            if not m[y:y1, x:x1].any():
                continue
            box = (x, y, x1, y1)
            filled = inpaint(lama, out.crop(box), mask.crop(box))
            out.paste(filled, box[:2])
    return out


@torch.inference_mode()
def upscale(esr, img: Image.Image, tile=512, overlap=32) -> Image.Image:
    """x4 in overlapping tiles (VRAM), joined without seams."""
    w, h = img.size
    out = Image.new("RGB", (w * 4, h * 4))
    for y in range(0, h, tile):
        for x in range(0, w, tile):
            x0, y0 = max(0, x - overlap), max(0, y - overlap)
            x1, y1 = min(w, x + tile + overlap), min(h, y + tile + overlap)
            up = to_image(esr(to_tensor(img.crop((x0, y0, x1, y1)).convert("RGB"))))
            cx, cy = (x - x0) * 4, (y - y0) * 4
            cw, ch = min(tile, w - x) * 4, min(tile, h - y) * 4
            out.paste(up.crop((cx, cy, cx + cw, cy + ch)), (x * 4, y * 4))
    return out


def grained(up: Image.Image, src: Image.Image, amount=0.8) -> Image.Image:
    """The model irons the parchment flat: its grain comes back from the source itself (the
    high-pass of a bicubic enlargement); the strokes stay the model's."""
    bic = src.convert("RGB").resize(up.size, Image.Resampling.BICUBIC)
    hi = np.asarray(bic, np.float32) - np.asarray(
        bic.filter(ImageFilter.GaussianBlur(3)), np.float32
    )
    out = np.asarray(up, np.float32) + amount * hi
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def sheets(paintings: Path, out: Path, only: set[int]) -> None:
    import easyocr

    reader = easyocr.Reader(["en"], gpu=DEV == "cuda", recognizer=False)
    font = ImageFont.load_default(size=22)
    for path in sorted(paintings.glob("*.png")):
        ui = int(path.stem)
        if only and ui not in only:
            continue
        img = Image.open(path).convert("RGB")
        boxes = detect(reader, img)
        (out / f"{ui}_boxes.json").write_text(json.dumps(boxes), encoding="utf-8")
        d = ImageDraw.Draw(img)
        for i, (x0, y0, x1, y1) in enumerate(boxes):
            d.rectangle([x0, y0, x1, y1], outline=(255, 0, 255), width=2)
            d.text(
                (x1 + 3, y0 - 4),
                str(i),
                fill=(255, 255, 255),
                font=font,
                stroke_width=3,
                stroke_fill=(120, 0, 120),
            )
        img.save(out / f"{ui}_sheet.png")
        print(ui, len(boxes), "boxes", flush=True)


def clean(paintings: Path, out: Path, only: set[int], models: Path) -> None:
    lama = load(models, "big-lama.pt")
    esr = load(models, "RealESRGAN_x4plus_anime_6B.pth")
    for read in sorted(READINGS.glob("*.json")):
        ui = int(read.stem)
        if only and ui not in only:
            continue
        img = Image.open(paintings / f"{ui}.png").convert("RGB")
        boxes = [
            b
            for lab in json.loads(read.read_text(encoding="utf-8"))["labels"]
            for b in lab["boxes"]
        ]
        cleaned = inpaint(lama, img, mask_of(img.size, boxes))
        cleaned.save(out / f"{ui}_clean.png")
        grained(upscale(esr, cleaned), cleaned).save(out / f"{ui}_x4.png")
        print(ui, len(boxes), "boxes painted out", flush=True)


def far(work: Path, models: Path) -> None:
    img = Image.open(work / "far_image.png").convert("RGB")
    gaps = Image.open(work / "far_gaps.png").convert("L").filter(ImageFilter.MaxFilter(5))
    lama = load(models, "big-lama.pt")
    filled = inpaint_tiled(lama, img, gaps)
    filled.save(work / "far_filled.png")
    print("far image filled", filled.size, flush=True)
    del lama
    esr = load(models, "RealESRGAN_x4plus_anime_6B.pth")
    big = grained(upscale(esr, filled), filled)
    np.save(work / "far_x4.npy", np.asarray(big, dtype=np.uint8))
    print("far image upscaled", big.size, flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sheets", nargs=2, type=Path, metavar=("PAINTINGS", "OUT"))
    ap.add_argument("--clean", nargs=2, type=Path, metavar=("PAINTINGS", "OUT"))
    ap.add_argument("--far", type=Path, metavar="WORK")
    ap.add_argument("--models", type=Path, default=Path("D:/bastians-ml/models"))
    ap.add_argument("ui", nargs="*", type=int)
    args = ap.parse_args()
    only = set(args.ui)
    if args.sheets:
        args.sheets[1].mkdir(parents=True, exist_ok=True)
        sheets(*args.sheets, only)
    elif args.clean:
        args.clean[1].mkdir(parents=True, exist_ok=True)
        clean(*args.clean, only, args.models)
    elif args.far:
        far(args.far, args.models)
    else:
        ap.error("one of --sheets, --clean, --far")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
