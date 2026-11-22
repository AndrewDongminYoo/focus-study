"""Compose the App Store screenshots of 온:공 from app captures, hand photos and screen masks.

Run with: uv run --with numpy --with pillow python3 screenshot/compose_store_screenshots.py <captures dir> <output dir>

Inputs in this directory: hand-NN.png (a hand holding a phone with a black screen) and screen-NN.png (the visible
screen area of that photo, opaque where the screen shows, with the fingers and the Dynamic Island cut out).
The script finds where each mask sits on its hand photo, fits the four straight screen edges to get the screen
corners, warps a capture onto them, clips it with the mask and lays the result out like the 온:음 store set.
It needs ImageMagick 7 (`magick`) and `oxipng`.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
FONTS = HERE / "fonts"  # Pretendard 1.3.9 static OTF, SIL Open Font License 1.1 (fonts/OFL.txt)
BRAND_FONT = FONTS / "Pretendard-Bold.otf"
HEADLINE_FONT = FONTS / "Pretendard-SemiBold.otf"
SUBTITLE_FONT = FONTS / "Pretendard-Regular.otf"

WIDTH, HEIGHT = 1320, 2868  # App Store 6.9-inch portrait
NAVY, CREAM, AMBER = "#1E2744", "#FFF4E2", "#F4A64A"

# The 온:음 layout scaled to 1320 x 2868: the feature phone starts below the headline and runs past the bottom edge.
FEATURE_SCREEN = (150, 760, 1020, 2216, 120)  # x, y, width, height, corner radius
FEATURE_FRAME = (118, 728, 1084, 2280, 152)
ISLAND = {"width": 0.286, "height": 0.084, "top": 0.026}  # Dynamic Island, as shares of the screen width
HEADLINE = {"size": 72, "y": 300}
HERO = {"title_size": 132, "title_y": 300, "subtitle_size": 60, "subtitle_y": 482, "screen_height": 1800, "screen_top": 800}

TITLE, SUBTITLE = "온:공", "고른 앱만 잠그는 공부 타이머"
SHOTS = [
    {"kind": "hero", "hand": "01", "capture": "store-shield"},
    {"kind": "hero", "hand": "04", "capture": "store-focus"},
    {"kind": "feature", "capture": "store-picker", "headline": "공부할 때 손이 가는\n앱과 웹사이트만 골라요"},
    {"kind": "feature", "capture": "store-length", "headline": "집중 시간은\n25분부터 50분까지"},
    {"kind": "feature", "capture": "store-break-wait", "headline": "3분씩 최대 3번\n쉬어도 흐름은 그대로"},
    {"kind": "feature", "capture": "store-day-clock", "headline": "정해 둔 시간에는\n매일 알아서 막아요"},
]


def magick(*args: object) -> None:
    result = subprocess.run(["magick", *map(str, args)], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "magick failed")


def alpha(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))[:, :, 3] > 127


def locate_mask(hand: Path, mask: np.ndarray) -> tuple[int, int]:
    """Offset of the mask on the hand photo: the place where the mask covers the most dark screen pixels."""
    rgba = np.asarray(Image.open(hand).convert("RGBA")).astype(np.float32)
    dark = (rgba[:, :, :3].mean(axis=2) < 40) & (rgba[:, :, 3] > 127)
    step = 4
    d = np.where(dark[::step, ::step], 1.0, -1.0)
    m = mask[::step, ::step].astype(np.float32)
    shape = (d.shape[0] + m.shape[0], d.shape[1] + m.shape[1])
    score = np.fft.irfft2(np.fft.rfft2(d, shape) * np.conj(np.fft.rfft2(m, shape)), shape)
    valid = score[: d.shape[0] - m.shape[0] + 1, : d.shape[1] - m.shape[1] + 1]
    y, x = np.unravel_index(np.argmax(valid), valid.shape)
    best, best_xy = -1.0, (x * step, y * step)
    # Refine at full resolution around the coarse match.
    for yy in range(max(0, y * step - step), y * step + step + 1):
        for xx in range(max(0, x * step - step), x * step + step + 1):
            window = dark[yy : yy + mask.shape[0], xx : xx + mask.shape[1]]
            if window.shape != mask.shape:
                continue
            value = float(window[mask].mean())
            if value > best:
                best, best_xy = value, (xx, yy)
    return best_xy


def cross(a, b) -> float:
    return float(a[0] * b[1] - a[1] * b[0])


def hull(points: np.ndarray) -> np.ndarray:
    pts = sorted(map(tuple, points))

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and cross(np.subtract(out[-1], out[-2]), np.subtract(p, out[-2])) <= 0:
                out.pop()
            out.append(p)
        return out

    lower, upper = half(pts), half(reversed(pts))
    return np.array(lower[:-1] + upper[:-1], dtype=np.float64)


def island_center(mask: np.ndarray) -> np.ndarray | None:
    """Centre of the hole inside the screen that touches no edge: the Dynamic Island cut-out."""
    small = mask[::4, ::4]
    ys, xs = np.nonzero(small)
    inside = np.zeros_like(small)
    for row in range(small.shape[0]):
        cols = xs[ys == row]
        if cols.size:
            inside[row, cols.min() : cols.max() + 1] = True
    holes = inside & ~small
    seen = np.zeros_like(holes)
    best = None
    for start in zip(*np.nonzero(holes)):
        if seen[start]:
            continue
        queue, comp, touches = deque([start]), [], False
        seen[start] = True
        while queue:
            r, c = queue.popleft()
            comp.append((r, c))
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nr, nc = r + dr, c + dc
                if not (0 <= nr < holes.shape[0] and 0 <= nc < holes.shape[1]) or not inside[nr, nc]:
                    touches = True
                    continue
                if holes[nr, nc] and not seen[nr, nc]:
                    seen[nr, nc] = True
                    queue.append((nr, nc))
        if not touches and 20 < len(comp) and (best is None or len(comp) > len(best)):
            best = comp
    if best is None:
        return None
    arr = np.array(best, dtype=np.float64) * 4
    return np.array([arr[:, 1].mean(), arr[:, 0].mean()])


def screen_corners(mask: np.ndarray) -> list[tuple[float, float]]:
    """The four screen corners, top-left first and clockwise, from lines fitted to the straight edges of the mask's hull."""
    ys, xs = np.nonzero(mask)
    pts = np.stack([xs, ys], axis=1).astype(np.float64)
    centre = pts.mean(axis=0)
    _, _, vt = np.linalg.svd(pts[::50] - centre, full_matrices=False)
    long_axis, short_axis = vt[0], vt[1]
    poly = hull(pts[:: max(1, len(pts) // 200000)])
    dense = np.concatenate([np.linspace(a, b, 200, endpoint=False) for a, b in zip(poly, np.roll(poly, -1, axis=0))])
    u, v = (dense - centre) @ long_axis, (dense - centre) @ short_axis
    lines = {}
    # The short ends lose much of their length to the rounded corners, so they use only their middle 30 %.
    for name, coord, other, sign, keep in (("end_a", u, v, -1, 0.15), ("end_b", u, v, 1, 0.15),
                                           ("side_a", v, u, -1, 0.3), ("side_b", v, u, 1, 0.3)):
        extreme = (coord * sign).max()
        span = other.max() - other.min()
        mid = np.abs(other - (other.max() + other.min()) / 2) < span * keep
        sel = mid & ((coord * sign) > extreme - span * 0.05 - 20)
        p = dense[sel]
        # Fit a line through the selected boundary points: centroid and principal direction.
        c = p.mean(axis=0)
        _, _, d = np.linalg.svd(p - c, full_matrices=False)
        lines[name] = (c, d[0])

    def meet(a, b):
        (p1, d1), (p2, d2) = lines[a], lines[b]
        t = np.linalg.solve(np.stack([d1, -d2], axis=1), p2 - p1)
        return p1 + t[0] * d1

    corners = {(e, s): meet(e, s) for e in ("end_a", "end_b") for s in ("side_a", "side_b")}
    island = island_center(mask)
    mids = {e: (corners[(e, "side_a")] + corners[(e, "side_b")]) / 2 for e in ("end_a", "end_b")}
    if island is not None:
        top = min(mids, key=lambda e: np.linalg.norm(mids[e] - island))
    else:
        top = min(mids, key=lambda e: mids[e][1])
    bottom = "end_b" if top == "end_a" else "end_a"
    a, b = corners[(top, "side_a")], corners[(top, "side_b")]
    # Clockwise in image coordinates: going from top-left to top-right keeps the bottom edge on the right-hand side.
    down = mids[bottom] - mids[top]
    if cross(b - a, down) < 0:
        a, b = b, a
        sides = ("side_b", "side_a")
    else:
        sides = ("side_a", "side_b")
    return [tuple(a), tuple(b), tuple(corners[(bottom, sides[1])]), tuple(corners[(bottom, sides[0])])]


def hand_mockup(number: str, capture: Path, out: Path, tmp: Path) -> dict:
    hand, mask_path = HERE / f"hand-{number}.png", HERE / f"screen-{number}.png"
    mask = alpha(mask_path)
    ox, oy = locate_mask(hand, mask)
    corners = [(x + ox, y + oy) for x, y in screen_corners(mask)]
    w, h = Image.open(capture).size
    hw, hh = Image.open(hand).size
    src = [(0, 0), (w - 1, 0), (w - 1, h - 1), (0, h - 1)]
    points = " ".join(f"{sx},{sy} {dx:.1f},{dy:.1f}" for (sx, sy), (dx, dy) in zip(src, corners))
    warped, full_mask = tmp / f"warped-{number}.png", tmp / f"mask-{number}.png"
    magick(capture, "-alpha", "set", "-virtual-pixel", "transparent", "-define", f"distort:viewport={hw}x{hh}+0+0",
           "-distort", "Perspective", points, "+repage", warped)
    magick("-size", f"{hw}x{hh}", "xc:black", mask_path, "-alpha", "extract", "-geometry", f"+{ox}+{oy}", "-compose", "Over",
           "-composite", full_mask)
    clipped = tmp / f"clipped-{number}.png"
    # Keep the warped capture only where both the capture and the mask are opaque.
    magick(warped, "(", full_mask, "-alpha", "copy", ")", "-compose", "DstIn", "-composite", clipped)
    magick(hand, clipped, "-compose", "Over", "-composite", out)
    ys = [c[1] for c in corners]
    xs = [c[0] for c in corners]
    return {"offset": [ox, oy], "corners": [[round(x, 1), round(y, 1)] for x, y in corners],
            "screen_box": [min(xs), min(ys), max(xs), max(ys)]}


def hero(shot: dict, capture: Path, out: Path, tmp: Path) -> dict:
    mockup = tmp / f"mockup-{shot['hand']}.png"
    info = hand_mockup(shot["hand"], capture, mockup, tmp)
    x0, y0, x1, y1 = info["screen_box"]
    scale = HERO["screen_height"] / (y1 - y0)
    hw, hh = Image.open(mockup).size
    px = round(WIDTH / 2 - (x0 + x1) / 2 * scale)
    py = round(HERO["screen_top"] - y0 * scale)
    background = tmp / f"hero-bg-{shot['hand']}.png"
    cx, cy = WIDTH / 2, HEIGHT * 0.74
    circles = " ".join(f"circle {cx},{cy} {cx + HEIGHT * r},{cy}" for r in (0.43, 0.33, 0.23))
    magick("-size", f"{WIDTH}x{HEIGHT}", "xc:white", "-sparse-color", "Bilinear",
           f"0,0 '#FBF8F2' {WIDTH - 1},0 '#FFF4E2' 0,{HEIGHT - 1} '#F9D9A8' {WIDTH - 1},{HEIGHT - 1} '{AMBER}'",
           "-fill", "rgba(255,255,255,0.10)", "-draw", circles, background)
    magick(background, "(", mockup, "-resize", f"{round(hw * scale)}x{round(hh * scale)}", ")", "-geometry", f"{px:+d}{py:+d}",
           "-composite", "-gravity", "north",
           "-font", BRAND_FONT, "-fill", NAVY, "-pointsize", HERO["title_size"], "-annotate", f"+0+{HERO['title_y']}", TITLE,
           "-font", SUBTITLE_FONT, "-fill", "#5B6172", "-pointsize", HERO["subtitle_size"],
           "-annotate", f"+0+{HERO['subtitle_y']}", SUBTITLE,
           "-alpha", "remove", "-alpha", "off", "-depth", "8", "-strip", out)
    return info


def feature(shot: dict, capture: Path, out: Path, tmp: Path) -> None:
    sx, sy, sw, sh, sr = FEATURE_SCREEN
    fx, fy, fw, fh, fr = FEATURE_FRAME
    screen, background = tmp / f"screen-{out.stem}.png", tmp / f"bg-{out.stem}.png"
    magick(capture, "-resize", f"{sw}x{sh}!", "(", "-size", f"{sw}x{sh}", "xc:none", "-fill", "white", "-draw",
           f"roundrectangle 0,0,{sw - 1},{sh - 1},{sr},{sr}", ")", "-alpha", "set", "-compose", "CopyOpacity", "-composite", screen)
    magick("-size", f"{WIDTH}x{HEIGHT}", f"gradient:{CREAM}-#F9DDB0", "-fill", "#0B0D14", "-draw",
           f"roundrectangle {fx},{fy},{fx + fw - 1},{fy + fh - 1},{fr},{fr}", background)
    iw, ih = round(sw * ISLAND["width"]), round(sw * ISLAND["height"])
    ix, iy = sx + (sw - iw) // 2, sy + round(sw * ISLAND["top"])
    magick(background, screen, "-geometry", f"+{sx}+{sy}", "-composite", "-fill", "#000000", "-draw",
           f"roundrectangle {ix},{iy},{ix + iw - 1},{iy + ih - 1},{ih // 2},{ih // 2}", "-font", HEADLINE_FONT,
           "-fill", NAVY, "-pointsize", HEADLINE["size"], "-interline-spacing", "10", "-gravity", "north",
           "-annotate", f"+0+{HEADLINE['y']}", shot["headline"], "-alpha", "remove", "-alpha", "off", "-depth", "8", "-strip", out)


def main() -> None:
    captures, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    report = {}
    with tempfile.TemporaryDirectory() as name:
        tmp = Path(name)
        for index, shot in enumerate(SHOTS, 1):
            capture = captures / f"{shot['capture']}.png"
            if not capture.is_file():
                print(f"skip {index:02d}: missing {capture}")
                continue
            out = output / f"focus-study-appstore-{index:02d}.png"
            if shot["kind"] == "hero":
                report[out.name] = hero(shot, capture, out, tmp)
            else:
                feature(shot, capture, out, tmp)
                report[out.name] = {}
            print(f"wrote {out}")
    pngs = sorted(str(p) for p in output.glob("focus-study-appstore-*.png"))
    if pngs:
        subprocess.run(["oxipng", "--strip", "safe", "-q", *pngs], check=True)
    (output / "layout.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
