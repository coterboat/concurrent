#!/usr/bin/env python3
"""ElevenLabs v4 samples (batch `el_samples`): is it worth taking the voices there?

Two kinds of voice, 4 lines each (the lines of the VoiceStudio first pass), 3 takes each:
- clones: the advisor and every commander, cloned from about 40 s of the game's own takes of that
  voice (whatever the game has now), plus Imre C (the VoiceStudio design the owner is keeping);
- designs: a new voice per commander from a description (the cast in docs/PROMPTING.md). A design
  gives 3 voice cards; all three are in the table, and the first one speaks the lines. The advisor
  gets no design: her cloned voice is the one we keep.

In the review table `0` plays the line as the game has it now; each take is loudness-matched to it.

    python3 tools/elevenlabs/el_samples.py --plan   # what it would make, the characters, the cost; no calls
    python3 tools/elevenlabs/el_samples.py          # make what's missing (checks the credits first)

Clones are deleted from the ElevenLabs account once their lines are made (they're rebuilt from the
same takes any time, and a plan has few voice slots); designs are kept, named "CONCURRENT · …".
Needs ELEVENLABS_API_KEY in .env.local (tools/elevenlabs/el.py --account checks it).
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "voicestudio"))
import el  # noqa: E402
import vs_samples as base  # noqa: E402
import vs_lines  # noqa: E402

BATCH = "el_samples"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
TAKES = 3
REF_SECONDS = 40.0
FFPROBE = "/opt/homebrew/bin/ffprobe"
LINES = base.LINES
NAMES = {"advisor": "the advisor", "varek": "Grand Marshal Varek", "ysolde": "Viceroy Ysolde", "quill": "Governor Quill",
         "oren": "Captain Oren", "hask": "Commodore Hask", "imre": "Admiral Imre"}
## new voices, by docs/PROMPTING.md's cast (what each wants, and what to keep away from)
DESIGNS = {
    "varek": "An elderly British field marshal of the Napoleonic wars. A deep, gravelly baritone, cold and stoic. "
             "He speaks slowly, with weight and long pauses, and every sentence falls to a low, final close, like a verdict. "
             "Clipped and unhurried; never warm, never raised.",
    "ysolde": "A middle-aged imperial viceroy, a woman with a low, cold, velvety voice and a faint Eastern European accent. "
              "Menacing and controlled, she lingers on possessive words like 'my' and 'mine'. Quiet contempt, never bright or friendly.",
    "quill": "A smug, middle-aged British colonial company governor: a merchant clerk turned conqueror. A precise, slightly "
             "nasal voice, pleased with himself, relishing every word about money. Each phrase descends at its end; no rising questions.",
    "oren": "A cocky British cavalry captain of noble birth, a young man in his twenties: eager, boastful and smarmy, a bit "
            "of a show-off. An upper-class accent and a quick, excited delivery that runs away with him. Swagger, not heroism.",
    "hask": "A loud, salty old sea commodore called the Old Bear. A booming, gravelly, rough-edged West Country voice, "
            "belly laughs, shouted orders, full of gusto and sudden anger. Never polite, never quiet.",
    "imre": "A calm elderly female admiral. A low, precise British voice, clipped and utterly confident, with a small "
            "calculating pause before each verdict. Cool and exact; never hesitant.",
}


def duration(path):
    r = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


def game_dir(who):
    return os.path.join(ROOT, "assets", "voice" if who == "advisor" else "voice13", who)


def refs(who, sid):
    """[files], seconds: about REF_SECONDS of this voice. The game's own takes (greeting first), or
    for Imre C its voice card and the takes of it the owner accepted in vs_lines."""
    if sid == "clone":
        names = sorted(f for f in os.listdir(game_dir(who)) if f.endswith(".mp3") and not f.startswith("_"))
        names.sort(key=lambda f: (not f.startswith(("greet", "welcome")), f))
        files = [os.path.join(game_dir(who), f) for f in names]
    else:
        files = [os.path.join(ROOT, "review", "vs_designs", who, sid, "card.mp3")]
        try:
            rv = json.load(open(os.path.join(ROOT, "review", "vs_lines", "review.json"), encoding="utf-8"))["items"]
        except (OSError, ValueError):
            rv = {}
        for aid, v in sorted(rv.items()):
            if aid.startswith("%s.%s." % (who, sid)) and v.get("verdict") == "accept":
                p = os.path.join(ROOT, "review", "vs_lines", v.get("pick") or "%s/%s/%s.mp3" % (who, sid, aid.split(".", 2)[2]))
                if os.path.exists(p):
                    files.append(p)
    out, total = [], 0.0
    for f in files:
        if total >= REF_SECONDS:
            break
        d = duration(f)
        if d > 0.5:
            out.append(f)
            total += d
    return out, total


def voices():
    """[(who, set, kind, label)] in the order they're made"""
    out = [("advisor", "clone", "clone", "clone of the game's voice")]
    for who in ["varek", "ysolde", "quill", "oren", "hask", "imre"]:
        out.append((who, "clone", "clone", "clone of the game's voice"))
        if who == "imre":
            out.append((who, "C", "clone", "clone of VoiceStudio's Imre C"))
        out.append((who, "design", "design", "new voice (ElevenLabs design)"))
    return out


