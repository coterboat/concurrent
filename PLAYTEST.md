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
| Every probe (needs a display, e.g. Xvfb) | `GODOT=godot ./scripts/probes.sh` (or name some: `./scripts/probes.sh v112 v113`) | it ends without `probes: failed:`. Each probe's `ok`/`FAIL` lines are facts about the picture (three armies on three grounds, no arrow left for a dead column): a `FAIL` is a bug, even when the PNG looks fine |
| One screenshot probe | `SHOT_DIR=/tmp/shots godot --path . res://tools/probe.tscn -- --script=res://tools/shots/<name>.gd` | it prints no `FAIL` lines and the PNGs look right |
| The short check before a commit | `GODOT=godot ./scripts/check.sh` | it ends without `check: FAIL` |
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

## v1.13: the map says what the engine knows, and the big moments land (this push)

No rule changes: new games still play **rules 20**, and every save replays as before (the arena
fingerprints below v1.12 are unchanged). Everything here is what the table shows and says.

- **Last round's columns carry their fate.** The faint arrows you plan over now say what happened:
  a red cross where a column was thrown back (or fell back, or lost the scramble), and a column
  beaten in a border clash stops halfway, where it died, with a cross there. Hover the land for the
  words ("Varek's 7 were thrown back by Dad.").
  - **Poke:** probe `v113`, and any war on the Isles or the Ring. `tests/test_v113.gd` checks every
    column's fate against the world in whole AI wars on three maps; tell us any cross that sits on a
    land the column actually took, or a clash with no half-arrow.
- **A sword plate on your lands that could be outnumbered next round**, with the most one enemy
  could bring. Your capital rings crimson as soon as it could be outnumbered at all. It updates as
  you place recruits and give orders.
  - **Poke:** it should never cover a number or the garrison shield, and on a crowded map it
    shouldn't be on every land (it needs about 1.5× your men and 3 more).
- **An amber dashed ring (supply maps): a land that holds the road home for others.** The tooltip
  names them; sealing an order that leaves one with a single man warns you.
- **Region pips** beside each region's bonus: one per land, in its holder's colour, biggest holder
  first; a pulsing ring on the last land someone needs. The tooltip adds "Varek holds 5 of 7" and,
  for a region with three ways in or fewer, where they are (Great Vane: two).
- **The land tooltip** now says all of the above; the roster shows each commander's recruits for
  next round (+N); the recruits' breakdown adds up to the total (capital and levée included, only
  lands in supply paying; it used to leave them out). A cut-off land's recruit message no longer
  says "at most 0 (1 + your -1 neighbouring lands)".
- **The recap** tells melees held, scrambles won, fall-backs and capitals taken (it used to skip
  them), names a border clash by the road it was fought on, and opens with a new leader or a
  capital won back.
- **The moments, played harder:**
  - **Against all odds:** any battle won with under a 30% chance, whoever fought, gets a gold shout,
    a fanfare, and "Decided, against N% odds" under the bar. The report's cards say it too.
  - **The last man:** a side down to one man against three or more gets "ONE MAN LEFT" and a
    drum roll; winning with him gets "THE LAST MAN STANDING!". The advisor's close-call lines now
    always play.
  - **The lead:** a new leader on points opens the recap with a flag snap, the roster's crown pops
    across, and the advisor says so when it's our lead won or lost.
  - **The endgame music carries through** the regroup, the battles and the recap of the last rounds
    (it used to drop back to the ordinary themes). The ending's music starts with the tally,
    after the film, not ducked under it; when an AI wins, the advisor's defeat line follows theirs.
  - A capital's fall filmed: the commander's line now plays after the film (it was cut off). The
    court fleeing raises a flag (a sound). The capital-choosing line is voiced.
  - **Poke:** the voice queue. Several moments in one round (a lead change, a region, a capital)
    must never talk over each other or leave the music ducked.
- **Tooling:** `scripts/check.sh` (the short pre-commit check, ~10 s: compile, tool tests, the
  newest test file) and `scripts/probes.sh` (every probe, failing on any `FAIL`, `SCRIPT ERROR` or
  hang). `tools/test_one.gd` no longer plays sessions into the real save slot.
  - **Poke:** `GODOT=godot ./scripts/probes.sh` under Xvfb end to end: it should end without
    `probes: failed:`. `v112` now also checks where each army stands in a three- and a five-way
    scramble.

## v1.12: the fled court, a fairer Thousand Isles, a war you can hear

New games play **rules 20**.

- **A three-way scramble looks like one.** When three or more commanders march on an empty land, each
  army gets its own ground: left, right, and a row at the back that turns to face whoever it fires
  at. Each ring stands over its own army.
  - **Poke:** probe `v112`, and any war with 4–5 commanders. No two armies should share a side as if
    allied, and nothing should overlap the odds bar.
- **A fallen capital's court** flees to the land deepest among the commander's own (not the biggest
  stack), with one fresh troop and the garrison dug in to the full.
  - **Poke:** conservation and the report (`tests/test_v112.gd` checks both), and what the AI does
    with a capital that's now thinly held.
- **Map amendments.** The Thousand Isles' Great Vane pays 3 under rules 20. A rules 19 save still
  pays 4.
  - **Poke:** load an old Isles save. It must replay (no hash mismatch), and the region labels must
    show the old bonus.
- **Border clashes** clear the beaten column's arrow, even when you skip past its card.
  - **Poke:** Battles: mine, several AI clashes, Space through the report. No arrow may be left for
    a column that died in the field.
- **The war around you:** distant sounds while planning (on the ambience slider), smoke over lands
  that changed hands, and the map's light warming toward dusk in the last rounds.
  - **Poke:** it should never hide a token or number, the seat colours must stay readable at dusk,
    and it should be silent at Ambience 0.
- **B-004 fixed** (the lessons test needed local review data).
- **Fingerprints (Mac, 28 Sep 2026, rules 20)** for `arena.gd -- map=<m> n=6 seats=general,veteran,recruit,hask seed=500`:
  `known24` → `f782eba38886`, `world30` → `d9f01fe55802`. The CLI hashes below are unchanged (the
  CLI plays the old rules).

## v1.11: the review table learns

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
- **Fingerprints (Mac, 27 Sep 2026, rules 19: superseded by v1.12's above)** for `arena.gd -- map=<m> n=6 seats=general,veteran,recruit,hask seed=500`:
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
