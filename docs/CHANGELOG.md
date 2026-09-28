# Changelog

The bible says amendments come with a dated entry and the test or band that justified them. Everything below has both.

## v1.10 — 27 Sep 2026: Fortune in every fight, the second wave, and nobody cut off

New games play **rules 19**. v1.9 saves (rules 18) and older replay exactly as they were
played.

### Fortune, fixed where it didn't fire

The owner: "fortune doesn't seem to fire off correctly." Three things were wrong.

- **Auto-roll declined every offer.** With Auto-roll on, or Settings → "Roll the dice
  yourself" off, the battlefield answered every call by the standing order, which never
  spends a favour. So a Fortune offer passed by without being shown. Now an offer always
  stops and waits for you, even on auto-roll.
- **Only one-on-one assaults counted.** Clashes, melees and the scramble for the spoils
  never fed the ledger. In a five-handed war those are a large share of the dice a
  commander throws, so the end-of-war Luck column could say "cursed" while no favour came.
  Now every fight counts (rules 19):
  - Clashes and fights for the spoils are fought to the end, so each is its outcome less
    its odds.
  - A melee books each exchange's swing on the whole attack (the attackers together, shared
    by their numbers; the defender the opposite).
  - A scramble books each army's outcome less its chance of being the last standing
    (`Combat.scramble_odds`, simulated from a fixed seed, so the same fight always quotes
    the same odds).
  - The Luck column now weighs the same fights.
- **No Fortune in melees.** Now anyone in a melee can call on her after a bad exchange: the
  defender (beset from two sides is exactly when you want it) or the commander of any front.
  That exchange is thrown again for everyone in it, once a battle for each commander. The
  AI calls it by the same doctrine, and a watching human is asked. Clashes and scrambles
  still have no calls; their stars show dimmed, with "no calls in a free-for-all".

Arena, the same 30–40 wars (favours earned per commander per war):

| | rules 18 | rules 19 |
|---|---|---|
| Known World, 4 commanders | 1.55 | 1.79 |
| Wide World, 5 commanders | 1.83 | 2.11 |
| battles a favour was spent in, won by the spender | 48–49% | 47–48% |

The hard commander still leads both. The bar stays at half a battle.

### Melees and scrambles look like every other battle

- **The scramble for the spoils** draws an odds bar split into every army's chance of
  being the last standing, in its colours (it had none).
- **Fortune's stars** show in melees and scrambles.
- **The painted pieces** stand beside the table in melees and scrambles too, and the flag
  goes up (and the loser's piece topples) when they end.

### The second wave (rules 19)

A surge into a land you also attack directly can't fight alongside that assault: the surge
only marches once its own land has fallen. So it is a second wave.

- If the land held, the surge storms what's left (as before).
- If the first assault took it, the second wave now **marches in to hold it**, where it used
  to stay where it broke through.
- The surge's order card says which will happen.

### Dice, sound and voices

- **Even volleys are fired again as a throw of their own.** An exchange used to throw every
  volley at once, re-fired ties included, so a battle could show four or five pairs of dice
  with no explanation. Now three pairs are thrown, and any ties are re-fired in a second
  throw under "EVEN VOLLEYS ARE FIRED AGAIN".
- Every throw on any table plays the dice leaving the hand and settling (`dice_throw`,
  `dice_settle`, generated earlier but never wired in), besides each knock.
- **Charges are heard:** a hurrah when the foot press on, hooves (and sometimes a neigh)
  when the horse do.
- **Nobody is cut off.** A taunt or a callout used to be cut off by whatever the game did
  next. Now:
  - A line the game starts by itself waits for the one being spoken, and is dropped if it
    waited over five seconds.
  - A line that follows your own click or keypress may cut in, and Space or Enter skips a
    line.
  - A portrait's bubble shows when its line starts.
  - The battle report and auto-rolled battles hold a few seconds for a line to finish.

### The final chart

- It draws the same size in all three modes. The longer "Armies" title used to widen the
  panel off the screen, so switching modes resized the graph.
- Markers stay inside the chart, and the names at the lines' ends are stacked so they
  never overlap.

### The review table

- **In game.** After a successful Install run (not a dry run), every take that was
  accepted when the run began is marked **In game**, with its own tab, count and Finish
  tile. It stays so until a new take replaces its file.
- `review.py reconcile` (also run when the server starts) marks accepted takes whose
  installed copies already match: the 176 v1.8 lines installed earlier show as in game.

### Playtest bot findings (f5ee031), all fixed

- **B1:** the v13 probe closed the cards dialog after turning a set in had already freed it.
  Turning in closes it; `_close()` now ignores a second call, and the probe only closes a
  dialog still open.
- **B2:** the text CLI treated the end of stdin as a blank line and looped forever. Now a
  run of empty reads is the end of input: it prints "(end of input)" and quits without
  playing on.
- **B3:** the `ui` probe's fast-forward stalled in the regroup phase and screenshotted
  round 2 as "game over". It now passes the regroup phase and checks that it reached the
  end.

### Tools

- `tools/test_one.gd` runs one test file.
- `tests/test_v110.gd` covers every fight's luck, melee Fortune for a watching defender, a
  watching attacker and the AI, the old rules untouched, the second wave, and five-handed
  wars replaying.
- The `v110` probe checks melees, scrambles, a defender's offer, and the chart in all three
  modes.

## v1.9 — 27 Sep 2026: Fortune comes back, the chest is divided, the table gets dressed

New games play **rules 18**. Saves from v1.8 (rules 17) replay exactly as they were played.

### Fortune comes back (rules 18)

The complaint: "Fortune doesn't seem to come back after the first time each player uses it."
It was right, for two reasons.

- **The ledger only ever ran one way for attackers.** v1.8 weighed a battle's outcome against
  the odds it began with, but skipped every battle the attacker fell back from. The fights
  that went badly (the ones you retreat from) were never booked, while every fight that
  went well was booked as luck. Using Fortune made it worse: the rethrow that saved a battle
  was then counted as the dice being kind.
- **The bar was too high.** A favour cost three-quarters of a battle's bad luck, with a
  lucky streak remembered down to −1.5 battles. In the arena a commander earned about
  **0.6 favours in a whole war**, so most never saw one again.

The fix:

- **Luck is measured exchange by exchange.** Every invasion now carries `luck`: the sum,
  over the exchanges that stood, of how much each one moved the attacker's chances
  (`capture_rate` after it, less before). Reserves and falling back are choices, not luck,
  and don't count. An exchange Fortune threw away never happened, so it doesn't count
  either. A battle pressed to the end comes to exactly its outcome less its odds (checked in
  `tests/test_v19.gd`), and across many battles the swing averages to zero.
- **The bar is half a battle** (`Fortune.BATTLE_18 = 50`), and a lucky streak is held against
  you only a little (`FLOOR_18 = −20`).

Arena, 4 commanders, lands claimed in turn, levée on:

| | v1.8 ledger | v1.9 ledger |
|---|---|---|
| Known World (40 wars): favours earned per commander per war | 0.63 | **1.55** |
| Wide World (30 wars, 5 commanders) | 0.68 | **1.83** |
| battles a favour was spent in, won by the spender | 45–47% | 48–49% |
| hard commander's wins, Known World | 9 of 40 | 11 of 40 |

Settings tried on the same seeds (Known World, per commander per war): 60/−60 → 1.01,
50/−50 → 1.29, 60/0 → 1.48, 45/−20 → 1.70, 40/−40 → 1.70, 50/0 → 1.84. We chose
50/−20: a favour or two back per war, not a rethrow every battle.

**Seeing it.**

- **On the roster**, every commander's favours show as gold stars beside their name, and
  the next empty star fills with gold from the bottom as the dice owe them. Hover it for the
  numbers.
- **In a battle**, each side's stars sit under its dice.
  - They glow when that commander can call on Fortune right now.
  - They dim to "called on Fortune" once used this battle.
  - An AI holding one reads "may call on Fortune".
- **The Fortune button** wears the star.
- **Calling on her** plays her own chime, and a favour banked plays a softer one.

### A war chest divided (rules 18)

When several commanders take a fallen commander's last lands in the same round (they all
fell at once), the chest no longer goes to whoever happened to be last in the queue.

