# playtest bugs

running ledger kept by bug clerk from playtester's reports. one file per red run lives in `playtest/reports/`.

## open

| id | severity | title | first seen | latest report |
|---|---|---|---|---|
| B-004 | broken | review lessons test never sees `_test_*` batches | 5d5d2a1 | [2026-09-27-2314-5d5d2a1](reports/2026-09-27-2314-5d5d2a1.md) |

### B-004: review lessons test never sees `_test_*` batches
- area: tooling (review table / v1.11 lessons), not the game
- repro:
  1. `python3 tools/review/test_review.py` from repo root
- error: `StopIteration` at `tools/review/test_review.py:590`: `pause = next(t for t in ls["themes"] if t["theme"] == "pause")` in test_note_themes_and_lessons
- suspect: `tools/review/review.py:467` (lessons() skips `name.startswith("_")`) vs `tools/review/test_review.py:29` (`TAG = "_test_" + secrets.token_hex(3)`), so the fixture batch is filtered out
- expected: `python3 tools/review/test_review.py && python3 tools/ludo/test_notes.py` both OK

## fixed

| id | title | fixed in | date |
|---|---|---|---|
| B-003 | ui.gd 11_game_over.png showed round 2 regroup, not game over (glitch; `tools/shots/ui.gd:103-114`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-002 | cli.gd play spins forever on stdin EOF (broken; `tools/cli.gd:178-180`, `:210-212`, read `:278-280`, first seen f5ee031) | ec9bced | 2026-09-27 |
| B-001 | v13 shot probe crashes godot (crash; `tools/shots/v13.gd:220` closed cards dialog after `_turn()` freed it, first seen f5ee031) | ec9bced | 2026-09-27 |
