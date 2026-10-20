#!/usr/bin/env python3
"""v2.0 diorama run: the tin soldiers' poses, the longboat and the battle's sounds, for the
battles fought on the land (game/world3d/). Every asset is generated, installed at its game
path in this checkout, and put in the review batch review/v20_diorama for the owner's verdict.

    python3 tools/ludo/v20_content.py --make images [--jobs 6]   # pose pictures (0.5 each)
    python3 tools/ludo/v20_content.py --make models [--jobs 6]   # each picture to a GLB (3 each)
    python3 tools/ludo/v20_content.py --make sfx [--jobs 6]      # sound effects, 2 takes (2 each)
    python3 tools/ludo/v20_content.py --make models --only inf_aim,boat
    python3 tools/ludo/v20_content.py --post                     # install + write the review batch
    python3 tools/ludo/v20_content.py --cost                     # what --make would spend

Round two (the land in 3D): buildings and ships (LANDMARKS, two variants each, image then model),
ground textures (TEXTURES, two takes), more poses and sounds.

    python3 tools/ludo/v20_content.py --make pics --jobs 8       # every picture, texture and sound first
    python3 tools/ludo/v20_content.py --make meshes --jobs 6     # then every model (the land's most-seen first)
    python3 tools/ludo/v20_content.py --drop-rejected [--dry-run]  # take the rejected out of the game

Ludo runs about two jobs at a time for the account and a model takes 4-11 minutes, so run the models
after the pictures: a model's worker waits for its picture, and a pool full of waiting models starves
the pictures. A rerun picks up a job already on the server (its request id), so a run can be stopped
and restarted in another order. Models are slimmed for the repo (glb_slim.py: JPEG textures, embedded
on import): a figure from 2.4 MB to under 0.9, a building to about 0.5.

The poses are edits of the v1.9 infantry and hussar pictures (the same painted figure, a new
stance), so every figure on the field is one family; the game repaints each coat in its
commander's colour (game/world3d/tin.gdshader keys on the coat's own colour).
"""
import glob
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MAN = os.path.join(HERE, "manifest.json")
RAW = "assets/raw/v20"
BATCH = "v20_diorama"
## the full build: the plain one has no WebP encoder (the ground textures)
FF = "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg" if os.path.exists("/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg") else shutil.which("ffmpeg")

INF_REF = "assets/raw/v19/models/infantry_ref.webp"
CAV_REF = "assets/raw/v19/models/cavalry_ref.webp"
ROOM = (" Full figure with clear space on every side, even studio lighting, plain light grey background,"
        " the same hand-painted antique tin toy finish.")
SAME = ("The same hand-painted antique tin toy soldier, in the same crimson coat with white crossbelts, black shako "
        "with its gold plate, grey trousers and black shoes, on the same small round green-painted base, ")

