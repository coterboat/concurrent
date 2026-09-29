#!/usr/bin/env python3
"""VoiceStudio, the full sets: every line of every commander in the voice the owner chose, 3 takes
each, plus every iteration of the v1.11 speech lab spoken by the new voices.

The cast (the owner, 28 Sep 2026): Oren A, Varek B and Imre C (designed voices, vs_designs), Hask's
own voice cloned (vs_samples), and for Quill and Ysolde both their own voice cloned and the recast
they kept (Quill E, Ysolde F, vs_cast), to compare line by line. In the review table the two sets
sit next to each other; `0` plays the line as the game has it now.

    python3 tools/voicestudio/vs_lines.py              # make what's missing (hours; resumable), write the batch
    python3 tools/voicestudio/vs_lines.py --batch      # rewrite review/vs_lines/batch.json only
    python3 tools/voicestudio/vs_lines.py --install    # the table's button: accepted takes go into the game
    python3 tools/voicestudio/vs_lines.py --regen      # re-roll the rejected (free); notes steer the words

Every take is checked before anyone hears it. Its pitch must sit near its voice (junk lands an
octave off), it can't swing wildly, and its length has to fit its words; a take that fails is
rolled again with a new seed. A click before the first word (Quill's clones had a "tsk" on nearly
every take: a 0.1-0.2 s burst, 16-21 dB under the line, then silence) is cut off, and so is a lip
smack after the last one. A quiet burst with a pitch is a word (Quill's murmured "Hm.") and stays.
Free and local; needs VoiceStudio at http://127.0.0.1:3900.
"""
import array
import json
import math
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "ludo"))
import vs  # noqa: E402
import vs_samples as base  # noqa: E402
import vs_designs as round1  # noqa: E402
import vs_casting as casting  # noqa: E402
import notes  # noqa: E402
import voice_measure  # noqa: E402

BATCH = "vs_lines"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
LAB = os.path.join(ROOT, "review", "v111_lab", "batch.json")
TAKES = 3
LAB_TAKES = 2
TRIES = 4 ## seeds per take before a failing one is kept anyway (and flagged)

## who -> the voices every line is spoken in: "clone" is their own voice (vs_samples), a letter is
## a designed voice (A-C, vs_designs) or a recast (D-F, vs_cast)
CAST = {
    "quill": ["clone", "E"],
    "ysolde": ["clone", "F"],
    "oren": ["A"],
    "varek": ["B"],
    "imre": ["C"],
    "hask": ["clone"],
}
ORDER = ["quill", "ysolde", "oren", "varek", "imre", "hask"]
## the lab's lines, in the voices above (the advisor's cloned, as in vs_samples)
LAB_CAST = {"quill": ["clone", "E"], "ysolde": ["clone", "F"], "varek": ["B"], "advisor": ["clone"]}
LAB_SKIP = {"break_tag", "bracket"} ## both get read aloud ("reads break time", "reads pause")

## the first pass's notes (vs_voices), turned into the words the voice is given; the subtitle keeps the line
DIRECTION = {
    ("ysolde", "lose"): ("You will pay for that... Deerly.", "\"She's pronouncing it Duhrly, not Deer-lee\""),
    ("ysolde", "capital_took"): ("Your capital kneels to... ME... now.", "\"no emphasis or pause around 'me'\""),
    ("oren", "lose"): ("Wait, that was NOT supposed to happen!", "\"Stress *not*\""),
    ("oren", "capital_took"): ("I took your capital!... wait until I write home!",
                               "\"The second sentence needs to start softer and end with the same high inflection\""),
}
CONTEXT = {
    "greet": "their greeting at the table", "attack": "they send an attack", "win": "they win a battle",
    "lose": "they lose a battle", "walkin": "they walk into an empty land", "eliminated": "they are knocked out",
    "victory": "they win the war", "retreat": "they fall back", "reserves": "they throw in the reserves",
    "claim": "they claim a land in the deal", "cash": "they cash in cards", "capital_took": "they take a capital",
    "capital_lost": "their capital falls", "taunt": "they march on you", "fortune": "they spend Fortune on a throw",
}
FEMALE = {"ysolde", "imre"}


