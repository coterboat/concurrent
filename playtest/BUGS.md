# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| B-018 | broken | tools/first_war.gd step 2 stalls at round 6 in the cinema and cascades | ec97c35 | [2026-11-04-1943-ec97c35](reports/2026-11-04-1943-ec97c35.md) |
| B-017 | broken | v204 "sits in the land" fact expects the seating coat v2.5 removed on Compatibility | ec97c35 | [2026-11-04-1943-ec97c35](reports/2026-11-04-1943-ec97c35.md) |

### B-018: tools/first_war.gd step 2 stalls at round 6 in the cinema and cascades
- repro:
  1. `XDG_DATA_HOME=<empty dir> DISPLAY=:5 $G --path . --script res://tools/first_war.gd -- step=1` (passes, 0 failed, 530 s)
  2. the same with `step=2`
- error: `WALK FAIL the war stood still for 30 s at 5|6|orders|-|24|false (the draft , rolling , seating [], claim wait false, whose turn -)` then `WALK FAIL the war plays to its end (round 6, nobody won)`, `WALK FAIL the ending is shown`, `WALK FAIL a button to click was missing`, `WALK FAIL back on the title, nothing left to continue` (5 failed, 976 s)
- suspect: `tools/first_war.gd:184-191` the 30 s wall-clock watchdog keys only on phase/round/plan_step/theater/claimed/cinema._waiting; phase 5 is CINEMA with `_waiting` false and the theater hidden, so a long cinema on llvmpipe (acted on only every 15 frames, `:228-230`) never changes the mark. Not proven: a real stuck cinema would read the same.

### B-017: v204 "sits in the land" fact fails on Compatibility: the probe still expects the seating coat v2.5 removed there
- repro:
  1. `cd /home/box/playtester/concurrent && DISPLAY=:5 GODOT=/home/box/playtester/godot/godot PROBE_SECS=5400 sh scripts/probes.sh v204`
- error: `PROBE FAIL known24: and sits in the land (its plate's lime toned down, its foot darkened: 0 of 33)` / `PROBE FAIL world30: ... 0 of 52`
- suspect: `tools/shots/v204.gd:76-82` counts `material_override.next_pass`; `game/world3d/scenery.gd:458-459` (32031a4) now returns early on `gl_compatibility`, and v25 asserts `0 coated` on the same renderer. The two probes contradict each other on this box.

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| B-016 | v24p token meshes don't match the old drawing (glitch; first seen d6c1f58) | 1953944 (v2.4.2) | 2026-11-04 |
| B-015 | v21 reports -1 left standing (broken; first seen d6c1f58) | 1953944 (v2.4.2) | 2026-11-04 |
| B-014 | v22 never sees the musket shots fly (broken; first seen bacccac) | 1953944 (v2.4.2) | 2026-11-04 |
| B-013 | v202 border-clash probe hangs (broken; first seen bacccac) | 1953944 (v2.4.2) | 2026-11-04 |
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