## name: (source picture, what the figure does, label)
POSES = {
    "inf_aim": (INF_REF, SAME + "now aiming his musket: standing side-on with his feet apart, the musket raised to his "
                "right shoulder and held level pointing to the left, his left hand under the barrel and his right hand "
                "at the lock, his cheek against the stock. Side three-quarter view.", "Infantry: aiming, standing"),
    "inf_kneel": (INF_REF, SAME + "now kneeling on his right knee and aiming his musket level to the left, the butt at "
                  "his right shoulder, his left elbow resting on his raised left knee and his left hand under the barrel. "
                  "Side three-quarter view.", "Infantry: kneeling, aiming"),
    "inf_charge": (INF_REF, SAME + "now charging with the bayonet: lunging forward to the left with his left knee bent "
                   "in front, the musket held low and level at his hip in both hands with a long fixed bayonet pointing "
                   "straight ahead, his mouth open in a shout. Side three-quarter view.", "Infantry: bayonet charge"),
    "inf_march": (INF_REF, SAME + "now marching to the left: his left leg striding forward, the musket sloped on his "
                  "left shoulder with his left hand holding the butt, his right arm swinging forward at his side. "
                  "Side three-quarter view.", "Infantry: marching"),
    "officer": (INF_REF, "The same hand-painted antique tin toy style: a Napoleonic infantry officer in a crimson coat "
                "with gold epaulettes and a white sash across his chest, a black bicorne hat with a gold cockade, white "
                "breeches and tall black boots, his right arm raised high holding a curved sword that points forward to "
                "the left, his left hand on his hip, standing on the same small round green-painted base. Side "
                "three-quarter view.", "Officer, sword raised"),
    "drummer": (INF_REF, "The same hand-painted antique tin toy style: a young Napoleonic drummer in a crimson coat "
                "with white lace and a black shako, grey trousers, a brass side drum with crimson hoops hanging on a "
                "white belt at his left hip, a wooden drumstick held in each hand above the drumhead, standing on the "
                "same small round green-painted base. Front three-quarter view.", "Drummer"),
    "gunner": (INF_REF, SAME.replace("tin toy soldier", "tin toy artilleryman") + "now standing at ease holding a long "
               "wooden rammer staff upright beside him in his right hand, its sponge head above his shako. Front "
               "three-quarter view.", "Artilleryman with rammer"),
    "cav_charge": (CAV_REF, "The same hand-painted antique tin toy hussar on the same brown horse, now at full gallop "
                   "to the left: the horse stretched out with its forelegs reaching forward and its hind legs pushing "
                   "back, mane and tail flying, the rider in the same sky-blue braided jacket and fur busby leaning "
                   "forward with his sabre pointing straight ahead, one hind hoof standing on the same flat oval "
                   "green-painted base. Side three-quarter view.", "Hussar at full gallop"),
    ## round two: the rest of a battle's life
    "inf_cheer": (INF_REF, SAME + "now cheering in victory: standing tall facing us, his musket raised high above his head "
                  "in his right hand, his left fist raised, his mouth wide open in a cheer. Front three-quarter view.",
                  "Infantry: cheering the victory"),
    "inf_fallen": (INF_REF, "The same hand-painted antique tin toy soldier, in the same crimson coat with white crossbelts, "
                   "grey trousers and black shoes, now fallen in battle: lying flat on his back on the ground with his arms "
                   "flung out, his black shako fallen beside his head and his musket on the ground beside him, his eyes "
                   "closed. Seen from the side and a little above, the whole figure lying full length.",
                   "Infantry: fallen"),
    "inf_reload": (INF_REF, SAME + "now reloading: standing with the musket upright in front of him, its butt on the "
                   "ground between his feet, his left hand holding the barrel and his right hand pushing the ramrod down "
                   "the muzzle. Front three-quarter view.", "Infantry: reloading"),
    "inf_flee": (INF_REF, SAME + "now running away to the right in panic, looking back over his shoulder with a frightened "
                 "face, his musket trailing low in his left hand, his right arm swinging. Side three-quarter view.",
                 "Infantry: running away"),
    "gunner_ram": (INF_REF, SAME.replace("tin toy soldier", "tin toy artilleryman") + "now ramming home a charge: leaning "
                   "forward to the left with a long wooden rammer staff held level in both hands, pushing it forward as if "
                   "into a cannon's muzzle. Side three-quarter view.", "Artilleryman ramming"),
    "gunner_fire": (INF_REF, SAME.replace("tin toy soldier", "tin toy artilleryman") + "now touching off a cannon: leaning "
                    "away to the right, his left arm stretched out to the left holding a long linstock staff whose tip "
                    "glows with a smoking match, his right hand pressed over his right ear. Side three-quarter view.",
                    "Artilleryman firing"),
    "general": (CAV_REF, "The same hand-painted antique tin toy style: a Napoleonic general on a grey horse standing still, "
                "the general in a crimson coat with heavy gold epaulettes and a white sash, a black bicorne hat with white "
                "plumes, white breeches and tall black boots, raising a brass telescope to his right eye with his right "
                "hand, the reins in his left, on the same flat oval green-painted base. Side three-quarter view.",
                "General on horseback, with his glass"),
}
BOAT = ("A single hand-painted antique tin toy: a Napoleonic navy wooden longboat (a ship's cutter) with a dark blue "
        "painted hull, a white stripe along the gunwale, a varnished wooden interior with four plank seats, and four "
        "long wooden oars resting out over each side, empty, sitting level. Full object with clear space on every "
        "side, side three-quarter view, even studio lighting, plain light grey background")

## Round two: the land's own buildings, as wargame terrain pieces painted to stand with the tin soldiers.
## name: (what it is, label, faces). Each picture is rolled twice (two variants, _a and _b), and each becomes a model.
PIECE = (" A hand-painted miniature tabletop wargame terrain model, like a painted model-railway building, made to stand "
         "beside antique tin toy soldiers: chunky simplified shapes, crisp clean painted colours, a toy-like charm. The "
         "model stands on its own with its walls meeting the floor and clear space on every side, three-quarter view "
         "from a little above, even studio lighting, plain light grey background")
