#!/usr/bin/env python3
"""
Convert Source/images/meowta.png (a 3-frame, black-on-white line-art sprite
sheet of the player car) into a Playdate-ready 1-bit imagetable:

    Source/images/meowta-table-<CW>-<CH>.png

Pipeline per frame:
  1. threshold to pure black/white
  2. flood-fill the exterior white from the borders -> mark as background
  3. background becomes transparent; the car is rebuilt as a SOLID dark body
     with white detail lines (inverted), so it reads against the light road
     the way the rest of the 1-bit art does
  4. crop to the car, scale to fit the cell, bottom-centre align

Re-run this whenever you drop in a new meowta.png. Frame order left->right is
kept as-is: frame1 = straight, frame2 = lean-left, frame3 = lean-right.
"""
from PIL import Image, ImageDraw
import numpy as np
import os, sys

CW, CH = 72, 48          # cell size (matches the in-game draw scale)
PAD    = 1               # transparent margin inside the cell
SENT   = 128             # sentinel value used while flood-filling the exterior

SRC = "Source/images/meowta.png"
OUT = f"Source/images/meowta-table-{CW}-{CH}.png"


def process_frame(img_l):
    """img_l: 'L' image of one frame -> RGBA (dark body, white lines, clear bg)."""
    bw = img_l.point(lambda p: 255 if p >= 128 else 0)
    px = bw.load()
    w, h = bw.size

    # flood the exterior white inward from every still-white border pixel
    for x in range(w):
        if px[x, 0] == 255:     ImageDraw.floodfill(bw, (x, 0), SENT)
        if px[x, h-1] == 255:   ImageDraw.floodfill(bw, (x, h-1), SENT)
    for y in range(h):
        if px[0, y] == 255:     ImageDraw.floodfill(bw, (0, y), SENT)
        if px[w-1, y] == 255:   ImageDraw.floodfill(bw, (w-1, y), SENT)

    a   = np.array(bw)
    ext = (a == SENT)            # exterior background
    car = ~ext                   # car body + enclosed interior

    # invert the car: original ink (0) -> white line; interior white (255) -> black body
    val = np.where(a == 0, 255, 0).astype(np.uint8)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., 0] = val
    out[..., 1] = val
    out[..., 2] = val
    out[..., 3] = np.where(car, 255, 0).astype(np.uint8)

    rgba = Image.fromarray(out, "RGBA")
    bbox = Image.fromarray((car * 255).astype(np.uint8)).getbbox()
    return rgba.crop(bbox)


def fit_cell(rgba):
    """Scale to fit (CW-2*PAD) x (CH-2*PAD), bottom-centre in a CW x CH cell, 1-bit."""
    maxw, maxh = CW - 2 * PAD, CH - 2 * PAD
    w, h = rgba.size
    s = min(maxw / w, maxh / h)
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    car = rgba.resize((nw, nh), Image.LANCZOS)

    # re-threshold back to clean 1-bit + binary alpha after the resample
    arr = np.array(car)
    lum = arr[..., 0]
    alpha = arr[..., 3]
    a = (alpha >= 110).astype(np.uint8) * 255
    v = np.where(lum >= 128, 255, 0).astype(np.uint8)
    out = np.zeros((nh, nw, 4), dtype=np.uint8)
    out[..., 0] = v; out[..., 1] = v; out[..., 2] = v; out[..., 3] = a
    car = Image.fromarray(out, "RGBA")

    cell = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    ox = (CW - nw) // 2
    oy = CH - PAD - nh           # bottom aligned
    cell.paste(car, (ox, oy), car)
    return cell


def main():
    root = os.path.dirname(os.path.abspath(__file__))
    os.chdir(root)
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")

    sheet = Image.open(SRC).convert("L")
    W, H = sheet.size
    fw = W // 3
    frames = [process_frame(sheet.crop((i * fw, 0, (i + 1) * fw, H))) for i in range(3)]
    cells = [fit_cell(f) for f in frames]

    table = Image.new("RGBA", (CW * 3, CH), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        table.paste(c, (i * CW, 0), c)
    table.save(OUT)
    print("wrote:", OUT, table.size)


if __name__ == "__main__":
    main()
