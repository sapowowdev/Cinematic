"""Art for Cinematic's low-health edges (LowHealth.lua, themes in
LowHealthThemes.lua). All of it white or grey, tinted in the game by each
theme's colours, so one texture serves several themes.

Edge materials (Textures/LowHealth/<Name>.tga, stretched over the whole
screen): clear in the middle, the material past a ragged line round the
edges. LowHealth.lua grows them past the screen edges so they creep in as
they shrink back. Most also have <Name>Glow.tga, drawn additively (light
through cracks, a fire's ember rim, a glow), tinted on its own.
  Soak   blood or water soaking in (a wet rim)
  Crack  a battered plate (steel, stone, glass) cracked from the edge
  Frost  frost crystals growing in
  Smoke  billowing smoke or cloud
  Flame  flames licking in from a charred edge
  Glow   no body: a soft glow round the edges
  Vines  thorny tendrils reaching in (veins, briars, roots)
  Runes  a dark band of glowing runes
  Fur    a thick pelt, its strands pointing in
  Scales a dragon's scales in rows, their rims glowing
  Leaves a thick border of leaves
  Wind   streaks sweeping along the edges
  SunMoon  sunlight streaming in from the left (the body), a crescent moon's
         cold light on the right (the glow): tinted gold and silver
Sprites: Effects.tga, 8x4 cells of 128 (see CELLS below). Vitals Vision no
longer shows them; make_wind_guide.py copies them for the Wind Guide, and the
release leaves the file out (.pkgmeta). Bolt.tga (256 square), Star.tga
(128) and Mote.tga (64): the few it still shows, each on its own; Gas.tga
(256): a soft wisp, for gas.
Our own, made from scratch here; usage: make_lowhealth.py (from the addon folder)"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join("Textures", "LowHealth")
os.makedirs(OUT, exist_ok=True)


def grid(w, h):
    x = np.linspace(-1, 1, w)[None, :].repeat(h, 0)
    y = np.linspace(-1, 1, h)[:, None].repeat(w, 1)
    return x, y


def value_noise(x, y, cells_x, cells_y, seed):
    """Smooth noise: random values on a grid, eased between."""
    g = np.random.default_rng(seed).random((cells_y + 2, cells_x + 2))
    gx = (x + 1) / 2 * cells_x
    gy = (y + 1) / 2 * cells_y
    ix, iy = np.clip(gx.astype(int), 0, cells_x), np.clip(gy.astype(int), 0, cells_y)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = g[iy, ix], g[iy, ix + 1]
    c, d = g[iy + 1, ix], g[iy + 1, ix + 1]
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def fbm(x, y, base, octaves, seed):
    total, amp, norm = 0, 1.0, 0
    for o in range(octaves):
        cells = base * 2 ** o
        total = total + value_noise(x, y, cells, cells // 2 + 1, seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rounded(x, y):
    """1 at the middle of each edge, more in the corners (a rounded box)."""
    return (np.abs(x) ** 4 + np.abs(y) ** 4) ** 0.25


def save(name, grey, alpha, levels=None):
    """levels: steps to round grey and alpha to (fewer: smaller files, as the
    run-length packing finds longer runs; too few would band)."""
    grey = np.clip(grey, 0, 1)
    alpha = np.clip(alpha, 0, 1)
    if levels:
        grey = np.round(grey * levels) / levels
        alpha = np.round(alpha * levels) / levels
    rgba = np.stack([grey, grey, grey, np.clip(alpha, 0, 1)], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(OUT, name + ".tga"), compression="tga_rle")


def mask_from(image):
    return np.asarray(image, dtype=np.float64) / 255


def edge_points(count, rng, at=0.84, jitter=0.0):
    """Points round the rounded box's line (x, y in -1..1), evenly by angle."""
    points = []
    for i in range(count):
        a = (i + rng.uniform(0, 1)) / count * 2 * math.pi
        px, py = math.cos(a), math.sin(a)
        s = (at + rng.uniform(-jitter, jitter)) / (abs(px) ** 4 + abs(py) ** 4) ** 0.25
        points.append((px * s, py * s))
    return points


def to_pixels(px, py, w, h):
    return (px + 1) / 2 * (w - 1), (py + 1) / 2 * (h - 1)


def inward(px, py):
    """A unit direction from an edge point toward the middle (in pixels' shape)."""
    d = math.hypot(px * 2, py)
    return -px * 2 / d, -py / d


def along_and_depth(x, y, line):
    """Coordinates that follow the edge: along it (0-1 round the screen) and
    how far past the line (in its units)."""
    along = (np.arctan2(y, x * 2) / (2 * math.pi) + 0.5)
    return along, rounded(x, y) - line


