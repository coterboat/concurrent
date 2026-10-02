# CONCURRENT

A SameTime conquest game of rival empires. Everyone writes their orders in secret, everyone's orders happen at once, and the armies you send away leave home empty. Whoever strips a border gets walked.

Two to five commanders on one of six maps. Any seat can be a person at this computer (hotseat) or one of six AI commanders, from easy to hard.

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
- **Surge.** Drag on from the land you're attacking to the next one: if you take it, the men who took it (from every direction) push on, up to the number you choose. All surges happen at once, after every other battle; two surges running at each other's lands clash head-on. A surge into a land you also attack directly is a second wave: if the first took it, the second marches in to hold it; if not, it storms what's left.
- **Regroup phase.** After the battles, everyone marches troops between their own neighbouring lands, one land per soldier, then the next round begins.
- **Garrisons.** The gold shield on a land is its garrison, who never march: its dug-in defenders, or on a land with none yet the one man who must stay behind. The big number is exactly who can march. Every round you keep a land, one more man digs in, up to three.
- **Cards** (bigger maps). Capturing earns a card: infantry, cavalry or artillery, each naming a land. Three alike or one of each turn in for 4, 6, 8, 10, then 5 more each time, plus a free soldier on every named land you hold. Take a commander's last land and their whole hand is yours; if several of you took their last lands in the same round, each throws a die and the cards are shared out in proportion to the throws.
- **What a land is.** Some maps give a land a standing character, shown by a small brass emblem on it. A **fortress** fires a line of six instead of five and takes one more man dug in. A **pass** lets no more than six storm it from any one land, surges and reserves included, however many you have there — come at it from two lands at once. A **port** is joined by sea to your other ports: troops march between them and supply runs along them, but you cannot attack down a sea link.
- **Supply** (some maps). Your largest connected body of lands — joined by land, or by your own ports — is in supply. A land cut off from it pays no income and takes no recruits (deployment aside), though it still fights and still digs in. The map says CUT OFF across it. A conquest that reaches too far is worth nothing until the road behind it is yours.
- **Capitals.** Every commander keeps a capital, marked with a crown: name it at deployment (or your first claim is it). It pays 2 recruits a round, fights like a fortress, and supply runs from it. Take a rival's and you plunder half their cards and raise 3 troops there; lose yours and the court flees deep into your own lands with its guard (one fresh troop, the walls fully manned), and you may move it next round.
- **Fortune** ✦. Bad luck banks favours: the ledger weighs every exchange against its odds, and each time the dice have cost you about half a battle, Fortune owes you one (start with one, hold three; a commander's next star fills with gold as the dice owe them). Every fight counts toward it (assaults, clashes, melees, scrambles). In a battle you're watching, after an exchange that went badly for you, spend one and the exchange is thrown again, for everyone in it. Assaults and melees, once a battle for each commander; only you ever spend yours.
- **Levée en masse.** Whoever trails the leader in lands raises a recruit for every three lands behind (up to four a round).
- **Reading the map.** While you plan, last round's columns stay on the map, faint, and one that failed ends in a mark for how: a red cross (thrown back), a chevron pointing the way they went (fell back), a broken banner (beaten in a scramble); one beaten in a border clash stops halfway, where it died. An enemy land that borders yours shows the most it could hold (≤N). A sword plate on a land of yours says it could be outnumbered next round (your capital rings crimson), an amber ring that it holds the road home for others, and the pips beside a region's bonus who holds how much of it. Hover any land to read it all in words; the roster shows what each commander raises next round.
- **Rules.** Standard is the full war we balance around; Recruit is a first war with fewer rules; Classic is Risk II odds; or customize any rule on the setup screen.
- **The lands.** Dealt at random, or claimed in turn: every commander's die drops onto the map for the order, then everyone claims one land at a time.
- **Winning.** After the last round, the highest score wins (lands + region bonuses). Holding 80% of the map, or being the last one standing, wins at once.

## What's in the box

| | |
|---|---|
| **Maps** | *The Isthmus* (7, the teaching map) · *The Marches* (18, the two-player duel) · *The Known World* (24, an island sea) · *The Thousand Isles* (24, an archipelago run on harbours) · *The Ring* (26, five realms around one crown) · *The Wide World* (30, six regions) |
| **You** | Six commanders to be — the Iron Duke, the Corsair, the Lioness, the Scholar, the Rajah, the Grenadier — or stay an anonymous silhouette. Click the portrait on the setup screen. |
| **Commanders** | Captain Oren of the Hussars (easy) · Commodore Hask, Governor Quill of the Company (medium) · Grand Marshal Varek, Viceroy Ysolde, Admiral Imre (hard). Hard commanders simulate several plans against predicted enemy moves before sealing. Each fights with a temperament: Hask and Ysolde throw in every reserve, Quill cuts his losses, Oren never knows when to quit. |
| **Modes** | Solo vs AI, hotseat for 2–5 people (a cover screen hides each sheet), mixed, or all-AI to watch |
| **Options** | Game length (short / standard / long / conquest), lands dealt or claimed in turn, planning clock, battle speed, the map and the battles on the map's own land in 3D (or the chart and the painted field), text size, advisor tips, colorblind-safe token shapes |
| **Presentation** | The map's own land in 3D, generated for any map (hills, ranges and passes, rivers and their bridges, woods, a village in every land, landmarks from the lands' names, a star fort on a fortress, a palace at a capital, ships under sail, every land's garrison in tin), with the board's own tokens and arrows over it; battles fought on that land, where each army came from. Or, L away: an imperial war room: a painted chart dressed with a compass rose, a title cartouche and ships of the line; heavy region borders and a regions view; a Risk II–style command bar in brass and gilt; a battlefield scene where tin soldiers march in, breathe, fire, topple and retreat; round reports, end-of-war chart; martial music (drums, brass, fifes) |
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
| Seal | **SEAL** on the dial (or ⌘↩ / Ctrl+Enter: whatever the dial says, so in the reinforcement phase it moves on to the orders first) |
| Zoom / pan | Mouse wheel or pinch / drag the sea or two-finger scroll; ⤢ shows the whole map |
| Edit an attack or march | Click the number on its arrow; ✓ OK or Enter closes the card |
| Cards | **Cards** in the command bar (or C) opens your hand; each card names a land, and turning in a card for a land you hold puts a free soldier there |
| Advisor's plan | The button in the dispatch panel drafts a whole sheet; adopt it or keep yours |
| Map view | **View** coin or V: owner colours ↔ region colours |
| The land in 3D | L, or the **3D / 2D** chip above the zoom buttons: the board stands on the map's own land in 3D (hills, woods, villages, ships, every land's garrison), or on the chart as it always was. Settings → *The land in 3D* holds both switches: the map and the battles |
| Battle scene | Space / ROLL = throw the next exchange; at a call Space = press on, R = reserves, F = fall back, T = call on Fortune; **? Dice** explains the scoring; Esc = skip the battles |
| Claiming lands | Click a free land on your turn; **PICK** takes the advisor's choice; **Hurry** speeds up the others |
| Battle report | Space = next, P = pause, Esc = skip to the report; on the round's report, Space or Enter = next round |
| Dialogs | Esc closes the pause menu, Settings, the cards, the rules and the advisor's plan (keeping your own); while one is open the map's keys wait |
| Fullscreen | F11, or Settings |

