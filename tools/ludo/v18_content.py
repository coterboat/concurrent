#!/usr/bin/env python3
"""v1.8 voices: dozens of new takes so nobody repeats themselves, and lines for capitals,
upsets and taunts. Every new take is generated into a review batch first and only reaches
the game when it has been accepted in the review tool.

    python3 tools/ludo/v18_content.py            # lines.json + manifest entries (idempotent)
    python3 tools/ludo/ludo.py $(python3 tools/ludo/v18_content.py --ids)   # generate
    python3 tools/ludo/v18_content.py --batch    # write review/v18_voices/batch.json
    python3 tools/review/review.py serve --open  # listen: A accept, R reject, E fix the words
    python3 tools/ludo/v18_content.py --install  # apply the accepted takes and import them into Godot
                                                 #   (--dry-run: only list what would be copied)
    python3 tools/ludo/v18_content.py --regen    # re-roll every rejected take (edited words kept)

The last two are also the review table's "Install accepted" and "Redo rejected" buttons: the
batch.json that --batch writes declares them as actions.

A take's file is <key>.mp3 for take 1 and <key>_v<n>.mp3 after; lines.json holds a list.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAN = os.path.join(os.path.dirname(__file__), "manifest.json")
LINES_JSON = os.path.join(ROOT, "game", "data", "lines.json")
BATCH = "v18_voices"
BATCH_DIR = os.path.join(ROOT, "review", BATCH)
TITLE = {"v18_voices": "v1.8 voice lines", "v18b_voices": "v1.8b voice lines: Fortune"}

## When each line is heard, for the reviewer.
CONTEXT = {
    "sealed": "you seal your orders", "reveal": "every order is revealed at once", "orders": "recruits placed, now the orders",
    "reinforce": "fresh recruits arrive", "unplaced": "you still have recruits unplaced", "maneuver": "the regroup phase begins",
    "surges": "the surges begin", "opening_good": "your battle starts well (first call)", "opening_bad": "your battle starts badly (first call)",
    "cut_off": "your battle, no retreat possible", "press": "you press the attack", "retreat": "you fall back",
    "reserves": "the reserves are thrown in", "melee": "several armies storm one land", "scramble": "the victors fight over the spoils",
    "walkin_us": "you walk into an empty land", "walkin_them": "they walk into a land you left empty", "cash_us": "you turn in cards",
    "cash_them": "a rival turns in cards", "enemy_out": "a rival is wiped out", "cards_seized": "you seize a war chest",
    "capture": "your attack takes the land", "hold": "your garrison holds", "lost_land": "you lose a land in battle",
    "upset_win": "you win a battle you were likely to lose", "upset_loss": "you lose a battle you were very likely to win",
    "close_win": "you take a land with one man left standing", "close_hold": "your land holds with one man left",
    "good_roll": "a crushing exchange in your favour", "bad_roll": "a crushing exchange against you",
    "leader": "you take the lead", "behind": "you fall well behind the leader",
    "capital_choose": "deployment: name your capital", "capital_move": "your capital fell last round: move it?",
    "capital_taken": "you take a rival's capital", "capital_lost": "your capital falls",
    "attack": "their battle begins", "win": "they win a battle", "lose": "they lose a battle", "walkin": "they walk into your empty land",
    "claim": "they claim a land in the draft", "cash": "they turn in cards", "capital_took": "they take a capital",
    "taunt": "their orders are revealed, marching on you",
}

NEW = {
    "advisor": {
        "sealed": ["Sealed and sent. No taking it back now, Commander.",
                   "The couriers are riding. Whatever happens next, we chose it.",
                   "Signed, sealed, and out of our hands. I do love this part.",
                   "There. Our orders are in. Now we wait for the others to show their hand."],
        "reveal": ["And there they go! Every column on the map, all at once.",
                   "The orders are open. Let us see who guessed right.",
                   "Look at them all. Half of those arrows are aimed at somebody's mistake.",
                   "Everyone moves at once. Somebody is about to have a very bad afternoon."],
        "orders": ["The recruits are in position. Now choose our targets.",
                   "The men are ready. Point them at something worth taking.",
                   "Placements done. Now the interesting part. Who do we hit?"],
        "reinforce": ["New recruits have arrived. Put them where the enemy can see them.",
                      "More men for the cause. Strengthen the border, not the barracks."],
        "unplaced": ["Commander, there are still men standing on the docks. Place them, or lose them.",
                     "Some of our recruits have no orders yet. Unplaced troops go home at the seal."],
        "maneuver": ["The guns have gone quiet. Shift the men forward while we can.",
                     "A moment's peace. Use it. March the reserves up to the border.",
                     "Regroup, Commander. Idle soldiers in the rear win nothing."],
        "surges": ["The breakthroughs charge on! Hold on to your hat.",
                   "Here come the surges, all at once. Steady now."],
        "opening_good": ["A fine start! They are wavering, Commander.",
                         "Their line is buckling. Keep at them!",
                         "Good shooting! The day is ours if we hold our nerve."],
        "opening_bad": ["That went poorly. Cut our losses, or double down?",
                        "They are giving as good as they get. Your call, Commander.",
                        "An ugly start. The dice are not with us yet."],
        "cut_off": ["Nowhere to fall back to, Commander. It is this field or nothing.",
                    "No retreat from here. The men know it. So do I."],
        "press": ["Forward! Do not give them a moment to breathe!",
                  "At them again, lads!",
                  "Press on! We have them now."],
        "retreat": ["Pull them back, Commander. Live to fight another round.",
                    "Fall back in good order. There is no shame in it."],
        "reserves": ["Bring up the reserves! Throw them in!",
                     "Every man we have, Commander. Now is the moment."],
        "melee": ["Three armies, one field. Chaos, Commander. Glorious chaos.",
                  "Everyone has come to the same party. Keep your head down."],
        "scramble": ["The garrison is gone, and now the wolves turn on each other!",
                     "Nobody holds it yet. Now the victors fight for the spoils!"],
        "walkin_us": ["They left the door open and we walked right in. Splendid!",
                      "Not a soul defending it. Thank you kindly.",
                      "Empty! Oh, that is careless of them. Ours now."],
        "walkin_them": ["Confound it! We left the door open, and they walked right in.",
                        "They strolled into an empty land of ours. Lesson learned, I hope.",
                        "An empty land is an invitation, Commander. They accepted."],
        "cash_us": ["The cards are in. Fresh troops, courtesy of the war office.",
                    "Cashed in! Call up the regiments."],
        "cash_them": ["They have cashed in their cards. Mind the border, Commander.",
                      "Fresh troops for the enemy. Brace yourself."],
        "enemy_out": ["Another banner falls. The table grows smaller.",
                      "One rival down. The rest will be nervous now."],
        "cards_seized": ["Their war chest is ours! Every last card."],
        "capture": ["It is ours! Raise the colours!",
                    "Taken! Well fought, Commander.",
                    "The flag goes up. Another one for the map.",
                    "We have it! The men will drink well tonight."],
        "hold": ["They came, they bled, they went home. We hold!",
                 "The line held, Commander. Good men, those.",
                 "Repulsed! Send them home with their tails between their legs."],
        "lost_land": ["We have lost it, Commander. A bitter blow.",
                      "The land has fallen. We will be back for it.",
                      "Gone. Mark it on the map, and mark who took it."],
        "upset_win": ["Against all odds! I will not pretend I expected that.",
                      "Well, I never! The dice owed us one.",
                      "That should not have worked. It worked! Marvellous!",
                      "A miracle, Commander. Do not get used to it."],
        "upset_loss": ["Impossible! We had them beaten three times over!",
                       "Of all the rotten luck. Those odds were ours.",
                       "Blast those dice! That was a certainty on paper.",
                       "Sometimes the dice simply hate us, Commander. Today is one of those days.",
                       "Well. That was an outrage. Remember it, and move on."],
        "close_win": ["Taken with a single man standing. Close, Commander. Far too close.",
                      "One man left, and the land is ours. Give that fellow a medal."],
        "close_hold": ["One soldier left on the walls, and he held! Remarkable.",
                       "By the skin of our teeth, Commander. But we hold."],
        "good_roll": ["A cracking volley!", "Right on target!"],
        "bad_roll": ["Blast!", "Dreadful shooting.", "Oh, come on!"],
        "leader": ["We are out in front, Commander. Expect company."],
        "behind": ["The others are pulling ahead. We need land, and quickly."],
        "capital_choose": ["Choose our capital, Commander. Somewhere safe, somewhere central. It pays well, and it fights hard.",
                           "Every empire needs a seat of government. Pick ours wisely."],
        "capital_move": ["The court has fled, Commander. Name a new capital, or leave it where it landed.",
                         "Our government has moved in rather a hurry. Choose a proper home for it."],
        "capital_taken": ["Their capital is ours! Plunder the treasury!",
                          "We have taken their seat of government! Half their cards, and a city full of recruits.",
                          "Their crown has fallen! Loot the vaults, lads!"],
        "capital_lost": ["Our capital has fallen! The treasury is plundered.",
                         "They have taken the capital, Commander. The court is fleeing.",
                         "A black day. Our capital is in enemy hands."],
    },
    "varek": {
        "attack": ["Forward. Steady ranks.", "Take the ground. Hold it.", "Advance, and do not stop until it is ours."],
        "win": ["Of course.", "The ground is ours. Next.", "They broke. They always break."],
        "lose": ["Noted.", "A costly lesson. For them, eventually.", "Bury the dead. We go again."],
        "walkin": ["An open gate is an invitation. I accepted.", "You forgot to leave a guard. I did not forget to notice."],
        "retreat": ["Withdraw in good order. Discipline.", "Enough. Pull them back."],
        "reserves": ["Commit the reserve. Finish it.", "Every man forward. Now."],
        "cash": ["The war office sends its compliments. And its regiments."],
        "claim": ["Here. We build from here.", "A sound position. Mine."],
        "capital_took": ["Your capital is mine. Your treasury too.", "The seat of your government now flies my colours.", "A capital is only stone. You should have held it."],
        "capital_lost": ["They have taken my capital. They will not keep it.", "The capital falls. The war does not.", "Move the court. We fight on."],
        "taunt": ["I see your border, Commander. It is thin.", "My columns are marching. I would dig in, if I were you.",
                  "You have something of mine. I am coming to collect it.", "Brace yourself. This one will hurt."],
    },
    "ysolde": {
        "attack": ["March. And do not come back without it.", "Crush them. Quickly.", "Take it. I dislike waiting."],
        "win": ["As it should be.", "They were never going to hold.", "Another province for the Viceroy."],
        "lose": ["Unacceptable.", "Someone will answer for this.", "You have made an enemy today, Commander."],
        "walkin": ["You left it undefended. How generous.", "An empty province. How very careless."],
        "retreat": ["Fall back. I will remember this field.", "Withdraw. We choose the next battle."],
        "reserves": ["Send the guard. All of it.", "Reinforce. I do not accept defeat."],
        "cash": ["The treasury is open. Raise the regiments."],
        "claim": ["This one is mine. Mark it.", "I will have this province."],
        "capital_took": ["Your capital kneels to me now.", "Your court has fled. Your treasury has not.", "A pretty city. I will rename it."],
        "capital_lost": ["They dare to sit in my capital?", "My court moves. My army does not forget.", "You have taken my capital. Now I will take everything."],
        "taunt": ["Your border is weak, Commander. I can see it from here.", "In my country, we do not knock.",
                  "Look east, Commander. Winter is coming for you.", "I hope you enjoyed that land. You will not keep it."],
    },
    "quill": {
        "attack": ["Right, lads. Go and repossess it.", "Hostile takeover, gentlemen!", "There is money in that valley. Fetch it."],
        "win": ["Ka-ching!", "A very tidy margin.", "Add it to the ledger!"],
        "lose": ["Ooh, that is a write-off.", "Well, that was a poor investment.", "Losses, losses. Most disappointing."],
        "walkin": ["Unattended property? Mine, by right of possession.", "Nobody minding the shop? Lovely."],
        "retreat": ["Pull out, lads. The market has turned.", "Sell! Sell! Back to the ships!"],
        "reserves": ["Throw in the capital! All of it!", "Double down, gentlemen!"],
        "cash": ["Cashing in my chips. With interest."],
        "claim": ["Prime real estate. I will take it.", "Location, location, location."],
        "capital_took": ["Your treasury? Consider it audited.", "What a lovely capital. And such generous vaults!", "The Company thanks you for your contribution."],
        "capital_lost": ["My counting house! Somebody stop them!", "They have robbed the treasury! Pack the ledgers, we are moving.", "A temporary cash flow problem. Temporary!"],
        "taunt": ["Nothing personal, Commander. Just business.", "I have made you an offer you cannot refuse. My army.",
                  "Your lands are under new management. Mine.", "Let us call it a merger, shall we?"],
    },
    "oren": {
        "attack": ["Tally ho! After them!", "Right! Swords out! Charge!", "Come on, boys! Last one there buys the drinks!"],
        "win": ["Ha! Easy!", "Did you see that? Did everyone see that?", "Magnificent! I am magnificent!"],
        "lose": ["Oh, bother.", "That is, hm. That is not ideal.", "Not fair! They cheated! Probably."],
        "walkin": ["Oh, it is empty! Mine, mine, mine!", "Nobody there? Brilliant!"],
        "retreat": ["Back! Back! Regroup! Look dashing!", "Strategic withdrawal! It is a real thing!"],
        "reserves": ["Send everyone! Even the cooks!", "Bring the whole regiment!"],
        "cash": ["More soldiers! This is the best day ever!"],
        "claim": ["That one looks fun!", "I want that one! Dibs!"],
        "capital_took": ["I took your capital! Wait until I write home!", "Your capital! Is it mine? It is mine!", "Ha! A whole capital! With a palace!"],
        "capital_lost": ["My capital! Oh, Mother is going to be furious.", "They took my capital? I was using that!", "Right. New capital. Nobody panic. I am not panicking."],
        "taunt": ["Hello, neighbour! Coming through!", "Ready or not, here I come!",
                  "You look like you need a good charge, Commander!", "I have a very fast horse, and it is pointed at you!"],
    },
    "hask": {
        "attack": ["Board them, lads! Ha!", "Give them the broadside!", "Up and at them! The Bear is hungry!"],
        "win": ["Ha ha! Too easy!", "Sunk! Like a stone!", "That is how the Bear does it!"],
        "lose": ["Argh! Lucky shot!", "Bah! They will pay for that one!", "Grr. Patch the hull and go again."],
        "walkin": ["Ha! Nobody on deck? I will take her!", "Empty? The Bear says thank you!"],
        "retreat": ["Hard about! Back to the ships!", "Fall back, lads! Live to plunder another day!"],
        "reserves": ["All hands! Everybody in!", "Send the whole fleet! Ha!"],
        "cash": ["Fresh crew for the Bear! Ha ha!"],
        "claim": ["That harbour looks good. Mine!", "Drop anchor there, lads!"],
        "capital_took": ["Your capital! Loot the treasury, lads! Ha ha!", "The Bear sits on your throne now!", "What a prize! Hoist my colours!"],
        "capital_lost": ["They have taken my capital! Argh! To arms!", "My hall! My beer! They will pay!", "Bah! A capital is just a building. The Bear is still here!"],
        "taunt": ["I am coming for you, little general! Ha!", "Hide your ships and lock your doors!",
                  "The Bear smells your border, and it smells weak!", "Run! Or do not. It is more fun if you do not!"],
    },
    "imre": {
        "attack": ["Execute.", "As predicted. Proceed.", "They are exactly where I expected. Strike."],
        "win": ["Precisely.", "Of course it did.", "The numbers never lie."],
        "lose": ["Unexpected. Noted.", "A variance. It will even out.", "Hm. You have my attention."],
        "walkin": ["You left it open. I noticed.", "Empty. I had counted on that."],
        "retreat": ["The odds have shifted. Withdraw.", "Preserve the fleet. Fall back."],
        "reserves": ["Now. The reserve.", "All of it. The margin matters."],
        "cash": ["Exactly the right moment. Deploy."],
        "claim": ["This one. It connects everything.", "That land. I have my reasons."],
        "capital_took": ["Your capital. I have had it marked since round one.", "The seat of your power. Now the seat of mine.", "Your treasury was poorly defended. I corrected that."],
        "capital_lost": ["My capital has fallen. Irritating.", "A setback. The court relocates. The plan continues.", "Well played. It will not happen twice."],
        "taunt": ["I have already seen your next move, Commander.", "You are predictable. That is not a compliment.",
                  "I found your weakest border.", "Check."],
    },
}

## v1.8 sounds and art, generated straight into the game (not voice lines)
EXTRA = [
    {"id": "sfx_capital_fall", "kind": "sfx", "duration": 4, "out": "assets/raw/sfx/capital_fall",
     "prompt": "a great city bell tolling slowly and heavily while a cannon booms and a distant crowd cries out in dismay, a capital city falling, no music"},
    {"id": "howto_capital", "kind": "image", "type": "art", "aspect": "ar_16_9", "out": "assets/art/howto_capital", "v": 2,
     "prompt": "A grand capital city at dusk crowned by a domed palace flying a great banner, cannon smoke drifting over its walls as a victorious column of Napoleonic-era infantry in red coats, shakos and crossbelts, muskets with fixed bayonets, marches through the broken city gate while soldiers carry off chests of treasure, 1810s, no armour, no knights, dramatic golden light"},
]


def voice_of(who):
    return "voice_advisor" if who == "advisor" else "voice2_" + who


def target_of(who, name):
    return ("assets/voice/advisor/%s.mp3" % name) if who == "advisor" else ("assets/voice13/%s/%s.mp3" % (who, name))


PLAN = os.path.join(os.path.dirname(__file__), "v18_plan.json")


def plan():
    """[(who, key, take_index, name, text)] for every new take (take_index 0-based). Frozen
    to v18_plan.json on the first run, so a take keeps its number (and its file) even after
    a reviewer rewords it."""
    if os.path.exists(PLAN):
        return [tuple(r) for r in json.load(open(PLAN))]
    d = json.load(open(LINES_JSON))
    out = []
    for who, keys in NEW.items():
        have = d["lines"].get(who, {})
        for key, texts in keys.items():
            cur = have.get(key, [])
            cur = cur if isinstance(cur, list) else ([cur] if cur else [])
            ## the takes that were there before this script
            base = [t for t in cur if t not in texts]
            for n, text in enumerate(texts):
                i = len(base) + n
                name = key if i == 0 else "%s_v%d" % (key, i + 1)
                out.append((who, key, i, name, text))
    json.dump(out, open(PLAN, "w"), indent=0, ensure_ascii=False)
    return out


def write_lines():
    rows = plan()
    d = json.load(open(LINES_JSON))
    for who, key, i, name, text in rows:
        have = d["lines"].setdefault(who, {})
        cur = have.get(key, [])
        cur = cur if isinstance(cur, list) else ([cur] if cur else [])
        while len(cur) <= i:
            cur.append("")
        cur[i] = text
        have[key] = cur if len(cur) > 1 else cur[0]
    json.dump(d, open(LINES_JSON, "w"), indent=1, ensure_ascii=False)


def mid(who, name):
    return "line18_%s_%s" % (who, name)


def write_manifest():
    man = json.load(open(MAN))
    old = {a["id"]: a for a in man["assets"]}
    for who, key, i, name, text in plan():
        e = {"id": mid(who, name), "kind": "speech", "voice": voice_of(who), "text": text,
             "out": "review/%s/%s/%s" % (BATCH, who, name)}
        o = old.get(e["id"])
        e["v"] = int(o.get("v", 1)) + (1 if o.get("text") != text else 0) if o else 1
        old[e["id"]] = e
    for e in EXTRA:
        o = old.get(e["id"])
        if not o:
            old[e["id"]] = e
    man["assets"] = list(old.values())
    json.dump(man, open(MAN, "w"), indent=1)


def ids():
    return [mid(who, name) for who, key, i, name, text in plan()] + [e["id"] for e in EXTRA]


def script_rel():
    """The script this run started from, relative to the repo: v18b_content.py runs this module's
    code, and its buttons must call v18b_content.py back."""
    main = os.path.abspath(sys.argv[0]) if sys.argv and sys.argv[0] else ""
    if not (main.endswith(".py") and os.path.isfile(main) and main.startswith(ROOT + os.sep)):
        main = os.path.abspath(__file__)
    return os.path.relpath(main, ROOT).replace(os.sep, "/")


def actions():
    """The buttons the review table offers for this batch (see tools/review/README.md)."""
    cmd = ["python3", script_rel()]
    return [
        {"id": "install", "kind": "install", "label": "Install accepted",
         "help": "Copy the accepted takes into the game, then re-import in Godot",
         "cmd": cmd + ["--install"],
         "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                      "help": "Only list what would be copied; no Godot import"}]},
        {"id": "regen", "kind": "regen", "label": "Redo rejected",
         "help": "Regenerate every rejected take with Ludo (spends credits); reworded lines use the new words",
         "cmd": cmd + ["--regen"], "spends": True},
    ]


def write_batch():
    items = []
    for who, key, i, name, text in plan():
        f = None
        for ext in (".mp3", ".wav", ".ogg"):
            if os.path.exists(os.path.join(BATCH_DIR, who, name + ext)):
                f = "%s/%s%s" % (who, name, ext)
        items.append({"id": "%s.%s.%d" % (who, key, i + 1), "kind": "audio", "group": who,
                      "label": "%s · take %d" % (key, i + 1), "text": text,
                      "file": f or "%s/%s.mp3" % (who, name), "target": target_of(who, name),
                      "meta": {"voice": voice_of(who), "manifest_id": mid(who, name), "key": key,
                               "context": CONTEXT.get(key, "")}})
    os.makedirs(BATCH_DIR, exist_ok=True)
    out = os.path.join(BATCH_DIR, "batch.json")
    with open(out + ".tmp", "w") as f:  ## the review table may be reading it: swap it in whole
        json.dump({"batch": BATCH, "title": TITLE.get(BATCH, BATCH), "actions": actions(), "items": items},
                  f, indent=1, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    print("batch: %d takes (%d with audio)" % (len(items), sum(1 for it in items if os.path.exists(os.path.join(BATCH_DIR, it["file"])))))


def regen():
    """Re-roll every rejected take: new words if the reviewer fixed them, a new take either way."""
    path = os.path.join(BATCH_DIR, "rejected.json")
    if not os.path.exists(path):
        print("nothing rejected (run: python3 tools/review/review.py apply %s)" % BATCH)
        return
    rejected = json.load(open(path))
    man = json.load(open(MAN))
    by = {a["id"]: a for a in man["assets"]}
    d = json.load(open(LINES_JSON))
    todo = []
    for r in rejected:
        m = r.get("meta", {})
        aid = m.get("manifest_id")
        if aid not in by:
            continue
        e = by[aid]
        new_text = r.get("text") or e["text"]
        if new_text != e["text"]:
            ## keep the subtitle in step with the new words
            who = aid.split("_")[1]
            key = m.get("key", "")
            cur = d["lines"].get(who, {}).get(key)
            if isinstance(cur, list) and e["text"] in cur:
                cur[cur.index(e["text"])] = new_text
            elif cur == e["text"]:
                d["lines"][who][key] = new_text
            ## and in the script's own table, so a re-run does not undo it
            print("  words changed: %s -> %r" % (aid, new_text))
            e["text"] = new_text
            rows = json.load(open(PLAN))
            for row in rows:
                if mid(row[0], row[3]) == aid:
                    row[4] = new_text
            json.dump(rows, open(PLAN, "w"), indent=0, ensure_ascii=False)
        e["v"] = int(e.get("v", 1)) + 1
        todo.append(aid)
    json.dump(man, open(MAN, "w"), indent=1)
    json.dump(d, open(LINES_JSON, "w"), indent=1, ensure_ascii=False)
    if todo:
        subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "ludo.py")] + todo, check=False)
        write_batch()


def install():
    """Copy the accepted takes into the game, then have Godot import them (a voice file the
    engine has not imported does not exist as far as the game is concerned). --dry-run only
    lists what would be copied."""
    dry = "--dry-run" in sys.argv
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "review", "review.py"), "apply", BATCH]
                   + (["--dry-run"] if dry else []), check=True)
    if dry:
        print("dry run: nothing copied, no Godot import")
        return
    godot = os.environ.get("GODOT", os.path.expanduser("~/Downloads/Godot.app/Contents/MacOS/Godot"))
    if not os.path.exists(godot):
        print("Godot not found at %s: set GODOT=... and run it with --headless --path . --import" % godot)
        return
    print("importing into Godot (this can take a minute)...", flush=True)
    subprocess.run([godot, "--headless", "--path", ROOT, "--import"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("imported: the accepted takes are in the game")


def main():
    if "--install" in sys.argv:
        install()
        return
    if "--ids" in sys.argv:
        print(" ".join(ids()))
        return
    if "--batch" in sys.argv:
        write_batch()
        return
    if "--regen" in sys.argv:
        regen()
        return
    write_lines()
    write_manifest()
    write_batch()
    n = len(plan())
    print("v1.8: %d new takes across %d voices; %d extra assets" % (n, len(NEW), len(EXTRA)))


if __name__ == "__main__":
    main()
