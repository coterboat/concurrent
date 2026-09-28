#!/usr/bin/env python3
"""v1.11 speech lab: which TEXT conventions move Ludo's cloned-voice speech (/audio/speech)?

The endpoint takes only `text` and `sample`, so punctuation (and re-rolling) is the only lever.
Reviewers keep asking for "more pause between sentences" and "downward inflection"; this
measures what the words can do about it, on the four cloned voices.

    python3 tools/ludo/lab_speech.py              # generate what is missing, measure, write results + batch
    python3 tools/ludo/lab_speech.py --dry-run    # list the calls it would make (no credits)
    python3 tools/ludo/lab_speech.py --measure    # re-measure the clips on disk (no credits)
    python3 tools/ludo/lab_speech.py --steer      # also the sample-steering test (part 4)
    python3 tools/ludo/lab_speech.py --only pause,fall   # just these tests
    python3 tools/ludo/lab_speech.py --only pause2 --take 1 [--variants bracket,break_tag]
    python3 tools/ludo/lab_speech.py --contour review/v111_lab/fall/advisor_l1_period_t1.mp3

Tests (review/v111_lab/<test>/<voice>_<line>_<variant>_t<n>.<ext>):
  pause  the gap between two sentences: period "A. B.", ellipsis "A... B.", dash "A — B.",
         para "A.\\n\\nB."; 3 lines x 2 takes per voice. Measured: the longest silence
         (ffmpeg silencedetect -35 dB, 60 ms) that starts after 15% and ends before 90% of the clip.
  pause2 ("pause+" in the table) stronger marks on the same lines: stop_ellipsis "A. ... B.",
         double_ellipsis "A...... B.", break_tag 'A. <break time="0.8s" /> B.', bracket
         "A. [pause] B."; compared with period and ellipsis of the same line and take, and flagged
         when the clip grew by more sound than silence (the mark read aloud?).
  fall   the end of a statement: period, ellipsis, bang; 2 lines x 2 takes per voice. Measured:
         end_slope_st = median f0 of the last 350 ms of voiced frames minus the clip's median f0,
         in semitones (negative = falls). f0 by normalized autocorrelation, pure Python.
  emph   one key word: plain, *stars*, CAPS, _underscore_; 1 take. For ears (a rough level/pitch
         of the word's estimated region is recorded too).
  steer  (--steer) Ysolde cloned from her normal sample vs from an accepted "more menace" take.
Measurements come from tools/ludo/voice_measure.py (one implementation for the lab and the redo tools).

Idempotent: every call has a stable request id (a rerun never charges twice) and a clip already
on disk is skipped. Each call is recorded in assets/ludo_ledger.json (id lab111_...).
Nothing here touches the game: the review batch has no install action.
"""
import json
import math
import os
import re
import statistics
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ludo  # noqa: E402
import voice_measure as vm  # noqa: E402

ROOT = ludo.ROOT
BATCH = "v111_lab"
OUT = os.path.join(ROOT, "review", BATCH)
TITLE = "v1.11 speech lab: pauses, falls, emphasis"

VOICES = {"advisor": "voice_advisor", "varek": "voice2_varek", "ysolde": "voice2_ysolde", "quill": "voice2_quill"}

## pause: two sentences, in each character's own manner (several are real lines with a real
## "more pause" note behind them)
PAUSE_LINES = {
    "advisor": [("The line held", "Now we advance"),
                ("Orders sealed", "Now we see who flinches"),
                ("We have lost the river crossing, Commander", "We will take it back")],
    "varek": [("Fall back", "We return at dawn"),
              ("As expected", "Strike"),
              ("I have buried a hundred generals", "You will be the next")],
    "ysolde": [("Withdraw", "I will remember this"),
               ("You left it undefended", "How generous"),
               ("Kneel", "The empire is mine")],
    "quill": [("Cut our losses, lads", "Back to the ships"),
              ("Unguarded goods", "Finders keepers"),
              ("Everything has its price", "Now you pay")],
}
PAUSE_VARIANTS = {
    "period": lambda a, b: "%s. %s." % (a, b),
    "ellipsis": lambda a, b: "%s... %s." % (a, b),
    "dash": lambda a, b: "%s — %s." % (a, b),
    "para": lambda a, b: "%s.\n\n%s." % (a, b),
}

