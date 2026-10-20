#!/usr/bin/env python3
"""VoiceStudio casting, round 2: new voices auditioned the way a casting director would, so the
owner only hears the best. From round 1 (vs_designs.py) the owner kept Varek B, Imre C and Oren A/B.
Russian came out American, one identity per commander was junk, and Hask and Quill were "boring and
flat".

For each part to recast, several seeds are rolled for each trait mix. Every voice card is scored:
- plausible: its pitch suits the gender asked for (a woman at 80 Hz is a failed design);
- alive: how far its pitch moves (the spread of the voiced pitch, 10th to 90th percentile, in
  semitones), because flat is what the owner rejected;
- right: Whisper (VoiceStudio's /transcribe) must hear the card's words. Junk transcribes as
  nothing, or as Whisper's "Thanks for watching!".
The liveliest card that is plausible and right wins. Its lines are cloned from it, 3 takes each,
the liveliest take first.

Measured against round 1's verdicts, these numbers only catch junk. The pitch spread doesn't tell
"flat" from "great": the owner's flat Hask voices spread 4.4-6.3 st, the same as Varek B (4.5) and
Imre C (5.6), while every broken voice swung 10-18 st. So the checks throw out junk, and the livelier
card scripts (CARDS) and 3 takes per line do the rest. Ears pick the performance.

Oren: the owner wants A's pitch with B's delivery. D clones from B's voice card raised to A's pitch
(rubberband, formants kept); E is B's own lines raised the same way (pure DSP); F designs a
"teenager, high pitch" voice outright.

    python3 tools/voicestudio/vs_casting.py             # cast what's missing, write the batch
    python3 tools/voicestudio/vs_casting.py --profiles  # the table's button: save the accepted voices

Free and local; needs VoiceStudio at http://127.0.0.1:3900. Batch: review/vs_cast.
"""
import difflib
import json
import os
import re
import statistics
import subprocess
import sys
import time
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "ludo"))
import vs  # noqa: E402
import vs_samples as base  # noqa: E402
import vs_designs as round1  # noqa: E402
import voice_measure  # noqa: E402

BATCH = "vs_cast"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
FFMPEG_FULL = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg" ## the one with rubberband
SEEDS = 5
TAKES = 3

## livelier scripts for the voice cards: the card's delivery is what the clones copy
CARDS = {
    "hask": "Commodore Hask, the Old Bear! Ha! Bring me your best, little general... and I will SINK it! [laughter] Plant my flag there, lads!",
    "quill": "Governor Quill, of the Company. Everything has its price... and I intend to buy the world. [laughter] Ah. A fine piece of property. I will take it.",
    "ysolde": "Viceroy Ysolde. Every land at this table will fly my banner... Guard your doors. I will take this one. Remember who chose first.",
}
## (who, id, traits): parts to recast, rolled SEEDS times each
ROLLS = [
    ("varek", "D", "male, middle-aged, very low pitch, american accent"),      ## round 1's C, which failed, again
    ("ysolde", "D", "female, middle-aged, low pitch, british accent"),
    ("ysolde", "E", "female, middle-aged, low pitch"),
    ("ysolde", "F", "female, elderly, low pitch, british accent"),
    ("quill", "D", "male, middle-aged, high pitch, british accent"),
    ("quill", "E", "male, elderly, moderate pitch, british accent"),
    ("quill", "F", "male, middle-aged, low pitch, british accent"),
    ("hask", "D", "male, elderly, very low pitch, australian accent"),
    ("hask", "E", "male, middle-aged, low pitch, british accent"),
    ("hask", "F", "male, elderly, low pitch, american accent"),
    ("oren", "F", "male, teenager, high pitch, british accent"),
]
OREN_SHIFT = None ## semitones from B up to A, measured (about +4)
RANGE = {"male": (65.0, 210.0), "female": (140.0, 340.0)}
WILD = 14.0 ## semitones: past this the voice is junk, however lively it looks


