# Changelog

The bible says amendments come with a dated entry and the test or band that justified them. Everything below has both.

## v1.3 — 25 Sep 2026: the campaign pass

### Amendment 10: the melee

Before, when two commanders invaded the same land, they fought the defender one at a time, in an order set by a hash. The first invader soaked up the defenders, and the second often just mopped up. Now:

> When invaders of two or more commanders storm a held land, they fight it at once. Every salvo, each invader fights its own volley against the defenders, who split their strength across the fronts in proportion to the invaders: *score = 5 × die + defenders × this invader ÷ all invaders*. The loser of each volley loses one, so a defender can lose a man on every front in a single salvo, or win them all. Battle calls still come after every exchange, front by front. When the defenders fall, the surviving invaders fight each other for the spoils.

**Why split, not full strength on every front?** `tools/melee_sim.py` measured three candidate rules. With the split, a dogpile hits exactly like one combined attack of the same total, so being attacked from two sides is as dangerous as it should be. With full strength on every front, a defender held about as often as under the old one-at-a-time rule.

| 6 + 6 invaders vs 8 defenders | Defender holds |
|---|---|
| One at a time (v1.2) | ~40% |
| Split (v1.3) | 7% |
| One attack of 12 | 5% |

- **Where it applies.** A lone invader still fights an ordinary assault. The decisive-roll battle style keeps the old sequence.
- **Checked by** `tests/test_v13.gd`:
  - 300 melees, each with army conservation and the replay agreeing
  - both double losses and double wins seen in a single salvo
  - a live melee pausing for each watching invader's call and replaying from the saved sheets

### Amendment 11: the reinforcement phase

After the battles, everyone marches troops between their own neighbouring lands at the same time, before the next orders.

- **One land per soldier.** Only soldiers who were there when the phase began may leave, so nobody moves twice.
- **What stays.** Dug-in defenders never march, and a land with no dug-in defender keeps one soldier.
- **Simultaneous.** Moves only touch your own lands, so everyone's marches land together. Hotseat players each get the pass screen.
- **It replaces the old one-move regroup.** That regroup was written on the orders sheet before the battles. Old saves keep it.
- **The AI marches too.** Quiet lands send every spare man one step toward the front, and a well-held front lends to a hard-pressed neighbour.
- **The record.** The marches are saved with the round. A game saved between the battles and the marches resumes in the reinforcement phase.
- **Checked by:**
  - 10 session checks, covering clamping, no chaining, no marching into enemy land, the save, and replay to the same hash
  - AI marches that are legal and conserving on every map
  - whole wars replayed with their marches

### Amendment 12: surges belong to the land being taken

A surge is now ordered from the land you are attacking, not from each attack's origin (`Sheet.surges`). Every army converging on that land, from any direction, pushes on together with everything but one man.

- **The bug this fixes.** A second attack added after the surge was ordered used to cancel the surge.
- **Checked by:** armies converging from two lands surge on together (59 of 59 captures). A surge from a land nobody attacks is refused.

### Amendment 13: men, horses and cannon

New games deal campaign cards in three kinds: infantry, cavalry and artillery. There are no wild cards. Three alike or one of each turn in. Any five cards still always hold a set, and `test_v13` checks all 243 hands. Old saves keep their wild cards.

### Bands after v1.3

Arena, 60 games per matchup on the Known World and 30 on the Wide World, under all v1.3 rules:

| | v1.2 | v1.3 |
|---|---|---|
| General vs two Veterans (coin flip 33%) | 42% | 40% |
| Recruit vs two Veterans | 17% | 7% |
| General vs three Veterans, Wide World (coin flip 25%) | 37% | 43% |
| Melees per game (3 seats / 4 / 5) | — | 2.3 / 3.7 / 4.9 |
| Known World 3-seat games ending early by domination | 18% | 45% |

The reinforcement phase lets armies mass at the front, so wars are more decisive. More Known World games now end in domination before the last round, and the recruit, who plans without looking ahead, is punished harder.

### Seeing the war