## For developers

**The review table** (where generated voices, pictures and films are accepted, rejected and installed): double-click **`Review Table.command`** in the repo folder, or run `./scripts/review.sh`. It opens at http://127.0.0.1:8765/ in your browser; keep its window open while you review.

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
| `./scripts/test.sh` | Full headless suite (counts drift upward — trust the run, not this line) |
| `godot --headless --path . --script res://tools/compile_check.gd` | Compile every script (catches UI errors in seconds) |
| `godot --headless --path . --script res://tools/arena.gd -- map=world30 n=40 seats=general,veteran,hask   # supply=/traits= A/B a rule on the same seeds` | AI tournament: win rates, game length, walk-ins, combat bands |
| `./scripts/combat_sim.sh` | Combat capture bands |
| `node tools/mapgen/mapgen.mjs knife7 marches18 known24 isles24 ring26 world30` | Regenerate map geography from `tools/mapgen/*.geo.json` |
| `./scripts/review.sh` (or double-click `Review Table.command`) | The review table: listen to, look at or watch a batch of generated assets and accept, reject or reword each one; **F** (Finish review) runs the batch's own Install accepted / Redo rejected from the page (see `tools/review/README.md`, and `docs/ASSETS.md` for the whole pipeline) |
| `godot --headless --script res://tools/contact.gd -- dir=res://assets/portraits match=you_ out=/tmp/sheet.png` | Contact sheet of an art batch, to judge it all at once |
| `python3 tools/ludo/ludo.py [ids…]` | Generate missing art/audio from `tools/ludo/manifest.json` (reads `LUDO_API_KEY` from `.env.local`; idempotent) |
| `./scripts/shot.sh ui` | Drive the real client and save screenshots (`SHOT_DIR=…`); `calls` plays a battle with live calls, `v13` a melee, the reinforcement phase and the cards, `v14` the dice, a scramble and the land draft, `v15` the phases, a surge with a count, the physics dice in battle and a card turn-in, `dice` the physics dice on their own (1,000 throws checked), `field` the formations, `input` clicks with the real mouse path, `v17` traits, supply and the setup screen, `v18` capitals and the spoils fix, `v19` Fortune's stars, the divided chest, the fading card star, the living title and a cutscene, `v110` melee Fortune and the chart, `v111` the volley's timing, `v112` three- and five-way scrambles and the clash arrows, `v113` last round's fates, threats, the road home, region pips and the moments (`./scripts/probes.sh` runs them all as facts) |
| `./scripts/check.sh` | The short check before a commit (~10 s; the pre-commit hook runs it once `./scripts/check.sh --install` has set it up) |
| `python3 tools/ludo/v12_content.py` | Rewrite the v1.2 manifest entries and `game/data/lines.json` (version-bumps anything whose prompt changed) |
| `python3 tools/ludo/pack_anims.py [--fetch]` | Pack Ludo animation masters into game sheets, checking every loop's seam and clipping |
| `./scripts/cli.sh play --seed 42` | Text-mode knife-fight vs the monkey |

Working notes for contributors (and Claude): [CLAUDE.md](CLAUDE.md), the engine's laws, the commands and the gotchas. Assets: [docs/ASSETS.md](docs/ASSETS.md).

Design history: [CONCURRENT_Build_Bible.pdf](CONCURRENT_Build_Bible.pdf) → [v0.2](CONCURRENT_Build_Bible_v0.2.pdf) → [BUILD_PLAN.md](BUILD_PLAN.md) → [docs/CHANGELOG.md](docs/CHANGELOG.md) (v1.0 and every rule amendment since the bible).

## Credits

- Art, music, sound effects, portrait reactions, portrait and soldier animations, the films (living paintings and cutscenes), the painted 3D pieces and the voiced lines were generated with [Ludo.ai](https://ludo.ai). The prompts are in `tools/ludo/manifest.json` (lines and the v1.2 art direction in `tools/ludo/v12_content.py`), and the job ledger is in `assets/ludo_ledger.json`.
- Fonts: Cinzel and Alegreya Sans, SIL Open Font License (`assets/fonts/OFL-*.txt`).
- Built with [Godot Engine](https://godotengine.org) (MIT).
- An original game in the SameTime tradition. Not affiliated with any published board game.
