"""Raster helpers for the Bastian map (ADR 0027): blur, grow and shrink of masks, edges, value
noise, hill shading, hatching and colour mixing, on numpy arrays. Images are float RGB in 0..1,
H x W x 3."""

from __future__ import annotations

import numpy as np
from PIL import Image


def rgb(hexcode: str) -> np.ndarray:
    return np.array([int(hexcode[i : i + 2], 16) / 255 for i in (0, 2, 4)], dtype="f4")


def box(a: np.ndarray, r: int) -> np.ndarray:
    """Mean over a (2r+1) square, edges padded with their own values."""
    if r <= 0:
        return a.astype("f4")
    p = np.pad(a.astype("f8"), r, mode="edge")
    c = p.cumsum(0)
    c = np.vstack([np.zeros((1, c.shape[1])), c])
    v = (c[2 * r + 1 :] - c[: -2 * r - 1]) / (2 * r + 1)
    c = v.cumsum(1)
    c = np.hstack([np.zeros((c.shape[0], 1)), c])
    return ((c[:, 2 * r + 1 :] - c[:, : -2 * r - 1]) / (2 * r + 1)).astype("f4")


def blur(a: np.ndarray, r: float) -> np.ndarray:
    """Three box passes: close to a Gaussian of about r."""
    k = max(1, round(r / 1.7))
    out = a.astype("f4")
    for _ in range(3):
        out = box(out, k)
    return out


def grow(m: np.ndarray, r: float) -> np.ndarray:
    return box(m.astype("f4"), max(1, round(r))) > 1e-4 if r > 0 else m.copy()


def shrink(m: np.ndarray, r: float) -> np.ndarray:
    return ~grow(~m, r)


def edge(m: np.ndarray, width: float, outside: bool = True) -> np.ndarray:
    """A band of `width` pixels along the mask's border, outside it (default) or inside."""
    return (grow(m, width) & ~m) if outside else (m & ~shrink(m, width))


def smooth_mask(m: np.ndarray, r: float) -> np.ndarray:
    """A mask with rounded borders (the staircase of the cells gone)."""
    return blur(m.astype("f4"), r) > 0.5


def min_filter(a: np.ndarray, r: int) -> np.ndarray:
    """The smallest value in a (2r+1) square."""
    if r <= 0:
        return a.copy()
    view = np.lib.stride_tricks.sliding_window_view
    out = view(np.pad(a, ((r, r), (0, 0)), mode="edge"), 2 * r + 1, axis=0).min(axis=-1)
    return view(np.pad(out, ((0, 0), (r, r)), mode="edge"), 2 * r + 1, axis=1).min(axis=-1)


def components(mask: np.ndarray) -> np.ndarray:
    """Labels of the 4-connected parts of a mask (the smallest index of each part), -1 outside;
    min-label propagation with pointer jumping."""
    h, w = mask.shape
    big = h * w
    lab = np.where(mask, np.arange(big).reshape(h, w), big)
    while True:
        prev = lab
        nb = lab.copy()
        nb[1:] = np.minimum(nb[1:], lab[:-1])
        nb[:-1] = np.minimum(nb[:-1], lab[1:])
        nb[:, 1:] = np.minimum(nb[:, 1:], lab[:, :-1])
        nb[:, :-1] = np.minimum(nb[:, :-1], lab[:, 1:])
        nb = np.where(mask, nb, big)
        flat = np.append(nb.ravel(), big)
        for _ in range(4):  # pointer jumping: a label points at its own label's label
            flat = np.minimum(flat, flat[flat])
        lab = flat[:-1].reshape(h, w)
        if np.array_equal(lab, prev):
            break
    return np.where(mask, lab, -1)


def slope(z: np.ndarray, ypp: float) -> np.ndarray:
    """Degrees."""
    gy, gx = np.gradient(z, ypp)
    return np.degrees(np.arctan(np.hypot(gx, gy)))


def fill_nan(a: np.ndarray) -> np.ndarray:
    out = a.astype("f4").copy()
    bad = np.isnan(out)
    if bad.all():
        return np.zeros_like(out)
    r = 1
    while bad.any():
        num = box(np.where(bad, 0, out), r)
        den = box((~bad).astype("f4"), r)
        fix = bad & (den > 0)
        out[fix] = num[fix] / den[fix]
        bad = np.isnan(out)
        r *= 2
    return out


def upscale(a: np.ndarray, s: int, nearest: bool = False) -> np.ndarray:
    if s == 1:
        return a
    h, w = a.shape
    img = Image.fromarray(a.astype("f4"), "F")
    return np.asarray(img.resize((w * s, h * s), Image.NEAREST if nearest else Image.BILINEAR))