- Each taker throws a die, and the cards are shared out **in proportion to the throws**. The
  highest thrower takes what's left over, and the cards are drawn by lot.
- A lone taker still gets it all.
- The report throws the dice on the map, in each victor's colour, then flies each share
  across.
- Tests: every card handed out, the higher throw never getting fewer cards, conservation,
  the report agreeing, and replays.

### The table

- **Card troops on the map fade.** The gold "+1" star on a land a card is paying for now
  pops in, pulses and fades after about four seconds. It only ever meant "the troops
  appeared here".
- **The dice tray is dressed** in generated seamless baize, mahogany and brass. The
  rails have a rounded top and a brass inlay, the corner posts have finials, and the lamp
  pools light on the cloth. Each texture's own grain becomes a normal map at run time.
- **Score plates.** Each duel's totals now sit on a brass plate hung on the front rail
  ("25 vs 30", the winner's number in their colour, an even volley reads "even"). They
  replace the "2×5+5=15" labels that sat on top of the dice. Hover a plate for the working.
- **Painted pieces on the table.** A hand-painted tin miniature stands beside the tray for
  each side, on a plinth in its colour (generated 3D models, `assets/models`). It's the Risk
  piece the army is worth (a cannon for ten, a horse for five, a man), and it changes as the
  men fall. When the battle ends, the winner's piece becomes the colour-bearer and the
  loser's topples.
- The roll seal's label shrinks to fit ("PRESS ON", "LET IT STAND" no longer spill off it).
- **Capitals on the final chart.** Every capital taken is marked on the lands chart: a
  crown on the line of the commander who lost it, ringed in the captor's colour.

### The battlefield

- **Moves keyframed through our own poses.** The volley, the volley from the knee, the
  charge, the cheer, the reload, the cannon firing and the cavalry charge were made with
  Ludo's keyframe animation. It starts from our stand pose, passes through our exact aim
  pose, and ends back at the stand, so the figures stay on-model.
  - The raise is hurried, so the shot lands with the dice.
  - The lowering plays at its own pace.
- **The Guard.** An army of fifteen or more (a Brigade's dice) fields grenadiers in
  bearskins and cuirassiers in helmets and breastplates. They idle, march, volley and charge
  in their own dress: Ludo re-skinned our own sheets, so the motion is the same. The dress is
  used only when the whole set is on disk, so nobody swaps hats mid-volley.
- **A real fall.** A man hit falls backward and lies flat (keyframed to a generated
  "fallen" pose). Before, the standing figure was toppled in code.
- **Painted smoke, blasts and dust**, untinted and separate from the figures: musket smoke
  from the muzzle, a cannon's blast, dust kicked up where a man falls, a gun blown apart.
- **A capital burns.** Take a capital and the city burns behind its fallen defenders, and on
  the map behind its token.
- The Hydra **talk loops** (35 frames, real mouth shapes, a blink) replace the old
  mouth-flaps for the advisor and all six commanders, each at its own frame rate.
- Fortune's stars sit under each commander's dice in battle, and the order card says who
  holds favours before you attack.

### Films

- **Living paintings.** The title, victory and defeat screens are generated films that
  loop seamlessly over their paintings, with their own room tone
  (`game/ui/living_painting.gd`).
- **Cutscenes** at a war's big moments (`game/ui/cutscene.gd`):
  - the war beginning;
  - a capital taken or lost;
  - a rival wiped out;
  - victory and defeat.

  Each plays once a war, the battle report waits for it, and any key skips. They carry
  music and effects but no speech: the advisor speaks over them in his own voice.
- Settings → **Films** picks cutscenes and living paintings, living paintings only, or
  stills.
- **Music follows the war.** When a rival's army at least as big as your capital's
  garrison sits next door, the planning music turns to *besieged*. In the last rounds, or
  when someone is near a conquest, it's *endgame*. The victory screen alternates its fanfare
  with a sung march, and defeat with a lament.

### Tools

- **The review table finishes the job.** Finish review (F) shows the counts and runs the
  batch's own actions from the page, with a live log: Install accepted, and Redo rejected
  (which asks first, since it spends credits). It plays video, loops it, and measures the loop
  seam. Details in `tools/review/README.md`.
- `ludo.py` gained keyframes, motion transfer, sheet edits, video (image, references,
  upscale), 3D models, audio remixes and Hydra. The v1.9 production run
  (`tools/ludo/v19_content.py`, seven review batches) cost **376.9 credits**, leaving
  7,338.5. The breakdown by group, and what worked and failed, is in
  `docs/LUDO_CAPABILITIES.md`.
- `CLAUDE.md` holds the working rules and gotchas; `docs/ASSETS.md` covers the asset
  pipeline and every format the code reads.
- The arena takes `levee=`, `fbar=` and `ffloor=`, and reports favours per commander.

## v1.8 — 27 Sep 2026: capitals, Fortune, and the war we balance around

### Capitals

Every commander keeps a seat of government, marked with a crown on its token.

- **Choosing it.** After a random deal you name yours at deployment: the advisor pencils
  one in (deep in your own lands) and "Make this our capital" on any land's card moves it.
  The others' choices stay sealed until deployment ends. When the lands are claimed in
  turn, your first claim is your capital.
- **What it does.** It pays the treasury, **+2 recruits a round** while you hold it. It is a
  fortress: its defenders fire a line of six and one more man may dig in (a fortified
  capital is no stronger than either: a pip is five men, so one is the whole effect). On
  supply maps the road home runs to your capital.
- **When it falls.** The captor plunders it: **half the fallen commander's cards** (rounded
  up, drawn by lot) and **3 fresh troops** raised in the city on the spot. The court flees at
  once to the fallen commander's strongest land, and in their next reinforcement phase
  they may move it anywhere they hold (the AI keeps the one it was given).
- **In the report** a capital's fall is its own beat, "X's capital falls!", with a tolling
  bell and cannon; then "The court flees to Y".
- Setup → **Capitals** turns it off. Saves from before v1.8 have none and replay untouched;
  a world without capitals serializes and hashes exactly as before.

Measured (arena, seed 3000, the AI planner valuing enemy capitals and guarding its own):

| | without | with capitals |
|---|---|---|
| Known World, hard commander's wins (180 wars) | 39% | 34% |
| Known World, wars won outright before the last round (of 180) | 32 | 25 |
| The Ring, hard commander's wins (40) | 30% | 35% |
| The Thousand Isles, hard commander's wins (30) | 27% | 33% |
| capitals falling per war (Ring / Isles / Marches) | — | 4.0 / 3.7 / 1.2 |

A little less blitz and a lot more drama: about four capitals change hands in a
four- or five-handed war.

### Fortune: bad luck banks a throw-again

The dice keep no memory, but Fortune keeps a ledger. Every assault a commander fights is
weighed against the odds quoted as it began (the same sum as the luck column), in hundredths
of a battle; each time the dice have cost you **three-quarters of a battle's worth**, she owes
you a favour, ✦. Everyone starts with one and holds at most three; the count is beside every
name in the roster (hover for how close the next one is).

**Spend it in a battle you are watching.** After an exchange that went badly for you — it
ended the battle, or cost you two more men than it cost them — the call plate offers
**✦ Fortune (T)**: that exchange never happened, the fallen stand again, and the dice fly
once more. Once a battle for each side, attacker *or* defender (defenders are asked only
when it applies). The plate says what the exchange cost you ("69% → 39%").

Rules that keep it from being bullshit:

- **Your favours are only ever spent by you.** Skip the battle, or let it auto-roll, and they
  stay in your pocket. (The sheet carries `fortune_auto` only for AI commanders.)
- **It can only undo a disaster of your own**, never target a good exchange of theirs.
- **The AI follows the same limits** and spends by doctrine: only when the exchange swung a
  battle worth having (a quarter or better) by a fifth of its chances.
- Everyone's ✦ is visible, and Fortune paying out is its own beat in the report.

Engine: the choice is a battle call (`F` spend, `n` let it stand) recorded on the sheet, so
a save replays it exactly; the defender's choices go on the defender's sheet. Arena (Known
World, 30 wars): about 1.5 favours earned and 3.5 spent a war; the side that spent one won
the battle 56–59% of the time — a real swing, not a guarantee.

### The rules, and the war we balance around

The setup screen's five rule rows became one **Rules** row: **Standard**, **Recruit**,
**Classic**, or **Custom**, with **Customize…** opening every rule with what it does written
beside it. The table's rules are saved with the game (`game/core/rules.gd`).

| | Standard (the full war) | Recruit (a first war) | Classic (Risk II) |
|---|---|---|---|
| lands | claimed in turn | dealt | dealt |
| capitals | yes | — | — |
| Fortune | yes | yes | — |
| levée en masse | yes | yes | — |
| battle odds | firing line | firing line | every man counts |
| surges | yes | — | yes |
| fortresses, passes, ports, supply | yes | — | — |
| regroup phase, cards | yes | yes | yes |

**Why Standard is Standard.** The arena learned to measure fun, not just who wins: lead
changes, wins from behind, how close the finish was, upsets. Known World, general v two
veterans, 60 wars each, one rule changed at a time:

| | Standard | lands dealt | no capitals | no Fortune | v1.7 rules | classic odds |
|---|---|---|---|---|---|---|
| wars won outright before the last round | **2** | 12 | 11 | 10 | 10 | 17 |
| lead changes a war | **1.6** | 1.4 | 1.2 | 1.1 | 0.9 | 1.1 |
| won from behind | **18%** | 10% | 6% | 5% | 6% | 11% |
| finishes within 3 points | **27%** | 20% | 13% | 19% | 12% | 15% |
| the hard commander's wins | 43% | 38% | 42% | 33% | 47% | 40% |

Capitals and Fortune each add drama; **claiming the lands in turn is the biggest lever of
all** — wars stop ending in early knockouts and turn into close fights that swing. On the
Thousand Isles it doubles the lead changes (1.5 → 3.3 a war) and wins from behind go from
16% to 43%, because a random deal on a supply map scattered everyone's lands.

**Levée en masse** (new): a recruit for every three lands you trail the leader by, up to four a
round. A gentle hand for whoever is losing. It is the most debatable rule in Standard, so the
evidence: the Wide World's outright conquests fall from 13 in 40 wars to 2, the Ring's
finishes within 3 points go from 5 of 28 to 10 of 29, and the hard commander's share is
unchanged everywhere (the Known World is a wash). Wars go the distance and finish close;
skill still wins.

### The Marches: a duel is a duel

Asked to make the duel last: it can't be done with the dials. Every variant ended 34–39 of
40 wars in conquest, usually by round six — starting with 6 or 9 lands instead of 3,
stronger neutrals, a bigger opening pool, needing 90% or 100% of the map (elimination: still
37 of 40, by round seven), and the levée at full strength. Two commanders with nobody else at
the table snowball; whoever gets ahead rolls the other up. The Marches stays the short,
brutal duel. Maps may now ask for a different domination share (`"dominate"`), which it
turned out this one doesn't need.

### Generation, explored

`docs/LUDO_CAPABILITIES.md` inventories what Ludo can make (36 tools; CONCURRENT used 10),
with costs and 25 sample generations (86.5 credits) in the review batch `ludo_explore`.
The best finds: keyframe animation for the tin soldiers (stand → aim → fire → shoulder arms
on the same base figure the game tints), image-to-video "living paintings" for the title
and victory screens, portraits that speak their line (Hydra), and untinted smoke sheets.
The account balance is **6,759 credits** (the ledger undercounts: background removals were
never recorded).

### The spoils are no longer yours to roll

Defend a land alone against two commanders, lose, and the victors then fought over it in
a scramble — with you pressing ROLL for their dice. The battle screen decided "you roll"
once for the whole field. Now you roll only while you have men standing on it: once
you're out, their dice roll themselves, and when nothing left on that field is yours the
screen closes and the map shows who took the spoils. (Probe: `v18`.)

### A war that talks back

**260 new voice lines.** Every line may now have takes: `lines.json` holds a list, take 1 is
`<key>.mp3` and take n `<key>_v<n>.mp3`. Takes are dealt from a shuffled bag, so none
repeats until the rest have been heard, never twice in a row, and only takes with a voice
are ever shown, so subtitles always match the audio.

- The **advisor** gains 92: new takes of everything he says every round (the seal, the
  reveal, the orders, the regroup, every battle call), and lines that were written in v1.2
  but never wired to anything (a land taken, a garrison that held, a land lost, the lead
  taken, falling behind, a crushing exchange).
- **When the dice mock the odds, he says so.** Win a battle you were likely to lose, or lose
  one you were very likely to win, and you hear about it ("Blast those dice! That was a
  certainty on paper."). One man left standing gets its own line too.
- **The six commanders** gain 28 each: new takes of attack, win, lose, walk-in, retreat,
  reserves, claim and cash; lines for taking and losing a capital; and **taunts** — when the
  orders open, a commander marching on you may have a word for you.
- Only the upsets always speak; the everyday verdicts speak six times in ten, so the
  advisor never becomes a metronome.

### Review before it ships: `tools/review`

Generated assets now go through a review queue before they reach the game. The 260 new
takes were generated into `review/v18_voices/`, and none is in the game until it has been
accepted:

    python3 tools/review/review.py serve --open     # listen, accept, reject, fix the words
    python3 tools/ludo/v18_content.py --install     # accepted takes go into the game (and get imported)
    python3 tools/ludo/v18_content.py --regen       # rejected takes are re-rolled (new words kept)

The tool is general: any batch of audio or images with a `batch.json` (see
`tools/review/README.md`).

### The luck ledger

The end-of-war standings gain a **Luck** column: every one-on-one battle (assaults and
border clashes; retreats are a choice, not a roll) against the odds quoted when it began.
+2 means the dice handed you two battles you should have lost; the tooltip gives the
numbers ("Won 14 of 22; the odds said 16.3"). Not a rule change: a way to settle the
argument.

### Also

- The capital's crown, the Capitals rules page (with new art), and the setup option.
- A falling capital has its own sound (a tolling bell under cannon fire).
- `tools/arena.gd`: `capitals=` (default on) and a "capitals fell per game" line.
- `tools/review`'s demo batch speaks real words now (the Mac's own voices), not tone babble.
- 21 Fortune voice lines in their own review batch, `v18b_voices` (`tools/ludo/v18b_content.py`).
- The arena's new lines: `capitals`, `fortune`, and `drama` (lead changes, wins from behind,
  upsets, finishing margin).
