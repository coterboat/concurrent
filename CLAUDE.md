# CONCURRENT: working notes

A Napoleonic simultaneous-orders conquest game (Risk-like, everyone moves at once) in
Godot 4.5.1 / GDScript, made to be good enough for everyone to play (it began as a game
for the owner and their dad). Art, audio and voices come from Ludo.ai. This file holds the
rules of the road for working in the repo. `README.md` covers how to play,
`docs/CHANGELOG.md` has every rule change and the evidence behind it, `docs/ASSETS.md`
covers the asset pipeline, `docs/PROMPTING.md` covers how we prompt for assets (and what the
reviews taught us), and `PLAYTEST.md` is the testers' brief.

## The owner's standing instructions

- **Commit or push only when asked.** The owner commits. If asked, end the message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Secrets:** `LUDO_API_KEY` lives in `.env.local`. Never print, log or commit it.
- **Never kill the owner's Godot.** They often have the game open, sometimes from a
  translocated `Godot.app`. Stop only processes you started, matching on your own
  script path (e.g. `pkill -f res://tools/arena.gd`).
- **Ludo credits: spend freely**, but check the balance (`getAccount`) before a big run and
  report what was spent.
- **The advisor's cloned voice is the good one.** Never replace a voiced line with a
  Ludo-generated voice (cutscenes carry no speech; the game speaks over them).
- **Imperial theme, unflinching.** Don't sanitize flags, uniforms or war imagery.
- **Don't make review verdicts for the owner.** Generate into a review batch; they accept
  or reject.
- Probes and tests must never save the owner's settings.

## Commands (Godot is `~/Downloads/Godot.app/Contents/MacOS/Godot`, `$G` below)

