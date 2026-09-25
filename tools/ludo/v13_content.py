#!/usr/bin/env python3
"""v1.3 content: cavalry and cannon, more tin-soldier moves, music that loops.

    python3 tools/ludo/v13_content.py            # stage 1: figures, music, sound, infantry moves
    python3 tools/ludo/v13_content.py --figures  # stage 2: cavalry + cannon animations (after padding)

Stage 2 animates the padded cavalry/cannon (tools/sheet_tool.gd pad), so every sheet of a
figure shares one canvas and nothing clips. Versions bump when a prompt changes.
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")

TIN = "the whole figure painted pure white and very light grey with no other colors, glossy painted tin-soldier miniature look, isolated on a plain white background"

FIGURES = {
    "cavalry_stand": ("ar_4_3", "A single toy cavalry dragoon on horseback, the rider in a tall crested helmet holding a sabre upright, the horse standing square, full body side view facing right, " + TIN),
    "cannon_stand": ("ar_4_3", "A single toy field cannon on a wooden-wheeled carriage with two artillerymen crew standing beside it holding a rammer, full body side view with the barrel pointing right, " + TIN),
}

## id, source pad, motion, loop-closing (final = first frame)
INFANTRY = [
    ("soldier_kneel", "soldier_stand", "kneels on one knee, aims the musket straight ahead to the right and fires with a puff of smoke from the muzzle, then stands back up exactly as at the start"),
    ("soldier_reload", "soldier_stand", "reloads the musket: bites a cartridge and rams the ramrod down the barrel, then shoulders the musket exactly as at the start"),
    ("soldier_charge", "soldier_stand", "charges forward at a run with the bayonet levelled to the right, a running cycle"),
    ("soldier_cheer", "soldier_stand", "raises the musket high above his head and cheers in victory, then lowers it back exactly as at the start"),
]
FIGURE_ANIMS = [
    ("cavalry_idle", "cavalry_stand", "the horse shifts its weight and swishes its tail while the rider sits still, subtle idle motion"),
    ("cavalry_gallop", "cavalry_stand", "gallops forward in place, a smooth gallop cycle, the rider holding the sabre"),
    ("cavalry_charge", "cavalry_stand", "charges at full gallop with the sabre pointed forward, a gallop cycle"),
    ("cavalry_rear", "cavalry_stand", "the horse rears up on its hind legs while the rider raises the sabre high, then comes back down exactly as at the start"),
    ("cannon_idle", "cannon_stand", "the crew stand ready beside the cannon, breathing, small natural movements"),
    ("cannon_fire", "cannon_stand", "the cannon fires with a big burst of smoke and flame from the muzzle on the right and recoils backward, then the crew roll it back into place exactly as at the start"),
    ("cannon_reload", "cannon_stand", "the crew swab and ram the barrel, then stand ready again exactly as at the start"),
]

LOOP = "Seamless loop: steady intensity from the first bar to the last, no intro, no fade, no big ending, no final crescendo"
MUSIC = [
    ("music_menu_2", "menu_2", 150, "Imperial march for a conquest strategy game: proud brass melody over marching snare and timpani, strings and a wordless choir, confident and glorious. " + LOOP),
    ("music_plan_2", "plan_2", 150, "War council music: a steady military snare cadence, pizzicato strings and low brass, fifes in the distance, a quiet menace of armies gathering. " + LOOP),
    ("music_plan_3", "plan_3", 150, "Map-room strategy music: harpsichord and strings over a soft war drum pulse, scheming and determined, empires plotting conquest. " + LOOP),
    ("music_battle_2", "battle_2", 150, "Relentless battle march: pounding war drums, snare rolls, blaring brass fanfares, fife and drum corps, cannon-like timpani hits. " + LOOP),
    ("music_battle_3", "battle_3", 150, "Driving orchestral war music: galloping low strings ostinato, stabbing brass, big drums, heroic and aggressive, a world at war. " + LOOP),
    ("music_charge_2", "charge_2", 120, "Cavalry charge battle music: breathless galloping strings, bugle calls, crashing cymbals, brass heroics. " + LOOP),
    ("music_charge_3", "charge_3", 120, "Fierce skirmish music for a tabletop battle: snare drums, fifes, brass stabs and rolling timpani, tense and exciting. " + LOOP),
    ("music_muster", "muster", 150, "Troops redeploying between battles: a steady marching drum and fife tune with low strings, purposeful and brisk, soldiers on the move. " + LOOP),
]
SFX = {
    "melee": ("a chaotic melee: many muskets and sabres clashing, shouts from several sides, short", 3),
    "border_clash": ("two marching columns collide head on: drums, a roar and a crash of steel, short", 3),
    "maneuver": ("a company of soldiers marching off to a new post with a drum beat, short", 2),
    "neigh": ("a war horse neighs and rears, short", 2),
    "cannon_big": ("a heavy field cannon fires, deep boom, echo and rumble", 3),
    "cards_open": ("a leather folio opened and playing cards fanned out on a table", 2),
    "turn_in": ("cards slapped down on a table followed by a trumpet flourish and coins", 2),
    "zoom_in": ("a short whoosh with a low drum hit, a camera swooping down on a battlefield", 1),
}


## Commander voices, take two: the advisor's clone came from a long, calm sample; the
## commanders' from short shouted greets. These samples are long and varied, and the
## descriptions ask for natural speech. They land in assets/voice13 (Settings picks).
VOICES2 = {
    "varek": ("Elderly British army field marshal, deep weathered baritone, slow and deliberate, dry and stern, clipped aristocratic delivery, natural conversational speech",
              "Grand Marshal Varek. I have buried a hundred generals, and every one of them taught me patience. Advance. Fix bayonets. We take the ridge by nightfall, and we hold it until the sun comes up again."),
    "ysolde": ("Aristocratic English woman in her forties, cool low alto, crisp precise diction, measured and imperious, natural speech",
               "Viceroy Ysolde. I do not raise my voice, Commander, and I do not repeat myself. Take the fort. Leave nothing standing. When it is done, you may tell me how easy it was."),
    "quill": ("Middle-aged English merchant governor, jovial and sly, slightly nasal tenor, quick chatty delivery with a smile in the voice, natural speech",
              "Governor Quill, of the Company, at your service. Everything has its price, my friend, even a war. Especially a war. Now then, shall we discuss terms, or shall I simply send the lads?"),
    "oren": ("Young English cavalry officer in his early twenties, bright tenor, eager and cheerful, fast excited delivery, natural speech",
             "Captain Oren of the Hussars! Honestly, this is my very first war, but I have an excellent horse and I have read absolutely every book. Right then. Charge! No, wait. Yes. Charge!"),
    "hask": ("Big Scottish sea captain in his fifties, deep booming bass, hearty and rough, chuckles as he talks, natural speech",
             "Commodore Hask, the Old Bear himself! I have sunk more ships than you have eaten suppers, laddie. Bring me your best, and bring me a drink while you are at it. Ha! We sail at dawn."),
    "imre": ("Hungarian-accented woman naval officer in her thirties, low calm alto, dry wit, unhurried precise delivery, natural speech",
             "Admiral Imre. I read your plan before you finished writing it. It was a good plan. Mine is better. Proceed, Commander, and try not to look surprised when it all goes exactly as I said."),
}


def stage_voices():
    sys.path.insert(0, os.path.dirname(__file__))
    import v12_content
    out = []
    for who, (desc, sample) in VOICES2.items():
        out.append({"id": "voice2_" + who, "kind": "voice", "describe": desc, "text": sample, "out": "assets/voice13/%s/_sample" % who})
        for key, text in v12_content.LINES[who].items():
            out.append({"id": "line2_%s_%s" % (who, key), "kind": "speech", "voice": "voice2_" + who, "text": text,
                        "out": "assets/voice13/%s/%s" % (who, key)})
    return out


def bump(old, e):
    o = old.get(e["id"])
    if o is None:
        return int(e.get("v", 1))
    keys = ("prompt", "text", "from", "from_file", "kind", "type", "cutout", "duration")
    if any(o.get(k) != e.get(k) for k in keys if k in e or k in o):
        return max(int(o.get("v", 1)) + 1, int(e.get("v", 1)))
    return int(o.get("v", 1))


def stage1():
    out = []
    for fid, (aspect, prompt) in FIGURES.items():
        out.append({"id": fid, "kind": "image", "type": "sprite", "cutout": True, "style": False,
                    "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": aspect,
                    "out": "assets/raw/battle/" + fid, "prompt": prompt})
    for aid, src, motion in INFANTRY:
        e = {"id": aid + "_anim", "kind": "animate", "from_file": "assets/raw/battle/%s_pad.png" % src, "prompt": motion,
             "image_type": "sprite", "model": "forge", "duration": 2, "frames": 16, "frame_size": -9, "loop": False,
             "crop": False, "out": "assets/raw/battle/" + aid}
        if aid != "soldier_charge":
            e["final_same"] = True
        else:
            e["final_same"] = True  ## a run cycle also closes on its first stride
        out.append(e)
    for aid, name, dur, prompt in MUSIC:
        out.append({"id": aid, "kind": "music", "duration": dur, "out": "assets/audio/music/" + name, "prompt": prompt})
    for key, (prompt, dur) in SFX.items():
        out.append({"id": "sfx_" + key, "kind": "sfx", "duration": dur, "out": "assets/audio/sfx/" + key, "prompt": prompt})
    return out


def stage2():
    out = []
    for aid, src, motion in FIGURE_ANIMS:
        out.append({"id": aid + "_anim", "kind": "animate", "from_file": "assets/raw/battle/%s_pad.png" % src, "prompt": motion,
                    "image_type": "sprite", "model": "forge", "duration": 2, "frames": 16, "frame_size": -9, "loop": False,
                    "crop": False, "final_same": True, "out": "assets/raw/battle/" + aid})
    return out


def main():
    man = json.load(open(MAN))
    old = {a["id"]: a for a in man["assets"]}
    new = stage2() if "--figures" in sys.argv else (stage_voices() if "--voices" in sys.argv else stage1())
    for e in new:
        e["v"] = bump(old, e)
    ids = {a["id"] for a in new}
    man["assets"] = [a for a in man["assets"] if a["id"] not in ids] + new
    json.dump(man, open(MAN, "w"), indent=1)
    print("manifest now %d assets; stage has %d" % (len(man["assets"]), len(new)))
    print(" ".join(a["id"] for a in new))


if __name__ == "__main__":
    main()