## pause2 ("pause+"): stronger marks on the same lines, against period/ellipsis of the same take
PAUSE2_VARIANTS = {
    "stop_ellipsis": lambda a, b: "%s. ... %s." % (a, b),
    "double_ellipsis": lambda a, b: "%s...... %s." % (a, b),
    "break_tag": lambda a, b: '%s. <break time="0.8s" /> %s.' % (a, b),
    "bracket": lambda a, b: "%s. [pause] %s." % (a, b),
}
PAUSE_TESTS = ("pause", "pause2")

## fall: statements whose ending should drop (the last sentence carries the variant)
FALL_LINES = {
    "advisor": ["Your call, Commander", "The capital has fallen, Commander"],
    "varek": ["A setback. They will pay for it in blood", "The world is mine. It always was"],
    "ysolde": ["You will pay for that", "Every land at this table will fly my banner"],
    "quill": ["Nobody leaves my shop without paying", "The market has turned, lads"],
}
FALL_VARIANTS = {
    "period": lambda s: s + ".",
    "ellipsis": lambda s: s + "...",
    "bang": lambda s: s + "!",
}

## emph: one word that a reviewer would want leaned on
EMPH_LINES = {
    "advisor": ("We always hold the line", "always"),
    "varek": ("You will not keep it", "not"),
    "ysolde": ("That is my capital", "my"),
    "quill": ("Now you pay for it", "pay"),
}
EMPH_VARIANTS = {
    "plain": lambda w: w,
    "stars": lambda w: "*%s*" % w,
    "caps": lambda w: w.upper(),
    "italic_underscore": lambda w: "_%s_" % w,
}

## steer: does an emotional sample carry its emotion? (Ysolde's accepted "more menace" take)
STEER_LINES = ["Guard your doors. I am coming for them.", "Run, if you like. I will find you."]
STEER_SAMPLE_FILE = "assets/voice13/ysolde/retreat_v2.mp3"
STEER_VARIANTS = ["sample_normal", "sample_retreat_v2"]


def clips(tests, steer=False):
    """Every clip of the lab: dicts with test, who, line, variant, take, text, (sample)."""
    out = []
    if "pause" in tests:
        for who, lines in PAUSE_LINES.items():
            for li, (a, b) in enumerate(lines, 1):
                for var, fn in PAUSE_VARIANTS.items():
                    for t in (1, 2):
                        out.append(dict(test="pause", who=who, line="l%d" % li, variant=var, take=t, text=fn(a, b)))
    if "pause2" in tests:
        for who, lines in PAUSE_LINES.items():
            for li, (a, b) in enumerate(lines, 1):
                for var, fn in PAUSE2_VARIANTS.items():
                    for t in (1, 2):
                        out.append(dict(test="pause2", who=who, line="l%d" % li, variant=var, take=t, text=fn(a, b)))
    if "fall" in tests:
        for who, lines in FALL_LINES.items():
            for li, s in enumerate(lines, 1):
                for var, fn in FALL_VARIANTS.items():
                    for t in (1, 2):
                        out.append(dict(test="fall", who=who, line="l%d" % li, variant=var, take=t, text=fn(s)))
    if "emph" in tests:
        for who, (s, w) in EMPH_LINES.items():
            for var, fn in EMPH_VARIANTS.items():
                text = re.sub(r"\b%s\b" % re.escape(w), fn(w), s, count=1) + "."
                out.append(dict(test="emph", who=who, line="l1", variant=var, take=1, text=text, word=w))
    if steer:
        for li, s in enumerate(STEER_LINES, 1):
            for var in STEER_VARIANTS:
                for t in (1, 2):
                    out.append(dict(test="steer", who="ysolde", line="l%d" % li, variant=var, take=t, text=s))
    for c in out:
        c["name"] = "%s_%s_%s_t%d" % (c["who"], c["line"], c["variant"], c["take"])
        c["rid"] = "concurrent-lab111-%s-%s-%s-%s-t%d" % (c["test"], c["who"], c["line"], c["variant"], c["take"])
        c["aid"] = "lab111_%s_%s_%s_%s_t%d" % (c["test"], c["who"], c["line"], c["variant"], c["take"])
        c["base"] = os.path.join(OUT, c["test"], c["name"])
    return out


