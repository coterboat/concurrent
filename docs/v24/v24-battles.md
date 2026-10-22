# v24-battles: split storms that fall back, melee ties, the battle's end, the charge bugle

Branch `claude/v24-battles-1faa9d` (worktree `.claude/worktrees/v24-battles-1faa9d`), off `017a215`.
**Rules 23** (new games; old saves replay as they were played: rules-22 wars end on the same world hash as
before this change, three wars with 25 melees in them, in `tests/test_v24.gd`).

From Alex's notes on v2.3.1 (`concurrent_playtest_notes.txt`, 10-21), in the order given.

## 1. "Imre was dual invading … decided to fall back, but then nothing changed" (and Quill)

**What happened.** Since rules 21 a commander's columns from two lands are two fronts of a melee, and the
battle calls come front by front (`engine/resolve.gd` `_melee`). Officers judged each front *alone* against
the defenders' whole firing line (`Combat.doctrine(stance, f.a, d)`), and alone each column of a two-sided
storm looks lost. So one column fell back while the other fought on, and a later call took the rest. The
battle screen never took the column that left off the commander's count ("7 + 5" stayed), never repriced
the odds, and its line said only "Imre sounds the retreat to Harbor". That is the retreat that "changed
nothing", and the second one that took "the full army".

Reproduced headless before any change: Imre (officer's judgment), 7 from Ridge and 5 from Harbor against a
Gate of 10, 200 seeds: a column fell back alone 104 times. Quill (fall back if it turns): 70 times.

**The picture (every rules version, so old saves read right too).** `game/ui/battle_theater.gd`
- The column that falls back turns and leaves the field (the land's and the painted field's retreat; on the
  land its plate goes too). Its men come off its commander's count and show as gone home: `6  ↩4`, then `↩7`
  once all are home. The odds bar and its words count only the men still fighting ("6 attackers on 1 front
  against 8 defenders"), and so does the dial's "N vs M".
- The line says which column went and which fights on, kept short enough (under ~500 px, a probe fact) that
  a speaking commander's bubble doesn't cover it:
  - a lone commander's: "The column from Harbor falls back — the column from Ridge fights on"
  - yours: "Your column from Harbor falls back — the column from Ridge fights on"
  - among several commanders: "Governor Quill's column from Harbor falls back — …"
  - the last one, later: "The column from Ridge falls back too: the attack is called off"
  - together: "Admiral Imre sounds the retreat: both columns fall back" (a commander's fall-backs at one call
    are told as one retreat, not one column after another)
  - "… falls back to Mill" only when a column can't go home (its land was lost).
- The verdict for a commander whose whole attack fell back is his retreat: "ADMIRAL IMRE FALLS BACK — 7 SAVED"
  ("… FALLS BACK TO RIDGE — 5 SAVED" from one land), not "YOU HOLD THE GATE AGAINST ALL COMERS".
- The battle report's melee line (the battles you don't watch) says who fell back: "The column from Harbor
  fell back." (`game/ui/cinema.gd` `_fell_back_words`).
- The melee's odds bar is priced as the fronts it is (`Combat.fronts_capture_rate`, as the order card and the
  AI have priced a two-sided storm since v2.3), not as one army of their sum; a lone commander's reads
  "Admiral Imre: 56% to take The Gate". It is repriced when a whole salvo has been read off the table: a
  half-read salvo is a state the price's memo never meets, and pricing one costs ~100 ms for three fronts.

**The AI (rules 23).** A commander's fronts that carry the same standing order make **one call together**,
at once, on the odds of all his fronts still fighting (`Combat.fronts_doctrine`, `resolve.gd` `_officers`):
they fall back together, or throw in the reserves together. Two columns under different orders keep their
own (one to the last man, one careful: the careful one now goes when the *whole storm's* odds turn).
I chose a group call over judging each front in turn on the combined odds: in turn, a front with no
reserves could fall back an instant before its neighbour decided to call up its own, splitting them again.

**Your own two columns** are still asked one at a time (each has its own call), and the plate now reads
clearly: "Your call for the column from Harbor · both columns together: long shot — 36% to take it · with
the reserves: 44%"; send that one home and the next plate is "Your call for the column from Ridge · From
here: long shot — 13% …" (alone now). On auto-roll your officers' call comes from the engine (`pending`
carries `officer`), so a storm you watch on auto-roll calls exactly as one you skip.

Evidence (`tests/test_v24.gd`, 200 storms of 7 + 5 against a Gate of 10, the same seeds both sides):

| | a column fell back while the other fought on | The Gate taken |
|---|---|---|
| officer's judgment, rules 22 | 104 | 49 / 200 |
| officer's judgment, rules 23 | **0** (132 columns fell back; none left the other fighting) | **98 / 200** |
| fall back if it turns, rules 22 | 70 | 31 / 200 |
| fall back if it turns, rules 23 | **0** (144 fell back; none left the other fighting) | **93 / 200** |

