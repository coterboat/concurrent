#!/usr/bin/env python3
"""v2.4 faces: reactions that move.

Until v2.3 a face reacted by swapping to a generated still (v1.2: "laughing triumphantly with chin
raised, eyes blazing with victory") and bumping it with a tween. v2.4 animates the reaction instead,
the way the talk loops were made (v1.9 G6): Hydra animates the portrait itself, from its own pose
and, for every reaction but the fall, back to it, so the game cuts from the idle loop into the
reaction and out again without a jump. Every reaction rolls two takes into the review batch
review/v24_faces. Only an accepted take is installed (assets/portraits/loops/<who>_<clip>.webp +
.json); until then the game shows the old still (game/ui/leader_face.gd).

    python tools/ludo/v24_content.py --cost [--only hask_win,quill_taunt] [--takes 1]
    python tools/ludo/v24_content.py --make [--only hask_win,quill_taunt] [--takes 1] [--jobs 6]
    python tools/ludo/v24_content.py --post                    # pack every take made into the batch
    python tools/ludo/v24_content.py --reprompt hask_win ...   # before a review: the script's prompt, a new version
    python tools/ludo/v24_content.py --install --batch-name v24_faces [--dry-run]
    python tools/ludo/v24_content.py --regen --batch-name v24_faces [--dry-run] [--jobs N] [--no-notes]

The clips (game/ui/leader_face.gd CLIPS picks one by mood, and by line for the taunt):
  win    a win, a capital taken, cards cashed, a greeting (the moods win and happy)
  lose   a loss, a retreat, a capital lost (lose and alarm)
  taunt  the taunt line, said to you
  dead   knocked out: it ends bowed, and the game holds that last frame
The advisor's win is his good news, his lose a warning, his dead the war lost (grave, then back to
himself). The faces a player can wear have win, lose and dead, and say nothing.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MAN = os.path.join(HERE, "manifest.json")
LEDGER = os.path.join(ROOT, "assets", "ludo_ledger.json")
RAW = "assets/raw/v24/faces"
BATCH = "v24_faces"
TITLE = "v2.4 reactions: faces that win, lose, taunt and fall"
SELF = "tools/ludo/v24_content.py"
GAME = "assets/portraits/loops"
PX = 256  ## the game's portrait loops are 256 px wide
TAKES = 2
sys.path.insert(0, HERE)
import notes  # noqa: E402  (a review note steers the redo)

GODOT = os.environ.get("GODOT", "")
for _g in (os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot"), "/Applications/Godot.app/Contents/MacOS/Godot",
           os.path.expanduser("~/Documents/godot/Godot_v4.7.1-stable_win64_console.exe")):
    if not GODOT and os.path.exists(_g):
        GODOT = _g

# ---------------------------------------------------------------- the cast and their reactions
## who: (the person as the prompt names them, his/her, headwear or "", what the hands keep or "")
CAST = {
    "advisor": ("old field marshal with white mutton-chop whiskers and round spectacles", "his", "", ""),
    "varek": ("grizzled old field marshal with an eyepatch and a grey moustache", "his", "bicorne hat", ""),
    "ysolde": ("stern noblewoman general", "her", "plumed tricorne hat", ""),
    "quill": ("portly trading-company governor in a powdered wig and round spectacles", "his", "", ""),
    "oren": ("young blond hussar captain", "his", "", ""),
    "hask": ("huge black-bearded privateer commodore", "his", "tricorne hat", ""),
    "imre": ("calm woman admiral with short dark hair", "her", "", "The brass spyglass stays tucked under her arm."),
}
## the faces a player can wear (game/ui/setup_screen.gd FACES): silent, so their lips stay closed
PLAYERS = {
    "you_ironduke": ("silver-haired commander in a scarlet coat with a blue sash", "his", "", ""),
    "you_corsair": ("weathered corsair captain with a short grey beard", "his", "", ""),
    "you_lioness": ("red-haired woman officer", "her", "slouch hat", ""),
    "you_scholar": ("dark-haired officer in round spectacles", "his", "", "The rolled map stays in his hand."),
    "you_rajah": ("rajah with a grey moustache", "his", "jewelled turban", ""),
    "you_grenadier": ("grey-bearded grenadier", "his", "tall bearskin cap", ""),
}
BACK = "then settles back exactly into the starting pose, looking at the viewer."

## who -> clip -> the motion. A motion ending in "," is followed by BACK (the clip ends on the
## portrait it started from); one ending in "." is a fall that stays where it ends.
MOTIONS = {
    "advisor": {
        "win": "beams with pride as a warm, satisfied smile spreads under his white whiskers, giving a slow approving nod as he says a few words,",
        "lose": "raises his eyebrows high above his spectacles, his eyes wide with alarm, and leans forward as he calls out an urgent warning,",
        "dead": "lets his smile fade into a grave, sorrowful look and slowly bows his head with his eyes closed, lifts it again with quiet dignity,",
    },
    "varek": {
        "win": "gives a slow, grim nod of satisfaction, his one eye narrowing and the corner of his grey moustache lifting in a thin, hard smile as he says two curt words,",
        "lose": "sets his jaw hard, nostrils flaring and brow knitting, his one eye glaring coldly at the viewer as he mutters a few grim words through his moustache,",
        "taunt": "leans in a little toward the viewer with a cold, thin smile under his grey moustache, his one eye fixed on the viewer as he says a short sentence slowly and menacingly,",
        "dead": "closes his one eye and slowly bows his head, his shoulders sinking with exhaustion, and stays still with his head bowed to the end.",
    },
    "ysolde": {
        "win": "lifts her chin and lowers her eyelids as a cold, thin smile of satisfaction spreads across her lips, and she says a single word,",
        "lose": "narrows her eyes to slits and presses her lips into a hard line, nostrils flaring with icy fury, as she hisses a few words,",
        "taunt": "tilts her head slowly with a cruel half-smile and one eyebrow raised, her eyes fixed on the viewer as she says a short sentence softly and menacingly,",
        "dead": "lowers her gaze, closes her eyes and slowly bows her head, her jaw still set with pride, and stays still with her head bowed to the end.",
    },
    "quill": {
        "win": "breaks into a delighted, greedy grin and chuckles, his round cheeks bunching up and his eyes crinkling behind his spectacles as his head bobs with laughter,",
        "lose": "winces as if he has just lost a fortune, pursing his lips and peering sourly over his spectacles, shaking his head slowly as he mutters a few words,",
        "taunt": "lowers his chin and peers over the top of his round spectacles at the viewer with a sly, smug smile, saying a short sentence and giving a slow, knowing nod,",
        "dead": "lets out a long sigh as his face falls, his cheeks sagging and his eyes closing, and his head droops forward and stays drooping to the end.",
    },
    "oren": {
        "win": "whoops with a big boyish laugh, tossing his head back so his blond hair bounces, and flashes a dazzling grin at the viewer,",
        "lose": "drops his jaw in disbelief with his eyebrows shooting up and scowls in an indignant pout as he protests a few words,",
        "taunt": "gives the viewer a cheeky wink and a cocky grin and says a short sentence with a laugh,",
        "dead": "lets his grin fade and sighs, slowly bowing his head so his blond hair falls over his eyes, and stays still with his head bowed to the end.",
    },
    "hask": {
        "win": "throws his head back in a huge, booming belly laugh, his black beard shaking and his eyes squeezed shut with glee, and grins at the viewer,",
        "lose": "snarls with fury, teeth bared in his black beard and brows crashing down, growling a few words and shaking his head,",
        "taunt": "leans toward the viewer with a wolfish grin and booms a short sentence, laughing so his black beard shakes,",
        "dead": "lets out a heavy sigh, his big shoulders sagging, and his head drops forward with his eyes closed, and he stays still with his head down to the end.",
    },
    "imre": {
        "win": "gives a small, knowing smile and raises one eyebrow, with a short satisfied nod as she says one quiet word,",
        "lose": "narrows her eyes thoughtfully and presses her lips thin, tilting her head slightly as she says a few cool words,",
        "taunt": "gives the viewer a slow, knowing smile, one eyebrow raised and her eyes fixed on the viewer as she says a short, calm sentence,",
        "dead": "gives a small rueful smile, closes her eyes and bows her head slightly, and stays still with her head bowed and her eyes closed to the end.",
    },
}
PLAYER_MOTIONS = {
    "win": "smiles with proud confidence and gives one firm nod, chin lifted and eyes bright,",
    "lose": "scowls grimly with lips pressed tight, jaw clenched and brows lowered, and lets out a sharp breath through the nose,",
    "dead": "closes {pos} eyes and slowly bows {pos} head in exhaustion, shoulders sinking, and stays still with {pos} head bowed to the end.",
}

## the still each clip replaces in the game (the v1.2 faces)
STILL = {"win": "triumphant", "lose": "angry", "taunt": "triumphant", "dead": "defeated"}
ADVISOR_STILL = {"win": "pleased", "lose": "alarmed", "dead": "alarmed"}
NAMES = {"advisor": "Advisor", "you_ironduke": "The Iron Duke (you)", "you_corsair": "The Corsair (you)",
         "you_lioness": "The Lioness (you)", "you_scholar": "The Scholar (you)", "you_rajah": "The Rajah (you)",
         "you_grenadier": "The Grenadier (you)"}
## what the review table says each clip is for (meta.context)
CONTEXT = {
    "win": "plays when they win a battle, take a capital, claim a land or cash in cards, and when they greet you (with the line)",
    "lose": "plays when they lose a battle, fall back or lose their capital (with the line)",
    "taunt": "plays when they taunt you across a border (with the taunt line)",
    "dead": "plays once on the 'has fallen' card; the last frame stays, greyed, in the roster",
}
ADVISOR_CONTEXT = {
    "win": "the advisor's good news: a capture, Fortune on our side, reserves, a capital taken (with his line)",
    "lose": "the advisor's warnings: a land lost, a bad roll, an army cut off, a capital lost (with his line)",
    "dead": "you have lost the war (with 'We are beaten, Commander...'); he comes back to himself after",
}
PLAYER_CONTEXT = {
    "win": "your own face when you win a battle (no voice)",
    "lose": "your own face when you lose a battle (no voice)",
    "dead": "your own face, knocked out (hot seat): the last frame stays, greyed",
}
CLIP_LABEL = {"win": "wins", "lose": "loses", "taunt": "taunts you", "dead": "falls (holds the last frame)"}
ADVISOR_LABEL = {"win": "good news", "lose": "a warning", "dead": "the war is lost"}


def person(who):
    return CAST.get(who) or PLAYERS[who]


## Loops remade beside the reactions: the Lioness's portrait was re-rolled (portrait_you_lioness v2,
## the red coat) after her idle loop was made from the first one (a khaki greatcoat), so she breathed
## as someone else, 24 off her portrait where every other face is 3-7, and a reaction cut from her
## portrait would jump. Remade the way the other faces' idles were (v1.2 LOOPS, forge, 2 s).
LOOPS = {("you_lioness", "idle"): "breathes slowly and blinks, subtle idle motion, head nearly still"}
LOOP_CONTEXT = {("you_lioness", "idle"): "her face at rest everywhere: the setup screen, the roster, the battles. Remade from "
                                         "her current portrait (today she breathes in her old khaki coat). Takes 1-2 on forge "
                                         "(as every other face's idle), 3-4 on Hydra with her lips closed"}
## A loop can draw two more takes from a second model: the forge takes of the Lioness's idle came back
## with a white smudge beside her face in one frame and a mouth that opens as if talking, so two Hydra
## takes (as the reactions, which came back clean) sit beside them as takes 3 and 4.
EXTRA = {("you_lioness", "idle"): "The red-haired woman officer breathes slowly and blinks once, her lips gently closed "
                                  "and her head nearly still, then settles back exactly into the starting pose, looking at "
                                  "the viewer. The whole head and the slouch hat stay inside the frame."}


def is_loop(who, clip):
    return (who, clip) in LOOPS


def motion_of(who, clip):
    return (MOTIONS[who] if who in MOTIONS else PLAYER_MOTIONS)[clip].format(pos=person(who)[1])


def returns(who, clip):
    """Whether the clip ends on the portrait it began from (all but a commander's fall)."""
    return is_loop(who, clip) or motion_of(who, clip).endswith(",")


def prompt_of(who, clip):
    if is_loop(who, clip):
        return LOOPS[(who, clip)]
    desc, pos, hat, keep = person(who)
    motion = motion_of(who, clip)
    text = "The %s %s" % (desc, motion)
    if returns(who, clip):
        text += " " + BACK
    text += " The whole head%s inside the frame." % (" and the %s stay" % hat if hat else " stays")
    if keep:
        text += " " + keep
    return text


def clips_of(who):
    return list((MOTIONS[who] if who in MOTIONS else PLAYER_MOTIONS).keys())


ITEMS = [(who, clip) for who in list(CAST) + list(PLAYERS) for clip in clips_of(who)] + list(LOOPS)


def name_of(who, clip):
    return "%s_%s" % (who, clip)


def aid_of(who, clip):
    return ("v24_loop_%s_%s" if is_loop(who, clip) else "v24_react_%s_%s") % (who, clip)


def entry(who, clip):
    """The manifest entry: the talk loops' settings (v19 G6), so a reaction's cells match the
    portrait, the idle loop and the talk loop exactly. A remade idle loop: the v1.2 idles' settings."""
    if is_loop(who, clip):
        return {"id": aid_of(who, clip), "group": "v24f", "kind": "animate", "from_file": "assets/portraits/%s.png" % who,
                "fit": True, "model": "forge", "image_type": "portrait", "duration": 2, "frames": 16, "frame_size": -9,
                "loop": False, "crop": False, "final_same": True, "takes": TAKES, "out": "%s/%s" % (RAW, name_of(who, clip)),
                "prompt": prompt_of(who, clip)}
    e = {"id": aid_of(who, clip), "group": "v24f", "kind": "animate", "from_file": "assets/portraits/%s.png" % who,
         "fit": True, "model": "hydra", "image_type": "portrait", "duration": 3, "frames": 36, "frame_size": -9,
         "loop": False, "crop": False, "margin_ratio_mode": "manual", "margin_ratio_horizontal": 0.02,
         "margin_ratio_vertical": 0.02, "takes": TAKES, "out": "%s/%s" % (RAW, name_of(who, clip)),
         "prompt": prompt_of(who, clip)}
    if returns(who, clip):
        e["final_same"] = True  ## it ends on the portrait it began from
    return e


def extra_entry(who, clip):
    """A loop's second model: Hydra, the reactions' settings, its own prompt."""
    return {"id": aid_of(who, clip) + "_hydra", "group": "v24f", "kind": "animate",
            "from_file": "assets/portraits/%s.png" % who, "fit": True, "model": "hydra", "image_type": "portrait",
            "duration": 3, "frames": 36, "frame_size": -9, "loop": False, "crop": False, "final_same": True,
            "margin_ratio_mode": "manual", "margin_ratio_horizontal": 0.02, "margin_ratio_vertical": 0.02,
            "takes": TAKES, "out": "%s/%s_hydra" % (RAW, name_of(who, clip)), "prompt": EXTRA[(who, clip)]}


def entries_of(who, clip):
    return [entry(who, clip)] + ([extra_entry(who, clip)] if (who, clip) in EXTRA else [])


def sources(who, clip):
    """An item's takes in review order: [(its take number, manifest entry, that entry's take)]."""
    out = []
    for e in entries_of(who, clip):
        for k in range(1, TAKES + 1):
            out.append((len(out) + 1, e, k))
    return out


def ledger_id(aid, k):
    return aid if k == 1 else "%s~t%d" % (aid, k)


# ---------------------------------------------------------------- helpers
def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def abs_(r):
    return r if os.path.isabs(r) else os.path.join(ROOT, r)


def load_json(p, default=None):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(p, obj, **kw):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, **kw) + ("\n" if kw.get("indent") else ""))
    os.replace(tmp, p)


