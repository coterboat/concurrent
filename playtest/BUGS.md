# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| B-014 | broken | v22 never sees the musket shots fly, and the fall-timing fact gets no samples | bacccac | [2026-10-20-2218-d7a840b](reports/2026-10-20-2218-d7a840b.md) |
| B-013 | broken | v202 border-clash probe never sees the winner, then hangs on a script error | bacccac | [2026-10-20-2218-d7a840b](reports/2026-10-20-2218-d7a840b.md) |

### B-014: v22 never sees the musket shots fly, and the fall-timing fact gets no samples
- repro:
  1. `cd /home/box/playtester/concurrent && DISPLAY=:5 GODOT=/home/box/playtester/godot/godot sh scripts/probes.sh v22`
- error: run 1 `PROBE FAIL the shots fly: 4 seen, each from the side that won its pair at the men facing it across the field (1 sides fired)` and `PROBE FAIL the first man falls as the first ball reaches him, never before it (0 volleys timed, 0 early)`; run 2 `PROBE FAIL the shots fly: 0 seen … (0 sides fired)`, `PROBE FAIL a moment with a thread and shots in the air was caught (v22_01)`, `PROBE FAIL the first man falls as the first ball reaches him, never before it (1 volleys timed, 1 early)`
- suspect: `tools/shots/v22.gd:229` and `:314` (samples `dio.tracers` once per frame); tracers may spawn and finish between frames at this box's frame rate. Counts change run to run, so possibly frame-rate sensitive, but it fails every time here. Tags, threads, colours, Fortune rebate line and free-for-all ordering facts all pass.

### B-013: v202 border-clash probe never sees the winner, then hangs on a script error
- repro:
  1. `cd /home/box/playtester/concurrent && DISPLAY=:5 GODOT=/home/box/playtester/godot/godot sh scripts/probes.sh v202`
- error: `PROBE FAIL the dice land and the clash knows its winner (red)` then `SCRIPT ERROR: Invalid access to property or key 'meet' on a base object of type 'Dictionary'.` at `_clash (res://tools/shots/v202.gd:180)`; probe never quits (killed after 900 s). Same on both runs.
- suspect: `tools/shots/v202.gd:180` indexes `b.drawn_clash["meet"]` with no empty check (line 183 has one); underlying: `game/board/map_board.gd:1055-1056` returns before setting `drawn_clash` once `w >= 1.0` (CLASH_PUSH 0.65 s), after `:813` cleared it, so a frame carrying `winner` may never be drawn at this box's low software-GL frame rate. Facts before the break (meet head-on, camera lean-in, lands clear of the card) all pass.

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| B-012 | recap lead-change line "takes the lead from You." / "You takes the lead from ..." (glitch; `game/ui/recap.gd:50`, first seen cd3b208, [report](reports/2026-09-29-1253-cd3b208.md)) | 115854f (v1.14) | 2026-10-01 |
| B-011 | claiming phase reads "You's pick" (glitch; `game/ui/command_bar.gd:322`, first seen cd3b208, [report](reports/2026-09-29-1253-cd3b208.md)) | 115854f (v1.14) | 2026-10-01 |
| B-010 | defeat notice reads "You has been defeated" (renders "YOU HAS BEEN DEFEATED") (glitch; `game/ui/game_screen.gd:1810`, first seen cd3b208, [report](reports/2026-09-29-1253-cd3b208.md)) | 115854f (v1.14) | 2026-10-01 |
| B-009 | land tooltip region line reads "You holds it all" / "You holds N of M" (glitch; `game/ui/land_tip.gd:57`, first seen cd3b208, [report](reports/2026-09-29-1253-cd3b208.md)) | 115854f (v1.14) | 2026-10-01 |
| B-008 | land tooltip lists one merged column once per origin (glitch; `game/ui/land_tip.gd:35-39`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-007 | Esc during battle zoom-in opens battle screen instead of skipping (glitch; `game/ui/cinema.gd:246`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-006 | round banner one round behind during battles (glitch; `game/ui/game_screen.gd:426`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-005 | human seat possessive reads "You's" (glitch; `game/ui/recap.gd:141`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-004 | review lessons test never sees `_test_*` batches (broken; `tools/review/review.py:467` vs `tools/review/test_review.py:29`, first seen 5d5d2a1, [report](reports/2026-09-27-2314-5d5d2a1.md)) | 8616731 | 2026-09-28 |
| B-003 | ui.gd 11_game_over.png showed round 2 regroup, not game over (glitch; `tools/shots/ui.gd:103-114`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-002 | cli.gd play spins forever on stdin EOF (broken; `tools/cli.gd:178-180`, `:210-212`, read `:278-280`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-001 | v13 shot probe crashes godot (crash; `tools/shots/v13.gd:220` closed cards dialog after `_turn()` freed it, first seen f5ee031) | ec9bced | 2026-09-27 |