# --- Soak: blood (or water) soaking in, as the first blood edge --------------
def soak():
    w, h = 1024, 512
    x, y = grid(w, h)
    r = rounded(x, y)
    line = 0.8 + (fbm(x, y, 4, 6, 1) - 0.5) * 0.34
    inside = r - line
    body = smoothstep(-0.004, 0.012, inside)
    depth = np.clip(inside / 0.25, 0, 1)
    mottle = fbm(x, y, 24, 3, 40)
    grey = (0.55 - 0.32 * depth + (mottle - 0.5) * 0.18)
    rim = smoothstep(0.03, 0.0, np.abs(inside - 0.008)) * body
    grey = (grey + rim * 0.22) / 0.85
    alpha = body * (0.55 + 0.4 * depth ** 0.6)
    save("Soak", grey, alpha, 32)
    save("SoakGlow", np.ones_like(x), rim * 0.7)


# --- Crack: a battered plate, cracked in from its edge ------------------------
def cracks(w, h, rng, count, reach, start_at):
    """Cracks as a mask: jagged lines from the line inward, branching."""
    image = Image.new("L", (w * 2, h * 2), 0)
    draw = ImageDraw.Draw(image)

    def crack(px, py, dx, dy, length, width, depth):
        steps = max(2, int(length / 0.03))
        for _ in range(steps):
            angle = math.atan2(dy, dx) + rng.normal(0, 0.45)
            dx, dy = math.cos(angle), math.sin(angle)
            nx, ny = px + dx * 0.03 / 2, py + dy * 0.03
            a, b = to_pixels(px, py, w * 2, h * 2)
            c, d = to_pixels(nx, ny, w * 2, h * 2)
            draw.line((a, b, c, d), fill=255, width=max(1, int(width)))
            px, py = nx, ny
            width *= 0.93
            if depth < 2 and rng.random() < 0.18:
                side = rng.choice([-1, 1]) * rng.uniform(0.5, 1.1)
                bx, by = math.cos(angle + side), math.sin(angle + side)
                crack(px, py, bx, by, length * 0.45, width * 0.8, depth + 1)

    for px, py in edge_points(count, rng, start_at, 0.03):
        dx, dy = inward(px, py)
        crack(px, py, dx, dy, rng.uniform(reach * 0.4, reach), rng.uniform(3, 7), 0)
    image = image.resize((w, h), Image.LANCZOS)
    return mask_from(image)


