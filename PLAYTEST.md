# Playtest brief

For anyone testing CONCURRENT, and above all the owner's playtest bot, which runs on every push to
`main`. The newest version is at the top: what changed, and what to poke at. The standing checks
further down apply to every push.

## Getting the whole game

- **A plain clone has everything.** Art, audio and films are in ordinary git (no Git LFS), so
  `git clone https://github.com/coterboat/concurrent` or `git pull` brings the complete game.
  If a picture or sound ever looks like a 130-byte text file beginning `version https://git-lfs`,
  the repo has moved to LFS: run `git lfs install && git lfs pull` and see `docs/ASSETS.md`,
  "Storage".
- **Godot 4.5.1**, the editor build (the tests and probes are scripts, so an exported game can't
  run them).
- **Import once per fresh checkout**, before anything else: `godot --headless --path . --import`
  (the `.godot/` cache isn't in git).
- `review/` and `assets/raw/` are gitignored on purpose. They hold takes waiting for review and
  the masters, not the game.

| What | Command | Passes when |
|---|---|---|
| All tests | `godot --headless --path . --script res://tests/runner.gd` | the last line is `CONCURRENT ok passed=N failed=0` |
| One screenshot probe (needs a display, e.g. Xvfb) | `SHOT_DIR=/tmp/shots godot --path . res://tools/probe.tscn -- --script=res://tools/shots/<name>.gd` | it prints no `FAIL` lines and the PNGs look right |
| The probes | `calls input ui dice v13 v14 v14b v15 v16 v17 v18 v19 v110 v111` | |
| The text CLI | `godot --headless --path . --script res://tools/cli.gd -- play --seed 42 </dev/null` | a clean exit |
| AI wars | `godot --headless --path . --script res://tools/arena.gd -- map=known24 n=6 seats=general,veteran,recruit,hask seed=500` | no `VIOLATION` or `SCRIPT ERROR`, and the fingerprint below |
| Tool tests | `python3 tools/review/test_review.py && python3 tools/ludo/test_notes.py` | `OK` |

A GDScript runtime error doesn't quit headless Godot: it hangs. Treat a run that stops printing
as a crash, and grep the output for `SCRIPT ERROR`.

## How to report

Keep the format of the reports so far. One line per finding, the commit tested at the top:

`B1 file:line — what happens. repro: <command>. expect: <what should>. (game | tooling)`

Say which were checked and found fine too. "v1.10 melee Fortune: offered to the defender, rethrow
shown: fine" is as useful as a bug.

## Not bugs (by design)

- **A human's Fortune is never spent automatically.** The game offers the favour and waits, even
  with auto-roll on.
- **Clashes and scrambles have no Fortune calls.** The stars show dimmed with "no calls in a
  free-for-all".
- **A line the game starts on its own waits for the one being spoken**, and is dropped after 5 s.
  Only a click or key may cut in, and Space or Enter skips.
- **The Marches duel is short and brutal.** One side almost always conquers.
- **Old saves replay under the rules they were played with** (`map.rules`). A v1.8 save plays
  v1.8 Fortune.
- **Probes run with films off** (`motion = "paintings"`). `v19` turns them on.

## v1.11: the review table learns (this push)

Mostly tooling: the review table, and how assets get made. What reaches the game:

- **Speech bubbles and subtitles no longer show `*stars*`.** A line like "They dare to sit in
  \*my\* capital?" printed its stars.
  - **Poke:** play a few rounds and watch the commanders' bubbles and the eliminated card.
    `grep -n '\*' game/data/lines.json` lists the lines that carry stars.
- **The volley flash is timed to the shot again.** The redone standing and kneeling volley sheets
  had lost their `shot`/`muzzle` marks, so the flash fell back to default timing.
  - **Poke:** in any battle (probes `v111`, `v18`), the flash and smoke should leave the muzzle as
    the dice land, not before and not from the soldier's chest.
- **The eliminated film is re-encoded smaller** (Theora q5).
  - **Poke:** `v19` plays it; it should look the same as before.
- **Fingerprints (Mac, 27 Sep 2026)** for `arena.gd -- map=<m> n=6 seats=general,veteran,recruit,hask seed=500`:
  `known24` → `5ccf6e1a9a75`, `world30` → `fdc5601fe4b7`.
  - **Poke:** a different fingerprint on Linux, with no code change between the two runs, means
    the engine isn't deterministic across machines. That would break shared saves: please report it
    first. CLI matches: `cli.gd -- dump --seed 1` → `finalHash=1cce342a`, seed 2 → `a71862b8`,
    seed 3 → `6946e2ea`.

## v1.10: Fortune in every fight (still worth poking)

- Every fight earns Fortune now: clashes, melees, the scramble for spoils. Expect about 1.8–2.1
  favours per commander per war (`arena.gd` prints it).
  - **Poke:** a long human war where the human never gets a favour.
- **Fortune in melees.** The defender, or the commander of any attacking front, can call on it
  after a bad exchange, and the exchange is thrown again for everyone in it.
  - **Poke:** the favour is taken from the right commander (the roster stars), and the rethrow
    shows.
- **Second-wave surges.** A surge into a land your own direct attack just took marches in to hold
  it; a surge into a land that held storms what's left.
  - **Poke:** conservation. No armies appear or vanish (the report's totals).
- **Ties are re-fired.** An even volley is thrown again as its own labelled throw.
  - **Poke:** never four or five dice in one throw without the "fired again" label.
- **The final chart is the same size in all three modes**, with capital markers inside it and
  labels that don't overlap.
  - **Poke:** 1440×900 and larger windows.
- **The CLI and the v13/ui probes** (your B1–B3 from `f5ee031`) should all pass now.

## Standing checks (every push)

- All tests, every probe, the tool tests, and the CLI with `</dev/null`.
- A soak: `arena.gd` on `known24`, `world30` and `isles24`, n=20, with both `deal=draft` and
  `deal=random`. No `VIOLATION` or `SCRIPT ERROR`, and every war ends.
- Screens fit **1440×900**: setup, settings, How to Play, game over. Look for clipped text and
  buttons off-screen.
- A save made mid-war loads and replays to the same world hash (the tests do this; a real save from
  a probe run is better still).