So the AI's two-sided storms (which v2.3 taught it to send only when they're worth it as two fronts) were
being thrown away a column at a time; now they're fought as planned. The arena (known24, 40 wars, the same
seeds, draft, levée 3; `tools/arena.gd` now prints the split retreats):

| table | rules | wins | split retreats / game | assaults fell back | lead changes / won from behind / within 3 |
|---|---|---|---|---|---|
| general, veteran, recruit, hask | 22 | g 10, v 10, r 8, h 12 | 0.60 | 4% | 1.8 / 25% / 11 of 38 |
| | 23 | g 11, v 8, r 6, h 15 | **0.00** | 2% | 2.0 / 35% / 14 of 39 |
| general, quill, imre, hask | 22 | g 12, q 8, i 14, h 6 | 0.97 | 8% | 1.5 / 35% / 14 of 38 |
| | 23 | g 13, q 8, i 8, h 11 | **0.00** | 6% | 1.4 / 25% / 12 of 40 |
| same, fresh seeds (2000) | 22 | g 11, q 10, i 11, h 8 | 1.02 | 9% | 1.9 / 27% / 13 of 40 |
| | 23 | g 10, q 9, i 10, h 11 | **0.00** | 5% | 1.6 / 32% / 11 of 40 |

No violations in any of the 240 wars. Imre's 14 → 8 in the second table didn't repeat on fresh seeds (11 → 10):
noise. The one thing that moved the same way in all three tables is Hask (all in, never falls back): 12 → 15,
6 → 11, 8 → 11, so 26 → 37 of 120 wars. Each table alone is within noise, and the drama numbers go both ways,
but it is consistent. My read: the careful and judgment commanders used to save a column early and now fight
a failing two-sided storm on together (they fall back as one, later), losing a few more men than before, while
Hask never fell back anyway. Worth watching, not acting on yet.

## 2. "Rerolls in dual invasions don't re-roll if they tie on subsequent rolls"

**What the engine did.** In `_melee` an even volley cost nobody but *counted as one of the exchange's three*,
and was never fired again (an assault's has been fired again since Amendment 18, rules 17). **What the
screen showed:** "tie!" on the pair, a plate whose tooltip said "fired again", the rules saying "an even
volley is fired again", and, because a two-front melee throws two salvos in its first throw and one in its
second, a second throw that looked like the first one's ties re-rolled while its own ties never were.

**Rules 23:** a melee's even volley is fired again within its salvo, at the same line, until each front's
volley is decided, so an exchange is three decided volleys a front. On the table the even ones are thrown
again as a throw of their own under "EVEN VOLLEYS ARE FIRED AGAIN" (as an assault's are; the note sits over
the fronts' tags), the score line says so ("… Even volleys are fired again."), and an old save's plate no
longer claims it ("An even volley: nobody falls."). The fronts' price follows the rule (`Combat.refire`, set by
`use_rules`): [6, 5] against 9 priced 0.56, the battles took it 0.56 of 300; [4, 3, 3] against 7 priced
0.59, battles 0.61.

## 3. "Battles should automatically be exited after all dialogue lines are over instead of waiting to press space"

**Cause, double-checked.** In its "done" state the battlefield moved on by itself only when you weren't
"hands on": with Roll yourself on (the default) and men of yours still on the field it waited for Space. That's
every battle you win or hold, and every one you fall back from. The advisor has his verdict after a win or a
hold more often than not, hence "only when the advisor has something to say" (it also waited after your
retreats, when he's silent).

**Now** a finished battle moves on by itself, for everyone, once the lines are over: the winner's and loser's,
any line waiting its turn, and the advisor's verdict (scheduled after the winner's). Half a second of quiet,
never sooner than the 2.6 s it always held the verdict, never longer than 12 s. Space still moves on at once.
(`Audio.voice_waiting()` is new in `audio.gd` for it.) The probe: a battle you win rolling your own dice moves
on 7.7 s after its verdict, after Varek's line and the advisor's, with no key pressed.

## 4. "The pre-battle charge horns should only play once … also lower their volume a tad"

**Cause.** On the land, `play()` sounded the bugle as the land rose and again a moment later once it had
opened (each with its ±4% pitch: two takes, one behind the other). Now once: on the land as it rises, on
the painted field as it opens (a probe fact for each, via `Audio.tracing`). The charge *music* was checked
too: its takes open 6-10 dB under the bugle and fade in, so nothing in it stacks on the horn.

**3 dB lower:** `game/data/levels.json` `sfx/charge` -6.1 → -9.1, written through a new `EAR` trim in
`tools/audio/levels.py` ("the owner's ear, on top of the measure"), so re-measuring the mix keeps it.

## Tests and probes

- `tests/test_v24.gd` (30 facts, registered in `tests/runner.gd`): the split measure on hand-written fights;
  rules 23 columns fall back together (judgment and careful) and rules 22 untouched; mixed orders; reserves
  together; even volleys fired again (rules 23) and costing nobody as one of the three (rules 22); the fronts
  price against the battles; the call plate's `mine`/`officer` against the unwatched call (a melee's, and an
  assault's at a capital's walls); rules-22 golden
  world hashes; two rules-23 wars on known24 and isles24 (five commanders) legal, conserved, the report
  agreeing and replaying to the same world, with no split retreat; a new game plays rules 23.
