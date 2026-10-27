// The guidebook's pages and the bar every page shares. To add a page: put its
// file under docs/, add it to PAGES below, and give the page these two lines
// (paths relative to the page):
//   <link rel="stylesheet" href="../assets/site.css">
//   <script src="../assets/site.js" defer></script>
// The bar goes at the top of the page, and links to the next page and back to
// the menu at the bottom. The menu (index.html) lists the pages from here too.
(function () {
  var SECTIONS = [
    { id: "guides", name: "Guides", line: "How Cinematic's features work, for players." },
    { id: "design", name: "Under the hood", line: "How it's built: design notes drawn from the addon's code." }
  ];
  var PAGES = [
    { section: "guides", path: "guides/profiles.html", title: "Profiles",
      line: "Pick a level, then make it yours: the three levels, Customize's six areas, and where your changes are kept." },
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
    var list = PAGES.filter(function (p) { return p.section === current.section; });
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
        list.appendChild(el("li", {}, [el("a", { href: href(p.path) }, [
          el("span", { "class": "gb-title", text: p.title }),
          el("span", { "class": "gb-line", text: p.line }),
          el("span", { "class": "gb-go", "aria-hidden": "true", text: "→" })
        ])]));
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
