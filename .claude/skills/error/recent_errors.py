"""Prints the recent errors from the addon's log, as the game last saved it.

The log lives in SavedVariables (CinematicDev.lua, or Cinematic.lua for the
release copy), one quoted line per entry; the game writes it on /reload and
logout only. Picks the most recently saved file across the WoW clients.

usage: recent_errors.py [sessions=5] [context=6]
  sessions: how many of the last sessions (logins) to look through
  context:  log lines shown before each error
"""
import glob
import os
import re
import sys
import time

WOW = r"C:\Program Files (x86)\World of Warcraft"
LINE = re.compile(r'^\s*"(\d\d:\d\d:\d\d(?:\.\d+)?) (.*)",?\s*$')
SESSION = "session: ----"


def unescape(text):
    return text.encode("latin-1", "backslashescape").decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")


def main():
    sessions = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    context = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    files = [f for name in ("CinematicDev.lua", "Cinematic.lua")
             for f in glob.glob(os.path.join(WOW, "*", "WTF", "Account", "*", "SavedVariables", name))]
    if not files:
        print("no saved log found under " + WOW)
        return
    path = max(files, key=os.path.getmtime)
    saved = os.path.getmtime(path)
    print("log: %s" % path)
    print("saved: %s (%d min ago)" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(saved)), (time.time() - saved) // 60))

    entries = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = LINE.match(raw)
            if m:
                entries.append((m.group(1), unescape(m.group(2))))
    starts = [i for i, (_, text) in enumerate(entries) if text.startswith(SESSION)]
    first = starts[-sessions] if len(starts) >= sessions else 0
    print("looking at the last %d session(s), %d log lines\n" % (min(sessions, len(starts)), len(entries) - first))

    found = 0
    session = None
    for i in range(first, len(entries)):
        when, text = entries[i]
        if text.startswith(SESSION):
            session = "%s %s" % (when, text)
            continue
        if text.startswith("ERROR:") or text.startswith("errors:"):
            found += 1
            print("=" * 70)
            if session:
                print("[%s]" % session)
            if text.startswith("ERROR:"):
                for j in range(max(first, i - context), i):
                    if not entries[j][1].startswith(SESSION):
                        print("  %s %s" % entries[j])
            print(">> %s %s" % (when, text))
    if not found:
        print("no errors in those sessions")

    # Game crashes (not Lua errors) leave reports beside the client's WTF.
    client = path.split(os.sep + "WTF" + os.sep)[0]
    crashes = sorted(glob.glob(os.path.join(client, "Errors", "*")), key=os.path.getmtime)[-3:]
    recent = [c for c in crashes if time.time() - os.path.getmtime(c) < 86400]
    if recent:
        print("\ncrash reports in the last day:")
        for c in recent:
            print("  %s  %s" % (time.strftime("%H:%M", time.localtime(os.path.getmtime(c))), c))


if __name__ == "__main__":
    main()
