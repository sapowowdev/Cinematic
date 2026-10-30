"""Draws Textures/Wasted.tga: "wasted" in red with a dark outline, for the
death banner's wasted style.

The lettering is Pricedown (Typodermic). Its free desktop license covers
fixed artwork like this, where the font software isn't shipped, so only the
image goes in the addon: never the font file.

    python -I Tools/wasted-banner/render.py "path/to/Pricedown Bl.otf"
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1024, 256
TEXT = "wasted"
FILL = (196, 38, 32, 255)
OUTLINE = (20, 6, 6, 255)
STROKE = 5  # outline width, pixels
MARGIN = 16

def main():
    font_path = sys.argv[1]
    out = os.path.join(os.path.dirname(__file__), "..", "..", "Textures", "Wasted.tga")
    # The biggest size that fits, outline included.
    size = 400
    while True:
        font = ImageFont.truetype(font_path, size)
        left, top, right, bottom = font.getbbox(TEXT, stroke_width=STROKE)
        if right - left <= WIDTH - 2 * MARGIN and bottom - top <= HEIGHT - 2 * MARGIN:
            break
        size -= 2
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    x = (WIDTH - (right - left)) / 2 - left
    y = (HEIGHT - (bottom - top)) / 2 - top
    draw.text((x, y), TEXT, font=font, fill=FILL, stroke_width=STROKE, stroke_fill=OUTLINE)
    image.save(os.path.normpath(out))
    print(os.path.normpath(out), "size", size, "text", right - left, "x", bottom - top)

if __name__ == "__main__":
    main()