LANDMARKS = {
    "windmill": ("A tall Napoleonic-era post windmill: a white-washed wooden body on a round stone base, a dark shingled "
                 "roof, four large lattice sails with canvas, a wooden stair up to the door.", "Windmill", 9000),
    "watchtower": ("A round stone watchtower with crenellated battlements and an iron beacon brazier with a small fire on "
                   "top, a little arched wooden door, narrow windows.", "Watchtower with beacon", 8000),
    "lighthouse": ("A tall stone lighthouse painted in white and red bands with a glass lantern room and a gallery rail "
                   "on top, a small keeper's cottage with a slate roof at its foot, on a low rocky outcrop.",
                   "Lighthouse", 9000),
    "gatehouse": ("A fortified town gatehouse: two squat round stone towers with conical slate roofs either side of an "
                  "arched gateway with a raised iron portcullis, a short stretch of crenellated stone wall on each side.",
                  "Gatehouse", 10000),
    "keep": ("A square stone castle keep: a tall Norman tower with crenellated battlements and corner turrets, narrow "
             "arrow-slit windows, a wooden door at the top of a stone stair, a flagpole on the roof.", "Castle keep",
             9000),
    "palace": ("A grand baroque palace: a long pale cream stone facade with rows of tall windows, a central portico of "
               "white columns under a green copper dome, a tall flagpole on the dome, a gravel forecourt with low hedges.",
               "Palace (a capital)", 14000),
    "church": ("A village church of grey stone with a tall slender spire topped by a golden weathercock, a slate roof, "
               "an arched wooden door and a few gravestones beside it.", "Church with spire", 9000),
    "farm": ("A farmstead: a white-washed farmhouse with a thatched roof, a large red timber barn, a round haystack and a "
             "short wooden fence.", "Farmstead", 10000),
    "harbour": ("A small stone harbour quay: a stone pier with mooring bollards, a wooden jetty on pilings, a timber "
                "crane, barrels and crates stacked, a little harbour-master's hut.", "Harbour quay", 10000),
    "bridge": ("An old stone bridge with three round arches over nothing, a low parapet wall along each side, its two "
               "ends sloping down to the floor, seen from the side and a little above.", "Stone bridge", 7000),
    "starfort": ("A star-shaped Vauban fortress seen from above at an angle: low sloping stone-faced earth ramparts with "
                 "pointed bastions at every corner, black cannons on the ramparts, a gate with a little bridge, two "
                 "barracks buildings with red roofs inside, a flagpole in the middle.", "Star fort (a fort land)",
                 14000),
    "redoubt": ("A small earthwork redoubt: a ring of raised brown earth ramparts reinforced with woven wicker gabions and "
                "a sharpened wooden palisade, a black cannon pointing out through a gap, a small powder store inside.",
                "Earthwork redoubt (dug in)", 10000),
    "blockhouse": ("A stone toll house and wooden barrier across a mountain road: a small fortified stone guardhouse "
                   "with a slate roof and loopholes, a striped red and white barrier pole beside it.",
                   "Pass blockhouse (a pass land)", 8000),
    "camp": ("A Napoleonic army camp: three white canvas bell tents, muskets stacked in a pyramid, a campfire with a "
             "cooking pot on a tripod, a drum resting on the ground.", "Army camp", 9000),
    "oasis": ("A desert oasis: a small round pool of blue water with three tall date palm trees beside it, on a flat "
              "patch of golden sand.", "Oasis", 7000),
    "stones": ("A ring of seven ancient grey standing stones with a large flat stone in the middle, patches of moss on "
               "them.", "Standing stones", 6000),
    "quarry": ("A small stone quarry: a low block of pale cut stone in two stepped ledges, a few square cut stone "
               "blocks stacked beside it.", "Quarry", 7000),
    "ship": ("A Napoleonic three-masted ship of the line under full white sails, a black and ochre striped hull with two "
             "rows of gun ports, a red ensign at the stern, floating level.", "Ship of the line", 12000),
    "frigate": ("A Napoleonic frigate: a sleek three-masted warship under full white sails, a black hull with one ochre "
                "stripe and a row of gun ports, floating level.", "Frigate", 10000),
    ## a village for every land, in its region's terrain
    "village_grass": ("Two small white-washed timber-framed cottages side by side with thatched roofs and brick "
                      "chimneys, a low dry-stone wall in front.", "Village: lowland", 9000),
    "village_forest": ("Two dark timber log lodges with steep shingled roofs and stone chimneys, a woodpile, a sawn tree "
                       "stump with an axe in it.", "Village: forest", 11000),
    "village_moor": ("A low grey stone crofter's cottage with a green turf roof, a stack of peat, a round dry-stone "
                     "sheepfold beside it.", "Village: moor", 9000),
    "village_coast": ("Two fishermen's cottages with white walls, blue doors and slate roofs, fishing nets hung to dry on "
                      "poles, an upturned rowing boat on the ground.", "Village: coast", 11000),
    "village_desert": ("A cluster of flat-roofed sand-coloured adobe mud-brick houses with small dark windows, a wooden "
                       "ladder to a roof, clay pots, one palm tree.", "Village: desert", 11000),
    "village_snow": ("Two log cabins with roofs thick with white snow, icicles along the eaves, a stack of firewood "
                     "under snow, a little snow on the ground around them.", "Village: snow", 11000),
    "village_mountain": ("A simple alpine chalet: a whitewashed stone ground floor, a dark timber upper floor with one "
                         "wooden balcony, a wide overhanging shingled roof.", "Village: mountain", 8000),
    "village_ash": ("The blackened ruins of two stone houses: charred roof beams, broken walls, scattered rubble and a "
                    "lone standing chimney, grey ash on the ground.", "Village: ash (ruins)", 10000),
}
VARIANTS = ("a", "b")

## Ground textures for the land, seen flat from above: a tabletop's terrain mat at the soldiers' scale.
## name: prompt. Two takes each (_a, _b).
TEX = (" Seamless tileable texture seen flat from directly above, evenly lit with no shadows or perspective, the same "
       "density everywhere, filling the whole square, like a hand-painted tabletop wargame terrain mat")