def crack_plate():
    w, h = 1024, 512
    rng = np.random.default_rng(3)
    x, y = grid(w, h)
    r = rounded(x, y)
    line = 0.86 + (fbm(x, y, 6, 5, 5) - 0.5) * 0.12
    inside = r - line
    plate = smoothstep(-0.006, 0.006, inside)
    lines = cracks(w, h, rng, 34, 0.3, 0.86)
    texture = fbm(x, y, 32, 3, 9)
    grey = 0.45 + (texture - 0.5) * 0.35 + 0.2 * smoothstep(0.02, 0.0, np.abs(inside - 0.01))
    grey = grey * (1 - 0.75 * lines)
    alpha = np.maximum(plate * 0.92, lines * 0.85)
    save("Crack", grey, alpha, 32)
    glow = np.asarray(Image.fromarray((lines * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(3)), dtype=np.float64) / 255
    save("CrackGlow", np.ones_like(x), np.clip(lines * 0.9 + glow * 1.4, 0, 1))


# --- Frost: crystals growing in from the edge ---------------------------------
def frost():
    w, h = 1024, 512
    rng = np.random.default_rng(21)
    x, y = grid(w, h)
    r = rounded(x, y)
    line = 0.88 + (fbm(x, y, 5, 5, 23) - 0.5) * 0.16
    inside = r - line
    band = smoothstep(-0.03, 0.05, inside)
    image = Image.new("L", (w * 2, h * 2), 0)
    draw = ImageDraw.Draw(image)

    def branch(px, py, angle, length, width, depth):
        nx = px + math.cos(angle) * length / 2
        ny = py + math.sin(angle) * length
        a, b = to_pixels(px, py, w * 2, h * 2)
        c, d = to_pixels(nx, ny, w * 2, h * 2)
        draw.line((a, b, c, d), fill=255, width=max(1, int(width)))
        if depth >= 3:
            return
        for k in range(1, 4):  # side shoots at 60 degrees, as ice grows
            t = k / 4
            sx, sy = px + (nx - px) * t, py + (ny - py) * t
            for side in (-1, 1):
                if rng.random() < 0.7:
                    branch(sx, sy, angle + side * math.pi / 3, length * (0.45 - 0.08 * k),
                           width * 0.7, depth + 1)

    for px, py in edge_points(40, rng, 0.9, 0.04):
        dx, dy = inward(px, py)
        branch(px, py, math.atan2(dy, dx) + rng.normal(0, 0.25), rng.uniform(0.12, 0.3),
               rng.uniform(3, 6), 0)
    crystals = mask_from(image.resize((w, h), Image.LANCZOS))
    rime = fbm(x, y, 40, 3, 25)
    grey = 0.78 + (rime - 0.5) * 0.3 + crystals * 0.2
    alpha = np.maximum(band * (0.55 + 0.35 * rime), crystals * 0.9)
    save("Frost", grey, alpha, 32)
    soft = mask_from(Image.fromarray((crystals * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)))
    save("FrostGlow", np.ones_like(x), np.clip(soft * 1.2, 0, 1) * 0.6)


# --- Smoke: billowing in from the edges ---------------------------------------
def smoke():
    w, h = 512, 256  # (soft: half size is plenty)
    x, y = grid(w, h)
    warp_x = fbm(x, y, 3, 4, 31) - 0.5
    warp_y = fbm(x, y, 3, 4, 37) - 0.5
    wx, wy = np.clip(x + warp_x * 0.4, -1, 1), np.clip(y + warp_y * 0.4, -1, 1)
    billow = fbm(wx, wy, 5, 6, 41)
    r = rounded(x, y)
    line = 0.66 + (billow - 0.5) * 0.5
    inside = r - line
    body = smoothstep(-0.05, 0.12, inside)
    puffs = fbm(wx, wy, 12, 4, 43)
    grey = 0.35 + (puffs - 0.5) * 0.6
    alpha = body * (0.55 + 0.45 * puffs) * smoothstep(-0.05, 0.25, inside) ** 0.5
    save("Smoke", grey, alpha, 32)


# --- Flame: flames licking in from a charred edge -----------------------------
def flame():
    w, h = 1024, 512
    x, y = grid(w, h)
    r = rounded(x, y)
    angle = np.arctan2(y, x * 2)
    # (tongues: noise run along the edge, sharpened into peaks)
    along = (angle / math.pi + 1) / 2
    tongue = np.zeros_like(x)
    for k, (freq, amp) in enumerate([(24, 0.55), (51, 0.3), (97, 0.15)]):
        phase = np.random.default_rng(50 + k).uniform(0, 6.28)
        tongue = tongue + amp * (0.5 + 0.5 * np.sin(along * freq * 2 * math.pi + phase
                                                     + 2 * fbm(x, y, 6, 3, 60 + k)))
    # (taller here, lower there, so they don't come round evenly like teeth)
    tongue = tongue ** 2.2 * (0.35 + 0.9 * fbm(x, y, 3, 3, 65))
    line = 0.9 - tongue * 0.17 - (fbm(x, y, 8, 4, 66) - 0.5) * 0.08
    inside = r - line
    body = smoothstep(-0.004, 0.01, inside)
    char = fbm(x, y, 30, 3, 70)
    depth = np.clip(inside / 0.2, 0, 1)
    grey = 0.12 + (char - 0.5) * 0.12 + 0.12 * (1 - depth)
    alpha = body * (0.75 + 0.25 * depth)
    save("Flame", grey, alpha, 32)
    ember = smoothstep(0.05, 0.0, inside) * smoothstep(-0.05, 0.0, inside)
    ember = np.maximum(ember, body * smoothstep(0.08, 0.0, inside) * (0.4 + 0.6 * char))
    save("FlameGlow", np.ones_like(x), np.clip(ember * 1.1, 0, 1))


# --- Glow: no body, a soft glow round the edges -------------------------------
def glow():
    w, h = 512, 256
    x, y = grid(w, h)
    r = rounded(x, y)
    shimmer = fbm(x, y, 6, 4, 80)
    alpha = smoothstep(0.5, 1.08, r + (shimmer - 0.5) * 0.12) ** 1.6
    save("GlowGlow", np.ones_like(x), alpha * 0.95)


# --- Fur: a thick pelt, its strands pointing in -------------------------------
def fur():
    w, h = 1024, 512
    rng = np.random.default_rng(121)
    x, y = grid(w, h)
    line = 0.86 + (fbm(x, y, 6, 4, 123) - 0.5) * 0.12
    base = smoothstep(0.0, 0.06, rounded(x, y) - line)
    image = Image.new("L", (w * 2, h * 2), 0)
    draw = ImageDraw.Draw(image)
    for px, py in edge_points(2600, rng, 0.9, 0.06):
        dx, dy = inward(px, py)
        angle = math.atan2(dy, dx) + rng.normal(0, 0.35)
        length = rng.uniform(0.02, 0.07)
        a, b = to_pixels(px, py, w * 2, h * 2)
        c, d = to_pixels(px + math.cos(angle) * length / 2, py + math.sin(angle) * length, w * 2, h * 2)
        draw.line((a, b, c, d), fill=int(rng.uniform(120, 255)), width=int(rng.uniform(2, 5)))
    strands = mask_from(image.resize((w, h), Image.LANCZOS))
    grey = 0.3 + 0.5 * strands + (fbm(x, y, 20, 3, 125) - 0.5) * 0.2
    alpha = np.maximum(base * 0.9, np.clip(strands * 1.4, 0, 1) * 0.9)
    save("Fur", grey, alpha, 32)


# --- Scales: a dragon's scales in rows round the edge, their rims glowing -----
def scales():
    w, h = 1024, 512
    x, y = grid(w, h)
    line = 0.84 + (fbm(x, y, 5, 4, 131) - 0.5) * 0.08
    along, depth = along_and_depth(x, y, line)
    rows = depth / 0.06
    row = np.floor(rows)
    across = along * 110 + (row % 2) * 0.5
    u, v = across - np.floor(across) - 0.5, rows - row
    # (each scale a round-bottomed shape pointing in; the next row overlaps it)
    d = np.hypot(u * 1.3, v - 0.15)
    scale = smoothstep(0.62, 0.55, d) * (depth > -0.01)
    rim = smoothstep(0.08, 0.0, np.abs(d - 0.52)) * (depth > -0.01)
    shade = 0.35 + 0.45 * (1 - v) * scale + (fbm(x, y, 30, 3, 133) - 0.5) * 0.15
    alpha = np.maximum(scale, rim) * smoothstep(-0.01, 0.01, depth)
    save("Scales", shade, alpha * 0.95, 32)
    save("ScalesGlow", np.ones_like(x), rim * smoothstep(-0.01, 0.01, depth) * 0.8)


# --- Leaves: a thick border of leaves, thinning toward the line ---------------
def leaf_shape(draw, cx, cy, size, angle, fill):
    points = []
    for j in range(24):
        t = j / 23
        side = math.sin(t * math.pi) * size * 0.45
        points.append((t * size, side))
    for j in range(24):
        t = 1 - j / 23
        points.append((t * size, -math.sin(t * math.pi) * size * 0.45))
    ca, sa = math.cos(angle), math.sin(angle)
    draw.polygon([(cx + px * ca - py * sa, cy + px * sa + py * ca) for px, py in points], fill=fill)


def leaves():
    w, h = 1024, 512
    rng = np.random.default_rng(141)
    x, y = grid(w, h)
    image = Image.new("L", (w * 2, h * 2), 0)
    shade = Image.new("L", (w * 2, h * 2), 0)
    draw, shade_draw = ImageDraw.Draw(image), ImageDraw.Draw(shade)
    # (furthest out first, so the ones further in lie on top)
    for at in (1.02, 0.98, 0.94, 0.9, 0.87):
        for px, py in edge_points(int(170 * (1.1 - (1.02 - at) * 3)), rng, at, 0.03):
            a, b = to_pixels(px, py, w * 2, h * 2)
            dx, dy = inward(px, py)
            angle = math.atan2(dy, dx) + rng.normal(0, 0.7)
            size = rng.uniform(40, 80)
            leaf_shape(draw, a, b, size, angle, 255)
            leaf_shape(shade_draw, a, b, size, angle, int(rng.uniform(90, 255)))
    cover = mask_from(image.resize((w, h), Image.LANCZOS))
    tone = mask_from(shade.resize((w, h), Image.LANCZOS))
    grey = 0.35 + 0.55 * tone + (fbm(x, y, 40, 2, 143) - 0.5) * 0.1
    save("Leaves", grey, cover * 0.95, 32)


# --- Wind: streaks sweeping along the edges ------------------------------------
def wind():
    w, h = 1024, 512
    x, y = grid(w, h)
    line = 0.8 + (fbm(x, y, 4, 4, 151) - 0.5) * 0.2
    along, depth = along_and_depth(x, y, line)
    # (noise stretched along the edge: long thin streaks)
    streaks = np.zeros_like(x)
    for k, (cells_along, cells_deep, amp) in enumerate([(8, 60, 0.6), (16, 120, 0.3), (32, 220, 0.15)]):
        g = np.random.default_rng(155 + k).random((cells_deep + 2, cells_along + 2))
        ga, gd = along * cells_along, np.clip(depth + 0.3, 0, 0.6) / 0.6 * cells_deep
        ia, idp = ga.astype(int) % cells_along, np.clip(gd.astype(int), 0, cells_deep)
        fa, fd = ga - np.floor(ga), gd - np.floor(gd)
        fa, fd = fa * fa * (3 - 2 * fa), fd * fd * (3 - 2 * fd)
        nxt = (ia + 1) % cells_along  # (round the screen and back: no seam)
        a, b = g[idp, ia], g[idp, nxt]
        c, d = g[idp + 1, ia], g[idp + 1, nxt]
        streaks = streaks + amp * ((a + (b - a) * fa) * (1 - fd) + (c + (d - c) * fa) * fd)
    streaks = smoothstep(0.58, 0.9, streaks / 1.05)  # (sparse: gusts, with gaps)
    body = smoothstep(-0.08, 0.1, depth)
    alpha = body * (0.12 + 0.7 * streaks)
    save("Wind", 0.75 + 0.25 * streaks, alpha, 32)
    save("WindGlow", np.ones_like(x), body * streaks * 0.7)


# --- Sun and moon: sunlight streaming in from the left, moonlight on the right
def sun_moon():
    w, h = 1024, 512
    x, y = grid(w, h)
    r = rounded(x, y)
    edge = smoothstep(0.55, 1.05, r)
    # The sun: rays from just off the left edge, warm, strongest top left.
    sx, sy = -1.15, -0.45
    angle = np.arctan2(y - sy, (x - sx) * 2)
    rays = 0.55 + 0.45 * np.sin(angle * 26 + 3 * fbm(x, y, 4, 3, 161))
    near_sun = np.clip(1 - np.hypot((x - sx) * 2, y - sy) / 2.6, 0, 1)
    sun = np.clip(edge ** 1.5 * rays * near_sun ** 1.2 * 1.3 + np.exp(-np.hypot((x - sx) * 2, y - sy) / 0.3), 0, 1)
    left = smoothstep(0.35, -0.2, x)
    save("SunMoon", np.ones_like(x), sun * left * 0.65, 32)
    # The moon: a crescent top right, its cold light round the right side.
    mx, my, radius = 0.78, -0.55, 0.16
    d = np.hypot((x - mx) * 2, y - my)
    bite = np.hypot((x - mx - 0.04) * 2, y - my + 0.07)
    crescent = smoothstep(radius, radius - 0.01, d) * smoothstep(radius * 0.9, radius * 0.96, bite)
    halo = np.exp(-np.maximum(0, d - radius) / 0.06) * 0.35 * (d > radius)
    right = smoothstep(-0.35, 0.2, x)
    moon = np.clip(crescent + halo + edge ** 1.8 * right * 0.4, 0, 1)
    save("SunMoonGlow", np.ones_like(x), moon)


# --- Vines: tendrils reaching in (veins, briars, roots) -----------------------
def vines():
    w, h = 1024, 512
    rng = np.random.default_rng(101)
    x, y = grid(w, h)
    r = rounded(x, y)
    line = 0.9 + (fbm(x, y, 5, 5, 103) - 0.5) * 0.12
    base = smoothstep(-0.02, 0.06, r - line)
    image = Image.new("L", (w * 2, h * 2), 0)
    draw = ImageDraw.Draw(image)

    def tendril(px, py, angle, length, width, depth):
        steps = max(3, int(length / 0.02))
        bend = rng.normal(0, 0.12)
        for i in range(steps):
            angle += bend + rng.normal(0, 0.12)
            nx = px + math.cos(angle) * 0.02 / 2
            ny = py + math.sin(angle) * 0.02
            a, b = to_pixels(px, py, w * 2, h * 2)
            c, d = to_pixels(nx, ny, w * 2, h * 2)
            draw.line((a, b, c, d), fill=255, width=max(1, int(width)))
            # thorns, now and then, pointing back the way it came
            if width > 3 and rng.random() < 0.12:
                side = rng.choice([-1, 1])
                ta = angle + side * 1.9
                tx, ty = c + math.cos(ta) * width * 3, d + math.sin(ta) * width * 3 * 2 / 2
                draw.polygon([(c - math.sin(angle) * width * 0.6, d + math.cos(angle) * width * 0.6),
                              (c + math.sin(angle) * width * 0.6, d - math.cos(angle) * width * 0.6),
                              (tx, ty)], fill=255)
            px, py = nx, ny
            width *= 0.96
            if depth < 2 and rng.random() < 0.06:
                tendril(px, py, angle + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0),
                        length * (1 - i / steps) * 0.6, width * 0.75, depth + 1)

    for px, py in edge_points(34, rng, 0.92, 0.03):
        dx, dy = inward(px, py)
        tendril(px, py, math.atan2(dy, dx) + rng.normal(0, 0.3), rng.uniform(0.15, 0.42),
                rng.uniform(10, 18), 0)
    lines = mask_from(image.resize((w, h), Image.LANCZOS))
    bark = fbm(x, y, 48, 3, 107)
    grey = 0.35 + (bark - 0.5) * 0.4 + 0.15 * lines
    alpha = np.maximum(base * 0.85, lines * 0.95)
    save("Vines", grey, alpha, 32)
    soft = mask_from(Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)))
    save("VinesGlow", np.ones_like(x), np.clip(soft * 1.3, 0, 1) * 0.7)