- 567 checks; probes v13–v18 clean.

## v1.7 — 26 Sep 2026: the fresh pass

A pass over the whole game with fresh eyes: the rules re-derived from scratch and checked
against the code, three new maps, land that has a character of its own, supply lines, and
a face for the commander who had none.

### The review (27 Sep): what the first pass got wrong

The pass below was reviewed line by line before anyone played it. Amendment 18 was a real
find and stands. Around it:

- **Amendment 18 rewrote old saves.** The fix applied to every game, so a war saved under
  v1.6 replayed with different dice outcomes than it was fought with, and its later sheets
  stopped matching the world. The fix now belongs to games begun under v1.7 rules
  (`rules` 17, the default for new games); older games replay exactly as fought, and their
  battle report now shows the even volley going to the defender, as it did.
- **The AI couldn't count to six at a pass.** The planner didn't know the column cap, so any
  attack of seven or more into a pass failed the sheet check, and the repair step then
  struck *every* surge and dropped attacks from the end until the sheet passed: 11 to 31
  hobbled sheets a war on The Ring, 14 in one war on The Marches. The Ring and Marches
  ladders below were measured with that bug in. The planner now sends at most six from
  any one land into a pass, surges into one with six, and fears six a road into its own;
  a test holds the repair count at zero.
- **Nor could you.** "Attack with all" and the strength slider ignored the cap too, so the
  order was simply refused at the seal. Orders into a pass now stop at six, and the card
  says why.
