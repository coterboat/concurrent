#!/usr/bin/env python3
"""v1.2 content: the imperial re-theme, looping leaders, battle calls, martial sound.

    python3 tools/ludo/v12_content.py   # rewrites manifest entries + game/data/lines.json

Every asset that changes gets its version bumped, so ludo.py regenerates it (the old
file is replaced) and anything built from it waits for the new version.
One source of truth for spoken lines: the same text feeds Ludo speech and subtitles.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")

STYLE = {
    "art_style": "Digital Painting",
    "image": "Grand imperial oil painting in the tradition of 18th-century history painting and Age of Sail maritime art, rich glazes, dramatic golden light and deep shadow, palette of imperial crimson, royal navy blue, burnished gold, ivory and gunpowder grey, heroic and triumphant, no text, no letters, no watermark",
}

## ---------------------------------------------------------------- voices + lines
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
        "welcome": "Welcome to the war table, Commander. The world is wide, the maps are blank, and every inch of it is ours for the taking.",
        "deploy": "Plant our flag and pour in the troops. Spread too thin and the vultures will pick us apart.",
        "reinforce": "Fresh regiments off the boats, Commander. Send them where the fighting is.",
        "attack_hint": "Select one of our lands, then click the enemy you mean to crush.",
        "vacate_warn": "Careful. March them all out and that land stands empty. Any jackal next door could stroll right in.",
        "unplaced": "We have regiments idling on the docks. Unplaced men go home, and I will not have it.",
        "sealed": "Orders sealed. Now we see who flinches.",
        "reveal": "There it is. Every army on the map, marching at once. Glorious.",
        "walkin_us": "A walk-in! They left the gates wide open and we marched straight through. Plant the flag!",
        "walkin_them": "Blast! They walked straight into a land we left empty.",
        "capture": "Another land for the empire!",
        "hold": "Our garrison held. Let them break their teeth on our walls.",
        "lost_land": "We have lost ground there, Commander. We will take it back with interest.",
        "region": "The whole region flies our colours. Its riches will swell our ranks every round.",
        "cards": "We hold a matching set of cards. Cash them in and call up the regiments.",
        "final": "Final round, Commander! Only land counts now. Throw in everything. Leave nothing in the barracks.",
        "leader": "We lead the war. Every crown at this table wants our head. Let them come.",
        "behind": "We are falling behind. Fortune favours the bold, Commander. Attack!",
        "enemy_out": "One less rival for the throne. Their lands are ripe for the taking.",
        "defeat": "We are beaten, Commander. Even empires fall. But what a war it was.",
        "victory": "Victory! The world bows to you, Commander. Magnificent. Utterly magnificent.",
        "dug_in": "Lands we hold dig in. Dug-in troops never march, so they keep a land safe while the rest go conquering.",
        "surge": "A clean breakthrough! With men to spare, we can surge on to the next land.",
        "roll": "Roll the dice, Commander.",
        "good_roll": "The dice love us today!",
        "bad_roll": "Cursed luck!",
        "plan": "Here is what I would do, Commander.",
        "press": "They are breaking! Press the attack!",
        "retreat": "Sound the retreat! Save the men for another day.",
        "reserves": "Send in the reserves! Every last man!",
        "cut_off": "We are cut off, Commander. There is no retreat. Fight or die.",
        "opening_bad": "A bloody opening. Fall back now and save the men, or press on and pray.",
        "opening_good": "A glorious opening! One more push and the land is ours.",
    },
    "varek": {
        "greet": "Grand Marshal Varek. I have buried a hundred generals. You will be a hundred and one.",
        "attack": "Advance. Fix bayonets. No quarter.",
        "win": "As expected.",
        "lose": "A setback. They will pay for it in blood.",
        "walkin": "You left it empty. I merely accepted the invitation.",
        "eliminated": "My war is over. Remember the old soldier.",
        "victory": "The world is mine. It always was.",
        "retreat": "Fall back. Regroup. We return at dawn.",
        "reserves": "Bring up the reserves. End this.",
    },
    "ysolde": {
        "greet": "Viceroy Ysolde. Every land at this table will fly my banner. Guard your doors.",
        "attack": "Take it. Leave nothing standing.",
        "win": "Predictable.",
        "lose": "You will pay for that. Dearly.",
        "walkin": "An empty fort is an insult to its owner. I have corrected it.",
        "eliminated": "This is not the end of my house.",
        "victory": "Kneel. The empire is mine.",
        "retreat": "Withdraw. For now.",
        "reserves": "Send everything. I do not lose.",
    },
    "quill": {
        "greet": "Governor Quill, of the Company. Everything has its price, and I intend to buy the world.",
        "attack": "An investment opportunity, lads. Go and collect.",
        "win": "Profit!",
        "lose": "Hm. That will cost me.",
        "walkin": "Unguarded goods. Finders keepers.",
        "eliminated": "Bankrupt. Well, it was lovely doing business.",
        "victory": "Tally it up. The Company owns the lot.",
        "retreat": "Cut our losses, lads. Back to the ships.",
        "reserves": "Double the investment! Send the reserves!",
    },
    "oren": {
        "greet": "Captain Oren of the Hussars! First war, but I have a very fast horse!",
        "attack": "Charge! For glory!",
        "win": "Ha! Did you see that?",
        "lose": "Wait, that was not supposed to happen!",
        "walkin": "Nobody home? Do not mind if I do!",
        "eliminated": "I will be back. With more horses.",
        "victory": "I won? I won! Somebody tell my mother!",
        "retreat": "Retreat! Tactical retreat! Very tactical!",
        "reserves": "Everybody! Everybody charge!",
    },
    "hask": {
        "greet": "Commodore Hask, the Old Bear! Bring me your best, little general, and I will sink it!",
        "attack": "Haaa! Break them! Burn their boats!",
        "win": "Hah! Soft as butter!",
        "lose": "Grr. Lucky blow.",
        "walkin": "Empty? Then it is mine!",
        "eliminated": "Bah! Pour me a drink. I am done.",
        "victory": "The Bear rules land and sea! Ha ha ha!",
        "retreat": "Back to the ships! I will be back for you!",
        "reserves": "More! Send more! The Bear is hungry!",
    },
    "imre": {
        "greet": "Admiral Imre. I have already read your plan.",
        "attack": "Exactly as planned. Proceed.",
        "win": "Calculated.",
        "lose": "Interesting. I will adjust.",
        "walkin": "You moved. I did not. That was the whole trick.",
        "eliminated": "Well played. I underestimated you.",
        "victory": "Checkmate.",
        "retreat": "The odds have turned. We withdraw.",
        "reserves": "Commit the reserve. Now.",
    },
}

## ---------------------------------------------------------------- portraits
CUT = "Head and shoulders centered with space around them, isolated on a plain white background"
PORTRAITS = {
    "advisor": "Bust portrait of an elderly imperial chief of staff with white mutton-chop whiskers and a monocle, scarlet general's coat with gold aiguillettes and a sash of orders, a proud, shrewd, grandfatherly smile",
    "varek": "Bust portrait of a grizzled old imperial field marshal with an eyepatch, iron-grey mustache and a duelling scar, navy greatcoat heavy with gold epaulettes and medals, black bicorne hat with gold trim, stern and merciless",
    "ysolde": "Bust portrait of a stern noblewoman viceroy-general in her forties with dark hair pinned up, crimson governor's uniform coat with heavy gold braid, black tricorne hat with a white ostrich plume, cold and imperious",
    "quill": "Bust portrait of a portly cunning trading-company governor in a powdered wig, green brocade waistcoat and a gold chain of office, round spectacles, a flintlock pistol tucked in his sash, a sly greedy grin",
    "oren": "Bust portrait of a dashing young hussar captain with windswept blond hair, braided sky-blue dolman jacket with a fur-trimmed pelisse slung over one shoulder, sabre hilt at his shoulder, reckless grin",
    "hask": "Bust portrait of a huge black-bearded privateer commodore in a bear-fur mantle over a battered naval coat, tricorne hat, a cutlass hilt and a brace of pistols across his chest, fierce laughing eyes",
    "imre": "Bust portrait of a calm sharp-eyed woman admiral with short dark hair, navy frock coat with gold buttons and epaulettes, a brass spyglass tucked under her arm, a faint knowing smile",
}
PLAYER = "Silhouette bust of an anonymous imperial commander in a bicorne hat and greatcoat with epaulettes, backlit by a blazing sunset over a harbor full of warships, face in shadow"

FACES = {
    "triumphant": "Same person, same framing, same outfit and painting style, plain white background, now laughing triumphantly with chin raised, eyes blazing with victory",
    "angry": "Same person, same framing, same outfit and painting style, plain white background, now furious and roaring a battle cry, brow furrowed, teeth bared",
    "defeated": "Same person, same framing, same outfit and painting style, plain white background, now defeated and exhausted, head bowed, soot on the face and a small cut on the cheek, eyes downcast",
}
ADVISOR_FACES = {
    "alarmed": "Same person, same framing, same outfit and painting style, plain white background, now alarmed and urgent, eyebrows raised, shouting a warning",
    "pleased": "Same person, same framing, same outfit and painting style, plain white background, now beaming with pride, raising a glass of port in a toast",
}
LOOPS = {
    "idle": "breathes slowly and blinks, subtle idle motion, head nearly still",
    "talk": "speaks with feeling, mouth moving as if talking, small natural head movements",
}

## ---------------------------------------------------------------- battle
BATTLEFIELDS = {
    "grass": "rolling green farmland with hedgerows, a dirt road, a stone bridge and a windmill on a hill",
    "forest": "a clearing in a dense old forest with a log road and a half-built timber stockade",
    "mountain": "a rocky mountain pass with scree slopes and a small stone watch-fort on a crag",
    "desert": "golden sand dunes and a dry riverbed below a sandstone fortress on a ridge",
    "snow": "a frozen tundra plain with snow-laden pines and a timber trading fort in the distance",
    "coast": "a sandy landing beach with longboats pulled up on the sand and a ship of the line anchored offshore",
    "ash": "grey volcanic plains with cracked earth, a smoking volcano and a burned-out outpost",
    "moor": "misty heather moorland with standing stones and an earthwork redoubt",
}
STYLE_BG = "Painterly battlefield backdrop seen from a high angle, like a war-game table, no people, no soldiers, no text, soft even light, open ground in the middle for two armies"

SOLDIER = "A single toy soldier of imperial line infantry, tall shako, crossbelts and tailcoat, musket held upright at the shoulder, full body standing, side view facing right, the whole figure painted pure white and very light grey with no other colors, glossy painted tin-soldier miniature look, isolated on a plain white background"
FLAG = "A single toy soldier flag bearer of imperial line infantry holding a tall pole with a large plain white flag, tall shako, full body standing, side view facing right, the whole figure painted pure white and very light grey with no other colors, glossy painted tin-soldier miniature look, isolated on a plain white background"


def entries(old):
    def bump(aid, fields):
        """v = old v, +1 if anything that shapes the output changed."""
        o = old.get(aid)
        if o is None:
            return 1
        keys = ("prompt", "text", "from", "kind", "type", "style_from", "describe", "cutout")
        if any(o.get(k) != fields.get(k) for k in keys if k in fields or k in o):
            return int(o.get("v", 1)) + 1
        return int(o.get("v", 1))

    out = []

    def add(e):
        e["v"] = bump(e["id"], e)
        out.append(e)

    ## anchor portrait first: every other portrait is painted in its style
    add({"id": "portrait_advisor", "kind": "image", "type": "portrait", "cutout": True, "aspect": "ar_1_1",
         "prompt": PORTRAITS["advisor"] + ". " + CUT, "out": "assets/portraits/advisor"})
    for who, desc in PORTRAITS.items():
        if who == "advisor":
            continue
        add({"id": "portrait_" + who, "kind": "styled", "type": "portrait", "style_from": "portrait_advisor",
             "cutout": True, "prompt": desc + ". " + CUT, "out": "assets/portraits/" + who})
    add({"id": "portrait_player", "kind": "styled", "type": "portrait", "style_from": "portrait_advisor",
         "prompt": PLAYER, "out": "assets/portraits/player"})
    for who in PORTRAITS:
        faces = ADVISOR_FACES if who == "advisor" else FACES
        for face, prompt in faces.items():
            add({"id": "face_%s_%s" % (who, face), "kind": "edit", "from": "portrait_" + who, "cutout": True,
                 "prompt": prompt, "out": "assets/portraits/%s_%s" % (who, face)})
        for loop, motion in LOOPS.items():
            add({"id": "loop_%s_%s" % (who, loop), "kind": "animate", "from": "portrait_" + who, "prompt": motion,
                 "image_type": "portrait", "final_same": True, "model": "forge", "duration": 2, "frames": 16,
                 "frame_size": -9, "loop": False, "crop": False, "out": "assets/raw/loops/%s_%s" % (who, loop)})

    ## the world: title, end screens, rules plates
    art = [
        ("splash_title", "ar_16_9", "The grand map room of an empire at the height of its power: a vast painted chart of unknown continents spread across a mahogany table, brass dividers and a spyglass, toy regiments in crimson and navy massed along the coastlines, a gilded globe, captured battle flags on the walls, tall windows open onto a harbor crowded with ships of the line under full sail at golden hour"),
        ("art_victory", "ar_16_9", "An imperial crimson-and-gold standard raised over the ramparts of a captured star fort on a headland, a fleet of ships of the line below firing a thundering salute, cannon smoke rolling across the water, blazing golden sunset, triumphant"),
        ("art_defeat", "ar_16_9", "A burning flagship listing in a storm-dark bay, a torn plain crimson ensign with a small golden crown floating among broken spars, the victorious enemy fleet sailing away on the horizon, cold grey dawn. Every flag is an invented plain banner, no real-world flags"),
        ("howto_sealed", "ar_16_9", "Close-up of a gloved hand pressing a signet ring into red wax to seal campaign orders on parchment, beside a brass compass and a campaign map, candlelight"),
        ("howto_march", "ar_16_9", "A long column of red-coated line infantry with tall shakos and fixed bayonets marching out of the gate of a star fort under a crimson imperial standard, drummers and fifers at the head, morning light"),
        ("howto_clash", "ar_16_9", "Two lines of musketeers, one in crimson coats and one in navy blue coats, colliding head-on on a narrow stone bridge amid thick musket smoke, battle flags on both sides"),
        ("howto_walkin", "ar_16_9", "A swaggering squad of green-coated soldiers marching unopposed through the open gate of an abandoned frontier fort and planting their green banner, the previous owner's flag lying in the dust"),
        ("howto_dugin", "ar_16_9", "Sappers in shirtsleeves digging earthwork redoubts lined with wicker gabions around cannon on a hilltop fort, afternoon light, determined"),
        ("howto_cards", "ar_16_9", "Three ornate campaign cards fanned on a war table, painted with a musketeer, a charging dragoon and a bronze cannon, gilded edges, candlelight"),
        ("howto_surge", "ar_16_9", "Hussars charging through a breach in a fortress wall and galloping on toward a second town on the horizon, sabres raised, dust and smoke"),
    ]
    for aid, aspect, prompt in art:
        base = aid.replace("art_", "")
        add({"id": aid, "kind": "image", "type": "art", "aspect": aspect, "prompt": prompt,
             "out": "assets/art/" + (base if aid.startswith("art_") else aid)})
    ## cards: infantry / cavalry / artillery, as the old game had it
    cards = {
        "card_sun": ("sun", "a heroic line-infantry musketeer with fixed bayonet"),
        "card_moon": ("moon", "a dragoon on a rearing horse with sabre raised"),
        "card_star": ("star", "a bronze field cannon on a wooden carriage with a smoking fuse"),
        "card_wild": ("wild", "a golden crown above a crossed musket, sabre and cannon ramrod"),
    }
    for aid, (kind, art_desc) in cards.items():
        add({"id": aid, "kind": "image", "type": "card-art", "aspect": "ar_3_4", "out": "assets/cards/" + kind,
             "prompt": "Front face of an ornate imperial campaign card: %s painted inside a gilded oval medallion at the center, ivory parchment ground, gilded baroque border with crimson corner flourishes, no text, no numbers" % art_desc})
    add({"id": "card_back", "kind": "image", "type": "card-art", "aspect": "ar_3_4", "out": "assets/cards/back",
         "prompt": "Back of an ornate playing card: deep navy ground with a gilded compass rose over a crossed anchor and sabre, crimson and gold baroque border, symmetrical, no text"})

    ## battlefields
    for key, desc in BATTLEFIELDS.items():
        add({"id": "field_" + key, "kind": "image", "type": "fixed_background", "aspect": "ar_16_9",
             "perspective": "High Angle", "out": "assets/battle/field_" + key,
             "prompt": "%s. %s" % (desc[0].upper() + desc[1:], STYLE_BG)})
    ## soldiers (white so the game can tint them); animations come in a second pass
    ## after tools/sheet_tool.gd pads them onto a fixed canvas (see v12_soldiers)
    add({"id": "soldier_stand", "kind": "image", "type": "sprite", "cutout": True, "style": False,
         "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": "ar_3_4",
         "out": "assets/raw/battle/soldier_stand", "prompt": SOLDIER})
    add({"id": "soldier_flag", "kind": "image", "type": "sprite", "cutout": True, "style": False,
         "art_style": "Hand-Painted", "perspective": "Side-Scroll", "aspect": "ar_3_4",
         "out": "assets/raw/battle/soldier_flag", "prompt": FLAG})

    ## the table: brass and gilt
    hud = [
        ("hud_ring", "Ornate circular gilded frame: a golden laurel wreath ring with a small crown at the top and rivets, perfectly round, empty see-through center, front view, isolated on plain white background"),
        ("hud_button", "Large round embossed button like a crimson wax seal set in a gilded baroque rim with laurel, blank smooth face with no symbol or text, front view, isolated on plain white background"),
        ("hud_coin", "Small round gold sovereign coin button with a raised milled rim and blank smooth center, no symbol, front view, isolated on plain white background"),
        ("hud_ribbon", "Horizontal crimson silk banner with forked swallowtail ends, gold fringe and gold stitched edges, blank, front view, isolated on plain white background"),
    ]
    for key, prompt in hud:
        add({"id": key, "kind": "image", "type": "ui_asset", "cutout": True, "out": "assets/hud/" + key, "prompt": prompt})
    chart = [
        ("chart_rose", "An ornate antique map compass rose with sixteen gilded star points, a fleur-de-lis at north, crimson and navy inks on transparent, front view, isolated on plain white background"),
        ("chart_ship", "A small ship of the line under full white sails flying a plain crimson pennant, side view, painted like an ornament on an antique sea chart, isolated on plain white background"),
        ("chart_cartouche", "An empty ornate baroque cartouche frame for a map title, gilded scrollwork with a crown, laurel and two crossed cannons, blank center, isolated on plain white background"),
    ]
    for key, prompt in chart:
        add({"id": key, "kind": "image", "type": "ui_asset", "cutout": True, "out": "assets/art/" + key, "prompt": prompt})
    add({"id": "icon_app", "kind": "image", "type": "icon", "cutout": True, "out": "assets/icons/app",
         "prompt": "Imperial crest emblem: a crowned crimson shield with three golden arrows converging on a small star fort, laurel wreath around it, bold dark outline, isolated on plain white background"})

    ## music: drums, brass and conquest
    music = [
        ("music_menu", "menu", 120, "Grand imperial anthem for a conquest strategy game: thundering timpani, full brass fanfare, marching snare drums, soaring strings and a proud wordless choir, triumphant and bombastic, the empire on the march, instrumental"),
        ("music_plan", "plan", 150, "War council music for planning an invasion: steady military snare cadence, low brass and cellos building quiet menace, fifes in the distance, confident and driving, loopable, instrumental"),
        ("music_battle", "battle", 120, "Full-throttle battle march: pounding war drums, rolling snares, blaring brass, fife and drum corps, cannon-like timpani hits, relentless and aggressive, a battle of conquest, loopable, instrumental"),
        ("music_charge", "charge", 90, "Heroic cavalry charge music: galloping strings ostinato, bugle calls, crashing cymbals, brass heroics, breathless and victorious, loopable, instrumental"),
        ("music_victory", "victory", 40, "Triumphal imperial victory anthem: blazing brass fanfare, pealing bells, a choir singing a wordless hymn of conquest, timpani, glorious"),
        ("music_defeat", "defeat", 30, "Funeral march for a fallen empire: muffled drums, a solo bugle, low strings, dignified and grim"),
    ]
    for aid, name, dur, prompt in music:
        add({"id": aid, "kind": "music", "duration": dur, "out": "assets/audio/music/" + name, "prompt": prompt})
    sfx = {
        "capture": "short triumphant brass fanfare with a snare flourish and a distant cheer, a town has fallen, two seconds",
        "walkin": "cocky swaggering low brass sting with a snare hit, sly and triumphant, short",
        "eliminated": "a thundering cannon salute and a slow grand drum roll, an empire has fallen, short",
        "seal": "wax seal stamp pressed onto parchment followed by a war drum hit and a distant cannon boom",
        "reveal": "parchment unrolled quickly then a bugle calls the advance with drums",
        "retreat": "a bugle sounding the retreat call, urgent, short",
        "reserves": "war drums beating fast and a column of boots rushing forward with a roar, short",
        "hurrah": "a whole regiment roaring hurrah as they charge, short",
        "hoofs": "a squadron of cavalry galloping past on hard ground, short",
    }
    for key, prompt in sfx.items():
        add({"id": "sfx_" + key, "kind": "sfx", "duration": 2 if key not in ("reserves", "hoofs") else 3,
             "out": "assets/audio/sfx/" + key, "prompt": prompt})

    ## voices stay (a clone must sound the same), lines change
    for who, desc in VOICES.items():
        o = old.get("voice_" + who, {})
        out.append({"id": "voice_" + who, "kind": "voice", "describe": desc, "text": o.get("text", LINES[who]["greet" if who != "advisor" else "welcome"])[:200],
                    "out": "assets/voice/%s/_sample" % who, "v": int(o.get("v", 1))})
    for who, lines in LINES.items():
        for key, text in lines.items():
            add({"id": "line_%s_%s" % (who, key), "kind": "speech", "voice": "voice_" + who, "text": text,
                 "out": "assets/voice/%s/%s" % (who, key)})
    return out


SOLDIER_ANIMS = [
    ## id, motion, final (None = same as start), frames
    ("soldier_idle", "stands at ease breathing, shifting weight slightly, musket at the shoulder", None),
    ("soldier_fire", "levels the musket straight ahead to the right at shoulder height and fires, a puff of smoke bursts from the muzzle on the right, then shoulders the musket again exactly as at the start", None),
    ("soldier_march", "marches forward in place, a steady walk cycle, musket at the shoulder", None),
    ("soldier_fall", "is hit by a musket ball and falls backward to the ground, then lies still", None),
    ("flag_wave", "the flag waves in the wind while the bearer stands still", None),
]


def soldier_entries(old):
    """Second pass: animate the padded soldiers so every sheet shares one canvas."""
    out = []
    pad = "assets/raw/battle/%s_pad.png"
    for aid, motion, final in SOLDIER_ANIMS:
        src = "soldier_flag" if aid.startswith("flag") else "soldier_stand"
        e = {"id": aid + "_anim", "kind": "animate", "from_file": pad % src, "prompt": motion, "image_type": "sprite",
             "model": "forge", "duration": 2, "frames": 16, "frame_size": -9, "loop": False, "crop": False,
             "out": "assets/raw/battle/%s" % aid, "v": 3}
        if aid != "soldier_fall":
            e["final_same"] = True  ## loops and the volley end on the stance they began in
        if final:
            e["final_file"] = "assets/raw/battle/%s_pad.png" % final
        if aid == "soldier_fire":
            e["v"] = 4  ## v3 aimed at the sky
        out.append(e)
    return out


def main(argv=None):
    import sys
    argv = sys.argv[1:] if argv is None else argv
    man = json.load(open(MAN))
    old = {a["id"]: a for a in man["assets"]}
    new = soldier_entries(old) if "--soldiers" in argv else entries(old)
    ids = {a["id"] for a in new}
    man["assets"] = [a for a in man["assets"] if a["id"] not in ids] + new
    if "--soldiers" not in argv:
        man["style"] = STYLE
        os.makedirs(os.path.join(ROOT, "game", "data"), exist_ok=True)
        json.dump({"voices": VOICES, "lines": LINES}, open(os.path.join(ROOT, "game", "data", "lines.json"), "w"), indent=1)
    json.dump(man, open(MAN, "w"), indent=1)
    changed = [a["id"] for a in new if a["id"] not in old or int(a.get("v", 1)) != int(old[a["id"]].get("v", 1))]
    print("manifest now %d assets; %d new or re-versioned" % (len(man["assets"]), len(changed)))
    return changed


if __name__ == "__main__":
    main()
