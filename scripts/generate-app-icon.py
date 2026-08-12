#!/usr/bin/env python3
"""Generate layered app icon resources for BESS HarmonyOS app.

Produces:
- AppScope/resources/base/media/background.png (1024x1024, brand blue #145A94, full-bleed, no rounded corners, no padding)
- AppScope/resources/base/media/foreground.png (1024x1024, white lightning bolt, transparent background,
  subject centered inside ~66% safe zone)

The lightning path is rasterized from the existing app_icon.svg polygon:
  M145 35 L75 139 h40 l-9 82 75-116 h-45 z
  vertices: (145,35) (75,139) (115,139) (106,221) (181,105) (136,105)  [viewBox 0 0 256 256]
4x supersampling is used for anti-aliasing, then downscaled with LANCZOS.
"""
import math
import os
from PIL import Image, ImageDraw

CANVAS = 1024
SAFE_ZONE = int(CANVAS * 0.66)  # ~676 px: subject bbox must fit inside this
BRAND_BLUE = (0x14, 0x5A, 0x94, 255)
WHITE = (255, 255, 255, 255)

# Lightning polygon in the 256x256 viewBox (closed back to start point)
VERTICES = [(145, 35), (75, 139), (115, 139), (106, 221), (181, 105), (136, 105)]

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA_DIR = os.path.join(PROJECT_ROOT, 'AppScope', 'resources', 'base', 'media')


def lightning_geometry(canvas: int, safe: int) -> list:
    """Scale the lightning polygon so its bbox fits the safe zone, centered on canvas."""
    xs = [p[0] for p in VERTICES]
    ys = [p[1] for p in VERTICES]
    bbox_w = max(xs) - min(xs)  # 106
    bbox_h = max(ys) - min(ys)  # 186
    scale = min(safe / bbox_w, safe / bbox_h)
    cx = (min(xs) + max(xs)) / 2.0
    cy = (min(ys) + max(ys)) / 2.0
    return [(canvas / 2 + (x - cx) * scale, canvas / 2 + (y - cy) * scale) for x, y in VERTICES]


def make_background() -> Image.Image:
    """1024x1024 opaque brand-blue background, full bleed (no corner, no padding)."""
    img = Image.new('RGBA', (CANVAS, CANVAS), BRAND_BLUE)
    return img


def make_foreground() -> Image.Image:
    """1024x1024 transparent background with a white lightning bolt in the safe zone."""
    ss = 4  # supersample factor
    big = Image.new('RGBA', (CANVAS * ss, CANVAS * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    points = [(x * ss, y * ss) for x, y in lightning_geometry(CANVAS, SAFE_ZONE)]
    draw.polygon(points, fill=WHITE)
    img = big.resize((CANVAS, CANVAS), Image.LANCZOS)
    return img


def main() -> None:
    os.makedirs(MEDIA_DIR, exist_ok=True)
    bg_path = os.path.join(MEDIA_DIR, 'background.png')
    fg_path = os.path.join(MEDIA_DIR, 'foreground.png')
    make_background().save(bg_path)
    make_foreground().save(fg_path)

    # Self-check dimensions
    for path in (bg_path, fg_path):
        with Image.open(path) as im:
            w, h = im.size
            assert w == CANVAS and h == CANVAS, f'{path} is {w}x{h}, expected {CANVAS}x{CANVAS}'
            print(f'OK {os.path.basename(path)}: {w}x{h} mode={im.mode}')


if __name__ == '__main__':
    main()