- **The pass leaked.** Only the order was capped: a surge into a pass took every survivor,
  and the reserves could pour in without limit. Both now hold to six a road (games begun
  under v1.7 rules). And the text promised that two columns make "the defenders split";
  they never did, because one commander's columns into one land always merge into a single
  assault. So the rule now reads as it plays: six from each land you attack from.
- **Ports only worked for the AI's validator.** The regroup phase in the client still asked
  for a land border, so the sea march the rules page describes was impossible to order.
  It can be ordered now (the land card marks the crossing "by sea"), and the AI's own
  regroup ships men between its harbours too.
- **Deployment obeyed supply.** A land dealt away from your main cluster had room 0, so it
  couldn't take a single starting soldier. The lands were dealt, not conquered, and
  nothing is cut off before the war begins; the opening ignores supply now.
- **The AI couldn't see supply.** Every new map uses it and the planner didn't know it
  existed. It now values a conquest by what it does to the roads home: rejoining stranded
  lands, not stranding the conquest itself, cutting a rival's chain. Weighted by how well
  a commander reads the board: the recruit never sees it, the general sees it all.
- **The fortress was quoted open-ground odds in the planner's own sizing.** `_needed` took
  the fort's bonus as a parameter and was never passed it. It is now, and the battle bar's
  "both fire a full line of five" no longer says so inside a fortress.
- **The setup screen lost its start button.** Six maps in an unscrolled list made the page
  taller than the window, so "Begin the Campaign" sat at y 1070 of a 900-high screen, out
  of reach in fullscreen. The map list scrolls now (the last map you played is scrolled
  into view), the page fits with five commanders seated, and the v17 probe fails if the
  button ever leaves the screen again.
- **The emblems sat on the names.** On the Isles nearly every harbour's name lost its first
  letters under the anchor. They sit off the token's left flank now. The Marches read
  "2–2 players", and two map blurbs ran out of their cards.

**And the balance.** Amendment 18 changed every map, not only the new ones: the v1.6 that
was played and liked was quietly giving the defender every even volley. With honest
dice the whole table was a touch too bold, because v1.6 had made every commander 7 points
bolder to make up for dice that lied. Only the hard commanders keep that nerve now:

| Known World, general v two veterans, 60 wars | v1.6 as played | v1.7, all bold | v1.7, as shipped |
|---|---|---|---|
| won outright before the last round | 11 | 17 | 10 |
| the hard commander's wins | 47% | 52% | 47% |
| walk-ins a war | 5.4 | 5.7 | 5.1 |

### Amendment 18: the even volley is fired again — everywhere

v1.6's headline rule says an even volley costs nobody and is fired again. The combat
kernel did that. **The resolve queue did not.** In `_invade` a refired tie came back with
no winner recorded, and the loop's `else` branch took a man off the *attacker*. So:

- every battle actually fought ran at **41.7% a volley** where the sheet, the advisor, the
  battle bar and the AI's planner all quoted **50%**;
- and a fortress was worth *exactly nothing*, because the only thing its extra man did was
  turn a tie the attacker already lost into a loss by one pip.

The two faults hid each other, which is why the first fortress simulation came back
byte-for-byte identical with the fort on and off — the giveaway that started the hunt.

How it was found: the rules were re-implemented from the prose in this changelog, in
Python, with exact rational arithmetic, and the two were compared. The kernel agreed to
the last decimal on all sixteen quoted matchups. The queue did not.

| | quoted | fought, v1.6 | fought, v1.7 |
|---|---|---|---|
| 9 v 9, open ground | 50% | 34% | 50% |
| 12 v 9, open ground | 78% | 61% | 76% |
| 9 v 9, in a fortress | 36% | 34% | 38% |
| 6 v 9, open ground | 16% | 11% | 17% |

`tests/test_v17.gd` now fights six hundred battles through the queue at each of three
matchups and fails if the result drifts more than six points from the quoted odds, so the
sheet and the battlefield can never disagree again.

**And a band in this document has been meaningless since v1.0.** The arena reports "even
fights, attacker took X%", and that number has wandered between 41% and 79% across
versions while being read as a check on the combat rule. It never was one. Which even
fights a tournament produces is chosen by the commanders, not the dice — the AI sizes an
attack against the defence it *predicts*, so the fights that happen to come out equal are
a selected handful (53 of them in a forty-game tournament), not a sample of the rule.

The rule is now checked where a rule can actually be checked: the same matchup fought
through the real queue, 800 times, at eight sizes, on a map with no traits on it.

| through the queue | 1v1 | 2v2 | 3v3 | 4v4 | 5v5 | 6v6 | 8v8 | 12v12 |
|---|---|---|---|---|---|---|---|---|
| attacker takes it | 47.9% | 52.4% | 53.0% | 50.1% | 51.0% | 51.8% | 51.1% | 49.9% |

The arena still prints the band, now labelled as the selected sample it is, and also
reports the subset fought as they started — reserves thrown in mid-battle make the
attacker bigger than the record says, and a fall-back is scored as a loss the dice never
dealt.

