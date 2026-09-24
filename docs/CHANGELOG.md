# Changelog

The bible says amendments come with a dated entry and the test or band that justified them. Everything below has both.

## v1.0 — 24 Sep 2026: from kernel to game

The wheel is unchanged: simultaneous commit, attackers vacate, convergence, the fixed queue, the placement cap, and hidden intent on a public map. Combat is still size + 1d6 with ties to the attacker on invasion. v1.0 builds the rest of a game around it.

### New

- **2–5 seats, any mix of humans and AI.** `Setup.deal(map, seats, seed)` deals evenly and leaves the leftovers unoccupied (3.1). Two seats still get the Neutral doorstop (3.9). Player pools are set per map and player count (`pools` in each map file).
- **AI commanders** (`engine/ai.gd`). A heuristic planner reads only the public map. It cashes sets, regroups toward the front, and picks attacks by expected value (region swings, cards, kills, the leader) minus expected losses and the risk of being walked in an emptied origin. It surges breakthroughs, then places for defense and staging. In the final round it goes all in. Hard commanders draft several sheets and play each one out against predicted enemy sheets with invented dice, never the match seed, then keep the best.
  - Arena, Isthmus: Veteran beats Recruit 67%, General beats Recruit 72%.
  - Arena, Known World 3p: General wins 48% against two Veterans, where a coin-flip seat would win 33%.
  - `tests/test_ai.gd`: every AI sheet is legal across all maps and seat counts, and matches are deterministic.
- **Cards** (3.7), on the Known World and the Wide World. They are drawn from a seeded stream, so the deck needs no state on World. The rules follow bible 3.7; see the amendments below.
- **The Wide World**, 30 lands in 6 regions (L4: 28–32 / 5–6). The Heartlands are the rich but leaky center (+5, five doors). Every other region has three doors.
- **Painted geography for every map** (`tools/mapgen`). The rules graph is authoritative: two lands that are not adjacent never share a land border, because a channel is carved between them, and adjacent pairs that don't touch become dashed sea lanes. `mapgen` fails loudly if the geography would contradict the graph.
- **The client:**
  - title, setup and the game table
  - an order sheet with odds as words, which also shows the odds if the enemy fully reinforces
  - the battle cinema with dice, round reports, the end-of-war chart
  - illustrated rules, a scripted tutorial on the Isthmus, and the advisor
  - hotseat cover screens, a planning clock, settings, autosave/continue, music and sound
- **Assets** from Ludo.ai: 42 images and 27 audio files. The prompts are in `tools/ludo/manifest.json`.

### Amendments

1. **Known World: Crest–Silk became Crest–Steppe.**
   - **Why:** Crest–Silk and Haven–Steppe crossed each other in the Eastshore, so one of them had to be drawn as a sea lane running over land. The map would have lied about its own graph.
   - **Effect:** Eastshore keeps three ways in (Peak, Crest and Reef) and still has exactly two frontier lands.
   - **Checked by:** `mapgen known24` reports no crossings, and `tests/test_maps.gd` (west↔east, the northern route, the Southern Rim) still holds.

2. **The opening's two placement passes fold into one sheet with twice the cap.** Bible 3.1 already calls for a second simultaneous pass after a scattered deal. Both passes are sealed before any reveal, so one sheet at 2 × (1 + friendly neighbors) is the same game with half the clicks.
   - **Checked by:** `test_cards.gd` checks the opening cap, and `test_maps.gd` places the full 21 on a Known World 2p deal. With a single capped pass, scattered deals left armies with nowhere to go.

3. **Sets cashed in the same round all pay the table value at lock**, and the counter then advances by the number cashed.
   - **Why:** ordering by seat would pay the first seat less for a simultaneous act.
   - **Checked by:** `test_cards.gd` has two players trading in the same round, and both receive 4.

4. **An eliminated player's hand goes to whoever captured their last land**, meaning the latest capture of one of their lands in queue order (3.1). If the last land was only emptied, the hand is discarded. `test_cards.gd` covers this.

5. **Hand limit: at 5 cards you don't draw.** There is no forced cash. The sheet warns, and five cards always hold a set (proved in `test_cards.gd`).

6. **Neutral leftovers can be deeper than 1** (`neutralLeftoverArmies`). The Wide World 2p uses 2, so ten Neutral lands aren't free walk-ins.

7. **Game length is a setup option.** The default is the map's rounds: 5 for the Isthmus, 8 for the Known World, 10 for the Wide World. Short (×0.75), long (×1.5) and conquest (no limit) are also available. Domination at 80% still ends the game early.

### Bands after v1 (arena, `tools/arena.gd`)

| Map / seats | Rounds (median) | Early ends | Walk-ins per game | Even-fight attacker win |
|---|---|---|---|---|
| Known World, 5 AI | 8 | 1/30 | 11.4 | 64% |
| Wide World, 4 AI | 10 | 2/30 | 12.1 | 58% |
| Wide World, 5 commanders | 10 | 2/30 | 16.5 | 52% |
| Known World, 2p + Neutral | 7 | 28/40 | 3.5 | 55% |

Walk-ins, the game's hook, happen many times a game on the full maps. Two-player Known World often ends in domination before round 8. Nothing needs changing for v1, but watch it.

### Fixed while building

- The cinema's replay ignored that dug-in defenders absorb losses first, so it could show the wrong count on a held land (`game/view_events.gd`).
- The `.mp3` that Ludo sometimes returns is really a WAV. The generator now trusts the bytes.
