#!/usr/bin/env python3
"""Cut Ludo's raw sound effects (assets/raw/sfx/*.mp3) into game-ready WAVs.

    python3 tools/ludo/prep_sfx.py            # all of them
    python3 tools/ludo/prep_sfx.py --report   # just print each file's envelope
    python3 tools/ludo/prep_sfx.py --out DIR fortune   # write somewhere else (a review folder)

Knocks (one die hitting the table) are cut to the single loudest hit with a short tail;
cheers are levelled by loudness (RMS) so a bigger army sounds fuller, not louder;
everything else loses its leading silence and gets a fade. macOS afconvert decodes the
MP3s; the rest is the standard library.
"""
import array
import math
import os
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "assets", "raw", "sfx")
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

## name: (mode, max seconds, level) — level is peak dBFS for "peak", RMS dBFS for "rms"
PLAN = {
    "dice_click": ("knock", 0.2, -3.0),
    "dice_knock": ("knock", 0.22, -3.0),
    "dice_clunk": ("knock", 0.3, -6.0),
    "dice_settle": ("trim", 0.6, -6.0),
    "dice_shake": ("trim", 0.9, -4.0),
    "dice_throw": ("trim", 1.8, -4.0),
    "cheer_few": ("rms", 1.6, -21.0),
    "cheer_company": ("rms", 1.5, -21.0),
    "cheer_army": ("rms", 3.6, -22.0),
    "flag_plant": ("trim", 1.6, -3.0),
    "fanfare_order": ("trim", 2.0, -4.0),
    "war_chest": ("trim", 2.0, -3.0),
    ## v1.5: muskets that boom, horses in rhythm, the distant battle, phase stings
    "musket_volley_1": ("trim", 2.2, -1.0),
    "musket_volley_2": ("trim", 2.2, -1.0),
    "musket_volley_3": ("trim", 2.2, -1.0),
    "musket_shot_1": ("trim", 1.4, -1.0),
    "musket_shot_2": ("trim", 1.4, -1.0),
    "cavalry_charge": ("trim", 4.0, -2.0),
    "cavalry_gallop": ("trim", 3.0, -3.0),
    "horse_trample": ("trim", 2.0, -4.0),
    "far_cannon": ("trim", 3.0, -4.0),
    "far_volley": ("trim", 3.0, -4.0),
    "far_drums": ("trim", 4.0, -4.0),
    "far_bugle": ("trim", 3.0, -4.0),
    "far_shouts": ("trim", 3.0, -4.0),
    "phase_sting": ("trim", 2.0, -3.0),
    "phase_tap": ("trim", 1.0, -4.0),
    ## v1.8: a capital falls: a tolling bell, a cannon, a cry
    "capital_fall": ("trim", 3.6, -3.0),
    ## v1.9: Fortune's favour: calling on it (harp and bells into a timpani hit), and banking one
    "fortune": ("trim", 2.4, -3.0),
    "fortune_gained": ("trim", 1.2, -5.0),
}


def decode(mp3):
    tmp = tempfile.mktemp(suffix=".wav")
    subprocess.run(["afconvert", mp3, tmp, "-f", "WAVE", "-d", "LEI16@44100"], check=True, capture_output=True)
    w = wave.open(tmp)
    ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
    data = array.array("h", w.readframes(n))
    w.close()
    os.remove(tmp)
    ## mono view for analysis
    mono = [sum(data[i * ch + c] for c in range(ch)) / ch for i in range(n)]
    return data, ch, rate, mono


def envelope(mono, rate, win=0.01):
    k = max(1, int(rate * win))
    return [max(abs(x) for x in mono[i:i + k]) for i in range(0, len(mono), k)]


def write(path, data, ch, rate):
    w = wave.open(path, "wb")
    w.setnchannels(ch)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(data.tobytes())
    w.close()


def cut(data, ch, a, b):
    return array.array("h", data[a * ch:b * ch])


def fade(data, ch, rate, tail_s, head_s=0.004):
    n = len(data) // ch
    tail = min(n, int(tail_s * rate))
    head = min(n, int(head_s * rate))
    for i in range(n):
        g = 1.0
        if i < head:
            g = i / head
        if i >= n - tail:
            g *= max(0.0, (n - i) / tail) ** 1.6
        if g < 1.0:
            for c in range(ch):
                data[i * ch + c] = int(data[i * ch + c] * g)
    return data


def gain(data, db_now, db_want):
    g = 10 ** ((db_want - db_now) / 20.0)
    for i in range(len(data)):
        data[i] = max(-32767, min(32767, int(data[i] * g)))
    return data


def peak_db(data):
    p = max(1, max(abs(x) for x in data))
    return 20 * math.log10(p / 32767.0)


def rms_db(data):
    s = sum(x * x for x in data) / max(1, len(data))
    return 10 * math.log10(max(1e-9, s) / (32767.0 ** 2))


def main():
    global OUT
    report = "--report" in sys.argv
    argv = sys.argv[1:]
    if "--out" in argv:
        i = argv.index("--out")
        OUT = os.path.abspath(argv[i + 1])
        os.makedirs(OUT, exist_ok=True)
        argv = argv[:i] + argv[i + 2:]
    only = [x for x in argv if not x.startswith("--")]
    for name, (mode, max_s, level) in PLAN.items():
        if only and name not in only:
            continue
        src = os.path.join(RAW, name + ".mp3")
        if not os.path.exists(src) and os.path.exists(os.path.join(RAW, name + ".wav")):
            src = os.path.join(RAW, name + ".wav")  ## Ludo sometimes sends a WAV
        if not os.path.exists(src):
            print("missing", name)
            continue
        data, ch, rate, mono = decode(src)
        env = envelope(mono, rate)
        pk = max(env) or 1
        if report:
            bars = "".join(" .:-=+*#%@"[min(9, int(9 * e / pk))] for e in env[: 300])
            print("%-14s %5.2fs ch%d  %s" % (name, len(mono) / rate, ch, bars))
            continue
        n = len(mono)
        if mode == "knock":
            ## the loudest hit, from just before its onset
            i_pk = max(range(len(env)), key=lambda i: env[i])
            k = int(rate * 0.01)
            start = i_pk * k
            thr = 0.25 * pk
            while start > 0 and abs(mono[start]) > 0.02 * pk:
                start -= 1
            start = max(0, start - int(0.002 * rate))
            end = min(n, start + int(max_s * rate))
            out = cut(data, ch, start, end)
            out = fade(out, ch, rate, max_s * 0.55, 0.001)
            out = gain(out, peak_db(out), level)
        else:
            start = 0
            thr = 0.04 * max(abs(x) for x in mono)
            while start < n and abs(mono[start]) < thr:
                start += 1
            start = max(0, start - int(0.01 * rate))
            end = min(n, start + int(max_s * rate))
            out = cut(data, ch, start, end)
            out = fade(out, ch, rate, min(0.35, max_s * 0.3))
            if mode == "rms":
                out = gain(out, rms_db(out), level)
                if peak_db(out) > -1.0:
                    out = gain(out, peak_db(out), -1.0)
            else:
                out = gain(out, peak_db(out), level)
        dst = os.path.join(OUT, name + ".wav")
        write(dst, out, ch, rate)
        print("wrote %-14s %.2fs  peak %.1f dB  rms %.1f dB" % (name, len(out) / ch / rate, peak_db(out), rms_db(out)))


if __name__ == "__main__":
    main()