### Land with a character of its own

Three traits a map may give a land. They are off unless the map asks for them, so the
Isthmus, the Known World and the Wide World have none. (Amendment 18 does touch them: it is
the combat rule itself.)

- **Fortress** — its defenders fire a line of six instead of five, and one more man than
  usual may dig in there.
- **Pass** — no more than six may storm it from any one land, however many you have
  there: surges and reserves included. The answer to a pass is to come at it from two
  lands at once.
- **Port** — two of your own ports are joined by sea: troops may march between them in the
  regroup phase, and supply runs along them. You cannot attack down a sea link.

**The fortress bonus is one, and one is the whole of it.** A pip is worth five men, so a
line of six, seven, eight or nine all score exactly the same against a line of five: the
next real step would be ten. Tested before a line of game code was written. It also means
a fortress is worth what you garrison it with — five men fire five wherever they stand —
which happens to be true of fortresses.

| ten against ten | open ground | fort +1 | fort +2 | fort +3 |
|---|---|---|---|---|
| attacker takes it | 50.0% | 34.2% | 34.2% | 34.1% |

### Supply

A map may ask that an army have a road home. Your largest connected body of lands — joined
by land borders, or by your own ports — is in supply. Anything cut off from it pays no
income and takes no recruits. It still fights, still holds, still digs in; it simply feeds
nobody until you join it up again. The map says CUT OFF across it.

It is a real lever, measured on the Thousand Isles over the same seeds:

| | walk-ins per game | the hard commander's share of 24 |
|---|---|---|
| supply off | 10.5 | 3 |
| supply on | 6.8 | 11 |

It costs some of the game's cheerful chaos and pays for it in generalship: overreaching
is punished, and cutting a neighbour's chain in the middle can strand half their empire
without fighting for a single one of those lands.

### Three new maps

| | lands | seats | what it is for |
|---|---|---|---|
| **The Marches** | 18 | 2 | The duel. Two crowns and a frontier that interlocks, so every march land faces two or three of the enemy's. One fortress and one pass each. |
| **The Ring** | 26 | 3–5 | Five realms around one crown. Every road in goes through a pass, and the Throne at the centre is a fortress. |
| **The Thousand Isles** | 24 | 2–5 | Five island groups and nothing but sea between them. Every crossing is a harbour; supply runs on ships. |

Every map is generated from a rules graph that is checked before it is drawn — undirected,
connected, no land without a way in, regions the right size, and the symmetry the map
claims — and `mapgen` then refuses to draw a border the graph denies or a sea lane that
would cross land. It refused twice while the Isles were being laid out, both times
correctly.

### Bands after v1.7 (arena, same rules on every map)

After the review (seed 3000; these replace the first pass's table, which was measured
with the AI hobbled at every pass and under the old `rules` default):

| map / seats | rounds (median) | ended in conquest | walk-ins per game | AI ladder |
|---|---|---|---|---|
| The Marches, 2 | 7 | 36/40 | 4.6 | general 22 / veteran 18 of 40 |
| The Ring, 5 | 10 | 8/40 | 10.3 | general 12, hask 10, veteran 8, quill 6, oren 4 of 40 |
| The Thousand Isles, 4 | 10 | 5/30, 7/30 | 8.7 | general 17 of 60 over two seed sets (a fair share is 15) |
| Known World, 3 | 8 | 17/60 | 5.1 | general 28 of 60 |
| Wide World, 4 | 10 | 9/40 | 9.6 | general 18 of 40 |

The Isles are the luckiest map: supply plus a random deal scatters everyone's lands, so the
early game is decided more by the deal than by generalship.

The first pass's table, for the record:

| map / seats | rounds (median) | ended in conquest | walk-ins per game | AI ladder |
|---|---|---|---|---|
| The Marches, 2 | 6 | 35/40 | 3.4 | general 23 / veteran 17 of 40; general 30 / recruit 10 |
| The Ring, 5 | 10 | 5/40 | 9.0 | veteran 12, hask 10, general 10, quill 7, oren 1 of 40 |
| The Thousand Isles, 4 | 10 | 8/30 | 9.1 | general 12, veteran 7, quill 6, hask 5 of 30 |
| Known World, 3 | 8 | 17/40 | 5.9 | — |
| Wide World, 4 | 10 | 12/30 | 10.0 | — |

The Ring is the one to watch and the best of the three: almost every war goes the full ten
rounds and is decided on score rather than conquest, with a walk-in somewhere on the board
nearly every round, and the easy commander is properly buried.

**The Marches is honest about what it is.** It fixed what it was built to fix — 3.4
walk-ins a game against the Narrow Sea's 0.9 — and its ladder is right. But 35 wars in 40
still end in outright conquest, usually by round six of ten. Two commanders on one map
with a frontier between them tend to finish each other off; that is arguably what a duel
is for, and it is left as it is rather than tuned into something limper.

**The Narrow Sea did not survive its own simulations.** A first draft of the duel map put
two realms either side of a sea with three crossings. It read beautifully and played badly:
78% of wars ended in outright conquest, by round five of eight, with **0.9 walk-ins a
game** on a game whose whole hook is the walk-in. Two realms across a sea barely touch, and
what does not touch cannot be walked into. It was replaced by The Marches, whose frontier
interlocks on purpose.

### A face for the commander

The human seat was a black silhouette beside six painted faces — it read as a missing
asset rather than a choice. There are now six commanders to be: the Iron Duke, the Corsair,
the Lioness, the Scholar, the Rajah and the Grenadier, each with the same triumphant,
angry and defeated faces the AI commanders have, and an idle loop that breathes. The old
anonymous silhouette is still the first choice for anyone who liked being nobody in
particular. Click the portrait on the setup screen to change it.

### The rules where you can see them

- A land's character shows **on the land**: small brass emblems along the token, and on its
  card in the words the rules use.
- A land out of supply is ringed in crimson and says **CUT OFF**.
- The order card, the advisor, the live battle bar and the AI's planner all quote the
  fortress's odds on a fortress. An odds figure that ignores the fort is a lie told to the
  commander at the moment they commit.
- Two new How to Play pages: *Fortresses, passes and ports*, and *Supply*.

### Tools and checks

- `tests/test_v17.gd`: the traits, the supply rule, Amendment 18, the map files' topology,
  and whole wars on all three new maps replaying to the same hash.
- `tools/contact.gd` builds a contact sheet from a glob of images, so a whole art batch can
  be judged at once instead of one file at a time. It caught three portraits where "eyes
  blazing with victory" had been taken literally.
- The arena learned `supply=` and `traits=` so a rule can be measured against the very same
  seeds without a second map file.

## v1.6 — 26 Sep 2026: the polish pass

### Amendment 17: the firing line

You asked whether attackers have too much edge ("7 having a huge advantage over 6"). They did, for two reasons:

- **Ties went to the attacker.** That gave every even fight to the attacker, 58.7% at 12 against 12.
- **Every man added to every volley's score.** So a bigger army won almost every volley, and a small lead compounded over a long fight: 25 against 20 was 98%.

Now, for new games:

> Each volley, both sides score pips × 5 + the men in their firing line: **at most five fire at once.** The higher total wins; the loser loses a man. **An even volley is fired again.**