# ---------------------------------------------------------------- generation

ERRORS = {}


def sample_for(c):
    if c["test"] == "steer" and c["variant"] == "sample_retreat_v2":
        return ludo.local_image(STEER_SAMPLE_FILE)  ## a base64 data URI (audio/mpeg)
    return ludo.ledger_url(VOICES[c["who"]])


def generate(c):
    have = ludo.existing(c["base"])
    if have:
        return have
    params = {"text": c["text"], "sample": sample_for(c)}
    try:
        job = ludo.run_job("/audio/speech", params, c["rid"])
    except Exception as e:  # keep the rest of the lab moving; the error is a result too
        ERRORS[c["name"] + ":" + c["test"]] = str(e)[:400]
        ludo.log("FAIL", c["test"], c["name"], str(e)[:200])
        return None
    url = ludo.result_urls(job["result"])[0]
    dest = c["base"] + ludo.ext_of(url, ".mp3")
    ludo.download(url, dest)
    real = ludo.sniff(dest)
    if real and not dest.endswith(real):
        os.replace(dest, c["base"] + real)
        dest = c["base"] + real
    shown = dict(params)
    if shown["sample"].startswith("data:"):
        shown["sample"] = shown["sample"][:40] + "...(base64 of %s)" % STEER_SAMPLE_FILE
    ludo.record({"id": c["aid"], "v": 1, "endpoint": "/audio/speech", "params": shown, "job": job.get("id"),
                 "credits": job.get("credits_charged"), "url": url, "file": os.path.relpath(dest, ROOT)})
    ludo.log("done", c["test"], c["name"], "credits", job.get("credits_charged"))
    return dest


# ---------------------------------------------------------------- measurement
## one implementation: tools/ludo/voice_measure.py (the redo tools rank takes with it too)

LAB_KEYS = {"dur": "duration_s", "gap": "gap_s", "gap_at": "gap_at_s", "gap_merged": "gap_merged_s",
            "dip": "dip_s", "f0": "f0_median_hz"}  ## the lab's names for the module's measures


def emph_measures(c, frames):
    """Rough: map the key word's character span onto the speech span (first to last frame above
    the energy gate) and compare its level and pitch with the rest of the line."""
    plain = c["text"].replace("*", "").replace("_", "")
    m = re.search(r"\b%s\b" % re.escape(c["word"]), plain, re.I)
    if not m or not frames:
        return {}
    en = [e for t, f, e in frames]
    q = sorted(en)[int(0.9 * (len(en) - 1))]
    live = [i for i, e in enumerate(en) if e > 0.02 * q]
    if not live:
        return {}
    t0, t1 = frames[live[0]][0], frames[live[-1]][0]
    L = float(len(plain.rstrip(".")))
    a = t0 + (t1 - t0) * max(0.0, m.start() / L - 0.04)
    b = t0 + (t1 - t0) * min(1.0, m.end() / L + 0.04)
    inw = [(f, e) for t, f, e in frames if a <= t <= b and e > 0.02 * q]
    rest = [(f, e) for t, f, e in frames if (t0 <= t < a or b < t <= t1) and e > 0.02 * q]
    if not inw or not rest:
        return {}
    db = lambda xs: 10 * math.log10(max(1e-9, sum(xs) / len(xs)))
    out = {"word_region_s": [round(a, 2), round(b, 2)],
           "word_gain_db": round(db([e for f, e in inw]) - db([e for f, e in rest]), 2),
           "word_peak_db": round(10 * math.log10(max(e for f, e in inw) / max(e for f, e in rest)), 2)}
    fw = [f for f, e in inw if f]
    fr = [f for f, e in rest if f]
    if len(fw) >= 3 and len(fr) >= 3:
        out["word_f0_st"] = round(vm.st(statistics.median(fw), statistics.median(fr)), 2)
    return out


