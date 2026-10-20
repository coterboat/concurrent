<!-- RV-006, reviewer claude-fresh: a fresh Claude subagent given only the rubric (coter-kit outside-review
rubric.md) and the packet docs/reviews/packets/RV-006.md (sha256 9d6b9660ba7909ca08448f33115aee932d241c3bc08983ce942c668c851092c1),
told not to read the repository. Grok was not signed in on the Windows PC and Codex isn't installed there, so this
round is less independent than a Codex or Grok round. Its reply, as it gave it: -->

CANARY: packet only
(I read the rubric and RV-006.md, all 6,388 lines. The only other tool call was one Grep over the packet file itself, to list its section headings. I opened, searched and ran nothing else.)

Line numbers are new-file lines worked out from the hunk headers, with the packet line in brackets where that helps.

### F1 · medium · correctness
File: engine/combat.gd:414, 433-435 (packet 1744, 1763-1765)
Claim: Three or more fronts are priced too kindly, by about 7 points even in the smallest case. This optimistic price is what the AI uses to decide it has brought enough men, and it is what the order card, the dispatch and the advisor show a first-time player. Take the packet's own melee model (each front fires one volley a salvo at the defenders' whole line; an even volley costs nobody) and three 1-man columns storming a land held by 2:
- `fronts_capture_rate([1,1,1], 2)` folds this into `_two_fronts(2, 1, 2)`, which gives 0.658.
- The exact three-front chain gives 0.589. Each 1-man front fires 1 against 2, so it wins 15/36 and loses 21/36 with no ties: P = P(≥2 wins) + P(exactly 1 win) × 0.5 = 0.376 + 0.425 × 0.5.
Merging small fronts into one "rest" column gives them the rest's firing line (min(sum, 5)) instead of their own, so the gap grows when the rest is several small columns (for example [6,2,2,2]). The AI makes exactly these patterns: `_take` adds sources in offer order, and the new `while p_win < p_want` loop (ai.gd:693, `want = got + 2`) can add a third front and stop early on the inflated price. That breaks the stated goal that it "no longer walks into a split it can't win".
Evidence: the combat.gd comment admits "three or more are priced as the biggest against the rest together, a little kind to the attacker". The only three-front test (test_v23.gd:71-72) compares `[4,4,3]` with a different two-front split `[8,3]`, not with real battles. The battle check (test_v23.gd:70, n=300) and `tools/study/fronts.gd:32-43` test two fronts only, so "within 2–4 points across the whole table" (CHANGELOG) covers two fronts only.
Fix: price k fronts exactly, with a memo keyed on the sorted tuple of fronts (cheap at realistic sizes). Or, at least in the AI, use the true lower bound: the two largest fronts only. An extra front can only add defender losses, so this never overstates. Add a three-land storm checked against `Resolve`.
Confidence: high on the arithmetic and the gap; medium on how often the AI builds 3+ fronts.

### F2 · medium · test-gap
File: tests/test_v23.gd:80-113 (`_ai_split`); engine/ai.gd:644-656
Claim: Acceptance criterion 6 ("under rules 20 its plans are byte-for-byte what they were", citing "test_v23 AI cases") has no test behind it.
- Under rules 20, `_ai_split` only checks that `splits[20] > 0`. No sheet is compared with the old planner.
- The arena evidence ("`fronts=false` reproduces the old planner", meaning the old fingerprint 548347c5f849) is not in the packet.
- The rules-22 check is circular. It prices the AI's own split with the AI's own `fronts_capture_rate`, allows 0.17 of slack (line 110), and assumes the defender holds exactly 6. So it can't show a split is winnable in real battles.
Reading the code, the rules-20 path looks identical: `_fronts()` is false, `_build` runs once on the same sorted offers, and `_take` returns the same got, froms, places and used_place. Saved AI sheets also keep replay independent of the planner. So the practical risk is low, but the claim is unproven.
Fix: in test_v23, compare a rules-20 plan, and a `fronts=false` plan under rules 22, packet for packet against a stored pre-change sheet, or assert the arena fingerprint 548347c5f849 with `fronts=false`.

### F3 · low · performance
File: engine/combat.gd:453-477
Claim: `_two_fronts` touches about (hi+1)(lo+1)(d+1) states for each defender bonus. Every state rebuilds two 36-pair `_volley_odds` tables (144 `fire()` calls), and the recursion goes hi+lo+d deep. The static memo is never cleared. A late-game split of 40+40 against 40 means about 70k states and roughly 15–20M GDScript operations, i.e. seconds of stall the first time the planner (or an order card) prices it. Bigger conquest stacks grow cubically.
Fix: `_volley_odds` depends only on (min(a, line), min(d, line + bonus)); precompute that small table once. Fill the table bottom-up instead of recursing, or cap exact pricing at a size and fall back to a bound above it.

