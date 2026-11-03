# v2.4.2: the bot's four probes (B-013 to B-016), for the coordinator to fold in

Branch `claude/silly-sammet-b42360`. Three pieces of text below, each ready to paste. They're kept out of
`docs/CHANGELOG.md`, `PLAYTEST.md` and `CLAUDE.md` so this branch and the general pass don't collide.

1. **`docs/CHANGELOG.md`**: the entry goes at the top, above v2.4.1. Add the full suite's line to its evidence
   once the merged branch has run it.
2. **`PLAYTEST.md`**: the section goes above v2.4.1's, and v2.4.1's heading loses its "(this push)".
3. **`CLAUDE.md`**: one bullet for "Gotchas that have bitten before", after "Probes run with films off".

Files on the branch:
- `tools/probe.gd`
- `tools/shots/v202.gd`, `v21.gd`, `v22.gd`, `v24p.gd`
- `tools/shots/ref/.gdignore` and `tools/shots/ref/v24p_tokens.webp`
- `game/world3d/land.gd`: one line, the watchdog in `_process`. The general pass's change to the same file is in
  `fit()`; the two merge cleanly.

---

## 1. CHANGELOG entry

## v2.4.2 — 3 Nov 2026: the bot's four probes on a slow box (no rule change: rules 23)

The playtest bot's verdicts on v2.4 (`d6c1f58`) and v2.4.1 (`91128e7`) left four open bugs, B-013 to B-016,
all in probes on its box, which draws in software (llvmpipe). Three were frame-rate traps. One was the Godot
version. Under them was one thing in the game: the land's watchdog couldn't see a slow machine while a probe
held the clock.

- **B-013** (`v202`: one fact in 5,400 s on `d6c1f58`, none in 900 s on `91128e7`). Two causes:
  - **The land's watchdog judged the machine by the game's clock.** Since v2.3.1, `p.steady()` holds the
    game to a 60th of a second a frame, so a frame that took seconds looked like a 60th. The land never gave
    up its dearest effects: on the bot's box it drew SSAO, 2× MSAA and four shadow splits in software
    through every held moment. It now judges the machine's own frame (`land.gd`: the frame's delta over the
    clock's rate). The game never changes that rate, so play is untouched. Shown with the new `--slow=100`
    on the Compatibility renderer (about 9 frames a second, held a 60th): the land stepped from quality 0
    to 4 within 100 frames. Before the change it stayed at 0.
  - **The whole probe was held a 60th of a second a frame**: 4,114 frames at `--box=40`. Now a frame moves
    the game a quarter of a second at most, which changes nothing on a machine that draws faster than that.
    It drops to a 60th only from the clash's charge to the winner carrying on, for the swoop, and for a
    second of the battle. Waits that meant seconds are now seconds (`p.secs()`).
- **B-014** (`v22`): "then Dad's assault on Mill from Ridge" failed after 18 facts (`91128e7`, and here at
  `--box=40`, to the fact). A finished battle moves on by itself 2.6 s after its end (v2.4), and the probe
  waited 40 frames there before pressing on: a minute on the box. By then the melee had gone and the assault
  on Mill had opened, so the probe's press fought that too, and the battle it waited for next never came. The
  wait is two-thirds of a second of game time now. The shots are watched at a 20th of a second (six frames
  to a ball's flight; a 60th tripled the frames and saw no more), and the fall-timing volleys at a 60th.
  - **Found on the way:** `steady()` takes hold from the next frame, because Godot sets a frame's step before
    any script runs. The probe ordered its first timed volley in the frame it asked for a 60th, and that frame
    still moved a quarter of a second. The first men fired and their balls landed unseen, so the first fall
    looked early (4 runs in 6). It now waits a frame.
  - **The crash** (signal 11 after about 630 s, once, on `d6c1f58`) didn't reproduce here in 15 runs (NVIDIA;
    Forward+ and Compatibility; full speed, `--box=40` and `--box=120`), and the bot's run on `91128e7` didn't
    crash. It isn't called fixed: PLAYTEST asks for a backtrace if it comes back.
