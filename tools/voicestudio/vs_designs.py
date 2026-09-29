#!/usr/bin/env python3
"""VoiceStudio designs: new voices for the commanders, made from a description alone (OmniVoice's
voice design: gender, age, pitch, accent, whisper, and a seed that picks the person). None of our
current audio goes in.

Each commander gets three candidate identities. An identity first records a voice card (its
greeting and one more line, designed from the traits), and that card is then the reference its
other lines are cloned from, so every line is the same person. A few lines show off OmniVoice's
tags ([laughter], [sigh], [surprise-oh]…). In the review table each identity is a row per line,
grouped by commander; `0` plays the line as the game has it now.

    python3 tools/voicestudio/vs_designs.py              # make what's missing, write the batch
    python3 tools/voicestudio/vs_designs.py --profiles   # the table's button: save the identities
                                                         #   whose voice card you accepted in VoiceStudio

This is an audition, not an install: pick the identities you like here, and a full set of their
lines (3 takes each) is the next step. Free and local; needs VoiceStudio at http://127.0.0.1:3900.
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import vs  # noqa: E402
import vs_samples as base  # noqa: E402

BATCH = "vs_designs"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
NAMES = {"varek": "Grand Marshal Varek", "ysolde": "Viceroy Ysolde", "quill": "Governor Quill",
         "oren": "Captain Oren", "hask": "Commodore Hask", "imre": "Admiral Imre"}

## who -> [(identity, OmniVoice traits, seed)]: three people to audition for each part
IDENTITIES = {
    "varek": [("A", "male, elderly, very low pitch, russian accent", 101),
              ("B", "male, elderly, low pitch, british accent", 202),
              ("C", "male, middle-aged, very low pitch, american accent", 303)],
    "ysolde": [("A", "female, middle-aged, low pitch, russian accent", 111),
               ("B", "female, middle-aged, low pitch, british accent", 212),
               ("C", "female, middle-aged, low pitch, whisper, russian accent", 313)],
    "quill": [("A", "male, middle-aged, moderate pitch, british accent", 121),
              ("B", "male, elderly, high pitch, british accent", 222),
              ("C", "male, middle-aged, low pitch, american accent", 323)],
    "oren": [("A", "male, young adult, moderate pitch, british accent", 131),
             ("B", "male, teenager, moderate pitch, british accent", 232),
             ("C", "male, young adult, high pitch, american accent", 333)],
    "hask": [("A", "male, elderly, very low pitch, british accent", 141),
             ("B", "male, middle-aged, low pitch, australian accent", 242),
             ("C", "male, elderly, low pitch, russian accent", 343)],
    "imre": [("A", "female, middle-aged, moderate pitch, british accent", 151),
             ("B", "female, young adult, low pitch, american accent", 252),
             ("C", "female, elderly, low pitch, british accent", 353)],
}
LINES = ["taunt", "win", "lose", "capital_took"]
CARD_EXTRA = "claim" ## the voice card: the greeting, then this line (7-9 s to clone from)
## what OmniVoice can do beyond words: one line per commander carries a tag
TAGS = {
    ("hask", "capital_took"): lambda t: t.replace("Ha ha!", "[laughter]"),
    ("quill", "capital_took"): lambda t: t + " [laughter]",
    ("oren", "lose"): lambda t: "[surprise-oh] " + t,
    ("varek", "lose"): lambda t: "[dissatisfaction-hnn] " + t,
    ("ysolde", "lose"): lambda t: "[sigh] " + t,
    ("imre", "win"): lambda t: "[confirmation-en] " + t,
}


def short(traits):
    return traits.replace(" pitch", "").replace(" accent", "").replace("middle-aged", "middle-aged")


def card_path(who, ident):
    return os.path.join(BATCH_DIR, who, ident, "card.mp3")


def line_path(who, ident, line):
    return os.path.join(BATCH_DIR, who, ident, line + ".mp3")


def card_text(who):
    return base.spoken(base.text_of(who, "greet")) + " " + base.spoken(base.text_of(who, CARD_EXTRA))


def speak_of(who, line):
    t = base.spoken(base.text_of(who, line))
    f = TAGS.get((who, line))
    return f(t) if f else t


def finish(wav, out, match):
    """loudness-match to the game's take of the line (so `0` is a fair comparison), then mp3"""
    target = base.lufs(match) if os.path.exists(match) else -18.0
    base.run("-i", wav, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % target, "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    os.remove(wav)


def make_identity(who, ident, traits, seed):
    made = 0
    d = os.path.join(BATCH_DIR, who, ident)
    os.makedirs(d, exist_ok=True)
    card = card_path(who, ident)
    card_wav = os.path.join(d, "card.ref.wav") ## the 24 kHz original, kept: every line is cloned from it
    if not os.path.exists(card_wav):
        info = vs.generate(card_text(who), card_wav, instruct=traits, seed=seed)
        print("  %-7s %s  voice card (%s, seed %d): %.1f s in %.1f s" % (who, ident, traits, seed, info["duration"], info["gen_time"]), flush=True)
        made += 1
    if not os.path.exists(card):
        base.run("-i", card_wav, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % base.lufs(base.game_path(who, "greet")),
                 "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, card)
    for line in LINES:
        out = line_path(who, ident, line)
        if os.path.exists(out):
            continue
        wav = out + ".wav"
        info = vs.generate(speak_of(who, line), wav, ref_audio=card_wav, ref_text=card_text(who), seed=seed + 7)
        finish(wav, out, base.game_path(who, line))
        print("  %-7s %s  %-13s %.1f s in %.1f s" % (who, ident, line, info["duration"], info["gen_time"]), flush=True)
        made += 1
    return made


def generate_all():
    if not vs.health():
        print("VoiceStudio is not running at %s: start it, then run this again." % vs.URL)
        sys.exit(2)
    t0 = time.time()
    made = 0
    for who, ids in IDENTITIES.items():
        for ident, traits, seed in ids:
            made += make_identity(who, ident, traits, seed)
    print("made %d clips in %.0f s" % (made, time.time() - t0))


def actions():
    me = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")
    return [{"id": "profiles", "kind": "custom", "label": "Save accepted voices in VoiceStudio",
             "help": "Every identity whose voice card you accepted becomes a VoiceStudio profile (\"CONCURRENT · Varek B …\"), "
                     "to try more lines with in its app. Nothing goes into the game.",
             "cmd": ["python3", me, "--profiles"]}]


def write_batch():
    items = []
    for who, ids in IDENTITIES.items():
        for ident, traits, seed in ids:
            tag = "%s %s · %s" % (who.capitalize(), ident, short(traits))
            rows = [("card", card_path(who, ident), card_text(who), "greet", "the voice card, designed from the traits alone: its greeting")]
            for line in LINES:
                rows.append((line, line_path(who, ident, line), base.text_of(who, line), line, base.CONTEXT.get(line, "")))
            for line, path, text, game_line, ctx in rows:
                sp = speak_of(who, line) if line != "card" else ""
                items.append({"id": "%s.%s.%s" % (who, ident, line), "kind": "audio", "group": who,
                              "label": "%s · %s%s" % (tag, "voice card" if line == "card" else line, "  ✦ " + sp[sp.find("["):sp.find("]") + 1] if "[" in sp else ""),
                              "text": text, "file": os.path.relpath(path, BATCH_DIR).replace(os.sep, "/"),
                              "target": os.path.relpath(base.game_path(who, game_line), ROOT).replace(os.sep, "/"),
                              "meta": {"voice": "voicestudio-design:%s" % who, "context": ctx, "speak": sp if sp and sp != base.spoken(text) else "",
                                       "engine": "VoiceStudio voice design: %s, seed %d" % (traits, seed), "identity": ident, "traits": traits, "seed": seed}})
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    json.dump({"batch": BATCH, "title": "VoiceStudio designs: three new voices for each commander, from a description (0 = today's voice)",
               "actions": actions(), "items": items}, open(out + ".tmp", "w"), indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    print("batch: %d clips (%d made)" % (len(items), sum(1 for it in items if os.path.exists(os.path.join(BATCH_DIR, it["file"])))))


def profiles():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review
    mb = review.merged_batch(BATCH)
    have = {p["name"] for p in json.loads(urllib.request.urlopen(vs.URL + "/profiles", timeout=10).read())}
    n = 0
    for it in mb["items"]:
        if not it["id"].endswith(".card") or it["status"] != "accept":
            continue
        who, ident, _ = it["id"].split(".")
        name = "CONCURRENT · %s %s (%s)" % (NAMES[who], ident, short(it["meta"]["traits"]))
        if name in have:
            print("have", name)
            continue
        body, ctype = vs._multipart({"name": name, "ref_text": card_text(who), "language": "English", "kind": "clone"},
                                    {"ref_audio": os.path.join(BATCH_DIR, who, ident, "card.ref.wav")})
        req = urllib.request.Request(vs.URL + "/profiles", data=body, method="POST", headers={"Content-Type": ctype})
        urllib.request.urlopen(req, timeout=60).read()
        print("saved", name)
        n += 1
    print("%d voice%s saved in VoiceStudio" % (n, "" if n == 1 else "s"))


if __name__ == "__main__":
    if "--profiles" in sys.argv:
        profiles()
    elif "--batch" in sys.argv:
        write_batch()
    else:
        generate_all()
        write_batch()