- **Fights on the map.** Every fight in the battle report rings its lands in fire and dims everyone else, and only the arrows in play stay bright.
- **Border clashes.** Two columns meeting head on get a starburst with crossed swords on the border between them, a "BORDER CLASH!" banner and a drum-and-steel crash.
- **The camera swoops.** When your own troops fight, attacking or defending, the map rings the battle, pans and zooms in on it, and the battlefield opens out of the map. It eases back out afterwards.
- **Garrisons have their own number.**
  - A land's big number is its army, the soldiers who can march.
  - Dug-in defenders sit on a gold shield beside it.
  - A faint empty shield means nobody is dug in yet.
  - Cards and tips say "3 armies · 1 dug in" instead of adding them together.
- **Orders.** Attack and march cards have a ✓ OK button (and Enter) as well as the ✕.
- **Cards on the table.** The Cards button opens your hand as painted cards. Pick three, or let it pick the best set, and turn them in. It says what a set is worth right now.
- **Wording.** Placing new troops is now "recruits", so "reinforcement" means the phase after the battles.

### The battlefield grows up

- **Risk pieces.** Armies are counted in Risk pieces: a cannon for every 10, a cavalryman for every 5, and infantry for the rest.
  - A loss that can't come from the men topples a horse, and four men march up to make change.
  - The same goes for a cannon: it becomes a horse and four men.
- **New tin figures and moves** (Ludo):
  - A dragoon on a base plate that idles, gallops, charges and rears.
  - A field gun with crew that idles, fires with a big smoke burst and reloads.
  - Infantry now also kneel and fire, reload, charge with the bayonet, and cheer.
  - Every sheet is checked for clipping and loop seams. The breathing idles play back and forth where their loops weren't seamless. Kneel-and-fire and the cheer rise out of the stance, played in a custom frame order.
- **Melees on the field.** Several invaders share the left of the field, each army in its own band with its own ring, count, dice and calls.
- **Victory.** Winners cheer, and horses rear.

### Sound

- **Music that doesn't restart.** Each mood is now a playlist of takes. A take plays through once, and six seconds before its ending it crossfades into another take of the same mood. It never snaps from a crescendo back to a quiet opening.
- **New tracks.** Eight were written as steady loops with no intro or ending:
  - a second anthem
  - two war-council takes
  - two battle marches
  - two cavalry charges
  - a marching tune for the reinforcement phase
- **New sounds.** Melee, border clash, the march, a war horse, a heavy gun, cards fanned out and turned in, and the camera's swoop.
- **New lines.** The chief of staff now has lines for the reinforcement phase and for melees.
- **Commander voices, second take.** Settings → Commander voices → *New take*. The advisor's clone had a long, calm sample line, and the commanders' had short shouted ones. The new takes are cloned from long, natural samples. The originals remain the default.

### Tools

- `tools/melee_sim.py`: compares melee rule candidates.
- `tools/shots/v13.gd`: the v1.3 probe. It plays a three-way melee with live calls and replays it, then runs the reinforcement phase, a border clash and the cards.
- The arena counts melees and follows the v1.3 rules by default (`moves=1 wild=0`).
- `tools/ludo/v13_content.py`: the figures, music and sound, and the second voice take.
- Ludo credits this pass: about 150, for 91 generations. The running total is about 560.

## v1.2 — 25 Sep 2026: the empire pass

### Amendment 9: battle calls — press on, reserves, or fall back

v1.1 let you watch a battle roll by roll, but you could only watch. Now an assault is fought in exchanges, and the attacker decides between them:

> An assault runs in exchanges of three volleys. After each exchange, if both sides still stand, the attacker calls:
> - **Press on.** Roll the next exchange.
> - **Reserves** (once per battle). Every soldier still at home who could march (the attack's origin keeps its last man, or only its dug-in defenders) joins the fight.
> - **Fall back.** The survivors march home and add to its army; the defender holds. If home has fallen, they fall back to the attacker's strongest land next to the battle. With nowhere to go, they're cut off and fight on.
>
> Border clashes and fights for the spoils have no calls; they are fought to the end. The decisive-roll style has no calls.

**Who makes the call.**

- **You**, if you're watching your own battle. The round pauses at the call. The battlefield shows the odds from here and the odds with the reserves, plus three buttons: PRESS ON (Space), RESERVES (R) and FALL BACK (F). The chief of staff reads the opening exchange aloud: "A bloody opening. Fall back now and save the men, or press on and pray."
- **Your officers** otherwise, when you auto-roll, skip, or turn battle scenes off. They follow the *standing order* sealed on each attack (the order card's "If it turns:"):
  - **Officer's judgment** (the default): calls the reserves when they'd lift the odds by 15 points and the fight is under 65%, and falls back under 20%.
  - **To the last man:** never calls, exactly v1.1.
  - **All in:** throws in the reserves whenever the fight is under 80%, and never falls back.
  - **Fall back if it turns:** falls back under 30%.
- **AI commanders** have a temperament:
  - Hask (the Bear never retreats) and Ysolde fight **all in**.
  - Quill cuts his losses (**careful**).
  - Oren fights **to the last man**.
  - Varek and Imre use **judgment**.

**Still one deterministic lock.**

- Calls made live are recorded on the attacker's sheet (`calls`: battle key → the calls in order), so a save replays every called battle exactly.
- The engine stops at a live call and returns the log so far with `pending`. The session puts the answer on the sheet and resolves the whole round again. Same inputs give the same prefix, so nothing already shown ever changes.
- An order with no stance and no calls fights the v1.1 battle volley for volley. Old saves replay unchanged, and sheets serialize exactly as before.
- Checked by `tests/test_calls.gd` (27 checks) and the `calls` probe, which plays a real battle through the client, calls reserves then a fall-back, and replays the saved round to the same world hash.

**Bands** (arena, volleys, 90 games per ladder):

| | v1.1 | v1.2 |
|---|---|---|
| General vs two Veterans, Known World | 50% | 42% (a coin-flip seat: 33%) |
| Recruit vs two Veterans | 20% | 17% |
| General vs Recruit, Isthmus | 77% | 80% |
| General vs three Veterans, Wide World | — | 37% (coin flip: 25%) |
| Assaults where the reserves are called / the attacker falls back | — | 10% / 4–5% |
| Evenly matched assaults won by the attacker | 58% | 69% |

The last row is the point of the amendment. An attacker with men at home now has a second wave, and a defender needs its dug-in garrison and its neighbours. Walk-ins stay the hook: 8 per game on the Known World (3 seats) and 12.5 on the Wide World (4 seats).

### The imperial re-theme

Everything was repainted as an empire at the height of its power. The new art direction is 18th-century history painting and Age of Sail maritime art in crimson, navy, gilt and ivory (`tools/ludo/v12_content.py`).

- **Commanders.** Grand Marshal Varek, Viceroy Ysolde, Governor Quill of the Company, Captain Oren of the Hussars, Commodore Hask ("the Old Bear"), Admiral Imre and the Chief of Staff.
  - **New portraits.** Every portrait after the first was painted with the first as its style reference (Ludo's style endpoint), so the set reads as one series.
  - **Faces.** New triumphant, furious and defeated faces, all cut out.
  - **Saved setups.** Saved setups pick up the new titles.
- **Voice.** All 87 lines were rewritten for conquest ("Every inch of it is ours for the taking", "Burn their boats!"). This adds 16 new lines: the chief of staff on the opening exchange, reserves, retreat and being cut off, plus every commander's own retreat and reserves calls. The same cloned voices speak them.
- **Music.** New tracks:
  - an imperial anthem for the title
  - a war-council march for planning
  - a full fife-and-drum battle march
  - a cavalry-charge theme for the battlefield
  - a triumphal victory and a funeral march for defeat
- **Sound.** New sounds for the capture fanfare, the walk-in sting, the cannon salute for a fallen empire, the retreat bugle, the reserves' drums, a regiment's hurrah and galloping hooves.
- **The chart.** Every map is dressed as an admiral's chart:
  - a compass rose
  - a gilded cartouche with the map's name
  - ships of the line riding the swell
  - All are placed from the map's own coastline data in the widest open water, clear of land and sea lanes.
- **The table.** Gilded laurel rings with a crown, a wax-seal dial in a baroque rim, gold coins, a silk banner.
- **Other art.** A new title painting (the map room), victory (a star fort's salute), defeat (a burning flagship), battlefields with forts and landing beaches, and the rules plates.
- **Cards.** Now infantry, cavalry and artillery, with a crowned wild card. The rules are unchanged.
- **Every flag is invented.** One defeat painting came back flying something close to a real-world flag, and it was regenerated.

### Living portraits

Every commander and the chief of staff breathe at rest and move their mouths while speaking. They react with the emotional face first, then talk for the rest of the line.

- **No clipping.** Each loop was generated at the portrait's exact size and position ("true size"), so frames never crop or shift. The worst drift was 2.8 px on a 1024 px frame.
- **No reset.** Each loop was generated to end on its first frame, and that duplicate frame is dropped when packing. If the step from the last kept frame back to the first is still larger than any step inside the loop, the loop plays back and forth instead (one loop, Imre's idle). `tools/ludo/pack_anims.py` checks and decides this for every sheet.
- **Smooth.** Frames crossfade at display rate, and switching between breathing, talking and a mood fades over a fifth of a second.

### The battlefield, alive

- **Soldiers.** New tin soldiers on a shared padded canvas, so smoke and falls have room and every sheet lines up.
  - They march in from their own edge, breathe (a ping-pong idle, so there's no seam), and fire.
  - The volley plays raise, aim, fire, then shoulder arms. Before, the figure snapped back to its stance.
  - They topple stiffly backwards when hit, drawn in code. Ludo's generated fall flipped the figure upside down and was unusable.
  - They turn and march off when you fall back, colours and all. Reserves march up behind the line.
- **Big calls.** "RESERVES! +9" and "FALL BACK!" across the field, with the drums, the hurrah or the bugle.
- **Smoke.** Powder smoke is now soft layered clouds instead of flat grey discs.
- **Names.** Long titles shrink to fit under the ring.

### Fixed

- **Probes muted the game.** The screenshot probes mute audio in memory, and a settings save during a probe wrote that into the player's own settings file. The game could start silent. Settings now have a `persist` switch the probes turn off. This machine's music, effects, ambience and map view were restored to their defaults.
- **The input probe on a Retina screen.** It now converts its clicks through the viewport's transform. The game itself was always right.
- **The generator.**
  - `ludo.py` is version-aware: an asset whose prompt changed is rebuilt even though its file exists.
  - Anything built from it waits for the new version, so a re-themed face is never edited from the old portrait.
  - Ledger writes are locked across processes.

### Tools

- `tools/sheet_tool.gd`: spritesheet checks (edge contact, drift, loop seam), packing, padding and contact sheets.
- `tools/ludo/pack_anims.py`: turns the animation masters into game sheets. The masters live in `assets/raw`, not in git; `--fetch` re-downloads them.
- `tools/shots/calls.gd`: the battle-calls probe.
- The arena reports how often reserves are called and attackers fall back.
- Ludo credits this pass: about 210, for 154 generations (20 of them animations). The running total is about 410.

## v1.1 — 24 Sep 2026: the feel pass

### Fixed

- **"Forces heading out of a land that gets captured vanish."** The engine was right; the battle replay was wrong. When a dug-in land moved every mobile soldier out, the replay treated the land as abandoned, showing it empty and unowned with its dug-in defenders gone. Across 268 AI rounds the replay disagreed with the engine on 234 land checks. It now agrees on all of them.
  - `tests/test_ai.gd` now checks that the replay matches the engine on every land, every round, on all three maps.
  - `engine/autoplay.gd` now checks army accounting (P2) on every map and seat count, not just the 2-player Isthmus.

### Amendment 8: roll-by-roll battles (the default for new games)

v0.2 made combat one decisive roll so the odds would stay readable. v1.1 adds a volley mode with the same odds, so a battle can be watched and rolled by hand:

> Each volley, both sides roll a die, multiply it by five and add their armies. The lower score loses one army (ties go to the attacker; in clashes and spoils, ties reroll). Fight until one side is gone.

Why ×5: a die worth five armies makes size matter exactly as much as it does in one decisive roll. Whole-number "+1 per N armies" bonuses snowball: even fights drift to 70–80% at large sizes. Measured with `tools/battle_sim.py` and in `tests/test_volleys.gd`:

| Matchup | Decisive | Volleys | Band |
|---|---|---|---|
| 1v1 | 58% | 58% | 55–60 |
| 4v4 / 8v8 / 20v20 | 58–59% | 58–59% | 55–60, stable |
| 6v4 (3:2) | 83% | 86% | ~80 |
| 8v5 | 92% | 91% | high 80s |
| 5v8 | 17% | 12% | ≤ 25 |
| 10v5 (2:1) | 100% | 98% | ~95 |
| survivors, 8v8 / 12v12 | 4.0 / 6.0 | 4.1 / 5.9 | same bloodiness |

The one difference is that tiny defenders fold faster (3v1: 93% instead of 84%). The AI plans with exact volley odds (dynamic programming, `Combat.capture_rate`), and every volley is on the event record, so the battle scene shows the engine's own dice. The decisive roll stays available as a setup option. Saves record which style they were played with.

AI ladder under volleys: General wins 50% against two Veterans (a coin-flip seat would win 33%), Recruit wins 20%, and General beats Recruit 77% on the Isthmus.

### The table, rebuilt around Risk II

- **Full-bleed map.** The side panel is gone.
- **The command bar.**
  - Left: the commander's medallion in a brass ring, with the reinforcements coin.
  - Middle: the advisor's dispatches, with counsel, a running log and *Advisor's plan*.
  - Next to that: the order tally.
  - Right: the big wax-seal dial (SEAL / NEXT / ROLL) with brass coin buttons for View, Rules and Menu.
- **Floating cards on the map.** The land card places itself where it hides none of the neighbors you'll click next. The order card has a strength slider, odds as words, the odds if they reinforce fully, surge, and cancel. Click an arrow's number to edit that order.
- **Commander strip along the top.** It sits in the space the map keeps clear, so it never covers a land. Hovering a commander lights up their lands.
- **Continents you can see.**
  - Heavy region borders with a gold core, plus a band of each region's own color along its outline and coast.
  - Region names painted across the land.
  - A **View** mode (V) that paints the land by region, with each owner shown as a band inside its borders.

### Battles you can watch

- **The battlefield scene.** When a battle involves you, it opens over the map on region-matched terrain (grassland, forest, mountains, desert, snow, coast, ash, moor). Toy soldiers are tinted to each commander, one figure per army (battalions for big stacks). They fire and fall with animated sprites.
- **Rolling.** You press ROLL: three volleys per roll, dice from the event log, each score shown ("Dad 5×4 + 3 = 23 vs …").
- **Controls.** Auto-roll and "Skip battles" are always there. Several fights at one land play back to back.
- **Settings.** Show my battles / every battle / map only, and roll yourself or auto.

### Leaders who react

- **Faces.** Every AI commander has triumphant, angry and defeated portraits (Ludo edits of their originals). The advisor has alarmed and pleased.
- **Voices.** 76 voiced lines from 7 designed voices, using Ludo voice design plus voice cloning, so each character sounds the same in every line. The subtitles and the audio come from one table (`game/data/lines.json`).
- **When they speak.**
  - A greeting as the commanders take their seats.
  - A battle cry when they attack.
  - A cheer or a curse after every engagement, and a flinch for every volley lost.
  - A taunt when they walk into a land you left empty.
  - A farewell card when they fall.
  - A victory line if they win.
- **The advisor now reads the board.**
  - Enemy punches that could land on your lands.
  - Lands that would complete a region.
  - Nearly empty neighbors.
  - Cards to trade, and the final round.
- **Advisor's plan.** It drafts a whole sheet in plain words ("Attack Steppe with 3 from Lantern — likely"), and you can adopt it with one click.

### Tools

- `tools/compile_check.gd` loads every script headless; it catches client compile errors in seconds.
- `tools/ludo/v11_content.py` is the single source for lines and v1.1 asset prompts. `ludo.py` learned image edits, sprite animation, voice design and voice cloning, with lanes that wait on their sources.
- `mapgen` places region labels where they have room, clear of tokens.

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
