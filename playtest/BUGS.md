# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| B-012 | glitch | recap lead-change line "takes the lead from You." / "You takes the lead from ..." | cd3b208 | [2026-09-29-1253-cd3b208](reports/2026-09-29-1253-cd3b208.md) |
| B-011 | glitch | claiming phase reads "You's pick" | cd3b208 | [2026-09-29-1253-cd3b208](reports/2026-09-29-1253-cd3b208.md) |
| B-010 | glitch | defeat notice reads "You has been defeated" (renders "YOU HAS BEEN DEFEATED") | cd3b208 | [2026-09-29-1253-cd3b208](reports/2026-09-29-1253-cd3b208.md) |
| B-009 | glitch | land tooltip region line reads "You holds it all" / "You holds N of M" | cd3b208 | [2026-09-29-1253-cd3b208](reports/2026-09-29-1253-cd3b208.md) |

all four: grammar for a human seat named "You" (play critic reports, confirmed by playtester). the probe lives on the shared box, not in the repo.

### B-012: recap lead-change line "takes the lead from You." / "You takes the lead from ..."
- repro:
  1. run the probe (on the shared box, not in the repo; ring26, You (human) + Captain Oren + Governor Quill (AI), RSEED=1):
  ```sh
  G=/home/box/playtester/godot/godot; R=/home/box/playtester/scratch/bugs5/concurrent; OUT=/home/box/playtester/runs/cd3b208-you
  cd $R && DISPLAY=:5 RSEED=1 SHOT_DIR=$OUT/shots timeout 400 $G --path $R res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs5/you5.gd > $OUT/02_you5_seed1_final.log 2>&1
  grep -E "PROBE (DRAFT|TIP|RECAP r[0-9] shown|MODAL|CINEMA|THEATER|SEEN)" $OUT/02_you5_seed1_final.log
  ```
  2. seed 1, natural
- error: r2 recap `Captain Oren takes the lead from You.`; r1 recap `You takes the lead from Captain Oren.`
- suspect: game/ui/recap.gd:50, raw name_of on both sides instead of Style.says/Style.who
- coverage: not reported

### B-011: claiming phase reads "You's pick"
- repro:
  1. run the probe (on the shared box, not in the repo; ring26, You (human) + Captain Oren + Governor Quill (AI), RSEED=1):
  ```sh
  G=/home/box/playtester/godot/godot; R=/home/box/playtester/scratch/bugs5/concurrent; OUT=/home/box/playtester/runs/cd3b208-you
  cd $R && DISPLAY=:5 RSEED=1 SHOT_DIR=$OUT/shots timeout 400 $G --path $R res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs5/you5.gd > $OUT/02_you5_seed1_final.log 2>&1
  grep -E "PROBE (DRAFT|TIP|RECAP r[0-9] shown|MODAL|CINEMA|THEATER|SEEN)" $OUT/02_you5_seed1_final.log
  ```
  2. seed 1, human's turn in claiming phase; read command bar tally and top-left plate
- error: `tally="You's pick"` (shot 01); turn 2 `plate_phase="You's pick" tally="You's pick"`
- suspect: game/ui/command_bar.gd:322 and game/ui/game_screen.gd:433, raw name_of instead of Style.owns (style.gd:206)
- coverage: not reported

### B-010: defeat notice reads "You has been defeated" (renders "YOU HAS BEEN DEFEATED")
- repro:
  1. run the probe (on the shared box, not in the repo; ring26, You (human) + Captain Oren + Governor Quill (AI), RSEED=1):
  ```sh
  G=/home/box/playtester/godot/godot; R=/home/box/playtester/scratch/bugs5/concurrent; OUT=/home/box/playtester/runs/cd3b208-you
  cd $R && DISPLAY=:5 RSEED=1 SHOT_DIR=$OUT/shots timeout 400 $G --path $R res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs5/you5.gd > $OUT/02_you5_seed1_final.log 2>&1
  grep -E "PROBE (DRAFT|TIP|RECAP r[0-9] shown|MODAL|CINEMA|THEATER|SEEN)" $OUT/02_you5_seed1_final.log
  ```
  2. default DEFEAT_ROUND=3; on RECAP _maybe_defeat_notice() runs (game_screen.gd:289)
- error: `PROBE MODAL r3: You has been defeated`, shown in all caps by the Cinzel font (shot 03)
- suspect: game/ui/game_screen.gd:1810 (`"%s ha%s been defeated"` with "s" for one seat)
- coverage: not reported

### B-009: land tooltip region line reads "You holds it all" / "You holds N of M"
- repro:
  1. run the probe (on the shared box, not in the repo; ring26, You (human) + Captain Oren + Governor Quill (AI), RSEED=1):
  ```sh
  G=/home/box/playtester/godot/godot; R=/home/box/playtester/scratch/bugs5/concurrent; OUT=/home/box/playtester/runs/cd3b208-you
  cd $R && DISPLAY=:5 RSEED=1 SHOT_DIR=$OUT/shots timeout 400 $G --path $R res://tools/probe.tscn -- --script=/home/box/playtester/scratch/bugs5/you5.gd > $OUT/02_you5_seed1_final.log 2>&1
  grep -E "PROBE (DRAFT|TIP|RECAP r[0-9] shown|MODAL|CINEMA|THEATER|SEEN)" $OUT/02_you5_seed1_final.log
  ```
  2. seed 1, hover Goldmarch in round 2 planning (any land of The Crown)
- error: `The Crown  (+7) · You holds it all` (shot 02). r1: `The Crown  (+7) · You holds 5 of 6`, `The Emberfen  (+3) · You holds 3 of 4`. r3: `The Crown  (+7) · You holds 4 of 6`
- suspect: game/ui/land_tip.gd:57 and :59 in _region(), raw name_of instead of Style.says (game/core/style.gd:220)
- coverage: not reported

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