- **B-015** (`v21`: "-1 left standing", 3 runs in 3; reproduced here at `--box=40`). The same trap: the probe
  waited 90 frames at a battle's end before counting the loser's pieces, and on the box the battle had closed
  and its field was gone. That wait is now held a 60th of a second a frame (1.5 s, inside the 2.6 s before
  the battle moves on), and the rest of the probe a quarter at most. The clash on Ridge's border, which failed
  once on the bot (Harbor's column "-1"), is watched a 60th too: Ridge's column stands aside until the shove
  is over, and the clash is gone a quarter of a second later.
- **B-016** (`v24p`: the token meshes "19.6/255 apart"). It wasn't llvmpipe or the renderer: it was the Godot
  version.
  - Godot 4.4 on the PC's RTX 3070 gives the bot's numbers: 19.6/255 over 177,507 pixels (the bot's 177,518),
    26.2% off, 28.85% two pixels across (28.84%). Godot 4.7.1 gives 4.0/255 on Forward+, Compatibility, ANGLE
    and D3D12.
  - The meshes draw pixel for pixel the same on 4.4 and 4.7.1; the old drawing doesn't. Before 4.7 an
    antialiased line comes out about a pixel wider than asked (a 2 px line covers 3.24 px on 4.4 and 2.20 on
    4.7.1), and the meshes were matched to 4.7's lines.
  - On Godot 4.7 or later the meshes are still held to the old drawing. On any Godot they're held to their
    own 4.7 picture, `tools/shots/ref/v24p_tokens.webp` (lossless, 94 KB, kept out of the import): 0.00/255
    on 4.4 and 4.7.1, 0.42 on Compatibility, 0.88 on ANGLE. Five planted faults fail it on both Godots: a
    token a pixel too big (1.9/255, half a percent off), its edge a pixel too thin (10/255, 15%), its sheen or
    its shadow gone (3.2/255 and 8%; 1.7/255 and 4%), its face a shade lighter (5.3/255). The probe logs
    the Godot, the renderer and how wide this Godot draws its lines. `PROBE_ARGS=--ref ./scripts/probes.sh
    v24p` writes the picture afresh, on 4.7 or later and only while the meshes match the old drawing.
  - On an older Godot (the Mac's 4.5.1, and the bot's) the tokens' lines are now 4.7's, about a pixel
    thinner than v2.3 drew them there. On the PC and in Dad's build (4.7.1) they look as they always did.
  - **Also caught at `--box=40`:** "musket balls are seen to fly (0 streaks)", the bot's "once under load".
    v24p's battles are now held a quarter of a second a frame, and a 20th until six streaks have been seen
    in each of the first two.
- **The probe harness** (`tools/probe.gd`):
  - `p.steady(on, step)` with a coarse step costs a fast machine nothing and keeps a slow one from leaping over
    a moment. Its floor is now a thousandth (was a hundredth), so a 60th holds on a box as slow as 16 s a frame.
  - `p.secs(t)` waits t seconds of game time.
  - `p.lap(part)` logs the frames and seconds a part took.
  - `--slow=MS` makes every frame take MS longer, as a slow box's do. `--box` only moves the game on.
- **Evidence** (the PC, Godot 4.7.1, with the v2.5 session's soak and suite running alongside). Frames as the
  bot's box (`--box=40`) before and after, every fact passing after:

  | probe | facts | `--box=40` before → after | `--box=120` | full speed |
  |---|---|---|---|---|
  | v202 | 34 | 4,114 → 2,234 | 2,048 | 6,440 |
  | v21 | 13 | 1,647, FAIL → 1,246 | 1,238 | 6,743 |
  | v22 | 19 | 4,181, FAIL → 1,692 | 1,705 | 5,784 |
  | v24p | 30 | about 800, FAIL (0 streaks) → 1,243 | 1,273 | 3,160 |

  Here a frame also waits on things that take real time (the land is built on a worker thread), which cost
  this PC more frames than they will cost the bot. `check.sh` green.

---

## 2. PLAYTEST section

## v2.4.2: your report on d6c1f58 and 91128e7 (this push)

B-013 to B-016 are fixed, all in probes, plus one line in the land's watchdog. `docs/CHANGELOG.md` (v2.4.2)
has the evidence.
- **B-013 (v202 hung):** the probe held the whole run to a 60th of a second a frame, and the land's watchdog
  took those held frames for fast ones. On your box the land drew its dearest effects (SSAO, 2× MSAA, four
  shadow splits) in software through every held moment. The watchdog now sees your real frames and steps the
  land down as the game does on a slow machine. The probe holds a 60th only around the clash.
- **B-014 (v22, "then Dad's assault on Mill"):** a battle moves on by itself 2.6 s after it ends. The probe
  waited a minute of your frames there, then fought the next battle by mistake. Fixed.
  **The crash (signal 11) didn't reproduce here** in 15 runs. If it comes back, send the lines after
  `handle_crash` (a debug build of Godot gives function names), your Godot version and your renderer.
- **B-015 (v21, "-1 left standing"):** the same trap at a battle's end. Fixed.
- **B-016 (v24p, the token meshes):** it's your Godot version, not llvmpipe. Before Godot 4.7 an antialiased
  line is drawn about a pixel wider than asked, and the meshes are matched to 4.7's lines. v24p now holds the
  meshes to their 4.7 picture (`tools/shots/ref/v24p_tokens.webp`) on any Godot, and to the old drawing as
  well on 4.7 or later. Its log names your Godot, its renderer and how wide it draws a 2 px line
  (`PROBE Godot …`): say what it says.
- **Poke:** `PROBE_SECS=5400 ./scripts/probes.sh v202 v21 v22 v24p`. All four should pass.
  - Send each probe's `done` line and its `lap` lines (each part's frames and seconds), so we can see where
    your box's time goes.
  - Here, as your box (`PROBE_ARGS=--box=40`), they took 2,234, 1,246, 1,692 and 1,243 frames. Yours should
    need fewer: some waits take real time, not frames.
  - If v202 still runs out of time, its laps say which part ran long.
- **New in the harness** (`tools/probe.gd`): `PROBE_ARGS=--slow=MS` makes every frame take MS longer to draw,
  as yours do (`--box` only moves the game on). Also `p.secs()` (a wait in game seconds) and `p.lap()`.
- **Which Godot do you run?** This brief says 4.5.1; the PC and Dad's build are on 4.7.1.

---

## 3. CLAUDE.md gotcha

- **The bot's box draws a frame every second or more** (software GL), so `p.frames(N)` is N/60 of a
  second only at 60 frames a second. A wait that means time is `p.secs(t)`. A moment a probe samples
  needs `p.steady(true, step)` around it (a quarter of a second costs a fast machine nothing), and
  `steady()` takes hold from the next frame. See the box here with `PROBE_ARGS=--box=40` (its leaps)
  or `--slow=MS` (its slowness). (v2.4.2: B-013 to B-016)
