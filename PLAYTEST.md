# Playtest brief

For anyone testing CONCURRENT, and above all the owner's playtest bot, which runs on every push to
`main`. The newest version is at the top: what changed, and what to poke at. The standing checks
further down apply to every push.

## Getting the whole game

- **A plain clone has everything.** Art, audio and films are in ordinary git (no Git LFS), so
  `git clone https://github.com/coterboat/concurrent` or `git pull` brings the complete game.
  If a picture or sound ever looks like a 130-byte text file beginning `version https://git-lfs`,
  the repo has moved to LFS: run `git lfs install && git lfs pull` and see `docs/ASSETS.md`,
  "Storage".
- **Godot 4.5.1**, the editor build (the tests and probes are scripts, so an exported game can't
  run them).
- **Import once per fresh checkout**, before anything else: `godot --headless --path . --import`
  (the `.godot/` cache isn't in git).
- `review/` and `assets/raw/` are gitignored on purpose. They hold takes waiting for review and
  the masters, not the game.

| What | Command | Passes when |
|---|---|---|
| All tests | `godot --headless --path . --script res://tests/runner.gd` | the last line is `CONCURRENT ok passed=N failed=0` |
| Every probe (needs a display, e.g. Xvfb) | `GODOT=godot ./scripts/probes.sh` (or name some: `./scripts/probes.sh v112 v113`) | it ends without `probes: failed:`. Each probe's `ok`/`FAIL` lines are facts about the picture (three armies on three grounds, no arrow left for a dead column): a `FAIL` is a bug, even when the PNG looks fine |
| One screenshot probe | `SHOT_DIR=/tmp/shots godot --path . res://tools/probe.tscn -- --script=res://tools/shots/<name>.gd` | it prints no `FAIL` lines and the PNGs look right |
| The short check before a commit | `GODOT=godot ./scripts/check.sh` | it ends without `check: FAIL` |
| The text CLI | `godot --headless --path . --script res://tools/cli.gd -- play --seed 42 </dev/null` | a clean exit |
| AI wars | `godot --headless --path . --script res://tools/arena.gd -- map=known24 n=6 seats=general,veteran,recruit,hask seed=500` | no `VIOLATION` or `SCRIPT ERROR`, and the fingerprint below |
| Tool tests | `python3 tools/review/test_review.py && python3 tools/ludo/test_notes.py` | `OK` |

A GDScript runtime error doesn't quit headless Godot: it hangs. Treat a run that stops printing
as a crash, and grep the output for `SCRIPT ERROR`.

## How to report

Keep the format of the reports so far. One line per finding, the commit tested at the top:

`B1 file:line — what happens. repro: <command>. expect: <what should>. (game | tooling)`

Say which were checked and found fine too. "v1.10 melee Fortune: offered to the defender, rethrow
shown: fine" is as useful as a bug.

## Not bugs (by design)

- **A human's Fortune is never spent automatically.** The game offers the favour and waits, even
  with auto-roll on.
- **Clashes and scrambles have no Fortune calls.** The stars show dimmed with "no calls in a
  free-for-all".
- **A line the game starts on its own waits for the one being spoken**, and is dropped after 5 s.
  Only a click or key may cut in, and Space or Enter skips.
- **The Marches duel is short and brutal.** One side almost always conquers.
- **Old saves replay under the rules they were played with** (`map.rules`). A v1.8 save plays
  v1.8 Fortune.
- **Probes run with films off** (`motion = "paintings"`). `v19` turns them on.

## v2.0 (draft): the map and its battles on the land

No rule changes (rules 20), nothing in `engine/` or `session.gd`. The board stands on the map's own
land in 3D (L, or the 3D/2D chip by the zoom buttons, switches it back to the chart), and battles are
fought on that land, with the battle screen's UI unchanged over it. Settings → *The land in 3D* has a
switch for each. The project now renders with **Forward+**. On a Linux machine without Vulkan, Godot
falls back to Compatibility: say which renderer your log's first lines show, and whether the land draws.

- **The board on the land.** The same board (tokens, arrows, names, ceilings, fates, region pips, the
  land card) drawn over the land: straight down it is the chart to the pixel, then the land rises and
  the camera tips back; zoom in and it comes lower. **Poke:** play a whole round on it. Is any token,
  name or plate unreadable over a hill, a wood or the sea? Does any click land on the wrong land (a
  token behind a hill is the one to try)? Does a zoom keep the land under your cursor? Drag to pan:
  does the ground follow your hand?
- **Living lands.** Every held land's garrison stands by its token (one figure for two men, five at
  most), repainted when the land changes hands. A village in every land in its region's style; a
  landmark where the name calls for one (a mill, a gate, a beacon, a haven...); the rules as buildings:
  a star fort on a fortress, a blockhouse on a pass, a quay on a port, a palace at a capital. Ships ride
  the sea and a frigate plies every sea lane. **Poke:** does any building stand in the sea, on a road,
  on a token, or in the middle of a battle?
