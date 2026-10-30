"""Builds vitals-demo.html: Vitals Vision running in a web page, from the
addon's own art and LowHealthThemes.lua, and Blizzard art taken from
/cine debug texreel shots screenshots (each texture on black, then on grey:
its colors and its alpha come from the pair). The page runs LowHealth.lua's
drawing in JavaScript: the shadow, our art, Blizzard art's layer and wave, the
heartbeat, flashes, the color grade and sparks.
Usage: python build_demo.py <addon folder> <screenshots folder> <out .html>
(the screenshots: just the 186 of one full texreel shots run, in order)."""
import base64, io, json, os, re, sys
import numpy as np
from PIL import Image
import lupa

ADDON, SHOTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
ART = os.path.join(ADDON, "Textures", "LowHealth")
HERE = os.path.dirname(os.path.abspath(__file__))
PW, PH = 640, 360  # Blizzard art's size here
CROP = 118         # rows of a 1440-high shot under the reel's label box

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
ns = lua.table()
src = open(os.path.join(ADDON, "LowHealthThemes.lua"), encoding="utf-8").read()
lua.eval("function(src, ns) local f = assert(load(src)) f('Cinematic', ns) end")(src, ns)


def py(t):
    if lupa.lua_type(t) != "table":
        return t
    keys = list(t.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [py(t[k]) for k in sorted(keys)]
    return {k: py(v) for k, v in t.items()}


def b64(im, fmt, **kw):
    buf = io.BytesIO()
    im.save(buf, fmt, **kw)
    mime = {"JPEG": "jpeg", "PNG": "png"}[fmt]
    return "data:image/%s;base64,%s" % (mime, base64.b64encode(buf.getvalue()).decode())


def pair(rgb, alpha):
    """A color image and its alpha as two JPEGs (the page joins them)."""
    c = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L")
    return b64(c, "JPEG", quality=82), b64(a, "JPEG", quality=88)


img = {}

# The themes, Blizzard art's patterns and masks, and the menu.
themes = []
for i in range(1, len(ns.LOW_HEALTH_THEMES) + 1):
    t = ns.LOW_HEALTH_THEMES[i]
    d = {k: py(t[k]) for k in ("key", "name", "edge", "body", "glow", "glowAlpha", "shadow", "flash",
                               "pulse", "bpm", "sway", "sparks", "look")}
    if t.theirs:
        d["theirs"] = {"file": t.theirs[1], "own": None if t.theirs.own is None else bool(t.theirs.own)}
    themes.append(d)
patterns = []
for i in range(1, len(ns.LOW_HEALTH_BLIZZ_PATTERNS) + 1):
    p = ns.LOW_HEALTH_BLIZZ_PATTERNS[i]
    patterns.append({"id": p[1], "name": p[2], "mask": p.mask, "own": bool(p.own), "tiles": p.tiles or 1,
                     "paint": bool(p.paint)})
masks = [{"id": m[0], "name": m[1]} for m in py(ns.LOW_HEALTH_BLIZZ_MASKS)]
menu = []
for i in range(1, len(ns.LOW_HEALTH_MENU) + 1):
    e = ns.LOW_HEALTH_MENU[i]
    menu.append({"name": e[2], "specs": [{"spec": e[3][j][1], "key": e[3][j][2]} for j in range(1, len(e[3]) + 1)]})

lh = open(os.path.join(ADDON, "LowHealth.lua"), encoding="utf-8").read()
# The settings' defaults (LowHealth.lua's DEFAULTS.lowHealth... lines): numbers, ticks and words.
defaults = {}
for key, value in re.findall(r"^DEFAULTS\.(lowHealth\w+) = (\S+)", lh, re.M):
    if value in ("true", "false"):
        defaults[key] = value == "true"
    elif value.startswith('"'):
        defaults[key] = value.strip('"')
    else:
        defaults[key] = float(value)

# The screenshots' order: the dev list in LowHealth.lua (EDGE_SCOUT), a pair each.
block = lh[lh.index("local EDGE_SCOUT = {"):lh.index("\n}", lh.index("local EDGE_SCOUT = {"))]
order = [int(x) for x in re.findall(r"\{ (\d+), \"", block)]
shots = sorted(f for f in os.listdir(SHOTS) if f.lower().endswith(".jpg"))
assert len(shots) == 2 * len(order), "need one full texreel shots run: %d shots, %d textures" % (len(shots), len(order))
# (The first few: the files Classic has, for the page's Classic switch.)
classic = order[:8]


def shot(name):
    a = np.asarray(Image.open(os.path.join(SHOTS, name)).convert("RGB"), dtype=np.float32) / 255
    crop = int(CROP * a.shape[0] / 1440)
    a = a.copy()
    a[:crop] = a[crop:2 * crop][::-1]  # (under the label box: the rows below, mirrored)
    return np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((PW, PH), Image.LANCZOS),
                      dtype=np.float32) / 255