A big army no longer wins every volley. Its extra men are its staying power, the men it can lose after the other side runs out. Numbers still tell: two to one wins almost always, and a lone holdout firing one man against five needs a miracle.

| Attackers v defenders | v1.5 | v1.6 |
|---|---|---|
| 6 v 6 | 58.3% | 50.0% |
| 7 v 6 | 73.7% | 64.2% |
| 9 v 6 | 90.8% | 83.6% |
| 12 v 6 | 99.4% | 95.9% |
| 12 v 12 | 58.7% | 50.0% |
| 16 v 12 | 94.4% | 80.1% |
| 25 v 20 | 97.8% | 78.7% |
| 30 v 20 | 100.0% | 93.4% |

**The candidates.** Tested exactly in `tools`-style Python before any game code was touched:
- ties to the defender, as in Risk
- a bigger pip
- "bloody" volleys that kill both sides on a near tie
- 2d6
- firing lines of 5 to 10

The firing line of five with refired ties was the flattest curve that still keeps two to one decisive. Ties to the defender made big even battles hopeless for the attacker (20 v 20: 19%), which would have turned the game into turtling.

**Garrisons are untouched.** The cap stays at three, and the defence comes from the combat rule instead.

**In a melee** the defenders' whole firing line faces every front, and an even volley costs nobody. A dogpile keeps the same loss ratio as one combined attack. `tests/test_v16.gd` checks a 6 + 6 on 8 (held 22%) against one attack of 12 (15%).

**On the battlefield:**
- The sums under the dice use the firing line.
- The bar explains it: "14 men against 9: both fire a full line of 5, so every volley is even; Varek has 5 more to lose".
- **? Dice** and How to Play explain the rule.

**Choose it.** It's the default for new games. Setup → **Battle odds** can switch back to "Every man counts" (the v1.5 odds). Old saves keep the old combat. `Combat.use_rules(map)` sets the rule from the game's map for the resolve queue, the AI and the table alike.

**What it does to a war.** Arena, same seeds:

| | v1.5 | v1.6 |
|---|---|---|
| General vs two Veterans, Known World (coin flip 33%) | 47% | 40% |
| General vs three Veterans, Wide World (coin flip 25%) | 40% | 40% |
| Known World 3-seat wars won by conquest (before the last round) | 50% (34%) | 30% (20%) |
| Wide World 4-seat wars won by conquest | 22/60 | 16/60 |
| Walk-ins per game, Known World | 7.3 | 5.8 |

- **Fewer conquests.** Stronger defence means fewer wars end in outright conquest. That's the trade for fairer fights.
- **Bolder AI.** Under the firing line every attack is a longer shot. Left alone, the commanders sat still and the hard AI fell to 38%, so every commander now accepts 7 points less certainty before attacking.
- **Line size.** Lines of 8 or 10 kept more conquests (37–40%) but fixed less of the steepness: 7 v 6 at 68%.

### Campaign cards name a land

Every land has one card of a fixed kind, dealt evenly over the map at the start of a war. Rules:
- **Drawing.** A card already in someone's hand can't be drawn.
- **Free soldiers.** Turning in a card whose land you hold puts **a free soldier there**, on top of the set's troops. The best set now picks the one that brings the most free soldiers, for you and for the AI.
- **Marching.** The free soldier can march the same round.

What you see:
- **The table** shows each card's land and "★ yours: +1 soldier there". Hovering a card lights its land on the map.
- **Turning in.** The three cards fly off the table into your recruit coin, the table closes, and the coin swells with +N. It takes you back to the reinforcement phase if you were writing orders. Each free soldier's land gets a gold star and a +1.
- **In the report**, a turn-in shows which lands got a free soldier.
- **The C key** opens your cards, and **Enter** moves on from the recruits to the orders. The cards are laid out by kind, so sets are easy to spot.

### The numbers along the top are always true

The roster's lands, scores and card counts now follow the battle report beat by beat, instead of jumping to the end of the round the moment the report starts. The hands follow too: the report's view of the world now applies turn-ins, draws and war chests. While you write orders, your own count takes away the cards you're turning in.

### Dice in their commanders' colours

Every tier now wears its commander's colour, and a glow of that colour sits under each die on the felt:

| Tier | Colour |
|---|---|
| Wood | stained |
| Bone | coloured pips and painted edges |
| Ivory | coloured pips and painted edges |
| Lacquer | the colour itself |
| Gold | coloured edges and gem pips |

### Arrows that tell the truth

- **In the battle report,** a column beaten in a border clash loses its arrow the moment the clash is decided, and the winner's arrow shows only the men still standing.
- **Next round's ghost arrows** leave out columns that never arrived and surges that never set off.

### The end of the war

The chart switches between **lands, armies and score**. Every set of cards turned in is marked on it: a little card in the commander's colour, on their line, at the round they turned it in, with its worth.

### Tools and checks

- **Tests.** `tests/test_v16.gd` has 16 checks. With them the suite is 456 checks, all passing. They cover:
  - the firing-line odds, and battles fought matching the quoted odds (7 v 6: 63.9% won of 4,000 against 64.2% quoted)
  - the melee loss ratio
  - the land deck: even kinds, no duplicates, the best set, free soldiers, conservation, and the report's hands matching the world
  - whole wars under v1.6 rules, replaying exactly
  - each test section starts from the classic battle rules
- **Probes.**
  - `tools/shots/v16.gd`: the land cards, the flying turn-in, the roster's count, and the end-of-war chart.
  - `tools/shots/v13.gd` now checks that the loser of a border clash loses its arrow.
- **Arena.** New argument: `line=` sets the firing-line size (0 is off).

## v1.5 — 25 Sep 2026: the phases pass

### Dice with real physics

- **How a throw works.** Every throw is now a rigid-body simulation of all the dice together (`game/ui/dice_stage.gd`):
  - The dice are tossed in over the far rail, tumble on the felt, bounce off the rails and knock into each other.
  - They come to rest on whatever face the physics says, and a dealer then squares each pair up so the sums line up.
  - Every knock on the felt, a rail or another die plays its sound, as hard as it hit.
- **Landing on the engine's roll.** The throw is simulated before it plays, 8–48 ms for up to ten dice. Then each die's pips are turned by a symmetry of the cube until the face that came up is the engine's roll. The shape and the tumble never change, only which face carries which number.
- **Why the engine still decides.** Saves replay, AI battles resolve instantly, and hotseat stays fair, so the number has to come from the seeded engine. The physics decides how the die rolls, not what it shows.
- **Checked.** `tools/shots/dice.gd` throws 1,000 dice and checks every one shows its roll.
- **Everywhere.** The commanders' order dice in the land draft fall onto the map the same way and stay where they land. So does the deciding throw on a map battle card.
- **Melees and scrambles** now throw up to four duels at once. A two-army scramble throws three pairs like any exchange, not one die at a time.

### The round, in four phases

Every round is now four phases, each opening with a banner and a drum-and-brass sting:

| Phase | What happens |
|---|---|
| **Reinforcement** | Click your lands to place recruits (one click, one man; right-click takes one back) and turn in cards. The dial says **ORDERS**. |
| **Orders** | Attacks and surges, then **SEAL**. **◀ Recruits** goes back. |
| **The Battles** | Everyone's orders at once. |
| **Regroup** | What v1.3 called the reinforcement phase: marching troops one land toward the front. |

