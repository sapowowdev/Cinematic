"""Builds vitals-themes.html (the Vitals Vision theme gallery) from
out/vitals_data.json, made by vitals_gallery.py. Published as a private
claude.ai artifact: https://claude.ai/artifact/4YWb3DgV9LGRGRV17WaVDu
Usage: python build_page.py (after vitals_gallery.py)"""
import html, json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(here, "out", "vitals_data.json")))
# (A render saved as out/vitals_before.json, if any: cards that changed get Show before.)
before_path = os.path.join(here, "out", "vitals_before.json")
before = json.load(open(before_path))["themes"] if os.path.exists(before_path) else data["themes"]
COLORS = {"WARRIOR": "#C69B6D", "PALADIN": "#F48CBA", "HUNTER": "#AAD372", "ROGUE": "#FFF468",
          "PRIEST": "#FFFFFF", "SHAMAN": "#0070DD", "MAGE": "#3FC7EB", "WARLOCK": "#8788EE",
          "DRUID": "#FF7C0A", "DEATHKNIGHT": "#C41E3A", "MONK": "#00FF98", "DEMONHUNTER": "#A330C9",
          "EVOKER": "#33937F"}
e = html.escape
edges = sorted({t["edge"] for t in data["themes"].values()})

sections = []
shown = set()
for c in data["classes"]:
    cards = []
    for s in c["specs"]:
        t = data["themes"][s["key"]]
        again = s["key"] in shown
        shown.add(s["key"])
        fx = ", ".join(t["fx"] + ([t["drip"]] if t["drip"] else [])) or "none"
        tag = '<span class="tag">retail</span>' if s["retail"] or c["retail"] else ""
        old = before[s["key"]]
        changed = old["img"] != t["img"]
        swap = (f'<button type="button" class="swap" aria-pressed="false" data-old="{old["img"]}">Show before ({e(old["edge"])})</button>'
                if changed else "")
        cards.append(f'''<figure class="card{' changed' if changed else ''}" data-edge="{e(t["edge"])}" id="{e(s["key"])}{'-2' if again else ''}">
  <button type="button" class="shot" aria-label="Enlarge {e(t["name"])}"><img loading="lazy" src="{t["img"]}" alt="{e(t["name"])} at full low health" width="960" height="540"></button>
  <figcaption><div class="row"><b>{e(t["name"])}</b>{tag}</div>
  <div class="spec">{e(s["spec"])}</div>
  <dl><dt>Edge</dt><dd>{e(t["edge"])}</dd><dt>Sprites</dt><dd>{e(fx)}</dd><dt>Key</dt><dd><code>{e(s["key"])}</code></dd></dl>{swap}</figcaption>
</figure>''')
    sections.append(f'''<section class="cls" style="--cls:{COLORS[c["token"]]}">
  <h2><i></i>{e(c["name"])}</h2>
  <div class="grid">{"".join(cards)}</div>
</section>''')

chips = "".join(f'<button type="button" class="chip" data-edge="{e(x)}" aria-pressed="false">{e(x)}</button>' for x in edges)

