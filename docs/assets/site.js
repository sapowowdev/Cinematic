// The guidebook's pages and the bar every page shares. To add a page: put its
// file under docs/, add it to PAGES below, and give the page these two lines
// (paths relative to the page):
//   <link rel="stylesheet" href="../assets/site.css">
//   <script src="../assets/site.js" defer></script>
// The bar goes at the top of the page, and links to the next page and back to
// the menu at the bottom. The menu (index.html) lists the pages from here too.
(function () {
  var SECTIONS = [
    { id: "start", name: "Start here", line: "New to Cinematic? Begin with these." },
    { id: "guides", name: "Guides", line: "How Cinematic's features work, for players." },
    { id: "reference", name: "Reference", line: "Commands, keybinds and every settings page, to look things up." },
    { id: "help", name: "Help", line: "When something's not right." },
    { id: "design", name: "Under the hood", line: "How it's built: design notes drawn from the addon's code." }
  ];
  // soon: listed on the menu as coming soon, not linked, until its page is written.
  var PAGES = [
    { section: "start", path: "start/getting-started.html", title: "Getting started",
      line: "Installing, the welcome window, and turning CineMode on and off." },
    { section: "guides", path: "guides/profiles.html", title: "Profiles",
      line: "Pick a level, then make it yours: the three levels, Customize's six areas, and where your changes are kept." },
    { section: "guides", path: "guides/cinemode.html", title: "CineMode and fading",
      line: "What fades and when, smart reveals, mouseover groups, fights, and where it turns itself off." },
    { section: "guides", path: "guides/cameras.html", title: "The cameras",
      line: "Every camera, what starts it, the Camera Triggers page and depth of field." },
    { section: "guides", path: "guides/flight-cam.html", title: "Flight Cam",
      line: "Takeoff, sway, fly-bys and landing, and how each route is timed." },
    { section: "guides", path: "guides/look.html", title: "Look and mood",
      line: "Tints, time of day, zone moods, inn glow, weather, letterbox and vignette." },
    { section: "guides", path: "guides/music.html", title: "Music and sound",
      line: "Which cameras start music, music fatigue, muting by place, and your settings put back." },
    { section: "guides", path: "guides/visions.html", title: "Visions",
      line: "Heal, Quest, Roll, Duel and Vitals Vision." },
    { section: "guides", path: "guides/wheels.html", title: "Wheels",
      line: "Camera, menu, marker and vision wheels, and wheels of your own." },
    { section: "guides", path: "guides/nameplates.html", title: "Nameplates and names",
      line: "What shows for each kind of unit and place, plate parts and the target arrow." },
    { section: "guides", path: "guides/frames.html", title: "Frames",
      line: "Standard and unit frames, personal resources, the Cooldown Manager, swing timer and buffs." },
    { section: "guides", path: "guides/chat-and-quests.html", title: "Chat and quests",
      line: "Chat that peeks in, chat bubbles, and quest dialogue as bubbles and cards." },
    { section: "guides", path: "guides/quality-of-life.html", title: "Quality of life",
      line: "The campfire button, fishing casts, hunter ammo, the talent calculator and loot rolls." },
    { section: "guides", path: "guides/other-addons.html", title: "Other addons",
      line: "Addons handled out of the box, and Add mode for the rest." },
    { section: "guides", path: "guides/gamepad.html", title: "Gamepad",
      line: "Playing WoW Forever with a controller." },
    { section: "guides", path: "guides/graphics.html", title: "Graphics+",
      line: "What the Graphics+ page changes, and why." },
    { section: "reference", path: "reference/commands.html", title: "Commands",
      line: "Every /cine command." },
    { section: "reference", path: "reference/keybinds.html", title: "Keybinds",
      line: "Every keybind and what it does." },
    { section: "reference", path: "reference/settings.html", title: "Settings map",
      line: "Every settings page in one line, with a link to its guide." },
    { section: "reference", path: "reference/sharing.html", title: "Sharing profiles",
      line: "Export your setup as text, and import a friend's." },
    { section: "reference", path: "reference/forever-vs-retail.html", title: "WoW Forever and retail",
      line: "Which features are on which game." },
    { section: "help", path: "help/troubleshooting.html", title: "Troubleshooting",
      line: "Common fixes, /cine panic and resume, and how to report a bug with /cine log." },
    { section: "design", path: "design/profile-modules.html", title: "Profile modules",
      line: "How modules, choices and profiles fit together, with the welcome window, the coverage map and the checks." }
  ];

  // The guidebook's root: the folder above assets/, wherever it's served from.
  var me = document.currentScript;
  var root = new URL("../", me ? me.src : location.href);
  function href(path) { return new URL(path, root).href; }
  var here = location.href.split("#")[0].split("?")[0];
  var current = PAGES.filter(function (p) { return href(p.path) === here; })[0];

  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") n.textContent = attrs[k]; else n.setAttribute(k, attrs[k]);
    });
    (kids || []).forEach(function (k) { if (k) n.appendChild(k); });
    return n;
  }

  function bar() {
    var links = el("div", { "class": "gb-links" });
    SECTIONS.forEach(function (s) {
      var a = el("a", { href: href("index.html#" + s.id), text: s.name });
      if (current && current.section === s.id) a.setAttribute("aria-current", "true");
      links.appendChild(a);
    });
    var crumb = current ? el("span", { "class": "gb-crumb", text: current.title }) : null;
    return el("nav", { "class": "gb-bar", "aria-label": "Guidebook" }, [
      el("div", { "class": "gb-inner" }, [
        el("a", { "class": "gb-home", href: href("index.html") }, [
          el("span", { "class": "gb-mark", "aria-hidden": "true" }),
          el("span", { text: "Cinematic Guidebook" })
        ]),
        crumb, links
      ])
    ]);
  }

  function foot() {
    var list = PAGES.filter(function (p) { return p.section === current.section && !p.soon; });
    var i = list.indexOf(current);
    var prev = list[i - 1], next = list[i + 1];
    function card(p, dir) {
      return el("a", { "class": "gb-card gb-" + dir, href: href(p.path) }, [
        el("span", { "class": "gb-dir", text: dir === "prev" ? "Previous" : "Next" }),
        el("span", { "class": "gb-title", text: p.title })
      ]);
    }
    return el("footer", { "class": "gb-foot" }, [
      el("div", { "class": "gb-inner" }, [
        el("a", { "class": "gb-back", href: href("index.html") }, [el("span", { text: "← Back to the guidebook" })]),
        prev ? card(prev, "prev") : null,
        next ? card(next, "next") : null
      ])
    ]);
  }

  // The menu page's lists: one block per section.
  function menu(into) {
    SECTIONS.forEach(function (s) {
      var pages = PAGES.filter(function (p) { return p.section === s.id; });
      var list = el("ul", { "class": "gb-list" });
      pages.forEach(function (p) {
        var kids = [
          el("span", { "class": "gb-title", text: p.title }),
          el("span", { "class": "gb-line", text: p.line }),
          el("span", { "class": "gb-go", "aria-hidden": "true", text: p.soon ? "Soon" : "→" })
        ];
        list.appendChild(el("li", {}, [p.soon ? el("div", { "class": "gb-soon" }, kids) : el("a", { href: href(p.path) }, kids)]));
      });
      into.appendChild(el("section", { "class": "gb-section", id: s.id }, [
        el("h2", { text: s.name }), el("p", { "class": "gb-sline", text: s.line }), list
      ]));
    });
  }

  function start() {
    document.body.insertBefore(bar(), document.body.firstChild);
    if (current) document.body.appendChild(foot());
    var into = document.getElementById("gb-menu");
    if (into) menu(into);
    if (location.hash) { var t = document.getElementById(location.hash.slice(1)); if (t) t.scrollIntoView(); }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
