"""The target indicator's other styles (PlateParts.lua's Target Arrow), each
white with a dark edge (the glow: soft, no edge) so the game can tint it,
on a see-through background. Our own, drawn from scratch here; usage:
make_target_marks.py Textures   (writes TargetChevron, TargetGlow and
TargetBracket .tga there)"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
EDGE, FACE, SHADOW = (20, 16, 10, 255), (255, 255, 255, 255), (0, 0, 0, 90)


def canvas(w, h):
    big = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return big, ImageDraw.Draw(big)


def scaled(points, dx=0.0, dy=0.0):
    return [((x + dx) * S, (y + dy) * S) for x, y in points]


def save(big, w, h, name):
    big.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, name))


# Chevron: two thin stacked chevrons pointing down, 64x64.
def chevron(top, thick):
    return [(10, top), (32, top + 16), (54, top), (54, top + thick), (32, top + 16 + thick), (10, top + thick)]


big, draw = canvas(64, 64)
for top in (10, 30):
    draw.polygon(scaled(chevron(top, 12), 1.5, 2), fill=SHADOW)
    draw.polygon(scaled(chevron(top, 12)), fill=EDGE)
    draw.polygon(scaled([(13, top + 2.6), (32, top + 16.4), (51, top + 2.6), (51, top + 9.4), (32, top + 23.4),
                         (13, top + 9.4)]), fill=FACE)
save(big, 64, 64, "TargetChevron.tga")

# Glow: a soft white oval, brightest in the middle, 128x64.
big = Image.new("L", (128 * S, 64 * S), 0)
ImageDraw.Draw(big).ellipse([14 * S, 14 * S, 114 * S, 50 * S], fill=255)
mask = big.filter(ImageFilter.GaussianBlur(9 * S)).resize((128, 64), Image.LANCZOS)
glow = Image.new("RGBA", (128, 64), (255, 255, 255, 0))
glow.putalpha(mask)
glow.save(os.path.join(OUT, "TargetGlow.tga"))

# Bracket: a left-hand [ (the right one is it mirrored), 32x64.
outer = [(26, 4), (26, 12), (14, 12), (14, 52), (26, 52), (26, 60), (6, 60), (6, 4)]
inner = [(23.5, 6.5), (23.5, 9.5), (11.5, 9.5), (11.5, 54.5), (23.5, 54.5), (23.5, 57.5), (8.5, 57.5), (8.5, 6.5)]
big, draw = canvas(32, 64)
draw.polygon(scaled(outer, 1.5, 2), fill=SHADOW)
draw.polygon(scaled(outer), fill=EDGE)
draw.polygon(scaled(inner), fill=FACE)
save(big, 32, 64, "TargetBracket.tga")