- **The battle report.** Every live arrow has its column of tin soldiers marching it (in a longboat over
  a sea lane). A battle tips down out of the board's own camera, and rises back to it.
- **L** switches the chart and the land at any moment. Does anything stay behind (garrisons on the
  chart, a missing token, a wrong highlight)?
- **Frame rate.** Say what fps you get on the land (and on which GPU), whole map and zoomed in. On a
  slow machine the land gives up its dearest effects a step at a time (fewer shadow splits and no
  ambient occlusion, then no shadows from the woods and no MSAA, then no shadows, then a lower
  resolution) once it runs under 40 fps for a few seconds: say if you see it change.
- **Compatibility** (Linux without Vulkan): on the Mac with `--rendering-method gl_compatibility` the
  land draws and `v20b` passes; say whether it does for you.

- **The handoff.** The board swoops in, then the same picture tips up into 3D and the land rises. At the
  end the pieces lift off and the land sinks back into the board. **Poke:** any battle. Is there a jump,
  a flash, or a token left floating at either end? Esc and "Skip battles" in the middle of it.
- **Where they stand.** Columns at the border they crossed, boats for a sea lane, the defender split to
  face every front, a border clash on the border. **Poke:** a three-way melee, a landing over a lane on
  the Known World or the Thousand Isles, a border clash. Does any army stand in the sea, in another land,
  or under the title, the call plate or the dice tray?
- **One die, one man.** The front rank aims and fires, and the loser's man drops as the shot lands.
  **Poke:** reserves arriving (more men walk in), a horse going down (four men step up), Fortune's
  rethrow. Do the men standing always match the count?
- **Sound.** A crack per musket, falls that sound like the ground (snow, sand, stone, mud), the drum
  quickening near the end, oars and the beach on a landing; a hurrah when a side wins, horses at the
  gallop, steel at the charge, the guns on a fort's or a capital's walls. Close over the land: wind,
  surf, a ship's timbers.
- **The fight's life.** The front rank reloads after it fires, the winners cheer, the beaten run with a
  look back, the fallen lie where they fell, a gunner fires his cannon and rams the next charge, and
  each army's commander watches from his horse behind it. **Poke:** does anyone stand inside a
  building, or does a building hide a fight from the camera?
- **Fixed: the land's borders.** Round one's land never found where two lands meet (no roads, no passes,
  columns halfway between the hearts). Now every crossing is found (`tests/test_v20.gd`), the roads run
  over them, bridges carry them over the lowland rivers, and columns halt at their real border.
- **Probes** are held to 60 fps now (`tools/probe.gd`): under Forward+ on a 120 Hz screen the frame-
  counting probes ran twice as fast and failed. If any probe is flaky on your machine, say at what fps.
- New probes: `v20` (the real client: a melee at the Gate and a landing), `v20b` (the board on the
  land in the real client: tokens, clicks, zoom, garrisons, the highlights, L, the report's columns, a
  battle out of the board and back), `diorama` (every map's battle), `board3d` (the board over the land).

## v1.14: a senior pass on the polish (this push)

No rule changes: new games still play **rules 20**, nothing in `engine/` changed, every save replays
as before, and the arena fingerprints are unchanged. Everything here is what the table shows, says,
and does with a key.

- **B-009..B-012 fixed** (the seat called "You"). **Poke:** play as "You" on the ring with claiming on:
  "Your pick", the tooltip's "You hold 5 of 6", "takes the lead from you." in the recap, "You have been
  defeated". Then watch the battle report for any "You's", "You raises", "You is" or "You has".
- **Fate marks:** half as big again, a broken banner for a scramble lost (not crossed swords), and
  never on a land's name. **Poke:** a busy round 2. Can you tell a scramble lost from a sword plate?
- **CUT OFF** moves under the land's name when a fate mark sits at its walls.
- **A region's bonus and pips** keep off the tokens and the names, on the region's own lands or the
  water off them. **Poke:** every map at 1280×800 and 1440×900, at the fit zoom and zoomed in. Does
  any bonus read as its neighbour's? (The Ring's Crown has no clear spot; it takes the least-covered.)
- **Keys:** a dialog over the table takes the keys; Esc closes Settings, the plan and the dice help;
  ⌘↩/Ctrl+Enter does what the dial does; Space goes on from the round's report (not in its first
  moment). **Poke:** mash Space through a battle report and see the round's report stay up; ⌘↩ with
  the pause menu, the cards or the rules open; C twice.

## v1.13: the map says what the engine knows, and the big moments land

No rule changes: new games still play **rules 20**, and every save replays as before (the arena
fingerprints below v1.12 are unchanged). Everything here is what the table shows and says.