for file in sorted({p["id"] for p in patterns} | {m["id"] for m in masks}):
    i = order.index(file)
    black, grey = shot(shots[2 * i]), shot(shots[2 * i + 1])
    alpha = np.clip(1 - (grey - black).mean(axis=2) / 0.5, 0, 1)
    rgb = black / np.maximum(alpha, 1 / 255)[..., None]
    img["p%dc" % file], img["p%da" % file] = pair(rgb, alpha)
    print("blizzard art", file, flush=True)

# Our art: the edges and their glows, and the sparks' sprites.
for name in sorted({t["edge"] for t in themes if t.get("edge")} | {t["edge"] + "Glow" for t in themes if t.get("edge")}):
    path = os.path.join(ART, name + ".tga")
    if not os.path.exists(path):
        continue
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255
    img["o" + name + "c"], img["o" + name + "a"] = pair(a[..., :3], a[..., 3])
for name in ("Mote", "Star", "Bolt", "Gas"):
    img["s" + name] = b64(Image.open(os.path.join(ART, name + ".tga")).convert("RGBA"), "PNG")

# The world behind: the gallery's scene.
W, H = 960, 540
y = np.linspace(0, 1, H)[:, None, None]
sky = np.array([0.42, 0.55, 0.68]) * (1 - y * 0.5) + np.array([0.75, 0.72, 0.62]) * y * 0.5
ground = np.array([0.33, 0.36, 0.22]) * (1.15 - (y - 0.62))
world = np.where(y < 0.62, sky, ground) * np.ones((H, W, 1))
xs = np.linspace(0, 1, W)
hill = 0.58 + 0.04 * np.sin(xs * 7) + 0.02 * np.sin(xs * 19 + 1)
yy = np.linspace(0, 1, H)[:, None]
m = (yy > hill[None, :]) & (yy < 0.62)
world[m] = world[m] * 0.6 + np.array([0.25, 0.32, 0.3]) * 0.4
Y, X = np.mgrid[0:H, 0:W]
cx, cy = W / 2, H * 0.66
world[(((X - cx) / 26) ** 2 + ((Y - cy) / 70) ** 2 < 1) | (((X - cx) ** 2 + (Y - (cy - 85)) ** 2) < 400)] = [0.12, 0.1, 0.1]
img["world"] = b64(Image.fromarray((np.clip(world, 0, 1) * 255).astype(np.uint8)), "JPEG", quality=85)

data = {"themes": themes, "patterns": patterns, "masks": masks, "menu": menu, "classic": classic, "img": img,
        "defaults": defaults, "edge": ns.LOW_HEALTH_BLIZZ_EDGE}
page = open(os.path.join(HERE, "demo_template.html"), encoding="utf-8").read()
page = page.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
with open(OUT, "w", encoding="utf-8") as f:
    f.write(page)
print("done", os.path.getsize(OUT) // 1024, "KB")
