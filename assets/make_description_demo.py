"""Builds assets/description-demo.png, the demo image for the CurseForge description, from
in-game screenshots.

    python assets/make_description_demo.py <screenshot folder> assets/description-demo.png

The crops below are for the screenshots it was first made from; adjust them for new ones.
"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = sys.argv[1]  # folder with the screenshots
OUT = sys.argv[2]
W = 1200
PAD = 24
GAP = 18
BG = (18, 16, 14)
PANEL = (30, 26, 22)
GOLD = (255, 209, 0)
CAP = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 22)
CAPH = 40


def shot(name, box):
    return Image.open(f"{SRC}/{name}").convert("RGB").crop(box)


def fit(im, w, h=None):
    scale = w / im.width
    if h:
        scale = min(scale, h / im.height)
    return im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)


LABEL = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 24)


def callout(im, text, x, y, side):
    """A gold label on a dark pill, with an arrow on the given side ("left" or "right") pointing at
    what it names. (x, y) is the arrow's tip."""
    d = ImageDraw.Draw(im, "RGBA")
    tw = d.textlength(text, font=LABEL)
    h = 40
    if side == "left":
        l = x + 18
    else:
        l = x - 18 - tw - 24
    r = l + tw + 24
    d.rounded_rectangle([l, y - h // 2, r, y + h // 2], radius=10, fill=(0, 0, 0, 205), outline=GOLD, width=2)
    if side == "left":
        d.polygon([(x, y), (l + 1, y - 11), (l + 1, y + 11)], fill=GOLD)
    else:
        d.polygon([(x, y), (r - 1, y - 11), (r - 1, y + 11)], fill=GOLD)
    d.text(((l + r) / 2, y), text, font=LABEL, fill=GOLD, anchor="mm")
    return im


def panel(im, w, caption, h=None):
    im = fit(im, w - 12, h)
    ph = (h or im.height) + 12 + CAPH
    p = Image.new("RGB", (w, ph), PANEL)
    p.paste(im, ((w - im.width) // 2, 6 + ((h or im.height) - im.height) // 2))
    d = ImageDraw.Draw(p)
    d.rectangle([0, 0, w - 1, ph - 1], outline=(120, 96, 50), width=2)
    d.text((w // 2, ph - CAPH // 2 - 4), caption, font=CAP, fill=GOLD, anchor="mm")
    return p


rows = []
# Hero: our frame beside Blizzard's own target frame and its Target of Target.
hero = shot("46.webp", (100, 160, 1430, 450))
callout(hero, "Pet Target Frame", 480, 177, "left")
callout(hero, "Blizzard's Target of Target", 1100, 172, "right")
rows.append([panel(hero, W - 2 * PAD,
                   "Your pet's target, in a frame just like Blizzard's Target of Target")])
half = (W - 2 * PAD - GAP) // 2
rows.append([
    panel(shot("37.webp", (0, 110, 820, 300)), half, "Debuffs in combat, with tooltips", h=200),
    panel(shot("44.png", (80, 90, 575, 330)), half, "Health and power follow your Status Text", h=200),
])
third = (W - 2 * PAD - 2 * GAP) // 3
rows.append([
    panel(shot("49.webp", (0, 30, 820, 360)), third, "Place it in Edit Mode", h=200),
    panel(shot("42.png", (0, 0, 584, 300)), third, "Attach it or resize it", h=200),
    panel(shot("43.png", (740, 30, 1109, 140)), third, "Leave it out of Edit Mode", h=200),
])

# No title: the description's own text names the addon.
H = PAD + sum(max(p.height for p in r) for r in rows) + GAP * (len(rows) - 1) + PAD
img = Image.new("RGB", (W, H), BG)
y = PAD
for r in rows:
    widths = sum(p.width for p in r) + GAP * (len(r) - 1)
    x = (W - widths) // 2
    for p in r:
        img.paste(p, (x, y))
        x += p.width + GAP
    y += max(p.height for p in r) + GAP
img.save(OUT, optimize=True)
print(OUT, img.size)