TEXTURES = {
    "grass": "Lush green meadow grass with a few tiny wildflowers and small clover patches.",
    "forest": "A forest floor of fallen brown and orange leaves, moss, pine needles and small twigs.",
    "moor": "A heather moor: low purple heather, brown bracken and tufts of coarse yellow-green grass.",
    "sand": "Pale golden beach sand with fine ripples, a few small shells and pebbles.",
    "desert": "Warm orange desert sand with soft wind ripples and a few small stones.",
    "snow": "Fresh white snow with soft blue shadows in its hollows and a crisp crust.",
    "ash": "Dark grey volcanic ash and cinders with small black rocks and faint red embers.",
    "rock": "Grey granite rock face with cracks, lichen spots and strata lines.",
    "road": "A packed brown dirt road with cart wheel ruts and small stones.",
    "field": "Ploughed farm field: straight furrows of dark brown earth with rows of young green crops.",
}
## name: (prompt, seconds, loop, context)
SFX = {
    "fall_grass": ("a small painted tin toy soldier topples over and falls flat onto soft grass: one short dull thud "
                   "with a faint metallic tink, close up, dry, no voice", 1, False, "a man falls on grass or moor"),
    "fall_snow": ("a small painted tin toy soldier topples over and falls flat into crisp snow: one short soft crunch "
                  "with a faint metallic tink, close up, no voice", 1, False, "a man falls in snow"),
    "fall_sand": ("a small painted tin toy soldier topples over and falls flat onto dry sand: one soft muffled thump "
                  "with a short hiss of sand, close up, no voice", 1, False, "a man falls on sand"),
    "fall_stone": ("a small painted tin toy soldier topples over and falls onto rock: a sharp metallic clatter, one "
                   "small bounce and a rattle, close up, no voice", 1, False, "a man falls on rock or ash"),
    "fall_mud": ("a small painted tin toy soldier topples over and falls into wet mud: one short wet squelching slap, "
                 "close up, no voice", 1, False, "a man falls in the mud of a river bank"),
    "drum_tap": ("one single crisp military snare drum hit, the snares buzzing and the shell ringing out naturally for "
                 "half a second, outdoors on a battlefield, then quiet", 2, False,
                 "the drum that quickens as an army nears breaking (played by the game, beat by beat)"),
    "drum_boom": ("a single deep bass drum hit from a Napoleonic military band, outdoors, one hit only", 2, False,
                  "the drum's heavy beat"),
    "row_oars": ("sailors rowing a wooden longboat at sea: steady rhythmic oar strokes dipping into the water, wooden "
                 "oarlocks creaking, small waves slapping the hull, even rhythm", 4, True, "boats rowing a column ashore"),
    "boat_beach": ("a heavy wooden rowing boat runs aground on a shingle beach: the keel grinding up over pebbles, a "
                   "wave washing back out", 3, False, "a boat grounds on the beach"),
    "wade_ashore": ("a company of soldiers jumping out of boats and splashing ashore through knee-deep surf: many boots "
                    "in shallow water, sloshing and splashing, equipment rattling, no voices", 3, False,
                    "a column wades ashore from its boats"),
    "ball_impact": ("a cannonball slams into the earth nearby: a heavy deep thump, dirt and stones spraying and pattering "
                    "down, a short low rumble", 2, False, "a cannon's shot lands in the enemy's ranks"),
    "musket_shot_3": ("a single flintlock musket shot outdoors: the flint snap, a sharp powder crack and a short echo "
                      "across a field", 2, False, "one musket of a ragged volley (the game fires one per man)"),
    "musket_shot_4": ("a single black-powder musket shot at a distance across a valley: a sharp crack and a rolling "
                      "echo", 2, False, "one musket of a ragged volley, further off"),
    ## round two
    "cheer_hurrah": ("a company of soldiers cheering a victory outdoors: three rousing hurrahs from many men's voices "
                     "together, muskets rattling as they are raised", 3, False, "an army cheers when its fight is won"),
    "horse_gallop": ("a troop of cavalry galloping past across turf: many hooves thundering, harness and sabres "
                     "jingling, then fading", 3, False, "the horse charges"),
    "melee_steel": ("a bayonet and sabre melee: steel ringing on steel, several fast clashes and scrapes and a musket "
                    "butt thudding, no voices", 2, False, "a bayonet charge meets the enemy"),
    "flee_run": ("a few soldiers running away across a field: hurried boots on grass, equipment rattling, canteens "
                 "clanking, fading away, no voices", 2, False, "a beaten army runs"),
    "fort_gun": ("a heavy fortress cannon fires from stone ramparts: a deep boom echoing off stone walls, a long rumble",
                 3, False, "a fort's or a capital's guns"),
    "ship_creak": ("a wooden sailing warship at sea: timbers creaking, rigging straining, canvas sails flapping, waves "
                   "washing along the hull, steady", 8, True, "a ship sails the sea on the land map (loop)"),
    "land_wind": ("gentle wind over open countryside: grass rustling, distant birdsong, peaceful and steady", 8, True,
                  "the land map up close (loop)"),
    "shore_surf": ("small waves breaking on a shingle beach and drawing back over the pebbles, calm and steady", 8,
                   True, "the coast up close (loop)"),
    "flag_flap": ("a large cloth flag flapping and snapping in a strong wind on a pole", 3, True,
                  "the colours over a capital or a fort (loop)"),
}


## a re-roll: the first drum_tap came back 53 ms long (both takes), a click without its ring
VERSIONS = {"drum_tap": 2}
## a model Ludo failed ("AI server timeout"): a new request id, and fewer faces
## (twice for the lowland village: "try with different inputs", so its pictures were simplified and rolled
## again, both variants, and the alpine chalet's with them)
RETRY = {"v20_model_lm_village_grass_a": (3, 9000), "v20_pic_lm_village_grass_a": (2, 0),
         "v20_pic_lm_village_grass_b": (2, 0), "v20_model_lm_village_grass_b": (2, 9000),
         "v20_model_lm_village_mountain_a": (2, 8000), "v20_pic_lm_village_mountain_a": (2, 0),
         "v20_pic_lm_village_mountain_b": (2, 0), "v20_model_lm_village_mountain_b": (2, 8000),
         ## the quarry's and the oasis's first pictures failed the same way: simpler, and again
         "v20_pic_lm_quarry_a": (2, 0), "v20_model_lm_quarry_a": (2, 7000),
         "v20_pic_lm_oasis_a": (2, 0), "v20_model_lm_oasis_a": (2, 7000)}
