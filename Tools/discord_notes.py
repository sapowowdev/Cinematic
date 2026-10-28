#!/usr/bin/env python3
"""Posts a release's new features to Discord, with a link to the patch notes page.

    python3 Tools/discord_notes.py v1.8.61          post (needs DISCORD_WEBHOOK set)
    python3 Tools/discord_notes.py v1.8.61 --dry    print the message instead

The release workflow runs it after packaging. A release's new features are the
Changelog.lua entries its tag has that the tag before it didn't. A release with
none posts nothing, and so does a run without DISCORD_WEBHOOK.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

NOTES = "https://sapowowdev.github.io/Cinematic/updates/patch-notes.html"
CLIENTS = {"forever": "WoW Forever only", "retail": "Retail only"}
GOLD = 0xE2B53F


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def features(ref):
    """ns.CHANGELOG_FEATURES at ref: its { key = "string" .. "string" } entries."""
    try:
        src = git("show", ref + ":Changelog.lua")
    except subprocess.CalledProcessError:
        return []
    at = src.find("ns.CHANGELOG_FEATURES")
    if at < 0:
        return []
    i, out, entry, key, depth = src.index("{", at) + 1, [], None, None, 1
    while i < len(src) and depth > 0:
        c = src[i]
        if src.startswith("--", i):
            i = src.find("\n", i)
            if i < 0:
                break
            continue
        if c == "{":
            depth, entry = depth + 1, {}
        elif c == "}":
            depth -= 1
            if entry is not None and depth == 1:
                out.append(entry)
                entry = None
        elif c in "\"'":
            s, j = "", i + 1
            while j < len(src) and src[j] != c:
                if src[j] == "\\":
                    j += 1
                    s += "\n" if src[j] == "n" else src[j]
                else:
                    s += src[j]
                j += 1
            if entry is not None and key:
                entry[key] = entry.get(key, "") + s
            i = j
        else:
            m = re.match(r"([A-Za-z_]\w*)\s*=", src[i:i + 40])
            if m:
                key = m.group(1)
                i += m.end()
                continue
        i += 1
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry" in sys.argv
    tag = args[0] if args else git("describe", "--tags", "--abbrev=0")
    try:
        prev = git("describe", "--tags", "--abbrev=0", "--match", "v*", tag + "^")
    except subprocess.CalledProcessError:
        prev = None
    seen = {(f.get("date"), f.get("title")) for f in features(prev)} if prev else set()
    new = [f for f in features(tag) if (f.get("date"), f.get("title")) not in seen]
    version = tag.lstrip("v")
    if not new:
        print(f"{tag}: no new features since {prev}, nothing to post")
        return

    lines = []
    for f in sorted(new, key=lambda f: f.get("date", ""), reverse=True):
        tail = f" *({CLIENTS[f['client']]})*" if f.get("client") in CLIENTS else ""
        lines.append(f"**{f.get('title', '')}**{tail}\n{f.get('text', '')}")
    link = f"[All patch notes]({NOTES}#v{version})"
    body = "\n\n".join(lines)
    if len(body) > 3900:  # an embed's description holds 4096
        body = body[:3900].rsplit("\n\n", 1)[0] + "\n\n…and more."
    message = {"embeds": [{
        "title": f"Cinematic {version} is out",
        "url": f"{NOTES}#v{version}",
        "description": body + "\n\n" + link,
        "color": GOLD,
    }]}

    if dry:
        print(json.dumps(message, indent=2, ensure_ascii=False))
        return
    hook = os.environ.get("DISCORD_WEBHOOK")
    if not hook:
        print("DISCORD_WEBHOOK not set, nothing posted")
        return
    req = urllib.request.Request(hook, data=json.dumps(message).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "Cinematic release"})
    with urllib.request.urlopen(req) as r:
        print(f"posted {len(new)} feature(s) for {tag} (HTTP {r.status})")


if __name__ == "__main__":
    main()