def measure(c, path):
    m = vm.measure(path, detail=True)
    if m.get("error"):
        raise RuntimeError(m["error"])
    fr = m.pop("_frames", [])
    out = {LAB_KEYS.get(k, k): v for k, v in m.items()}
    if c["test"] not in PAUSE_TESTS:
        for k in ("gap_s", "gap_at_s", "gap_merged_s", "dip_s"):
            out.pop(k, None)
    if c["test"] == "emph":
        out.update(emph_measures(c, fr))
    return out


def contour(path):
    fr = vm.pitch(vm.decode(path, vm.PITCH_BAND))
    for t, f, e in fr:
        bar = "#" * int((f - 60) / 5) if f else ""
        print("%5.2f  %6s  %s" % (t, "%.0f" % f if f else "-", bar))
    print(vm.contour_measures(fr))


# ---------------------------------------------------------------- analysis

def agg(vals):
    v = [x for x in vals if x is not None]
    if not v:
        return None
    return {"n": len(v), "mean": round(statistics.mean(v), 3), "median": round(statistics.median(v), 3),
            "sd": round(statistics.pstdev(v), 3)}


MEASURES = {  # test -> (baseline variant, [measures]; the first is the headline)
    "pause": ("period", ["gap_s", "gap_merged_s", "dip_s", "duration_s"]),  ## pause and pause2 together
    "fall": ("period", ["end_slope_st", "end_vs_prev_st", "end_trend_st_per_s", "f0_median_hz", "duration_s"]),
    "emph": ("plain", ["word_gain_db", "word_peak_db", "word_f0_st", "duration_s"]),
    "steer": ("sample_normal", ["f0_median_hz", "end_slope_st", "duration_s"]),
}


def analyse(rows):
    out = {}
    for test, (base, keys) in MEASURES.items():
        tests = PAUSE_TESTS if test == "pause" else (test,)
        rs = [r for r in rows if r["test"] in tests and r.get("measured")]
        if not rs:
            continue
        bases = [base] + (["ellipsis"] if test == "pause" else [])
        variants = list(dict.fromkeys(r["variant"] for r in rs))
        voices = list(dict.fromkeys(r["who"] for r in rs))
        res = {"baseline": base, "headline": keys[0], "variants": {}}
        ## the baseline's median duration per voice+line, for the read-aloud flag
        basedur = {}
        for r in rs:
            if r["variant"] == base:
                basedur.setdefault((r["who"], r["line"]), []).append(r["measured"]["duration_s"])
        for var in variants:
            vr = [r for r in rs if r["variant"] == var]
            d = {}
            for key in keys:
                idx = {(r["who"], r["line"], r["variant"], r["take"]): r["measured"].get(key) for r in rs}
                k = {"all": agg([r["measured"].get(key) for r in vr]),
                     "per_voice": {w: agg([r["measured"].get(key) for r in vr if r["who"] == w]) for w in voices}}
                ## take-to-take spread: |t1 - t2| on the same text
                spread = []
                for r in vr:
                    if r["take"] == 1:
                        a, b = idx.get((r["who"], r["line"], var, 1)), idx.get((r["who"], r["line"], var, 2))
                        if a is not None and b is not None:
                            spread.append(abs(a - b))
                k["take_spread"] = agg(spread)
                ## paired against the baseline (and, for pauses, the plain ellipsis) on the same
                ## voice, line and take number
                for bi, bv in enumerate(bases):
                    if var == bv:
                        continue
                    deltas = []
                    for r in vr:
                        a = r["measured"].get(key)
                        b0 = idx.get((r["who"], r["line"], bv, r["take"]))
                        if a is not None and b0 is not None:
                            deltas.append(a - b0)
                    kk = "vs_base" if bi == 0 else "vs_" + bv
                    k[kk] = agg(deltas)
                    if deltas:
                        k[kk]["share_above"] = round(sum(1 for x in deltas if x > 0) / len(deltas), 2)
                        k[kk]["share_below"] = round(sum(1 for x in deltas if x < 0) / len(deltas), 2)
                d[key] = k
            flags = []
            for r in vr:
                bd = basedur.get((r["who"], r["line"]))
                if bd and r["measured"]["duration_s"] > 1.6 * statistics.median(bd):
                    flags.append(r["name"])
            d["duration_outliers"] = flags
            if test == "pause":
                ## read aloud? the clip grew by more sound than silence against the period take
                ## of the same line and take (a spoken "pause" or "break" adds ~0.3 s of voice)
                sus = []
                pm = {(r["who"], r["line"], r["take"]): r["measured"] for r in rs if r["variant"] == base}
                for r in vr:
                    p0 = pm.get((r["who"], r["line"], r["take"]))
                    if p0 and var != base:
                        extra = (r["measured"]["duration_s"] - p0["duration_s"]) - (r["measured"]["gap_s"] - p0["gap_s"])
                        if extra > 0.35:
                            sus.append("%s (+%.2fs sound)" % (r["name"], extra))
                d["sound_added"] = sus
            res["variants"][var] = d
        out[test] = res
    return out


