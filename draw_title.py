#!/usr/bin/env python3
"""
Generate the title attract-screen background:  Source/images/title.png (400x240, 1-bit)

Pacific-Northwest rainforest mood: layered evergreen ridgelines receding into
fog, soft overcast light, drifting mist bands, the game's own fir trees framing
the foreground, and a faint road winding into the trees. The car sprite and the
blinking "PRESS A" prompt are drawn live in main.lua on top of this.

Change TITLE and re-run to rename the game's logo.
"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import os, random

TITLE = "MEOWTA RACER"
W, H = 400, 240
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
OUT = "Source/images/title.png"
HORIZON = 152

FONT_PATH = "/mnt/skills/examples/canvas-design/canvas-fonts/BigShoulders-Bold.ttf"
TREE_PATH = "Source/images/palm.png"   # the user's hand-made fir

_B = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER = np.tile(_B, (H // 4 + 1, W // 4 + 1))[:H, :W]


def dither_fill(a, mask, density):
    a[mask & (BAYER < density)] = BLACK


def forest_ridge(crest_y, jag, seed):
    rng = random.Random(seed)
    yy, xx = np.mgrid[0:H, 0:W]
    pts = np.zeros(W)
    x = 0
    while x < W:
        step = rng.randint(5, 11)
        top = crest_y + rng.randint(-jag, jag)
        for k in range(step):
            if x + k < W:
                tip = top - (jag // 2 if k == step // 2 else 0)
                pts[x + k] = tip
        x += step
    crest = pts[xx[0]]
    return (yy >= crest[None, :]) & (yy < HORIZON)


def render_logo(target_w):
    try:
        font = ImageFont.truetype(FONT_PATH, 150)
    except Exception:
        font = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", 130)
    tmp = Image.new("RGBA", (1400, 320), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((30, 20), TITLE, font=font, fill=WHITE,
                             stroke_width=10, stroke_fill=BLACK)
    logo = tmp.crop(tmp.getbbox())
    sh = 0.26
    nw = logo.width + int(logo.height * sh)
    logo = logo.transform((nw, logo.height), Image.AFFINE,
                          (1, sh, -sh * logo.height, 0, 1, 0), resample=Image.BICUBIC)
    scale = target_w / logo.width
    logo = logo.resize((target_w, max(1, int(logo.height * scale))), Image.LANCZOS)
    arr = np.array(logo)
    alpha = (arr[..., 3] >= 110).astype(np.uint8) * 255
    lum = np.where(arr[..., 0] >= 128, 255, 0).astype(np.uint8)
    out = np.zeros_like(arr)
    out[..., 0] = lum; out[..., 1] = lum; out[..., 2] = lum; out[..., 3] = alpha
    crisp = Image.fromarray(out, "RGBA")
    sil = np.zeros_like(arr); sil[..., 3] = alpha
    pad = 5
    canvas = Image.new("RGBA", (crisp.width + pad, crisp.height + pad), (0, 0, 0, 0))
    canvas.alpha_composite(Image.fromarray(sil, "RGBA"), (pad, pad))
    canvas.alpha_composite(crisp, (0, 0))
    return canvas


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    a = np.full((H, W, 4), 255, dtype=np.uint8)
    a[..., 3] = 255
    yy, xx = np.mgrid[0:H, 0:W]

    sky = yy < HORIZON
    a[sky & (BAYER < 0.06)] = BLACK      # barely-there overcast tone

    back  = forest_ridge(98,  6, 1)
    midr  = forest_ridge(114, 7, 2)
    front = forest_ridge(132, 8, 3)
    dither_fill(a, back,  0.32)
    dither_fill(a, midr,  0.60)
    dither_fill(a, front, 0.90)

    # mist bands between the ridge layers + along the horizon
    for fy in (110, 128):
        band = (yy >= fy) & (yy < fy + 3)
        a[band] = WHITE
        a[band & (BAYER < 0.10)] = BLACK
    hmist = (yy >= HORIZON - 4) & (yy < HORIZON + 4)
    a[hmist] = WHITE
    a[hmist & (BAYER < 0.08)] = BLACK

    ground = yy >= HORIZON
    a[ground] = WHITE
    a[ground & (BAYER < 0.10)] = BLACK
    road = np.zeros((H, W), dtype=bool)
    for y in range(HORIZON, H):
        t = (y - HORIZON) / (H - HORIZON)
        half = int(6 + t * t * 150)
        cxr = int(W // 2 + 8 + np.sin(t * 2.2) * 26 * t)
        road[y, max(0, cxr - half):min(W, cxr + half)] = True
    a[road] = WHITE
    a[road & (BAYER < 0.06)] = BLACK

    img = Image.fromarray(a, "RGBA")

    try:
        tree = Image.open(TREE_PATH).convert("RGBA")
        th = 168
        tw = int(tree.width * th / tree.height)
        big = tree.resize((tw, th), Image.NEAREST)
        img.alpha_composite(big, (-18, H - th + 8))
        sm = tree.resize((int(tw * 0.8), int(th * 0.8)), Image.NEAREST)
        img.alpha_composite(sm.transpose(Image.FLIP_LEFT_RIGHT), (W - sm.width + 16, H - sm.height + 6))
    except Exception:
        pass

    logo = render_logo(300)
    img.alpha_composite(logo, ((W - logo.width) // 2, 12))

    a = np.array(img)
    lum = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
    bw = np.where(lum >= 128, 255, 0).astype(np.uint8)
    a[..., 0] = bw; a[..., 1] = bw; a[..., 2] = bw; a[..., 3] = 255
    Image.fromarray(a, "RGBA").convert("RGB").save(OUT)
    print("wrote:", OUT, (W, H))


if __name__ == "__main__":
    main()