## v2.3 (on the PC): 25 models were never made (every B variant but four, and the quarry and the oasis),
## and by then their pictures had expired on Ludo's storage (404) and lived only on the Mac (assets/raw
## is not in git), so each picture was drawn once more and its model made from that
REDRAWN = [
    "windmill_b", "watchtower_b", "lighthouse_b", "gatehouse_b", "keep_b", "palace_b", "church_b",
    "farm_b", "harbour_b", "bridge_b", "starfort_b", "redoubt_b", "blockhouse_b", "camp_b", "oasis_a",
    "oasis_b", "stones_b", "quarry_a", "quarry_b", "ship_b", "frigate_b", "village_desert_b",
    "village_snow_b", "village_mountain_b", "village_ash_b"
]
for _k in REDRAWN:
    for _kind in ("pic", "model"):
        _id = "v20_%s_lm_%s" % (_kind, _k)
        _v, _f = RETRY.get(_id, (1, 0))
        RETRY[_id] = (_v + 1, _f)


def entries():
    out = []
    for name, (src, prompt, _label) in POSES.items():
        out.append({"id": "v20_pic_" + name, "kind": "edit", "from_file": src, "prompt": prompt + ROOM,
                    "augment": False, "out": RAW + "/models/%s_ref" % name, "group": "v20_images"})
        out.append({"id": "v20_model_" + name, "kind": "model3d", "from": "v20_pic_" + name, "faces": 8000,
                    "texture_size": 1024, "texture_type": "pbr", "out": RAW + "/models/" + name,
                    "group": "v20_models"})
    out.append({"id": "v20_pic_boat", "kind": "image", "type": "asset", "art_style": "Hand-Painted",
                "aspect": "ar_4_3", "style": False, "prompt": BOAT, "out": RAW + "/models/boat_ref",
                "group": "v20_images"})
    out.append({"id": "v20_model_boat", "kind": "model3d", "from": "v20_pic_boat", "faces": 6000,
                "texture_size": 1024, "texture_type": "pbr", "out": RAW + "/models/boat", "group": "v20_models"})
    for name, (prompt, dur, loop, _ctx) in SFX.items():
        ent = {"id": "v20_sfx_" + name, "kind": "sfx", "duration": dur, "prompt": prompt, "out": RAW + "/sfx/" + name,
               "group": "v20_sfx", "takes": 2}
        if loop:
            ent["loop"] = True
        if name in VERSIONS:
            ent["v"] = VERSIONS[name]
        out.append(ent)
    for name, (prompt, _label, faces) in LANDMARKS.items():
        wide = name in ("palace", "bridge", "ship", "frigate", "starfort", "harbour", "farm")
        for v in VARIANTS:
            key = "%s_%s" % (name, v)
            out.append({"id": "v20_pic_lm_" + key, "kind": "image", "type": "asset", "art_style": "Hand-Painted",
                        "aspect": "ar_4_3" if wide else "ar_1_1", "style": False, "prompt": prompt + PIECE,
                        "out": RAW + "/land/%s_ref" % key, "group": "v20_land_pics"})
            out.append({"id": "v20_model_lm_" + key, "kind": "model3d", "from": "v20_pic_lm_" + key, "faces": faces,
                        "texture_size": 1024, "texture_type": "pbr", "out": RAW + "/land/" + key,
                        "group": "v20_land_models"})
    for name, prompt in TEXTURES.items():
        for v in VARIANTS:
            out.append({"id": "v20_tex_%s_%s" % (name, v), "kind": "image", "type": "texture", "aspect": "ar_1_1",
                        "style": False, "prompt": prompt + TEX, "out": RAW + "/tex/%s_%s" % (name, v),
                        "group": "v20_tex"})
    for e in out:
        if e["id"] in RETRY:
            e["v"] = RETRY[e["id"]][0]
            if e["kind"] == "model3d" and RETRY[e["id"]][1]:
                e["faces"] = RETRY[e["id"]][1]
    return out


def _ordered():
    """The manifest order is the run order: the land's first variants before everything else."""
    ents = entries()
    rank = {"v20_land_pics": 0, "v20_tex": 1, "v20_images": 2, "v20_sfx": 3, "v20_land_models": 4, "v20_models": 5}

    ## the pieces seen most first: a village on every land, the ships, the bridges, the rules
    first = ["village_grass", "village_forest", "village_coast", "village_moor", "village_desert", "village_snow",
             "village_mountain", "village_ash", "ship", "frigate", "bridge", "harbour", "palace", "starfort",
             "blockhouse", "keep", "watchtower", "windmill", "church", "gatehouse", "farm", "stones", "redoubt",
             "lighthouse", "quarry", "oasis", "camp"]

    def key(e):
        r = rank.get(e["group"], 9)
        if e["group"] == "v20_land_models" and e["id"].endswith("_b"):
            r = 6
        sub = 99
        if e["group"] == "v20_land_models":
            name = e["id"][len("v20_model_lm_"):-2]
            sub = first.index(name) if name in first else 50
        return (r, sub)
    return sorted(ents, key=key)