def print_summary(an):
    nan = float("nan")
    for test, res in an.items():
        print("\n== %s (baseline %s)" % (test, res["baseline"]))
        keys = [k for k in next(iter(res["variants"].values())) if k not in ("duration_outliers", "sound_added")]
        for key in keys:
            print("  -- %s" % key)
            for var, d in res["variants"].items():
                k = d[key]
                a = k["all"] or {}
                sp = k.get("take_spread") or {}
                extra = ""
                for kk in [x for x in k if x.startswith("vs_")]:
                    vb = k[kk]
                    if vb:
                        extra += "  %s %+.3f (med %+.3f, up %.0f%%)" % (
                            res["baseline"] if kk == "vs_base" else kk[3:], vb["mean"], vb["median"], 100 * vb["share_above"])
                print("    %-18s mean %8.3f median %8.3f sd %7.3f n=%-3s spread %s%s" % (
                    var, a.get("mean", nan), a.get("median", nan), a.get("sd", nan), a.get("n"),
                    "%.3f" % sp["mean"] if sp else "-", extra))
                print("    %-18s   %s" % ("", "  ".join(
                    "%s %.3f" % (w, v["mean"]) for w, v in k["per_voice"].items() if v)))
        for var, d in res["variants"].items():
            if d["duration_outliers"]:
                print("  OUTLIERS %s: %s" % (var, ", ".join(d["duration_outliers"])))
            if d.get("sound_added"):
                print("  SOUND ADDED %s: %s" % (var, ", ".join(d["sound_added"])))


# ---------------------------------------------------------------- the review batch