- **The sheet is the same.** Each commander still places and orders in secret; the split is only the screen, so hotseat and the AI are unchanged.
- **The battle report announces its stages:** border clashes, the assaults, the surges (all at once, after every other battle) and the reckoning. The chief of staff calls the surges.
- **Card turn-ins are news.** When anyone turns in a set, the report opens with it: the three cards rise from the table into the commander's ring, with a +N and a line. Every commander has one, and the chief of staff speaks for you or warns you about a rival.

### Amendment 16: surges

- **Head-on surges clash.** Two surges running at each other's freshly taken lands used to pass in the night and each fight the other's leftovers. Now they meet in a border clash, like any two columns marching at each other.
- **A count.** A surge carries a count (`Sheet.surge_n`): up to N men push on, and the rest hold the land just taken. With no count, it's all who survive but one, as before.
- **Ordered like any march.** Drag from the land you're attacking on to the next one, or use **Surge onward…**. It draws as a full arrow labelled "all" or "≤N", and clicking the arrow opens its card to set the count.
- **Old saves** keep the old surges (`config.rules` is 0 for them).

### Garrisons: three deep, and the shield shows who stays home

- **Dig-in reaches three** for new games (v1.4 capped it at two). Alone, this tested neutral.
- **The shield always shows who stays home.** On a land with nobody dug in yet, the one man who must stay behind stands on the shield with the garrison. The big number is exactly who can march. This is how the table now teaches the old Risk rule "one army must stay behind".
- **The literal version: tried and left off.** Taken literally, the man left behind would be locked in the garrison for good. The arena says that costs a marching man on every land:

  | Wide World, 4 seats | v1.4 | cap 3 | man locked in | both |
  |---|---|---|---|---|
  | Wars won by conquest | 21/60 | 22/60 | 13/60 | 4/60 |
  | Walk-ins per game | 13.2 | — | 9.4 | — |
  | Hard AI wins (coin flip 25%) | 37% | 40% | 30% | 25% |

  So the lock-in is an engine switch (`config.first_digs_in`), off by default.

### Battles

- **Formations.** Armies draw up in formation instead of a crowd:
  - the foot in a line at the front of their ground, four abreast, rank behind rank
  - the horse behind the foot
  - the guns in a battery in the far lanes, three deep, so nothing stands in front of a muzzle

  An army too big for its half of the field closes ranks.
- **Sound.**
  - Muskets now fire with a violent black-powder crack and boom (three volley takes and two single shots), and one man firing is a shot, not a volley.
  - Cavalry charges and gallops in a real three-beat rhythm.
  - A quiet battle beyond the battle plays underneath: far cannon, far volleys, drums, a bugle, a distant roar, one every few seconds.
- **The odds bar.**
  - It ends on the verdict ("You take The Gate · Decided"). Before, it kept the last odds, like 10%, after the fight was over.
  - An even fight explains its lean: "12 men against 12: even numbers, the dice decide · ties go to the attacker". The attacker's 58.7% at 12 against 12 is right, and a simulation of 20,000 battles agrees.
- **Grammar for "You".** "You hold", "You take", "You throw", not "You holds".

### Bands after v1.5

Same seeds as v1.4. The pace and the hard commander's edge hold:

| | v1.4 | v1.5 |
|---|---|---|
| General vs two Veterans, Known World (coin flip 33%) | 51% | 47% |
| General vs three Veterans, Wide World (coin flip 25%) | 37% | 40% |
| Known World 3-seat wars won by conquest (before the last round) | 51% (34%) | 50% (34%) |
| Wide World 4-seat wars won by conquest | 21/60 | 22/60 |

### Tools and checks

- **Tests.** `tests/test_v15.gd` covers:
  - head-on surges clashing (40/40), with the old rule kept for old saves
  - surge counts, their validation and the save
  - the garrison display, and the literal lock-in switch
  - dig-in reaching three
  - whole wars under v1.5 rules
  - reinforcement, then orders, then back
- **Probes.**
  - `tools/shots/v15.gd`: the phases, a dragged surge with a count, the physics dice in battle, the stages of the report, the regroup phase and a set turned in.
  - `tools/shots/field.gd`: formations at every size.
  - `tools/shots/dice.gd`: 1,000 physics dice.
- **Audio.** `tools/ludo/v15_content.py` has the new sounds and lines, and `tools/ludo/prep_sfx.py` cuts them (it can now cut named sounds only).
- **Arena.** New arguments: `rules=`, `first=`.

## v1.4 — 25 Sep 2026: the dice pass

### Balance: what the arena says, and what changed

A balance study measured 200 seeded games in each of four setups: the Known World with 3 and 4 seats, and the Wide World with 4 and 5. It then tried nine rule tweaks on the same seeds. The instrumented runner and raw data stayed out of the repo.

**What it found.**
- **It isn't a turtle game.** Attackers still take 86–88% of assaults on dug-in land. They just bring about twice the men.
- **The problem is free dig-in.** From round 4 on, dug-in men are about 60% of every man on the board. Most of them sit on interior lands no enemy touches (70–76% by the end), where they are dead weight that thickens the board and slows the late war.
- **Snowballing is strong on the Known World with 3 seats** (the round-3 leader wins 78%) and moderate elsewhere (55–67%). Region bonuses drive it, at 36% of income there. The only levers that reduce it (half region income, catch-up income) also halve the decisive finishes, so they stay out: a merciless game should snowball.
- **Card sets** swell late income on the Wide World, but capping them changed nothing measurable.
- **The loss order** was already right: the field army falls first and the dug-in men behind the walls last. The code comments said the opposite and are fixed.

**Amendment 15: nobody digs in deeper than two.** New games cap the dug-in defenders on any land at two. A land with no neighbour of yours stays at one, unless you hold its whole region. Fronts dig in exactly as before in the first rounds; only the interior stockpiles go. In the study:
- more wars ended by conquest
- more assaults late in the game
- about 25% fewer men per land from round 4
- more comebacks
- no loss of attacker odds

Old saves keep the old ceiling (`config.dig_cap` is 0 for them).

**The hard commanders march to strike.** Every commander used to march the same way in the reinforcement phase, one step toward the nearest threat. Varek, Ysolde and Imre (and your chief of staff's *Advisor's marches*) now march on the front that faces the richest, weakest prey:
- a region to finish or break
- a rival down to their last lands, and their war chest
- thinly held ground

A quiet front also lends its spare men to the neighbour that will attack next.

**Not changed:** marches stay one land per soldier, as you asked for in v1.3. The study found two-land marches make wars more decisive still, so it's an option for later.