def _interleaved():
    """One run, by priority: each piece's picture and then its model, so a worker waiting on a
    picture always has another worker making it (the pool never starves)."""
    ents = {e["id"]: e for e in entries()}
    first = ["village_grass", "village_forest", "village_coast", "village_moor", "village_desert", "village_snow",
             "village_mountain", "village_ash", "ship", "frigate", "bridge", "harbour", "palace", "starfort",
             "blockhouse", "keep", "watchtower", "windmill", "church", "gatehouse", "farm", "stones", "redoubt",
             "lighthouse", "quarry", "oasis", "camp"]
    order = ["v20_tex_%s_a" % t for t in TEXTURES]  ## quick pictures, and every inch of the land wears them
    for v in VARIANTS:
        for name in first:
            order += ["v20_pic_lm_%s_%s" % (name, v), "v20_model_lm_%s_%s" % (name, v)]
        if v == "a":
            order += ["v20_tex_%s_b" % t for t in TEXTURES]
            for name in list(POSES.keys()) + ["boat"]:
                order += ["v20_pic_" + name, "v20_model_" + name]
    order += [e for e in ents if e not in order]
    return [ents[i] for i in order if i in ents]


def write_manifest():
    m = json.load(open(MAN, encoding="utf-8"))
    mine = {e["id"]: e for e in _interleaved()}
    kept = [a for a in m["assets"] if a["id"] not in mine]
    m["assets"] = kept + list(mine.values())
    with open(MAN, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=1)
        f.write("\n")


def ids_of(what, only):
    groups = {"images": ["v20_images"], "models": ["v20_models"], "sfx": ["v20_sfx"],
              "land": ["v20_land_pics", "v20_land_models"], "tex": ["v20_tex"],
              "all": ["v20_images", "v20_land_pics", "v20_tex", "v20_models", "v20_land_models", "v20_sfx"],
              ## two phases, so no worker sits on a model whose picture is queued behind it
              "pics": ["v20_images", "v20_land_pics", "v20_tex", "v20_sfx"],
              "meshes": ["v20_models", "v20_land_models"],
              "ordered": ["v20_images", "v20_land_pics", "v20_tex", "v20_models", "v20_land_models", "v20_sfx"]}[what]
    ents = entries()
    out = [e["id"] for g in groups for e in ents if e["group"] == g]
    if only:
        out = [i for i in out if any(i.endswith("_" + o) or ("_%s_" % o) in i for o in only)]
    return out


def make(what, only, jobs):
    write_manifest()
    ids = ids_of(what, only)
    cmd = [sys.executable, os.path.join(HERE, "ludo.py"), "--jobs", str(jobs)] + ids
    if what in ("sfx", "all", "pics", "ordered"):
        cmd[2:2] = ["--takes", "2"]
    print("ludo:", " ".join(ids), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=False)


def ff(*args):
    subprocess.run([FF, "-y", "-loglevel", "error", *args], check=True)


LAND_GROUPS = {"village": "land: villages", "ship": "land: at sea", "frigate": "land: at sea"}
RULE_PIECES = {"palace": "a capital", "starfort": "a fort land", "blockhouse": "a pass land", "harbour": "a port",
               "redoubt": "dug in", "bridge": "a road over a river"}


def _group_of(name):
    if name.startswith("village_"):
        return LAND_GROUPS["village"]
    if name in LAND_GROUPS:
        return LAND_GROUPS[name]
    return "land: the rules" if name in RULE_PIECES else "land: landmarks"


def _install_glb(src, target, max_size):
    """The model slimmed for the repo (JPEG textures, embedded on import, no PNG copies beside it)."""
    sys.path.insert(0, HERE)
    import glb_slim
    dst = os.path.join(ROOT, target)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    glb_slim.slim(src, dst, 4, max_size)
    glb_slim.write_import(target, ROOT)
    stem = os.path.splitext(dst)[0]
    for old in glob.glob(stem + "_[0-9].png") + glob.glob(stem + "_[0-9].png.import"):
        os.remove(old)  ## the textures an older import extracted


def _snaps(name_glob, sheet, pic):
    snaps = sorted(glob.glob(name_glob))
    if len(snaps) >= 2:
        ins = []
        for s in snaps[:4]:
            ins += ["-i", s]
        n = min(4, len(snaps))
        ff(*ins, "-filter_complex", "".join("[%d]scale=-2:384[s%d];" % (k, k) for k in range(n))
           + "".join("[s%d]" % k for k in range(n)) + "hstack=%d" % n, sheet)
        return True
    if pic:
        ff("-i", pic, "-vf", "scale=-2:512", sheet)
        return True
    return False