- **Last round's columns carry their fate.** The faint arrows you plan over now say what happened:
  a red cross where a column was thrown back (or fell back, or lost the scramble), and a column
  beaten in a border clash stops halfway, where it died, with a cross there. Hover the land for the
  words ("Varek's 7 were thrown back by Dad.").
  - **Poke:** probe `v113`, and any war on the Isles or the Ring. `tests/test_v113.gd` checks every
    column's fate against the world in whole AI wars on three maps; tell us any cross that sits on a
    land the column actually took, or a clash with no half-arrow.
- **A sword plate on your lands that could be outnumbered next round**, with the most one enemy
  could bring. Your capital rings crimson as soon as it could be outnumbered at all. It updates as
  you place recruits and give orders.
  - **Poke:** it should never cover a number or the garrison shield, and on a crowded map it
    shouldn't be on every land (it needs about 1.5× your men and 3 more).
- **An amber dashed ring (supply maps): a land that holds the road home for others.** The tooltip
  names them; sealing an order that leaves one with a single man warns you.
- **Region pips** beside each region's bonus: one per land, in its holder's colour, biggest holder
  first; a pulsing ring on the last land someone needs. The tooltip adds "Varek holds 5 of 7" and,
  for a region with three ways in or fewer, where they are (Great Vane: two).
- **The land tooltip** now says all of the above; the roster shows each commander's recruits for
  next round (+N); the recruits' breakdown adds up to the total (capital and levée included, only
  lands in supply paying; it used to leave them out). A cut-off land's recruit message no longer
  says "at most 0 (1 + your -1 neighbouring lands)".
- **The recap** tells melees held, scrambles won, fall-backs and capitals taken (it used to skip
  them), names a border clash by the road it was fought on, and opens with a new leader or a
  capital won back.
- **The moments, played harder:**
  - **Against all odds:** any battle won with under a 30% chance, whoever fought, gets a gold shout,
    a fanfare, and "Decided, against N% odds" under the bar. The report's cards say it too.
  - **The last man:** a side down to one man against three or more gets "ONE MAN LEFT" and a
    drum roll; winning with him gets "THE LAST MAN STANDING!". The advisor's close-call lines now
    always play.
  - **The lead:** a new leader on points opens the recap with a flag snap, the roster's crown pops
    across, and the advisor says so when it's our lead won or lost.
  - **The endgame music carries through** the regroup, the battles and the recap of the last rounds
    (it used to drop back to the ordinary themes). The ending's music starts with the tally,
    after the film, not ducked under it; when an AI wins, the advisor's defeat line follows theirs.
  - A capital's fall filmed: the commander's line now plays after the film (it was cut off). The
    court fleeing raises a flag (a sound). The capital-choosing line is voiced.
  - **Poke:** the voice queue. Several moments in one round (a lead change, a region, a capital)
    must never talk over each other or leave the music ducked.
- **Tooling:** `scripts/check.sh` (the short pre-commit check, ~10 s: compile, tool tests, the
  newest test file) and `scripts/probes.sh` (every probe, failing on any `FAIL`, `SCRIPT ERROR` or
  hang). `tools/test_one.gd` no longer plays sessions into the real save slot.
  - **Poke:** `GODOT=godot ./scripts/probes.sh` under Xvfb end to end: it should end without
    `probes: failed:`. `v112` now also checks where each army stands in a three- and a five-way
    scramble.

## v1.13.2: your critic's trims to reading the map

- **Enemy ceilings (`≤N`)** show only on enemy lands that border yours, and on the one you hover.
  - **Poke:** round 2 on the ring and the Isles. Count the numbers on the map. Hovering a far enemy
    land should show its ceiling.
- **The "ways in" line** names its region ("2 ways into Great Vane: …"). An entrance at the land
  you hover says "(here)".
- **The land tooltip** sits beside its land on the outer side, else above or below it, and wraps
  past 400 px.
  - **Poke:** hover lands at every edge and in the middle, at 1280×800 as well as 1440×900. It must
    never cover the land you hover, run off the screen, or sit under the command bar.
- **Fate marks:** a red cross (thrown back), a pale double chevron pointing the way the survivors
  went (fell back), crossed swords (beaten in a scramble). A column beaten in a border clash still
  stops halfway.
  - **Poke:** a busy round 2. Can you tell each fate apart without hovering?

## v1.13.1: fixes from your report on 0b2fe07

- **B-005..B-008 fixed.** Poke: a seat named "You" in the recap, the tooltips and the report ("your",
  "you were"); the round banner while your battle waits for a call; Esc during the swoop; a land two of
  your columns took together (one line: "Your 10 (from A and B) took it.").

## v1.12: the fled court, a fairer Thousand Isles, a war you can hear

New games play **rules 20**.

