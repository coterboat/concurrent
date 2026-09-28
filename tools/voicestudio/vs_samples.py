#!/usr/bin/env python3
"""VoiceStudio samples: the advisor and every commander, cloned locally by OmniVoice (k2-fsa, run
by VoiceStudio on this Mac) from one of their own accepted takes, saying lines the game already has
in Ludo's voice. In the review table each line has 3 takes (1-3) and `0` plays the Ludo take the
game uses now, so the two can be heard side by side.

    python3 tools/voicestudio/vs_samples.py             # make what's missing, then write the batch
    python3 tools/voicestudio/vs_samples.py --batch     # rewrite review/vs_voices/batch.json only
    python3 tools/voicestudio/vs_samples.py --install   # the table's button: accepted takes replace
                                                        #   the Ludo take of that line in the game
    python3 tools/voicestudio/vs_samples.py --regen     # re-roll the rejected (free), notes steer it

Free: no credits, nothing leaves the Mac. Each take is loudness-matched to the Ludo take it's
compared with, so the louder one doesn't win by being louder. Needs VoiceStudio running
(http://127.0.0.1:3900).
"""
import json
import os
import re
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "ludo"))
import vs  # noqa: E402
import notes  # noqa: E402
import voice_measure  # noqa: E402

BATCH = "vs_voices"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
LINES_JSON = os.path.join(ROOT, "game", "data", "lines.json")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
TAKES = 3

## who -> the accepted takes (file names) their clone is made from: 5-10 s of their own voice
REFS = {
    "advisor": ["welcome"],
    "varek": ["greet"],
    "ysolde": ["greet"],
    "quill": ["greet"],
    "oren": ["greet", "capital_lost_v3"],
    "hask": ["greet"],
    "imre": ["greet", "taunt_v2"],
}
## who -> the lines to hear them say (take 1 of each key: the Ludo take it's compared with)
LINES = {
    "advisor": ["final", "capital_lost", "walkin_us", "bad_roll"],
    "varek": ["taunt", "win", "lose", "capital_took"],
    "ysolde": ["taunt", "win", "lose", "capital_took"],
    "quill": ["taunt", "win", "lose", "capital_took"],
    "oren": ["taunt", "win", "lose", "capital_took"],
    "hask": ["taunt", "win", "lose", "capital_took"],
    "imre": ["taunt", "win", "lose", "capital_took"],
}
CONTEXT = {"taunt": "they march on you", "win": "they win a battle", "lose": "they lose a battle",
           "capital_took": "they take a capital", "final": "the last round begins", "capital_lost": "our capital falls",
           "walkin_us": "we walk into an empty land", "bad_roll": "the dice go against us"}


def game_path(who, name):
    return os.path.join(ROOT, "assets", "voice" if who == "advisor" else "voice13", who, name + ".mp3")


def lines():
    return json.load(open(LINES_JSON))["lines"]


def text_of(who, name):
    key, _, n = name.partition("_v")
    v = lines().get(who, {}).get(key, "")
    takes = v if isinstance(v, list) else [v]
    i = int(n) - 1 if n.isdigit() else 0
    return str(takes[i]) if i < len(takes) else ""


def spoken(text):
    """What OmniVoice is asked to say: the words, without the stars the game uses for stress."""
    return text.replace("*", "")


def run(*args):
    subprocess.run([FFMPEG, "-v", "error", "-y"] + [str(a) for a in args], check=True)


def lufs(path):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", path, "-af", "ebur128=framelog=quiet", "-f", "null", "-"], capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", r.stderr)
    return float(m[-1]) if m else -18.0


def ref_for(who):
    """The clone's reference: the chosen takes, joined with a breath of silence, 24 kHz mono."""
    out = os.path.join(BATCH_DIR, "refs", who + ".wav")
    texts = [spoken(text_of(who, n)) for n in REFS[who]]
    if not os.path.exists(out):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        ins = []
        for n in REFS[who]:
            ins += ["-i", game_path(who, n)]
        k = len(REFS[who])
        if k == 1:
            run(*ins, "-ar", 24000, "-ac", 1, out)
        else:
            parts = "".join("[%d:a]aresample=24000,aformat=channel_layouts=mono,apad=pad_dur=0.45[a%d];" % (i, i) for i in range(k))
            run(*ins, "-filter_complex", parts + "".join("[a%d]" % i for i in range(k)) + "concat=n=%d:v=0:a=1[o]" % k, "-map", "[o]", out)
    return out, " ".join(texts)