def _hash(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    """0..1 from integer lattice coordinates and a seed, the same for the same point everywhere."""
    m = np.uint64(0xFFFFFFFF)
    x = (ix.astype(np.int64).astype(np.uint64) * np.uint64(0x9E3779B1)) & m
    x = x ^ ((iy.astype(np.int64).astype(np.uint64) * np.uint64(0x85EBCA77)) & m)
    x = x ^ np.uint64(seed * 0xC2B2AE3D & 0xFFFFFFFF)
    x ^= x >> np.uint64(15)
    x = (x * np.uint64(0x2C1B3C6D)) & m
    x ^= x >> np.uint64(12)
    x = (x * np.uint64(0x297A2D39)) & m
    x ^= x >> np.uint64(15)
    return (x & np.uint64(0xFFFFFF)).astype("f4") / float(0xFFFFFF)


def noise(h: int, w: int, r0: int, c0: int, cell: float, seed: int, octaves: int = 3) -> np.ndarray:
    """Value noise in -1..1, features about `cell` pixels wide, anchored at the world: the image's
    pixel (0, 0) is the world raster's (r0, c0), so neighbouring cells continue each other."""
    out = np.zeros((h, w), "f4")
    rows = (r0 + np.arange(h, dtype="f8"))[:, None]
    cols = (c0 + np.arange(w, dtype="f8"))[None, :]
    amp, total = 1.0, 0.0
    for octave in range(octaves):
        fy, fx = rows / cell, cols / cell
        iy, ix = np.floor(fy), np.floor(fx)
        ty, tx = fy - iy, fx - ix
        ty, tx = ty * ty * (3 - 2 * ty), tx * tx * (3 - 2 * tx)
        k = seed * 31 + octave
        v00, v10 = _hash(ix, iy, k), _hash(ix + 1, iy, k)
        v01, v11 = _hash(ix, iy + 1, k), _hash(ix + 1, iy + 1, k)
        v = (v00 * (1 - tx) + v10 * tx) * (1 - ty) + (v01 * (1 - tx) + v11 * tx) * ty
        out += amp * (v * 2 - 1).astype("f4")
        total += amp
        amp *= 0.5
        cell /= 2
    return out / total


def point_hash(row: float, col: float, seed: int) -> float:
    """0..1 for one world pixel: a thing's own little variation, wherever it is drawn."""
    return float(_hash(np.array([int(col)]), np.array([int(row)]), seed)[0])


def hillshade(z: np.ndarray, ypp: float, exaggerate: float = 2.0) -> np.ndarray:
    """0 (in shadow) .. 1 (facing the light); the light from the north-west, 45 degrees up."""
    gy, gx = np.gradient(z * exaggerate, ypp)  # gy: d/dsouth, gx: d/deast
    north = -gy
    nx, ny, nz = -gx, -north, np.ones_like(z)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = (
        -np.cos(np.pi / 4) * np.sqrt(0.5),
        np.cos(np.pi / 4) * np.sqrt(0.5),
        np.sin(np.pi / 4),
    )
    return np.clip((nx * lx + ny * ly + nz * lz) / norm, 0, 1)


def hatch(
    h: int, w: int, r0: int, c0: int, angle: float, spacing: float, seed: int, wobble: float = 0.6
) -> np.ndarray:
    """Parallel strokes: 1 on a stroke, 0 between; `spacing` pixels apart, wavering a little;
    anchored at the world like `noise`."""
    yy = (r0 + np.arange(h, dtype="f8"))[:, None]
    xx = (c0 + np.arange(w, dtype="f8"))[None, :]
    t = np.radians(angle)
    u = (
        xx * np.cos(t)
        + yy * np.sin(t)
        + noise(h, w, r0, c0, spacing * 8, seed, 2) * spacing * wobble
    )
    phase = (u / spacing) % 1.0
    return np.clip(1 - np.abs(phase - 0.5) * 4, 0, 1)


def mix(img: np.ndarray, colour: np.ndarray, alpha: np.ndarray | float) -> np.ndarray:
    a = np.asarray(alpha, "f4")
    if a.ndim == 2:
        a = a[..., None]
    return img * (1 - a) + colour * a


def to_image(img: np.ndarray, s: int) -> Image.Image:
    """Float RGB -> an 8-bit image, scaled down by the supersampling factor."""
    out = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype("u1"), "RGB")
    if s > 1:
        out = out.resize((out.width // s, out.height // s), Image.LANCZOS)
    return out