- **A three-way scramble looks like one.** When three or more commanders march on an empty land, each
  army gets its own ground: left, right, and a row at the back that turns to face whoever it fires
  at. Each ring stands over its own army.
  - **Poke:** probe `v112`, and any war with 4–5 commanders. No two armies should share a side as if
    allied, and nothing should overlap the odds bar.
- **A fallen capital's court** flees to the land deepest among the commander's own (not the biggest
  stack), with one fresh troop and the garrison dug in to the full.
  - **Poke:** conservation and the report (`tests/test_v112.gd` checks both), and what the AI does
    with a capital that's now thinly held.
- **Map amendments.** The Thousand Isles' Great Vane pays 3 under rules 20. A rules 19 save still
  pays 4.
  - **Poke:** load an old Isles save. It must replay (no hash mismatch), and the region labels must
    show the old bonus.
- **Border clashes** clear the beaten column's arrow, even when you skip past its card.
  - **Poke:** Battles: mine, several AI clashes, Space through the report. No arrow may be left for
    a column that died in the field.
- **The war around you:** distant sounds while planning (on the ambience slider), smoke over lands
  that changed hands, and the map's light warming toward dusk in the last rounds.
  - **Poke:** it should never hide a token or number, the seat colours must stay readable at dusk,
    and it should be silent at Ambience 0.
- **B-004 fixed** (the lessons test needed local review data).
- **Fingerprints (Mac, 28 Sep 2026, rules 20)** for `arena.gd -- map=<m> n=6 seats=general,veteran,recruit,hask seed=500`:
  `known24` → `f782eba38886`, `world30` → `d9f01fe55802`. The CLI hashes below are unchanged (the
  CLI plays the old rules).

## v1.11: the review table learns

Mostly tooling: the review table, and how assets get made. What reaches the game:

- **Speech bubbles and subtitles no longer show `*stars*`.** A line like "They dare to sit in
  \*my\* capital?" printed its stars.
  - **Poke:** play a few rounds and watch the commanders' bubbles and the eliminated card.
    `grep -n '\*' game/data/lines.json` lists the lines that carry stars.
- **The volley flash is timed to the shot again.** The redone standing and kneeling volley sheets
  had lost their `shot`/`muzzle` marks, so the flash fell back to default timing.
  - **Poke:** in any battle (probes `v111`, `v18`), the flash and smoke should leave the muzzle as
    the dice land, not before and not from the soldier's chest.
- **The eliminated film is re-encoded smaller** (Theora q5).
  - **Poke:** `v19` plays it; it should look the same as before.
- **Fingerprints (Mac, 27 Sep 2026, rules 19: superseded by v1.12's above)** for `arena.gd -- map=<m> n=6 seats=general,veteran,recruit,hask seed=500`:
  `known24` → `5ccf6e1a9a75`, `world30` → `fdc5601fe4b7`.
  - **Poke:** a different fingerprint on Linux, with no code change between the two runs, means
    the engine isn't deterministic across machines. That would break shared saves: please report it
    first. CLI matches: `cli.gd -- dump --seed 1` → `finalHash=1cce342a`, seed 2 → `a71862b8`,
    seed 3 → `6946e2ea`.

## v1.10: Fortune in every fight (still worth poking)

- Every fight earns Fortune now: clashes, melees, the scramble for spoils. Expect about 1.8–2.1
  favours per commander per war (`arena.gd` prints it).
  - **Poke:** a long human war where the human never gets a favour.
- **Fortune in melees.** The defender, or the commander of any attacking front, can call on it
  after a bad exchange, and the exchange is thrown again for everyone in it.
  - **Poke:** the favour is taken from the right commander (the roster stars), and the rethrow
    shows.
- **Second-wave surges.** A surge into a land your own direct attack just took marches in to hold
  it; a surge into a land that held storms what's left.
  - **Poke:** conservation. No armies appear or vanish (the report's totals).
- **Ties are re-fired.** An even volley is thrown again as its own labelled throw.
  - **Poke:** never four or five dice in one throw without the "fired again" label.
- **The final chart is the same size in all three modes**, with capital markers inside it and
  labels that don't overlap.
  - **Poke:** 1440×900 and larger windows.
- **The CLI and the v13/ui probes** (your B1–B3 from `f5ee031`) should all pass now.

## Standing checks (every push)

- All tests, every probe, the tool tests, and the CLI with `</dev/null`.
- A soak: `arena.gd` on `known24`, `world30` and `isles24`, n=20, with both `deal=draft` and
  `deal=random`. No `VIOLATION` or `SCRIPT ERROR`, and every war ends.
- Screens fit **1440×900**: setup, settings, How to Play, game over. Look for clipped text and
  buttons off-screen.
- A save made mid-war loads and replays to the same world hash (the tests do this; a real save from
  a probe run is better still).