def manifest():
    return load_json(MAN)


def ledger():
    return load_json(LEDGER, {})


def write_manifest():
    """Add the reactions that are missing. One already there keeps its version and prompt (the
    review loop owns them from then on), unless it was never made: then the script's prompt wins."""
    man = manifest()
    led = ledger()
    by = {a["id"]: a for a in man["assets"]}
    changed = 0
    for who, clip in ITEMS:
        for e in entries_of(who, clip):
            old = by.get(e["id"])
            if old is None:
                man["assets"].append(e)
                changed += 1
            elif e["id"] not in led and old.get("prompt") != e["prompt"]:
                old["prompt"] = e["prompt"]
                changed += 1
    if changed:
        save_json(MAN, man, indent=1)
    return changed


def reprompt(names):
    """Before a review (dev): give these reactions the script's prompt again, as a new version."""
    man = manifest()
    by = {a["id"]: a for a in man["assets"]}
    for who, clip in ITEMS:
        if name_of(who, clip) not in names:
            continue
        a = by.get(aid_of(who, clip))
        if a is None:
            continue
        a["prompt"] = prompt_of(who, clip)
        a["v"] = int(a.get("v", 1)) + 1
        log("reprompt %s v%d: %s" % (name_of(who, clip), a["v"], a["prompt"]))
    save_json(MAN, man, indent=1)


