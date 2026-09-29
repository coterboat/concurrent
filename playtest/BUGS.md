# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| B-008 | glitch | land tooltip lists one merged column once per origin | 0b2fe07 | [2026-09-28-2108-0b2fe07](reports/2026-09-28-2108-0b2fe07.md) |
| B-007 | glitch | Esc during battle zoom-in opens battle screen instead of skipping | 0b2fe07 | [2026-09-28-2108-0b2fe07](reports/2026-09-28-2108-0b2fe07.md) |
| B-006 | glitch | round banner one round behind during battles | 0b2fe07 | [2026-09-28-2108-0b2fe07](reports/2026-09-28-2108-0b2fe07.md) |
| B-005 | glitch | human seat possessive reads "You's" | 0b2fe07 | [2026-09-28-2108-0b2fe07](reports/2026-09-28-2108-0b2fe07.md) |

all four: game glitches, no crashes. the probe script lives on the shared box at `/home/box/playtester/scratch/bugs4/ring3.gd`, not in the repo.

### B-008: land tooltip lists one merged column once per origin
- repro:
  1. run the probe: `RSEED=1 timeout 300 godot --headless --path . res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs4/ring3.gd` (exit 0, ~110 s; probe is on the shared box, not in the repo: ring, standard rules, You vs Oren + Quill, battles "mine", human orders from Varek AI profile)
  2. seed 1
- error: `TIP after r3 Ivorymarch: Last round: You's 7 took it. You's 3 took it.` (arrows silvermarch->ivorymarch x7, thethrone->ivorymarch x3); same at Goldmarch after r1, Emberwatch after r2. play critic saw `Governor Quill's 5 took it. Governor Quill's 2 took it.` at Greywatch.
- suspect: `game/ui/land_tip.gd:35-39` with `game/core/last_round.gd:60-81`. one arrow per sent column, each given the merged column's fate; tooltip prints a sentence per arrow with no origin, reading as two columns both taking the land. column-fate logic itself is correct (same commander's columns merge).
- coverage: none for tooltip text (test_v113 checks fates only; v113 probe tooltip covers a single-arrow land)

### B-007: Esc during battle zoom-in opens battle screen instead of skipping
- repro:
  1. run the probe with `ROUNDS=2 ESC_ROUND=2`: `RSEED=1 timeout 300 godot --headless --path . res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs4/ring3.gd` (exit 0, ~110 s; probe is on the shared box, not in the repo: ring, standard rules, You vs Oren + Quill, battles "mine", human orders from Varek AI profile)
  2. Esc pressed during the camera swoop, after the report asked for the theater, before it shows
- error: `ESC r2: pressing Esc during the swoop (cinema._active=true _waiting=true theater.visible=false phase=5)` then `ESC r2: after Esc -> theater.visible=true theater._state=ready ... _theater_off=false`. control `ESC_MODE=theater` gives `theater.visible=false cinema._theater_off=true`.
- suspect: `game/ui/cinema.gd:246` (returns while waiting), `game/ui/battle_theater.gd:457` (returns while not visible), `game/ui/cinema.gd:740` (0.8 s zoom), `game/ui/game_screen.gd:1995-1997` (marks Esc handled, does nothing, in report phase)
- coverage: none (tools/shots/ui.gd:86, v15.gd:115/166 call skip directly, never send Esc)

### B-006: round banner one round behind during battles
- repro:
  1. run the probe: `RSEED=1 timeout 300 godot --headless --path . res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs4/ring3.gd` (exit 0, ~110 s; probe is on the shared box, not in the repo: ring, standard rules, You vs Oren + Quill, battles "mine", human orders from Varek AI profile)
  2. seed 1, read banner each frame
- error: `during battles of round 3: Round 2 of 10|world.round=3|pending=true (3560 frames)` then `Round 2 of 10|world.round=4|pending=false (108 frames)`; round 2 shows `Round 1 of 10` for 7890 frames. recap correct.
- suspect: `game/ui/game_screen.gd:426` with `game/core/session.gd:629-640`. banner shows world.round-1 in the battle report, but when one of your battles pauses for a call, _run enters the report without _absorb (session.gd:637), so world.round is still current; banner not redrawn after absorb. round 1 hidden by floor at 1; only rounds with a paused player battle.
- coverage: none

### B-005: human seat possessive reads "You's"
- repro:
  1. run the probe: `RSEED=1 timeout 300 godot --headless --path . res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs4/ring3.gd` (exit 0, ~110 s; probe is on the shared box, not in the repo: ring, standard rules, You vs Oren + Quill, battles "mine", human orders from Varek AI profile)
  2. seed 1
- error: `Captain Oren beat You's column on the road between Cinderhow and Saltwatch.` also `Captain Oren took You's capital, The Throne.`, `Walk-in: Captain Oren took The Throne while You was away.`, tooltip `You's 2 were beaten by Governor Quill...`
- suspect: `game/ui/recap.gd:141` (+:112 :137 :147), `game/core/last_round.gd:148` :163, `game/ui/land_tip.gd:41`. all build `"%s's" % s.name_of(pid)`; name_of (session.gd:195) returns seat name "You"; no possessive helper; recap doesn't use Style.says (style.gd:206), hence "You was".
- coverage: none (v113 probe and tests/test_v113.gd use name "Dad")

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| B-004 | review lessons test never sees `_test_*` batches (broken; `tools/review/review.py:467` vs `tools/review/test_review.py:29`, first seen 5d5d2a1, [report](reports/2026-09-27-2314-5d5d2a1.md)) | 8616731 | 2026-09-28 |
| B-003 | ui.gd 11_game_over.png showed round 2 regroup, not game over (glitch; `tools/shots/ui.gd:103-114`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-002 | cli.gd play spins forever on stdin EOF (broken; `tools/cli.gd:178-180`, `:210-212`, read `:278-280`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-001 | v13 shot probe crashes godot (crash; `tools/shots/v13.gd:220` closed cards dialog after `_turn()` freed it, first seen f5ee031) | ec9bced | 2026-09-27 |
