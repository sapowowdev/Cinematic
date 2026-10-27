"""Target indicator for nameplates (PlateParts.lua): 64x64, a white arrow
pointing down, with a dark edge so it reads on light skies, on a see-through
background. White so the game can tint it. Our own, drawn from scratch here;
usage: make_target_arrow.py Textures/TargetArrow.tga"""
import sys
from PIL import Image, ImageDraw

N = 64
S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "TargetArrow.tga"

big = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
draw = ImageDraw.Draw(big)


def arrow(inset):
    """A chevron-backed arrowhead: its point at the bottom middle, a notch in its top."""
    points = [(8 + inset, 14 + inset * 0.6), (32, 24 + inset * 0.4), (56 - inset, 14 + inset * 0.6),
              (32, 56 - inset * 1.4)]
    return [(x * S, y * S) for x, y in points]


# A soft shadow, the dark edge, then the white face.
draw.polygon([(x + 1.5 * S, y + 2 * S) for x, y in arrow(0)], fill=(0, 0, 0, 90))
draw.polygon(arrow(0), fill=(20, 16, 10, 255))
draw.polygon(arrow(3.2), fill=(255, 255, 255, 255))

big.resize((N, N), Image.LANCZOS).save(OUT)
