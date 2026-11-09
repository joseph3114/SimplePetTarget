"""Draw the Edit Mode style logo: a unit frame selected in Edit Mode, labeled "Pet Target Frame".

Original artwork in the style of the Edit Mode selection (no game textures are used).
Usage: python make_logo_editmode.py <output.png> [size]
Drawn at 4x and downscaled for clean anti-aliased edges. Translucent shapes are drawn on their
own layers and alpha-composited, because ImageDraw replaces RGBA pixels instead of blending them.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

out_path = sys.argv[1]
size = int(sys.argv[2]) if len(sys.argv) > 2 else 512
S = size * 4

LABEL = "Pet Target Frame"
FONT_PATH = r"C:\Windows\Fonts\constanb.ttf"

YELLOW = (255, 210, 40)
CREAM = (246, 238, 222, 255)


def lerp(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def vertical_gradient(width, height, top, bottom):
    layer = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(layer)
    for y in range(height):
        draw.line([(0, y), (width, y)], fill=lerp(top, bottom, y / max(height - 1, 1)) + (255,))
    return layer


def rounded_mask(width, height, radius):
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, height - 1], radius=radius, fill=255)
    return mask


def new_layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


# Background: dusky gradient with a faint Edit Mode grid, clipped to a rounded square.
background = vertical_gradient(S, S, (58, 44, 40), (20, 18, 24))
grid = new_layer()
grid_draw = ImageDraw.Draw(grid)
step = S // 8
for i in range(1, 8):
    grid_draw.line([(i * step, 0), (i * step, S)], fill=(255, 255, 255, 34), width=round(S * 0.003))
    grid_draw.line([(0, i * step), (S, i * step)], fill=(255, 255, 255, 34), width=round(S * 0.003))
background.alpha_composite(grid)
img = new_layer()
img.paste(background, (0, 0), rounded_mask(S, S, round(S * 0.18)))

# Unit frame geometry.
fx0, fx1 = round(S * 0.08), round(S * 0.92)
fy0, fy1 = round(S * 0.34), round(S * 0.68)
fh = fy1 - fy0
radius = round(S * 0.05)
pad = round(S * 0.02)

# Selection glow, under the frame.
glow = new_layer()
ImageDraw.Draw(glow).rounded_rectangle([fx0 - pad, fy0 - pad, fx1 + pad, fy1 + pad], radius=radius + pad,
                                       outline=YELLOW + (255,), width=round(S * 0.03))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.018)))

d = ImageDraw.Draw(img)

# Frame body and border (opaque).
d.rounded_rectangle([fx0, fy0, fx1, fy1], radius=radius, fill=(22, 24, 32, 255),
                    outline=(150, 156, 168, 255), width=round(S * 0.008))

# Portrait: metal ring around a dark disc with a paw print.
pr = round(fh * 0.40)
pcx, pcy = fx0 + round(S * 0.035) + pr, (fy0 + fy1) // 2
d.ellipse([pcx - pr, pcy - pr, pcx + pr, pcy + pr], fill=(168, 174, 186, 255))
inner = round(pr * 0.86)
d.ellipse([pcx - inner, pcy - inner, pcx + inner, pcy + inner], fill=(34, 40, 52, 255))


def oval(x, y, w, h):
    d.ellipse([x - w / 2, y - h / 2, x + w / 2, y + h / 2], fill=CREAM)


u = inner * 2.5  # paw scale
oval(pcx, pcy + u * 0.10, u * 0.40, u * 0.30)
oval(pcx - u * 0.12, pcy + u * 0.155, u * 0.24, u * 0.21)
oval(pcx + u * 0.12, pcy + u * 0.155, u * 0.24, u * 0.21)
for dx, dy in ((-0.25, -0.11), (-0.10, -0.235), (0.10, -0.235), (0.25, -0.11)):
    oval(pcx + u * dx, pcy + u * dy, u * 0.14, u * 0.18)

# Health and power bars.
bx0, bx1 = pcx + pr + round(S * 0.03), fx1 - round(S * 0.04)
hb_h, pb_h, gap = round(fh * 0.24), round(fh * 0.16), round(fh * 0.06)
hb_y0 = pcy - (hb_h + gap + pb_h) // 2
pb_y0 = hb_y0 + hb_h + gap
for y0, h, top, bottom, fill_pct in ((hb_y0, hb_h, (86, 214, 120), (28, 140, 70), 1.0),
                                     (pb_y0, pb_h, (92, 150, 255), (34, 82, 200), 0.78)):
    d.rounded_rectangle([bx0, y0, bx1, y0 + h], radius=h // 3, fill=(10, 12, 16, 255))
    width = round((bx1 - bx0) * fill_pct)
    img.paste(vertical_gradient(width, h, top, bottom), (bx0, y0), rounded_mask(width, h, h // 3))

# Selected-state tint and crisp yellow outline on top of the frame.
tint = new_layer()
ImageDraw.Draw(tint).rounded_rectangle([fx0 - pad // 2, fy0 - pad // 2, fx1 + pad // 2, fy1 + pad // 2],
                                       radius=radius + pad // 2, fill=YELLOW + (40,),
                                       outline=YELLOW + (255,), width=round(S * 0.012))
img.alpha_composite(tint)

# Label, sized to fit across the frame, with a soft drop shadow and a dark outline.
font_size = round(S * 0.12)
while True:
    font = ImageFont.truetype(FONT_PATH, font_size)
    stroke = round(font_size * 0.08)
    left, top, right, bottom = d.textbbox((0, 0), LABEL, font=font, stroke_width=stroke)
    if right - left <= (fx1 - fx0) * 0.92:
        break
    font_size -= 4
tx = (S - (right - left)) // 2 - left
ty = (fy0 + fy1) // 2 - (bottom - top) // 2 - top
shadow = new_layer()
offset = round(font_size * 0.06)
ImageDraw.Draw(shadow).text((tx + offset, ty + offset), LABEL, font=font, fill=(0, 0, 0, 170),
                            stroke_width=stroke, stroke_fill=(0, 0, 0, 170))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(font_size * 0.04)))
ImageDraw.Draw(img).text((tx, ty), LABEL, font=font, fill=(255, 255, 255, 255),
                         stroke_width=stroke, stroke_fill=(0, 0, 0, 255))

img.resize((size, size), Image.Resampling.LANCZOS).save(out_path)
print(f"wrote {out_path} ({size}x{size})")
