#!/usr/bin/env python3
"""
Generate Source/images/bg.png (800x130, 1-bit, horizontally TILEABLE) -- the
in-game parallax horizon. Misty PNW forested ridgelines + a distant treeline,
matching the title screen. All crests use sine periods that divide 800 so the
strip wraps seamlessly as the player turns. Run: python3 draw_bg.py
"""
from PIL import Image, ImageDraw
import numpy as np
import os, math

W, H = 800, 130
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
OUT = "Source/images/bg.png"
_B = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER = np.tile(_B, (H // 4 + 1, W // 4 + 1))[:H, :W]


def dfill(a, mask, d):
    a[mask & (BAYER < d)] = BLACK


def crest(base, *comps):
    x = np.arange(W)
    y = np.full(W, float(base))
    for (period, amp, phase) in comps:
        y -= amp * np.sin(2 * math.pi * x / period + phase)
    return y


# Rainier silhouette (same profile as the title), scalable/placeable
_RAIN = [(88, 150), (112, 132), (140, 110), (164, 93), (176, 86), (183, 89),
         (193, 84), (201, 83), (209, 84), (223, 96), (236, 105), (242, 100),
         (248, 92), (255, 107), (273, 125), (300, 150)]
_RCX = (88 + 300) / 2
_RH = 150 - 83


def place_rainier(cx, base_y, height):
    s = height / _RH
    return [(cx + (x - _RCX) * s, base_y - (150 - y) * s) for (x, y) in _RAIN]


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    a = np.full((H, W, 4), 255, dtype=np.uint8); a[..., 3] = 255
    yy, xx = np.mgrid[0:H, 0:W]

    a[(yy < 22) & (BAYER < 0.05)] = BLACK                     # faint sky tone

    # layered forested ridges (periods divide 800 -> seamless wrap)
    back = crest(50, (800, 11, 0.0), (400, 6, 1.0))
    mid  = crest(68, (400, 10, 0.5), (200, 5, 2.0))
    frnt = crest(85, (800 / 3, 8, 0.0), (200, 5, 1.0))
    dfill(a, yy >= back[None, :], 0.22)
    dfill(a, yy >= mid[None, :],  0.46)
    dfill(a, yy >= frnt[None, :], 0.70)

    for fy in (64, 82, 99):                                   # drifting fog bands
        band = (yy >= fy) & (yy < fy + 3)
        a[band] = WHITE
        a[band & (BAYER < 0.08)] = BLACK

    img = Image.fromarray(a, "RGBA"); d = ImageDraw.Draw(img)

    # --- Mt. Rainier: one-off, centred and clear of the x=0/800 tiling seam ---
    rain = place_rainier(400, 104, 62)
    d.polygon(rain, fill=WHITE, outline=BLACK)
    mk = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mk).polygon(rain, fill=255)
    rmask = np.array(mk) > 0
    a = np.array(img)
    dfill(a, rmask & (yy > 72), 0.5)                          # forested skirt below snowline
    img = Image.fromarray(a, "RGBA"); d = ImageDraw.Draw(img)
    d.line(rain, fill=BLACK, width=1, joint="curve")          # crisp silhouette

    # tileable evergreen treeline at the horizon (period 100, 8 repeats)
    base = 108
    pattern = [(14, 17, 8), (36, 25, 11), (62, 15, 7), (82, 28, 12)]  # (cx, height, halfwidth)
    for rep in range(W // 100):
        ox = rep * 100
        for (cx, ht, hw) in pattern:
            x = ox + cx
            d.polygon([(x - hw, base), (x, base - ht), (x + hw, base)], fill=BLACK)

    a = np.array(img)
    lum = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    bw = np.where(lum >= 128, 255, 0).astype(np.uint8)
    a[..., 0] = bw; a[..., 1] = bw; a[..., 2] = bw; a[..., 3] = 255
    Image.fromarray(a, "RGBA").convert("RGB").save(OUT)
    print("wrote:", OUT, (W, H))


if __name__ == "__main__":
    main()
