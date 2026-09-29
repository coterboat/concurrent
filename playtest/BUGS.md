# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|

none.

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| B-008 | land tooltip lists one merged column once per origin (glitch; `game/ui/land_tip.gd:35-39`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-007 | Esc during battle zoom-in opens battle screen instead of skipping (glitch; `game/ui/cinema.gd:246`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-006 | round banner one round behind during battles (glitch; `game/ui/game_screen.gd:426`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-005 | human seat possessive reads "You's" (glitch; `game/ui/recap.gd:141`, first seen 0b2fe07, [report](reports/2026-09-28-2108-0b2fe07.md)) | 373d7a3..412335d (v1.13.1) | 2026-09-29 |
| B-004 | review lessons test never sees `_test_*` batches (broken; `tools/review/review.py:467` vs `tools/review/test_review.py:29`, first seen 5d5d2a1, [report](reports/2026-09-27-2314-5d5d2a1.md)) | 8616731 | 2026-09-28 |
| B-003 | ui.gd 11_game_over.png showed round 2 regroup, not game over (glitch; `tools/shots/ui.gd:103-114`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-002 | cli.gd play spins forever on stdin EOF (broken; `tools/cli.gd:178-180`, `:210-212`, read `:278-280`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-001 | v13 shot probe crashes godot (crash; `tools/shots/v13.gd:220` closed cards dialog after `_turn()` freed it, first seen f5ee031) | ec9bced | 2026-09-27 |
