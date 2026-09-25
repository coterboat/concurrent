#!/usr/bin/env python3
"""v1.1 content: leader reactions, voices, soldiers, battlefields, HUD, battle sound.

    python3 tools/ludo/v11_content.py   # rewrites manifest entries + game/data/lines.json

One source of truth for every spoken line: the same text feeds the Ludo speech
jobs and the in-game subtitles, so what you read is what you hear.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")

VOICES = {
    "advisor": "Elderly British military advisor, warm and wise, slightly gravelly, calm measured delivery, reassuring",
    "varek": "Old grizzled field marshal, very deep gravelly voice, slow, stoic and commanding",
    "ysolde": "Stern aristocratic woman general in her forties, cold, crisp, precise and commanding",
    "quill": "Portly sly quartermaster, nasal and amused, quick merchant patter",
    "oren": "Young eager cavalry captain in his twenties, bright, boyish and overconfident",
    "hask": "Huge bearded northern warlord, booming deep voice, rough accent, laughs easily",
    "imre": "Calm sharp-witted woman tactician, low even voice, dry and understated",
}

LINES = {
    "advisor": {
        "welcome": "Welcome to the war table, Commander. Every general writes orders in secret, and every army marches at once.",
        "deploy": "Place your starting armies. Spread too thin and you will be picked apart.",
        "reinforce": "Fresh troops have arrived. Put them where the enemy can reach.",
        "attack_hint": "Select one of our lands, then click the enemy you mean to strike.",
        "vacate_warn": "Careful. That land will be left with a single man. Anyone next door could walk right in.",
        "unplaced": "We still have troops waiting for orders. Unplaced men go home.",
        "sealed": "Orders sealed. Now we learn what the others were planning.",
        "reveal": "There it is. Every army on the map, moving at once.",
        "walkin_us": "A walk-in! They left the door wide open, and we strolled right through.",
        "walkin_them": "Blast. They walked straight into a land we left empty.",
        "capture": "The land is ours.",
        "hold": "Our garrison held. Well fought.",
        "lost_land": "We have lost ground there, Commander.",
        "region": "The whole region is ours. That bonus will swell our ranks every round.",
        "cards": "We hold a matching set of cards. Trade them in for fresh troops.",
        "final": "Final round. Only land counts now. Throw everything you have.",
        "leader": "We lead the war. Every general at this table will be gunning for us now.",
        "behind": "We are falling behind. Time to take a risk.",
        "enemy_out": "One less rival at the table.",
        "defeat": "We are beaten, Commander. There is no shame in a hard-fought war.",
        "victory": "Victory! The war is yours, Commander. Magnificent.",
        "dug_in": "Lands we hold dig in. Dug-in troops never march, so they keep a land safe while the rest go to war.",
        "surge": "A clean breakthrough. With men to spare, we can surge on to the next land.",
        "roll": "Roll the dice, Commander.",
        "good_roll": "The dice favor us!",
        "bad_roll": "Cursed luck.",
        "plan": "Here is what I would do, Commander.",
    },
    "varek": {
        "greet": "Marshal Varek. I have buried better generals than you. Let us begin.",
        "attack": "Advance. Steady ranks.",
        "win": "As expected.",
        "lose": "A setback. Nothing more.",
        "walkin": "You left it empty. I merely accepted the invitation.",
        "eliminated": "My war is over. Remember the old soldier.",
        "victory": "The field is mine. It always was.",
    },
    "ysolde": {
        "greet": "Lady Ysolde. I suggest you guard your doors.",
        "attack": "Take it. Leave nothing standing.",
        "win": "Predictable.",
        "lose": "You will pay for that.",
        "walkin": "An empty keep is an insult to its owner. I have corrected it.",
        "eliminated": "This is not the end of my house.",
        "victory": "Kneel. The realm is mine.",
    },
    "quill": {
        "greet": "The Quartermaster, at your service. Everything has its price.",
        "attack": "An investment opportunity, lads. Go and collect.",
        "win": "Profit!",
        "lose": "Hm. That will cost me.",
        "walkin": "Unguarded goods. Finders keepers.",
        "eliminated": "Bankrupt. Well, it was lovely doing business.",
        "victory": "Tally it up. I own the lot.",
    },
    "oren": {
        "greet": "Captain Oren! First war, but I am a fast learner!",
        "attack": "Charge! For glory!",
        "win": "Ha! Did you see that?",
        "lose": "Wait, that was not supposed to happen!",
        "walkin": "Nobody home? Do not mind if I do!",
        "eliminated": "I will be back. With more horses.",
        "victory": "I won? I won! Somebody tell my mother!",
    },
    "hask": {
        "greet": "Old Bear Hask! Bring me your best, little general!",
        "attack": "Haaa! Break them!",
        "win": "Hah! Soft as butter!",
        "lose": "Grr. Lucky blow.",
        "walkin": "Empty? Then it is mine!",
        "eliminated": "Bah! Pour me a drink. I am done.",
        "victory": "The Bear rules all! Ha ha ha!",
    },
    "imre": {
        "greet": "Commander Imre. I have already read your plan.",
        "attack": "Exactly as planned. Proceed.",
        "win": "Calculated.",
        "lose": "Interesting. I will adjust.",
        "walkin": "You moved. I did not. That was the whole trick.",
        "eliminated": "Well played. I underestimated you.",
        "victory": "Checkmate.",
    },
}

FACES = {
    "triumphant": "Same person, same framing and painting style, now laughing triumphantly with chin raised, eyes bright with victory",
    "angry": "Same person, same framing and painting style, now furious and shouting, brow furrowed, teeth bared",
    "defeated": "Same person, same framing and painting style, now defeated and exhausted, head bowed, soot and a small cut on the cheek, eyes downcast",
}
ADVISOR_FACES = {
    "alarmed": "Same person, same framing and painting style, now alarmed and urgent, eyebrows raised, pointing forward",
    "pleased": "Same person, same framing and painting style, now beaming with pride, warm smile, raising a glass",
}

BATTLEFIELDS = {
    "grass": "rolling green farmland with hedgerows, a dirt road and a small stone bridge",
    "forest": "a clearing in a dense dark forest with old oaks and fallen logs",
    "mountain": "a rocky mountain pass with scree slopes and a narrow trail",
    "desert": "golden sand dunes and a dry wadi with scattered palms",
    "snow": "a snowy tundra plain with frozen pines and drifts",
    "coast": "a sandy beach and rocky shoreline with gentle surf",
    "ash": "grey ash plains with cracked earth, distant smoking volcano and scorched grass",
    "moor": "windswept heather moorland with standing stones and low mist",
}

STYLE_BG = "Painterly battlefield terrain seen from a high angle, like a war-game table, no people, no soldiers, no text, soft even light, room in the middle for two armies"


def entries():
    out = []
    # --- leader reactions (portrait edits)
    for who in ["varek", "ysolde", "quill", "oren", "hask", "imre"]:
        for face, prompt in FACES.items():
            out.append({"id": "face_%s_%s" % (who, face), "kind": "edit", "from": "portrait_" + who,
                        "prompt": prompt, "out": "assets/portraits/%s_%s" % (who, face)})
    for face, prompt in ADVISOR_FACES.items():
        out.append({"id": "face_advisor_%s" % face, "kind": "edit", "from": "portrait_advisor",
                    "prompt": prompt, "out": "assets/portraits/advisor_%s" % face})
    # --- soldiers (light uniforms so the game can tint them per commander)
    out += [
        {"id": "soldier_stand", "kind": "image", "type": "sprite", "cutout": True, "style": False,
         "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": "ar_3_4",
         "out": "assets/battle/soldier_stand",
         "prompt": "A single toy soldier infantryman holding a musket at the ready, tall shako hat, full body, side view facing right, uniform entirely white and very light grey with no other colors, painted wooden miniature look, isolated on a plain white background"},
        {"id": "soldier_fallen", "kind": "edit", "from": "soldier_stand", "cutout": True,
         "out": "assets/battle/soldier_fallen",
         "prompt": "The same toy soldier now fallen flat on the ground on his back, musket dropped beside him, same colors, same side view"},
        {"id": "soldier_flag", "kind": "image", "type": "sprite", "cutout": True, "style": False,
         "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": "ar_3_4",
         "out": "assets/battle/soldier_flag",
         "prompt": "A single toy soldier flag bearer holding a tall pole with a large blank white flag, full body, side view facing right, uniform entirely white and very light grey, painted wooden miniature look, isolated on a plain white background"},
        {"id": "soldier_fire_anim", "kind": "animate", "from": "soldier_stand", "prompt": "raises the musket and fires one shot with a puff of smoke, then lowers it",
         "model": "forge", "duration": 2, "frames": 16, "frame_size": 128, "out": "assets/battle/soldier_fire"},
        {"id": "soldier_fall_anim", "kind": "animate", "from": "soldier_stand", "prompt": "is hit and falls backward to the ground",
         "model": "forge", "duration": 2, "frames": 16, "frame_size": 128, "out": "assets/battle/soldier_fall"},
    ]
    # --- battlefields per terrain
    for key, desc in BATTLEFIELDS.items():
        out.append({"id": "field_" + key, "kind": "image", "type": "fixed_background", "aspect": "ar_16_9",
                    "perspective": "High Angle", "out": "assets/battle/field_" + key,
                    "prompt": "%s. %s" % (desc.capitalize(), STYLE_BG)})
    # --- HUD pieces
    hud = [
        ("hud_ring", "Ornate circular brass medallion frame ring with engraved laurel leaves and rivets, perfectly round, empty see-through center, front view, isolated on plain white background"),
        ("hud_button", "Large round embossed button like a crimson wax seal set in a polished brass rim, blank smooth face with no symbol or text, front view, isolated on plain white background"),
        ("hud_coin", "Small round brass coin button with a raised rim and blank smooth center, no symbol, front view, isolated on plain white background"),
        ("hud_ribbon", "Horizontal crimson cloth ribbon banner with forked swallowtail ends and gold stitched edges, blank, front view, isolated on plain white background"),
    ]
    for key, prompt in hud:
        out.append({"id": key, "kind": "image", "type": "ui_asset", "cutout": True, "out": "assets/hud/" + key, "prompt": prompt})
    # --- battle sound
    sfx = {
        "volley": "a line of muskets firing a single volley together, sharp crack and echo",
        "cannon": "a single field cannon firing, deep boom with rumble",
        "cheer": "a company of soldiers cheering in victory, short",
        "charge": "bugle sounding a short cavalry charge call",
        "drumroll": "short military snare drum roll building tension then stop",
        "hit": "soldier grunts as he falls, muffled, short, not gory",
        "banner": "heavy cloth battle flag snapping in the wind, short",
    }
    for key, prompt in sfx.items():
        out.append({"id": "sfx_" + key, "kind": "sfx", "duration": 2, "out": "assets/audio/sfx/" + key, "prompt": prompt})
    out.append({"id": "amb_battle", "kind": "ambiance", "duration": 10, "out": "assets/audio/music/ambience_battle",
                "prompt": "distant battlefield: far-off musket fire, occasional cannon, wind, muffled shouting, no music"})
    # --- voices: design once, then clone for every line
    for who, desc in VOICES.items():
        first = next(iter(LINES[who].values()))
        out.append({"id": "voice_" + who, "kind": "voice", "describe": desc, "text": first[:200],
                    "out": "assets/voice/%s/_sample" % who})
    for who, lines in LINES.items():
        for key, text in lines.items():
            out.append({"id": "line_%s_%s" % (who, key), "kind": "speech", "voice": "voice_" + who, "text": text,
                        "out": "assets/voice/%s/%s" % (who, key)})
    return out


def main():
    man = json.load(open(MAN))
    new = entries()
    ids = {a["id"] for a in new}
    man["assets"] = [a for a in man["assets"] if a["id"] not in ids] + new
    json.dump(man, open(MAN, "w"), indent=1)
    os.makedirs(os.path.join(ROOT, "game", "data"), exist_ok=True)
    json.dump({"voices": VOICES, "lines": LINES}, open(os.path.join(ROOT, "game", "data", "lines.json"), "w"), indent=1)
    print("manifest now %d assets (%d new-or-updated)" % (len(man["assets"]), len(new)))


if __name__ == "__main__":
    main()
