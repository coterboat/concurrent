#!/usr/bin/env python3
"""ElevenLabs v4, the full sets (batch `el_lines`): every voice line in the game, spoken by the cast
(tools/elevenlabs/cast.json, from el_cast.py), 3 takes each. `0` in the review table plays the line
as the game has it now; each take is loudness-matched to it.

    python3 tools/elevenlabs/el_lines.py --plan     # the lines, the characters, the cost; no calls
    python3 tools/elevenlabs/el_lines.py            # make what's missing (resumable), write the batch
    python3 tools/elevenlabs/el_lines.py --install  # the table's button: accepted takes go into the game
    python3 tools/elevenlabs/el_lines.py --regen    # re-roll the rejected; a note steers the words

The words each voice is given are vs_lines.py's: the line without its stars, or the direction the
first pass's notes asked for ("Deerly", "...ME...", "NOT").
"""
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "voicestudio"))
sys.path.insert(0, os.path.join(ROOT, "tools", "ludo"))
import el  # noqa: E402
import el_cast  # noqa: E402
import vs_samples as base  # noqa: E402
import vs_lines  # noqa: E402
import notes  # noqa: E402

BATCH = "el_lines"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
TAKES = 3
WORKERS = 4 ## requests at once (Creator allows 5)
ORDER = ["varek", "ysolde", "quill", "oren", "hask", "imre", "advisor"]
_lock = threading.Lock()


def plan():
    """[(who, name, text)]: every line the game has, in ORDER"""
    return [(who, name, text) for who in ORDER for name, _, text in vs_lines.game_lines(who)]


def take_path(who, name, k):
    d = os.path.join(BATCH_DIR, who)
    return os.path.join(d, name + ".mp3") if k == 1 else os.path.join(d, ".takes", "%s.t%d.mp3" % (name, k))


