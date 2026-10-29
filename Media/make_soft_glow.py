"""Soft round glow for the quest item button's ready glow (QuestItemButton.lua):
64x64, white, its alpha falling from full in the middle to clear at the edge,
eased, so the game can tint it and draw it added on. Our own, made from
scratch here; usage: make_soft_glow.py Textures/SoftGlow.tga"""
import sys
from PIL import Image

N = 64
OUT = sys.argv[1] if len(sys.argv) > 1 else "SoftGlow.tga"


def alpha(x, y):
    c = (N - 1) / 2
    t = max(0.0, 1 - (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c)
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
image.save(OUT)
