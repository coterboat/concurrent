#!/usr/bin/env python3
"""v1.5 content: muskets that boom, cavalry in rhythm, a distant battle under the battle,
phase stings, and voices for turning in cards.

    python3 tools/ludo/v15_content.py      # writes the manifest entries + game/data/lines.json
    python3 tools/ludo/ludo.py <ids>        # then generate them
    python3 tools/ludo/prep_sfx.py          # and cut the sounds (see PLAN there)
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")
LINES_JSON = os.path.join(ROOT, "game", "data", "lines.json")

SFX = {
    ## the v1.2 volley was a pop gun: black powder is a violent crack and a boom that rolls away
    "musket_volley_1": ("a volley of a dozen 19th-century flintlock muskets fired together at close range, a violent deafening crack of black powder and a heavy boom that echoes across a battlefield, no music", 2),
    "musket_volley_2": ("a ragged line of 19th-century muskets firing in a rolling volley, loud violent cracks and booms of black powder with a long echo, no music", 2),
    "musket_volley_3": ("a company of redcoat soldiers firing their muskets all at once, one enormous booming crack with smoke-thick echo, 19th century battle, no music", 2),
    "musket_shot_1": ("a single heavy 19th-century musket shot very close, a sharp violent crack and deep boom with a short echo, no music", 1),
    "musket_shot_2": ("one Brown Bess flintlock musket firing, the flint snap then a loud booming black powder blast, close up, no music", 1),
    ## horses in a real gallop: three beats and a pause, again and again, coming on
    "cavalry_charge": ("a squadron of heavy cavalry charging at full gallop straight at the listener, thundering rhythmic three-beat gallop of hooves on hard earth, harness jingling, getting louder, no music", 4),
    "cavalry_gallop": ("several war horses galloping past in a steady rhythmic gallop, clear drumming three-beat hoofbeats on packed earth, no music", 3),
    "horse_trample": ("war horses trampling and stamping heavily in place, hooves pounding the ground in a rough rhythm, snorting, no music", 2),
    ## the battle beyond the battle: quiet, far off, now and then
    "far_cannon": ("distant cannon fire rumbling across a wide valley, two or three deep far-off booms, no music", 3),
    "far_volley": ("distant musket volleys crackling far away across a battlefield, faint and echoing, no music", 3),
    "far_drums": ("distant military drums beating a marching rhythm far across a battlefield, faint, no music", 4),
    "far_bugle": ("a distant cavalry bugle call far across a battlefield, faint and echoing, no music", 3),
    "far_shouts": ("distant soldiers shouting and a faint roar of a charge far away across a battlefield, no music", 3),
    ## phases: a drum and brass sting when a new phase begins
    "phase_sting": ("a short military snare drum roll ending on a single bold brass chord, announcing the start of a new phase, no reverb tail", 2),
    "phase_tap": ("a short crisp military snare drum flourish, three strokes, no music", 1),
}

## turning in a set is news: everyone hears it
NEW_LINES = {
    "advisor": {
        "cash_us": "Cards turned in, Commander. Fresh regiments are marching to the front.",
        "cash_them": "They have turned in their cards. Expect a flood of fresh troops across the border.",
        "orders": "The troops are placed, Commander. Now, where do we strike?",
        "surges": "Now the breakthroughs. Every surge charges on at once!",
    },
    "varek": {"cash": "Fresh regiments. Send them to the front."},
    "ysolde": {"cash": "My reserves have arrived. Now you will see an army."},
    "quill": {"cash": "A fine return on the investment. More men, at once!"},
    "oren": {"cash": "Reinforcements! Oh, this is going to be fun!"},
    "hask": {"cash": "More lads for the Bear! Ha!"},
    "imre": {"cash": "I have been saving these. Now they matter."},
}


def bump(old, e):
    o = old.get(e["id"])
    if o is None:
        return int(e.get("v", 1))
    keys = ("prompt", "text", "describe", "kind", "duration")
    if any(o.get(k) != e.get(k) for k in keys if k in e or k in o):
        return max(int(o.get("v", 1)) + 1, int(e.get("v", 1)))
    return int(o.get("v", 1))


def main():
    d = json.load(open(LINES_JSON))
    for who, add in NEW_LINES.items():
        d["lines"].setdefault(who, {}).update(add)
    json.dump(d, open(LINES_JSON, "w"), indent=1)
    out = []
    for key, (prompt, dur) in SFX.items():
        out.append({"id": "sfx_" + key, "kind": "sfx", "duration": dur, "out": "assets/raw/sfx/" + key, "prompt": prompt})
    for key, text in NEW_LINES["advisor"].items():
        out.append({"id": "line_advisor_" + key, "kind": "speech", "voice": "voice_advisor", "text": text, "out": "assets/voice/advisor/" + key})
    for who in ["varek", "ysolde", "quill", "oren", "hask", "imre"]:
        out.append({"id": "line2_%s_cash" % who, "kind": "speech", "voice": "voice2_" + who, "text": NEW_LINES[who]["cash"],
                    "out": "assets/voice13/%s/cash" % who})
    man = json.load(open(MAN))
    old = {a["id"]: a for a in man["assets"]}
    for e in out:
        e["v"] = bump(old, e)
    ids = {a["id"] for a in out}
    man["assets"] = [a for a in man["assets"] if a["id"] not in ids] + out
    json.dump(man, open(MAN, "w"), indent=1)
    print("manifest now %d assets; stage has %d" % (len(man["assets"]), len(out)))
    print(" ".join(a["id"] for a in out))


if __name__ == "__main__":
    main()
