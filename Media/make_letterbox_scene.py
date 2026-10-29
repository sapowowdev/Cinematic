"""Backdrop for the Style hub's Letterbox page's preview (LetterboxStyle.lua):
512x256, a landscape at dusk: a sky from deep blue to a warm glow, a low sun,
thin clouds, ridges of mountains paler with distance, mist between them, a
lake catching the light and dark pines in front. The letterbox bars are drawn
over it, so its top and bottom hold detail too.
Our own, made from scratch here (seeded noise, no source images); usage:
make_letterbox_scene.py Textures/LetterboxScene.tga"""
import sys
import numpy as np
from PIL import Image

W, H = 512, 256
SS = 3  # drawn this many times larger, then shrunk: smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "LetterboxScene.tga"
rng = np.random.default_rng(7)

w, h = W * SS, H * SS
ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
u, v = xs / (w - 1), ys / (h - 1)  # 0-1, v down


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return np.asarray(a, float) * (1 - t) + np.asarray(b, float) * t


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def noise1d(n, octaves, seed):
    """Fractal 1-D noise across the width, -1 to 1."""
    r = np.random.default_rng(seed)
    out = np.zeros(n)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        points = 4 * 2 ** o + 1
        knots = r.uniform(-1, 1, points)
        x = np.linspace(0, points - 1, n)
        i = np.floor(x).astype(int).clip(0, points - 2)
        f = smooth(x - i)
        out += amp * (knots[i] * (1 - f) + knots[i + 1] * f)
        total += amp
        amp *= 0.5
    return out / total


def noise2d(octaves, seed, sx=6, sy=3):
    """Fractal value noise over the picture, 0 to 1."""
    r = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gx, gy = sx * 2 ** o + 2, sy * 2 ** o + 2
        grid = r.uniform(0, 1, (gy, gx))
        x, y = u * (gx - 2), v * (gy - 2)
        ix, iy = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = smooth(x - ix), smooth(y - iy)
        a = grid[iy, ix] * (1 - fx) + grid[iy, ix + 1] * fx
        b = grid[iy + 1, ix] * (1 - fx) + grid[iy + 1, ix + 1] * fx
        out += amp * (a * (1 - fy) + b * fy)
        total += amp
        amp *= 0.5
    return out / total


HORIZON = 0.60
SUN = (0.66, 0.36)

# Sky: deep blue overhead to rose and gold at the horizon, brighter near the sun.
sky = mix((28, 40, 78), (92, 92, 140), smooth(v / 0.35))
sky = mix(sky, (226, 140, 112), smooth((v - 0.25) / 0.35))
sky = mix(sky, (252, 206, 140), smooth((v - 0.45) / 0.15))
dist = np.hypot((u - SUN[0]) * 2.0, (v - SUN[1]) * 1.0)
sky = sky + (np.exp(-dist * 5)[..., None] * np.array([70, 50, 20]))
sky = mix(sky, (255, 246, 220), smooth(1 - dist / 0.035))
# Thin streaks of cloud, lit underneath.
clouds = noise2d(5, 3, sx=3, sy=10)
band = smooth((clouds - 0.55) / 0.2) * smooth(1 - np.abs(v - 0.3) / 0.2)
sky = mix(sky, (250, 170, 150), band * 0.55)
image = sky

# Ridges, far to near: each a silhouette paler and hazier with distance, mist at its foot.
RIDGES = [  # (base height, roughness, colour, seed)
    (0.50, 0.16, (168, 128, 152), 11),
    (0.555, 0.15, (112, 88, 122), 12),
    (0.60, 0.11, (62, 54, 86), 13),
]
for base, rough, colour, seed in RIDGES:
    top = base - rough * (0.5 + 0.5 * noise1d(w, 7, seed)) - rough * 0.4 * np.exp(-((u[0] - rng.uniform(0.2, 0.8)) / 0.12) ** 2)
    edge = smooth((v - top[None, :]) * h / SS)  # one pixel of softness
    shade = mix(colour, np.asarray(colour) * 0.75, smooth((v - top[None, :]) / 0.1))
    image = mix(image, shade, edge)
    mist = smooth(1 - np.abs(v - base - 0.01) / 0.03) * 0.35
    image = mix(image, (232, 176, 160), mist * smooth((v - top[None, :]) / 0.02))

# The lake: the sky turned over, darker, with ripples and the sun's path on it.
lake_top, lake_bottom = HORIZON, 0.80
inlake = (v >= lake_top) & (v < lake_bottom)
rows = np.clip((2 * lake_top - v) * (h - 1), 0, h - 1).astype(int)
ripple = noise2d(4, 21, sx=2, sy=40)
shift = ((ripple - 0.5) * 6 * SS).astype(int)
mirror = image[rows, np.clip(xs.astype(int) + shift, 0, w - 1)] * 0.72
glint = smooth(1 - np.abs(u - SUN[0]) / (0.03 + (v - lake_top) * 0.4)) * smooth((ripple - 0.5) / 0.15)
mirror = mirror + glint[..., None] * np.array([120, 90, 50])
mirror = mirror * (0.92 + 0.16 * ripple)[..., None]
image = np.where(inlake[..., None], mirror, image)

# The near shore and pines, dark against the lake.
shore = 0.78 - 0.03 * noise1d(w, 6, 31) - 0.06 * smooth((u[0] - 0.75) / 0.25)
ground = smooth((v - shore[None, :]) * h / SS)
image = mix(image, mix((34, 30, 44), (14, 14, 22), smooth((v - 0.8) / 0.2)), ground)
trees = np.full(w, 2.0)
r = np.random.default_rng(41)
# A pine's outline: tiers of branches, each wider at its foot, narrowing to
# the top. REACH[i]: how high it reaches at DIST[i] of its half width out.
UP = np.linspace(0, 1, 400)
TIER_WIDTH = (1 - UP) * (0.55 + 0.45 * ((UP * 6) % 1))
DIST = np.linspace(0, 1, 200)
REACH = np.array([UP[TIER_WIDTH >= d].max() if (TIER_WIDTH >= d).any() else 0 for d in DIST])
for _ in range(160):
    cx = r.choice([r.uniform(-0.02, 0.26), r.uniform(0.84, 1.02)])
    base = np.interp(cx, u[0], shore) + 0.02
    edge_near = cx < 0.08 or cx > 0.95
    tall = r.uniform(0.08, 0.2) * (1.6 if edge_near else 1.0)
    half = tall * 0.32 * (h / w)
    reach = np.interp(np.abs(u[0] - cx) / half, DIST, REACH, right=0.0)
    crown = base - tall * reach
    trees = np.minimum(trees, np.where(reach > 0, crown, 2.0))
tree = smooth((v - trees[None, :]) * h / SS)
image = mix(image, (16, 16, 26), tree)

# A soft darkening at the corners, as through a lens.
corner = np.hypot((u - 0.5) * 1.3, (v - 0.5) * 1.1)
image = image * (1 - 0.35 * smooth((corner - 0.35) / 0.4))[..., None]

img = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8), "RGB").resize((W, H), Image.LANCZOS)
img.save(OUT)