| What | Command |
|---|---|
| Before a commit (~10 s; the pre-commit hook runs it) | `./scripts/check.sh`: compile, tool tests, the newest `test_vNN.gd` and any test changed (+ view/properties/match when `engine/` or `session.gd` changed). `./scripts/check.sh --install` sets the hook up in a checkout |
| Compile every script (seconds) | `$G --headless --path . --script res://tools/compile_check.gd` |
| Full test suite | `./scripts/test.sh` → ends `CONCURRENT ok passed=N failed=0` (a few minutes) |
| One test file | `$G --headless --path . --script res://tools/test_one.gd -- tests/test_v110.gd` (it can print `failed=0` over a `SCRIPT ERROR`: grep for it, or use `check.sh`) |
| Every probe, as facts (windowed, ~15 min) | `./scripts/probes.sh` or `./scripts/probes.sh v112 v113`: fails on any `FAIL`, `SCRIPT ERROR` or hang |
| One screenshot probe (windowed) | `SHOT_DIR=/some/dir ./scripts/shot.sh v18` (`calls`, `input`, `dice`, `v13`…`v19`, `v110`…`v113`) |
| AI arena (balance) | `$G --headless --path . --script res://tools/arena.gd -- map=known24 n=40 seats=general,veteran,recruit,hask deal=draft levee=3` |
| Review table | `./scripts/review.sh`, or the owner double-clicks `Review Table.command` in the repo folder (port 8765; if it's already running it just opens the page) |
| What the reviews taught us | `python3 tools/review/review.py lessons` (`W` in the table) |
| Tool tests | `python3 tools/review/test_review.py && python3 tools/ludo/test_notes.py` |
| Repo size | `./scripts/repo_size.sh` (plain git, no LFS: see `docs/ASSETS.md`, "Storage") |
| Pull what the bot pushed | `./scripts/sync_main.sh` (automatic: a hook runs it every prompt) |
| Generate assets | `python3 tools/ludo/ludo.py <ids>` or a `tools/ludo/vNN_content.py` script |
| Voices, free on this Mac | VoiceStudio running (`http://127.0.0.1:3900`), then `python3 tools/voicestudio/vs_samples.py` (see `docs/ASSETS.md`) |

Arena switches: `rules=`, `deal=draft|random`, `levee=`, `capitals=0|1`, `fortune=0|1`,
`fbar=`/`ffloor=` (try a Fortune bar or floor), `supply=`, `traits=`, `line=`, `battle=`.
It prints wins, length, capitals, Fortune, and drama (lead changes, wins from behind,
close finishes). Compare variants **on the same seeds**, 40+ wars each, and treat a few
points as noise.

## Outside eyes

- A **playtest bot** (the owner's Grok agent) runs on every push to `main` and reports findings
  (e.g. "B1 … crash signal 11"). Treat its report as a bug list: reproduce, fix, and say which
  were fixed. It flags tooling bugs as well as game bugs.
- **It pushes to `main`** (reports in `playtest/`, the running ledger in `playtest/BUGS.md`). So
  local main must be current before any work: `scripts/sync_main.sh` fetches and fast-forwards it
  (never merges, never touches uncommitted work). The project hooks (`.claude/settings.json`) run it
  at the start of every session and before every prompt, and it speaks only when something came in.
  **If it names new playtest files, the open bugs in `playtest/BUGS.md` come first.** Leave the
  ledger to the bot's clerk; say which B-numbers you fixed in the reply and the CHANGELOG.
- **`PLAYTEST.md` is its brief:** how to get and run the whole game, what's by design, and per
  version what changed and what to poke at (checklist step 7). Put there anything you want tested
  on another machine. The arena's `fingerprint` line is a cross-machine determinism check.
- **The owner's review notes are the other outside eyes.** `docs/PROMPTING.md` is the playbook
  they built: read it before writing a line or a prompt. After a review round, run
  `python3 tools/review/review.py lessons --write docs/PROMPTING.md` and fold any new pattern into
  its rules.
- **The bot is a playtest helper, not CI.** It catches things on a clean Linux clone after a push.
  The gate before a commit is ours: `scripts/check.sh` (the pre-commit hook), and `probes.sh` for
  anything that changes the picture.

## How the work is run

- **One writer.** One Claude session writes code. The bot writes only `playtest/`; Grok reads and
  reviews. If the owner may be playing from this tree, work in a `git worktree` beside it (copy
  `.godot/` in with `cp -Rc` to skip the import) so a running Godot never hot-reloads half-done code.
- **A version is a session.** When a version is in and the owner has played it, the next one starts
  in a fresh session from the top of `docs/CHANGELOG.md`, `PLAYTEST.md` and `playtest/BUGS.md`, not
  from a summary of a summary.
- **Peel, don't rewrite.** `game_screen.gd`, `battle_theater.gd` and `session.gd` are big. When a
  version touches a piece of one, move that piece into its own file in the same change, with its
  probe. No cleanup passes for their own sake, and never "tidy" `session.gd` or `engine/`: that is
  how replay breaks.
- **Probes assert facts.** The kernel tests can't see the picture. A probe's `p.ok()` states what
  the screen must say (three armies on three grounds, no arrow left for a column that died), so a
  regression fails without anyone squinting at a PNG.
- **No new systems** unless a play session asks for one in a way the arena can see. Polish,
  legibility and moments come first. (Parked: online play, AI diplomacy.)

## Gotchas that have bitten before

- **zsh doesn't word-split** `$var`. `cmd $args` passes one argument. Use `${=args}`, an array, or a
  script file. (Once this made the arena load a map called `known24 n=40 …`.)
- **A GDScript runtime error doesn't quit headless Godot.** It hangs. Always check the
  output for `SCRIPT ERROR`, and kill your own stuck runs by script path.
- Run probes one at a time when the owner's Godot is open. v13 has hung under contention;
  rerun it alone.
- `Style.tex()` caches a missing texture as null for the whole run. New art needs a restart
  (and `$G --headless --path . --import`).
- Godot plays only **Ogg Theora** video. Use `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` (the
  plain `ffmpeg` has no Theora).
- **Voice lines queue** (`Audio.voice`): a line the game starts on its own waits for the one
  being spoken (and is dropped after 5 s); only a line that follows the player's own click or
  key may cut in, and Space/Enter skips. Faces show their bubble when their line starts. The
  battle report and auto-rolled battles hold a few seconds for a line to finish.
- Probes run with films off (`tools/probe.gd` sets `motion = "paintings"`); `v19` turns them on.
- `ready` is a member of every Control. Don't name a variable `ready` (a parse error that
  fails every script that preloads it).
- **Media stays in plain git** so the playtest bot's clone is complete. Encode for size (Theora
  `-q:v 5`, webp, mp3). When the history nears ~1 GB, raise the LFS migration with the owner
  (`docs/ASSETS.md`, "Storage"). Don't start it without them.
- **A firing or falling sheet needs its marks** (`shot`/`muzzle`, `down` in its json). A redo that
  can't find them says "NO SHOT/FALL MARKS" in its review check. `v19_content.py --remark <name>`
  re-reads them.
