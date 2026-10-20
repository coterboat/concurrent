#!/usr/bin/env python3
"""The cast: which ElevenLabs voice speaks for whom, kept for good.

The owner's picks from the v4 samples (review/el_samples, 30 Sep 2026): the advisor's own voice,
cloned (the cloned voice is the good one), and a designed voice for each commander, by its voice
card. This makes sure each is a saved voice in the account and records its voice_id in
tools/elevenlabs/cast.json, which is what el_lines.py speaks with. Voice ids aren't secrets.

    python3 tools/elevenlabs/el_cast.py          # save what's missing, check the rest still exist, write cast.json
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import el  # noqa: E402
import el_samples as samples  # noqa: E402

CAST_JSON = os.path.join(HERE, "cast.json")
## who -> ("clone", None): the game's own voice, cloned; ("design", k): voice card k of their design
PICKS = {
    "advisor": ("clone", None),
    "varek": ("design", 1),
    "ysolde": ("design", 2),
    "quill": ("design", 1),
    "oren": ("design", 2),
    "hask": ("design", 3),
    "imre": ("design", 3),
}


def load():
    try:
        return json.load(open(CAST_JSON, encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def exists(voice_id):
    try:
        el.get("/v1/voices/%s" % voice_id)
        return True
    except el.Error:
        return False


def ensure():
    cast = load()
    st = samples.state()
    for who, (kind, card) in PICKS.items():
        have = cast.get(who, {})
        if have.get("voice_id") and have.get("kind") == kind and have.get("card") == card and exists(have["voice_id"]):
            print("  %-8s %s: have it (%s)" % (who, "clone" if kind == "clone" else "design card %d" % card, have["voice_id"]))
            continue
        name = "CONCURRENT · %s" % samples.NAMES[who]
        if kind == "clone":
            files, secs = samples.refs(who, "clone")
            vid = el.clone(name, files, "The game's own voice, cloned from %d takes (%.0f s)" % (len(files), secs))
            cast[who] = {"voice_id": vid, "kind": "clone", "card": None, "name": name,
                         "refs": [os.path.relpath(f, ROOT) for f in files], "ref_seconds": round(secs, 1)}
            print("  %-8s cloned from %d takes, %.0f s: %s" % (who, len(files), secs, vid))
        else:
            ent = st.get("%s.design" % who, {})
            cards = ent.get("cards", [])
            if card == 1 and ent.get("voice_id") and exists(ent["voice_id"]):
                vid = ent["voice_id"] ## the sample run saved card 1 already
            else:
                vid = el.save_design(name, samples.DESIGNS[who], cards[card - 1]["generated_voice_id"])
            cast[who] = {"voice_id": vid, "kind": "design", "card": card, "name": name,
                         "description": samples.DESIGNS[who], "card_file": "review/el_samples/" + cards[card - 1]["file"]}
            print("  %-8s design card %d: %s" % (who, card, vid))
        json.dump(cast, open(CAST_JSON, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    return cast


if __name__ == "__main__":
    try:
        ensure()
    except el.Error as e:
        sys.exit("elevenlabs: %s" % e)
    print("cast.json: %d voices" % len(load()))