def pick_items(only):
    want = [x.strip() for x in (only or "").split(",") if x.strip()]
    out = [(w, c) for w, c in ITEMS if not want or name_of(w, c) in want or w in want or c in want]
    missing = [x for x in want if not any(x in (name_of(w, c), w, c) for w, c in ITEMS)]
    if missing:
        sys.exit("no such reaction: %s" % ", ".join(missing))
    return out


def raw_of(e, k):
    """The raw sheet of a manifest entry's take k (1, 2, ...): ludo.py writes take k > 1 into .takes/."""
    out = e["out"]
    base = out if k == 1 else "%s/.takes/%s.t%d" % (os.path.dirname(out), os.path.basename(out), k)
    return abs_(base + ".webp"), abs_(base + ".json")


def review_of(who, clip, k):
    """The review stem of take k, relative to the batch folder: its preview is <stem>.webp (animated)
    and its sheet <stem>.sheet.webp + .sheet.json (a name the review table doesn't take for a take)."""
    return ("faces/%s" % name_of(who, clip)) if k == 1 else ("faces/.takes/%s.t%d" % (name_of(who, clip), k))


PREVIEW = ".webp"
SHEET = ".sheet"


def batch_dir():
    return os.path.join(ROOT, "review", BATCH)


# ---------------------------------------------------------------- packing and previews
def sheet_tool(*args):
    if not GODOT:
        raise RuntimeError("Godot not found: set GODOT=/path/to/godot")
    out = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "tools/sheet_tool.gd", "--"] + [str(a) for a in args],
                         capture_output=True, text=True)
    return out.stdout