- **Voice text carries direction.** `*stars*` and `...` in a line are for the voice; `Lines.text()`
  strips the stars for subtitles. A note's direction goes in the manifest's `speak`, never into the
  words.
- **Anything that runs a Session must fence the save slot first** (`Session.SAVE_PATH` to a test
  path, `Settings.persist = false`). `runner.gd`, `probe.gd` and `test_one.gd` do; a new entry point
  that plays rounds would otherwise overwrite, then clear, the owner's `user://savegame.json`.
- Screens must fit **1440×900**: the setup screen (the Rules row replaced five rows for this)
  and the settings panel are near the limit. Screenshot-check after adding rows.

## The engine's laws (engine/)

- **Deterministic.** Every random number comes from `Rng.derive_stream(match_seed, round,
  key)`. No `randi()`, no `randomize()`, no Nodes, no UI in `engine/`. A save is its setup
  plus every round's sheets, **replayed**, and each round's world hash must match.
- **Rules are versioned.** `map.rules` is stamped into a game at creation
  (`session.gd` `_apply_length`: new games get the latest). **Any change to outcomes
  must be gated** `if map.rules >= N`, so older saves replay exactly as they were
  played. Bump N, default new games to it (`session.gd`, `tools/arena.gd`), and test both
  sides of the gate.

  | rules | version | what it gates |
  |---|---|---|
  | 15 | v1.5 | surges clash head-on and carry a count |
  | 16 | v1.6 | land cards (a land on every card), card draws |
  | 17 | v1.7 | Amendment 18: fair ties (an even volley is fired again); a pass holds six, surges and reserves included |
  | 18 | v1.9 | Fortune's ledger kept exchange by exchange (`luck` on each invasion); a war chest divided by dice among everyone who took the last lands |
  | 19 | v1.10 | every fight feeds Fortune's ledger (clash/spoils odds, `luck` on melees and scrambles); Fortune can be spent in a melee (`defCalls`, fronts' calls); a second-wave surge whose land already fell marches in |
  | 20 | v1.12 | a fallen capital's court flees deep into its own lands (not to the biggest stack) with its guard: one fresh troop and the garrison dug in to the full; map amendments (the Thousand Isles' Great Vane pays 3) |

- **A map change that affects play is an amendment, not an edit.** Add it to the map json's
  `amendments` list (`{"since": N, "lanes": [[a, b]], "regionBonus": {id: n}, "why": …}`): setting
  `map.rules` applies it (the `MapDef.rules` setter), so a save replays on the map it was played on.
  A new lane also needs its entry in `maps/art/<id>_art.json` (the board hides it under older rules;
  `tools/study/lane.gd` finds the coast points). Measure a map change with a `tools/study/` script.
- Rules that a table chooses (capitals, Fortune, levée, surges, terrain, the deal…) live
  in `game/core/rules.gd` with their help text, and presets there (**Standard** is the
  version we balance around). The config is saved with the game, and loaded games default
  each switch to *off* so old saves stay as they were.
- New serialized state is written **only when set** (a world without capitals or Fortune
  hashes exactly as before).
- Events are the report. `game/view_events.gd` must be able to rebuild the world from
  them (the tests check `_view_agrees` every round).

## Adding a feature: the checklist

1. The engine change, gated by rules version if it changes outcomes.
2. Tests in `tests/test_vNN.gd` (registered in `tests/runner.gd`): the rule, the old rules
   untouched, conservation (`_conserved`), the report agreeing (`_view_agrees`), and
   whole wars replaying to the same hash.
3. The arena, when it touches balance: before and after on the same seeds.
4. UI, then a screenshot probe in `tools/shots/vNN.gd` whose `p.ok()` checks state what the
   screen must show, and `./scripts/probes.sh vNN`. Look at the screenshots too.
5. Words: the How to Play page (`game/ui/howto_screen.gd`), `rules.gd` help, `README.md`,
   and a dated `docs/CHANGELOG.md` entry with the evidence.
6. Voice lines, if a moment deserves one: add them to a `tools/ludo/vNN_content.py`, and
   they reach the game through a review batch. Write them (and any prompt) by
   `docs/PROMPTING.md`.
7. After meaningful gameplay changes, update PLAYTEST.md with what changed and what to poke at,
   or add a `playtest:` line to the commit message.
8. `./scripts/check.sh` passes (the hook runs it on commit), and the full suite before a push.
