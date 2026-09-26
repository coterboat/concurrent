# CONCURRENT

A SameTime conquest game of rival empires. Everyone writes their orders in secret, everyone's orders happen at once, and the armies you send away leave home empty. Whoever strips a border gets walked.

Two to five commanders on one of three maps. Any seat can be a person at this computer (hotseat) or one of six AI commanders, from easy to hard.

## Play it

**On this Mac:** build the launcher once, then double-click it like any app.

```bash
./scripts/make_launcher.sh ~/Desktop
```

That puts `CONCURRENT.app` on the Desktop. Drag it to the Dock. It runs through the Godot 4.5 already installed in `~/Downloads/Godot.app`.

**On another computer** (no Godot needed there): install Godot's export templates once (Godot → Editor → Manage Export Templates → Download and Install), then:

```bash
./scripts/export.sh
```

That builds `build/CONCURRENT-mac.zip` and `build/windows/CONCURRENT.exe`.

**First time?** Choose *Play the Tutorial* on the title screen. It is a short game on The Isthmus against Captain Oren (the easy commander). The advisor explains one idea each round. The illustrated *How to Play* pages are always one click away, including mid-game via the **? Rules** button.

## The rules in one minute

Every round has four phases, each announced as it begins: **Reinforcement** (place recruits, turn in cards), **Orders** (attacks and surges, sealed in secret), **the Battles** (everyone's orders at once: border clashes, then the assaults, then every surge together, then the reckoning), and **Regroup** (march troops one land toward the front).

- **Reinforce.** Each round you get armies: one per three lands you hold (at least 3), plus a little for a big connected empire and a bonus for each whole region. A land can take at most 1 + (your neighboring lands). Unplaced armies are lost.
- **Attack.** Send armies from your land at a neighbor. They leave home the moment orders are sealed. Every land keeps its garrison (the shield) at home; everyone else may march.
- **Battles.** Roll by roll: each volley both sides score pips × 5 + the men in their firing line (at most five), and the lower score loses a man; an even volley is fired again. A bigger army wins by staying power, not by winning every volley. In your own battles you press ROLL and throw real dice onto the war table (a physics simulation: they tumble, bounce off the rails and knock into each other, and land on the engine's roll); every die's sum is written under it and a bar shows your odds from here. Bigger armies throw finer dice, from whittled wood to gold. A setup option switches to one decisive roll (armies + a die); both styles give the same odds.
- **Battle calls.** An assault runs in exchanges of three volleys. After each one the attacker calls it: **press on**, throw in the **reserves** still at home (once), or **fall back** and save the survivors. Watch your own battles and you make the calls. Otherwise your officers follow the standing order on the attack (officer's judgment, to the last man, all in, or fall back if it turns).
- **Clashes, melees and scrambles.** Two lands attacking each other meet in the field first. Several commanders storming one land fight it at once: the defenders split their strength across the fronts. When the defenders fall, or several armies march into the same empty land, the victors fight it out all at once in a scramble; the last army standing takes it.
- **Surge.** Drag on from the land you're attacking to the next one: if you take it, the men who took it (from every direction) push on, up to the number you choose. All surges happen at once, after every other battle; two surges running at each other's lands clash head-on.
- **Regroup phase.** After the battles, everyone marches troops between their own neighbouring lands, one land per soldier, then the next round begins.
- **Garrisons.** The gold shield on a land is its garrison, who never march: its dug-in defenders, or on a land with none yet the one man who must stay behind. The big number is exactly who can march. Every round you keep a land, one more man digs in, up to three.
- **Cards** (bigger maps). Capturing earns a card: infantry, cavalry or artillery, each naming a land. Three alike or one of each turn in for 4, 6, 8, 10, then 5 more each time, plus a free soldier on every named land you hold. Take a commander's last land and their whole hand is yours.
- **The lands.** Dealt at random, or claimed in turn: every commander's die drops onto the map for the order, then everyone claims one land at a time.
- **Winning.** After the last round, the highest score wins (lands + region bonuses). Holding 80% of the map, or being the last one standing, wins at once.

## What's in the box

| | |
|---|---|
| **Maps** | *The Isthmus* (7 lands, the teaching map), *The Known World* (24 lands, an island sea), *The Wide World* (30 lands, six regions) |
| **Commanders** | Captain Oren of the Hussars (easy) · Commodore Hask, Governor Quill of the Company (medium) · Grand Marshal Varek, Viceroy Ysolde, Admiral Imre (hard). Hard commanders simulate several plans against predicted enemy moves before sealing. Each fights with a temperament: Hask and Ysolde throw in every reserve, Quill cuts his losses, Oren never knows when to quit. |
| **Modes** | Solo vs AI, hotseat for 2–5 people (a cover screen hides each sheet), mixed, or all-AI to watch |
| **Options** | Game length (short / standard / long / conquest), lands dealt or claimed in turn, planning clock, battle speed, text size, advisor tips, colorblind-safe token shapes |
| **Presentation** | An imperial war room: a painted chart dressed with a compass rose, a title cartouche and ships of the line; heavy region borders and a regions view; a Risk II–style command bar in brass and gilt; a battlefield scene where tin soldiers march in, breathe, fire, topple and retreat; round reports, end-of-war chart; martial music (drums, brass, fifes) |
| **Characters** | Voiced commanders in gilded rings who breathe and talk (seamless animated loops) and whose faces react: greetings, battle cries, curses, walk-in taunts, retreats, farewells. A chief of staff who reads the board, warns you, counsels you mid-battle, and drafts a whole plan on request |
| **Saves** | The campaign autosaves after every round; *Continue* picks it up |

## Controls

| Do this | By |
|---|---|
| Select a land | Click it |
| Reinforce (reinforcement phase) | Click one of your lands to add a recruit; right-click takes one back. The dial's **ORDERS** (or Enter) moves on |
| Attack (orders phase) | With your land selected, click an enemy neighbor, or drag from your land onto it |
| Surge (orders phase) | Drag from the land you're attacking on to the next one (or **Surge onward…** on the order); click the surge arrow to choose how many |
| March (regroup phase) | Drag from your land onto a neighbouring land of yours, or click one then the other; **Advisor's marches** plans them all |
| Seal | **SEAL** on the dial (or ⌘↩) |
| Zoom / pan | Mouse wheel or pinch / drag the sea or two-finger scroll; ⤢ shows the whole map |
| Edit an attack or march | Click the number on its arrow; ✓ OK or Enter closes the card |
| Cards | **Cards** in the command bar (or C) opens your hand; each card names a land, and turning in a card for a land you hold puts a free soldier there |
| Advisor's plan | The button in the dispatch panel drafts a whole sheet; adopt it or keep yours |
| Map view | **View** coin or V: owner colours ↔ region colours |
| Battle scene | Space / ROLL = throw the next exchange; at a call Space = press on, R = reserves, F = fall back; **? Dice** explains the scoring; Esc = skip the battles |
| Claiming lands | Click a free land on your turn; **PICK** takes the advisor's choice; **Hurry** speeds up the others |
| Battle report | Space = next, P = pause, Esc = skip to the report |
| Fullscreen | F11, or Settings |

## For developers

Godot 4.5.1, GDScript, gl_compatibility. The rules kernel in `engine/` has no Nodes and no unseeded randomness. Every match replays to the same world hash from its seed and sheets.

```
engine/      rules kernel: types, combat, resolve queue, cards, setup, AI (ai.gd), autoplay
game/core/   session (match controller, saves), style/theme, settings, audio
game/board/  map shader + board (tokens, arrows, hit-testing, pan/zoom), map art loader
game/ui/     title, setup, game screen, order sheet, cinema, recap, game over, rules, settings
maps/        rules graphs (*.json) and generated geography (maps/art/)
assets/      Ludo.ai art + audio, OFL fonts
tools/       mapgen (Node), ludo (Python), arena, combat_sim, cli, screenshot probes
tests/       headless suite: kernel, queue T1–T8, properties, cards, AI, session
```

| Command | What |
|---|---|
| `./scripts/test.sh` | Full headless suite (399 checks) |
| `godot --headless --path . --script res://tools/compile_check.gd` | Compile every script (catches UI errors in seconds) |
| `godot --headless --path . --script res://tools/arena.gd -- map=world30 n=40 seats=general,veteran,hask` | AI tournament: win rates, game length, walk-ins, combat bands |
| `./scripts/combat_sim.sh` | Combat capture bands |
| `node tools/mapgen/mapgen.mjs knife7 known24 world30` | Regenerate map geography from `tools/mapgen/*.geo.json` |
| `python3 tools/ludo/ludo.py [ids…]` | Generate missing art/audio from `tools/ludo/manifest.json` (reads `LUDO_API_KEY` from `.env.local`; idempotent) |
| `./scripts/shot.sh ui` | Drive the real client and save screenshots (`SHOT_DIR=…`); `calls` plays a battle with live calls, `v13` a melee, the reinforcement phase and the cards, `v14` the dice, a scramble and the land draft, `v15` the phases, a surge with a count, the physics dice in battle and a card turn-in, `dice` the physics dice on their own (1,000 throws checked), `field` the formations, `input` clicks with the real mouse path |
| `python3 tools/ludo/v12_content.py` | Rewrite the v1.2 manifest entries and `game/data/lines.json` (version-bumps anything whose prompt changed) |
| `python3 tools/ludo/pack_anims.py [--fetch]` | Pack Ludo animation masters into game sheets, checking every loop's seam and clipping |
| `./scripts/cli.sh play --seed 42` | Text-mode knife-fight vs the monkey |

Design history: [CONCURRENT_Build_Bible.pdf](CONCURRENT_Build_Bible.pdf) → [v0.2](CONCURRENT_Build_Bible_v0.2.pdf) → [BUILD_PLAN.md](BUILD_PLAN.md) → [docs/CHANGELOG.md](docs/CHANGELOG.md) (v1.0 and every rule amendment since the bible).

## Credits

- Art, music, sound effects, portrait reactions, portrait and soldier animations and all 87 voiced lines were generated with [Ludo.ai](https://ludo.ai). The prompts are in `tools/ludo/manifest.json` (lines and the v1.2 art direction in `tools/ludo/v12_content.py`), and the job ledger is in `assets/ludo_ledger.json`.
- Fonts: Cinzel and Alegreya Sans, SIL Open Font License (`assets/fonts/OFL-*.txt`).
- Built with [Godot Engine](https://godotengine.org) (MIT).
- An original game in the SameTime tradition. Not affiliated with any published board game.
