"""Draw the Simple Pet Target project logo: a paw print inside a target reticle.

Usage: python make_logo.py <output.png> [size]
Drawn at 4x and downscaled for clean anti-aliased edges.
"""
import sys
from PIL import Image, ImageDraw

out_path = sys.argv[1]
size = int(sys.argv[2]) if len(sys.argv) > 2 else 512
S = size * 4

GOLD = (232, 182, 76, 255)
CREAM = (246, 238, 222, 255)
TOP = (30, 37, 52)
BOTTOM = (11, 13, 19)

# Background: vertical gradient clipped to a rounded square.
bg = Image.new("RGBA", (S, S))
bg_draw = ImageDraw.Draw(bg)
for y in range(S):
    t = y / (S - 1)
    bg_draw.line([(0, y), (S, y)], fill=tuple(round(TOP[i] * (1 - t) + BOTTOM[i] * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=round(S * 0.18), fill=255)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.paste(bg, (0, 0), mask)

d = ImageDraw.Draw(img)

# Inset gold border.
inset = round(S * 0.035)
d.rounded_rectangle([inset, inset, S - 1 - inset, S - 1 - inset], radius=round(S * 0.15),
                    outline=GOLD, width=round(S * 0.012))

cx = cy = S / 2

# Reticle ring with four ticks crossing it.
R = S * 0.33
w = round(S * 0.03)
d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GOLD, width=w)
inner, outer = R * 0.80, R * 1.22
half = w / 2
d.rectangle([cx - half, cy - outer, cx + half, cy - inner], fill=GOLD)  # north
d.rectangle([cx - half, cy + inner, cx + half, cy + outer], fill=GOLD)  # south
d.rectangle([cx - outer, cy - half, cx - inner, cy + half], fill=GOLD)  # west
d.rectangle([cx + inner, cy - half, cx + outer, cy + half], fill=GOLD)  # east


def oval(x, y, width, height, fill):
    d.ellipse([x - width / 2, y - height / 2, x + width / 2, y + height / 2], fill=fill)


# Paw print: main pad plus four toes.
oval(cx, cy + S * 0.065, S * 0.25, S * 0.19, CREAM)
oval(cx - S * 0.075, cy + S * 0.10, S * 0.15, S * 0.13, CREAM)  # widen the base of the pad
oval(cx + S * 0.075, cy + S * 0.10, S * 0.15, S * 0.13, CREAM)
for dx, dy in ((-0.158, -0.070), (-0.062, -0.148), (0.062, -0.148), (0.158, -0.070)):
    oval(cx + S * dx, cy + S * dy, S * 0.088, S * 0.112, CREAM)

img.resize((size, size), Image.Resampling.LANCZOS).save(out_path)
print(f"wrote {out_path} ({size}x{size})")