- `tools/shots/v24b.gd` (28 facts, 12 shots): the old save's split retreat on the land (line, count, odds,
  the field, the verdict, the line's width, the battle report's line), rules 23's retreat together and a melee's even volleys fired
  again, your two columns asked one by one, the battle that ends by itself, one bugle on each field and its
  level, the How to Play pages saying it and fitting 1440×900 (with the garrison shield's two). It dry-runs the round on the session's own
  world to pick a seed where each moment happens, then plays it in the client.
- `./scripts/check.sh` green; the full suite `CONCURRENT ok passed=769 failed=0`; every probe (`./scripts/probes.sh`,
  windowed, on this PC): 33 of 33 ok, v24b's shots looked at (the retreat lines clear the commanders' bubbles,
  the re-fire note sits over the fronts' tags, both How to Play pages fit).

## Outside my list (small, needed by the bump)

- `tests/test_v22.gd`, `tests/test_v23.gd`: "a new game plays rules 22" became `>= 22` (the pattern test_v21
  already used).
- `tools/audio/levels.py`: the `EAR` trim (item 4).
- `game/core/session.gd`: only `_apply_length` (the default rules, 22 → 23).
- `CLAUDE.md`: the rules-23 row in the engine's table of rules versions.

## For the merge

- `tests/runner.gd`: my registration lines go right after V23Test's, where v24-map adds one too (a
  one-line conflict).
- `game/ui/battle_theater.gd` `play()`: the land path's one charge bugle is the `Audio.sfx("charge", -3.0)`
  inside the block that opens `_land_field` (v24-3d's part). I made the later, common-path bugle play off the
  land only, and didn't touch that block. If the land's opening moves, keep exactly one charge per battle
  opening; v24b checks it on both fields.
- `session.gd` `officer_call()` (nobody's) is now only a fallback: every pause for a call carries `officer`
  (below), and the battlefield's auto-roll uses it.

## What Alex should poke at

- Storm a land from two of yours and watch: each column is asked on its own, the plate quotes both together.
  Send one home: its men leave the field and the count ("5  ↩3"), and the line says which went and which
  fights on.
- Let Imre, Quill or Varek storm you from two sides: they fall back together now ("Admiral Imre sounds the
  retreat: both columns fall back"), and an old save's split retreat is shown for what it is.
- Melee ties: "EVEN VOLLEYS ARE FIRED AGAIN" on the table, the even pair thrown again.
- Win a battle rolling your own dice: it closes by itself after the last line.
- The charge bugle: once, a touch quieter.
- Balance: the AI's two-sided storms are no longer thrown away a column at a time. Does the AI feel pushier?

## Open questions

- **One call for all your columns?** You're asked column by column, as before: sending both home is F, then F
  again. A "fall back with every column" button would be a new control, so it's Alex's call: build it, or park it?
- **How long a won battle lingers.** It now moves on 0.5 s after the last line, never sooner than 2.6 s after the
  verdict (the probe's took 7.7 s, Varek's line and then the advisor's). If Alex wants longer to look at a battle
  he rolled himself, it's one number.
- **Hask** won a few more in all three arena tables (above). Watch it in play before touching anything.
- Not mine, noticed: the AI's Fortune doctrine in a melee (rules 19) weighs the attackers as one force; it
  predates v2.4 and changes nothing here. And the advisor's counsel (`game/core/counsel.gd`, `t-r2`) still says
  "the gold shield beside its number" (see below).

## After the merge (the coordinator's follow-ups, 10-21)

- **Every pause for a call carries the officers' call.** A plain assault's `pending` now carries `officer`
  (`Combat.doctrine` with the fortress's or capital's longer line, the very call made unwatched), and so does
  every melee front's, under any rules (`_officers` is rules-aware). So a battle watched on auto-roll calls
  exactly as one skipped; before, the session's `officer_call()` left the walls out. A field on the pause only:
  calls are recorded, so outcomes and old saves are untouched (the rules-22 golden hashes still hold). Test:
  120 assaults by a careful officer on a capital of 12, under rules 23 and 22: at 33 pauses the walls change
  the call, and the pause's `officer` is the unwatched call at all 120.
- **The garrison shield isn't always gold now** (v24-map's ranked shields, Alex's C4 still open): How to Play
  ("Attack — and leave home", "Digging in") and README's Garrisons line say "the shield beside its number" and
  what its look means: plain wood for the one man held back, then brass, steel and gold, gold on crimson for a
  fortress's or a capital's four. It's its own commit, so if Alex keeps the old shield it reverts in one. The
  advisor's counsel line (`counsel.gd`, nobody's file) still says "gold shield": the same one-word change.