def write_batch(rows):
    items = []
    for r in rows:
        if r["take"] != 1 or not r.get("file"):
            continue
        items.append({"id": "%s.%s.%s.%s" % (r["test"], r["who"], r["line"], r["variant"]), "kind": "audio",
                      "group": "pause+" if r["test"] == "pause2" else r["test"],
                      "label": "%s · %s · %s · take 1" % (r["who"], r["line"], r["variant"]),
                      "text": r["text"].replace("\n", "⏎"), "file": os.path.relpath(r["file"], OUT),
                      "meta": {"voice": VOICES[r["who"]], "test": r["test"], "variant": r["variant"],
                               "measured": {k: v for k, v in (r.get("measured") or {}).items() if k != "silences"}}})
    ## one harmless action, so the table does not offer its built-in "Install accepted":
    ## nothing in this lab belongs in the game
    actions = [{"id": "remeasure", "kind": "measure", "label": "Re-measure (no credits)",
                "help": "Re-run the silence and pitch measurements on these clips; no Ludo calls, installs nothing",
                "cmd": ["python3", "tools/ludo/lab_speech.py", "--measure"]}]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "batch.json")
    with open(path + ".tmp", "w") as f:
        json.dump({"batch": BATCH, "title": TITLE, "actions": actions, "items": items}, f, indent=1, ensure_ascii=False)
    os.replace(path + ".tmp", path)
    print("batch: %d items -> %s" % (len(items), os.path.relpath(path, ROOT)))


def main(argv):
    if "--contour" in argv:
        contour(argv[argv.index("--contour") + 1])
        return
    tests = ["pause", "fall", "emph"]
    if "--only" in argv:
        tests = argv[argv.index("--only") + 1].split(",")
    steer = "--steer" in argv or "steer" in tests
    todo = clips(tests, steer)
    if "--take" in argv:
        todo = [c for c in todo if c["take"] == int(argv[argv.index("--take") + 1])]
    if "--variants" in argv:
        keep = argv[argv.index("--variants") + 1].split(",")
        todo = [c for c in todo if c["variant"] in keep]
    if "--dry-run" in argv:
        missing = [c for c in todo if not ludo.existing(c["base"])]
        for c in missing:
            print(c["rid"], repr(c["text"]))
        print("%d clips, %d missing (about %d credits)" % (len(todo), len(missing), len(missing)))
        return
    if "--measure" not in argv:
        ludo.KEY = ludo.api_key()
        jobs = 4
        if "--jobs" in argv:
            jobs = int(argv[argv.index("--jobs") + 1])
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            list(ex.map(generate, todo))
    ## measure everything on disk (every test, so a partial run keeps the others' results)
    everything = clips(["pause", "pause2", "fall", "emph"], True)
    rows = []
    for c in everything:
        path = ludo.existing(c["base"])
        row = {k: c[k] for k in ("test", "who", "line", "variant", "take", "text", "name", "rid")}
        row["voice"] = VOICES[c["who"]]
        if c.get("word"):
            row["word"] = c["word"]
        err = ERRORS.get(c["name"] + ":" + c["test"])
        if err:
            row["error"] = err
        if path:
            row["file"] = path
            try:
                row["measured"] = measure(c, path)
            except Exception as e:
                row["measure_error"] = str(e)[:300]
            row["file"] = os.path.relpath(path, ROOT)
        elif not err:
            continue
        rows.append(row)
    ## identical takes? (same bytes = the endpoint cached the text)
    import hashlib
    digest = {}
    for r in rows:
        if r.get("file"):
            digest[(r["test"], r["name"])] = hashlib.md5(open(os.path.join(ROOT, r["file"]), "rb").read()).hexdigest()
    same = [n for (t, n), h in digest.items() if n.endswith("_t1") and digest.get((t, n[:-1] + "2")) == h]
    an = analyse(rows)
    prev = {}
    rpath = os.path.join(OUT, "results.json")
    if os.path.exists(rpath):
        prev = json.load(open(rpath))
    errors = dict(prev.get("errors", {}))
    errors.update(ERRORS)
    json.dump({"title": TITLE, "clips": rows, "summary": an, "identical_takes": same, "errors": errors},
              open(rpath, "w"), indent=1, ensure_ascii=False)
    for r in rows:
        if r.get("file"):
            r["file"] = os.path.join(ROOT, r["file"])
    write_batch(rows)
    print_summary(an)
    if same:
        print("\nidentical take pairs:", same)
    if errors:
        print("\nerrors:", json.dumps(errors, indent=1)[:2000])
    print("results -> %s" % os.path.relpath(rpath, ROOT))


if __name__ == "__main__":
    main(sys.argv[1:])
