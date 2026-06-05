#!/usr/bin/env python3
"""
Generate the title attract-screen background:  Source/images/title.png  (400x240, 1-bit)

An original 80s/early-90s arcade-racer homage: a synthwave sun with scanline
bands, a mountain silhouette, a retro perspective grid, framing palms, and a
big italic outlined wordmark. The car sprite and the blinking "PRESS A" prompt
are drawn live in main.lua on top of this.

Change TITLE and re-run to rename the game's logo.
Run: python3 draw_title.py
"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import os

TITLE = "MEOWTA RACER"
W, H = 400, 240
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
OUT = "Source/images/title.png"
HORIZON = 150

FONT_PATH = "/mnt/skills/examples/canvas-design/canvas-fonts/BigShoulders-Bold.ttf"
PALM_PATH = "Source/images/palm.png"


def synth_sun(cx, cy, r):
    """White sun disc with classic widening scanline bands below the midline."""
    yy, xx = np.mgrid[0:H, 0:W]
    disc = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    band_rows = set()
    y, gap = cy - 2, 3
    while y < cy + r:
        band_rows.update((y, y + 1))
        y += gap
        gap += 1
    band = np.isin(yy, list(band_rows))
    return disc, band


def render_logo(target_w):
    """Italic, white-fill / black-outline wordmark with a drop shadow -> RGBA (1-bit)."""
    try:
        font = ImageFont.truetype(FONT_PATH, 150)
    except Exception:
        font = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", 130)

    tmp = Image.new("RGBA", (1400, 320), (0, 0, 0, 0))
    d = ImageDraw.Draw(tmp)
    d.text((30, 20), TITLE, font=font, fill=WHITE, stroke_width=10, stroke_fill=BLACK)
    bbox = tmp.getbbox()
    logo = tmp.crop(bbox)

    # italic shear
    sh = 0.28
    nw = logo.width + int(logo.height * sh)
    logo = logo.transform((nw, logo.height), Image.AFFINE, (1, sh, -sh * logo.height, 0, 1, 0),
                           resample=Image.BICUBIC)

    # scale to target width
    scale = target_w / logo.width
    logo = logo.resize((target_w, max(1, int(logo.height * scale))), Image.LANCZOS)

    # threshold to crisp 1-bit + binary alpha
    a = np.array(logo)
    alpha = (a[..., 3] >= 110).astype(np.uint8) * 255
    lum = np.where(a[..., 0] >= 128, 255, 0).astype(np.uint8)
    out = np.zeros_like(a)
    out[..., 0] = lum; out[..., 1] = lum; out[..., 2] = lum; out[..., 3] = alpha
    crisp = Image.fromarray(out, "RGBA")

    # drop shadow: black silhouette offset behind
    sil = np.zeros_like(a)
    sil[..., 3] = alpha
    shadow = Image.fromarray(sil, "RGBA")
    pad = 5
    canvas = Image.new("RGBA", (crisp.width + pad, crisp.height + pad), (0, 0, 0, 0))
    canvas.alpha_composite(shadow, (pad, pad))
    canvas.alpha_composite(crisp, (0, 0))
    return canvas


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    img = Image.new("RGBA", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    # --- sky gradient: faint dither getting denser toward the top ---
    yy, xx = np.mgrid[0:H, 0:W]
    a = np.array(img)
    sky = yy < HORIZON
    dens = np.clip((HORIZON - yy) / HORIZON, 0, 1) * 0.5      # 0 at horizon -> .5 at top
    spot = (((xx * 7 + yy * 13) % 17) / 17.0) < dens
    a[sky & spot] = BLACK
    img = Image.fromarray(a, "RGBA")
    d = ImageDraw.Draw(img)

    # --- synth sun behind the logo ---
    disc, band = synth_sun(W // 2, 104, 50)
    a = np.array(img)
    a[disc] = WHITE
    a[disc & band] = BLACK
    img = Image.fromarray(a, "RGBA")
    d = ImageDraw.Draw(img)
    d.ellipse([W//2 - 50, 104 - 50, W//2 + 50, 104 + 50], outline=BLACK, width=2)

    # --- mountain silhouette along the horizon (low enough to show the sun) ---
    peaks = [(-20, HORIZON), (50, 120), (120, HORIZON), (165, 126),
             (210, HORIZON), (255, 118), (330, HORIZON), (370, 128), (420, HORIZON)]
    d.polygon(peaks + [(W, H), (0, H)], fill=BLACK)
    d.rectangle([0, HORIZON, W, HORIZON + 1], fill=BLACK)

    # --- retro perspective grid on the ground (white on the black ground) ---
    vp = (W // 2, HORIZON)
    for gx in range(-10, 11):
        x_bottom = W // 2 + gx * 46
        d.line([vp, (x_bottom, H)], fill=WHITE, width=1)
    yy2 = HORIZON + 6
    step = 6
    while yy2 < H:
        d.line([(0, yy2), (W, yy2)], fill=WHITE, width=1)
        yy2 += step
        step += 5

    # --- framing palms (silhouettes) ---
    try:
        palm = Image.open(PALM_PATH).convert("RGBA")
        ph = 82
        pw = int(palm.width * ph / palm.height)
        palm = palm.resize((pw, ph), Image.NEAREST)
        img.alpha_composite(palm, (4, HORIZON - ph + 14))
        img.alpha_composite(palm.transpose(Image.FLIP_LEFT_RIGHT), (W - pw - 4, HORIZON - ph + 14))
    except Exception:
        pass

    # --- wordmark ---
    logo = render_logo(300)
    img.alpha_composite(logo, ((W - logo.width) // 2, 12))

    # hard 1-bit clamp on the whole frame
    a = np.array(img)
    lum = (0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2])
    bw = np.where(lum >= 128, 255, 0).astype(np.uint8)
    a[..., 0] = bw; a[..., 1] = bw; a[..., 2] = bw; a[..., 3] = 255
    Image.fromarray(a, "RGBA").convert("RGB").save(OUT)
    print("wrote:", OUT, (W, H))


if __name__ == "__main__":
    main()
