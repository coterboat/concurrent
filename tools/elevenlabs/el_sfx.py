#!/usr/bin/env python3
"""ElevenLabs sound effects (batch `el_sfx`): battle sounds for the slots the game already plays, to
hear against what's there. 3 takes of each; `0` in the review table plays the game's own file.

The slots: `shot` (one man firing: musket_shot_1-2), `volley` (a line firing: musket_volley_1-3,
picked at random), the cannon (cannon, cannon_big), and the melee. Each take is cut to start on
its first sound (a shot lands on the muzzle flash) and loudness-matched to the file it would replace.

    python3 tools/elevenlabs/el_sfx.py --plan   # what it would make; no calls
    python3 tools/elevenlabs/el_sfx.py          # make what's missing, write the batch
    python3 tools/elevenlabs/el_sfx.py --install  # the table's button: accepted takes replace those files

Needs ELEVENLABS_API_KEY in .env.local.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "voicestudio"))
import el  # noqa: E402
import vs_samples as base  # noqa: E402

BATCH = "el_sfx"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
TAKES = 3
SHOT = ("A single flintlock musket fired outdoors: the flint snaps, the priming pan flashes with a short hiss, "
        "then one sharp, heavy black-powder crack with a quick echo off an open field.")
VOLLEY = ("A line of thirty Napoleonic infantrymen firing their flintlock muskets in one ragged volley: a rolling "
          "crackle of black-powder shots within a second, then the echo rumbling away across an open battlefield.")
## the game's file -> (what it should sound like, seconds)
SLOTS = {
    "musket_shot_1.wav": (SHOT, 0.8),
    "musket_shot_2.wav": (SHOT + " A little farther off.", 0.6),
    "musket_volley_1.wav": (VOLLEY, 1.6),
    "musket_volley_2.wav": (VOLLEY + " Close, the nearest muskets loudest.", 1.6),
    "musket_volley_3.wav": (VOLLEY + " A longer line, the shots spread wider.", 2.0),
    "cannon.mp3": ("A Napoleonic field cannon firing: a deep, heavy black-powder boom you feel in the chest, "
                   "then a long rolling echo across open country.", 2.0),
    "cannon_big.mp3": ("A battery of heavy Napoleonic guns firing together: an enormous deep boom that shakes the ground, "
                       "then a long rumbling echo.", 2.4),
    "melee.mp3": ("A close-quarters bayonet fight between two lines of Napoleonic infantry: steel scraping on steel, "
                  "musket stocks thudding, men grunting and shouting, boots churning mud.", 3.0),
}


def take_path(slot, k):
    stem, ext = os.path.splitext(slot)
    return os.path.join(BATCH_DIR, slot) if k == 1 else os.path.join(BATCH_DIR, ".takes", "%s.t%d%s" % (stem, k, ext))


def finish(mp3, out, target):
    """start on the first sound, match the game file's loudness, and its format (wav: 44.1 kHz stereo)"""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    raw = out + ".raw.mp3"
    with open(raw, "wb") as f:
        f.write(mp3)
    lufs = base.lufs(target) if os.path.exists(target) else -16.0
    af = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.01,loudnorm=I=%.1f:TP=-1.0:LRA=11" % lufs
    codec = ["-c:a", "pcm_s16le", "-ac", 2] if out.endswith(".wav") else ["-c:a", "libmp3lame", "-q:a", 2, "-ac", 2]
    base.run("-i", raw, "-af", af, "-ar", 44100, *codec, out)
    os.remove(raw)


def state():
    try:
        return json.load(open(os.path.join(BATCH_DIR, "state.json")))
    except (OSError, ValueError):
        return {}


def save(st):
    os.makedirs(BATCH_DIR, exist_ok=True)
    json.dump(st, open(os.path.join(BATCH_DIR, "state.json"), "w"), indent=1)


def make_all():
    st = state()
    for slot, (text, secs) in SLOTS.items():
        for k in range(1, TAKES + 1):
            out = take_path(slot, k)
            if os.path.exists(out):
                continue
            finish(el.sound_effect(text, secs), out, os.path.join(SFX, slot))
            st.setdefault(slot, {})["t%d" % k] = {"seconds": secs}
            save(st)
        print("  %-20s %d takes" % (slot, TAKES), flush=True)


def write_batch():
    items = []
    for slot, (text, secs) in SLOTS.items():
        if not os.path.exists(take_path(slot, 1)):
            continue
        info = {os.path.relpath(take_path(slot, k), BATCH_DIR): "" for k in range(1, TAKES + 1) if os.path.exists(take_path(slot, k))}
        group = "shot" if "shot" in slot else "volley" if "volley" in slot else "cannon" if "cannon" in slot else "melee"
        items.append({"id": os.path.splitext(slot)[0], "kind": "audio", "group": group,
                      "label": "%s · ElevenLabs sound effects" % slot, "text": text, "file": slot,
                      "target": os.path.relpath(os.path.join(SFX, slot), ROOT),
                      "meta": {"engine": "ElevenLabs text-to-sound (%.1f s asked)" % secs, "prompt": text, "take_info": info}})
    me = os.path.relpath(os.path.abspath(__file__), ROOT)
    os.makedirs(BATCH_DIR, exist_ok=True)
    json.dump({"batch": BATCH, "title": "ElevenLabs sound effects: musket fire, cannon, melee (0 = the game's sound)",
               "actions": [{"id": "install", "kind": "install", "label": "Put accepted in the game",
                            "help": "Each accepted take replaces that sound in the game (the old one stays in git history).",
                            "cmd": ["python3", me, "--install"]}],
               "items": items}, open(os.path.join(BATCH_DIR, "batch.json"), "w"), indent=1, ensure_ascii=False)
    print("batch: %d sounds" % len(items))


def install():
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "review", "review.py"), "apply", BATCH], check=True)
    godot = os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot")
    if os.path.exists(godot):
        subprocess.run([godot, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("imported")


if __name__ == "__main__":
    if "--install" in sys.argv:
        install()
    elif "--plan" in sys.argv:
        for slot, (text, secs) in SLOTS.items():
            print("  %-20s %.1f s x%d  %s" % (slot, secs, TAKES, text[:70]))
    else:
        acct = el.account_or_none()
        try:
            make_all()
        except el.Error as e:
            write_batch()
            print("elevenlabs: %s" % e)
            sys.exit(3 if "missing the permission" in str(e) else 1)
        write_batch()
        after = el.account_or_none()
        if acct and after:
            print("%d credits spent" % (acct["left"] - after["left"]))
