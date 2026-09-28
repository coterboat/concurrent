#!/usr/bin/env python3
"""Measure spoken voice takes: length, the pause between sentences, pitch, and whether the
line ends falling. Stdlib only (ffmpeg does the decoding), about 0.1-0.3 s per clip.

    import voice_measure as vm
    vm.measure("take.mp3")   # {"dur": 3.1, "gap": 0.42, "f0": 128.4, "end_slope_st": -2.3}
    vm.rank(paths, "fall")   # [{"path": ..., "dur": ..., ...}, ...] most falling ending first
                             # want: "fall" | "pause" (longest gap) | "lower" (lowest f0)

    python3 tools/ludo/voice_measure.py take.mp3 ...   # print the measurements
    python3 tools/ludo/voice_measure.py --selftest     # synthetic checks (no audio files needed)

The measures (see review/v111_lab/results.json for what they told us about Ludo's speech):
  dur           the clip's length in seconds.
  gap           the longest silence (ffmpeg silencedetect, -35 dBFS for 60 ms or more) that
                starts after 15% and ends before 90% of the clip: the pause between sentences.
                0.0 when there is none.
  f0            median pitch (Hz) of the voiced frames.
  end_slope_st  median pitch of the last 350 ms of voiced frames minus the clip's median, in
                semitones: negative = the line ends falling.
Pitch: 30 ms frames every 10 ms, normalized cross-correlation over 70-400 Hz on a 60-1000 Hz
band; voiced = energy over 20% of the clip's 90th-percentile frame and a peak over 0.45; the
smallest-lag peak within 88% of the best, an octave fold toward the clip median and a 5-frame
median. measure() never raises: a missing, broken or too-short file gives None fields.
"""
import array
import itertools
import math
import operator
import os
import re
import statistics
import subprocess
import sys

FFMPEG = os.environ.get("FFMPEG", "/opt/homebrew/bin/ffmpeg")
if not os.path.exists(FFMPEG):
    FFMPEG = "ffmpeg"
SR = 16000
W = 480           # 30 ms frame
HOP = 160         # 10 ms hop
LMIN = SR // 400  # 400 Hz
LMAX = SR // 70   # 70 Hz
PITCH_BAND = "highpass=f=60,lowpass=f=1000"

WANTS = {  # rank(): the key and whether bigger ranks first
    "fall": ("end_slope_st", False),
    "pause": ("gap", True),
    "lower": ("f0", False),
}