def state_path():
    return os.path.join(BATCH_DIR, "state.json")


def load_state():
    try:
        return json.load(open(state_path()))
    except (OSError, ValueError):
        return {}


def save_state(st):
    os.makedirs(BATCH_DIR, exist_ok=True)
    json.dump(st, open(state_path(), "w"), indent=1, ensure_ascii=False)


def take_path(who, name, k):
    d = os.path.join(BATCH_DIR, who)
    return os.path.join(d, name + ".mp3") if k == 1 else os.path.join(d, ".takes", "%s.t%d.mp3" % (name, k))


def seed_of(aid, rnd, k):
    return zlib.crc32(("%s|%d|%d" % (aid, rnd, k)).encode()) % 100000


def make_take(who, name, k, rnd, speak, st):
    """One take: OmniVoice clones the voice, then it's matched to the Ludo take's loudness."""
    out = take_path(who, name, k)
    if os.path.exists(out):
        return False
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ref, ref_text = ref_for(who)
    aid = "%s.%s" % (who, name)
    seed = seed_of(aid, rnd, k)
    wav = out + ".wav"
    info = vs.generate(speak, wav, ref_audio=ref, ref_text=ref_text, seed=seed)
    target = lufs(game_path(who, name)) if os.path.exists(game_path(who, name)) else -18.0
    run("-i", wav, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % target, "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    os.remove(wav)
    st.setdefault(aid, {"round": rnd})["t%d" % k] = {"seed": seed, "gen_time": info["gen_time"], "duration": info["duration"]}
    print("  %-22s take %d  seed %-6d %4.1f s of speech in %4.1f s" % (aid, k, seed, info["duration"], info["gen_time"]), flush=True)
    return True


def plan():
    rows = []
    for who, keys in LINES.items():
        for key in keys:
            text = text_of(who, key)
            if text:
                rows.append((who, key, text))
    return rows


def generate_all(takes=TAKES):
    if not vs.health():
        print("VoiceStudio is not running at %s: start it, then run this again." % vs.URL)
        sys.exit(2)
    st = load_state()
    t0 = time.time()
    made = 0
    for who, name, text in plan():
        aid = "%s.%s" % (who, name)
        speak = st.get(aid, {}).get("speak") or spoken(text)
        for k in range(1, takes + 1):
            made += make_take(who, name, k, int(st.get(aid, {}).get("round", 1)), speak, st)
            save_state(st)
    print("made %d takes in %.0f s" % (made, time.time() - t0))


def describe(m):
    parts = []
    s = m.get("end_slope_st")
    if s is not None:
        parts.append(("falls %.1f st" % -s) if s < -0.5 else ("rises %.1f st" % s) if s > 0.5 else "level end")
    if m.get("gap") is not None and m["gap"] >= 0.15:
        parts.append("pause %.2f s" % m["gap"])
    return ", ".join(parts)


def actions():
    me = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")
    return [
        {"id": "install", "kind": "install", "label": "Put accepted in the game",
         "help": "Each accepted VoiceStudio take replaces the Ludo take of that line in the game (the Ludo one "
                 "stays in git history), then Godot re-imports. Only what you accept.",
         "cmd": ["python3", me, "--install"],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
        {"id": "regen", "kind": "regen", "label": "Redo rejected (free)",
         "help": "New takes of every rejected line from VoiceStudio on this Mac (no credits). A note becomes "
                 "direction for the voice; the rejected take stays beside the new ones.",
         "cmd": ["python3", me, "--regen"],
         "options": [{"flag": "--takes", "label": "Takes per line", "type": "int", "default": 3, "min": 1, "max": 6},
                     {"flag": "--no-notes", "label": "Ignore the notes", "type": "bool", "default": False}]},
    ]


def write_batch():
    st = load_state()
    items = []
    for who, name, text in plan():
        aid = "%s.%s" % (who, name)
        info = {}
        d = os.path.join(BATCH_DIR, who)
        for k in range(1, 10):
            p = take_path(who, name, k)
            if os.path.exists(p):
                info[os.path.relpath(p, BATCH_DIR).replace(os.sep, "/")] = describe(voice_measure.measure(p))
        tdir = os.path.join(d, ".takes")
        if os.path.isdir(tdir):
            for f in os.listdir(tdir):
                if f.startswith(name + ".r"):
                    info[os.path.relpath(os.path.join(tdir, f), BATCH_DIR).replace(os.sep, "/")] = describe(voice_measure.measure(os.path.join(tdir, f)))
        speak = st.get(aid, {}).get("speak", "")
        items.append({"id": aid, "kind": "audio", "group": who, "label": "%s · VoiceStudio clone" % name,
                      "text": text, "file": "%s/%s.mp3" % (who, name),
                      "target": os.path.relpath(game_path(who, name), ROOT).replace(os.sep, "/"),
                      "meta": {"voice": "voicestudio:" + who, "context": CONTEXT.get(name, ""), "speak": speak if speak != spoken(text) else "",
                               "engine": "VoiceStudio (OmniVoice), cloned from " + ", ".join(REFS[who]), "take_info": info}})
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    json.dump({"batch": BATCH, "title": "VoiceStudio samples: every voice, cloned locally (0 = the Ludo take)",
               "actions": actions(), "items": items}, open(out + ".tmp", "w"), indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    print("batch: %d lines, %d with a take" % (len(items), sum(1 for it in items if os.path.exists(os.path.join(BATCH_DIR, it["file"])))))


def install():
    dry = "--dry-run" in sys.argv
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
    path = os.path.join(BATCH_DIR, "rejected.json")
    if not os.path.exists(path):
        print("nothing rejected")
        return
    takes = TAKES
    if "--takes" in sys.argv:
        takes = max(1, min(6, int(sys.argv[sys.argv.index("--takes") + 1])))
    use_notes = "--no-notes" not in sys.argv
    st = load_state()
    rejected = json.load(open(path))
    directed = []
    for r in rejected:
        aid = r["id"]
        who, _, name = aid.partition(".")
        ent = st.setdefault(aid, {"round": 1})
        ent["round"] = int(ent.get("round", 1)) + 1
        if use_notes and notes.meaningful(r.get("note")):
            directed.append({"id": aid, "text": r.get("text") or text_of(who, name), "speak": ent.get("speak"), "note": r["note"], "who": who})
        ## the rejected take moves aside, to be heard against the new ones; its extra takes are rolled again
        d = os.path.join(BATCH_DIR, who)
        tdir = os.path.join(d, ".takes")
        os.makedirs(tdir, exist_ok=True)
        main = take_path(who, name, 1)
        if os.path.exists(main):
            n = 1 + sum(1 for f in os.listdir(tdir) if f.startswith(name + ".r"))
            os.replace(main, os.path.join(tdir, "%s.r%d.mp3" % (name, n)))
        for k in range(2, 10):
            p = take_path(who, name, k)
            if os.path.exists(p):
                os.remove(p)
    if directed:
        print("reading %d note%s…" % (len(directed), "s" if len(directed) != 1 else ""), flush=True)
        for aid, (speak, why, how) in notes.rewrite_speech(directed).items():
            st[aid]["speak"] = speak
            print("  direction (%s): %s: %r%s" % (how, aid, speak, "  (" + why + ")" if why else ""))
    save_state(st)
    wanted = {r["id"] for r in rejected}
    for who, name, text in plan():
        aid = "%s.%s" % (who, name)
        if aid in wanted:
            for k in range(1, takes + 1):
                make_take(who, name, k, int(st[aid]["round"]), st[aid].get("speak") or spoken(text), st)
                save_state(st)
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
        write_batch()