# ---- the voices ----

def label_of(who, sid):
    if sid == "clone":
        return "own voice, cloned"
    for ident, traits, _ in round1.IDENTITIES.get(who, []):
        if ident == sid:
            return "%s · %s" % (sid, round1.short(traits))
    t = casting.state().get("%s.%s" % (who, sid), {}).get("traits", "")
    return "%s · %s" % (sid, round1.short(t))


def voice(who, sid):
    """(reference wav, its words): what every line of this voice is cloned from."""
    if sid == "clone":
        return base.ref_for(who)
    if sid in "ABC":
        return os.path.join(round1.BATCH_DIR, who, sid, "card.ref.wav"), round1.card_text(who)
    return casting.state()["%s.%s" % (who, sid)]["card"], casting.card_text(who)


_F0 = {}


def voice_f0(who, sid):
    if (who, sid) not in _F0:
        _F0[(who, sid)] = voice_measure.measure(voice(who, sid)[0]).get("f0") or (200.0 if who in FEMALE else 110.0)
    return _F0[(who, sid)]


# ---- the lines ----

def game_lines(who):
    """[(name, key, text)]: every line the game has for them, variants included."""
    out = []
    for key, v in base.lines().get(who, {}).items():
        for i, t in enumerate(v if isinstance(v, list) else [v]):
            out.append((key if i == 0 else "%s_v%d" % (key, i + 1), key, str(t)))
    return out


def plain(s):
    return " ".join(re.findall(r"[a-z0-9']+", s.lower().replace("_", " ")))


def lab_lines(who):
    """[(name, speak, test, variant, game name or None)]: the v1.11 lab's iterations for them, each text once."""
    if not os.path.exists(LAB):
        return []
    game = {plain(t): name for name, _, t in game_lines(who)}
    seen, out = set(), []
    for it in json.load(open(LAB))["items"]:
        test, w, l, variant = it["id"].split(".")[:4]
        if w != who or variant in LAB_SKIP or it["text"] in seen:
            continue
        seen.add(it["text"])
        out.append(("lab_%s_%s_%s" % (test, l, variant), it["text"], test, variant, game.get(plain(it["text"]))))
    return out


def match_for(who, target):
    """the take its loudness is matched to: the game's take of that line, else their greeting"""
    p = base.game_path(who, target) if target else ""
    return p if p and os.path.exists(p) else base.game_path(who, "welcome" if who == "advisor" else "greet")


def speak_for(who, name, text, st, aid):
    if st.get(aid, {}).get("speak"):
        return st[aid]["speak"]
    d = DIRECTION.get((who, name))
    return d[0] if d else base.spoken(text)


# ---- a take ----