def decode(path, filt=None):
    """Mono 16 kHz signed 16-bit samples through an ffmpeg pipe."""
    cmd = [FFMPEG, "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR)]
    if filt:
        cmd += ["-af", filt]
    cmd += ["-f", "s16le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True, timeout=60).stdout
    a = array.array("h")
    a.frombytes(raw[: len(raw) // 2 * 2])
    if sys.byteorder == "big":
        a.byteswap()
    return a


def silences(path, dur=None):
    """[(start, end)] of ffmpeg silencedetect at -35 dB / 60 ms; an open silence ends at `dur`."""
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR),
                        "-af", "silencedetect=noise=-35dB:d=0.06", "-f", "null", "-"],
                       capture_output=True, text=True, timeout=60)
    out, start = [], None
    for line in r.stderr.splitlines():
        m = re.search(r"silence_start: (-?[\d.]+)", line)
        if m:
            start = max(0.0, float(m.group(1)))
        m = re.search(r"silence_end: ([\d.]+)", line)
        if m and start is not None:
            out.append((start, float(m.group(1))))
            start = None
    if start is not None and dur is not None:
        out.append((start, dur))
    return out


def gaps(sil, dur):
    """The pause measures from a silence list: gap (the spec's), gap_merged (silences split by
    under 100 ms of sound, an in-breath, count as one)."""
    inner = [(s, e) for s, e in sil if s > 0.15 * dur and e < 0.90 * dur]
    best = max(inner, key=lambda se: se[1] - se[0]) if inner else None
    merged = []
    for s, e in sil:
        if merged and s - merged[-1][1] < 0.10:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    minner = [(s, e) for s, e in merged if s > 0.15 * dur and e < 0.90 * dur]
    mbest = max(minner, key=lambda se: se[1] - se[0]) if minner else None
    return {"gap": round(best[1] - best[0], 3) if best else 0.0,
            "gap_at": round(best[0], 3) if best else None,
            "gap_merged": round(mbest[1] - mbest[0], 3) if mbest else 0.0}


def dip(x, dur):
    """Loudness-relative gap: the longest run (inside 15-90% of the clip) of 10 ms frames more
    than 20 dB below the clip's 90th-percentile frame level."""
    step = SR // 100
    lv = []
    for i in range(0, len(x) - step + 1, step):
        e = sum(v * v for v in x[i:i + step]) / float(step)
        lv.append(10 * math.log10(e) if e > 0 else -200.0)
    if not lv:
        return 0.0
    ref = sorted(lv)[int(0.9 * (len(lv) - 1))]
    best = run = 0
    for i, v in enumerate(lv):
        if v < ref - 20 and 0.15 * dur < i * 0.01 < 0.90 * dur:
            run += 1
            best = max(best, run)
        else:
            run = 0
    return round(best * 0.01, 3)


def pitch(x):
    """[(t, f0 or None, energy)] per 10 ms frame (see the module doc)."""
    n = len(x)
    P = [0]
    P.extend(itertools.accumulate(v * v for v in x))
    starts = list(range(0, max(0, n - W - LMAX), HOP))
    if not starts:
        return []
    energies = [P[s + W] - P[s] for s in starts]
    thr = 0.2 * sorted(energies)[int(0.9 * (len(energies) - 1))]
    mul = operator.mul
    frames = []
    for s, e0 in zip(starts, energies):
        t = (s + W / 2.0) / SR
        if e0 <= thr or e0 <= 0:
            frames.append((t, None, e0))
            continue
        seg = x[s:s + W]
        r = [0.0] * (LMAX + 2)
        for lag in range(LMIN - 1, LMAX + 2):
            el = P[s + lag + W] - P[s + lag]
            if el > 0:
                r[lag] = sum(map(mul, seg, x[s + lag:s + lag + W])) / math.sqrt(e0 * el)
        rmax = max(r[LMIN:LMAX + 1])
        if rmax < 0.45:
            frames.append((t, None, e0))
            continue
        pick = None
        for lag in range(LMIN, LMAX + 1):
            if r[lag] >= 0.88 * rmax and r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1]:
                pick = lag
                break
        if pick is None:
            pick = max(range(LMIN, LMAX + 1), key=lambda l: r[l])
        a, b, c = r[pick - 1], r[pick], r[pick + 1]
        den = a - 2 * b + c
        off = 0.5 * (a - c) / den if den < 0 else 0.0
        frames.append((t, SR / (pick + max(-0.5, min(0.5, off))), e0))
    ## octave fold: a frame ~0.8 octave off the clip's median is a harmonic or sub-harmonic pick
    fs = [f for t, f, e in frames if f]
    if fs:
        M = statistics.median(fs)
        for i, (t, f, e) in enumerate(frames):
            if f and f > 1.75 * M and f / 2 >= SR / LMAX:
                frames[i] = (t, f / 2, e)
            elif f and f < M / 1.75 and f * 2 <= SR / LMIN:
                frames[i] = (t, f * 2, e)
    ## a 5-frame median smooths single-frame slips
    out = list(frames)
    for i, (t, f, e) in enumerate(frames):
        if f is not None:
            win = [frames[j][1] for j in range(max(0, i - 2), min(len(frames), i + 3)) if frames[j][1] is not None]
            out[i] = (t, statistics.median(win), e)
    return out


def st(a, b):
    return 12.0 * math.log2(a / b)


def contour_measures(frames):
    """f0, end_slope_st and two helpers: end_vs_prev_st (the last 350 ms against the 350 ms
    before) and end_trend_st_per_s (a straight-line slope over the last 350 ms)."""
    voiced = [(t, f) for t, f, e in frames if f]
    out = {"f0": None, "end_slope_st": None, "end_vs_prev_st": None, "end_trend_st_per_s": None,
           "voiced_frames": len(voiced)}
    if len(voiced) < 10:
        return out
    allmed = statistics.median(f for t, f in voiced)
    out["f0"] = round(allmed, 1)
    t_last = voiced[-1][0]
    end = [f for t, f in voiced if t >= t_last - 0.35]
    prev = [f for t, f in voiced if t_last - 0.70 <= t < t_last - 0.35]
    if len(end) >= 5:
        out["end_slope_st"] = round(st(statistics.median(end), allmed), 2)
        if len(prev) >= 5:
            out["end_vs_prev_st"] = round(st(statistics.median(end), statistics.median(prev)), 2)
        pts = [(t, st(f, allmed)) for t, f in voiced if t >= t_last - 0.35]
        mt = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        sxx = sum((p[0] - mt) ** 2 for p in pts)
        if sxx:
            out["end_trend_st_per_s"] = round(sum((p[0] - mt) * (p[1] - my) for p in pts) / sxx, 1)
    return out