page = f'''<title>Vitals Vision Themes</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600&family=Source+Sans+3:wght@400;600&family=JetBrains+Mono&display=swap">
<style>
/* Layout: a reading-width header, then one band per class, its spec themes in a wrapping grid of 16:9 stills. */
:root {{ --bg:#eef0f3; --panel:#ffffff; --fg:#1b1e24; --muted:#5d6470; --line:#d5d9e0; --accent:#a3271c;
  --display:"Cinzel", Georgia, serif; --body:"Source Sans 3", system-ui, sans-serif; --mono:"JetBrains Mono", ui-monospace, monospace; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#111317; --panel:#1a1d23; --fg:#e8eaee; --muted:#9aa1ad; --line:#2c3039; --accent:#ff6b5a; color-scheme:dark }} }}
:root[data-theme="dark"] {{ --bg:#111317; --panel:#1a1d23; --fg:#e8eaee; --muted:#9aa1ad; --line:#2c3039; --accent:#ff6b5a; color-scheme:dark }}
body {{ background:var(--bg); color:var(--fg); font:16px/1.5 var(--body); }}
.wrap {{ max-width:1280px; margin:0 auto; padding-block:32px 64px; padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); display:flex; flex-direction:column; gap:40px; }}
header {{ display:flex; flex-direction:column; gap:12px; max-width:68ch; }}
.eyebrow {{ font-size:12px; letter-spacing:.12em; text-transform:uppercase; color:var(--accent); font-weight:600; }}
h1 {{ font:600 clamp(28px,4vw,40px)/1.15 var(--display); margin:0; text-wrap:balance; }}
header p {{ margin:0; color:var(--muted); }}
.filter {{ display:flex; flex-wrap:wrap; gap:8px; align-items:center; }}
.filter span {{ font-size:13px; color:var(--muted); margin-right:4px; }}
.chip {{ font:13px var(--body); padding:4px 12px; border-radius:999px; border:1px solid var(--line); background:var(--panel); color:var(--fg); cursor:pointer; }}
.chip[aria-pressed="true"] {{ background:var(--fg); color:var(--bg); border-color:var(--fg); }}
.chip:focus-visible, .shot:focus-visible {{ outline:2px solid var(--accent); outline-offset:2px; }}
.cls {{ display:flex; flex-direction:column; gap:16px; }}
.cls h2 {{ font:600 22px var(--display); margin:0; display:flex; align-items:center; gap:10px; }}
.cls h2 i {{ width:14px; height:14px; border-radius:3px; background:var(--cls); box-shadow:0 0 0 1px var(--line); }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(min(100%, 340px), 1fr)); gap:20px; }}
.card {{ margin:0; background:var(--panel); border:1px solid var(--line); border-radius:8px; overflow:hidden; display:flex; flex-direction:column; min-width:0; }}
.card[hidden] {{ display:none; }}
.shot {{ padding:0; border:0; background:#000; cursor:zoom-in; display:block; }}
.shot img {{ display:block; width:100%; height:auto; aspect-ratio:16/9; }}
figcaption {{ padding:12px 14px 14px; display:flex; flex-direction:column; gap:4px; }}
.row {{ display:flex; justify-content:space-between; align-items:baseline; gap:8px; }}
.row b {{ font-size:17px; }}
.tag {{ font-size:11px; letter-spacing:.08em; text-transform:uppercase; color:var(--muted); border:1px solid var(--line); border-radius:4px; padding:0 6px; }}
.swap {{ align-self:flex-start; margin-top:8px; font:13px var(--body); padding:4px 10px; border-radius:6px; border:1px solid var(--line); background:transparent; color:var(--fg); cursor:pointer; }}
.swap[aria-pressed="true"] {{ background:var(--fg); color:var(--bg); }}
.swap:focus-visible {{ outline:2px solid var(--accent); outline-offset:2px; }}
.changed .row b::after {{ content:"changed"; margin-left:8px; font:600 11px var(--body); letter-spacing:.08em; text-transform:uppercase; color:var(--accent); }}
.spec {{ color:var(--muted); font-size:14px; }}
dl {{ display:grid; grid-template-columns:auto 1fr; gap:2px 12px; margin:6px 0 0; font-size:13px; }}
dt {{ color:var(--muted); }} dd {{ margin:0; min-width:0; }}
code {{ font:12px var(--mono); }}
dialog {{ padding:0; border:0; background:transparent; max-width:min(96vw, 1400px); }}
dialog::backdrop {{ background:rgba(0,0,0,.85); }}
dialog img {{ display:block; width:100%; height:auto; border-radius:6px; }}
dialog p {{ color:#fff; text-align:center; margin:8px 0 0; font:600 18px var(--display); }}
.empty {{ color:var(--muted); }}
@media (prefers-reduced-motion: no-preference) {{ .shot img {{ transition:transform .2s; }} .shot:hover img {{ transform:scale(1.02); }} }}
</style>
<div class="wrap">
<header>
  <div class="eyebrow">Cinematic · Visions</div>
  <h1>Vitals Vision themes</h1>
  <p>Every low-health theme, drawn from the addon's own textures and colors at the page's default settings, at full low health, just after a hit. These are stills: in the game the glow throbs with the heartbeat, and a hit flashes the edges. Every theme has a soft haze of gas drifting over its edges, in its own color. The only other sprites are lightning (Storm, Windfury), twinkling stars and rising motes.</p>
  <p>Each theme is shown under every spec that uses it. Click a still to see it larger.</p>
  <p><b>New:</b> Decay is now Unholy Death Knight's (in place of Plague), Affliction Warlock has Drained souls: fel green souls rising out of a near-black violet shadow; and Frost Death Knight has Hoarfrost: frost creeping over the glass on a new Rime edge, its cold front glowing.</p>
  <div class="filter" role="group" aria-label="Filter by edge material"><span>Edge material</span>{chips}</div>
</header>
{"".join(sections)}
<p class="empty" id="empty" hidden>No theme uses that edge material.</p>
</div>
<dialog id="big"><img alt=""><p></p></dialog>
<script>
const big = document.getElementById("big");
document.querySelectorAll(".shot").forEach(b => b.addEventListener("click", () => {{
  const img = b.querySelector("img");
  big.querySelector("img").src = img.src;
  big.querySelector("img").alt = img.alt;
  big.querySelector("p").textContent = b.closest(".card").querySelector("b").textContent;
  big.showModal();
}}));
big.addEventListener("click", () => big.close());
document.querySelectorAll(".swap").forEach(b => {{
  const img = b.closest(".card").querySelector("img"), now = img.src, label = b.textContent;
  b.addEventListener("click", () => {{
    const on = b.getAttribute("aria-pressed") !== "true";
    b.setAttribute("aria-pressed", on);
    img.src = on ? b.dataset.old : now;
    b.textContent = on ? "Show new" : label;
  }});
}});
let picked = null;
document.querySelectorAll(".chip").forEach(c => c.addEventListener("click", () => {{
  picked = picked === c.dataset.edge ? null : c.dataset.edge;
  document.querySelectorAll(".chip").forEach(x => x.setAttribute("aria-pressed", x.dataset.edge === picked));
  document.querySelectorAll(".cls").forEach(sec => {{
    let any = false;
    sec.querySelectorAll(".card").forEach(card => {{ card.hidden = picked && card.dataset.edge !== picked; any ||= !card.hidden; }});
    sec.hidden = !any;
  }});
}}));
</script>
'''
open(os.path.join(here, "vitals-themes.html"), "w", encoding="utf-8").write(page)
print(len(page) // 1024, "KB")