**Bands after v1.4** (arena, same seeds; the column before is v1.4's other rules with the old march planner). The arena now counts games decided *before* the last round separately. v1.3's "45% end early" also counted conquests completed in the final round.

| | before | v1.4 |
|---|---|---|
| General vs two Veterans, Known World (coin flip 33%) | 45% | 51% |
| General vs three Veterans, Wide World (coin flip 25%) | 35% | 37% |
| Known World 3-seat wars won by conquest (before the last round) | 46% | 51% (34%) |
| Wide World 4-seat wars won by conquest (before the last round) | 28% | 35% (22%) |
| General vs two Veterans, lands claimed in turn, Known World | 36% | 43% |
| General vs three Veterans, lands claimed in turn, Wide World | 38% | 43% |

In drafted games everyone starts on a clean block, so there is less for the hard commander to exploit. Its one-turn lookahead on the claims won back most of its edge.

### Dice you can hear

- **Real dice on a real table.** Every throw in the battlefield is a pair of 3D dice per duel. They fly in from each side over the armies, bounce, tumble edge over edge across a baize tray and settle on the engine's own roll. Each die knocks on the table as it lands (`game/ui/dice_stage.gd`, `game/ui/dice.gdshader`).
  - The motion is planned backwards from the face that must come up, so every throw looks loose and still always lands on the right number.
  - An exchange of three volleys is one throw of three pairs. A melee or a scramble throws each salvo, with one pair per front.
  - The dice keep the battle speed from Settings and hurry a little in auto-roll.
- **Dice by army size.** The dice an army throws are made of what it can afford, and they change mid-battle as it bleeds:

  | Army | Dice |
  |---|---|
  | Lone holdout (1–2) | whittled wood, burnt pips |
  | Company (3–6) | old bone |
  | Regiment (7–14) | ivory, pips in the commander's colours, brass trim |
  | Brigade (15–29) | lacquer in the commander's colours, brass edges |
  | Grand army (30+) | gold, gem pips, the imperial star on the one |

  Wood knocks, bone and ivory click, and gold lands with a heavy clunk.
- **The sums, in plain sight.** Under every die the table shows what it made: `4×5 + 14 = 34`. The winner's sum is in gold, and the loser's die goes dark with a −1.
  - Above the field, a tug-of-war bar gives your chance of taking the land from here, updated every volley.
  - Under it sits the reason: "14 men against 9: Varek throws with a 5-man edge (1 pip on every throw)".
  - **? Dice** opens the scoring rules and the dice ladder.
- **Battles on the map** (the ones you don't open) drop their deciding throw onto the battle card. The card now shows each side's men in and men left.

### Amendment 14: the scramble

When the defenders of a melee fall, or two or more commanders' columns march into the same empty land, the survivors no longer fight a ladder of duels. That ladder let the order of the duels decide too much when three armies met. Now:

> Every army duels every other at once. Each salvo, every pair still standing throws a duel: score = 5 × die + this army's weight against that foe, where an army splits its men across its foes in proportion to their size (weight = mine × theirs ÷ all my foes). The loser of a duel loses one man, and a tie costs nobody. Duels in a salvo run in a fixed order, and a man already down fights no more that salvo, so someone is always left standing. The last army standing takes the land.

- **Two armies** fight exactly a volley fight. `tests/test_v14.gd` measures a 6-vs-4 scramble won 83.3% of the time against the exact 82.8%.
- **The same rule** settles surges that converge on one land, and a surge into a held land by two commanders is a melee.
- **Owner's columns.** Under the new rules, an owner's own columns arriving at a land under attack join its defence before anyone fights.
- **On the battlefield,** the victors turn on each other on both sides of the field ("Every man for himself!"), throwing one pair of dice per duel.
- **Old saves** keep the ladder of duels (`config.scramble` is false for them).

### The war chest

Take a commander's last land and every card they held is yours. The rule was there, but it looked for the fallen commander's lands from the start of the round, so a last land they had only just captured never counted. Now the very last land they lose decides it. The moment has its own beat: the fallen commander's cards fly across the table into your ring, with a chest-and-brass sting and a line from the chief of staff.

### Lands claimed in turn

A new game can deal the lands at random, as before, or have the commanders claim them in turn (Setup → Lands, or Settings → Lands in new games).

- **The order.** Every commander's die drops onto the map, in their colours. The highest throw chooses first, and ties throw again among themselves.
- **The claims.** Round the table in that order, each claims one free land until everyone holds what the deal would give. The two-seat neutral doorstop is pinned first, and unclaimed lands are left exactly as the deal leaves them.
- **The AI picks** for regions it can still finish, friends next door, few borders and room to grow. It avoids lands ringed by rivals and takes the last free land of a region a rival is about to own. Sloppier commanders pick sloppier.
- **The hard commanders** (and your advisor's **PICK**) look one turn ahead. For each of their best claims, they let the rivals who choose before them next take what they would take, then judge the board that's left.
- **You click** a free land. **PICK** takes the advisor's choice, and **Hurry** speeds up the others.
- **Checked by** `tests/test_v14.gd`:
  - the order roll: everyone placed once, highest first, ties re-thrown
  - the claims matching the deal's counts on every map
  - drafted wars that are legal and finish
  - a drafted session that claims every land and opens on deployment
- **The arena** plays drafts with `deal=draft`.

### Soldiers who aim the right way

The v1.2 firing loops had the musket held butt-first, and a second musket still hung at the soldier's side. Now:

- **New poses.** The infantry have Ludo poses for aiming standing and aiming from the knee, drawn as proper side views with the barrel and bayonet level to the right.
- **The shot is drawn in code:** the snap up to the shoulder, the shot, a recoil kick, and back to the stance. The muzzle flash is a hot, untinted star at the real muzzle, and the smoke follows it.
- **Why not the animations.** The generated firing animations baked the flash and smoke into the figure, where they took the army's colour, so they're not used.

### Sound

- **Cheers scale with the winners.** A handful of men cheer for a handful, a company for a company, and a grand army roars. The takes are levelled by loudness, so bigger sounds fuller, not louder. Battles on the map get a distant cheer.
- **Dice.** A cup rattle before each throw, and single knocks in wood, bone and brass for every bounce. The dice have their own small pool of players, so a clatter never steals a volley's sound.
- **The draft.** A flag planted for every claim, and a fanfare for the order.
- **Voices.** The second take of the commanders' voices is now the default. Captain Oren was recast closer to his original voice (a cocky young hussar, not a princess), and Viceroy Ysolde is now Russian. The classic takes are still in Settings. New lines:
  - each commander's claim in the draft
  - the chief of staff on the order roll, your first pick, a war chest seized, and the victors turning on each other
- `tools/ludo/prep_sfx.py` cuts Ludo's raw sounds into game-ready WAVs: the loudest single hit for a knock, and loudness-levelled cheers.

### On the map

- **Surges march like any other column.** A surge is drawn as a full arrow from the land being taken to the next, in the same style as any attack and labelled "all". In the battle report its arrow appears only when the surge sets off, and it draws itself out from the captured land while the arrow that took it stays lit, so A → B → C reads as one march.
- **Columns on the move.** In the battle report, marching chevrons run along every live arrow.

### Tools and checks

- **Tests.** `tests/test_v14.gd` has 24 checks. With them the suite is 423 checks, all passing.
- **Probes.**
  - `tools/shots/v14.gd` plays a melee that ends in a scramble on the dice table (and replays it), then a whole land draft.
  - `tools/shots/v14b.gd` covers a surge from plan to hop, a battle card's dice, and a war chest.
  - `tools/shots/dice.gd` shows every tier of dice, on the tray and dropped onto the map.
- **Arena.** New arguments: `deal=draft`, `scramble=`, `dig=`. It reports scrambles, and conquests before the last round.
- **Ludo.**
  - `tools/ludo/v14_content.py` holds the poses, sounds, voices, new lines and How to Play art. `tools/ludo/prep_sfx.py` cuts the sounds.
  - Ludo credits this pass: about 50, for 53 generations, including the failed pose edits and the unused firing loops.

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