def card_text(who):
    return CARDS.get(who) or round1.card_text(who)


def plain_words(s):
    return re.findall(r"[a-z0-9']+", re.sub(r"\[[^\]]*\]", " ", (s or "").lower()))


def transcribe(path):
    """Whisper, in VoiceStudio: the words it hears."""
    body, ctype = vs._multipart({"language": "en"}, {"audio": path})
    req = urllib.request.Request(vs.URL + "/transcribe", data=body, method="POST", headers={"Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read()).get("text", "")


def heard_right(path, text):
    heard = transcribe(path)
    ratio = difflib.SequenceMatcher(None, plain_words(text), plain_words(heard)).ratio()
    return ratio, heard


def liveliness(path):
    """How far the voiced pitch moves: 10th to 90th percentile, in semitones (flat is ~2)."""
    m = voice_measure.measure(path, detail=True)
    f = sorted(x[1] for x in m.get("_frames") or [] if x[1])
    if len(f) < 20:
        return 0.0, m.get("f0")
    lo, hi = f[len(f) // 10], f[(len(f) * 9) // 10]
    return 12.0 * __import__("math").log2(hi / lo), m.get("f0")


def plausible(traits, f0):
    g = "female" if traits.startswith("female") else "male"
    lo, hi = RANGE[g]
    if "teenager" in traits or "child" in traits or "high pitch" in traits:
        hi += 110.0 ## a high-voiced boy sits well above a man (Oren F's one clean card: 268 Hz)
    return f0 is not None and lo <= f0 <= hi


def dirs(who, ident):
    d = os.path.join(BATCH_DIR, who, ident)
    os.makedirs(os.path.join(d, ".takes"), exist_ok=True)
    return d


def state():
    try:
        return json.load(open(os.path.join(BATCH_DIR, "cast.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(st):
    os.makedirs(BATCH_DIR, exist_ok=True)
    json.dump(st, open(os.path.join(BATCH_DIR, "cast.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)


def audition(who, ident, traits, st):
    """Roll SEEDS voice cards, keep the liveliest one that's plausible and heard right."""
    key = "%s.%s" % (who, ident)
    if st.get(key, {}).get("card"):
        return st[key]
    d = dirs(who, ident)
    text = card_text(who)
    cands = []
    for k in range(SEEDS):
        seed = (sum(map(ord, key)) * 131 + k * 97) % 100000
        p = os.path.join(d, "cands", "seed%d.wav" % seed)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p):
            vs.generate(text, p, instruct=traits, seed=seed)
        live, f0 = liveliness(p)
        cands.append({"seed": seed, "path": p, "live": round(live, 2), "f0": f0, "plausible": plausible(traits, f0)})
        print("  %-7s %s seed %-6d live %4.1f st  f0 %s%s" % (who, ident, seed, live, f0, "" if cands[-1]["plausible"] else "  (implausible)"), flush=True)
    chosen = None
    for c in sorted(cands, key=lambda c: (-c["plausible"], -c["live"])):
        if not c["plausible"]:
            break
        if c["live"] > WILD:
            continue ## a pitch that swings this far is a broken voice (round 1's junk: 10-18 st)
        ratio, heard = heard_right(c["path"], text)
        c["heard"], c["ratio"] = heard, round(ratio, 2)
        print("      Whisper %.0f%%: %s" % (ratio * 100, heard[:70]), flush=True)
        if ratio >= 0.8:
            chosen = c
            break
    st[key] = {"traits": traits, "candidates": cands, "card": chosen["path"] if chosen else "", "seed": chosen["seed"] if chosen else None,
               "live": chosen["live"] if chosen else None}
    if chosen:
        print("    -> %s %s: seed %d (live %.1f st, of %d)" % (who, ident, chosen["seed"], chosen["live"], len(cands)), flush=True)
    else:
        print("    -> %s %s: no card passed; roll more seeds" % (who, ident), flush=True)
    save(st)
    return st[key]


def shifted(src, out, st_up):
    subprocess.run([FFMPEG_FULL, "-v", "error", "-y", "-i", src, "-af", "rubberband=pitch=%.4f:formant=preserved" % (2 ** (st_up / 12.0)), out], check=True)


def take_file(who, ident, line, k):
    d = dirs(who, ident)
    return os.path.join(d, line + ".mp3") if k == 1 else os.path.join(d, ".takes", "%s.t%d.mp3" % (line, k))


def lines_for(who, ident, card, ref_text, seed, st):
    """3 takes of each line cloned from the card, the liveliest first."""
    for line in round1.LINES:
        if os.path.exists(take_file(who, ident, line, 1)):
            continue
        made = []
        for k in range(TAKES):
            wav = os.path.join(dirs(who, ident), "%s.k%d.wav" % (line, k))
            vs.generate(round1.speak_of(who, line), wav, ref_audio=card, ref_text=ref_text, seed=seed + 11 + k * 7)
            made.append((liveliness(wav)[0], wav))
        made.sort(key=lambda x: -x[0])
        for k, (live, wav) in enumerate(made, start=1):
            round1.finish(wav, take_file(who, ident, line, k), base.game_path(who, line))
        print("  %-7s %s %-13s 3 takes (liveliest %.1f st)" % (who, ident, line, made[0][0]), flush=True)


def cast_all():
    global OREN_SHIFT
    if not vs.health():
        print("VoiceStudio is not running at %s" % vs.URL)
        sys.exit(2)
    t0 = time.time()
    st = state()
    for who, ident, traits in ROLLS:
        a = audition(who, ident, traits, st)
        if a.get("card"):
            lines_for(who, ident, a["card"], card_text(who), int(a["seed"]), st)
    ## Oren: A's pitch, B's delivery
    fa = voice_measure.measure(os.path.join(round1.BATCH_DIR, "oren", "A", "card.ref.wav"))["f0"]
    fb = voice_measure.measure(os.path.join(round1.BATCH_DIR, "oren", "B", "card.ref.wav"))["f0"]
    OREN_SHIFT = round(12.0 * __import__("math").log2(fa / fb), 1)
    b_card = os.path.join(round1.BATCH_DIR, "oren", "B", "card.ref.wav")
    d_card = os.path.join(dirs("oren", "D"), "card.ref.wav")
    if not os.path.exists(d_card):
        shifted(b_card, d_card, OREN_SHIFT)
    b_seed = dict((i, s) for i, t, s in round1.IDENTITIES["oren"])["B"]
    st["oren.D"] = {"traits": "B's voice card raised %+.1f st to A's pitch (formants kept), cloned" % OREN_SHIFT, "card": d_card, "seed": b_seed}
    lines_for("oren", "D", d_card, round1.card_text("oren"), b_seed, st)
    e_dir = dirs("oren", "E")
    for line in ["card"] + round1.LINES:
        src = os.path.join(round1.BATCH_DIR, "oren", "B", line + ".mp3")
        out = os.path.join(e_dir, line + ".mp3")
        if os.path.exists(src) and not os.path.exists(out):
            tmp = out + ".wav"
            shifted(src, tmp, OREN_SHIFT)
            base.run("-i", tmp, "-c:a", "libmp3lame", "-q:a", 2, out)
            os.remove(tmp)
    st["oren.E"] = {"traits": "B's own lines raised %+.1f st to A's pitch (formants kept)" % OREN_SHIFT, "card": os.path.join(e_dir, "card.mp3")}
    save(st)
    print("cast in %.0f s (Oren B -> A: %+.1f st)" % (time.time() - t0, OREN_SHIFT))


def card_mp3(who, ident, st):
    """the winning voice card as an mp3 in the batch (loudness-matched to the game's greeting)"""
    out = os.path.join(dirs(who, ident), "card.mp3")
    src = st.get("%s.%s" % (who, ident), {}).get("card", "")
    if src and not os.path.exists(out) and src.endswith(".wav"):
        base.run("-i", src, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % base.lufs(base.game_path(who, "greet")),
                 "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    return out


def actions():
    me = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")
    return [{"id": "profiles", "kind": "custom", "label": "Save accepted voices in VoiceStudio",
             "help": "Every voice whose card you accepted becomes a VoiceStudio profile, to try more lines in its app. Nothing goes into the game.",
             "cmd": ["python3", me, "--profiles"]}]


def write_batch():
    st = state()
    items = []
    order = [(w, i) for w, i, t in ROLLS] + [("oren", "D"), ("oren", "E")]
    order.sort(key=lambda x: (list(round1.IDENTITIES).index(x[0]), x[1]))
    for who, ident in order:
        a = st.get("%s.%s" % (who, ident), {})
        if not a.get("card"):
            continue
        traits = a.get("traits", "")
        how = ("seed %s, the liveliest of %d (%.1f st)" % (a.get("seed"), len(a.get("candidates", [])), a["live"])) if a.get("live") else traits
        tag = "%s %s · %s" % (who.capitalize(), ident, round1.short(traits) if "," in traits and "raised" not in traits else traits)
        card = card_mp3(who, ident, st)
        rows = [("card", card, card_text(who) if ident != "E" else round1.card_text(who), "greet", "the voice card: " + how)]
        for line in round1.LINES:
            rows.append((line, take_file(who, ident, line, 1), base.text_of(who, line), line, base.CONTEXT.get(line, "")))
        for line, path, text, game_line, ctx in rows:
            sp = round1.speak_of(who, line) if line != "card" else ""
            items.append({"id": "%s.%s.%s" % (who, ident, line), "kind": "audio", "group": who,
                          "label": "%s · %s%s" % (tag, "voice card" if line == "card" else line, "  ✦ " + sp[sp.find("["):sp.find("]") + 1] if "[" in sp else ""),
                          "text": text, "file": os.path.relpath(path, BATCH_DIR).replace(os.sep, "/"),
                          "target": os.path.relpath(base.game_path(who, game_line), ROOT).replace(os.sep, "/"),
                          "meta": {"voice": "voicestudio-cast:%s" % who, "context": ctx, "speak": sp if sp and sp != base.spoken(text) else "",
                                   "engine": "VoiceStudio: " + traits, "identity": ident, "traits": traits}})
    json.dump({"batch": BATCH, "title": "VoiceStudio casting, round 2: the liveliest of 5 seeds, checked by Whisper (0 = today's voice)",
               "actions": actions(), "items": items}, open(os.path.join(BATCH_DIR, "batch.json.tmp"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    os.replace(os.path.join(BATCH_DIR, "batch.json.tmp"), os.path.join(BATCH_DIR, "batch.json"))
    print("batch: %d clips" % len(items))


def profiles():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review
    st = state()
    have = {p["name"] for p in json.loads(urllib.request.urlopen(vs.URL + "/profiles", timeout=10).read())}
    for it in review.merged_batch(BATCH)["items"]:
        if not it["id"].endswith(".card") or it["status"] != "accept":
            continue
        who, ident, _ = it["id"].split(".")
        name = "CONCURRENT · %s %s" % (round1.NAMES[who], ident)
        if name in have:
            continue
        a = st["%s.%s" % (who, ident)]
        ref = a["card"] if a["card"].endswith(".wav") else os.path.join(BATCH_DIR, who, ident, "card.mp3")
        body, ctype = vs._multipart({"name": name, "ref_text": card_text(who) if ident != "E" else round1.card_text(who), "language": "English", "kind": "clone"}, {"ref_audio": ref})
        urllib.request.urlopen(urllib.request.Request(vs.URL + "/profiles", data=body, method="POST", headers={"Content-Type": ctype}), timeout=60).read()
        print("saved", name)


if __name__ == "__main__":
    if "--profiles" in sys.argv:
        profiles()
    elif "--batch" in sys.argv:
        write_batch()
    else:
        cast_all()
        write_batch()
