"""Sprites for Cinematic's Wind Guide (WindGuide.lua): 128x128, white, the
picture in the alpha. Each lies along the x axis, its head to the right (the
way it blows), so the game can turn it to the wind with SetRotation; square,
so turning doesn't squash it. Soft shapes only: wind, light, shadow, snow.
  Streak  a thin line of wind, faint at its tail, brightest near its head
  Wisp    a longer streak, curling up at its head
  Gust1/2 a gust: a few thin strands of wind side by side, of different
          lengths, gently curving
  Shade1/2 a thick, soft-edged smear of shadow, tapering at both ends
  Arc1-6  a jagged lightning arc with a branch or two, in its own glow
  Glow    a soft light: a bright middle, a wide halo and a faint cross flare
  Snow    a soft round snowflake (a blurred speck)
  Mote    a soft round speck of light
Also copies of Vitals Vision's sprites (Textures/LowHealth/Effects.tga, made
by make_lowhealth.py), each in a file of its own so it can be turned without
its neighbours' edges showing: those with a way they go turned to face right.
Our own, made from scratch here; usage: make_wind_guide.py Textures/WindGuide"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "WindGuide"
N, BIG = 128, 512  # (drawn at BIG and shrunk, for smooth edges)
C = BIG / 2
YY, XX = np.mgrid[0:BIG, 0:BIG].astype(float)


def save(name, alpha):
    alpha = np.clip(alpha, 0, 1)
    rgba = np.stack([np.ones_like(alpha)] * 3 + [alpha], -1)
    image = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    image.resize((N, N), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"), compression="tga_rle")


def as_array(image, blur):
    return np.asarray(image.filter(ImageFilter.GaussianBlur(blur)), dtype=np.float64) / 255


def strand(draw, points, width_from, width_to, bright=1.0, tail=1.4, head=8):
    """A line through points, fading in from its tail and out at its head,
    thickening toward the head."""
    count = len(points) - 1
    for j in range(count):
        t = j / count
        fade = min(1, t * tail) * min(1, (1 - t) * head)
        draw.line((points[j], points[j + 1]), fill=int(255 * fade * bright),
                  width=max(1, round(width_from + (width_to - width_from) * t)))


def line(points, width_from, width_to):
    image = Image.new("L", (BIG, BIG), 0)
    strand(ImageDraw.Draw(image), points, width_from, width_to)
    return as_array(image, 4)


def gust(seed):
    rng = np.random.default_rng(seed)
    image = Image.new("L", (BIG, BIG), 0)
    draw = ImageDraw.Draw(image)
    for k, offset in enumerate((-34, 0, 30)):
        start, end = rng.uniform(20, 140), rng.uniform(BIG - 120, BIG - 20)
        amp, phase = rng.uniform(6, 16), rng.uniform(0, math.pi)
        points = [(start + t * (end - start), C + offset + amp * math.sin(t * math.pi * 1.5 + phase))
                  for t in [j / 60 for j in range(61)]]
        strand(draw, points, 2, 7, bright=(1.0, 0.75, 0.55)[k], tail=1.2, head=5)
    return as_array(image, 3)


def shade(seed):
    rng = np.random.default_rng(seed)
    image = Image.new("L", (BIG, BIG), 0)
    draw = ImageDraw.Draw(image)
    amp, phase = rng.uniform(10, 25), rng.uniform(0, math.pi)
    steps = [j / 60 for j in range(61)]
    middle = [(40 + t * (BIG - 80), C + amp * math.sin(t * math.pi * 1.2 + phase)) for t in steps]
    width = [38 * math.sin(math.pi * t) ** 0.8 * (0.6 + 0.4 * t) for t in steps]  # (fuller at the head)
    outline = [(x, y - w) for (x, y), w in zip(middle, width)] + \
              [(x, y + w) for (x, y), w in reversed(list(zip(middle, width)))]
    draw.polygon(outline, fill=215)
    return as_array(image, 11)


def lightning(seed):
    rng = np.random.default_rng(seed)

    def jagged(x0, y0, x1, y1, spread, depth):
        if depth == 0:
            return [(x0, y0), (x1, y1)]
        mx = (x0 + x1) / 2 + rng.normal(0, spread * 0.3)
        my = (y0 + y1) / 2 + rng.normal(0, spread)
        return jagged(x0, y0, mx, my, spread / 2, depth - 1)[:-1] + jagged(mx, my, x1, y1, spread / 2, depth - 1)

    core = Image.new("L", (BIG, BIG), 0)
    draw = ImageDraw.Draw(core)
    main = jagged(30, C, BIG - 30, C + rng.normal(0, 20), 70, 6)
    strand(draw, main, 14, 10, tail=6, head=6)
    for _ in range(rng.integers(1, 3)):  # (a branch or two off it)
        x, y = main[rng.integers(len(main) // 4, len(main) * 3 // 4)]
        a = rng.uniform(0.4, 0.9) * (1 if rng.uniform() < 0.5 else -1)
        reach = rng.uniform(80, 150)
        strand(draw, jagged(x, y, x + math.cos(a) * reach, y + math.sin(a) * reach, 25, 4), 8, 4, tail=20, head=2)
    sharp, glow = as_array(core, 1.5), as_array(core, 12)
    return np.maximum(sharp, np.clip(glow * 2.2, 0, 0.55))


def main():
    os.makedirs(OUT, exist_ok=True)
    steps = [j / 60 for j in range(61)]
    save("Streak", line([(30 + t * (BIG - 70), C + math.sin(t * 2.5) * 6) for t in steps], 3, 14))
    save("Wisp", line([(10 + t * (BIG - 60), C + 30 - 60 * t ** 3 + math.sin(t * 4) * 8) for t in steps], 2, 12))
    save("Gust1", gust(11))
    save("Gust2", gust(23))
    save("Shade1", shade(5))
    save("Shade2", shade(9))
    for k in range(6):
        save("Arc%d" % (k + 1), lightning(40 + k))
    d = np.hypot(XX - C, YY - C) / (BIG / 2)
    save("Mote", np.clip(1 - d / 0.25, 0, 1) ** 2 * 0.9 + np.clip(1 - d, 0, 1) ** 3 * 0.35)
    flare = (np.exp(-((YY - C) / 6) ** 2) + np.exp(-((XX - C) / 6) ** 2)) * np.clip(1 - d, 0, 1) ** 4 * 0.12
    save("Glow", np.clip(1 - d / 0.3, 0, 1) ** 1.2 + np.clip(1 - d, 0, 1) ** 1.8 * 0.5 + flare)
    save("Snow", np.clip((1 - d / 0.45) / 0.6, 0, 1) ** 1.5 * 0.95)
    copy_effects()


# Vitals Vision's sprites (8 across, 128 each, in make_lowhealth.py's order)
# to copy, and how far to turn each (degrees, anticlockwise) to face right.
EFFECT_CELLS = ["Splat1", "Splat2", "Splat3", "Splat4", "Slash", "Claw", "CrackBurst", "Ember",
                "Mote", "Feather", "Leaf", "Puff", "Shard", "Rain", "Bolt", "Ripple",
                "Rune1", "Rune2", "Rune3", "Eye", "Star", "Dust", "Bruise", "Spark",
                "Bubble", "Petal", "Wind", "Sand", "Paw", "WolfEyes", "Leaf2"]
COPIES = {"Ember": 0, "Rain": 90, "Ripple": 0, "Star": 0, "Bubble": 0}


def copy_effects():
    sheet = Image.open(os.path.join(OUT, "..", "LowHealth", "Effects.tga")).convert("RGBA")
    for name, turn in COPIES.items():
        i = EFFECT_CELLS.index(name)
        cell = sheet.crop((i % 8 * N, i // 8 * N, (i % 8 + 1) * N, (i // 8 + 1) * N))
        if turn:
            cell = cell.rotate(turn)
        cell.save(os.path.join(OUT, name + ".tga"), compression="tga_rle")


main()