# --- Runes: a dark band of glowing runes ---------------------------------------
def glyph(draw, cx, cy, size, rng, width):
    """A made-up rune: a few strokes between points of a 3x3 grid."""
    points = [(cx + (i % 3 - 1) * size, cy + (i // 3 - 1) * size * 1.4) for i in range(9)]
    start = rng.integers(0, 9)
    for _ in range(rng.integers(3, 6)):
        end = rng.integers(0, 9)
        if end != start:
            draw.line((points[start], points[end]), fill=255, width=width)
        start = end


def runes():
    w, h = 1024, 512
    rng = np.random.default_rng(111)
    x, y = grid(w, h)
    r = rounded(x, y)
    band = smoothstep(0.8, 0.9, r)
    image = Image.new("L", (w * 2, h * 2), 0)
    draw = ImageDraw.Draw(image)
    for px, py in edge_points(38, rng, 0.87, 0.0):
        a, b = to_pixels(px, py, w * 2, h * 2)
        glyph(draw, a, b, 18, rng, 7)
    marks = mask_from(image.resize((w, h), Image.LANCZOS))
    grey = 0.15 + 0.1 * fbm(x, y, 20, 3, 113)
    save("Runes", grey, band * 0.75, 32)
    soft = mask_from(Image.fromarray((marks * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)))
    save("RunesGlow", np.ones_like(x), np.clip(marks + soft * 1.2, 0, 1))


# --- Sprites ------------------------------------------------------------------
CELL, BIG = 128, 512  # (drawn at BIG and shrunk, for smooth edges)
CELLS = ["Splat1", "Splat2", "Splat3", "Splat4", "Slash", "Claw", "CrackBurst", "Ember",
         "Mote", "Feather", "Leaf", "Puff", "Shard", "Rain", "Bolt", "Ripple",
         "Rune1", "Rune2", "Rune3", "Eye", "Star", "Dust", "Bruise", "Spark",
         "Bubble", "Petal", "Wind", "Sand", "Paw", "WolfEyes", "Leaf2"]


def cell_image():
    return Image.new("L", (BIG, BIG), 0)


def soft_cell(radius_share, power=1.5):
    yy, xx = np.mgrid[0:BIG, 0:BIG].astype(float)
    d = np.hypot(xx - BIG / 2, yy - BIG / 2) / (BIG / 2 * radius_share)
    return np.clip(1 - d, 0, 1) ** power


def sprites():
    rng = np.random.default_rng(201)
    cells = {}
    yy, xx = np.mgrid[0:BIG, 0:BIG].astype(float)
    c = BIG / 2
    # Splats: lumpy blots with specks round them.
    for k in range(4):
        angle = np.arctan2(yy - c, xx - c)
        lumps = 1 + 0.12 * np.sin(angle * rng.integers(3, 7) + rng.uniform(0, 6)) \
            + 0.06 * np.sin(angle * rng.integers(7, 12))
        d = np.hypot(xx - c, yy - c) / (BIG * 0.22) / lumps
        blot = smoothstep(1.0, 0.85, d)
        for _ in range(rng.integers(3, 7)):
            a = rng.uniform(0, 2 * np.pi)
            dist = rng.uniform(0.3, 0.44) * BIG
            sx, sy = c + np.cos(a) * dist, c + np.sin(a) * dist
            size = rng.uniform(0.02, 0.05) * BIG
            blot = np.maximum(blot, smoothstep(size, size * 0.6, np.hypot(xx - sx, yy - sy)))
        cells["Splat%d" % (k + 1)] = blot
    # Slash: one long cut, corner to corner, thick in the middle.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    for i in range(60):
        t = i / 59
        width = 4 + 40 * math.sin(t * math.pi) ** 0.8
        px, py = 30 + t * (BIG - 60), BIG - 30 - t * (BIG - 60) + math.sin(t * 9) * 4
        draw.ellipse((px - width / 2, py - width / 2, px + width / 2, py + width / 2), fill=255)
    cells["Slash"] = mask_from(image)
    # Claw: three cuts side by side.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    for k in (-1, 0, 1):
        for i in range(50):
            t = i / 49
            width = 3 + 22 * math.sin(t * math.pi) ** 0.8
            px = 60 + t * (BIG - 160) + k * 70
            py = BIG - 60 - t * (BIG - 120) + k * 40
            draw.ellipse((px - width / 2, py - width / 2, px + width / 2, py + width / 2), fill=255)
    cells["Claw"] = mask_from(image)
    # Crack burst: cracks out from a point.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    for k in range(7):
        angle = k / 7 * 2 * math.pi + rng.uniform(-0.3, 0.3)
        px, py, width = c, c, 12
        for _ in range(12):
            angle += rng.normal(0, 0.35)
            nx, ny = px + math.cos(angle) * 18, py + math.sin(angle) * 18
            draw.line((px, py, nx, ny), fill=255, width=int(width))
            px, py, width = nx, ny, max(2, width * 0.85)
    cells["CrackBurst"] = mask_from(image)
    # Ember: a hot core with a glow.
    cells["Ember"] = np.clip(soft_cell(0.25, 1.2) + soft_cell(0.9, 3) * 0.6, 0, 1)
    cells["Mote"] = soft_cell(0.8, 2.2)
    # Feather: a quill with soft barbs.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    for i in range(80):
        t = i / 79
        py = 60 + t * (BIG - 120)
        span = 110 * math.sin(t * math.pi) ** 0.7
        draw.line((c, py, c - span, py - 50), fill=180, width=5)
        draw.line((c, py, c + span * 0.8, py - 45), fill=180, width=5)
    draw.line((c, 40, c, BIG - 40), fill=255, width=8)
    cells["Feather"] = mask_from(image.filter(ImageFilter.GaussianBlur(3)))
    # Leaf: a pointed oval with a midrib.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    outline = [(c + 150 * math.sin(t * math.pi) * (1 if i < 50 else -1), 50 + t * (BIG - 100))
               for i, t in enumerate([j / 49 for j in range(50)] + [1 - j / 49 for j in range(50)])]
    draw.polygon(outline, fill=230)
    draw.line((c, 50, c, BIG - 30), fill=120, width=8)
    cells["Leaf"] = mask_from(image)
    # Puff: a soft lumpy cloud.
    puff = np.zeros((BIG, BIG))
    for _ in range(7):
        ox, oy = rng.normal(0, 0.12) * BIG, rng.normal(0, 0.08) * BIG
        rad = rng.uniform(0.18, 0.3) * BIG
        puff = np.maximum(puff, np.clip(1 - np.hypot(xx - c - ox, yy - c - oy) / rad, 0, 1) ** 1.3)
    cells["Puff"] = puff * 0.8
    # Shard: a sharp splinter of glass or ice.
    image = cell_image()
    ImageDraw.Draw(image).polygon([(c - 40, 40), (c + 70, 120), (c + 20, BIG - 30), (c - 60, 200)], fill=230)
    cells["Shard"] = mask_from(image)
    # Rain: a thin streak.
    rain = smoothstep(10, 3, np.abs(xx - c)) * smoothstep(0, 120, yy) * smoothstep(BIG, BIG - 60, yy)
    cells["Rain"] = rain * 0.8
    # Bolt: lightning, jagged, top to bottom.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    px, py = c, 0
    while py < BIG:
        nx, ny = px + rng.uniform(-60, 60), py + rng.uniform(30, 60)
        draw.line((px, py, nx, ny), fill=255, width=10)
        if rng.random() < 0.3:
            draw.line((nx, ny, nx + rng.uniform(-90, 90), ny + rng.uniform(40, 90)), fill=200, width=5)
        px, py = nx, ny
    bolt = mask_from(image)
    cells["Bolt"] = np.clip(bolt + mask_from(image.filter(ImageFilter.GaussianBlur(14))) * 1.5, 0, 1)
    # Ripple: a ring.
    d = np.hypot(xx - c, yy - c) / (BIG / 2)
    cells["Ripple"] = np.exp(-((d - 0.8) / 0.05) ** 2) + 0.4 * np.exp(-((d - 0.6) / 0.04) ** 2)
    # Runes: three made-up glyphs, with a glow.
    for k in range(3):
        image = cell_image()
        glyph(ImageDraw.Draw(image), c, c, 95, rng, 22)
        sharp = mask_from(image)
        cells["Rune%d" % (k + 1)] = np.clip(sharp + mask_from(image.filter(ImageFilter.GaussianBlur(18))), 0, 1)
    # Eye: an almond with a slit pupil (dark), glowing round it.
    eye = smoothstep(1.0, 0.9, np.hypot((xx - c) / 200, (yy - c) / 90))
    pupil = smoothstep(1.0, 0.8, np.hypot((xx - c) / 20, (yy - c) / 80))
    cells["Eye"] = np.clip(eye * (1 - pupil * 0.85) + soft_cell(0.95, 3) * 0.4, 0, 1)
    # Star: a four-point sparkle.
    star = np.maximum(np.exp(-np.abs(xx - c) / 10) * np.exp(-np.abs(yy - c) / 120),
                      np.exp(-np.abs(yy - c) / 10) * np.exp(-np.abs(xx - c) / 120))
    cells["Star"] = np.clip(star * 1.3 + soft_cell(0.3, 2), 0, 1)
    # Dust: a scatter of specks.
    dust = np.zeros((BIG, BIG))
    for _ in range(26):
        sx, sy = rng.normal(c, 90), rng.normal(c, 90)
        size = rng.uniform(4, 12)
        dust = np.maximum(dust, smoothstep(size, size * 0.4, np.hypot(xx - sx, yy - sy)))
    cells["Dust"] = dust * 0.85
    # Bruise: a soft blotch.
    cells["Bruise"] = soft_cell(0.85, 0.8) * (0.7 + 0.3 * value_noise(
        xx / BIG * 2 - 1, yy / BIG * 2 - 1, 6, 6, 205))
    # Spark: a short bright streak, flying.
    spark = smoothstep(9, 2, np.abs(yy - c)) * smoothstep(c - 150, c + 60, xx) * smoothstep(c + 150, c + 60, xx)
    cells["Spark"] = np.clip(spark + soft_cell(0.2, 2), 0, 1)
    # Bubble: a thin round skin with a highlight.
    d = np.hypot(xx - c, yy - c) / (BIG * 0.4)
    cells["Bubble"] = np.clip(smoothstep(0.75, 1.0, d) * smoothstep(1.05, 1.0, d) * 0.9 + 0.15 * (d < 1)
                              + soft_cell(0.15, 2) * 0, 0, 1) \
        + np.clip(1 - np.hypot(xx - c + BIG * 0.15, yy - c + BIG * 0.15) / (BIG * 0.08), 0, 1) * 0.8
    # Petal: a soft teardrop.
    image = cell_image()
    ImageDraw.Draw(image).polygon([(c + 120 * math.sin(t * math.pi) ** 0.7 * (1 if i < 40 else -1),
                                    80 + t * (BIG - 160))
                                   for i, t in enumerate([j / 39 for j in range(40)] + [1 - j / 39 for j in range(40)])],
                                  fill=230)
    cells["Petal"] = mask_from(image.filter(ImageFilter.GaussianBlur(6)))
    # Wind: a long thin streak, curling up at its head.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    for k, offset in enumerate((-40, 0, 40)):
        points = [(20 + t * (BIG - 140), c + offset + math.sin(t * 3 + k) * 12) for t in [j / 30 for j in range(31)]]
        for j in range(len(points) - 1):
            draw.line((points[j], points[j + 1]), fill=int(120 + 135 * j / 30), width=max(2, int(2 + 8 * j / 30)))
    cells["Wind"] = mask_from(image.filter(ImageFilter.GaussianBlur(3)))
    # Sand: a falling stream of grains.
    sand = np.zeros((BIG, BIG))
    for _ in range(160):
        sx, sy = rng.normal(c, 14 + rng.uniform(0, 30)), rng.uniform(0, BIG)
        sand = np.maximum(sand, smoothstep(5, 2, np.hypot(xx - sx, yy - sy)))
    cells["Sand"] = sand
    # Paw: a wolf's print (a pad and four toes).
    paw = smoothstep(1.0, 0.85, np.hypot((xx - c) / 95, (yy - c - 70) / 80))
    for tx, ty in ((-110, -40), (-40, -110), (40, -110), (110, -40)):
        paw = np.maximum(paw, smoothstep(1.0, 0.85, np.hypot((xx - c - tx) / 42, (yy - c - ty) / 55)))
    cells["Paw"] = paw
    # Wolf eyes: two glowing eyes, slanted, in the dark.
    eyes = np.zeros((BIG, BIG))
    for side in (-1, 1):
        ex = c + side * 95
        eye = smoothstep(1.0, 0.75, np.hypot((xx - ex) / 55, (yy - c - side * 0 + (xx - ex) * side * 0.25) / 24))
        eyes = np.maximum(eyes, np.clip(eye + np.clip(1 - np.hypot(xx - ex, yy - c) / 110, 0, 1) ** 2 * 0.5, 0, 1))
    cells["WolfEyes"] = eyes
    # Leaf2: a broader leaf, lobed, with veins.
    image = cell_image()
    draw = ImageDraw.Draw(image)
    lobes = [(c + math.cos(a) * (150 + 45 * math.cos(a * 5)), c + math.sin(a) * (150 + 45 * math.cos(a * 5)) * 1.1)
             for a in [j / 60 * 2 * math.pi for j in range(60)]]
    draw.polygon(lobes, fill=230)
    for a in (-1.2, -0.6, 0, 0.6, 1.2):
        draw.line((c, BIG - 90, c + math.sin(a) * 160, c - math.cos(a) * 160), fill=140, width=7)
    draw.line((c, BIG - 90, c, BIG - 20), fill=200, width=10)
    cells["Leaf2"] = mask_from(image)

    atlas = np.zeros((CELL * 4, CELL * 8))
    for i, name in enumerate(CELLS):
        small = Image.fromarray((np.clip(cells[name], 0, 1) * 255).astype(np.uint8)).resize(
            (CELL, CELL), Image.LANCZOS)
        row, col = divmod(i, 8)
        atlas[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = mask_from(small)
    save("Effects", np.ones_like(atlas), atlas)
    # The few Vitals Vision still shows, each on its own: the lightning
    # bigger (it's drawn big), the stars and motes small.
    for name, size in (("Bolt", 256), ("Star", 128), ("Mote", 64)):
        alone = Image.fromarray((np.clip(cells[name], 0, 1) * 255).astype(np.uint8)).resize(
            (size, size), Image.LANCZOS)
        save(name, np.ones((size, size)), mask_from(alone))


def gas():
    """Gas.tga (256 square): a soft wisp of gas for Vitals Vision, with no
    hard edges: wispy noise inside a smooth round falloff, so it melts into
    the edges it drifts over."""
    w = 256
    x, y = grid(w, w)
    r = np.hypot(x, y * 1.15)
    # (A wide, flat falloff and a faint body: puffs overlap into a haze
    # rather than each showing as a bright clump.)
    falloff = smoothstep(1.0, 0.0, r) ** 0.8
    wisps = fbm(x * 1.3, y * 1.3, 3, 4, 77)
    wisps = smoothstep(0.25, 0.85, wisps)
    alpha = falloff * (0.45 + 0.55 * wisps) * 0.45
    save("Gas", np.ones_like(x), alpha)


soak()
crack_plate()
frost()
smoke()
flame()
glow()
vines()
runes()
fur()
scales()
leaves()
wind()
sun_moon()
sprites()
gas()
