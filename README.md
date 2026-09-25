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

- **Reinforce.** Each round you get armies: one per three lands you hold (at least 3), plus a little for a big connected empire and a bonus for each whole region. A land can take at most 1 + (your neighboring lands). Unplaced armies are lost.
- **Attack.** Send armies from your land at a neighbor. They leave home the moment orders are sealed. One must stay behind unless the land is dug in.
- **Battles.** Roll by roll: each volley both sides score die × 5 + armies, and the lower score loses a man (ties go to the attacker). In your own battles you press ROLL. A setup option switches to one decisive roll (armies + a die); both styles give the same odds.
- **Battle calls.** An assault runs in exchanges of three volleys. After each one the attacker calls it: **press on**, throw in the **reserves** still at home (once), or **fall back** and save the survivors. Watch your own battles and you make the calls. Otherwise your officers follow the standing order on the attack (officer's judgment, to the last man, all in, or fall back if it turns).
- **Clashes and melees.** Two lands attacking each other meet in the field first. Several commanders storming one land fight it at once: the defenders split their strength across the fronts, and the survivors then fight for the spoils.
- **Surge.** Order it from the land you're attacking: if you take it, everyone who took it (from every direction) but one pushes on, after all other battles.
- **Reinforcement phase.** After the battles, everyone marches troops between their own neighbouring lands, one land per soldier, then the next orders begin.
- **Dig in.** Every round you keep a land it gains a dug-in defender, who never marches. The big number on a land is its army; the dug-in defenders sit on the gold shield beside it.
- **Cards** (bigger maps). Capturing earns a card: infantry, cavalry or artillery. Three alike or one of each turn in for 4, 6, 8, 10, then 5 more each time.
- **Winning.** After the last round, the highest score wins (lands + region bonuses). Holding 80% of the map, or being the last one standing, wins at once.

## What's in the box

| | |
|---|---|
| **Maps** | *The Isthmus* (7 lands, the teaching map), *The Known World* (24 lands, an island sea), *The Wide World* (30 lands, six regions) |
| **Commanders** | Captain Oren of the Hussars (easy) · Commodore Hask, Governor Quill of the Company (medium) · Grand Marshal Varek, Viceroy Ysolde, Admiral Imre (hard). Hard commanders simulate several plans against predicted enemy moves before sealing. Each fights with a temperament: Hask and Ysolde throw in every reserve, Quill cuts his losses, Oren never knows when to quit. |
| **Modes** | Solo vs AI, hotseat for 2–5 people (a cover screen hides each sheet), mixed, or all-AI to watch |
| **Options** | Game length (short / standard / long / conquest), planning clock, battle speed, text size, advisor tips, colorblind-safe token shapes |
| **Presentation** | An imperial war room: a painted chart dressed with a compass rose, a title cartouche and ships of the line; heavy region borders and a regions view; a Risk II–style command bar in brass and gilt; a battlefield scene where tin soldiers march in, breathe, fire, topple and retreat; round reports, end-of-war chart; martial music (drums, brass, fifes) |
| **Characters** | Voiced commanders in gilded rings who breathe and talk (seamless animated loops) and whose faces react: greetings, battle cries, curses, walk-in taunts, retreats, farewells. A chief of staff who reads the board, warns you, counsels you mid-battle, and drafts a whole plan on request |
| **Saves** | The campaign autosaves after every round; *Continue* picks it up |

## Controls

| Do this | By |
|---|---|
| Select a land | Click it |
| Reinforce | Click your selected land again, or **+** in the order sheet. Right-click removes one. |
| Attack | With your land selected, click an enemy neighbor, or drag from your land onto it |
| March (reinforcement phase) | Drag from your land onto a neighbouring land of yours, or click one then the other; **Advisor's marches** plans them all |
| Surge | **Surge onward…** on an order, then click the next land |
| Seal | **Seal Orders** (or ⌘↩) |
| Zoom / pan | Mouse wheel or pinch / drag the sea or two-finger scroll; ⤢ shows the whole map |
| Edit an attack or march | Click the number on its arrow; ✓ OK or Enter closes the card |
| Cards | **Cards** in the command bar opens your hand |
| Advisor's plan | The button in the dispatch panel drafts a whole sheet; adopt it or keep yours |
| Map view | **View** coin or V: owner colours ↔ region colours |
| Battle scene | Space / ROLL = roll the next exchange; at a call Space = press on, R = reserves, F = fall back; Esc = skip the battles |
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
| `./scripts/shot.sh ui` | Drive the real client and save screenshots (`SHOT_DIR=…`); `calls` plays a battle with live calls, `v13` a melee, the reinforcement phase and the cards, `input` clicks with the real mouse path |
| `python3 tools/ludo/v12_content.py` | Rewrite the v1.2 manifest entries and `game/data/lines.json` (version-bumps anything whose prompt changed) |
| `python3 tools/ludo/pack_anims.py [--fetch]` | Pack Ludo animation masters into game sheets, checking every loop's seam and clipping |
| `./scripts/cli.sh play --seed 42` | Text-mode knife-fight vs the monkey |

Design history: [CONCURRENT_Build_Bible.pdf](CONCURRENT_Build_Bible.pdf) → [v0.2](CONCURRENT_Build_Bible_v0.2.pdf) → [BUILD_PLAN.md](BUILD_PLAN.md) → [docs/CHANGELOG.md](docs/CHANGELOG.md) (v1.0 and every rule amendment since the bible).

## Credits

- Art, music, sound effects, portrait reactions, portrait and soldier animations and all 87 voiced lines were generated with [Ludo.ai](https://ludo.ai). The prompts are in `tools/ludo/manifest.json` (lines and the v1.2 art direction in `tools/ludo/v12_content.py`), and the job ledger is in `assets/ludo_ledger.json`.
- Fonts: Cinzel and Alegreya Sans, SIL Open Font License (`assets/fonts/OFL-*.txt`).
- Built with [Godot Engine](https://godotengine.org) (MIT).
- An original game in the SameTime tradition. Not affiliated with any published board game.