def frames_of(sheet_path, meta):
    from PIL import Image
    im = Image.open(sheet_path).convert("RGBA")
    fw, fh, cols, n = int(meta["fw"]), int(meta["fh"]), int(meta["cols"]), int(meta["frames"])
    return [im.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)) for i in range(n)]


def likeness(frame, still_path):
    """How far a frame is from the portrait it should start (or end) on: the mean difference of the
    colour, 0-255. The portrait itself, re-rendered, comes out 5-15 (the idle and talk loops already
    meet at 5-18, behind the face's 0.2 s crossfade); well past that, the cut shows."""
    from PIL import Image, ImageChops, ImageStat
    s = Image.open(abs_(still_path)).convert("RGBA").resize(frame.size, Image.LANCZOS)
    a = Image.new("RGB", frame.size, (60, 45, 30))
    b = a.copy()
    a.paste(frame, (0, 0), frame)
    b.paste(s, (0, 0), s)
    return round(sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3.0, 1)


_RING = {}


def _ring_parts(size):
    """The backdrop, the circle mask and the ring of a face `size` px across, made once."""
    if size in _RING:
        return _RING[size]
    from PIL import Image, ImageDraw
    inner = int(size * 0.72)
    bg = Image.new("RGBA", (inner, inner))
    px = bg.load()
    c = inner / 2.0
    for y in range(inner):
        for x in range(inner):
            d = min(1.0, (((x - c) ** 2 + (y - inner * 0.42) ** 2) ** 0.5) / (inner * 0.75))
            px[x, y] = (int(96 - 72 * d), int(70 - 52 * d), int(38 - 28 * d), 255)
    mask = Image.new("L", (inner * 4, inner * 4), 0)
    r = inner * 4 * 0.4625
    ImageDraw.Draw(mask).ellipse((inner * 2 - r, inner * 2 - r, inner * 2 + r, inner * 2 + r), fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    ring = Image.open(abs_("assets/hud/hud_ring.png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    _RING[size] = (inner, bg, mask, ring)
    return _RING[size]


def ring_view(frame, size=300):
    """A frame as the game shows it: the lamp-lit backdrop, the face cover-scaled into the inner
    72% and masked to a circle, the gilded ring over it (game/ui/leader_face.gd)."""
    from PIL import Image
    inner, bg0, mask, ring = _ring_parts(size)
    bg = bg0.copy()
    sc = max(inner / float(frame.width), inner / float(frame.height))
    f = frame.resize((max(1, int(round(frame.width * sc))), max(1, int(round(frame.height * sc)))), Image.LANCZOS)
    bg.paste(f, ((inner - f.width) // 2, (inner - f.height) // 2), f)
    out = Image.new("RGBA", (size, size), (46, 36, 28, 255))
    out.paste(bg, ((size - inner) // 2, (size - inner) // 2), mask)
    out.alpha_composite(ring)
    return out.convert("RGB")


def make_preview(frames, fps, out, hold_end, hold_start=600):
    """The review preview, an animated WebP of the face in its ring: the first frame held a moment,
    the clip at its rate, the last frame held (full colour, a fifth the size of a GIF)."""
    views = [ring_view(f) for f in frames]
    ms = int(round(1000.0 / fps))
    durs = [hold_start] + [ms] * (len(views) - 2) + [hold_end]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    views[0].save(out, "WEBP", save_all=True, append_images=views[1:], duration=durs, loop=0, quality=82, method=4)


def pack(who, clip, k, raw, raw_json):
    """One take: the raw sheet -> the game's sheet (256 px cells, the duplicate last frame of a clip
    that ends where it began dropped, `fps` and `once`; a fall also `hold`), its review preview, and
    the checks. A remade idle loop packs the way the others were (pack_anims.pack_loop)."""
    if not (os.path.exists(raw) and os.path.exists(raw_json)):
        return None
    m = load_json(raw_json)
    cols, rows, n = int(m["cols"]), int(m["rows"]), int(m["frames"])
    stem = review_of(who, clip, k)
    out = os.path.join(batch_dir(), stem + SHEET + ".webp")
    out_json = os.path.join(batch_dir(), stem + SHEET + ".json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    back = returns(who, clip)
    if os.path.exists(out_json):
        os.remove(out_json)
    if is_loop(who, clip):
        import pack_anims
        pack_anims.GODOT = GODOT
        report = pack_anims.pack_loop(rel(raw), rel(out))
    else:
        report = sheet_tool("check", rel(raw), cols, rows, n)
        sheet_tool("shrink", rel(raw), cols, rows, PX, rel(out), n, *(["drop_last"] if back else []))
    meta = load_json(out_json)
    if not meta:
        raise RuntimeError("the sheet tool wrote no %s" % rel(out_json))
    if not is_loop(who, clip):
        meta["fps"] = round(n / float(m.get("duration") or 3.0), 3)
        meta["once"] = True
        if not back:
            meta["hold"] = True  ## a fall: the face stays on its last frame
        save_json(out_json, meta)
    fr = frames_of(out, meta)
    still = "assets/portraits/%s.png" % who
    start, end = likeness(fr[0], still), likeness(fr[-1], still)
    preview = os.path.join(batch_dir(), stem + PREVIEW)
    if is_loop(who, clip):
        ## a loop as the game plays it, in its order, three times round
        seq = [fr[int(i)] for i in (meta.get("order") or range(len(fr)))] * 3
        make_preview(seq, float(meta.get("fps") or 8.0), preview, int(1000.0 / float(meta.get("fps") or 8.0)),
                     int(1000.0 / float(meta.get("fps") or 8.0)))
    else:
        make_preview(fr, meta["fps"], preview, 900 if back else 2000)
    ## (a bust always runs off its frame, so the check's edge list says nothing here: its steps do)
    summ = [l.split("  edge_frames")[0] for l in report.splitlines() if l.startswith("SUMMARY")]
    step = re.search(r"max_step ([0-9.]+)", summ[0]) if summ else None
    kind = ("loops%s" % (", back and forth" if meta.get("order") else "")) if is_loop(who, clip) else \
        "plays once" + (", holds its last frame" if not back else "")
    return {"grid": "%sx%s, %s frames of %sx%s at %s fps, %s" % (meta["cols"], meta["rows"], meta["frames"], meta["fw"],
                                                                   meta["fh"], meta.get("fps", 8), kind),
            "likeness": {"start": start, "end": end}, "max_step": float(step.group(1)) if step else None,
            "check": summ[0] if summ else ""}


# ---------------------------------------------------------------- the batch
def state_path():
    return os.path.join(batch_dir(), "v24_state.json")


def post(only=None):
    st = load_json(state_path(), {})
    led = ledger()
    by = {a["id"]: a for a in manifest()["assets"]}
    for who, clip in pick_items(only):
        for k, e, kk in sources(who, clip):
            lid = ledger_id(e["id"], kk)
            key = "%s#%d" % (name_of(who, clip), k)
            if lid not in led:
                continue
            ver = int(led[lid].get("v", 1))
            have = st.get(key)
            if have and have.get("v") == ver and os.path.exists(os.path.join(batch_dir(), review_of(who, clip, k) + PREVIEW)):
                continue
            try:
                got = pack(who, clip, k, *raw_of(by.get(e["id"], e), kk))
            except Exception as ex:
                log("  ! pack %s take %d failed: %s" % (name_of(who, clip), k, str(ex)[:300]))
                continue
            if got:
                got["v"] = ver
                st[key] = got
                log("packed %-22s take %d  %s" % (name_of(who, clip), k, chip(who, clip, e, got)))
    save_json(state_path(), st, indent=1)
    write_batch()


def chip(who, clip, e, s):
    """A take's few words in the table (it shows 40 characters): how far its first and last frames are
    from the portrait (5-15 is the portrait itself), and the model when an item has two."""
    lk = s["likeness"]
    words = "from portrait: %.1f in, %s" % (lk["start"], "%.1f out" % lk["end"] if returns(who, clip) else "ends down")
    return ("%s · %s" % (e["model"].capitalize(), words)) if e["id"] != aid_of(who, clip) else words


def actions():
    return [
        {"id": "install", "kind": "install", "label": "Install accepted",
         "help": "Copy the take you kept of each accepted reaction into the game (assets/portraits/loops, the sheet and its "
                 "json), write rejected.json, then run Godot's import. The game plays an installed reaction instead of "
                 "the old still.",
         "cmd": ["python3", SELF, "--install", "--batch-name", BATCH],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False}]},
        {"id": "regen", "kind": "regen", "label": "Redo rejected",
         "help": "Roll two new takes of every rejected reaction with Ludo (about 18 credits each). An edited text becomes "
                 "the new prompt; otherwise the note rewrites it. The rejected take stays beside the new ones.",
         "cmd": ["python3", SELF, "--regen", "--batch-name", BATCH], "spends": True,
         "options": [{"flag": "--dry-run", "label": "Dry run (show the cost, spend nothing)", "type": "bool", "default": False},
                     {"flag": "--jobs", "label": "Jobs in flight", "type": "int", "min": 1, "max": 12, "default": 6},
                     {"flag": "--no-notes", "label": "Ignore the notes", "type": "bool", "default": False,
                      "help": "A plain re-roll. Otherwise each note rewrites its prompt (Claude when installed) unless you edited it"}]},
    ]


def label_of(who, clip):
    if is_loop(who, clip):
        return "%s at rest (her breathing, remade from today's portrait)" % NAMES.get(who, who.capitalize())
    if who == "advisor":
        return "Advisor: " + ADVISOR_LABEL[clip]
    return "%s %s" % (NAMES.get(who, who.capitalize()), CLIP_LABEL[clip])


def write_batch():
    st = load_json(state_path(), {})
    by = {a["id"]: a for a in manifest()["assets"]}
    led = ledger()
    items = []
    for who, clip in ITEMS:
        name = name_of(who, clip)
        aid = aid_of(who, clip)
        a = by.get(aid, entry(who, clip))
        s1 = st.get(name + "#1")
        if is_loop(who, clip):
            ctx, replaces = LOOP_CONTEXT[(who, clip)], "%s/%s.webp" % (GAME, name)
        else:
            ctx = (ADVISOR_CONTEXT if who == "advisor" else PLAYER_CONTEXT if who in PLAYERS else CONTEXT)[clip]
            replaces = "assets/portraits/%s_%s.png" % (who, (ADVISOR_STILL if who == "advisor" else STILL)[clip])
        meta = {"manifest_ids": [e["id"] for e in entries_of(who, clip)], "endpoints": ["/assets/sprite/animate"],
                "versions": {e["id"]: int(by.get(e["id"], e).get("v", 1)) for e in entries_of(who, clip)},
                "credits": round(sum(float(led.get(ledger_id(e["id"], kk), {}).get("credits") or 0)
                                     for k, e, kk in sources(who, clip)), 2),
                "context": ctx, "replaces": replaces}
        info = {}
        for k, e, kk in sources(who, clip):
            s = st.get("%s#%d" % (name, k))
            if s:
                info[review_of(who, clip, k) + PREVIEW] = chip(who, clip, e, s)
        if info:
            meta["take_info"] = info
        if s1:
            meta.update(grid=s1["grid"], check=s1["check"])
        items.append({"id": name, "kind": "image", "group": NAMES.get(who, who.capitalize()), "label": label_of(who, clip),
                      "text": a.get("prompt", ""), "file": review_of(who, clip, 1) + PREVIEW if s1 else "pending/" + name,
                      "target": "%s/%s.webp" % (GAME, name), "meta": meta})
    doc = {"batch": BATCH, "title": TITLE, "actions": actions(), "items": items}
    save_json(os.path.join(batch_dir(), "batch.json"), doc, indent=1, ensure_ascii=False)
    ready = sum(1 for x in items if not x["file"].startswith("pending/"))
    log("batch %s: %d reactions, %d ready" % (BATCH, len(items), ready))


# ---------------------------------------------------------------- verdicts, install, redo
def merged():
    sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
    import review as rv  # noqa: E402
    return rv.merged_batch(BATCH)["items"]


def godot_import():
    if not GODOT:
        log("Godot not found: run it with --headless --path . --import so the game sees the new reactions")
        return
    if not os.path.isdir(os.path.join(ROOT, ".godot")):
        ## a checkout Godot has never opened: a first import here rewrites every .import file under 4.7.1
        log("no .godot here: open the project in Godot (or copy an import cache in) so the game sees the new reactions")
        return
    subprocess.run([GODOT, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("imported into Godot")


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".tmp"
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def install(dry):
    """Every accepted reaction's kept take (the review table's pick) -> the game: its sheet and json."""
    tag = "[dry-run] " if dry else ""
    d = batch_dir()
    items = merged()
    copied = same = 0
    for it in items:
        if it.get("status") != "accept":
            continue
        src = it.get("src") or it["file"]
        stem = os.path.splitext(src)[0]
        for ext in (".webp", ".json"):
            a, b = os.path.join(d, stem + SHEET + ext), abs_(it["target"][: -len(".webp")] + ext)
            if not os.path.exists(a):
                print("  ! %s: %s is missing" % (it["id"], stem + SHEET + ext))
                continue
            if os.path.exists(b) and open(a, "rb").read() == open(b, "rb").read():
                same += 1
                continue
            print("  %s+  %s (%s, from %s)" % (tag, rel(b), "overwrite" if os.path.exists(b) else "new", stem + SHEET + ext))
            if not dry:
                copy(a, b)
            copied += 1
    rejected = [{"id": it["id"], "text": it.get("edited_text") or it.get("text") or "", "note": it.get("note") or ""}
                for it in items if it.get("status") == "reject"]
    if not dry:
        save_json(os.path.join(d, "rejected.json"), rejected, indent=1, ensure_ascii=False)
    counts = {}
    for it in items:
        counts[it.get("status")] = counts.get(it.get("status"), 0) + 1
    print("%s%s: %s %d files, %d unchanged; %s" % (tag, BATCH, "would copy" if dry else "copied", copied, same,
                                                  ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    if not dry and copied:
        godot_import()


def cost_of(items, takes):
    ## Hydra, 3 s: 3 credits a second, 9 at least; a forge idle, 2 s: 1.5 a second, 3
    return sum((3.0 if e["model"] == "forge" else 9.0) for w, c in items for e in entries_of(w, c)) * takes


def run_ludo(ids, jobs, takes=None):
    if not ids:
        return 0
    cmd = [sys.executable, os.path.join(HERE, "ludo.py"), "--jobs", str(jobs)] + ids
    if takes:
        cmd += ["--takes", str(takes)]
    return subprocess.run(cmd).returncode


def make(only, jobs, takes):
    write_manifest()
    items = pick_items(only)
    ids = [e["id"] for w, c in items for e in entries_of(w, c)]
    log("make %d reactions x %d takes, about %.0f credits" % (len(ids), takes or TAKES, cost_of(items, takes or TAKES)))
    rc = run_ludo(ids, jobs, takes)
    post(only)
    return rc


def regen(dry, jobs, use_notes=True):
    rej = [it for it in merged() if it.get("status") == "reject"]
    if not rej:
        print("%s: nothing rejected" % BATCH)
        return
    man = manifest()
    by = {a["id"]: a for a in man["assets"]}
    names = {name_of(w, c): (w, c) for w, c in ITEMS}
    redo, directed = [], []
    for r in rej:
        if r["id"] not in names:
            continue
        who, clip = names[r["id"]]
        aid = aid_of(who, clip)
        new_text = (r.get("edited_text") or "").strip()
        if new_text and new_text != (by[aid].get("prompt") or "").strip():
            print("  %s: the edited text is the new prompt" % r["id"])
            if not dry:
                by[aid]["prompt"] = new_text
        elif use_notes and notes.meaningful(r.get("note"), "image"):
            directed.append({"id": aid, "kind": "image", "prompt": by[aid].get("prompt", ""), "note": r["note"], "item": r["id"]})
        if use_notes and notes.meaningful(r.get("note"), "image") and not new_text:
            for e in entries_of(who, clip)[1:]:  ## a loop's second model reads the same note
                if e["id"] in by:
                    directed.append({"id": e["id"], "kind": "image", "prompt": by[e["id"]].get("prompt", ""),
                                     "note": r["note"], "item": r["id"]})
        redo.append((who, clip))
    if directed:
        if dry:
            os.environ["CONCURRENT_NO_CLAUDE"] = "1"  ## a dry run spends nothing, Claude included
        for aid, (prompt, why, how) in notes.rewrite_prompts(directed).items():
            print("  %snew prompt (%s) for %s: %s%s" % ("[dry-run] " if dry else "", how, aid, prompt, "  (" + why + ")" if why else ""))
            if not dry:
                by[aid]["prompt"] = prompt
    print("%sredo %d reactions: %s, about %.0f credits" % ("[dry-run] " if dry else "", len(redo),
                                                          ", ".join(name_of(w, c) for w, c in redo), cost_of(redo, TAKES)))
    if dry:
        return
    for who, clip in redo:
        for e in entries_of(who, clip):
            if e["id"] in by:
                by[e["id"]]["v"] = int(by[e["id"]].get("v", 1)) + 1
    save_json(MAN, man, indent=1)
    ## the rejected take stays beside the new ones ("rejected in round N" in the table); the rest go to old/
    d = batch_dir()
    stamp = time.strftime("%Y%m%d%H%M%S")
    for who, clip in redo:
        name = name_of(who, clip)
        tk = os.path.join(d, "faces", ".takes")
        rounds = [int(m.group(1)) for f in (os.listdir(tk) if os.path.isdir(tk) else [])
                  for m in [re.match(re.escape(name) + r"\.r(\d+)" + re.escape(PREVIEW) + "$", f)] if m]
        nxt = max(rounds or [0]) + 1
        for k, e, kk in sources(who, clip):
            for ext in (PREVIEW, SHEET + ".webp", SHEET + ".json"):
                p = os.path.join(d, review_of(who, clip, k) + ext)
                if not os.path.exists(p):
                    continue
                if k == 1:
                    dst = os.path.join(tk, "%s.r%d%s" % (name, nxt, ext))
                else:
                    dst = os.path.join(d, "old", "%s_%s" % (name, stamp), os.path.basename(p))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.move(p, dst)
    run_ludo([e["id"] for w, c in redo for e in entries_of(w, c)], jobs)
    post(",".join(name_of(w, c) for w, c in redo))


def main(argv):
    def opt(name, default=None):
        if name in argv:
            i = argv.index(name)
            return argv[i + 1] if i + 1 < len(argv) else default
        return default

    if "--batch-name" in argv and opt("--batch-name") != BATCH:
        sys.exit("this script makes the batch %s" % BATCH)
    os.chdir(ROOT)  ## the sheet tool and pack_anims take paths from the repo root
    jobs = int(opt("--jobs", 6))
    takes = int(opt("--takes", 0)) or None
    only = opt("--only")
    if "--cost" in argv:
        items = pick_items(only)
        print("%d reactions x %d takes: about %.0f credits" % (len(items), takes or TAKES, cost_of(items, takes or TAKES)))
        for w, c in items:
            print("  %-22s %s" % (name_of(w, c), prompt_of(w, c)))
    elif "--make" in argv:
        sys.exit(make(only, jobs, takes))
    elif "--post" in argv:
        post(only)
    elif "--reprompt" in argv:
        reprompt([a for a in argv[argv.index("--reprompt") + 1:] if not a.startswith("--")])
    elif "--install" in argv:
        install("--dry-run" in argv)
    elif "--regen" in argv:
        regen("--dry-run" in argv, jobs, "--no-notes" not in argv)
    else:
        n = write_manifest()
        write_batch()
        print("manifest: %d entries added or re-prompted" % n)


if __name__ == "__main__":
    main(sys.argv[1:])
