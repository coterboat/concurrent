#!/usr/bin/env python3
"""Pack Ludo's raw animation sheets (assets/raw, not imported) into game sheets.

    python3 tools/ludo/pack_anims.py

Portrait loops: 256 px frames; the last frame duplicates the first (the loop was
generated to end where it began), so it is dropped. If the step from the last kept
frame back to the first is still bigger than any step inside the loop, the loop
plays back and forth (ping-pong) so there is no seam at all.
Soldiers: 384 px frames on the shared padded canvas, plus a frame order:
  idle  - ping-pong, so the breathing never jumps at the seam
  fire  - raise (the lowering, reversed), aim, fire, lower back to the stance
  march - a walk cycle, looped as is
  fall  - not packed: the generated fall was unusable (the figure flipped upside
          down); the theater topples the standing figure in code instead
Every sheet is checked (sheet_tool.gd check) and its seam printed.

assets/raw is not in git (37 MB of masters). `--fetch` re-downloads any missing
master from the spritesheet URL recorded in assets/ludo_ledger.json first.
"""
import glob
import json
import os
import re
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot"))


def tool(*args):
    out = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "tools/sheet_tool.gd", "--"] + list(args),
                         capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() if l.startswith(("wrote", "SUMMARY", "padded"))]
    return "\n".join(lines)


def meta_of(raw):
    return json.load(open(os.path.splitext(raw)[0] + ".json"))


def patch(out, **extra):
    j = os.path.splitext(os.path.join(ROOT, out))[0] + ".json"
    m = json.load(open(j))
    m.update(extra)
    json.dump(m, open(j, "w"))


def fetch():
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    import ludo
    led = json.load(open(ludo.LEDGER))
    man = json.load(open(ludo.MANIFEST))
    for a in man["assets"]:
        if a["kind"] != "animate" or not a["out"].startswith("assets/raw/"):
            continue
        dest = os.path.join(ROOT, a["out"] + ".webp")
        if os.path.exists(dest) or a["id"] not in led:
            continue
        ludo.download(led[a["id"]]["url"], dest)
        job = led[a["id"]].get("params", {})
        json.dump({"cols": 4, "rows": 4, "frames": int(job.get("frames", 16))}, open(os.path.join(ROOT, a["out"] + ".json"), "w"))
        print("fetched", a["id"])


def main():
    import sys
    if "--fetch" in sys.argv:
        fetch()
    os.makedirs(os.path.join(ROOT, "assets/portraits/loops"), exist_ok=True)
    for raw in sorted(glob.glob(os.path.join(ROOT, "assets/raw/loops/*.webp"))):
        m = meta_of(raw)
        name = os.path.basename(raw)
        out = "assets/portraits/loops/" + name
        report = tool("check", raw, str(m["cols"]), str(m["rows"]), str(m["frames"]))
        print(report)
        print(tool("shrink", raw, str(m["cols"]), str(m["rows"]), "256", out, str(m["frames"]), "drop_last"))
        ## if coming round from the last kept frame to the first is a bigger step than
        ## any step inside the loop, play it back and forth instead: then there is no seam
        mx = float(re.search(r"max_step ([0-9.]+)", report).group(1))
        seam = float(re.search(r"seam\(prev->first\) ([0-9.]+)", report).group(1))
        n = int(m["frames"]) - 1
        if seam > mx:
            patch(out, order=list(range(0, n)) + list(range(n - 2, 0, -1)))
            print("  -> ping-pong (seam %.2f > max step %.2f)" % (seam, mx))
    ## (name, frame order or None, anchor x, baseline, figure height / canvas height)
    inf = (0.55, 0.92, 450.0 / 768.0)
    cav = (0.55, 0.92, 500.0 / 768.0)
    gun = (0.45, 0.92, 300.0 / 768.0)
    ping = list(range(0, 16)) + list(range(14, 0, -1))
    battle = [
        ("soldier_idle", ping, inf),
        ("soldier_fire", [7, 6, 5, 4, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], inf),
        ("soldier_march", None, inf),
        ("flag_wave", ping, inf),
        ## these start mid-motion: play the recovery backwards first, so they rise out of the stance
        ("soldier_kneel", [9, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], inf),
        ("soldier_cheer", [11, 9, 7, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], inf),
        ("soldier_reload", None, inf),
        ("soldier_charge", None, inf),
        ("cavalry_idle", None, cav),
        ("cavalry_gallop", None, cav),
        ("cavalry_charge", None, cav),
        ("cavalry_rear", None, cav),
        ("cannon_idle", None, gun),
        ("cannon_fire", None, gun),
        ("cannon_reload", None, gun),
    ]
    ## v1.4 aiming poses: single frames on the shared canvas; the theater kicks, flashes and smokes them
    for name in ("soldier_aim", "soldier_kneel_aim"):
        raw = os.path.join(ROOT, "assets/raw/battle/%s_pad.png" % name)
        if os.path.exists(raw):
            out = "assets/battle/%s.webp" % name
            print(tool("shrink", raw, "1", "1", "384", out, "1"))
            patch(out, ax=inf[0], ay=inf[1], fill=inf[2])
    for name, order, (ax, ay, fill) in battle:
        raw = os.path.join(ROOT, "assets/raw/battle/%s.webp" % name)
        if not os.path.exists(raw):
            print("missing", name)
            continue
        m = meta_of(raw)
        out = "assets/battle/%s.webp" % name
        report = tool("check", raw, str(m["cols"]), str(m["rows"]), str(m["frames"]))
        print(report)
        print(tool("shrink", raw, str(m["cols"]), str(m["rows"]), "384", out, str(m["frames"])))
        extra = {"ax": ax, "ay": ay, "fill": fill}
        if order:
            extra["order"] = order
        elif name.endswith(("idle", "gallop", "charge", "march")):
            ## a loop: if its seam is worse than any step, ping-pong it
            mx = float(re.search(r"max_step ([0-9.]+)", report).group(1))
            seam = float(re.search(r"seam\(last->first\) ([0-9.]+)", report).group(1))
            if seam > mx:
                extra["order"] = ping
                print("  -> ping-pong (seam %.2f > max step %.2f)" % (seam, mx))
        patch(out, **extra)


if __name__ == "__main__":
    main()
