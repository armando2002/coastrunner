#!/usr/bin/env python3
"""
Draw the player car ("Meowta" = silver NA Miata, rear view) natively in 1-bit
and write a 3-frame Playdate imagetable:

    Source/images/meowta-table-72-48.png   (cells: straight, lean-left, lean-right)

1-bit has no grey, so "silver" is a 50% checker dither that reads as metallic
against the light road. The car has a crisp black outline, white taillights,
and an oversized MEOW plate sized so the letters stay legible at 72px.
The cockpit is left open with two headrests -> room for a cat passenger.

Run: python3 draw_meowta.py   (re-run after tweaking any constants below)
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os

CW, CH = 72, 48
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
OUT = "Source/images/meowta-table-72-48.png"

SHOW_CAT = True   # tuxedo cat in the passenger seat; set False for an empty headrest

# pixel font for the plate (variable width; W is 5-wide with a zigzag so it can't read as V/H)
FONT = {
    "M": ["X..X", "XXXX", "XXXX", "X..X", "X..X"],
    "E": ["XXXX", "X...", "XXXX", "X...", "XXXX"],
    "O": ["XXXX", "X..X", "X..X", "X..X", "XXXX"],
    "W": ["X...X", "X...X", "X.X.X", "XX.XX", "X...X"],
}


def body_mask(sk):
    """White body silhouette on black, as an 'L' image (sk = lean skew, px)."""
    m = Image.new("L", (CW, CH), 0)
    d = ImageDraw.Draw(m)
    # rear quarters + bumper
    d.rounded_rectangle([3, 26, 68, 45], radius=7, fill=255)
    # trunk deck
    d.rounded_rectangle([9, 19, 62, 29], radius=6, fill=255)
    # cockpit surround / rollbar hump (leans)
    d.rounded_rectangle([15 + sk, 11, 57 + sk, 22], radius=7, fill=255)
    return m


def draw_driver(img, d, x):
    """Human driver: black hair, white face, sunglasses. Clearly person-sized."""
    d.ellipse([x - 5, 8, x + 5, 19], fill=BLACK)      # head + hair
    d.ellipse([x - 4, 12, x + 4, 19], fill=WHITE)     # face (lower half)
    d.rectangle([x - 3, 14, x + 3, 15], fill=BLACK)   # sunglasses


def draw_cat(img, d, x):
    """Small black tuxedo cat in the passenger seat -- cat-sized, sits low."""
    # white rim (head + ears) so the black cat reads against the dark cockpit
    d.ellipse([x - 4, 13, x + 4, 20], fill=WHITE)
    d.polygon([(x - 4, 16), (x - 3, 11), (x - 1, 14)], fill=WHITE)
    d.polygon([(x + 4, 16), (x + 3, 11), (x + 1, 14)], fill=WHITE)
    # black head + ears
    d.ellipse([x - 3, 14, x + 3, 19], fill=BLACK)
    d.polygon([(x - 3, 15), (x - 2, 12), (x - 1, 14)], fill=BLACK)
    d.polygon([(x + 3, 15), (x + 2, 12), (x + 1, 14)], fill=BLACK)
    # eyes
    img.putpixel((x - 1, 16), WHITE)
    img.putpixel((x + 1, 16), WHITE)
    # white muzzle + nose
    d.ellipse([x - 2, 17, x + 2, 19], fill=WHITE)
    img.putpixel((x, 18), BLACK)
    # small white chest bib
    d.polygon([(x - 2, 19), (x + 2, 19), (x + 2, 21), (x - 2, 21)], fill=WHITE)


def build_frame(lean):
    sk = lean * 3
    mask = body_mask(sk)
    eroded = mask.filter(ImageFilter.MinFilter(3))   # 1px erosion -> interior

    m = np.array(mask) > 0
    er = np.array(eroded) > 0
    yy, xx = np.mgrid[0:CH, 0:CW]
    checker = ((xx + yy) % 2 == 0)

    interior_white = er & ~checker        # silver: the "lit" half of the checker
    val = np.where(interior_white, 255, 0).astype(np.uint8)   # everything else (outline + dark checker) black
    out = np.zeros((CH, CW, 4), dtype=np.uint8)
    out[..., 0] = val; out[..., 1] = val; out[..., 2] = val
    out[..., 3] = np.where(m, 255, 0).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    d = ImageDraw.Draw(img)

    # --- open cockpit (dark interior) ---
    d.rounded_rectangle([19 + sk, 12, 53 + sk, 21], radius=4, fill=BLACK)

    # --- occupants: human driver (left) always; cat or empty headrest (right) ---
    def headrest(hx):
        x0 = hx + sk
        d.ellipse([x0, 8, x0 + 8, 18], fill=BLACK)
        for yy2 in range(9, 18):
            for xx2 in range(x0 + 1, x0 + 8):
                if (xx2 + yy2) % 2 == 0:
                    img.putpixel((xx2, yy2), WHITE)

    draw_driver(img, d, 28 + sk)       # driver behind the wheel
    if SHOW_CAT:
        draw_cat(img, d, 45 + sk)      # passenger: small tuxedo cat
    else:
        headrest(40)

    # --- taillights: white ovals with black ring ---
    for lx in (9, 49):
        d.ellipse([lx, 30, lx + 14, 38], fill=BLACK)
        d.ellipse([lx + 2, 31, lx + 12, 37], fill=WHITE)
        d.ellipse([lx + 5, 33, lx + 9, 35], fill=BLACK)   # bulb centre

    # --- metallic highlights (top edges) ---
    d.line([(12, 20), (60, 20)], fill=WHITE)
    d.line([(6, 27), (66, 27)], fill=WHITE)

    # --- license plate: white, black border, bold MEOW ---
    px0, py0, px1, py1 = 24, 34, 48, 44
    d.rectangle([px0, py0, px1, py1], fill=BLACK)         # border
    d.rectangle([px0 + 1, py0 + 1, px1 - 1, py1 - 1], fill=WHITE)
    word = "MEOW"
    glyphs = [FONT[c] for c in word]
    tw = sum(len(g[0]) for g in glyphs) + (len(word) - 1)   # glyph widths + 1px gaps
    tx = px0 + 1 + ((px1 - px0 - 1) - tw) // 2
    ty = py0 + 1 + ((py1 - py0 - 1) - 5) // 2
    cx = tx
    for g in glyphs:
        for ry, row in enumerate(g):
            for rx, c in enumerate(row):
                if c == "X":
                    img.putpixel((cx + rx, ty + ry), BLACK)
        cx += len(g[0]) + 1

    # --- exhaust tips ---
    img.putpixel((33, 44), WHITE); img.putpixel((34, 44), WHITE)
    img.putpixel((38, 44), WHITE); img.putpixel((39, 44), WHITE)

    return img


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    frames = [build_frame(0), build_frame(-1), build_frame(1)]  # straight, left, right
    table = Image.new("RGBA", (CW * 3, CH), CLEAR)
    for i, f in enumerate(frames):
        table.paste(f, (i * CW, 0), f)
    table.save(OUT)
    print("wrote:", OUT, table.size)


if __name__ == "__main__":
    main()
