# v24-faces: reactions that move

Alex, from the v2.3.1 playthrough: "let's do away with the 'eyes blazing' animations, and redo them with
new and improved reaction animations for win/loss/taunt/etc".

Branch `claude/v24-faces-d6b1ac`. Everything here is mine to merge as is, except small changes to two shared
scripts (`scripts/check.sh`, one line; `scripts/review.sh`, the Python it runs) and a section each in
`docs/ASSETS.md` and `docs/PROMPTING.md`, called out below.

## What changed

**The face (`game/ui/leader_face.gd`).** `react(mood, line_key, hold, speak)` keeps its signature, so no
caller changed. A mood now plays its reaction when one is installed in `assets/portraits/loops/`:

| mood (callers) | reaction | the advisor's | a player's face |
|---|---|---|---|
| win, happy (a win, a capital taken, a claim, cards cashed, a greeting, Fortune, reserves) | `win` | `win`: good news | `win` |
| lose, alarm (a loss, a retreat, a capital lost) | `lose` | `lose`: a warning | `lose` |
| dead (the "has fallen" card, a fallen face in the roster) | `dead`: a fall that stays down | `dead`: the war lost, grave, then back to himself | `dead` |
| the `taunt` line (said with mood win) | `taunt`, or `win` without one | | |

- A reaction plays once, from the portrait and back to it, so it cuts in from the idle loop and out again
  without a jump (a 0.2 s crossfade, as between idle and talk). The line is spoken while it plays; if the
  line runs longer, the talk loop says the rest, then the face rests. A line that has to wait its turn
  doesn't hold the reaction back.
- A fall (`"hold": true` in its json) ends bowed and the face stays on that last frame, its colour draining
  over the fall (the old 0.4 s grey tween, stretched to the fall). A face set dead in the roster shows that
  last frame at once, in grey, and doesn't replay it on every roster refresh.
- **No reaction installed: today's behaviour, untouched.** The v1.2 still (`triumphant`, `angry`,
  `defeated`; the advisor's `pleased`, `alarmed`) and its bump. Nothing is installed on this branch, so the
  game plays exactly as v2.3.1 until Alex accepts takes in the review table.

