#!/usr/bin/env python3
"""v1.9 production run: the Ludo tools from docs/LUDO_CAPABILITIES.md, used for real.

Every asset is generated, processed into the game's format, installed at its game path
AND put in a review batch whose target is that path, so it can be accepted or redone.

    python3 tools/ludo/v19_content.py                      # manifest entries + batch files (idempotent)
    python3 tools/ludo/v19_content.py --make G1 G3 [--jobs 8]   # generate, process, install, batch
    python3 tools/ludo/v19_content.py --post G2 [--no-install]  # process what is generated
    python3 tools/ludo/v19_content.py --ids G5             # the manifest ids of a group
    python3 tools/ludo/v19_content.py --batch              # rewrite review/v19_*/batch.json
    python3 tools/ludo/v19_content.py --install --batch-name v19_dice [--dry-run]
    python3 tools/ludo/v19_content.py --regen --batch-name v19_dice [--dry-run]

--install copies every accepted take (and its sidecars: a sheet's json, a video's ogv) to
the game, writes rejected.json and runs Godot's import. --regen bumps the version of every
rejected take's generation chain (a reviewer's edited text becomes the new prompt), makes a
new take into the review folder (the old one moves to review/<batch>/old/) and does NOT
install it: review it again, then --install.

Groups: G1 dice table and Fortune, G2p battle poses, G2 keyframe moves, G3 untinted VFX,
G4 living paintings, G5 cutscenes, G6 Hydra talk loops, G7 leitmotif remixes, G8 marching
song, G9 unit variants (editSpritesheet on the G2 sheets, which must be under 7 days old),
G10 three-quarter views, G11 3D pieces.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MAN = os.path.join(HERE, "manifest.json")
LEDGER = os.path.join(ROOT, "assets", "ludo_ledger.json")
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot"))
FFMPEG = os.environ.get("FFMPEG_FULL", "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg")  ## the build with Theora
RAW = "assets/raw/v19"
SELF = "tools/ludo/v19_content.py"
sys.path.insert(0, HERE)
import pack_anims  # noqa: E402

BATCHES = {
    "v19_dice": "v1.9 dice table and Fortune",
    "v19_battle": "v1.9 battle moves (keyframes) and unit variants",
    "v19_fx": "v1.9 untinted battle effects",
    "v19_video": "v1.9 living paintings and cutscenes",
    "v19_portraits": "v1.9 talk loops (Hydra)",
    "v19_music": "v1.9 leitmotif remixes and the marching song",
    "v19_models": "v1.9 tabletop views and 3D pieces",
}

NOSPEECH = (" No spoken words, no dialogue, no narration: only music and sound effects."
            " Painterly oil-painting look matching the reference images, Napoleonic era, 1810s.")

# ---------------------------------------------------------------- manifest entries
E = []


def e(group, **kw):
    kw["group"] = group
    E.append(kw)


## G1 dice table and Fortune
e("G1", id="v19_tex_felt", kind="image", type="texture", aspect="ar_1_1", style=False, out=RAW + "/dice/felt",
  prompt="Seamless tileable texture of green billiard-table baize seen flat from directly above: a fine woven wool felt "
         "with a soft short nap, deep rich green, very subtle fibre variation and the faintest wear, even lighting, "
         "no borders, no vignette, no seams, no objects, flat")
e("G1", id="v19_tex_rail", kind="image", type="texture", aspect="ar_1_1", style=False, out=RAW + "/dice/rail_wood",
  prompt="Seamless tileable texture of polished dark mahogany wood: long straight grain running horizontally from left "
         "to right, deep reddish brown with a warm lacquered sheen and subtle ribbon figure, even lighting, flat, "
         "no knots, no borders, no objects")
e("G1", id="v19_tex_brass", kind="image", type="texture", aspect="ar_1_1", style=False, out=RAW + "/dice/brass",
  prompt="Seamless tileable texture of aged brushed brass metal: fine horizontal brushing lines, warm golden yellow "
         "with a soft darker patina and faint tarnish, even lighting, flat, no borders, no objects")
e("G1", id="v19_plaque", kind="image", type="ui_asset", aspect="ar_19_9", cutout=True, out=RAW + "/dice/plaque",
  prompt="An empty horizontal nameplate, long and narrow, about three times as wide as it is tall: a panel of aged cream "
         "parchment set in an ornate burnished brass frame with rivets at the corners and small laurel scrolls at "
         "each end, blank with no text and no symbols, front view, isolated on plain white background")
e("G1", id="v19_fortune_star", kind="image", type="ui_asset", aspect="ar_1_1", cutout=True, out=RAW + "/dice/fortune_star",
  prompt="A gold eight-pointed star medallion: eight sharp polished gold rays, four long and four short, around a round "
         "domed gold centre, bold simple silhouette that reads at a tiny size, bright and lucky, front view, no text, "
         "isolated on plain white background")
e("G1", id="v19_fortune_empty", kind="edit", from_="v19_fortune_star", cutout=True, out=RAW + "/dice/fortune_empty",
  prompt="Turn it into the empty socket where the star would sit: the same eight-pointed star shape, same size and "
         "outline, but as a dim recessed engraving in dull dark grey pewter, unlit and flat, no gold, no shine, "
         "no glow, front view, on a plain white background")
e("G1", id="v19_sfx_fortune", kind="sfx", duration=3, out="assets/raw/sfx/fortune",
  prompt="calling on Lady Fortune: a bright magical shimmering swell of a harp glissando and tinkling bells rising "
         "quickly, ending on one deep resonant timpani hit, orchestral, no voice")
e("G1", id="v19_sfx_fortune_gained", kind="sfx", duration=2, out="assets/raw/sfx/fortune_gained",
  prompt="a soft sparkling chime: a few high glockenspiel and small bell notes twinkling upward, gentle and magical, "
         "short, no voice")
e("G1", id="v19_howto_fortune", kind="image", type="art", aspect="ar_16_9", out=RAW + "/dice/howto_fortune",
  prompt="A Napoleonic-era commander in a dark blue greatcoat with gold epaulettes leans over a candlelit war table "
         "covered with maps and tin soldiers; behind him rises a translucent, ghostly Lady Fortune, a classical goddess "
         "in flowing robes turning a great spoked wheel of fortune, who tips a single falling ivory die onto the map "
         "with one finger; through the open tent behind, regiments of line infantry in shakos and white crossbelts "
         "with muskets and fixed bayonets stand in ranks under their colours, 1810s, no armour, no knights, "
         "dramatic golden candlelight")

## G2p poses on the padded 1152x768 canvas (a human picks the variant, see --pick)
POSE_SRC = {"soldier": "assets/raw/battle/soldier_stand_pad.png", "cavalry": "assets/raw/battle/cavalry_stand_pad.png"}
e("G2p", id="v19_pose_fallen", kind="pose", from_file=POSE_SRC["soldier"], pose="Other", n=2, out=RAW + "/battle/pose_fallen",
  prompt="Side view, the same Napoleonic infantryman lying flat on his back on the ground after being shot, body "
         "stretched out horizontally along the ground with his head to the left and his feet to the right, his "
         "musket fallen on the ground beside him, still, same scale and same ground line")
e("G2p", id="v19_pose_cheer", kind="pose", from_file=POSE_SRC["soldier"], pose="Other", n=2, out=RAW + "/battle/pose_cheer",
  prompt="Side view facing right, the same Napoleonic infantryman cheering in victory: standing, one arm thrust up "
         "holding his musket high above his head, the other fist raised, mouth open in a shout")
e("G2p", id="v19_pose_reload", kind="pose", from_file=POSE_SRC["soldier"], pose="Other", n=2, out=RAW + "/battle/pose_reload",
  prompt="Side view facing right, the same Napoleonic infantryman reloading: standing with the musket held upright in "
         "front of him, its butt on the ground, driving the ramrod down the barrel with his right hand")
e("G2p", id="v19_pose_cav_charge", kind="pose", from_file=POSE_SRC["cavalry"], pose="Other", n=2, out=RAW + "/battle/pose_cav_charge",
  prompt="Side view facing right, the same cavalryman charging at full gallop: the horse stretched out with its "
         "forelegs reaching forward, the rider leaning forward in the saddle with his sabre pointed straight ahead")

## G2 keyframe moves (forge holds our poses exactly; it only draws the in-betweens)
KF = dict(kind="keyframes", model="forge", duration=3, frames=25, frame_size=-9, loop=False, crop=False)
PAD = "assets/raw/battle/%s_pad.png"
PICK = RAW + "/battle/%s_pad.png"  ## the chosen pose variant, see --pick
e("G2", id="v19_kf_soldier_volley", from_file=PAD % "soldier_stand", middle_file=PAD % "soldier_aim",
  final_file=PAD % "soldier_stand", out=RAW + "/battle/soldier_volley_kf", **KF,
  prompt="raises the musket to his shoulder and aims it straight ahead to the right, his shoulder kicks back slightly with the recoil, then he lowers the musket back to his shoulder; he stays in side view facing right the whole time and never turns around")
e("G2", id="v19_kf_soldier_kneel_volley", from_file=PAD % "soldier_stand", middle_file=PAD % "soldier_kneel_aim",
  final_file=PAD % "soldier_stand", out=RAW + "/battle/soldier_kneel_volley_kf", **KF,
  prompt="drops to one knee and aims the musket to the right, jolts back with one sharp recoil, then stands back up "
         "with the musket at the shoulder, no smoke")
e("G2", id="v19_kf_soldier_charge", from_file=PAD % "soldier_stand", middle_file=PICK % "guard",
  final_file=PAD % "soldier_stand", out=RAW + "/battle/soldier_charge_kf", **KF,
  prompt="brings the musket down and levels the bayonet at the enemy on the right, lunges forward with a bayonet thrust, pulls back and shoulders the musket again; he does not fire, no flash, no smoke, and he stays in side view facing right")
e("G2", id="v19_kf_soldier_cheer", from_file=PAD % "soldier_stand", middle_file=PICK % "cheer",
  final_file=PAD % "soldier_stand", out=RAW + "/battle/soldier_cheer_kf", **KF,
  prompt="raises his musket high above his head and cheers, shaking it in triumph, then lowers it back to his shoulder; he stays in side view facing right the whole time")
e("G2", id="v19_kf_soldier_reload", from_file=PAD % "soldier_stand", middle_file=PICK % "reload",
  final_file=PAD % "soldier_stand", out=RAW + "/battle/soldier_reload_kf", **KF,
  prompt="brings the musket upright in front of him, bites a cartridge, rams the ramrod down the barrel twice, then "
         "shoulders the musket again")
e("G2", id="v19_kf_soldier_fall", from_file=PAD % "soldier_stand", final_file=PICK % "fallen",
  out=RAW + "/battle/soldier_fall_kf", **KF,
  prompt="is shot in the chest, staggers backward, drops the musket and falls backward onto the ground, ending lying "
         "flat and still on his back")
e("G2", id="v19_kf_cannon_fire", from_file=PAD % "cannon_stand", final_file=PAD % "cannon_stand",
  out=RAW + "/battle/cannon_fire_kf", **KF,
  prompt="the gunner touches off the cannon, the cannon jumps and recoils sharply backward to the left on its carriage "
         "while the crew lean away, then the crew heave it back into place")
e("G2", id="v19_kf_cavalry_charge", from_file=PICK % "cav_charge", final_file=PICK % "cav_charge",
  out=RAW + "/battle/cavalry_charge_kf", **KF,
  prompt="gallops at full speed in place, one smooth gallop stride, the rider leaning forward with the sabre pointed "
         "straight ahead")

## G3 untinted VFX: a sprite-vfx still, then forge with a manual margin so nothing clips
FX = {
    "smoke_musket": ("A single burst of white and pale grey gunpowder smoke puffing out sideways to the right from a small "
                     "bright orange muzzle flash at its left edge, soft round billows, painterly oil-paint brushwork, side view",
                     "the smoke puff swells gently where it is, then thins, turns transparent and dissolves into faint "
                     "wisps until it has vanished; it stays in place and does not drift off", 2, 25, "left", False, 256),
    "cannon_blast": ("A cannon muzzle blast seen from the side with no cannon and no gun barrel visible: a bright yellow-white "
                     "flash core at the left edge with tongues of orange flame shooting to the right, and a big rolling "
                     "cloud of thick white and grey gunpowder smoke billowing out to the right, sparks and burning wadding, "
                     "painterly oil-paint brushwork",
                     "the flash flares and dies away in the first moments, the smoke cloud rolls outward to the right, "
                     "swells, then thins and drifts apart until it has almost vanished", 2.5, 25, "left", False, 384),
    "fort_explosion": ("A great powder-magazine explosion erupting upward from the ground: a towering fireball of orange "
                       "flame and black and grey smoke, flying stone and timber debris, painterly oil-paint brushwork, side view",
                       "the explosion erupts upward, the fireball swells and turns to a rising column of dark smoke while "
                       "debris falls, then the smoke slowly thins", 3, 25, "bottom", False, 384),
    "capital_fire": ("A large blaze of tall orange and yellow flames with glowing embers and dark smoke rising above, the "
                     "fire of a burning city, no buildings, painterly oil-paint brushwork",
                     "the flames flicker and leap continuously, embers float upward and the smoke rolls, an endless "
                     "steady blaze", 3, 25, "bottom", True, 384),
    "fuse_spark": ("A sputtering cannon-fuse spark: a small bright white-yellow core throwing out tiny orange sparks and a "
                   "thin wisp of grey smoke, painterly",
                   "the spark sputters and crackles, throwing out tiny sparks, the wisp of smoke curls up",
                   1.5, 16, "spark", False, 256),
    "dust_kick": ("A low spray of kicked-up brown and ochre dust and dirt bursting up from the ground, small clods of earth "
                  "flying, painterly oil-paint brushwork, side view",
                  "the dust bursts up and out from the ground, the clods arc and fall, then the dust settles and fades",
                  1.5, 16, "bottom", False, 256),
}
MARGIN = {"smoke_musket": (0.45, 0.35)}  ## the first take's smoke grew out of a 0.25 margin
for name, (img, motion, dur, frames, emit, loop, px) in FX.items():
    e("G3", id="v19_fxsrc_" + name, kind="image", type="sprite-vfx", aspect="ar_1_1", style=False, out=RAW + "/fx/%s_src" % name,
      prompt=img)
    e("G3", id="v19_fx_" + name, kind="animate", from_="v19_fxsrc_" + name, image_type="sprite-vfx", model="forge",
      duration=dur, frames=frames, frame_size=384, loop=False, crop=False, final_same=loop,
      margin_ratio_mode="manual", margin_ratio_horizontal=MARGIN.get(name, (0.25, 0.25))[0],
      margin_ratio_vertical=MARGIN.get(name, (0.25, 0.25))[1], out=RAW + "/fx/" + name, prompt=motion)

## Tried and dropped: the musket smoke grown from a small puff (the still shrunk onto a wide empty
## canvas, animated at true size). Forge barely moved it: the puff stayed tiny for all 25 frames.
## The kept musket smoke is the full cloud dissolving (v2), with a grow-in drawn in post_fx.
e("G3", id="v19_fx_smoke_musket_grow", manual=True, kind="animate", from_file=RAW + "/fx/smoke_musket_start_pad.png",
  image_type="sprite-vfx", model="forge", duration=2, frames=25, frame_size=-9, loop=False, crop=False,
  margin_ratio_mode="none", out=RAW + "/fx/smoke_musket_grow",
  prompt="the small puff of gunpowder smoke bursts out and quickly billows into a large cloud rolling out to the right, "
         "then thins, turns transparent and dissolves into faint wisps until it has vanished")

## G4 living paintings: first frame = last frame, 480p, then 2x
LIVING = {
    "title": ("assets/art/splash_title.webp",
              "A living oil painting, the camera stays completely still. The regimental flags stir gently in a breeze from "
              "the open windows, the tall ships outside rock slowly on the swell, dust motes drift through the golden "
              "sunbeams, light glints on the brass telescope and globe. Quiet room tone, distant gulls and a faint "
              "harbour bell."),
    "victory": ("assets/art/victory.webp",
                "A living oil painting, the camera stays completely still. The great crimson-and-gold standard ripples in "
                "the wind over the ramparts, cannon smoke rolls slowly across the water, the ships of the line rock gently "
                "on the swell and fire a slow saluting broadside with soft flashes, gulls wheel in the golden sunset "
                "light. Distant cannon salute, wind, waves and faint far-off cheering, no music."),
    "defeat": ("assets/art/defeat.webp",
               "A living oil painting, the camera stays completely still. The burning flagship smoulders, flames flicker "
               "and embers drift upward, the torn crimson ensign floats on the dark swell among broken spars, grey storm "
               "clouds creep across the sky, the enemy fleet sails slowly on the horizon. Crackling fire, creaking "
               "timber, wind and rolling waves, a distant tolling bell, no music."),
}
for name, (img, prompt) in LIVING.items():
    e("G4", id="v19_vid_" + name, kind="video", from_file=img, final_same=True, model="griffin", duration=8,
      out="assets/raw/video/%s_loop_480" % name, prompt=prompt, manual=(name == "title"))
    e("G4", id="v19_vid_%s_up" % name, kind="upscale", source="v19_vid_" + name,
      out="assets/raw/video/%s_loop" % name, manual=(name == "title"))

## G5 cutscenes: our cast in our rooms, no dialogue (the advisor's own voice plays over them)
SPLASH, ADVISOR = "assets/art/splash_title.webp", "assets/portraits/advisor.png"
CUTS = {
    "intro": ([SPLASH, ADVISOR],
              "Image 1 is the imperial war room, Image 2 is the old field marshal. Dawn: pale golden light spills "
              "through the tall windows of the war room from Image 1 onto the great map table and its tin soldiers. The "
              "doors open and two dust-stained couriers in blue hussar jackets hurry in and lay sealed dispatches on the "
              "map. The field marshal from Image 2, standing at the window with his hands clasped behind his back, "
              "turns slowly to face the camera with a grave, knowing look, silent. Slow push-in camera. Sound: a lone "
              "snare drum and a low rising brass theme, hurried footsteps, rustling paper, distant gulls and a harbour bell."),
    "capital_taken": (["assets/art/howto_capital.webp", "assets/art/victory.webp"],
                      "Image 1 is an enemy capital city. At dusk, regiments of our red-coated Napoleonic infantry in shakos "
                      "and white crossbelts storm the broken gate of the burning capital from Image 1 with fixed bayonets, "
                      "smoke and flames pouring from the walls; a colour-sergeant runs up the palace steps and raises our "
                      "great crimson-and-gold standard over the dome as the soldiers cheer, as in Image 2. Sweeping crane "
                      "shot. Sound: cannon fire, crackling flames, a thundering drum march and triumphant brass, soldiers "
                      "roaring a wordless cheer."),
    "capital_lost": ([ADVISOR, "assets/art/howto_capital.webp"],
                     "Image 1 is the old field marshal, Image 2 is our capital city. Night: our capital from Image 2 burns "
                     "on the horizon, orange flames under a black sky. A line of black carriages and mounted guards flees "
                     "the city along a muddy road by torchlight. Inside a jolting carriage, the field marshal from Image 1 "
                     "stares grimly out of the window at the burning city, firelight flickering on his face, silent. "
                     "Sound: a slow mournful string lament, distant cannon, carriage wheels and hooves on the road, "
                     "crackling fire."),
    "eliminated": (["assets/art/howto_walkin.webp", "assets/art/howto_clash.webp"],
                   "Image 1 is a captured frontier fort. In the fort from Image 1, victorious red-coated Napoleonic "
                   "infantry tear down the enemy's green regimental colours from the flagpole; the flag falls into the mud "
                   "and is trampled under marching boots, while a long column of disarmed enemy prisoners in green coats "
                   "from Image 2 is marched away under guard with fixed bayonets. Grey overcast light, drifting smoke. "
                   "Slow tracking shot. Sound: a steady drum beat, tramping boots, a bugle call, wind, a distant church bell."),
    "victory": ([SPLASH, ADVISOR, "assets/art/victory.webp"],
                "Image 1 is the imperial war room, Image 2 is the old field marshal, Image 3 is our victory. In the war "
                "room from Image 1 at golden sunset, the field marshal from Image 2 plants a final small gilded flag on the "
                "great map, now covered with our flags, and straightens with quiet pride; through the tall windows crowds "
                "cheer in the streets, flags wave, and a cannon salute and fireworks burst over the harbour as in Image 3. "
                "Slow pull-back camera. Sound: church bells ringing, a triumphant orchestral march with brass and drums, "
                "crowds cheering, cannon salute."),
    "defeat": ([SPLASH, ADVISOR, "assets/art/defeat.webp"],
               "Image 1 is the imperial war room, Image 2 is the old field marshal. The war room from Image 1 lies in ruins "
               "at dusk: shattered windows, toppled chairs, torn flags, smoke drifting through; the great map on the table "
               "is burning, flames curling across the painted continents and the tin soldiers. The field marshal from "
               "Image 2 stands alone in the ruins, his coat torn and dusty, and slowly lowers his head. Slow push-in "
               "camera. Sound: a slow sorrowful cello lament, crackling fire, wind through the broken windows, distant "
               "cannon fading, as grim as Image 3."),
}
for name, (imgs, prompt) in CUTS.items():
    e("G5", id="v19_cut_" + name, kind="video_refs", refs=imgs, model="griffin", duration=7, aspect="ar_16_9",
      out="assets/raw/video/cut_%s_480" % name, prompt=prompt + NOSPEECH)
    e("G5", id="v19_cut_%s_up" % name, kind="upscale", source="v19_cut_" + name, out="assets/raw/video/cut_" + name)

## G6 talk loops on Hydra (its sound track is thrown away: our cloned voices stay)
TALKERS = {"advisor": "old field marshal", "varek": "grizzled field marshal", "ysolde": "noblewoman viceroy-general",
           "quill": "portly trading-company governor", "oren": "young hussar captain", "hask": "bearded privateer commodore",
           "imre": "woman admiral"}
for who, desc in TALKERS.items():
    e("G6", id="v19_talk_" + who, kind="animate", from_file="assets/portraits/%s.png" % who, fit=True, model="hydra",
      image_type="portrait", duration=3, frames=36, frame_size=-9, loop=False, crop=False, final_same=True,
      margin_ratio_mode="manual", margin_ratio_horizontal=0.02, margin_ratio_vertical=0.02,
      out=RAW + "/loops/%s_talk" % who,
      prompt="The %s looks at the viewer and talks steadily as if speaking a sentence: the lips and jaw move through "
             "natural speaking mouth shapes, the eyes blink once, the head nods and turns very slightly, then settles "
             "back exactly into the starting pose" % desc)

## G7 leitmotif remixes, G8 marching song
REMIX = {
    "lament": ("assets/audio/music/menu.mp3", 0.6,
               "The same imperial anthem reimagined as a slow, solemn lament after a lost war: muffled drums, low strings, "
               "a lone mournful bugle and a distant wordless choir, sparse and grieving, instrumental, loopable"),
    "besieged": ("assets/audio/music/plan.mp3", 0.6,
                 "The same theme turned tense and ominous, a capital under siege: low pulsing strings, distant war drums, "
                 "dark brass swells and a ticking pizzicato, slow and threatening, instrumental, loopable"),
    "endgame": ("assets/audio/music/battle.mp3", 0.55,
                "The same battle theme as a driving late-war climax: relentless snare and timpani, urgent staccato strings, "
                "bold brass calls, rising tension, instrumental, loopable"),
}
for name, (src, strength, prompt) in REMIX.items():
    e("G7", id="v19_remix_" + name, kind="audio_transform", sample_file=src, strength=strength, duration=90,
      out=RAW + "/music/" + name, prompt=prompt)

SONGS = [
    ("A rousing Napoleonic-era army marching song sung by a rough male soldiers' chorus in unison, snare drums and "
     "fifes, brass on the choruses, steady quick-march tempo, proud and stirring",
     "[Verse 1]\nRoll out the drums at the grey of the dawn,\nThe orders are sealed and the sabres are drawn,\n"
     "We left all our sweethearts to cry on the quay,\nFor the map on the table has marked out the way.\n\n"
     "[Chorus]\nSo march, lads, march, where the tall colours fly,\nShoulder to shoulder we hold or we die,\n"
     "Over the river and up through the smoke,\nSteady and forward, the line never broke.\n\n"
     "[Verse 2]\nThe cannon are thundering over the plain,\nWe crossed it before and we'll cross it again,\n"
     "With powder and ball and a crust in the pack,\nWe'll plant the flag high and we'll never look back.\n\n"
     "[Chorus]\nSo march, lads, march, where the tall colours fly,\nShoulder to shoulder we hold or we die,\n"
     "Over the river and up through the smoke,\nSteady and forward, the line never broke."),
    ("A slow heavy grenadiers' marching song, a deep male choir singing in harmony, bass drum, side drums and a brass "
     "band, dignified and triumphant, a homecoming after a long war",
     "[Verse 1]\nTall caps of bearskin and boots worn thin,\nWe marched through the snow and we marched through the din,\n"
     "They told us the city lay three days away,\nSo we sang as we marched and we marched as we prayed.\n\n"
     "[Chorus]\nOh, the Guard is coming, the Guard is coming home,\nWith the eagle on the standard and the drummers "
     "marching on,\nLet the bells of the capital ring out loud and long,\nFor the Guard is coming home with a song.\n\n"
     "[Verse 2]\nWe held at the bridge and we held at the wall,\nWe stood in the square when the others would fall,\n"
     "Now the old flag is tattered and grey is my hair,\nBut I'd follow that drum to the end of the square.\n\n"
     "[Chorus]\nOh, the Guard is coming, the Guard is coming home,\nWith the eagle on the standard and the drummers "
     "marching on,\nLet the bells of the capital ring out loud and long,\nFor the Guard is coming home with a song."),
    ("A jaunty 19th-century fife-and-drum marching song: a rough male singer with a soldiers' chorus joining on the "
     "refrains, fifes, penny whistle and snare drum, cheerful quick-step",
     "[Verse 1]\nThe sergeant came round with a ribbon and a coin,\nSaid, here is your shilling, lad, will you not join?\n"
     "I took up the musket, I followed the drum,\nAnd I've marched every mile from the harbour to home.\n\n"
     "[Chorus]\nWith a rum-tum-tum and a fife in the rain,\nWe'll go and we'll take all the country again,\n"
     "Left, right, left, with the flags in the sun,\nWe'll march till the last of the battles is won.\n\n"
     "[Verse 2]\nMy boots have been soaked in a hundred good streams,\nMy coat has been patched at the elbows and seams,\n"
     "But give me a volley and give me a cheer,\nAnd I'll tell you, my lads, there's no place like here.\n\n"
     "[Chorus]\nWith a rum-tum-tum and a fife in the rain,\nWe'll go and we'll take all the country again,\n"
     "Left, right, left, with the flags in the sun,\nWe'll march till the last of the battles is won."),
]
for i, (desc, lyrics) in enumerate(SONGS):
    e("G8", id="v19_song_%d" % (i + 1), kind="music", duration=120, lyrics=lyrics, out=RAW + "/music/march_song_%d" % (i + 1),
      prompt=desc)

## G9 unit variants: editSpritesheet prompt on the G2 sheets (same motion, new look).
## The grenadier wording is the survey's: a longer Guard wording ("of the Imperial Guard",
## fringed epaulettes, a moustache) came back as a bare "AI server error" four times out of four.
GREN = "Make him a grenadier: a tall bearskin cap instead of the shako. Keep the plain white tin finish and exactly the same motion."
CUIR = ("Make the rider a heavy cuirassier: a polished steel breastplate over his coat and a steel helmet with a brass "
        "crest and a long flowing horsehair plume, a long straight heavy sword. Keep the plain white tin finish, the same "
        "horse, the same size and position, and exactly the same motion and timing.")
VARIANTS = {
    "grenadier_volley_kf": ("v19_kf_soldier_volley", GREN),
    "grenadier_charge_kf": ("v19_kf_soldier_charge", GREN),
    "cuirassier_charge_kf": ("v19_kf_cavalry_charge", CUIR),
}
for name, (src, prompt) in VARIANTS.items():
    e("G9", id="v19_var_" + name.replace("_kf", ""), kind="sprite_edit", source=src, edit_mode="prompt",
      out=RAW + "/battle/" + name, prompt=prompt)
## ...and the loops those units also play, so a grenadier never changes hats mid-battle: the
## game's own idle/march/gallop sheets (made 25 Sep, inside the 7-day edit window) re-skinned,
## so the motion is exactly what soldier_idle / cavalry_gallop already play
LOOP_VARIANTS = {  ## name: (source manifest id, prompt, pack order like the original's)
    "grenadier_idle": ("soldier_idle_anim", GREN, "ping"),
    "grenadier_march": ("soldier_march_anim", GREN, "auto"),
    "cuirassier_idle": ("cavalry_idle_anim", CUIR, "auto"),
    "cuirassier_gallop": ("cavalry_gallop_anim", CUIR, "auto"),
}
for name, (src, prompt, order) in LOOP_VARIANTS.items():
    e("G9", id="v19_var_" + name, kind="sprite_edit", source=src, edit_mode="prompt", out=RAW + "/battle/" + name,
      prompt=prompt)

## G10 three-quarter tabletop views, G11 3D pieces
VIEWS = {"infantry": "assets/raw/battle/soldier_stand.png", "cavalry": "assets/raw/battle/cavalry_stand.png",
         "cannon": "assets/raw/battle/cannon_stand.png"}
for name, src in VIEWS.items():
    e("G10", id="v19_view_" + name, kind="rotate", from_file=src, rotation=45, elevation=30, n=2,
      out=RAW + "/views/%s_q" % name)

PIECES = {
    "infantry": ("ar_3_4", "a Napoleonic line infantryman in a crimson coat with white crossbelts, black shako and grey "
                           "trousers, musket held upright at his side, standing at attention on a small round "
                           "green-painted base. Full figure, front three-quarter view"),
    "cavalry": ("ar_4_3", "a Napoleonic hussar in a sky-blue braided dolman jacket and fur busby, sabre held upright at his "
                          "shoulder, riding a brown horse standing on a flat oval green-painted base. Full figure, side "
                          "three-quarter view"),
    "cannon": ("ar_4_3", "a Napoleonic bronze field cannon on a dark olive-green wooden carriage with two large spoked "
                         "wheels and a trail, standing on a flat rectangular green-painted base. Full object, "
                         "three-quarter view"),
    "flag": ("ar_3_4", "a Napoleonic colour-bearer in a crimson coat with white crossbelts and black shako holding a tall "
                       "staff with a large crimson-and-gold regimental flag with a gold fringe, standing on a small round "
                       "green-painted base. Full figure, front three-quarter view"),
}
for name, (aspect, what) in PIECES.items():
    e("G11", id="v19_piece_" + name, kind="image", type="asset", art_style="Hand-Painted", aspect=aspect, style=False,
      out=RAW + "/models/%s_ref" % name,
      prompt="A single hand-painted antique tin toy miniature: %s, even studio lighting, plain light grey background" % what)
    e("G11", id="v19_model_" + name, kind="model3d", from_="v19_piece_" + name, faces=20000, texture_size=1024,
      texture_type="pbr", out=RAW + "/models/" + name)


def fix_keys(ent):
    ## python keywords: from_ -> from
    if "from_" in ent:
        ent["from"] = ent.pop("from_")
    return ent


E = [fix_keys(x) for x in E]
BY = {x["id"]: x for x in E}

# ---------------------------------------------------------------- review items
## (batch, item id, group label, label, post, chain of manifest ids, target, options)
ITEMS = []


def item(batch, iid, group, label, post, chain, target, **opts):
    ITEMS.append({"batch": batch, "id": iid, "group": group, "label": label, "post": post, "chain": chain,
                  "target": target, "opts": opts})


item("v19_dice", "felt", "table", "Green baize felt (seamless, 1024)", "tex", ["v19_tex_felt"], "assets/tex/felt.webp", size=(1024, 1024))
item("v19_dice", "rail_wood", "table", "Mahogany rail (seamless, grain horizontal)", "tex", ["v19_tex_rail"], "assets/tex/rail_wood.webp", size=(1024, 1024), flatten=90)
item("v19_dice", "brass", "table", "Brushed brass (seamless, 512)", "tex", ["v19_tex_brass"], "assets/tex/brass.webp", size=(512, 512), flatten=50)
item("v19_dice", "plaque", "table", "Volley-total plaque (blank, 640 wide)", "cut", ["v19_plaque"], "assets/hud/plaque.png", width=640)
item("v19_dice", "fortune_star", "fortune", "Fortune's favour: gold star with glow (256)", "star", ["v19_fortune_star"], "assets/hud/fortune_star.png", glow=True)
item("v19_dice", "fortune_empty", "fortune", "Fortune slot: empty pewter socket (256)", "star", ["v19_fortune_empty"], "assets/hud/fortune_empty.png", glow=False)
item("v19_dice", "sfx_fortune", "fortune", "Calling on Fortune (sfx)", "sfx", ["v19_sfx_fortune"], "assets/audio/sfx/fortune.wav", name="fortune")
item("v19_dice", "sfx_fortune_gained", "fortune", "A favour banked (sfx)", "sfx", ["v19_sfx_fortune_gained"], "assets/audio/sfx/fortune_gained.wav", name="fortune_gained")
item("v19_dice", "howto_fortune", "fortune", "How to play: Fortune", "art", ["v19_howto_fortune"], "assets/art/howto_fortune.webp")

KF_ITEMS = [("soldier_volley_kf", "v19_kf_soldier_volley", pack_anims.INF, "Volley: stand, aim, recoil, shoulder arms"),
            ("soldier_kneel_volley_kf", "v19_kf_soldier_kneel_volley", pack_anims.INF, "Kneeling volley"),
            ("soldier_charge_kf", "v19_kf_soldier_charge", pack_anims.INF, "Bayonet lunge (stand to stand)"),
            ("soldier_cheer_kf", "v19_kf_soldier_cheer", pack_anims.INF, "Cheer"),
            ("soldier_reload_kf", "v19_kf_soldier_reload", pack_anims.INF, "Reload"),
            ("soldier_fall_kf", "v19_kf_soldier_fall", pack_anims.INF, "Fall: stand to lying flat (one-shot, hold last frame)"),
            ("cannon_fire_kf", "v19_kf_cannon_fire", pack_anims.GUN, "Cannon fires and recoils"),
            ("cavalry_charge_kf", "v19_kf_cavalry_charge", pack_anims.CAV, "Cavalry charge gallop (loop)")]
MARKS = {"soldier_volley_kf": "musket", "soldier_kneel_volley_kf": "musket", "cannon_fire_kf": "cannon",
         "soldier_fall_kf": "fall", "grenadier_volley_kf": "musket"}
## Cheer: the re-roll (v2) shrank the figure to 73% by its last frames, so the first take is kept
## (fetched back from listGenerations). Its frame 0 is a port-arms pose and 1-11 the cheer, and
## 12-24 lower to the stand: play every other frame of that lowering backwards first, so the
## figure rises out of the stance, then cheer and lower.
## Charge (v2): frame 8 flicks the musket up behind his back for one frame; it is skipped. The
## take ends holding the charge-bayonet guard rather than the stand.
ORDERS = {"soldier_cheer_kf": [24, 22, 20, 18, 16, 14, 12] + list(range(1, 25)),
          "soldier_charge_kf": list(range(0, 8)) + list(range(9, 25))}
ORDERS["grenadier_charge_kf"] = ORDERS["soldier_charge_kf"]  ## the same motion, re-skinned
PICKS = {"soldier_cheer_kf": (2, RAW + "/battle/soldier_cheer_kf_take1.webp")}
for name, mid, anchor, label in KF_ITEMS:
    item("v19_battle", name, "keyframes", label, "sheet", [mid], "assets/battle/%s.webp" % name, anchor=anchor,
         ref=BY[mid]["from_file"], ref_last=BY[mid].get("final_file"), marks=MARKS.get(name), order=ORDERS.get(name),
         pick=PICKS.get(name))
for name, (src, prompt) in VARIANTS.items():
    anchor = pack_anims.CAV if name.startswith("cuirassier") else pack_anims.INF
    item("v19_battle", name, "variants", name.replace("_kf", "").replace("_", " ").capitalize() + " (editSpritesheet)",
         "sheet", ["v19_var_" + name.replace("_kf", "")], "assets/battle/%s.webp" % name, anchor=anchor,
         ref=BY[src]["from_file"], ref_last=BY[src].get("final_file"), marks=MARKS.get(name), order=ORDERS.get(name))
for name, (src, prompt, order) in LOOP_VARIANTS.items():
    anchor = pack_anims.CAV if name.startswith("cuirassier") else pack_anims.INF
    ref = "assets/raw/battle/%s_stand_pad.png" % ("cavalry" if name.startswith("cuirassier") else "soldier")
    item("v19_battle", name, "variants", name.replace("_", " ").capitalize() + " (re-skin of the game's own loop)",
         "sheet", ["v19_var_" + name], "assets/battle/%s.webp" % name, anchor=anchor, ref=ref, order=order)

## Tried and dropped: outpaint on the cannon blast, whose cloud runs into a crop box (x <= 660,
## y >= 152 of each 768 cell) from frame 16 on. It came back as 24 tiny 264x178 cells of a static
## cloud, flash gone. Instead the sheet plays only its clean frames 0-15 (KEEP) and the game fades it.
e("G3", id="v19_fx_cannon_blast_out", kind="sprite_edit", source="v19_fx_cannon_blast", edit_mode="outpaint", manual=True,
  out=RAW + "/fx/cannon_blast_out", prompt="zoom out so the whole smoke cloud stays inside the frame with empty space around it")
KEEP = {"cannon_blast": 16}
FACES = {"smoke_musket": "right", "cannon_blast": "right"}  ## the way the shot and its smoke travel
GROW_IN = {"smoke_musket": [0.3, 0.55, 0.8]}  ## frames drawn in front: the first frame scaled up from the muzzle
for name, (img, motion, dur, frames, emit, loop, px) in FX.items():
    chain = ["v19_fxsrc_" + name, "v19_fx_" + name]
    item("v19_fx", name, "fx", name.replace("_", " ").capitalize() + (" (loop)" if loop else " (one-shot)"), "fx",
         chain, "assets/fx/%s.webp" % name, emit=emit, loop=loop, px=px, faces=FACES.get(name), grow_in=GROW_IN.get(name),
         keep=KEEP.get(name))

item("v19_video", "title_loop", "living paintings", "Title screen, living painting (loop)", "loopvid",
     ["v19_vid_title", "v19_vid_title_up"], "assets/video/title_loop.ogv",
     fallback="review/ludo_explore/warroom_loop_up2x_video.mp4")
for name in ("victory", "defeat"):
    item("v19_video", name + "_loop", "living paintings", "%s screen, living painting (loop)" % name.capitalize(), "loopvid",
         ["v19_vid_" + name, "v19_vid_%s_up" % name], "assets/video/%s_loop.ogv" % name)
for name in CUTS:
    item("v19_video", "cut_" + name, "cutscenes", "Cutscene: " + name.replace("_", " "), "cutscene",
         ["v19_cut_" + name, "v19_cut_%s_up" % name], "assets/video/cut_%s.ogv" % name)

for who in TALKERS:
    item("v19_portraits", who + "_talk", "talk loops", "%s talking (Hydra, sound discarded)" % who.capitalize(), "talk",
         ["v19_talk_" + who], "assets/portraits/loops/%s_talk.webp" % who)

LUFS = {"lament": -18.0, "besieged": -19.0, "endgame": -18.0}  ## like defeat.mp3, plan.mp3, battle.mp3
for name in REMIX:
    item("v19_music", name, "remixes", "%s (remix of %s)" % (name.capitalize(), os.path.basename(REMIX[name][0])), "music",
         ["v19_remix_" + name], "assets/audio/music/%s.mp3" % name, lufs=LUFS[name])
item("v19_music", "lament_explore", "remixes", "Lament, the earlier 60 s take (alternative: accept one lament)", "music",
     [], "assets/audio/music/lament.mp3", fallback="review/ludo_explore/remix_menu_lament.mp3", lufs=LUFS["lament"],
     note="From the capability survey; createAudioTransform menu.mp3 at 0.6. Accept this OR the new lament.")
for i in range(len(SONGS)):
    item("v19_music", "march_song_%d" % (i + 1), "marching song", "Marching song, take %d (accept one)" % (i + 1), "music",
         ["v19_song_%d" % (i + 1)], "assets/audio/music/march_song.mp3", install_now=(i == 0), lufs=-14.0)

for name in VIEWS:
    for k in range(2):
        item("v19_models", "view_%s_%d" % (name, k), "tabletop views", "%s, 45 deg around, 30 deg up (take %d)" % (name.capitalize(), k + 1),
             "view", ["v19_view_" + name], "assets/raw/views/%s_q_%d.webp" % (name, k), index=k)
for name in PIECES:
    item("v19_models", "model_" + name, "3D pieces", "3D painted piece: %s (4 snapshots)" % name, "model",
         ["v19_piece_" + name, "v19_model_" + name], "assets/models/%s.glb" % name)

GROUP_OF_BATCH = {}
for it in ITEMS:
    GROUP_OF_BATCH.setdefault(it["batch"], set()).update(BY[c]["group"] for c in it["chain"] if c in BY)


# ---------------------------------------------------------------- helpers
def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def ledger():
    return json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}


def manifest():
    return json.load(open(MAN))


def man_by():
    return {a["id"]: a for a in manifest()["assets"]}


def write_manifest():
    """Add the v1.9 entries that are missing. An entry already there is left alone: its
    version and prompt belong to the review loop from then on."""
    man = manifest()
    have = {a["id"] for a in man["assets"]}
    added = 0
    for ent in E:
        if ent["id"] not in have:
            man["assets"].append(dict(ent))
            added += 1
    if added:
        json.dump(man, open(MAN, "w"), indent=1)
    return added


def ff(*args, quiet=True):
    cmd = [FFMPEG, "-v", "error", "-y"] + [str(a) for a in args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg failed: %s\n%s" % (" ".join(cmd[-6:]), r.stderr[-800:]))
    return r


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                          "stream=codec_type,codec_name,width,height,r_frame_rate,nb_frames,duration,sample_rate,channels:format=duration",
                          "-of", "json", path], capture_output=True, text=True).stdout
    return json.loads(out or "{}")


def abs_(rel):
    return rel if os.path.isabs(rel) else os.path.join(ROOT, rel)


def batch_dir(batch):
    return os.path.join(ROOT, "review", batch)


def out_file(chain_id):
    """The generated file of a manifest id (from the ledger), or None."""
    led = ledger()
    ent = led.get(chain_id)
    if not ent or not ent.get("file"):
        return None
    need = int(man_by().get(chain_id, {}).get("v", 1))
    if int(ent.get("v", 1)) < need:
        return None
    p = abs_(ent["file"])
    return p if os.path.exists(p) else None


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".tmp"
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def gif_from_sheet(sheet, meta, out_gif, bg="0x5a5a5a", max_w=384):
    """An animated preview of a packed sheet, played in its frame order at its fps."""
    tmp = tempfile.mkdtemp(prefix="v19gif_")
    cols, rows, n = int(meta["cols"]), int(meta["rows"]), int(meta["frames"])
    ff("-i", sheet, "-vf", "format=rgba,untile=%dx%d" % (cols, rows), "-f", "image2", os.path.join(tmp, "f_%04d.png"))
    order = meta.get("order") or list(range(n))
    for k, idx in enumerate(order):
        os.symlink(os.path.join(tmp, "f_%04d.png" % (int(idx) + 1)), os.path.join(tmp, "o_%04d.png" % k))
    fps = float(meta.get("fps") or 8)
    w = min(max_w, int(meta["fw"]))
    ff("-framerate", "%.3f" % fps, "-i", os.path.join(tmp, "o_%04d.png"), "-filter_complex",
       "color=c=%s:s=%dx%d[bg];[bg][0]overlay=shortest=1,scale=%d:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
       % (bg, int(meta["fw"]), int(meta["fh"]), w), "-loop", "0", out_gif)
    shutil.rmtree(tmp, ignore_errors=True)


def patch_json(path, **kw):
    m = json.load(open(path))
    m.update(kw)
    json.dump(m, open(path, "w"))
    return m


def first_bbox(report):
    """frame 0's alpha bbox from a sheet_tool check report, as (x, y, w, h), and the frame size."""
    m = re.search(r"frame\s+0\s+bbox \[P: \((-?\d+), (-?\d+)\), S: \((-?\d+), (-?\d+)\)\]", report)
    fm = re.search(r"frame=(\d+)x(\d+)", report)
    return tuple(int(x) for x in m.groups()), (int(fm.group(1)), int(fm.group(2)))