def post():
    bd = os.path.join(ROOT, "review", BATCH)
    for sub in ("models", "land", "tex/.takes", "sfx/.takes"):
        os.makedirs(os.path.join(bd, sub), exist_ok=True)
    ledger = json.load(open(os.path.join(ROOT, "assets", "ludo_ledger.json"), encoding="utf-8"))
    led = ledger if isinstance(ledger, dict) else {}
    items = []

    def credits(*ids):
        tot = 0.0
        for i in ids:
            ent = led.get(i) if isinstance(led.get(i), dict) else None
            if ent:
                tot += float(ent.get("credits", 0) or 0)
        return round(tot, 2)

    ## the figures: poses, the general, the longboat
    for name in list(POSES.keys()) + ["boat"]:
        glb = os.path.join(ROOT, RAW, "models", name + ".glb")
        pic = glob.glob(os.path.join(ROOT, RAW, "models", name + "_ref.*"))
        label = POSES[name][2] if name in POSES else "Longboat"
        text = (POSES[name][1] + ROOM) if name in POSES else BOAT
        if os.path.exists(glb):
            target = "assets/models/diorama/%s.glb" % name
            _install_glb(glb, target, 1024)
            shutil.copyfile(os.path.join(ROOT, target), os.path.join(bd, "models", name + ".glb"))
            _snaps(os.path.join(ROOT, RAW, "models", name + "_snap*.png"), os.path.join(bd, "models", name + "_snaps.png"),
                   pic[0] if pic else None)
            items.append({"id": "model_" + name, "kind": "image", "group": "3D figures", "label": label + " (3D, 4 views)",
                          "text": text, "target": target, "file": "models/%s_snaps.png" % name,
                          "meta": {"manifest_ids": ["v20_pic_" + name, "v20_model_" + name], "added": True,
                                   "credits": credits("v20_pic_" + name, "v20_model_" + name),
                                   "reference_image": os.path.relpath(pic[0], ROOT) if pic else "",
                                   "install": [["models/%s.glb" % name, target]]}})
        elif pic:
            ff("-i", pic[0], "-vf", "scale=-2:768", os.path.join(bd, "models", name + "_pic.png"))
            items.append({"id": "pic_" + name, "kind": "image", "group": "pose pictures", "label": label + " (picture)",
                          "text": text, "target": os.path.relpath(pic[0], ROOT), "file": "models/%s_pic.png" % name,
                          "meta": {"manifest_ids": ["v20_pic_" + name], "credits": credits("v20_pic_" + name)}})
    ## the land's buildings and ships, every variant its own item (the game uses every one kept)
    for name, (prompt, label, _faces) in LANDMARKS.items():
        for v in VARIANTS:
            key = "%s_%s" % (name, v)
            glb = os.path.join(ROOT, RAW, "land", key + ".glb")
            pic = glob.glob(os.path.join(ROOT, RAW, "land", key + "_ref.*"))
            ids = ["v20_pic_lm_" + key, "v20_model_lm_" + key]
            what = RULE_PIECES.get(name)
            ctx = ("the rules as scenery: " + what) if what else ""
            if os.path.exists(glb):
                target = "assets/models/land/%s.glb" % key
                _install_glb(glb, target, 512)
                shutil.copyfile(os.path.join(ROOT, target), os.path.join(bd, "land", key + ".glb"))
                _snaps(os.path.join(ROOT, RAW, "land", key + "_snap*.png"), os.path.join(bd, "land", key + "_snaps.png"),
                       pic[0] if pic else None)
                items.append({"id": "land_" + key, "kind": "image", "group": _group_of(name),
                              "label": "%s, variant %s (3D, 4 views)" % (label, v.upper()), "text": prompt + PIECE,
                              "target": target, "file": "land/%s_snaps.png" % key,
                              "meta": {"manifest_ids": ids, "credits": credits(*ids), "added": True, "context": ctx,
                                       "reference_image": os.path.relpath(pic[0], ROOT) if pic else "",
                                       "install": [["land/%s.glb" % key, target]]}})
            elif pic:
                ff("-i", pic[0], "-vf", "scale=-2:768", os.path.join(bd, "land", key + "_pic.png"))
                items.append({"id": "landpic_" + key, "kind": "image", "group": _group_of(name),
                              "label": "%s, variant %s (picture; its model is still to come)" % (label, v.upper()),
                              "text": prompt + PIECE, "target": os.path.relpath(pic[0], ROOT), "file": "land/%s_pic.png" % key,
                              "meta": {"manifest_ids": ids[:1], "credits": credits(ids[0]), "context": ctx}})
    ## the ground: the A take is in the game, the B take beside it (accept the one you want)
    for name, prompt in TEXTURES.items():
        takes = [t for t in (sorted(glob.glob(os.path.join(ROOT, RAW, "tex", "%s_%s.*" % (name, v)))) for v in VARIANTS) if t]
        if not takes:
            continue
        target = "assets/tex/ground/%s.webp" % name
        os.makedirs(os.path.join(ROOT, os.path.dirname(target)), exist_ok=True)
        ff("-i", takes[0][0], "-vf", "scale=1024:1024", "-quality", "86", os.path.join(ROOT, target))
        shutil.copyfile(os.path.join(ROOT, target), os.path.join(bd, "tex", name + ".webp"))
        listed = []
        for k, t in enumerate(takes[1:]):
            rel = "tex/.takes/%s.t%d.webp" % (name, k + 2)
            ff("-i", t[0], "-vf", "scale=1024:1024", "-quality", "86", os.path.join(bd, rel))
            listed.append({"file": rel, "label": "take B"})
        ids = ["v20_tex_%s_%s" % (name, v) for v in VARIANTS]
        items.append({"id": "tex_" + name, "kind": "image", "group": "land: ground textures",
                      "label": "Ground: %s (seamless; take A is in the game)" % name, "text": prompt + TEX,
                      "target": target, "file": "tex/%s.webp" % name, "take_label": "take A", "takes": listed,
                      "meta": {"manifest_ids": ids, "credits": credits(*ids), "added": True}})
    for name, (prompt, _dur, loop, ctx) in SFX.items():
        raws = sorted(glob.glob(os.path.join(ROOT, RAW, "sfx", name + ".*")))
        raws = [r for r in raws if r.endswith((".mp3", ".wav"))]
        if not raws:
            continue
        target = "assets/audio/sfx/%s.wav" % name
        _prep(raws[0], os.path.join(ROOT, target), loop)
        shutil.copyfile(os.path.join(ROOT, target), os.path.join(bd, "sfx", name + ".wav"))
        for k, t in enumerate(sorted(glob.glob(os.path.join(ROOT, RAW, "sfx", ".takes", name + ".t*.*")))):
            _prep(t, os.path.join(bd, "sfx", ".takes", "%s.t%d.wav" % (name, k + 2)), loop)
        items.append({"id": "sfx_" + name, "kind": "audio", "group": "sounds", "label": name.replace("_", " ").capitalize(),
                      "text": prompt, "target": target, "file": "sfx/%s.wav" % name,
                      "meta": {"manifest_ids": ["v20_sfx_" + name], "credits": credits("v20_sfx_" + name), "added": True,
                               "context": ctx, "install": [["sfx/%s.wav" % name, target]]}})
    actions = [
        {"id": "install", "label": "Install accepted",
         "help": "Copy each accepted file (or the take you picked) over the one in the game (review.py apply)",
         "cmd": ["python3", "tools/review/review.py", "apply", BATCH],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                      "help": "Only list what would be copied"}]},
        {"id": "drop_rejected", "label": "Take the rejected out of the game",
         "help": "Everything in this batch is already in the game: delete each rejected piece's file from it",
         "cmd": ["python3", "tools/ludo/v20_content.py", "--drop-rejected"],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                      "help": "Only list what would be deleted"}]},
    ]
    batch = {"batch": BATCH, "title": "v2.0 the land in 3D: figures, buildings, ships, ground, sounds", "actions": actions,
             "items": items}
    with open(os.path.join(bd, "batch.json"), "w", encoding="utf-8") as f:
        json.dump(batch, f, indent=1)
    print("batch %s: %d items" % (BATCH, len(items)))