def samples(path):
    """the take as 16 kHz mono samples"""
    raw = subprocess.run([base.FFMPEG, "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"], capture_output=True).stdout
    a = array.array("h")
    a.frombytes(raw[: len(raw) // 2 * 2])
    return a


def envelope(a, ms=5):
    n = 16 * ms
    return [20 * math.log10(math.sqrt(sum(x * x for x in a[i:i + n]) / n) / 32768 + 1e-9) for i in range(0, len(a) - n, n)]


def voiced(a, t0, t1, f0):
    """Is this stretch spoken in this voice? A murmured "Hm" repeats itself at the voice's own pitch;
    Quill's "tsk" rumbles at 60-120 Hz, under his 180. Share of 30 ms windows whose autocorrelation
    peaks above 0.6 at a pitch within the voice's range (-5 to +9 semitones of f0)."""
    lo, hi = f0 * 2 ** (-5 / 12), f0 * 2 ** (9 / 12)
    lags = range(max(20, int(16000 / hi)), min(400, int(16000 / lo)) + 1)
    top = lags[-1]
    w, hop, hits, n = 480, 240, 0, 0
    for i in range(int(t0 * 16000), max(int(t0 * 16000) + 1, int(t1 * 16000) - w), hop):
        x = a[i:i + w + top]
        if len(x) < w + top:
            break
        e0 = sum(v * v for v in x[:w:2]) or 1
        best = 0.0
        for lag in lags:
            num = sum(x[j] * x[j + lag] for j in range(0, w, 2))
            el = sum(x[j + lag] * x[j + lag] for j in range(0, w, 2)) or 1
            best = max(best, num / math.sqrt(e0 * el))
        hits += best > 0.6
        n += 1
    return n > 0 and hits >= max(1, n * 0.4)


def edges(path, f0):
    """(cut before, cut after) in seconds: a short, quiet, pitchless burst before the first word or
    after the last, set apart by silence (a click, a lip smack), is cut off. 0 = nothing to cut.
    A burst with a pitch is a word ("Hm.") and stays, however quiet."""
    a = samples(path)
    e = envelope(a)
    segs, cur, quiet = [], None, 0
    for i, v in enumerate(e):
        if v > -50:
            cur = cur or [i, i, v]
            cur[1], cur[2], quiet = i, max(cur[2], v), 0
        elif cur is not None:
            quiet += 1
            if quiet >= 16: ## 80 ms of silence closes a burst
                segs.append(cur)
                cur, quiet = None, 0
    if cur:
        segs.append(cur)
    if len(segs) < 2:
        return 0.0, 0.0
    peak = max(s[2] for s in segs)
    click = lambda s, longest: ((s[1] - s[0]) * 0.005 <= longest and s[2] <= peak - 14
                                and not voiced(a, s[0] * 0.005, (s[1] + 1) * 0.005, f0))
    k = 0
    while k < len(segs) - 1 and k < 3 and segs[k][0] * 0.005 < 0.45 and click(segs[k], 0.35):
        k += 1
    j = len(segs) - 1
    while j > k and len(segs) - 1 - j < 2 and click(segs[j], 0.12):
        j -= 1
    head = max(0.0, segs[k][0] * 0.005 - 0.05) if k else 0.0
    tail = segs[j][1] * 0.005 + 0.15 if j < len(segs) - 1 else 0.0
    return head, tail


def fits(info, f0, live, speak, ref_f0):
    words = len(plain(re.sub(r"\[[^\]]*\]", " ", speak)).split())
    why = []
    if not f0 or not ref_f0 * 2 ** (-7 / 12) <= f0 <= ref_f0 * 2 ** (9 / 12):
        why.append("pitch %s Hz, its voice %.0f" % (int(f0) if f0 else "?", ref_f0))
    if live > casting.WILD:
        why.append("swings %.0f st" % live)
    if not words * 0.12 <= info["duration"] <= 1.5 + words * 0.75:
        why.append("%.1f s for %d words" % (info["duration"], words))
    return why


def finish(wav, out, match, cut, tail=0.0):
    target = base.lufs(match) if match and os.path.exists(match) else -18.0
    af = ""
    if tail:
        af += "atrim=end=%.3f,afade=t=out:st=%.3f:d=0.06," % (tail, max(0.0, tail - 0.06))
    if cut:
        af += "atrim=start=%.3f,asetpts=PTS-STARTPTS,afade=t=in:d=0.012,adelay=80:all=1," % cut
    af += "loudnorm=I=%.1f:TP=-1.5:LRA=11" % target
    base.run("-i", wav, "-af", af, "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    os.remove(wav)


def take_path(who, sid, name, k):
    d = os.path.join(BATCH_DIR, who, sid)
    return os.path.join(d, name + ".mp3") if k == 1 else os.path.join(d, ".takes", "%s.t%d.mp3" % (name, k))


def make_take(who, sid, name, k, speak, match, st):
    out = take_path(who, sid, name, k)
    if os.path.exists(out):
        return False
    os.makedirs(os.path.dirname(out), exist_ok=True)
    aid = "%s.%s.%s" % (who, sid, name)
    ref, ref_text = voice(who, sid)
    ref_f0 = voice_f0(who, sid)
    rnd = int(st.get(aid, {}).get("round", 1))
    wav = out + ".wav"
    for r in range(TRIES):
        seed = base.seed_of(aid, rnd * 10 + r, k)
        info = vs.generate(speak, wav, ref_audio=ref, ref_text=ref_text, seed=seed)
        live, f0 = casting.liveliness(wav)
        why = fits(info, f0, live, speak, ref_f0)
        if not why:
            break
        print("    %-30s take %d seed %-6d rolled again: %s" % (aid, k, seed, "; ".join(why)), flush=True)
    cut, tail = edges(wav, ref_f0)
    finish(wav, out, match, cut, tail)
    st.setdefault(aid, {"round": rnd})["t%d" % k] = {"seed": seed, "tries": r + 1, "f0": round(f0 or 0, 1), "live": round(live, 1),
                                                    "duration": info["duration"], "cut": round(cut, 2), "tail": round(tail, 2), "doubt": "; ".join(why)}
    return True


# ---- state ----

def state_path():
    return os.path.join(BATCH_DIR, "state.json")


def load_state():
    try:
        return json.load(open(state_path()))
    except (OSError, ValueError):
        return {}


def save_state(st):
    os.makedirs(BATCH_DIR, exist_ok=True)
    json.dump(st, open(state_path() + ".tmp", "w"), indent=1, ensure_ascii=False)
    os.replace(state_path() + ".tmp", state_path())


def plan():
    """[(who, sid, name, text, speak-or-None, target name or None, takes, kind)] in the order they're made."""
    rows = []
    for who in ORDER:
        for name, key, text in game_lines(who):
            for sid in CAST[who]:
                rows.append((who, sid, name, text, None, name, TAKES, "line"))
    for who, sids in LAB_CAST.items():
        for name, speak, test, variant, game in lab_lines(who):
            for sid in sids:
                rows.append((who, sid, name, base.spoken(speak), speak, game, LAB_TAKES, "lab"))
    return rows


def generate_all():
    if not vs.health():
        print("VoiceStudio is not running at %s: start it, then run this again." % vs.URL)
        sys.exit(2)
    st = load_state()
    t0, made, last = time.time(), 0, None
    for who, sid, name, text, speak, target, takes, kind in plan():
        aid = "%s.%s.%s" % (who, sid, name)
        say = speak or speak_for(who, name, text, st, aid)
        match = match_for(who, target)
        n = 0
        for k in range(1, takes + 1):
            n += make_take(who, sid, name, k, say, match, st)
            save_state(st)
        if n:
            made += n
            doubts = [st[aid]["t%d" % k]["doubt"] for k in range(1, takes + 1) if st[aid].get("t%d" % k, {}).get("doubt")]
            cuts = [st[aid]["t%d" % k]["cut"] for k in range(1, takes + 1) if st[aid].get("t%d" % k, {}).get("cut")]
            tails = sum(1 for k in range(1, takes + 1) if st[aid].get("t%d" % k, {}).get("tail"))
            print("  %-30s %d take%s  %s%s%s" % (aid, n, "s" if n > 1 else "", say[:48],
                  ("  (click cut: %s s)" % ", ".join("%.2f" % c for c in cuts) if cuts else "") + ("  (%d tail click%s cut)" % (tails, "s" if tails > 1 else "") if tails else ""),
                  "  DOUBT: " + " | ".join(doubts) if doubts else ""), flush=True)
        if (who, name) != last:
            last = (who, name)
            write_batch(quiet=True)
    write_batch()
    print("made %d takes in %.0f min" % (made, (time.time() - t0) / 60))


# ---- the review batch ----

def describe(aid, k, st):
    t = st.get(aid, {}).get("t%d" % k, {})
    parts = []
    if t.get("cut"):
        parts.append("click cut %.2f s" % t["cut"])
    if t.get("tail"):
        parts.append("ends at %.2f s (a click after it cut)" % t["tail"])
    if t.get("tries", 1) > 1:
        parts.append("%d seeds" % t["tries"])
    if t.get("doubt"):
        parts.append("doubt: " + t["doubt"])
    return ", ".join(parts)


def actions():
    me = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")
    return [
        {"id": "install", "kind": "install", "label": "Put accepted in the game",
         "help": "Each accepted take replaces that line in the game (the old one stays in git history), then Godot "
                 "re-imports. Stops if two takes are accepted for one line (Quill's and Ysolde's two voices). Lab "
                 "lines that aren't game lines yet are listed, not installed.",
         "cmd": ["python3", me, "--install"],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
        {"id": "regen", "kind": "regen", "label": "Redo rejected (free)",
         "help": "New takes of every rejected line, in the same voice (no credits). A note becomes direction for the "
                 "words; the rejected take stays beside the new ones.",
         "cmd": ["python3", me, "--regen"],
         "options": [{"flag": "--takes", "label": "Takes per line", "type": "int", "default": 3, "min": 1, "max": 6},
                     {"flag": "--no-notes", "label": "Ignore the notes", "type": "bool", "default": False}]},
    ]


def write_batch(quiet=False):
    st = load_state()
    items = []
    for who, sid, name, text, speak, target, takes, kind in plan():
        aid = "%s.%s.%s" % (who, sid, name)
        if not os.path.exists(take_path(who, sid, name, 1)):
            continue
        info = {}
        for k in range(1, 10):
            p = take_path(who, sid, name, k)
            if os.path.exists(p):
                info[os.path.relpath(p, BATCH_DIR).replace(os.sep, "/")] = describe(aid, k, st)
        tdir = os.path.join(BATCH_DIR, who, sid, ".takes")
        if os.path.isdir(tdir):
            for f in sorted(os.listdir(tdir)):
                if f.startswith(name + ".r"):
                    info[os.path.relpath(os.path.join(tdir, f), BATCH_DIR).replace(os.sep, "/")] = "rejected earlier"
        say = speak or speak_for(who, name, text, st, aid)
        voice_label = label_of(who, sid)
        if kind == "lab":
            test, l, variant = name.split("_", 3)[1:4] if name.count("_") >= 3 else ("", "", "")
            label = "lab · %s %s · %s · %s" % (test, l, variant, voice_label)
            ctx = "v1.11 speech lab (%s: %s)%s" % (test, variant, "; the game's %s line" % target if target else "; not a game line yet")
        else:
            label = "%s · %s" % (name, voice_label)
            ctx = CONTEXT.get(name.split("_v")[0], "")
            if (who, name) in DIRECTION and not st.get(aid, {}).get("speak"):
                ctx += "  ·  steered by the note " + DIRECTION[(who, name)][1]
        it = {"id": aid, "kind": "audio", "group": who, "label": label, "text": text,
              "file": os.path.relpath(take_path(who, sid, name, 1), BATCH_DIR).replace(os.sep, "/"),
              "meta": {"voice": "voicestudio:%s.%s" % (who, sid), "context": ctx,
                       "speak": say if say != base.spoken(text) else "", "engine": "VoiceStudio (OmniVoice): %s" % voice_label,
                       "set": sid, "take_info": info}}
        if target:
            it["target"] = os.path.relpath(base.game_path(who, target), ROOT).replace(os.sep, "/")
        items.append(it)
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    json.dump({"batch": BATCH, "title": "VoiceStudio, the full sets: every line in the chosen voices, and the v1.11 lab (0 = the game's take)",
               "actions": actions(), "items": items}, open(out + ".tmp", "w"), indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    if not quiet:
        print("batch: %d lines with takes (of %d planned)" % (len(items), len(plan())))


# ---- the table's buttons ----

def merged():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review
    return review.merged_batch(BATCH)


def install():
    dry = "--dry-run" in sys.argv
    mb = merged()
    acc = [it for it in mb["items"] if it["status"] == "accept"]
    by_target, sets, untargeted = {}, {}, []
    for it in acc:
        if it.get("target"):
            by_target.setdefault(it["target"], []).append(it["id"])
        else:
            untargeted.append(it)
        sets.setdefault(it["group"], set()).add(it["meta"].get("set"))
    clash = {t: ids for t, ids in by_target.items() if len(ids) > 1}
    if clash:
        print("Two takes are accepted for the same line; reject one of each, then install:")
        for t, ids in sorted(clash.items()):
            print("  %s: %s" % (t, ", ".join(ids)))
        sys.exit(1)
    for who, s in sorted(sets.items()):
        if len(s) > 1:
            print("note: %s's accepted lines come from %d voices (%s): they'll sound like different people" % (who, len(s), ", ".join(sorted(s))))
    for it in untargeted:
        print("not a game line yet (say which moment it belongs to): %s  %r" % (it["id"], it["text"]))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "review", "review.py"), "apply", BATCH] + (["--dry-run"] if dry else []), check=True)
    if dry:
        print("dry run: nothing copied")
        return
    godot = os.environ.get("GODOT", os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot"))
    if os.path.exists(godot):
        print("importing into Godot…", flush=True)
        subprocess.run([godot, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("imported: the accepted takes are in the game")


def regen():
    takes = TAKES
    if "--takes" in sys.argv:
        takes = max(1, min(6, int(sys.argv[sys.argv.index("--takes") + 1])))
    use_notes = "--no-notes" not in sys.argv
    rejected = [it for it in merged()["items"] if it["status"] == "reject"]
    if not rejected:
        print("nothing rejected")
        return
    st = load_state()
    rows = {"%s.%s.%s" % (r[0], r[1], r[2]): r for r in plan()}
    directed = []
    for it in rejected:
        aid = it["id"]
        if aid not in rows:
            continue
        who, sid, name, text, speak, target, _, kind = rows[aid]
        ent = st.setdefault(aid, {"round": 1})
        ent["round"] = int(ent.get("round", 1)) + 1
        if use_notes and notes.meaningful(it.get("note")):
            directed.append({"id": aid, "text": text, "speak": speak or speak_for(who, name, text, st, aid), "note": it["note"], "who": who})
        tdir = os.path.join(BATCH_DIR, who, sid, ".takes")
        os.makedirs(tdir, exist_ok=True)
        main = take_path(who, sid, name, 1)
        if os.path.exists(main):
            n = 1 + sum(1 for f in os.listdir(tdir) if f.startswith(name + ".r"))
            os.replace(main, os.path.join(tdir, "%s.r%d.mp3" % (name, n)))
        for k in range(2, 10):
            p = take_path(who, sid, name, k)
            if os.path.exists(p):
                os.remove(p)
    if directed:
        print("reading %d note%s…" % (len(directed), "s" if len(directed) != 1 else ""), flush=True)
        for aid, (speak, why, how) in notes.rewrite_speech(directed).items():
            st[aid]["speak"] = speak
            print("  direction (%s): %s: %r%s" % (how, aid, speak, "  (" + why + ")" if why else ""))
    save_state(st)
    for it in rejected:
        if it["id"] not in rows:
            continue
        who, sid, name, text, speak, target, _, kind = rows[it["id"]]
        say = st[it["id"]].get("speak") or speak or speak_for(who, name, text, st, it["id"])
        match = match_for(who, target)
        for k in range(1, takes + 1):
            make_take(who, sid, name, k, say, match, st)
            save_state(st)
        print("  %-30s redone: %s" % (it["id"], say[:60]), flush=True)
    write_batch()


if __name__ == "__main__":
    if "--install" in sys.argv:
        install()
    elif "--regen" in sys.argv:
        regen()
    elif "--batch" in sys.argv:
        write_batch()
    else:
        generate_all()