def check_full(raw, meta):
    out = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "tools/sheet_tool.gd", "--", "check", raw,
                          str(meta["cols"]), str(meta["rows"]), str(meta["frames"])], capture_output=True, text=True)
    return out.stdout


# ---------------------------------------------------------------- post-processing
## Each returns (review file, install pairs [(review rel, game rel)], extra meta)

def post_tex(it, src, bd):
    name = os.path.basename(it["target"])
    w, h = it["opts"]["size"]
    out = os.path.join(bd, "tex", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sig = it["opts"].get("flatten")
    if sig:
        ## even out the painted lighting (a bright patch repeats on every tile): subtract a wide
        ## blur taken on a 3x3 tiling (so the result still wraps) and add back the mean colour
        ff("-i", src, "-filter_complex",
           "[0]scale=%d:%d:flags=lanczos,format=gbrp,split=4[o][t][m][z];"
           "[t]split=3[t1][t2][t3];[t1][t2][t3]hstack=3,split=3[r1][r2][r3];[r1][r2][r3]vstack=3,"
           "gblur=sigma=%d,crop=%d:%d:%d:%d[b];"
           "[o][b]blend=all_expr='A-B+128'[d];"
           "[m]scale=1:1:flags=area,scale=%d:%d[mean];[d][mean]blend=all_expr='A+B-128'[f];[z]nullsink;[f]format=rgb24"
           % (w, h, sig, w, h, w, h, w, h), "-c:v", "libwebp", "-quality", "92", out)
    else:
        ff("-i", src, "-vf", "scale=%d:%d:flags=lanczos" % (w, h), "-c:v", "libwebp", "-quality", "92", out)
    ## the reviewer judges the seams on a 2x2 tiling
    prev = os.path.join(bd, "tex", name.replace(".webp", "_tiled.jpg"))
    ff("-i", out, "-filter_complex", "[0]split=4[a][b][c][d];[a][b]hstack[t];[c][d]hstack[u];[t][u]vstack,scale=1024:-2",
       "-q:v", "3", prev)
    return os.path.relpath(prev, bd), [(os.path.relpath(out, bd), it["target"])], {"size": "%dx%d" % (w, h)}


def post_cut(it, src, bd):
    out = os.path.join(bd, "hud", os.path.basename(it["target"]))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ff("-i", src, "-vf", "scale=%d:-2:flags=lanczos,format=rgba" % it["opts"]["width"], out)
    p = probe(out)["streams"][0]
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {"size": "%dx%d" % (p["width"], p["height"])}


def post_star(it, src, bd):
    out = os.path.join(bd, "hud", os.path.basename(it["target"]))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fit = "scale=200:200:force_original_aspect_ratio=decrease:flags=lanczos,format=rgba,pad=256:256:(ow-iw)/2:(oh-ih)/2:color=0x00000000"
    if it["opts"].get("glow"):
        ## a soft gold halo from the star's own silhouette, under the star
        ff("-i", src, "-filter_complex",
           "[0]%s,split[s][g];[g]alphaextract,gblur=sigma=11,lut=y=val*0.9[ga];"
           "color=c=0xFFD466:s=256x256,format=rgba[col];[col][ga]alphamerge[glow];[glow][s]overlay=format=auto,format=rgba" % fit,
           "-frames:v", "1", out)
    else:
        ff("-i", src, "-vf", fit, "-frames:v", "1", out)
    ## how it reads at 24, 32 and 40 px on a dark and a light ground
    prev = out.replace(".png", "_sizes.png")
    ff("-i", out, "-filter_complex",
       "[0]split=3[a][b][c];[a]scale=24:24[a2];[b]scale=32:32[b2];[c]scale=40:40[c2];"
       "color=c=0x2a2320:s=200x60[bg];[bg][a2]overlay=20:18[x];[x][b2]overlay=70:14[y];[y][c2]overlay=130:10,scale=600:-1:flags=neighbor",
       "-frames:v", "1", prev)
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {"size": "256x256", "preview_sizes": os.path.relpath(prev, bd)}


def post_sfx(it, src, bd):
    name = it["opts"]["name"]
    d = os.path.join(bd, "sfx")
    r = subprocess.run([sys.executable, os.path.join(HERE, "prep_sfx.py"), "--out", d, name], capture_output=True, text=True)
    log("  ", r.stdout.strip())
    out = os.path.join(d, name + ".wav")
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {"prep": r.stdout.strip()}


def post_art(it, src, bd):
    out = os.path.join(bd, "art", os.path.basename(it["target"]))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ff("-i", src, "-vf", "scale=1344:768:flags=lanczos", "-c:v", "libwebp", "-quality", "90", out)
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {"size": "1344x768"}


def alpha_psnr(a, b):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", a, "-i", b, "-lavfi",
                        "[0]format=rgba,alphaextract[x];[1]format=rgba,alphaextract[y];[x][y]psnr", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"average:([0-9.]+|inf)", r.stderr)
    return float("inf") if m and m.group(1) == "inf" else (float(m.group(1)) if m else 0.0)


