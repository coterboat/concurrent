#!/usr/bin/env python3
"""The mix's levels (v2.3): measure every sound's loudness and write the gains that bring the
outliers into line, for game/core/audio.gd to apply at play time (the files are never touched).

    python3 tools/audio/levels.py            # measure everything, write game/data/levels.json
    python3 tools/audio/levels.py --report   # also print what moved and why

Run it again whenever new sounds arrive (a review batch installed, a new voice cast). It needs ffmpeg.

What it evens out, and what it leaves alone:
  * voices: each speaker's lines are brought to one level (VOICE_TARGET), so a commander never shouts
    over the advisor or mumbles under him; inside a speaker the performance is kept (a shout stays
    louder than a mutter), and only a line more than VOICE_SPREAD from its speaker's middle is pulled
    back to that edge.
  * music: every take to the takes' own middle, so a playlist never jumps 8 dB between two takes of
    one mood, and the score as a whole is as loud as it was.
  * ambience: a bed quieter than AMB_TARGET comes up to it (the tent's was measured at -41 LUFS:
    under its bus, silence); a louder one is left as it was mixed.
  * sound effects: only the hot ones come down, to SFX_CEILING; quiet ones (a click) stay quiet.
  * anything shorter than MIN_SECONDS or gated to silence by the meter is left alone.
Gains are clamped (MAX_CUT, MAX_BOOST) so a bad measurement can't wreck a sound, and a boost never lifts
a sound's true peak past PEAK_CEILING (the master bus's limiter catches what stacks).
"""
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "data", "levels.json")
DIRS = ["assets/audio/sfx", "assets/audio/music", "assets/voice", "assets/voice13"]
EXTS = (".mp3", ".wav", ".ogg")

VOICE_TARGET = -20.0
VOICE_SPREAD = 5.0
MUSIC_TOLERANCE = 1.0
AMB_TARGET = -26.0
SFX_CEILING = -12.0
MIN_SECONDS = 0.4
MAX_CUT = -8.0
MAX_BOOST = 12.0
PEAK_CEILING = -1.0


def ffmpeg() -> str:
    for c in [shutil.which("ffmpeg"), "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]:
        if c and os.path.exists(c):
            return c
    sys.exit("levels: ffmpeg not found")


def measure(path: str) -> dict:
    """integrated loudness (LUFS) and duration"""
    p = subprocess.run([ffmpeg(), "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True, errors="replace")
    err = p.stderr
    m = re.findall(r"I:\s+(-?[\d.]+|-inf) LUFS", err)
    d = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err)
    dur = int(d.group(1)) * 3600 + int(d.group(2)) * 60 + float(d.group(3)) if d else 0.0
    lufs = float(m[-1]) if m and m[-1] != "-inf" else -99.0
    pk = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", err)
    tp = float(pk[-1]) if pk and pk[-1] != "-inf" else -99.0
    return {"I": lufs, "dur": dur, "tp": tp}


def files() -> list:
    out = []
    for d in DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            for n in sorted(names):
                if n.endswith(EXTS) and "_sample" not in n:
                    out.append(os.path.relpath(os.path.join(base, n), ROOT).replace("\\", "/"))
    return sorted(out)


def kind(rel: str) -> str:
    if rel.startswith("assets/voice"):
        return "voice"
    if rel.startswith("assets/audio/music/"):
        return "ambience" if os.path.basename(rel).startswith("ambience") else "music"
    return "sfx"


def clamp(g: float) -> float:
    return max(MAX_CUT, min(MAX_BOOST, g))


def main() -> None:
    rels = files()
    with ThreadPoolExecutor(max_workers=8) as ex:
        meas = dict(zip(rels, ex.map(lambda r: measure(os.path.join(ROOT, r)), rels)))
    usable = {r: m for r, m in meas.items() if m["dur"] >= MIN_SECONDS and m["I"] > -60.0}
    ## each speaker (a folder of voice lines) has its middle
    speakers = {}
    for r, m in usable.items():
        if kind(r) == "voice":
            speakers.setdefault(os.path.dirname(r), []).append(m["I"])
    mid = {k: statistics.median(v) for k, v in speakers.items()}
    music = [m["I"] for r, m in usable.items() if kind(r) == "music"]
    music_target = round(statistics.median(music), 1) if music else -18.0
    gains = {}
    why = {}
    for r, m in usable.items():
        k = kind(r)
        i = m["I"]
        g = 0.0
        if k == "voice":
            sm = mid[os.path.dirname(r)]
            g = VOICE_TARGET - sm
            dev = i - sm
            if abs(dev) > VOICE_SPREAD:
                g -= dev - (VOICE_SPREAD if dev > 0 else -VOICE_SPREAD)
            why[r] = "voice %.1f (speaker %.1f)" % (i, sm)
        elif k == "music":
            if abs(i - music_target) > MUSIC_TOLERANCE:
                g = music_target - i
            why[r] = "music %.1f" % i
        elif k == "ambience":
            if i < AMB_TARGET:
                g = AMB_TARGET - i
            why[r] = "ambience %.1f" % i
        else:
            if i > SFX_CEILING:
                g = SFX_CEILING - i
            why[r] = "sfx %.1f" % i
        g = clamp(g)
        if g > 0.0:
            g = max(0.0, min(g, PEAK_CEILING - m["tp"])) ## a boost never pushes the true peak past the ceiling
        g = round(g, 1)
        if abs(g) >= 0.5:
            key = "res://" + os.path.splitext(r)[0]
            gains[key] = g
    doc = {
        "about": "v2.3 the mix's levels: dB added to each sound at play time (game/core/audio.gd). Written by tools/audio/levels.py from the files' measured loudness; run it again when sounds change. A sound not listed plays as it is.",
        "targets": {"voice": VOICE_TARGET, "music": music_target, "ambience": AMB_TARGET, "sfx_ceiling": SFX_CEILING},
        "gains": dict(sorted(gains.items())),
    }
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("levels: %d sounds measured, %d moved, written to %s" % (len(meas), len(gains), os.path.relpath(OUT, ROOT)))
    if "--report" in sys.argv:
        for key, g in sorted(gains.items(), key=lambda kv: kv[1]):
            rel = key[len("res://"):]
            src = next((r for r in usable if os.path.splitext(r)[0] == rel), rel)
            print("  %+5.1f dB  %s  (%s)" % (g, rel, why.get(src, "")))


if __name__ == "__main__":
    main()
