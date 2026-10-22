#!/usr/bin/env python3
"""Bring kept wars into the repo's wars/ folder (v2.4, game/core/war_records.gd), then commit wars/.

    python tools/wars/collect.py                  this machine's wars (the game's user folder)
    python tools/wars/collect.py <folder|zip> ... wars someone sent (Dad's wars folder, zipped or not)

The game keeps one file per war, rewritten every round until the war ends, so a war still being
played is brought up to date here; a copy with fewer rounds than the repo's is never taken over it.
Every war replays from its file: $G --headless --path . --script res://tools/wars/replay.gd -- wars/<id>.json
"""
import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEST = os.path.join(ROOT, "wars")


def user_wars():
    """the game's own folder of kept wars on this machine (Godot's app_userdata for CONCURRENT)"""
    if sys.platform.startswith("win"):
        base = os.path.join(os.environ.get("APPDATA", ""), "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "godot")
    return os.path.join(base, "app_userdata", "CONCURRENT", "wars")


def sources(args):
    """(label, bytes) for every war file named: folders are read, zips are read in memory (never unpacked)"""
    for arg in args:
        if os.path.isdir(arg):
            for name in sorted(os.listdir(arg)):
                if name.endswith(".json"):
                    with open(os.path.join(arg, name), "rb") as f:
                        yield name, f.read()
        elif zipfile.is_zipfile(arg):
            with zipfile.ZipFile(arg) as z:
                for info in z.infolist():
                    if info.filename.endswith(".json") and not info.is_dir():
                        yield os.path.basename(info.filename), z.read(info)
        elif os.path.isfile(arg) and arg.endswith(".json"):
            with open(arg, "rb") as f:
                yield os.path.basename(arg), f.read()
        else:
            print("collect: nothing to read at %s" % arg)


def describe(rec):
    seats = rec.get("config", {}).get("seats", [])
    names = ", ".join("%s%s" % (s.get("name", "?"), "" if s.get("kind") == "human" else " (AI)") for s in seats)
    winner = rec.get("winner", "")
    for s in seats:
        if s.get("id") == winner:
            winner = s.get("name", winner)
    mapname = os.path.splitext(os.path.basename(str(rec.get("config", {}).get("map", "?"))))[0]
    end = ("won by %s" % winner) if winner else "unfinished"
    return "%s  %s  %d rounds, %s  [%s]" % (rec.get("war", "?"), mapname, len(rec.get("sheets", [])), end, names)


def progress(rec):
    """how far a copy of a war goes: its rounds, then its marches after them, then its end"""
    return (len(rec.get("sheets", [])), sum(1 for m in rec.get("maneuvers", []) if m), 1 if rec.get("winner") else 0)


def main(argv):
    args = argv or [user_wars()]
    if not argv and not os.path.isdir(args[0]):
        print("collect: no wars kept on this machine yet (%s)" % args[0])
        args = []
    os.makedirs(DEST, exist_ok=True)
    new, grown, same, kept_ours, bad = [], [], 0, 0, 0
    for label, data in sources(args):
        try:
            rec = json.loads(data.decode("utf-8"))
            war = str(rec["war"])
            assert rec.get("setup") and war and isinstance(rec["sheets"], list)
        except (ValueError, KeyError, TypeError, AssertionError, UnicodeDecodeError):
            print("collect: skipped %s (not a kept war)" % label)
            bad += 1
            continue
        path = os.path.join(DEST, war + ".json")
        if os.path.exists(path):
            with open(path, "rb") as f:
                ours = f.read()
            if ours == data:
                same += 1
                continue
            try:
                here = progress(json.loads(ours.decode("utf-8")))
            except ValueError:
                here = (-1,)
            if progress(rec) <= here:
                kept_ours += 1
                continue
            grown.append(rec)
        else:
            new.append(rec)
        with open(path, "wb") as f:
            f.write(data)
    for rec in new:
        print("new      " + describe(rec))
    for rec in grown:
        print("updated  " + describe(rec))
    total = [n for n in os.listdir(DEST) if n.endswith(".json")]
    size = sum(os.path.getsize(os.path.join(DEST, n)) for n in total)
    print("collect: %d new, %d updated, %d already here%s%s; wars/ holds %d (%.1f MB)" % (
        len(new), len(grown), same,
        ", %d copies no further on than ours left alone" % kept_ours if kept_ours else "",
        ", %d skipped" % bad if bad else "",
        len(total), size / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