### F4 · low · reliability (macOS)
File: tools/review/review.py:1084-1087
Claim: The swap of `python3` for `sys.executable` is not limited to Windows. On the Mac, batch actions now run under whatever interpreter started the review server, not the `python3` on PATH. That is only "the same python3" (as the comment says) if `scripts/review.sh` and `Review Table.command` start the server with that same binary. The packet doesn't show those scripts. If the server is started with `/usr/bin/python3` (Apple's 3.9) while the actions' packages live in Homebrew's python3, actions that worked before fail on the owner's machine.
Fix: gate the swap on `os.name == "nt"`, or only when `shutil.which("python3")` is missing or is the WindowsApps stub. That leaves the Mac exactly as it was.

### F5 · low · reliability / data-loss (Windows only; macOS unchanged)
File: tools/ludo/ludo.py:160-167, 189-198
Claim: Three problems with the Windows ledger lock and swap:
- `msvcrt.locking(..., LK_LOCK, 1)` is never unlocked.
- `LK_LOCK` raises `OSError` after about 10 one-second tries, yet the holder can sit inside the lock for up to 5 s in the `os.replace` retry loop. With a scanner holding the ledger (the case the loop exists for), a second or third generator can time out in `record()`.
- After 20 failed tries, the final `else: os.replace` raises.
Both failures happen after the asset has been paid for, so its ledger entry (job, url, credits) is lost. The `time.sleep` path also needs `time` imported, which the packet doesn't show. On macOS the `fcntl` path is unchanged.
Fix: unlock in a `finally`; use `LK_NBLCK` in a retry loop with a long or no deadline; if the swap fails, write the entry to a side file instead of raising.

### F6 · low · maintainability (cross-machine data)
File: assets/ludo_ledger.json (e.g. 16334, `"file": "assets\\raw\\v20\\land\\blockhouse_b.glb"`, and every new `side_files` list); tools/ludo/ludo.py:321
Claim: `record()` now writes Windows separators into the committed ledger: 21 model entries and 24 picture entries, mixed in with forward-slash entries. Any Mac or Linux reader that resolves `file` or `side_files` will miss them. The fix to `take_out` covers one path but not this class (OS-native paths written into shared JSON). The new `"/".join` in `take_out` also returns `/.takes/...` (the filesystem root) when `out` has no directory; `os.path.join` returned `.takes/...`.
Fix: normalise paths to "/" inside `record()` and rewrite the existing entries. Build `take_out` with `os.path.join(...).replace(os.sep, "/")`.

### F7 · low · overclaim
File: docs/CHANGELOG.md (packet 1627-1630); tools/ludo/v20_content.py:272 (REDRAWN); tools/ludo/manifest.json
Claim: The changelog says all 25 were "drawn again and modelled". The ledger diff has no new model for camp_b, oasis_b, quarry_b or village_desert_b, and no new picture for village_desert_b, yet the manifest moves all of them to v2. Landmarks that depend on those (possibly the Wide World's Mirage and Kelwell) may still be missing. The next ludo run on the Mac will try to make them.

### Open questions (not checkable from the packet)
- Audio: if `_duck(false)` or anything else sets the music player's `volume_db` back to 0.0, every music take loses its gain after the first spoken line. `_crossfade(take)` must also get a bare take name for `MUSIC_DIR + take` to match a key. Nothing tests that a gain is actually applied; criterion 7's probe only checks that files exist.
- `_vkey`'s packing isn't shown. If it uses fixed-width fields, `hi*1000+lo` could spill into the `d` field. The fronts memo also omits `Combat.line`; that is safe only if `line` is always 0 or 5 while fronts apply.
- Other AI paths that add men to an existing attack (top-ups, search tweaks) would create splits nobody priced. They aren't in the diff.
- Callers of `income_left()` not in the diff (hotseat cover screen, board hints, voice cues) may still ask about recruits with no room.
- Does `Session.odds()` cap each land at six on a pass? `odds_into` hands the uncapped per-land sums to `fronts_capture_rate`.
- The only gate shown is check.sh, which runs tests through test_one.gd. The repo's own notes say that can pass what tests/runner.gd fails. A full-suite and probe run after the change isn't evidenced.
- The new `.png.import` and `.gd.uid` files are untracked and were made by Godot 4.7.1. If the Mac has its own untracked copies, `sync_main.sh`'s fast-forward will refuse to pull.

### What looked correct
- Replay and outcomes: nothing in resolve changed, and the combat.gd additions are new functions; `odds_word` → `word_for` gives the same words; capping `income_total()` in the opening can't change any complete deployment; the rules < 21 AI path is unchanged as far as reading the code shows (F2 is about proof only); the static memo caches a pure function.
- `fronts_capture_rate` for two fronts: the recursion always ends; the both-even self-loop is normalised correctly; the denominator is at least 1 − (6/36)²; the memo is its own dictionary; one front, no firing line, or one decisive roll falls back to `capture_rate`; when the defenders reach 0, at least one front is always still standing.
- First-time-player flow: `placeable_left()` and `no_room()` add up; every prompt the diff changed uses `placeable_left()`; the game still asks whenever any land has room.
- Python on macOS: KEY=value parsing, the `fcntl` lock, `encoding="utf-8"`/`newline="\n"`, the POSIX kill branch, the test helpers and the ffmpeg path are unchanged on the Mac.