def drop_rejected(dry):
    """Every item here was installed as it came: a rejected one's file leaves the game."""
    bd = os.path.join(ROOT, "review", BATCH)
    batch = json.load(open(os.path.join(bd, "batch.json"), encoding="utf-8"))
    rv = os.path.join(bd, "review.json")
    verdicts = (json.load(open(rv, encoding="utf-8")).get("items") or {}) if os.path.exists(rv) else {}
    n = 0
    for it in batch["items"]:
        v = verdicts.get(it["id"]) or {}
        if v.get("verdict") != "reject" or not (it.get("meta") or {}).get("added"):
            continue
        tgt = os.path.join(ROOT, it["target"])
        for f in (tgt, tgt + ".import"):
            if os.path.exists(f):
                print(("would delete " if dry else "deleted ") + os.path.relpath(f, ROOT))
                if not dry:
                    os.remove(f)
                n += 1
    print("%d files %s" % (n, "to delete" if dry else "deleted"))


## the longest a sound may ring (seconds): a drum stroke played four times a second can't carry a tail
MAXLEN = {"drum_tap": 0.5, "drum_boom": 1.2, "fall_grass": 0.9, "fall_snow": 0.9, "fall_sand": 0.9, "fall_stone": 0.9,
          "fall_mud": 0.9}


def _prep(src, dst, loop):
    ## leading silence off, levelled, a short fade out (a loop keeps its ends)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    af = "loudnorm=I=-16:TP=-2:LRA=11"
    if not loop:
        af = "silenceremove=start_periods=1:start_threshold=-45dB," + af + ",areverse,silenceremove=start_periods=1:start_threshold=-55dB,afade=t=in:d=0.04,areverse"
        cap = MAXLEN.get(os.path.splitext(os.path.basename(dst))[0].split(".")[0])
        if cap:
            af += ",atrim=0:%s,afade=t=out:st=%s:d=%s" % (cap, cap * 0.6, cap * 0.4)
    ff("-i", src, "-af", af, "-ar", "44100", "-ac", "1", dst)


def cost(what):
    per = {"v20_images": 0.5, "v20_land_pics": 0.5, "v20_tex": 0.5, "v20_models": 3.0, "v20_land_models": 3.0,
           "v20_sfx": 4.0}
    gid = {e["id"]: e["group"] for e in entries()}
    return sum(per[gid[i]] for i in ids_of(what, []))


def main(argv):
    jobs = 6
    only = []
    if "--jobs" in argv:
        jobs = int(argv[argv.index("--jobs") + 1])
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    if "--make" in argv:
        make(argv[argv.index("--make") + 1], only, jobs)
    elif "--post" in argv:
        post()
    elif "--drop-rejected" in argv:
        drop_rejected("--dry-run" in argv)
    elif "--cost" in argv:
        for w in ("images", "models", "sfx", "land", "tex", "all"):
            print("%-7s %5.1f credits" % (w, cost(w)))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