def probe_frames(path, cols, rows, n, ref=""):
    """sheet_tool probe: per frame bbox, rightmost point and difference to a reference."""
    args = [GODOT, "--headless", "--path", ROOT, "-s", "tools/sheet_tool.gd", "--", "probe", abs_(path), str(cols), str(rows), str(n)]
    if ref:
        args.append(abs_(ref))
    out = subprocess.run(args, capture_output=True, text=True).stdout
    rows_ = []
    for line in out.splitlines():
        if line.startswith("PROBE "):
            v = line.split()[1:]
            rows_.append({"i": int(v[0]), "x0": int(v[1]), "y0": int(v[2]), "x1": int(v[3]), "y1": int(v[4]),
                          "tx": float(v[5]), "ty": float(v[6]), "diff": float(v[7])})
    return rows_


def normalize_canvas(src, ref, ref_last=None, W=1152, H=768, P=200):
    """animateSpriteKeyframes returns cells bigger than our 1152x768 canvas (1173x768,
    1217x769, 1297x770...): the same picture with the canvas grown on some side. Find the
    shift by lining up the frame that should equal a keyframe (the first, or the last when
    that one matches its keyframe better), refine it by pixel match, and re-cut every cell
    to our exact canvas (padding where the shift is negative)."""
    meta = json.load(open(os.path.splitext(src)[0] + ".json"))
    cols, rows, n = int(meta["cols"]), int(meta["rows"]), int(meta["frames"])
    p = probe(src)["streams"][0]
    fw, fh = int(p["width"]) // cols, int(p["height"]) // rows
    if (fw, fh) == (W, H) or not ref:
        return src, (0, 0)
    fr = probe_frames(src, cols, rows, n)
    cands = []
    for idx, r in ((0, ref), (n - 1, ref_last)):
        if not r:
            continue
        rb = probe_frames(r, 1, 1, 1)[0]
        f = fr[idx]
        size = abs((f["x1"] - f["x0"]) - (rb["x1"] - rb["x0"])) + abs((f["y1"] - f["y0"]) - (rb["y1"] - rb["y0"]))
        ox = int(round(((f["x0"] + f["x1"]) - (rb["x0"] + rb["x1"])) / 2.0))
        oy = f["y1"] - rb["y1"]
        cands.append((size, ox, oy, idx, r))
    size, ox, oy, idx, r = min(cands)
    tmp = tempfile.mkdtemp(prefix="v19canvas_")
    cell = "format=rgba,crop=%d:%d:%d:%d,pad=%d:%d:%d:%d:color=0x00000000" % (fw, fh, (idx % cols) * fw, (idx // cols) * fh,
                                                                            fw + 2 * P, fh + 2 * P, P, P)
    best, bx, by = -1.0, ox, oy
    for dy in range(-2, 3):
        for dx in range(-3, 4):
            x, y = ox + dx, oy + dy
            f0 = os.path.join(tmp, "f_%d_%d.png" % (x, y))
            ff("-i", src, "-vf", cell + ",crop=%d:%d:%d:%d" % (W, H, P + x, P + y), "-frames:v", "1", f0)
            q = alpha_psnr(f0, abs_(r))
            if q > best:
                best, bx, by = q, x, y
    shutil.rmtree(tmp, ignore_errors=True)
    out = os.path.splitext(src)[0] + "_canvas.png"
    ff("-i", src, "-vf", "format=rgba,untile=%dx%d,pad=%d:%d:%d:%d:color=0x00000000,crop=%d:%d:%d:%d,tile=%dx%d,format=rgba"
       % (cols, rows, fw + 2 * P, fh + 2 * P, P, P, W, H, P + bx, P + by, cols, rows), "-frames:v", "1", out)
    m2 = dict(meta)
    m2["crop"] = [bx, by]
    json.dump(m2, open(os.path.splitext(out)[0] + ".json", "w"))
    log("  canvas: %dx%d cells, shifted by (%d, %d) onto %dx%d, matched on frame %d (%.1f dB)" % (fw, fh, -bx, -by, W, H, idx, best))
    return out, (bx, by)


def sheet_marks(it, src, W=1152, H=768):
    """The moments the battlefield syncs to, read off the frames (on our 1152x768 canvas):
    "shot" + "muzzle" for a firing sheet, "down" for a fall. Indices are in playback order."""
    kind = it["opts"].get("marks")
    if not kind:
        return {}
    m = json.load(open(os.path.splitext(src)[0] + ".json"))
    fr = probe_frames(src, m["cols"], m["rows"], m["frames"])
    out = {}
    if kind == "musket":
        ## the aim is held where the musket tip is far out to the right at a steady height;
        ## the shot is the last frame of that first hold, just before the recoil kicks it
        base = fr[0]["tx"]
        far = [f for f in fr if f["tx"] > base + 150]
        if far:
            ys = sorted(f["ty"] for f in far)
            aim_y = ys[len(ys) // 2]
            run = []
            for f in fr:
                if f["tx"] > base + 150 and abs(f["ty"] - aim_y) < 40:
                    run.append(f)
                elif run:
                    break
            shot = run[-1] if run else far[0]
            out = {"shot": shot["i"], "muzzle": [round(shot["tx"] / W, 3), round(shot["ty"] / H, 3)]}
    elif kind == "cannon":
        ## the discharge is the first frame whose outline jumps out past the muzzle (flash,
        ## sparks); the muzzle itself is where the barrel ends at rest
        base = fr[0]
        shot = next((f for f in fr[1:] if f["tx"] > base["tx"] + 40 or f["y0"] < base["y0"] - 30), fr[len(fr) // 4])
        out = {"shot": shot["i"], "muzzle": [round(base["tx"] / W, 3), round(base["ty"] / H, 3)]}
    elif kind == "fall":
        final_h = fr[-1]["y1"] - fr[-1]["y0"]
        down = next(f for f in fr if f["y1"] - f["y0"] <= 1.25 * final_h)
        out = {"down": down["i"]}
    if it["opts"].get("faces"):
        out["faces"] = it["opts"]["faces"]
    log("  marks %s" % json.dumps(out))
    return out


def post_sheet(it, src, bd):
    name = os.path.basename(it["target"]).replace(".webp", "")
    src, crop = normalize_canvas(src, it["opts"].get("ref"), it["opts"].get("ref_last"))
    rel = os.path.relpath(os.path.join(bd, "battle", name + ".webp"), ROOT)
    os.makedirs(os.path.join(bd, "battle"), exist_ok=True)
    order = None
    if isinstance(it["opts"].get("order"), list):
        order = it["opts"]["order"]
    elif it["opts"].get("order"):
        m0 = json.load(open(os.path.splitext(src)[0] + ".json"))
        n0 = int(m0["frames"])
        ping = list(range(0, n0)) + list(range(n0 - 2, 0, -1))
        if it["opts"]["order"] == "ping":
            order = ping
        else:  ## a loop: ping-pong only if its seam is worse than any step (as pack_anims does)
            rep = check_full(src, m0)
            mx = float(re.search(r"max_step ([0-9.]+)", rep).group(1))
            seam = float(re.search(r"seam\(last->first\) ([0-9.]+)", rep).group(1))
            order = ping if seam > mx else None
    report = pack_anims.pack_sheet(src, rel, it["opts"]["anchor"], order)
    meta = json.load(open(abs_(rel.replace(".webp", ".json"))))
    marks = sheet_marks(it, src)
    if marks and order:  ## frame indices -> positions in the playback order
        for k in ("shot", "down"):
            if k in marks and marks[k] in order:
                marks[k] = order.index(marks[k])
    if marks:
        meta = patch_json(abs_(rel.replace(".webp", ".json")), **marks)
    gif = os.path.join(bd, "battle", name + "_anim.gif")
    gif_from_sheet(abs_(rel), meta, gif)
    summ = [l for l in report.splitlines() if l.startswith("SUMMARY")]
    return (os.path.relpath(gif, bd),
            [("battle/%s.webp" % name, it["target"]), ("battle/%s.json" % name, it["target"].replace(".webp", ".json"))],
            {"grid": "%sx%s, %s frames of %sx%s at %s fps" % (meta["cols"], meta["rows"], meta["frames"], meta["fw"], meta["fh"], meta.get("fps")),
             "check": summ[0] if summ else "", "canvas_crop": list(crop)})


def grow_in(src, scales, emit):
    """Prepend frames that grow the first frame out of its emitter (a muzzle flash that blooms
    into the cloud), and return the new raw sheet."""
    meta = json.load(open(os.path.splitext(src)[0] + ".json"))
    cols, rows, n = int(meta["cols"]), int(meta["rows"]), int(meta["frames"])
    p = probe(src)["streams"][0]
    fw, fh = int(p["width"]) // cols, int(p["height"]) // rows
    f0 = probe_frames(src, cols, rows, 1)[0]
    w, h = f0["x1"] - f0["x0"], f0["y1"] - f0["y0"]
    ex = f0["x0"] + 0.06 * w if emit == "left" else f0["x0"] + 0.5 * w
    ey = f0["y0"] + (h if emit == "bottom" else 0.5 * h)
    tmp = tempfile.mkdtemp(prefix="v19grow_")
    ff("-i", src, "-vf", "format=rgba,untile=%dx%d" % (cols, rows), "-f", "image2", os.path.join(tmp, "o_%04d.png"))
    k = len(scales)
    for i, sc in enumerate(scales):
        sw, sh = max(2, int(fw * sc)) // 2 * 2, max(2, int(fh * sc)) // 2 * 2
        x, y = int(round(ex - ex * sw / fw)), int(round(ey - ey * sh / fh))
        ff("-i", os.path.join(tmp, "o_0001.png"), "-filter_complex",
           "[0]scale=%d:%d:flags=lanczos,format=rgba[s];color=0x00000000:s=%dx%d,format=rgba[bg];[bg][s]overlay=%d:%d:format=auto,format=rgba"
           % (sw, sh, fw, fh, x, y), "-frames:v", "1", os.path.join(tmp, "g_%04d.png" % (i + 1)))
    total = n + k
    oc = 1
    while oc * oc < total:
        oc += 1
    orows = (total + oc - 1) // oc
    seq = [os.path.join(tmp, "g_%04d.png" % (i + 1)) for i in range(k)] + [os.path.join(tmp, "o_%04d.png" % (i + 1)) for i in range(n)]
    for i in range(oc * orows):  ## empty cells to fill the grid
        link = os.path.join(tmp, "s_%04d.png" % i)
        if i < total:
            os.symlink(seq[i], link)
        else:
            ff("-f", "lavfi", "-i", "color=0x00000000:s=%dx%d,format=rgba" % (fw, fh), "-frames:v", "1", link)
    out = os.path.splitext(src)[0] + "_grow.png"
    ff("-framerate", "1", "-i", os.path.join(tmp, "s_%04d.png"), "-vf", "format=rgba,tile=%dx%d" % (oc, orows), "-frames:v", "1", out)
    shutil.rmtree(tmp, ignore_errors=True)
    m2 = dict(meta)
    m2.update(cols=oc, rows=orows, frames=total, grow_in=scales)
    if meta.get("duration"):
        m2["duration"] = float(meta["duration"]) * total / n
    json.dump(m2, open(os.path.splitext(out)[0] + ".json", "w"))
    return out


def post_fx(it, src, bd):
    name = os.path.basename(it["target"]).replace(".webp", "")
    if it["opts"].get("grow_in"):
        dur = json.load(open(os.path.splitext(src)[0] + ".json")).get("duration") or \
            man_by().get(it["chain"][-1], {}).get("duration") or 2
        m0 = json.load(open(os.path.splitext(src)[0] + ".json"))
        m0["duration"] = dur
        json.dump(m0, open(os.path.splitext(src)[0] + ".json", "w"))
        src = grow_in(src, it["opts"]["grow_in"], it["opts"]["emit"])
    raw_meta = json.load(open(os.path.splitext(src)[0] + ".json"))
    rel = os.path.relpath(os.path.join(bd, "fx", name + ".webp"), ROOT)
    os.makedirs(os.path.join(bd, "fx"), exist_ok=True)
    report = check_full(src, raw_meta)
    print("\n".join(l for l in report.splitlines() if l.startswith("SUMMARY")))
    px = it["opts"]["px"]
    print(pack_anims.tool("shrink", src, str(raw_meta["cols"]), str(raw_meta["rows"]), str(px), rel, str(raw_meta["frames"])))
    (x, y, w, h), (fw, fh) = first_bbox(report)
    emit = it["opts"]["emit"]
    if emit == "left":
        ax, ay = (x + 0.06 * w) / fw, (y + 0.5 * h) / fh
    elif emit == "bottom":
        ax, ay = (x + 0.5 * w) / fw, (y + h) / fh
    elif emit == "spark":  ## the burning point sits at the foot of its smoke wisp
        ax, ay = (x + 0.5 * w) / fw, (y + 0.85 * h) / fh
    else:
        ax, ay = (x + 0.5 * w) / fw, (y + 0.5 * h) / fh
    dur = raw_meta.get("duration") or man_by().get(it["chain"][-1], {}).get("duration") or 2
    fps = round(int(raw_meta["frames"]) / float(dur), 3)
    frames = int(raw_meta["frames"])
    extra = {"fps": fps, "loop": bool(it["opts"]["loop"]), "ax": round(ax, 3), "ay": round(ay, 3)}
    if it["opts"].get("faces"):
        extra["faces"] = it["opts"]["faces"]
    if it["opts"].get("keep"):  ## play only the clean first frames
        extra["order"] = list(range(int(it["opts"]["keep"])))
    seam_note = ""
    if it["opts"]["loop"]:
        ## generated to end on its first frame: drop the duplicate
        mx = float(re.search(r"max_step ([0-9.]+)", report).group(1))
        seam = float(re.search(r"seam\(prev->first\) ([0-9.]+)", report).group(1))
        extra["order"] = list(range(frames - 1))
        seam_note = "seam %.2f vs max step %.2f" % (seam, mx)
    meta = patch_json(abs_(rel.replace(".webp", ".json")), **extra)
    gif = os.path.join(bd, "fx", name + "_anim.gif")
    gif_from_sheet(abs_(rel), meta, gif, bg="0x2b2b33")
    summ = [l for l in report.splitlines() if l.startswith("SUMMARY")]
    return (os.path.relpath(gif, bd),
            [("fx/%s.webp" % name, it["target"]), ("fx/%s.json" % name, it["target"].replace(".webp", ".json"))],
            {"grid": "%sx%s, %s frames of %sx%s at %s fps, emitter (%.2f, %.2f)" % (meta["cols"], meta["rows"], meta["frames"], meta["fw"], meta["fh"], fps, ax, ay),
             "check": (summ[0] if summ else "") + (" · loop " + seam_note if seam_note else "")})


def vinfo(path):
    p = probe(path)
    v = [s for s in p.get("streams", []) if s.get("codec_type") == "video"][0]
    a = [s for s in p.get("streams", []) if s.get("codec_type") == "audio"]
    num, den = v["r_frame_rate"].split("/")
    fps = float(num) / float(den)
    dur = float(p.get("format", {}).get("duration") or v.get("duration") or 0)  ## Ogg streams carry neither count nor length
    n = int(v.get("nb_frames") or round(float(v.get("duration") or dur) * fps))
    return {"w": int(v["width"]), "h": int(v["height"]), "fps": fps, "frames": n, "audio": bool(a), "duration": dur}


def encode_pair(filter_args, maps, out_base):
    """The same filtered clip as .ogv (Theora + Vorbis, for Godot) and .mp4 (for the review page)."""
    ff(*filter_args, *maps, "-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "4", out_base + ".ogv")
    ff(*filter_args, *maps, "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k",
       "-movflags", "+faststart", out_base + ".mp4")


def post_loopvid(it, src, bd, xfade_frames=12):
    """A living painting as a seamless loop: the last half second crossfades into the first
    (video and sound together), and the clip is that much shorter, so the end runs straight
    into the start."""
    name = os.path.basename(it["target"]).replace(".ogv", "")
    master = abs_("assets/raw/video/%s.mp4" % name)
    if os.path.abspath(src) != master:
        copy(src, master)
    info = vinfo(master)
    n, fps, k = info["frames"], info["fps"], xfade_frames
    x = k / fps
    d = n / fps
    fc = ("[0:v]split=3[v1][v2][v3];"
          "[v1]trim=start_frame=0:end_frame={k},setpts=PTS-STARTPTS[head];"
          "[v2]trim=start_frame={nk}:end_frame={n},setpts=PTS-STARTPTS[tail];"
          "[v3]trim=start_frame={k}:end_frame={nk},setpts=PTS-STARTPTS[body];"
          "[tail][head]xfade=transition=fade:duration={x:.4f}:offset=0[blend];"
          "[blend][body]concat=n=2:v=1:a=0,format=yuv420p[v]").format(k=k, nk=n - k, n=n, x=x)
    maps = ["-map", "[v]"]
    if info["audio"]:
        fc += (";[0:a]aresample=44100,asplit=3[a1][a2][a3];"
               "[a1]atrim=0:{x:.4f},asetpts=PTS-STARTPTS[ah];"
               "[a2]atrim=start={dx:.4f}:end={d:.4f},asetpts=PTS-STARTPTS[at];"
               "[a3]atrim=start={x:.4f}:end={dx:.4f},asetpts=PTS-STARTPTS[ab];"
               "[at][ah]acrossfade=d={x:.4f}:c1=qsin:c2=qsin[ablend];"
               "[ablend][ab]concat=n=2:v=0:a=1[a]").format(x=x, dx=d - x, d=d)
        maps += ["-map", "[a]"]
    os.makedirs(os.path.join(bd, "video"), exist_ok=True)
    base = os.path.join(bd, "video", name)
    encode_pair(["-i", master, "-filter_complex", fc], maps, base)
    ff("-i", base + ".mp4", "-frames:v", "1", base + "_poster.png")
    out = vinfo(base + ".ogv")
    return (os.path.relpath(base + ".mp4", bd), [("video/%s.ogv" % name, it["target"])],
            {"video": "%dx%d, %.2f s at %g fps, audio %s, seamless loop (last %.2f s crossfaded into the start)"
                      % (out["w"], out["h"], out["duration"], fps, "yes" if out["audio"] else "no", x),
             "poster": os.path.relpath(base + "_poster.png", bd), "master": os.path.relpath(master, ROOT)})


def post_cutscene(it, src, bd):
    name = os.path.basename(it["target"]).replace(".ogv", "")
    master = abs_("assets/raw/video/%s.mp4" % name)
    if os.path.abspath(src) != master:
        copy(src, master)
    info = vinfo(master)
    os.makedirs(os.path.join(bd, "video"), exist_ok=True)
    base = os.path.join(bd, "video", name)
    ## a short fade in from and out to black, so a cut never starts or ends on a hard frame
    d = info["duration"]
    fc = "[0:v]fade=t=in:st=0:d=0.3,fade=t=out:st=%.3f:d=0.4,format=yuv420p[v]" % (d - 0.45)
    maps = ["-map", "[v]"]
    if info["audio"]:
        fc += ";[0:a]aresample=44100,afade=t=in:st=0:d=0.2,afade=t=out:st=%.3f:d=0.5[a]" % (d - 0.55)
        maps += ["-map", "[a]"]
    encode_pair(["-i", master, "-filter_complex", fc], maps, base)
    ff("-ss", "%.2f" % (d * 0.45), "-i", base + ".mp4", "-frames:v", "1", base + "_poster.png")
    out = vinfo(base + ".ogv")
    return (os.path.relpath(base + ".mp4", bd), [("video/%s.ogv" % name, it["target"])],
            {"video": "%dx%d, %.2f s at %g fps, audio %s (0.3 s fade in, 0.4 s fade out)"
                      % (out["w"], out["h"], out["duration"], out["fps"], "yes" if out["audio"] else "no"),
             "poster": os.path.relpath(base + "_poster.png", bd), "master": os.path.relpath(master, ROOT)})


def post_talk(it, src, bd):
    name = os.path.basename(it["target"]).replace(".webp", "")
    rel = os.path.relpath(os.path.join(bd, "portraits", name + ".webp"), ROOT)
    os.makedirs(os.path.join(bd, "portraits"), exist_ok=True)
    report = pack_anims.pack_loop(src, rel)
    meta = json.load(open(abs_(rel.replace(".webp", ".json"))))
    gif = os.path.join(bd, "portraits", name + "_anim.gif")
    gif_from_sheet(abs_(rel), meta, gif, bg="0x3a2c22", max_w=256)
    summ = [l for l in report.splitlines() if l.startswith("SUMMARY")]
    return (os.path.relpath(gif, bd),
            [("portraits/%s.webp" % name, it["target"]), ("portraits/%s.json" % name, it["target"].replace(".webp", ".json"))],
            {"grid": "%sx%s, %s frames of %sx%s at %s fps%s" % (meta["cols"], meta["rows"], meta["frames"], meta["fw"], meta["fh"],
                                                                meta.get("fps"), ", ping-pong" if meta.get("order") else ""),
             "check": summ[0] if summ else ""})


def lufs(path):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", path, "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[0-9.]+) LUFS", r.stderr)
    return float(m[-1]) if m else None


def post_music(it, src, bd):
    """Levelled to sit with the track it replaces (Ludo's remixes came back anywhere from -14
    to -27 LUFS): a plain gain to the target loudness, with a limiter for the peaks."""
    out = os.path.join(bd, "music", it["id"] + ".mp3")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    target = it["opts"].get("lufs")
    now = lufs(src)
    if target is not None and now is not None:
        ff("-i", src, "-af", "volume=%.2fdB,alimiter=limit=0.94:level=disabled" % (target - now),
           "-c:a", "libmp3lame", "-b:a", "192k", out)
    elif src.endswith(".mp3"):
        copy(src, out)
    else:
        ff("-i", src, "-c:a", "libmp3lame", "-b:a", "192k", out)
    d = vinfo_audio(out)
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {
        "duration_s": round(d, 1), "loudness": "%s LUFS (Ludo gave %s)" % (lufs(out) and round(lufs(out), 1), now and round(now, 1))}


def vinfo_audio(path):
    return float(probe(path).get("format", {}).get("duration") or 0)


def post_view(it, src, bd):
    k = it["opts"]["index"]
    base = os.path.splitext(src)[0]
    cand = [f for f in glob.glob(base + "_%d.*" % k)]
    if not cand:
        raise RuntimeError("no variant %d next to %s" % (k, src))
    out = os.path.join(bd, "views", os.path.basename(it["target"]))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ff("-i", cand[0], "-c:v", "libwebp", "-lossless", "1", out)
    return os.path.relpath(out, bd), [(os.path.relpath(out, bd), it["target"])], {}


def post_model(it, src, bd):
    name = os.path.basename(it["target"]).replace(".glb", "")
    d = os.path.join(bd, "models")
    os.makedirs(d, exist_ok=True)
    copy(src, os.path.join(d, name + ".glb"))
    snaps = sorted(glob.glob(os.path.splitext(src)[0] + "_snap*"))
    out = os.path.join(d, name + "_snaps.png")
    if len(snaps) >= 4:
        args = []
        for s in snaps[:4]:
            args += ["-i", s]
        ff(*args, "-filter_complex", "[0]scale=384:384:force_original_aspect_ratio=decrease,pad=384:384:(ow-iw)/2:(oh-ih)/2:color=0x505050[a];"
           "[1]scale=384:384:force_original_aspect_ratio=decrease,pad=384:384:(ow-iw)/2:(oh-ih)/2:color=0x505050[b];"
           "[2]scale=384:384:force_original_aspect_ratio=decrease,pad=384:384:(ow-iw)/2:(oh-ih)/2:color=0x505050[c];"
           "[3]scale=384:384:force_original_aspect_ratio=decrease,pad=384:384:(ow-iw)/2:(oh-ih)/2:color=0x505050[e];"
           "[a][b]hstack[t];[c][e]hstack[u];[t][u]vstack", "-frames:v", "1", out)
    elif snaps:
        ff("-i", snaps[0], "-frames:v", "1", out)
    ref = out_file(it["chain"][0])
    return (os.path.relpath(out, bd), [("models/%s.glb" % name, it["target"])],
            {"glb_bytes": os.path.getsize(src), "reference_image": os.path.relpath(ref, ROOT) if ref else ""})


POST = {"tex": post_tex, "cut": post_cut, "star": post_star, "sfx": post_sfx, "art": post_art, "sheet": post_sheet,
        "fx": post_fx, "loopvid": post_loopvid, "cutscene": post_cutscene, "talk": post_talk, "music": post_music,
        "view": post_view, "model": post_model}
KIND = {"sfx": "audio", "music": "audio", "loopvid": "video", "cutscene": "video"}


def state_path(batch):
    return os.path.join(batch_dir(batch), "v19_state.json")


def load_state(batch):
    p = state_path(batch)
    return json.load(open(p)) if os.path.exists(p) else {}


def save_state(batch, st):
    os.makedirs(batch_dir(batch), exist_ok=True)
    tmp = state_path(batch) + ".tmp"
    json.dump(st, open(tmp, "w"), indent=1)
    os.replace(tmp, state_path(batch))


def source_of(it):
    ## a hand-picked earlier take wins while the ledger is still at the version it was picked against
    pick = it["opts"].get("pick")
    if pick and int(ledger().get(it["chain"][-1], {}).get("v", 0)) == pick[0] and os.path.exists(abs_(pick[1])):
        return abs_(pick[1])
    if it["chain"]:
        f = out_file(it["chain"][-1])
        if f:
            return f
    fb = it["opts"].get("fallback")
    return abs_(fb) if fb and os.path.exists(abs_(fb)) else None


def post(it, to_game):
    src = source_of(it)
    if not src:
        return False
    bd = batch_dir(it["batch"])
    log("post %-24s <- %s" % (it["id"], os.path.relpath(src, ROOT)))
    fileu, pairs, meta = POST[it["post"]](it, src, bd)
    st = load_state(it["batch"])
    led = ledger()
    st[it["id"]] = {"file": fileu, "install": pairs, "meta": meta, "src": os.path.relpath(src, ROOT),
                    "versions": {c: led.get(c, {}).get("v") for c in it["chain"]}, "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    save_state(it["batch"], st)
    if to_game and (it["opts"].get("install_now", True)):
        for a, b in pairs:
            copy(os.path.join(bd, a), abs_(b))
            log("  installed", b)
    return True


# ---------------------------------------------------------------- batches
def credits_of(chain):
    led = ledger()
    return round(sum(float(led.get(c, {}).get("credits") or 0) for c in chain), 2)


def endpoints_of(chain):
    led, mb = ledger(), man_by()
    return [led.get(c, {}).get("endpoint") or mb.get(c, {}).get("kind") for c in chain]


def text_of(it):
    mb = man_by()
    parts = []
    for c in it["chain"]:
        a = mb.get(c, BY.get(c, {}))
        if a.get("prompt"):
            parts.append(a["prompt"])
        if a.get("lyrics"):
            parts.append("Lyrics:\n" + a["lyrics"])
    if it["opts"].get("note"):
        parts.append(it["opts"]["note"])
    return "\n\n".join(parts)


def prompt_id(it):
    """The manifest id whose prompt a reviewer's edited text replaces (the last one that has a prompt)."""
    mb = man_by()
    ids = [c for c in it["chain"] if mb.get(c, BY.get(c, {})).get("prompt")]
    return ids[-1] if ids else None


def actions(batch):
    return [
        {"id": "install", "kind": "install", "label": "Install accepted",
         "help": "Copy every accepted take into the game (sheets with their json, videos as .ogv), write rejected.json, "
                 "then run Godot's import so the game sees them.",
         "cmd": ["python3", SELF, "--install", "--batch-name", batch],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
        {"id": "regen", "kind": "regen", "label": "Redo rejected",
         "help": "Generate a new take of every rejected item with Ludo (spends credits; an edited text becomes the new "
                 "prompt). New takes land in this review folder only; install them after you accept them.",
         "cmd": ["python3", SELF, "--regen", "--batch-name", batch], "spends": True,
         "options": [{"flag": "--dry-run", "label": "Dry run (show the cost, spend nothing)", "type": "bool", "default": False},
                     {"flag": "--jobs", "label": "Jobs in flight", "type": "int", "min": 1, "max": 12, "default": 6}]},
    ]


CONTEXT = {
    "felt": "tiles the dice tray's cloth", "rail_wood": "tiles the tray's wooden rail", "brass": "tiles the tray's brass fittings",
    "plaque": "shows a volley total", "fortune_star": "you hold Fortune's favour (24-40 px)",
    "fortune_empty": "the empty favour slot (24-40 px)", "sfx_fortune": "you call on Fortune",
    "sfx_fortune_gained": "you bank a favour", "howto_fortune": "How to Play: the Fortune rule",
    "title_loop": "behind the title menu, looping", "victory_loop": "the victory screen, looping",
    "defeat_loop": "the defeat screen, looping", "cut_intro": "a new campaign begins", "cut_capital_taken": "you take a capital",
    "cut_capital_lost": "your capital falls", "cut_eliminated": "a rival is eliminated", "cut_victory": "you win the war",
    "cut_defeat": "you lose the war", "lament": "defeat", "besieged": "your capital is threatened",
    "endgame": "late-game battles", "lament_explore": "defeat",
}


def write_batch(batch):
    st = load_state(batch)
    items = []
    for it in ITEMS:
        if it["batch"] != batch:
            continue
        s = st.get(it["id"])
        kind = KIND.get(it["post"], "image")
        mb = man_by()
        m = {"manifest_ids": it["chain"], "endpoints": endpoints_of(it["chain"]), "credits": credits_of(it["chain"]),
             "versions": {c: int(mb.get(c, {}).get("v", 1)) for c in it["chain"]}}
        if it["id"] in CONTEXT:
            m["context"] = CONTEXT[it["id"]]
        elif it["id"].startswith("march_song"):
            m["context"] = "a sung march for the victory screen or credits: accept ONE take"
        entry = {"id": it["id"], "kind": kind, "group": it["group"], "label": it["label"], "text": text_of(it),
                 "target": it["target"], "meta": m}
        if s:
            entry["file"] = s["file"]
            m.update(s.get("meta", {}))
            m["install"] = s["install"]
            if s.get("meta", {}).get("poster"):
                entry["poster"] = s["meta"]["poster"]
        else:
            entry["file"] = "pending/%s" % it["id"]  ## not generated yet: shows as missing
        items.append(entry)
    d = batch_dir(batch)
    os.makedirs(d, exist_ok=True)
    doc = {"batch": batch, "title": BATCHES[batch], "actions": actions(batch), "items": items}
    tmp = os.path.join(d, "batch.json.tmp")
    json.dump(doc, open(tmp, "w"), indent=1, ensure_ascii=False)
    os.replace(tmp, os.path.join(d, "batch.json"))
    return len(items), sum(1 for x in items if not x["file"].startswith("pending/"))


def write_batches(only=None):
    for b in BATCHES:
        if only and b not in only:
            continue
        n, ready = write_batch(b)
        log("batch %-14s %d items, %d ready" % (b, n, ready))


# ---------------------------------------------------------------- verdicts, install, regen
def merged(batch):
    """Items with their review status (the review tool's own logic when it imports)."""
    try:
        sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
        import review as rv  # noqa
        return rv.merged_batch(batch)["items"]
    except Exception:
        d = batch_dir(batch)
        doc = json.load(open(os.path.join(d, "batch.json")))
        rj = os.path.join(d, "review.json")
        verdicts = json.load(open(rj)).get("items", {}) if os.path.exists(rj) else {}
        out = []
        for it in doc["items"]:
            v = verdicts.get(it["id"], {})
            p = os.path.join(d, it["file"])
            status = v.get("verdict", "pending")
            if os.path.exists(p) and status in ("accept", "reject") and v.get("file_mtime") is not None \
                    and os.path.getmtime(p) > float(v["file_mtime"]) + 1.0:
                status = "pending"
            if not os.path.exists(p) and status != "reject":
                status = "missing"
            x = dict(it)
            x.update(status=status, verdict=v.get("verdict", "pending"), note=v.get("note", ""), edited_text=v.get("text"))
            out.append(x)
        return out


def godot_import():
    if not os.path.exists(GODOT):
        log("Godot not found at %s: run it with --headless --path . --import" % GODOT)
        return
    subprocess.run([GODOT, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("imported into Godot")


def install(batch, dry):
    tag = "[dry-run] " if dry else ""
    d = batch_dir(batch)
    items = merged(batch)
    seen_target = {}
    copied = same = 0
    for it in items:
        if it.get("status") != "accept":
            continue
        tgt = it.get("target")
        if tgt in seen_target:
            print("  ! %s: %s is already taken by the accepted %s; skipped (accept one take per target)"
                  % (it["id"], tgt, seen_target[tgt]))
            continue
        seen_target[tgt] = it["id"]
        pairs = (it.get("meta") or {}).get("install") or [[it["file"], tgt]]
        for a, b in pairs:
            src, dst = os.path.join(d, a), abs_(b)
            if not os.path.exists(src):
                print("  ! %s: %s is missing" % (it["id"], a))
                continue
            if os.path.exists(dst) and open(src, "rb").read() == open(dst, "rb").read():
                same += 1
                print("  %s=  %s (unchanged)" % (tag, b))
                continue
            print("  %s+  %s (%s)" % (tag, b, "overwrite" if os.path.exists(dst) else "new"))
            if not dry:
                copy(src, dst)
            copied += 1
    rejected = [{"id": it["id"], "text": it.get("edited_text") or it.get("text") or "", "note": it.get("note") or "",
                 "meta": it.get("meta") or {}} for it in items if it.get("status") == "reject"]
    if not dry:
        tmp = os.path.join(d, "rejected.json.tmp")
        json.dump(rejected, open(tmp, "w"), indent=1, ensure_ascii=False)
        os.replace(tmp, os.path.join(d, "rejected.json"))
    counts = {}
    for it in items:
        counts[it.get("status")] = counts.get(it.get("status"), 0) + 1
    print("%s%s: %s %d files, %d unchanged; %s" % (tag, batch, "would copy" if dry else "copied", copied, same,
                                                  ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    if not dry and copied:
        godot_import()


def estimate(ids):
    """A rough credit estimate for regenerating these manifest ids."""
    mb = man_by()
    tot = 0.0
    for i in ids:
        a = mb.get(i, {})
        k = a.get("kind")
        dur = float(a.get("duration", 3))
        if k in ("image", "edit", "styled"):
            tot += 0.5 + (0.5 if a.get("cutout") else 0)
        elif k in ("pose", "rotate"):
            tot += 0.5 * a.get("n", 1)
        elif k in ("animate", "keyframes", "transfer"):
            tot += max(9.0, 3 * dur) if a.get("model") == "hydra" else max(4.0, 1.5 * dur)
        elif k == "sprite_edit":
            tot += 9.0
        elif k == "video":
            tot += 1.5 * dur
        elif k == "video_refs":
            tot += 2.5 * dur
        elif k == "upscale":
            tot += 1.6
        elif k == "model3d":
            tot += 3
        elif k in ("sfx", "ambiance"):
            tot += 2
        elif k in ("music", "audio_transform"):
            tot += 3
    return tot


def prep_smoke_start():
    """The musket smoke's first frame: its full-cloud still, shrunk to a 140 px puff at the left
    of an empty 1024x512 canvas."""
    src = out_file("v19_fxsrc_smoke_musket")
    ff("-i", src, "-filter_complex",
       "[0]format=rgba,crop=678:548:48:110,scale=140:-1:flags=lanczos[s];color=0x00000000:s=1024x512,format=rgba[bg];"
       "[bg][s]overlay=70:(512-h)/2:format=auto,format=rgba", "-frames:v", "1", abs_(RAW + "/fx/smoke_musket_start_pad.png"))


PREP = {"v19_fx_smoke_musket_grow": prep_smoke_start}


def run_ludo(ids, jobs):
    if not ids:
        return 0
    for i in ids:
        if i in PREP and not os.path.exists(abs_(BY[i]["from_file"])):
            PREP[i]()
    r = subprocess.run([sys.executable, os.path.join(HERE, "ludo.py"), "--jobs", str(jobs)] + ids)
    return r.returncode


def regen(batch, dry, jobs):
    items = [it for it in merged(batch) if it.get("status") == "reject"]
    if not items:
        print("%s: nothing rejected" % batch)
        return
    mine = {it["id"]: it for it in ITEMS if it["batch"] == batch}
    man = manifest()
    by = {a["id"]: a for a in man["assets"]}
    bump, redo = [], []
    for r in items:
        it = mine.get(r["id"])
        if not it:
            continue
        if not it["chain"]:
            print("  %s: no Ludo chain (a file from the survey); nothing to redo" % r["id"])
            continue
        ## a reviewer's edited text becomes the new prompt of the chain's prompted step
        pid = prompt_id(it)
        new_text = r.get("edited_text")
        if pid and new_text and new_text.strip() and new_text.strip() != text_of(it).strip():
            print("  %s: new prompt for %s" % (r["id"], pid))
            if not dry:
                by[pid]["prompt"] = new_text.strip()
        for c in it["chain"]:
            if c not in bump:
                bump.append(c)
        redo.append(it)
    cost = estimate(bump)
    print("%sredo %d items: %s (bumps %s), about %.1f credits" % ("[dry-run] " if dry else "", len(redo),
                                                                ", ".join(i["id"] for i in redo), " ".join(bump), cost))
    if dry:
        return
    for c in bump:
        by[c]["v"] = int(by[c].get("v", 1)) + 1
    json.dump(man, open(MAN, "w"), indent=1)
    ## keep the take being replaced
    st = load_state(batch)
    d = batch_dir(batch)
    for it in redo:
        s = st.get(it["id"])
        if not s:
            continue
        old = os.path.join(d, "old", "%s_%s" % (it["id"], time.strftime("%Y%m%d%H%M%S")))
        for rel in [s["file"]] + [a for a, b in s.get("install", [])]:
            p = os.path.join(d, rel)
            if os.path.exists(p):
                os.makedirs(old, exist_ok=True)
                shutil.copy2(p, os.path.join(old, os.path.basename(rel)))
    run_ludo(bump, jobs)
    for it in redo:
        try:
            post(it, to_game=False)
        except Exception as ex:
            print("  ! post %s failed: %s" % (it["id"], ex))
    write_batch(batch)


def ids_of(groups):
    return [x["id"] for x in E if x["group"] in groups]


def make(groups, jobs, no_install):
    write_manifest()
    ids = [x["id"] for x in E if x["group"] in groups and not x.get("manual")]
    log("make %s: %d generations" % (" ".join(groups), len(ids)))
    run_ludo(ids, jobs)
    do_post(groups, not no_install)


def do_post(groups, to_game):
    batches = set()
    for it in ITEMS:
        gs = {BY[c]["group"] for c in it["chain"] if c in BY}
        if not gs & set(groups):
            continue
        try:
            if post(it, to_game):
                batches.add(it["batch"])
        except Exception as ex:
            log("  ! post %s failed: %s" % (it["id"], str(ex)[:600]))
    write_batches(batches or None)


def main(argv):
    def opt(name, default=None):
        if name in argv:
            return argv[argv.index(name) + 1]
        return default
    dry = "--dry-run" in argv
    jobs = int(opt("--jobs", 6))
    batch = opt("--batch-name")
    groups = [a for a in argv[1:] if re.match(r"^G\d+p?$", a)]
    if "--install" in argv:
        for b in ([batch] if batch else list(BATCHES)):
            install(b, dry)
        return
    if "--regen" in argv:
        write_manifest()
        for b in ([batch] if batch else list(BATCHES)):
            regen(b, dry, jobs)
        return
    if "--ids" in argv:
        print(" ".join(ids_of(groups)))
        return
    if "--make" in argv:
        make(groups, jobs, "--no-install" in argv)
        return
    if "--post" in argv:
        do_post(groups, "--no-install" not in argv)
        return
    if "--batch" in argv:
        write_batches([batch] if batch else None)
        return
    n = write_manifest()
    log("manifest: %d new v1.9 entries" % n)
    write_batches()


if __name__ == "__main__":
    main(sys.argv)