def measure(path, detail=False):
    """{"dur", "gap", "f0", "end_slope_st"} (None where it can't tell; never raises). With
    detail=True also gap_at, gap_merged, dip, end_vs_prev_st, end_trend_st_per_s, voiced_frames,
    and the pitch frames under "_frames" (for callers that measure more)."""
    m = {"dur": None, "gap": None, "f0": None, "end_slope_st": None}
    try:
        x = decode(path)
        if not len(x):
            raise ValueError("no audio")
        dur = len(x) / float(SR)
        m["dur"] = round(dur, 3)
        g = gaps(silences(path, dur), dur)
        m["gap"] = g["gap"]
        frames = pitch(decode(path, PITCH_BAND))
        c = contour_measures(frames)
        m["f0"], m["end_slope_st"] = c["f0"], c["end_slope_st"]
        if detail:
            m.update(g)
            m["dip"] = dip(x, dur)
            m.update({k: v for k, v in c.items() if k not in m})
            m["_frames"] = frames
    except Exception as e:  # a bad or short file: whatever was measured, None for the rest
        if detail:
            m["error"] = str(e)[:200]
    return m


def rank(paths, want):
    """The paths as [{"path", **measure(path)}], best first for `want` ("fall": most negative
    end_slope_st; "pause": largest gap; "lower": lowest f0). Unmeasurable clips go last."""
    key, big_first = WANTS[want]
    rows = [dict(measure(p), path=p) for p in paths]
    have = [r for r in rows if r.get(key) is not None]
    none = [r for r in rows if r.get(key) is None]
    have.sort(key=lambda r: r[key], reverse=big_first)
    return have + none


# ---------------------------------------------------------------- self-test

def _write_wav(path, samples, sr=SR):
    import wave
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(array.array("h", [max(-32767, min(32767, int(v))) for v in samples]).tobytes())


def _voice(f0_of_t, secs, t0=0.0):
    """A buzzy vowel-ish tone (three harmonics) whose pitch follows f0_of_t."""
    out, ph = [], 0.0
    for i in range(int(secs * SR)):
        ph += 2 * math.pi * f0_of_t(t0 + i / SR) / SR
        out.append(9000 * math.sin(ph) + 6000 * math.sin(2 * ph) + 4500 * math.sin(3 * ph))
    return out


def selftest():
    import tempfile
    import time
    ok = True
    with tempfile.TemporaryDirectory() as d:
        ## 1. a falling chirp 200 -> 100 Hz over 2 s: f0 ~150, the end ~ -5.4 st
        chirp = os.path.join(d, "chirp.wav")
        _write_wav(chirp, _voice(lambda t: 200 - 50 * t, 2.0))
        ## 2. two "sentences" (flat 130 Hz, then rising 130 -> 180) with 0.5 s of silence between
        gap = os.path.join(d, "gap.wav")
        _write_wav(gap, [0] * 1600 + _voice(lambda t: 130, 1.0) + [0] * 8000
                   + _voice(lambda t: 130 + 50 * t, 1.0) + [0] * 1600)
        ## 3. a broken file and a too-short one
        bad = os.path.join(d, "bad.mp3")
        open(bad, "wb").write(b"not audio at all")
        short = os.path.join(d, "short.wav")
        _write_wav(short, _voice(lambda t: 150, 0.02))
        t0 = time.time()
        m1, m2, m3, m4 = measure(chirp), measure(gap), measure(bad), measure(short)
        el = time.time() - t0
        checks = [
            ("chirp f0 ~150 Hz", m1["f0"] is not None and abs(m1["f0"] - 150) < 4, m1),
            ("chirp falls ~-5.4 st", m1["end_slope_st"] is not None and -6.5 < m1["end_slope_st"] < -4.5, m1),
            ("chirp has no gap", m1["gap"] == 0.0, m1),
            ("gap ~0.5 s", m2["gap"] is not None and abs(m2["gap"] - 0.5) < 0.06, m2),
            ("rising end > +2 st", m2["end_slope_st"] is not None and m2["end_slope_st"] > 2, m2),
            ("bad file -> None fields", m3 == {"dur": None, "gap": None, "f0": None, "end_slope_st": None}, m3),
            ("short file -> no f0", m4["f0"] is None, m4),
            ("rank fall puts the chirp first", [r["path"] for r in rank([gap, bad, chirp], "fall")] == [chirp, gap, bad], None),
            ("rank pause puts the gap first", rank([chirp, gap], "pause")[0]["path"] == gap, None),
        ]
        for name, good, got in checks:
            ok &= bool(good)
            print("%s  %s%s" % ("ok  " if good else "FAIL", name, "" if good else "   got %r" % (got,)))
        print("4 clips measured in %.2f s" % el)
    print("selftest", "passed" if ok else "FAILED")
    return ok


def main(argv):
    if "--selftest" in argv:
        sys.exit(0 if selftest() else 1)
    if not argv:
        print(__doc__)
        return
    import time
    for p in argv:
        t0 = time.time()
        m = measure(p)
        print("%-60s dur %6s  gap %6s  f0 %6s  end_slope_st %6s   (%.2fs)" % (
            p, m["dur"], m["gap"], m["f0"], m["end_slope_st"], time.time() - t0))


if __name__ == "__main__":
    main(sys.argv[1:])