**The reactions (`tools/ludo/v24_content.py`, review batch `v24_faces`).** 46 items, two takes each (the
Lioness's idle four):

- The six commanders: win, lose, taunt, dead. The advisor: win, lose, dead. The six faces a player can wear
  (Iron Duke, Corsair, Lioness, Scholar, Rajah, Grenadier): win, lose, dead, silent (no lines).
- Made the way the v1.9 talk loops were (Hydra `animateSprite`, `image_type: portrait`, 3 s, 36 frames, the
  talk loops' manual 0.02 margins), from the portrait itself with `final_same` (a fall has no final image).
  The game's sheet is 256 px cells at ~12 fps, the duplicate last frame dropped, `"once": true`.
- Each prompt plays the character's own lines: Varek's grim nod ("As expected."), Hask's belly laugh ("Hah!
  Soft as butter!"), Quill peering over his spectacles ("Nothing personal, Commander. Just business."), Oren's
  boyish whoop, Imre's knowing eyebrow, Ysolde's cold half-smile. Written by `docs/PROMPTING.md`: the whole
  motion and how it ends, where the eyes go, head and hat in the frame, what the hands keep (Imre's spyglass,
  the Scholar's map), said positively.
- **The Lioness breathed as someone else.** Her portrait was re-rolled (red coat, `portrait_you_lioness` v2)
  after her idle loop and her angry/defeated stills were made from the first one (a khaki greatcoat). Her idle
  is 24.1 off her portrait (mean colour difference /255); every other face's is 2.6-7.0. Her reactions are cut
  from today's portrait, so they would have jumped out of a different coat. The batch has a remade idle for
  her, item `you_lioness_idle`, with four takes: 1-2 the way every other face's idle was made (forge, 2 s, the
  v1.2 idle prompt), 3-4 on Hydra with "her lips gently closed" (added after looking at 1-2, below).
- The review shows each take as an animated WebP of the face in its gilded ring, as the game draws it (the
  first frame held 0.6 s, the last 0.9 s, a fall's 2 s). Its chip says how far its first and last frames
  are from the portrait ("from portrait: 5.8 in, 5.7 out"; 5-15 is the portrait itself).
  Install copies the kept take's sheet (`<stem>.sheet.webp` + `.json` beside it) to the game and imports.
  Redo rolls two new takes of a rejected reaction, reading its note (`notes.py`) or the edited prompt; the
  rejected take stays beside the new ones ("rejected in round N").

**`tools/ludo/ludo.py`.**
- The job wait. Every Ludo call is a queued job, charged at once (`{id, status: queued}`); `run_job` already
  polled `GET /assets/jobs/{id}?wait=55`, but it spun forever on a `cancelled` or `error` status (it knew only
  `failed`/`canceled`), and a dropped connection while polling (five tries, about 75 s) abandoned a paid job.
  Now: every spelling of a dead job fails it, a connection error keeps polling, and a job unfinished after
  `LUDO_JOB_WAIT` (an hour) says to run the asset again, which its `request_id` hands back without a charge.
  Tests: `tools/ludo/test_ludo.py` (no network; its 7 job and input tests against the old `ludo.py`: 1
  failure and 6 errors), plus 4 on `v24_content.py`: every face and mood asked for, a reaction comes home
  and a fall stays down, every take numbered, and Install copies the take that was kept.
- The 1-megapixel fit used macOS `sips`; on the PC it uses Pillow (same sizes: varek 1013x993 -> 998x980).
- `animate` assets roll takes (`takes` in the manifest) like speech and sfx.

**Shared files, small:**
- `scripts/review.sh` ran `python3`, which on this PC is the Microsoft Store stub, so the review table
  couldn't open here. It now picks a Python that runs (as `check.sh` does), and opens the browser with
  `start` on Windows when the table is already running.
- `scripts/check.sh`: the tool tests run `tools/ludo/test_ludo.py` too. (CLAUDE.md's "Tool tests" row could
  name it; I left CLAUDE.md alone.)
- `docs/ASSETS.md`: a "Reactions" section beside "Portrait loops" (the format and the accept rule).
- `docs/PROMPTING.md`: rule 9 under "Pictures, animation and film", which `notes.py` hands to Claude on
  every picture redo: a face reacts in character and comes home.

## Evidence

- **Pilot first** (6 clips, one take each, 54 credits): Hask's win, Varek's loss, Quill's taunt, Oren's fall,
  the advisor's alarm, the Lioness's win. All six kept their identity and costume, natural eyes (no glow),
  returned to the portrait, and Oren's fall ended bowed with his hair over his eyes. Varek's loss is subtle
  (cold, in character). The prompts went to the full run unchanged but for grammar.
- **The cut in and out.** Reaction first/last frame against the idle loop's frame: 6-15 (mean colour
  difference /255). The game already cuts between idle and talk at 5-18 (advisor 14.2, varek 16.6, quill 16.3,
  oren 17.8, hask 5.4), so a reaction joins as smoothly as the talk loop does.
- **Probe `tools/shots/v24f.gd`: 30 facts, 6 shots** (`./scripts/probes.sh v24f`, 28 s; green as the bot's
  box too, `PROBE_ARGS=--box=40`). The review's takes aren't in git until accepted, so it stands in reactions
  cut from the committed talk loops (as their own textures) for the moments:
  - every face has, for every mood, an installed reaction that is a valid one-shot sheet (`once`, fps, 256 px,
    `hold` only on a fall) or its v1.2 still;
  - no reaction: Ysolde's win shows her triumphant still and the bump, then relaxes into her idle loop;
  - a reaction: Varek's win plays it once with no bump and returns to his idle loop; the advisor's alarm and
    the player's face play theirs and rest;
  - Varek's greeting (7.8 s) outlasts his reaction (1.4 s stand-in): the reaction, then the talk loop, then rest;
  - the taunt plays the win without a taunt of its own, and its own when there is one;
  - a battle closing (`hush`) stops a reaction, as it stops the talking (a fall stays down);
  - a line queued behind the advisor's doesn't hold Hask's reaction back;
  - Quill's fall plays and stays on its last frame, colour drained (0.75) and sunk (0.94); a roster face set
    dead shows the last frame at once, in grey (0.85); a face with no fall shows its defeated still; brought
    back, it breathes again;
  - in a war: Hask's taunt plays on his roster face, Quill (no reaction) shows his still, Hask comes back.
- `./scripts/check.sh` green (compile, the tool tests with `test_ludo.py`, the newest test file). The full suite:
  `CONCURRENT ok passed=741 failed=0`, no SCRIPT ERROR. The probes that drive faces or whole wars: v17 (11
  facts), v113 (36), v23 (50, the tutorial war start to finish), all green.

## Credits

**834 spent**: 3,681.7 available before, 2,847.7 after (`ludo.py --account`), matching the ledger's 94 v24
entries: 90 Hydra takes at 9 (the 45 reactions, two each), 2 Hydra idle takes at 9 and 2 forge idle takes at
3. Of that, the pilot was 54. Nothing failed or was refused (Hydra's moderation passed every prompt).

## What I saw in the takes (observations, not verdicts: every item is pending)

- Every take kept its character's face, costume and framing, with natural eyes. Every returning take starts
  and ends 5-15 from its portrait (Varek's two taunts end a little further off, 17.2 and 15.7), and every
  fall ends bowed and holds.
- The Lioness's forge idles: take 1 has a small white smudge beside her face in one frame (frame 7 of 15);
  take 2 opens her mouth through most of the loop, so she would look like she's talking at rest. That's why
  takes 3-4 (Hydra, lips closed) are there; both came back clean.
- Varek's win and loss, and Imre's, are small movements (a grim nod, narrowed eyes): in character, but they
  may not read on the 44 px roster faces.
- The taunts lean toward you (the head grows for a moment), so a tall hat can touch the ring's top edge.
- Falls end with the hat brim over the face (Hask, Varek, Ysolde, the Lioness): the face goes, the hat stays.

## Where the batch is

`review/` and `assets/raw/` are gitignored, so the batch isn't on the branch: it is in this worktree,
`review/v24_faces/` (92 MB: 94 previews, their sheets, `batch.json`, `v24_state.json`). To review it in the
main checkout, copy that folder to the same place there after the merge (the ledger and manifest entries it
refers to come with the branch):

    cp -r .claude/worktrees/v24-faces-d6b1ac/review/v24_faces review/

`assets/raw/v24/` (403 MB of Ludo masters) is only needed to re-pack a take, not to review, install or redo.
Then `./scripts/review.sh` (or `Review Table.command` on the Mac) and pick "v2.4 reactions". I opened it in
this worktree's table: all 46 items render with their previews and take captions, nothing recorded.
Install imports into Godot only where a `.godot` cache already exists (the PC's main checkout has none: a
first 4.7.1 import there rewrites ~900 `.import` files), and otherwise says to open the project in Godot.

## What Alex should poke at

1. In the review table: each reaction has two takes (`←`/`→`). Keep one (`A`) or reject both with a note
   (`N`): the redo reads it. The Lioness's breathing is in there too. Then **Install accepted**.
2. In a war with the reactions installed: a commander winning, losing and taunting you (the roster faces and
   the battle faces), the advisor's good news and warnings, your own face in a battle, and a knockout (the
   "has fallen" card, then the greyed face in the roster).
3. That a reaction reads at the roster's size (44 px): the faces are drawn small there.

## Open questions (for Alex, through the coordinator)

1. A commander's "happy" (a greeting, Fortune, reserves) plays the win reaction, as it showed the triumphant
   still before. A warmer "pleased" reaction of their own: 6 more, about 108 credits for two takes each?
2. The Lioness's angry and defeated stills are still the khaki ones. They show only until her lose and dead
   reactions are accepted. Remake them too (an edit of today's portrait), or let the reactions retire them?
3. Repo size: an accepted sheet is 0.4-0.9 MB (617 KB on average), so all 46 add about 28 MB.
