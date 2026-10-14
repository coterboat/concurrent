# RV-005: are the hostile reviews finding real things, or inventing them?

10 Oct 2026. The owner: "let's do one more pass with the critics - it should tell us if our hostile
reviews are truly finding new stuff or inventing stuff."

## How it was measured

- **Plants (recall).** The packet was built from a copy of the v2.2 tree with three bugs planted in
  the code under review, of known severity, where the gates don't catch them (check.sh was green on
  the planted copy, as it would be for a real escaped bug). The reviewers weren't told.
  - **P1, high, engine:** in a melee, an invader's Fortune call credits the rebate to the spender
    (`rebate[pid]`), not the defender (`engine/resolve.gd`, the `side == "a"` branch).
  - **P2, medium, client state:** the field's plate names (`LandField._tags`) are never reset between
    battles, so a plain assault after a melee shows "from Ridge" on its plates.
  - **P3, low, client state:** `Diorama.clear()` doesn't free shots still in the air.
- **Two reviewers, one packet** (RV-005, 310 KB, the whole uncommitted diff, aimed at v2.2):
  Grok and Codex, independently, through `relay.mjs`.
- **Every unplanted finding verified twice.** I checked each against the real code. A blind verifier
  then checked all eight claims against the pre-fix tree without seeing my verdicts. It was a fresh
  Sonnet agent, read-only, given only the goal and the claims, and the plant claims were included as
  known-true controls.

## Results

| | Grok | Codex |
|---|---|---|
| Findings | 3 | 5 |
| Plants caught | **3 of 3** (P1 as its F1 high; P2 and P3 together as F2 medium) | **2 of 3** (P1 high, P2 rated high); missed P3 (low) |
| Unplanted, real | 1 (F3, confirmed) | 3 (F4 confirmed; F3 and F5 partial) |
| Invented | **0** | **0** |

- Grok F3 and Codex F4 are the same bug, found independently: in a melee with two Fortune calls, the
  narration read the battle's summed rebate, so one call named a commander owed for the other. That
  leaves 3 distinct real bugs that weren't planted, all new (none repeats RV-001..RV-004). All three
  are fixed and pinned:
  - **Per-call debts.** `owed` on each Fortune call, and `_owed_by` for a call answered live.
    `test_v22 _each_call_its_own` fails without it.
  - **Free-for-all order.** A free-for-all's pairs are laid out in field order (probe v22, 2 facts).
  - **Fall timing.** The first man falls when the first ball lands (probe v22: 8 volleys, 0 early).
- The plants' classes are pinned too. `_each_call_its_own` would catch P1 (an invader's call owes only
  the defender). Probe v22's "nothing of the melee comes with it" catches P2: with P2 put back in the
  real tree it failed, showing `["from Ridge", "from Harbor"]` on the next assault's plates.
- **The blind verifier agreed with every verdict on real-vs-not (8 of 8).** It marked three as partial
  where the claim overstates. Codex F3: the tags don't point at the wrong pair. Codex F5: the early
  fall is up to ~0.06 s, and only for volleys of a few men. Grok F2: the shots half expires on its own
  within 0.4 s. That matches the severities: P3 was planted as the low one.
- Neither reviewer was packet-only in fact: both said on their canary line that they could see tools
  or a workspace. Both said their findings came from the packet, and their line numbers were the
  packet's (2 to ~470 lines off the real files), which fits.

## Against the earlier rounds

RV-001 to RV-004 (Grok only, the v2.0.1 to v2.1 work): 14 findings, 7 confirmed, 2 partial,
**5 rejected**. All five rejects were confident claims that the code didn't do something it did:
"the train is never toppled", "_place has no lift arm", "no fromIds", "Esc is swallowed", "a split
surge is dropped". All were misreads of a large cross-cutting diff, and our verification caught each
one before it was acted on.

## What it says

- **They find real things.** This round: 5 of 6 plant-catches across the two reviewers (the miss was
  the most benign plant), 3 real new bugs on top, and nothing invented. Both reviewers caught the high
  engine plant, the one that would have mattered.
- **They do invent, sometimes.** Over all five rounds Grok has invented 5 of 17 (29%), always the
  same way: a confident "X never happens" about code that does it. This round's 0 of 8 is one round,
  on a narrow, well-aimed packet. That's encouraging, but it's not proof the rate has changed.
- **So the verify step is what makes them safe to use.** Act on no finding until it's checked against
  the code. The blind second check agreed with mine every time this round. For a contested reject,
  it's a cheap way to rule out author bias.
- **The two reviewers are worth running together on a milestone.** They overlapped on one bug.
  Otherwise Grok was sharper on state leaks (it caught P3, which Codex missed) and Codex on timing
  and goal gaps (its F3 and F5).
