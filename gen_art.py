#!/usr/bin/env python3
"""Generate 1-bit PNG art for MeowtaRacer (Playdate).
Convention: pure black (0,0,0,255) = black pixel, white (255,255,255,255) = white,
alpha 0 = transparent. Playdate importer keys off luminance/alpha thresholds.
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "Source", "images")
os.makedirs(OUT, exist_ok=True)

BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def new(w, h):
    return Image.new("RGBA", (w, h), CLEAR)


# ---------------------------------------------------------------------------
# Player car: rear 3/4 view sports car. 3 frames: straight, lean-left, lean-right
# Cell size 72x48, laid out in one row -> imagetable "player-table-72-48.png"
# ---------------------------------------------------------------------------
CW, CH = 72, 48


def draw_car(d, ox, lean):
    """lean: -1 left, 0 straight, +1 right. ox = cell x origin."""
    cx = ox + CW // 2 + lean * 2
    base = 44  # bottom of car within cell

    # tyres
    d.rectangle([ox + 6, base - 8, ox + 16, base], fill=BLACK)
    d.rectangle([ox + CW - 16, base - 8, ox + CW - 6, base], fill=BLACK)
    # hubcaps
    d.ellipse([ox + 8, base - 6, ox + 14, base - 1], fill=WHITE)
    d.ellipse([ox + CW - 14, base - 6, ox + CW - 8, base - 1], fill=WHITE)

    # main body (wide low wedge) -- skew with lean
    sk = lean * 3
    body = [
        (cx - 30 + sk, base - 6),
        (cx + 30 + sk, base - 6),
        (cx + 26 + sk, base - 16),
        (cx - 26 + sk, base - 16),
    ]
    d.polygon(body, fill=BLACK)
    # lower valance / diffuser
    d.rectangle([cx - 30 + sk, base - 8, cx + 30 + sk, base - 4], fill=BLACK)

    # rear deck / cabin
    deck = [
        (cx - 24 + sk, base - 16),
        (cx + 24 + sk, base - 16),
        (cx + 18 + sk, base - 28),
        (cx - 18 + sk, base - 28),
    ]
    d.polygon(deck, fill=BLACK)

    # rear window (white slit)
    d.polygon([
        (cx - 14 + sk, base - 27),
        (cx + 14 + sk, base - 27),
        (cx + 11 + sk, base - 23),
        (cx - 11 + sk, base - 23),
    ], fill=WHITE)
    d.line([(cx + sk, base - 27), (cx + sk, base - 23)], fill=BLACK, width=1)

    # tail lights (full-width light bar, broken in middle) - white
    d.rectangle([cx - 26 + sk, base - 14, cx - 6 + sk, base - 10], fill=WHITE)
    d.rectangle([cx + 6 + sk, base - 14, cx + 26 + sk, base - 10], fill=WHITE)
    # license/centre
    d.rectangle([cx - 4 + sk, base - 13, cx + 4 + sk, base - 11], fill=WHITE)
    # spoiler edge highlight
    d.line([(cx - 26 + sk, base - 16), (cx + 26 + sk, base - 16)], fill=WHITE, width=1)
    # exhaust tips
    d.rectangle([cx - 10 + sk, base - 5, cx - 6 + sk, base - 3], fill=WHITE)
    d.rectangle([cx + 6 + sk, base - 5, cx + 10 + sk, base - 3], fill=WHITE)


img = new(CW * 3, CH)
d = ImageDraw.Draw(img)
for i, lean in enumerate((0, -1, 1)):
    draw_car(d, i * CW, lean)
img.save(os.path.join(OUT, "player-table-72-48.png"))

# ---------------------------------------------------------------------------
# Palm tree
# ---------------------------------------------------------------------------
pw, ph = 64, 96
img = new(pw, ph)
d = ImageDraw.Draw(img)
tx = pw // 2
# curved trunk
for y in range(28, ph):
    t = (y - 28) / (ph - 28)
    x = tx + int(8 * (t ** 2)) - 4
    w = 2 + int(t * 3)
    d.rectangle([x - w, y, x + w, y + 1], fill=BLACK)
# fronds
crown = (tx - 4, 30)
import math
for ang in range(0, 360, 30):
    a = math.radians(ang)
    ex = crown[0] + int(math.cos(a) * 26)
    ey = crown[1] + int(math.sin(a) * 16) - 6
    d.line([crown, (ex, ey)], fill=BLACK, width=3)
    # droop tip
    d.line([(ex, ey), (ex + int(math.cos(a) * 4), ey + 6)], fill=BLACK, width=2)
d.ellipse([crown[0] - 6, crown[1] - 6, crown[0] + 6, crown[1] + 6], fill=BLACK)
# coconuts (white dots)
d.ellipse([tx - 6, 32, tx - 2, 36], fill=WHITE)
d.ellipse([tx + 2, 33, tx + 6, 37], fill=WHITE)
img.save(os.path.join(OUT, "palm.png"))

# ---------------------------------------------------------------------------
# Billboard / sign (arrow chevron sign)
# ---------------------------------------------------------------------------
sw, sh = 56, 64
img = new(sw, sh)
d = ImageDraw.Draw(img)
# posts
d.rectangle([12, 30, 16, sh], fill=BLACK)
d.rectangle([sw - 16, 30, sw - 12, sh], fill=BLACK)
# board
d.rectangle([4, 4, sw - 4, 30], fill=BLACK)
d.rectangle([6, 6, sw - 6, 28], fill=WHITE)
# chevrons (black arrows pointing right)
for i in range(3):
    bx = 10 + i * 13
    d.polygon([(bx, 10), (bx + 8, 17), (bx, 24), (bx + 4, 17)], fill=BLACK)
img.save(os.path.join(OUT, "sign.png"))

# ---------------------------------------------------------------------------
# Background: tileable mountains + sun + clouds. 800 wide, 130 tall.
# Bottom is transparent so road grass shows through; sky stays white.
# ---------------------------------------------------------------------------
bw, bh = 800, 130
img = new(bw, bh)
d = ImageDraw.Draw(img)
# sun outline with horizontal slats (classic synth sun)
sun = (150, 48, 30)
d.ellipse([sun[0] - sun[2], sun[1] - sun[2], sun[0] + sun[2], sun[1] + sun[2]], outline=BLACK, width=2)
for i, yy in enumerate(range(sun[1] - 4, sun[1] + sun[2], 6)):
    d.line([(sun[0] - sun[2], yy), (sun[0] + sun[2], yy)], fill=BLACK, width=2)
# distant mountain ridge (seamless: same height at x=0 and x=bw)
ridge = []
random_seed = [40, 70, 55, 95, 60, 110, 75, 50, 88, 62, 100, 45, 70, 40]
n = len(random_seed)
for i in range(n + 1):
    x = int(i * bw / n)
    yv = bh - random_seed[i % n]
    ridge.append((x, yv))
poly = ridge + [(bw, bh), (0, bh)]
d.polygon(poly, fill=BLACK)
# a second nearer ridge with white snowline detail
for (x, y) in ridge:
    d.line([(x, y), (x, y + 4)], fill=WHITE, width=1)
# clouds (white blobs with black outline against... sky is white, so outline only)
for cxk in (300, 470, 640):
    cy = 28
    for dx2, r in ((0, 9), (12, 12), (26, 9), (-12, 7)):
        d.ellipse([cxk + dx2 - r, cy - r // 2, cxk + dx2 + r, cy + r // 2], outline=BLACK, width=2, fill=WHITE)
img.save(os.path.join(OUT, "bg.png"))

print("wrote:", sorted(os.listdir(OUT)))
