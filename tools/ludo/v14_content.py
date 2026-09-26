#!/usr/bin/env python3
"""v1.4 content: soldiers who aim the right way round, dice you can hear, cheers that
grow with the army, Oren and Ysolde recast, and lines for the land draft.

    python3 tools/ludo/v14_content.py            # stage 1: poses, sounds, voices, lines
    python3 tools/ludo/v14_content.py --anims    # stage 2: firing loops (after padding the poses)

Stage 2 animates the padded aiming poses (tools/sheet_tool.gd pad), so the muzzle is
fixed on the right before the model ever moves the figure. Versions bump when a prompt
changes; the recast voices force their lines to be spoken again.
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")
LINES_JSON = os.path.join(ROOT, "game", "data", "lines.json")

## the v1.2 fire/kneel loops held the musket butt-first: pose the aim, then animate only the shot
POSES = {
    "soldier_aim": "The same toy soldier now standing and aiming his musket to the right: the wooden butt of the musket tucked into his right shoulder, his cheek against the stock, the long steel barrel and bayonet pointing straight out level to the right, same white colors, same side view facing right, holding only one musket",
    "soldier_kneel_aim": "The same toy soldier now kneeling on one knee and aiming his musket to the right: the wooden butt of the musket tucked into his shoulder, his cheek against the stock, the long steel barrel and bayonet pointing straight out level to the right, same white colors, same side view facing right, holding only one musket",
}
ANIMS = [
    ("soldier_volley", "soldier_aim", "fires the musket: a bright flash and a puff of white smoke burst from the muzzle at the far right end of the barrel, the shoulder kicks back with the recoil, then he steadies his aim again exactly as at the start"),
    ("soldier_kneel_volley", "soldier_kneel_aim", "fires the musket from the knee: a bright flash and a puff of white smoke burst from the muzzle at the far right end of the barrel, the shoulder kicks back with the recoil, then he steadies his aim again exactly as at the start"),
]

## the edits drifted (lost the musket, changed the uniform): fresh figures instead, two ways each
TIN = "the whole figure painted pure white and very light grey with no other colors, glossy painted tin-soldier miniature look, isolated on a plain white background"
FIGS = {
    "soldier_aim": "A single toy soldier of imperial line infantry, tall shako with a plume, crossbelts and tailcoat, standing and aiming his long musket straight out to the right: the wooden butt tucked into his shoulder, cheek on the stock, the barrel and bayonet level and pointing right, full body side view facing right, " + TIN,
    "soldier_kneel_aim": "A single toy soldier of imperial line infantry, tall shako with a plume, crossbelts and tailcoat, kneeling on one knee and aiming his long musket straight out to the right: the wooden butt tucked into his shoulder, cheek on the stock, the barrel and bayonet level and pointing right, full body side view facing right, " + TIN,
}

TRAY = ("Top-down view of an empty campaign dice tray: a deep green baize felt surface inside a polished dark mahogany frame "
        "with brass corner fittings, soft even light from above, flat, no dice, no text")

SFX = {
    ## the dice: a shake, a throw, and single knocks for each bounce by what the die is made of
    "dice_shake": ("two dice rattled quickly in a leather dice cup, close up, dry, no music", 1),
    "dice_throw": ("a handful of dice thrown onto a wooden table, tumbling and clattering across the wood, then coming to rest, close up", 2),
    "dice_click": ("a single ivory die hitting a hardwood table top once, one sharp dry click, close up, nothing else", 1),
    "dice_knock": ("a small rough wooden die knocking once on a wooden table, one dull hollow tok, close up, nothing else", 1),
    "dice_clunk": ("a heavy solid brass die dropped once on a wooden table, one weighty metallic clunk, close up, nothing else", 1),
    "dice_settle": ("a single die rocking to a stop on a wooden table, a tiny rattle then silence, close up", 1),
    ## victory, by the size of the army that won
    "cheer_few": ("three or four soldiers give one short victorious cheer, huzzah, close up, no music", 2),
    "cheer_company": ("a company of about forty soldiers cheering huzzah together in victory, short, no music", 3),
    "cheer_army": ("a vast army of thousands roaring in triumph across a battlefield, huge and distant, short, no music", 4),
    ## the land draft
    "flag_plant": ("a flagpole driven into the earth with a solid thud and a flag snapping open in the wind", 2),
    "fanfare_order": ("a short bright brass fanfare of three notes announcing the order of play", 2),
    "war_chest": ("a heavy iron-bound chest thrown open, coins and papers spilling out, a short triumphant brass sting", 2),
}

## Oren's second take sounded like a princess, and Ysolde goes east. Everyone else keeps take two.
VOICES = {
    "oren": ("Young British man in his twenties, dashing hussar cavalry captain, clear masculine voice, cocky and boyish, overconfident swagger, speaks fast, natural speech",
             "Captain Oren of the Hussars! First war, yes, but I have the fastest horse in the regiment and I have read every book on cavalry. Right then, lads. Sabres out. Charge!"),
    "ysolde": ("Russian aristocratic woman in her forties, strong Russian accent, cool low alto, imperious and unhurried, crisp precise speech, natural speech",
               "Viceroy Ysolde. In my country the winter kills more men than cannon, and I am colder than the winter. Take the fort. Leave nothing standing. Then you may tell me how easy it was."),
}

## new lines (text shared with the subtitles in game/data/lines.json)
NEW_LINES = {
    "advisor": {
        "draft_roll": "Every commander throws a die. The highest roll claims first, and so on round the table.",
        "draft_first": "Fortune smiles, Commander. We choose first. Take the land that matters most.",
        "draft_pick": "Our pick, Commander. Claim a land.",
        "cards_seized": "Their war chest is ours, Commander. Every card they held now fights for us.",
        "scramble": "The defenders are finished. Now the victors turn on each other. Every man for himself!",
    },
    "varek": {"claim": "This ground is mine. Dig in."},
    "ysolde": {"claim": "I will take this one. Remember who chose first."},
    "quill": {"claim": "A fine piece of property. I will take it."},
    "oren": {"claim": "Ooh, that one! I call that one!"},
    "hask": {"claim": "Ha! Plant my flag there, lads!"},
    "imre": {"claim": "That one. You were about to take it, were you not?"},
}


def bump(old, e):
    o = old.get(e["id"])
    if o is None:
        return int(e.get("v", 1))
    keys = ("prompt", "text", "describe", "from", "from_file", "kind", "type", "cutout", "duration", "voice_v")
    if any(o.get(k) != e.get(k) for k in keys if k in e or k in o):
        return max(int(o.get("v", 1)) + 1, int(e.get("v", 1)))
    return int(o.get("v", 1))


def lines():
    d = json.load(open(LINES_JSON))
    for who, add in NEW_LINES.items():
        d["lines"].setdefault(who, {}).update(add)
    json.dump(d, open(LINES_JSON, "w"), indent=1)
    return d["lines"]


def stage1(old):
    out = []
    for pid, prompt in POSES.items():
        out.append({"id": pid, "kind": "edit", "from": "soldier_stand", "cutout": True, "out": "assets/raw/battle/" + pid, "prompt": prompt})
    out.append({"id": "dice_tray", "kind": "image", "type": "art", "style": False, "art_style": "Digital Painting",
                "perspective": "Top-Down", "aspect": "ar_16_9", "out": "assets/battle/dice_tray", "prompt": TRAY})
    for key, (prompt, dur) in SFX.items():
        out.append({"id": "sfx_" + key, "kind": "sfx", "duration": dur, "out": "assets/raw/sfx/" + key, "prompt": prompt})
    all_lines = lines()
    for who, (desc, sample) in VOICES.items():
        out.append({"id": "voice2_" + who, "kind": "voice", "describe": desc, "text": sample, "out": "assets/voice13/%s/_sample" % who})
    ## every commander's take-two voice speaks the lines (a recast voice speaks all of them again)
    for who in ["varek", "ysolde", "quill", "oren", "hask", "imre"]:
        recast = who in VOICES
        for key, text in all_lines[who].items():
            if not recast and key != "claim":
                continue
            e = {"id": "line2_%s_%s" % (who, key), "kind": "speech", "voice": "voice2_" + who, "text": text,
                 "out": "assets/voice13/%s/%s" % (who, key)}
            if recast:
                e["voice_v"] = 2
            out.append(e)
    for key in NEW_LINES["advisor"]:
        out.append({"id": "line_advisor_" + key, "kind": "speech", "voice": "voice_advisor", "text": all_lines["advisor"][key],
                    "out": "assets/voice/advisor/" + key})
    return out


def stage_figs():
    out = []
    for fid, prompt in FIGS.items():
        out.append({"id": fid + "_img", "kind": "image", "type": "sprite", "cutout": True, "style": False,
                    "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": "ar_4_3",
                    "out": "assets/raw/battle/%s_img" % fid, "prompt": prompt})
        out.append({"id": fid + "_sty", "kind": "styled", "style_from": "soldier_stand", "type": "sprite", "cutout": True,
                    "out": "assets/raw/battle/%s_sty" % fid, "prompt": prompt})
    return out


HOWTO = {
    "howto_dice": "Two rival generals' hands throwing dice onto a green baize campaign dice tray on a war table among maps and tin soldiers: one throws rough wooden dice, the other gleaming gold dice with jewelled pips, candlelight",
    "howto_scramble": "Three armies in crimson, navy blue and green coats storming a burning hilltop fort from three sides, then turning their muskets on each other in the smoke, battle flags everywhere, chaos",
    "howto_draft": "Rival commanders leaning over a great map table, planting little coloured flags on a painted map of unclaimed lands while dice on the table decide who chooses first, candlelight",
}


def stage_howto():
    return [{"id": hid, "kind": "image", "type": "art", "aspect": "ar_16_9", "out": "assets/art/" + hid, "prompt": prompt}
            for hid, prompt in HOWTO.items()]


def stage2():
    out = []
    for aid, src, motion in ANIMS:
        out.append({"id": aid + "_anim", "kind": "animate", "from_file": "assets/raw/battle/%s_pad.png" % src, "prompt": motion,
                    "image_type": "sprite", "model": "forge", "duration": 2, "frames": 16, "frame_size": -9, "loop": False,
                    "crop": False, "final_same": True, "out": "assets/raw/battle/" + aid})
    return out


def main():
    man = json.load(open(MAN))
    old = {a["id"]: a for a in man["assets"]}
    if "--howto" in sys.argv:
        new = stage_howto()
    else:
        new = stage2() if "--anims" in sys.argv else (stage_figs() if "--figs" in sys.argv else stage1(old))
    for e in new:
        e["v"] = bump(old, e)
    ids = {a["id"] for a in new}
    man["assets"] = [a for a in man["assets"] if a["id"] not in ids] + new
    json.dump(man, open(MAN, "w"), indent=1)
    print("manifest now %d assets; stage has %d" % (len(man["assets"]), len(new)))
    print(" ".join(a["id"] for a in new))


if __name__ == "__main__":
    main()