def card_text(who):
    t = base.spoken(base.text_of(who, "greet")) + " " + base.spoken(base.text_of(who, "claim"))
    if len(t) < 100:
        t += " " + base.spoken(base.text_of(who, "taunt"))
    return t[:1000]


def take_path(who, sid, name, k):
    d = os.path.join(BATCH_DIR, who, sid)
    return os.path.join(d, name + ".mp3") if k == 1 else os.path.join(d, ".takes", "%s.t%d.mp3" % (name, k))


def speak_text(who, name):
    return vs_lines.speak_for(who, name, base.text_of(who, name), {}, "")


def plan_chars():
    n = 0
    for who, sid, kind, _ in voices():
        n += sum(len(speak_text(who, name)) * TAKES for name in LINES[who])
        if kind == "design":
            n += len(card_text(who))
    return n


def state():
    try:
        return json.load(open(os.path.join(BATCH_DIR, "state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(st):
    os.makedirs(BATCH_DIR, exist_ok=True)
    p = os.path.join(BATCH_DIR, "state.json")
    json.dump(st, open(p + ".tmp", "w", encoding="utf-8"), indent=1)
    os.replace(p + ".tmp", p)


def finish(mp3_bytes, out, match):
    """loudness-matched to the game's take of the line, so `0` is a fair comparison"""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    raw = out + ".raw.mp3"
    with open(raw, "wb") as f:
        f.write(mp3_bytes)
    target = base.lufs(match) if os.path.exists(match) else -18.0
    base.run("-i", raw, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % target, "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    os.remove(raw)


def make_voice(who, sid, kind, st):
    key = "%s.%s" % (who, sid)
    ent = st.setdefault(key, {})
    if all(os.path.exists(take_path(who, sid, n, k)) for n in LINES[who] for k in range(1, TAKES + 1)) and (kind == "clone" or ent.get("cards")):
        return
    if not ent.get("voice_id"):
        if kind == "clone":
            files, secs = refs(who, sid)
            ent["voice_id"] = el.clone("CONCURRENT · %s (%s, sample)" % (NAMES[who], sid), files,
                                       "Cloned from %d of the game's takes (%.0f s)" % (len(files), secs))
            ent.update({"refs": [os.path.relpath(f, ROOT) for f in files], "ref_seconds": round(secs, 1)})
            print("  %-8s %-6s cloned from %d takes, %.0f s" % (who, sid, len(files), secs), flush=True)
        else:
            previews = el.design(DESIGNS[who], card_text(who), seed=sum(map(ord, who)) * 97)
            ent["cards"] = []
            for i, (gid, audio) in enumerate(previews, start=1):
                out = os.path.join(BATCH_DIR, who, sid, "card%d.mp3" % i)
                finish(audio, out, base.game_path(who, "greet"))
                ent["cards"].append({"generated_voice_id": gid, "file": os.path.relpath(out, BATCH_DIR)})
            ent["voice_id"] = el.save_design("CONCURRENT · %s (ElevenLabs design)" % NAMES[who], DESIGNS[who], previews[0][0])
            print("  %-8s design: %d voice cards; card 1 saved as a voice" % (who, len(previews)), flush=True)
        save(st)
    for name in LINES[who]:
        text = speak_text(who, name)
        for k in range(1, TAKES + 1):
            out = take_path(who, sid, name, k)
            if os.path.exists(out):
                continue
            seed = base.seed_of("%s.%s.%s" % (who, sid, name), 1, k)
            finish(el.speak(ent["voice_id"], text, seed=seed), out, base.game_path(who, name))
            ent.setdefault("chars", 0)
            ent["chars"] += len(text)
            save(st)
        print("  %-8s %-6s %-13s %d takes" % (who, sid, name, TAKES), flush=True)
    if kind == "clone" and not ent.get("deleted"):
        el.delete_voice(ent["voice_id"])
        ent["deleted"] = True
        save(st)


def write_batch():
    st = state()
    items = []
    for who, sid, kind, label in voices():
        ent = st.get("%s.%s" % (who, sid), {})
        for i, c in enumerate(ent.get("cards", []), start=1):
            if os.path.exists(os.path.join(BATCH_DIR, c["file"])):
                items.append({"id": "%s.%s.card%d" % (who, sid, i), "kind": "audio", "group": who,
                              "label": "voice card %d · %s%s" % (i, label, " (speaks the lines below)" if i == 1 else ""),
                              "text": card_text(who), "file": c["file"], "target": os.path.relpath(base.game_path(who, "greet"), ROOT),
                              "meta": {"voice": "elevenlabs:%s.%s" % (who, sid), "engine": "ElevenLabs voice design (%s)" % el.DESIGN_MODEL,
                                       "context": DESIGNS[who]}})
        for name in LINES[who]:
            if not os.path.exists(take_path(who, sid, name, 1)):
                continue
            text = base.text_of(who, name)
            takes = {os.path.relpath(take_path(who, sid, name, k), BATCH_DIR): "" for k in range(1, TAKES + 1)
                     if os.path.exists(take_path(who, sid, name, k))}
            sp = speak_text(who, name)
            items.append({"id": "%s.%s.%s" % (who, sid, name), "kind": "audio", "group": who,
                          "label": "%s · ElevenLabs v4 · %s" % (name, label), "text": text,
                          "file": os.path.relpath(take_path(who, sid, name, 1), BATCH_DIR),
                          "target": os.path.relpath(base.game_path(who, name), ROOT),
                          "meta": {"voice": "elevenlabs:%s.%s" % (who, sid), "engine": "ElevenLabs %s, %s" % (el.V4, label),
                                   "context": base.CONTEXT.get(name, ""), "speak": sp if sp != base.spoken(text) else "",
                                   "refs": ent.get("refs", []), "take_info": takes}})
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    json.dump({"batch": BATCH, "title": "ElevenLabs v4 samples: clones of our voices, and new designed voices (0 = the game's take)",
               "items": items}, open(out + ".tmp", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    print("batch: %d items" % len(items))


def main():
    n = plan_chars()
    print("plan: %d voices, %d characters (about $%.2f at $%.2f per 1k; less on the v4 sale)"
          % (len(voices()), n, n / 1000.0 * el.PRICE_PER_1K, el.PRICE_PER_1K))
    for who, sid, kind, label in voices():
        if kind == "clone":
            files, secs = refs(who, sid)
            print("  %-8s %-6s %s: %d takes, %.0f s" % (who, sid, label, len(files), secs))
        else:
            print("  %-8s %-6s %s" % (who, sid, label))
    if "--plan" in sys.argv:
        return
    acct = el.account_or_none()
    if acct:
        print("account: plan %s, %d credits left, voices %s of %s" % (acct["tier"], acct["left"], acct["voices_used"], acct["voice_limit"]))
        if acct["left"] < n:
            sys.exit("elevenlabs: %d credits left, and this needs about %d. Nothing made." % (acct["left"], n))
    try:
        ms = el.models()
        if el.V4 not in ms:
            sys.exit("elevenlabs: %s isn't available to this key (models: %s)" % (el.V4, ", ".join(sorted(ms))))
    except el.Error:
        pass ## no models_read: the first line says whether v4 speaks
    st = state()
    t0 = time.time()
    blocked = False
    for who, sid, kind, label in voices():
        try:
            make_voice(who, sid, kind, st)
        except el.Error as e:
            blocked = blocked or "missing the permission" in str(e)
            print("  %-8s %-6s FAILED: %s" % (who, sid, e), flush=True)
        write_batch()
    after = el.account_or_none()
    print("done in %.0f s%s" % (time.time() - t0, "; %d credits spent (%d left)" % (acct["left"] - after["left"], after["left"]) if acct and after else ""))
    if blocked:
        sys.exit(3) ## the key lacks a permission: run again once it has it (what's made is kept)


if __name__ == "__main__":
    main()
