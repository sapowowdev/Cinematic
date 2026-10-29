"""Bar fills for the Style pages' texture lists (StylePages.lua): 256x32, white
shaded in grey (the game tints them the bar's color), fully opaque. Our own,
drawn from scratch here; usage: make_bar_textures.py Textures/Bars
Glass: a bright band along the top over a darker lower half, like polished glass.
Soft: a gentle shade from light at the top to darker at the bottom.
Striped: thin diagonal lines over a light ground.
Minimal: flat, with a one-pixel highlight along the top and a shade along the bottom.
Rounded: lit in the middle and darker at the top and bottom, like a tube."""
import math
import os
import sys

from PIL import Image

W, H = 256, 32
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def glass(x, y):
    v = y / (H - 1)
    if v < 0.45:
        level = 1.0 - 0.18 * smooth(v / 0.45)
    else:
        level = 0.66 - 0.12 * smooth((v - 0.45) / 0.55)
    if y <= 1:
        level = 1.0
    return level


def soft(x, y):
    return 1.0 - 0.38 * smooth(y / (H - 1))


def striped(x, y):
    # (Lines at 45 degrees, 10 px apart, 4 px wide, their edges eased.)
    d = (x + y) % 10
    edge = min(abs(d - 2), abs(d - 12), abs(d + 8))
    stripe = 1 - smooth((edge - 1.5) / 1.0)
    return (0.92 - 0.06 * (y / (H - 1))) - 0.24 * stripe


def minimal(x, y):
    if y == 0:
        return 1.0
    if y == H - 1:
        return 0.62
    return 0.86


def rounded(x, y):
    v = (y + 0.5) / H
    return 0.58 + 0.42 * math.sin(math.pi * v) ** 0.7


SHADES = {"Glass": glass, "Soft": soft, "Striped": striped, "Minimal": minimal, "Rounded": rounded}

os.makedirs(OUT, exist_ok=True)
for name, shade in SHADES.items():
    image = Image.new("RGBA", (W, H))
    pixels = []
    for y in range(H):
        for x in range(W):
            g = round(255 * min(max(shade(x, y), 0.0), 1.0))
            pixels.append((g, g, g, 255))
    image.putdata(pixels)
    image.save(os.path.join(OUT, name + ".tga"))
