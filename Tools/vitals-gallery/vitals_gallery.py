"""Render a still of every Vitals Vision theme from the addon's own textures
and LowHealthThemes.lua, at the page's default strengths, full low health.
Usage: python vitals_gallery.py <addon folder> <out folder>
(from here: python vitals_gallery.py ../.. out), then build_page.py."""
import base64, io, json, os, random, sys
import numpy as np
from PIL import Image
import lupa

ADDON, OUT = sys.argv[1], sys.argv[2]
ART = os.path.join(ADDON, "Textures", "LowHealth")
W, H = 960, 540

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
ns = lua.table()
src = open(os.path.join(ADDON, "LowHealthThemes.lua"), encoding="utf-8").read()
loader = lua.eval("function(src, ns) local f = assert(load(src)) f('Cinematic', ns) end")
loader(src, ns)


def py(t):
    if lupa.lua_type(t) != "table":
        return t
    keys = list(t.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [py(t[k]) for k in sorted(keys)]
    return {k: py(v) for k, v in t.items()}


themes = py(ns.LOW_HEALTH_THEMES)

# Defaults (LowHealth.lua)
DARK, RED, BLOOD_ALPHA, REACH, BLOOD_REACH = 0.85, 0.6, 0.9, 0.3, 0.7
ART_SCALE = 1.2 + (1 - 1.2) * BLOOD_REACH

_cache = {}


def tex(name):
    if name not in _cache:
        im = Image.open(os.path.join(ART, name + ".tga")).convert("RGBA")
        _cache[name] = im
    return _cache[name]


def arr(im):
    a = np.asarray(im, dtype=np.float32) / 255
    return a[..., :3], a[..., 3:4]


def background():
    y = np.linspace(0, 1, H)[:, None, None]
    sky = np.array([0.42, 0.55, 0.68]) * (1 - y * 0.5) + np.array([0.75, 0.72, 0.62]) * y * 0.5
    ground = np.array([0.33, 0.36, 0.22]) * (1.15 - (y - 0.62))
    img = np.where(y < 0.62, sky, ground) * np.ones((H, W, 1))
    # soft hills
    xs = np.linspace(0, 1, W)
    hill = 0.58 + 0.04 * np.sin(xs * 7) + 0.02 * np.sin(xs * 19 + 1)
    yy = np.linspace(0, 1, H)[:, None]
    mask = (yy > hill[None, :]) & (yy < 0.62)
    img[mask] = img[mask] * 0.6 + np.array([0.25, 0.32, 0.3]) * 0.4
    # a figure in the middle (the player)
    cx, cy = W / 2, H * 0.66
    Y, X = np.mgrid[0:H, 0:W]
    body = ((X - cx) / 26) ** 2 + ((Y - cy) / 70) ** 2 < 1
    head = ((X - cx) ** 2 + (Y - (cy - 85)) ** 2) < 20 ** 2
    img[body | head] = np.array([0.12, 0.1, 0.1])
    return img


BG = background()


def vignette(img, color):
    Y, X = np.mgrid[0:H, 0:W]
    d = np.minimum(np.minimum(X / W, 1 - X / W), np.minimum(Y / H, 1 - Y / H))
    t = np.clip(d / REACH, 0, 1)
    w = (1 - t * t * (3 - 2 * t)) * DARK
    return img * (1 - w[..., None]) + np.array(color) * w[..., None]


def full_art(name):
    im = tex(name).resize((int(W * ART_SCALE), int(H * ART_SCALE)), Image.LANCZOS)
    ox, oy = (im.width - W) // 2, (im.height - H) // 2
    return arr(im.crop((ox, oy, ox + W, oy + H)))


def paste(img, sprite, x, y, color, alpha, add, rot=0):
    if rot:
        sprite = sprite.rotate(rot, resample=Image.BICUBIC, expand=True)
    rgb, a = arr(sprite)
    h, w = rgb.shape[:2]
    x0, y0 = int(x - w / 2), int(y - h / 2)
    sx0, sy0 = max(0, -x0), max(0, -y0)
    x1, y1 = min(W, x0 + w), min(H, y0 + h)
    if x1 <= max(0, x0) or y1 <= max(0, y0):
        return
    region = img[max(0, y0):y1, max(0, x0):x1]
    s = rgb[sy0:sy0 + region.shape[0], sx0:sx0 + region.shape[1]] * np.array(color)
    sa = a[sy0:sy0 + region.shape[0], sx0:sx0 + region.shape[1]] * alpha
    if add:
        region += s * sa
    else:
        region[:] = region * (1 - sa) + s * sa


def cell_sprite(name, rng):
    if name in ("Bolt", "Star", "Mote", "Puff", "Gas"):
        return tex(name)
    if name == "Splat":
        name = "Splat%d" % rng.randint(1, 4)
    i = cells.index(name)
    return tex("Effects").crop(((i % 8) * 128, (i // 8) * 128, (i % 8) * 128 + 128, (i // 8) * 128 + 128))


def spot(at, kind, rng):
    band = 0.22
    if at == "across":
        at = rng.choice(["top", "bottom"])
    if at == "edge":
        at = rng.choice(["top", "bottom", "left", "right"])
    if at == "sides":
        at = rng.choice(["left", "right"])
    if kind == "fall" and at == "top":
        return rng.uniform(0, W), rng.uniform(0, H * 0.7)
    if kind == "rise" and at == "bottom":
        return rng.uniform(0, W), rng.uniform(H * 0.35, H)
    if kind == "flutter" and at == "top":
        return rng.uniform(0, W), rng.uniform(0, H * 0.6)
    if at == "top":
        return rng.uniform(0, W), rng.uniform(0, H * band)
    if at == "bottom":
        return rng.uniform(0, W), rng.uniform(H * (1 - band), H)
    if at == "left":
        return rng.uniform(0, W * band * 0.6), rng.uniform(0, H)
    return rng.uniform(W * (1 - band * 0.6), W), rng.uniform(0, H)


def effects(img, theme, rng):
    for fx in (theme.get("effects") or []) + [dict(f, cell=f["tex"], add=not f.get("flat"), at=f.get("at", "edge"))
                                               for f in theme.get("sparks") or []]:
        life = sum(fx.get("life", [1, 2])) / 2
        n = fx.get("rate", 0) / 60 * life * 2.5
        hit = fx.get("hit")
        if hit:
            n += sum(hit) / 2
        n = max(1, min(30, round(n + (fx.get("beat", 0) or 0) * 2)))
        trail = fx.get("trail")
        for _ in range(n if not trail else 1):
            size = rng.uniform(*fx["size"]) * H
            spr = cell_sprite(fx["cell"], rng)
            if fx["cell"] == "Gas":  # (over the edges, anywhere along them)
                side = rng.choice("tblr")
                inset = rng.uniform(0.0, 0.07)
                x = rng.uniform(0, W) if side in "tb" else (inset * W * 0.6 if side == "l" else W - inset * W * 0.6)
                y = rng.uniform(0, H) if side in "lr" else (inset * H if side == "t" else H - inset * H)
            else:
                x, y = spot(fx.get("at", "edge"), fx["kind"], rng)
            add = bool(fx.get("add"))
            if trail:
                ang = rng.uniform(-0.3, 0.3)
                for k in range(trail):
                    s = spr.resize((max(2, int(size)), max(2, int(size))), Image.LANCZOS)
                    paste(img, s, x + k * fx.get("step", 0.06) * H * np.cos(ang),
                          y + k * fx.get("step", 0.06) * H * np.sin(ang) + (k % 2) * size * 0.6,
                          fx["color"], BLOOD_ALPHA * (0.4 + 0.6 * k / trail), add, -np.degrees(ang) - 90)
                continue
            w = h = size
            if fx["cell"] in ("Rain", "Sand", "Wind", "Bolt", "Slash", "Claw"):
                pass
            s = spr.resize((max(2, int(w)), max(2, int(h))), Image.LANCZOS)
            rot = 0
            if fx["kind"] in ("flutter", "splat", "reveal") or fx["cell"] in ("Shard", "Leaf", "Leaf2", "Petal"):
                rot = rng.uniform(0, 360)
            if fx["kind"] == "sweep":
                rot = rng.uniform(-10, 10)
            alpha = BLOOD_ALPHA * rng.uniform(0.55, 1)
            if fx["kind"] in ("flicker",):
                alpha = BLOOD_ALPHA
            paste(img, s, x, y, fx["color"], alpha, add, rot)


def drips(img, theme, rng):
    d = theme.get("drip")
    if not d:
        return
    spr = tex(d["tex"])
    up = d.get("up")
    for _ in range(max(2, round(5 * d.get("rate", 1)))):
        h = rng.uniform(0.12, 0.24) * H
        s = spr.resize((max(2, int(h / 8)), int(h)), Image.LANCZOS)
        if up:
            s = s.rotate(180)
        x = rng.uniform(0, W)
        y = (H - h / 2 - rng.uniform(0, 0.05) * H) if up else (h / 2 + rng.uniform(0, 0.05) * H)
        paste(img, s, x, y, d["color"], BLOOD_ALPHA * rng.uniform(0.7, 1), False)


def render(theme):
    rng = random.Random(theme["key"])
    img = BG.copy()
    img = vignette(img, [c * RED for c in theme["shadow"]])
    edge = theme.get("edge")
    if edge and theme.get("body"):
        rgb, a = full_art(edge)
        a = a * BLOOD_ALPHA
        img = img * (1 - a) + rgb * np.array(theme["body"]) * a
    if edge and theme.get("glow"):
        name = edge + "Glow"
        if os.path.exists(os.path.join(ART, name + ".tga")):
            rgb, a = full_art(name)
            ga = min(1, BLOOD_ALPHA * (theme.get("glowAlpha") or 1) * 0.8)
            img = img + rgb * np.array(theme["glow"]) * a * ga
    drips(img, theme, rng)
    effects(img, theme, rng)
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    buf = io.BytesIO()
    out.save(buf, "JPEG", quality=84)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


data = {"classes": [], "themes": {}}
# (Lua menu entries mix array parts and retail=true; read them raw.)
for i in range(1, len(ns.LOW_HEALTH_MENU) + 1):
    e = ns.LOW_HEALTH_MENU[i]
    specs = []
    for j in range(1, len(e[3]) + 1):
        s = e[3][j]
        specs.append({"spec": s[1], "key": s[2], "retail": bool(s.retail)})
    data["classes"].append({"token": e[1], "name": e[2], "retail": bool(e.retail), "specs": specs})

for t in themes:
    print("rendering", t["key"], flush=True)
    data["themes"][t["key"]] = {"name": t["name"], "edge": t.get("edge") or "none",
                                "who": t.get("who", ""), "img": render(t),
                                "fx": sorted({f["tex"] for f in t.get("sparks") or []}),
                                "drip": (t.get("drip") or {}).get("tex")}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "vitals_data.json"), "w") as f:
    json.dump(data, f)
print("done", sum(len(v["img"]) for v in data["themes"].values()) // 1024, "KB")