def state():
    try:
        return json.load(open(os.path.join(BATCH_DIR, "state.json"), encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(st):
    with _lock:
        os.makedirs(BATCH_DIR, exist_ok=True)
        p = os.path.join(BATCH_DIR, "state.json")
        json.dump(st, open(p + ".tmp", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        os.replace(p + ".tmp", p)


def words(who, name, text, st):
    aid = "%s.%s" % (who, name)
    return st.get(aid, {}).get("speak") or vs_lines.speak_for(who, name, text, {}, aid)


def one_take(cast, who, name, text, k, st):
    out = take_path(who, name, k)
    if os.path.exists(out):
        return 0
    aid = "%s.%s" % (who, name)
    say = words(who, name, text, st)
    rnd = int(st.get(aid, {}).get("round", 1))
    seed = base.seed_of(aid, rnd, k)
    for attempt in range(4):
        try:
            audio = el.speak(cast[who]["voice_id"], say, seed=seed)
            break
        except el.Error as e:
            if "429" in str(e) or "rate" in str(e).lower() or "busy" in str(e).lower():
                time.sleep(3 * (attempt + 1)) ## too many at once: wait and try again
                continue
            raise
    else:
        raise el.Error("%s take %d: still busy after 4 tries" % (aid, k))
    samples_finish(audio, out, base.game_path(who, name))
    with _lock:
        st.setdefault(aid, {"round": rnd})["t%d" % k] = {"seed": seed, "chars": len(say)}
    save(st)
    return len(say)


def samples_finish(audio, out, match):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    raw = out + ".raw.mp3"
    with open(raw, "wb") as f:
        f.write(audio)
    target = base.lufs(match) if os.path.exists(match) else -18.0
    if target < -35.0:
        ## v2.3: a game take too short or broken to measure (Imre's 0.24 s "Check." read -70 LUFS)
        ## would level the new takes down to silence: the voices' usual level instead
        target = -20.0
    base.run("-i", raw, "-af", "loudnorm=I=%.1f:TP=-1.5:LRA=11" % target, "-ar", 44100, "-ac", 1, "-c:a", "libmp3lame", "-q:a", 2, out)
    os.remove(raw)


def generate(takes=TAKES, only=None):
    cast = el_cast.load()
    missing = [w for w in ORDER if not cast.get(w, {}).get("voice_id")]
    if missing:
        sys.exit("no voice for %s in cast.json: run tools/elevenlabs/el_cast.py first" % ", ".join(missing))
    st = state()
    jobs = [(who, name, text, k) for who, name, text in plan() if only is None or "%s.%s" % (who, name) in only
            for k in range(1, takes + 1) if not os.path.exists(take_path(who, name, k))]
    if not jobs:
        print("nothing to make")
        return 0
    print("making %d takes, %d at a time…" % (len(jobs), WORKERS), flush=True)
    t0, done, chars, failed = time.time(), 0, 0, []
    with ThreadPoolExecutor(WORKERS) as pool:
        futs = {pool.submit(one_take, cast, who, name, text, k, st): (who, name, k) for who, name, text, k in jobs}
        for f in futs:
            who, name, k = futs[f]
            try:
                chars += f.result()
            except Exception as e:  # one bad take doesn't stop the rest
                failed.append("%s.%s t%d: %s" % (who, name, k, str(e)[:160]))
            done += 1
            if done % 60 == 0:
                print("  %d of %d takes (%.0f s)" % (done, len(jobs), time.time() - t0), flush=True)
                write_batch(quiet=True)
    write_batch()
    for f in failed[:10]:
        print("  FAILED " + f)
    print("made %d takes, %d characters (about $%.2f at $%.2f per 1k) in %.0f s"
          % (len(jobs) - len(failed), chars, chars / 1000.0 * el.PRICE_PER_1K, el.PRICE_PER_1K, time.time() - t0))
    return len(failed)


def write_batch(quiet=False):
    cast = el_cast.load()
    st = state()
    items = []
    for who, name, text in plan():
        if not os.path.exists(take_path(who, name, 1)):
            continue
        aid = "%s.%s" % (who, name)
        info = {}
        for k in range(1, 10):
            p = take_path(who, name, k)
            if os.path.exists(p):
                info[os.path.relpath(p, BATCH_DIR)] = ""
        tdir = os.path.join(BATCH_DIR, who, ".takes")
        if os.path.isdir(tdir):
            for f in sorted(os.listdir(tdir)):
                if f.startswith(name + ".r"):
                    info[os.path.relpath(os.path.join(tdir, f), BATCH_DIR)] = "rejected earlier"
        c = cast.get(who, {})
        voice = "the advisor's own voice, cloned" if c.get("kind") == "clone" else "design card %s" % c.get("card")
        say = words(who, name, text, st)
        items.append({"id": aid, "kind": "audio", "group": who, "label": "%s · ElevenLabs v4 · %s" % (name, voice), "text": text,
                      "file": os.path.relpath(take_path(who, name, 1), BATCH_DIR), "target": os.path.relpath(base.game_path(who, name), ROOT),
                      "meta": {"voice": "elevenlabs:%s" % c.get("voice_id", "?"), "engine": "ElevenLabs %s, %s" % (el.V4, voice),
                               "context": vs_lines.CONTEXT.get(name.split("_v")[0], ""), "speak": say if say != base.spoken(text) else "",
                               "take_info": info}})
    me = os.path.relpath(os.path.abspath(__file__), ROOT)
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    json.dump({"batch": BATCH, "title": "ElevenLabs v4, the full sets: every line in the cast's voices (0 = the game's take)",
               "actions": [
                   {"id": "install", "kind": "install", "label": "Put accepted in the game",
                    "help": "Each accepted take replaces that line in the game (the old one stays in git history), then Godot re-imports.",
                    "cmd": ["python3", me, "--install"], "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
                   {"id": "regen", "kind": "regen", "label": "Redo rejected",
                    "help": "New takes of every rejected line in the same voice (a credit a character). A note becomes direction "
                            "for the words; the rejected take stays beside the new ones.",
                    "cmd": ["python3", me, "--regen"],
                    "options": [{"flag": "--takes", "label": "Takes per line", "type": "int", "default": 3, "min": 1, "max": 6},
                                {"flag": "--no-notes", "label": "Ignore the notes", "type": "bool", "default": False}]}],
               "items": items}, open(out + ".tmp", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    if not quiet:
        print("batch: %d lines with takes (of %d)" % (len(items), len(plan())))


def install():
    dry = "--dry-run" in sys.argv
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "review", "review.py"), "apply", BATCH] + (["--dry-run"] if dry else []), check=True)
    godot = os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot")
    if not dry and os.path.exists(godot):
        print("importing into Godot…", flush=True)
        subprocess.run([godot, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("imported: the accepted takes are in the game")


def regen():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review
    takes = TAKES
    if "--takes" in sys.argv:
        takes = max(1, min(6, int(sys.argv[sys.argv.index("--takes") + 1])))
    use_notes = "--no-notes" not in sys.argv
    rejected = [it for it in review.merged_batch(BATCH)["items"] if it["status"] == "reject"]
    if not rejected:
        print("nothing rejected")
        return
    st = state()
    texts = {"%s.%s" % (w, n): t for w, n, t in plan()}
    directed = []
    for it in rejected:
        aid = it["id"]
        who, _, name = aid.partition(".")
        ent = st.setdefault(aid, {"round": 1})
        ent["round"] = int(ent.get("round", 1)) + 1
        if use_notes and notes.meaningful(it.get("note")):
            directed.append({"id": aid, "text": texts.get(aid, ""), "speak": words(who, name, texts.get(aid, ""), st), "note": it["note"], "who": who})
        tdir = os.path.join(BATCH_DIR, who, ".takes")
        os.makedirs(tdir, exist_ok=True)
        main = take_path(who, name, 1)
        if os.path.exists(main):
            n = 1 + sum(1 for f in os.listdir(tdir) if f.startswith(name + ".r"))
            os.replace(main, os.path.join(tdir, "%s.r%d.mp3" % (name, n)))
        for k in range(2, 10):
            if os.path.exists(take_path(who, name, k)):
                os.remove(take_path(who, name, k))
    if directed:
        print("reading %d note%s…" % (len(directed), "s" if len(directed) != 1 else ""), flush=True)
        for aid, (speak, why, how) in notes.rewrite_speech(directed).items():
            st[aid]["speak"] = speak
            print("  direction (%s): %s: %r%s" % (how, aid, speak, "  (" + why + ")" if why else ""))
    save(st)
    generate(takes, only={it["id"] for it in rejected})


if __name__ == "__main__":
    if "--install" in sys.argv:
        install()
    elif "--regen" in sys.argv:
        regen()
    elif "--batch" in sys.argv:
        write_batch()
    elif "--plan" in sys.argv:
        p = plan()
        n = sum(len(words(w, nm, t, {})) for w, nm, t in p) * TAKES
        print("%d lines x %d takes: %d characters, about $%.2f at $%.2f per 1k ($%.2f on the v4 sale)"
              % (len(p), TAKES, n, n / 1000.0 * el.PRICE_PER_1K, el.PRICE_PER_1K, n / 1000.0 * 0.022))
        for who in ORDER:
            print("  %-8s %3d lines  %s" % (who, sum(1 for w, _, _ in p if w == who), el_cast.load().get(who, {}).get("voice_id", "NO VOICE")))
    else:
        sys.exit(1 if generate() else 0)
