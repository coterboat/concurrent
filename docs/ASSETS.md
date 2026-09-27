# Assets: where they come from and how they get into the game

Everything the game shows or plays was generated with Ludo.ai, except the fonts. This page
covers the pipeline from a prompt to a file in `assets/`, and the formats the code expects.
Ludo's capabilities and prices are in [LUDO_CAPABILITIES.md](LUDO_CAPABILITIES.md).

## The loop: generate → review → install

1. **Generate.** `tools/ludo/ludo.py` runs Ludo jobs from `tools/ludo/manifest.json`
   (idempotent, a stable `request_id` per asset version, every charged call written to
   `assets/ludo_ledger.json`). The content scripts (`tools/ludo/vNN_content.py`) write the
   manifest entries for a release and build its review batches.
2. **Review.** `python3 tools/review/review.py serve --open` → http://127.0.0.1:8765. Each
   batch is `review/<batch>/batch.json` (gitignored). Listen, look or watch, then **A**ccept or
   **R**eject, with an optional reworded line or a note. **F** (Finish review) shows the
   counts and the batch's own actions.
3. **Install / redo.** The batch declares its actions in `batch.json` (below), and the review
   table runs them from the page with a live log:
   - **Install accepted** copies the accepted takes to their `target` paths and re-imports in
     Godot.
   - **Redo rejected** regenerates the rejected takes. This spends credits, so it asks first.
     The new take lands on the same review file and comes back as "needs a listen".

Some releases also install straight into the game so the owner can judge an asset in
place (video especially). The batch still lists each one, so a rejection sends it back
for another take. `git checkout` restores the previous version.

### `batch.json` actions

```json
"actions": [
  {"id": "install", "kind": "install", "label": "Install accepted", "help": "…",
   "cmd": ["python3", "tools/ludo/v19_content.py", "--install", "--batch-name", "v19_dice"],
   "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": false}]},
  {"id": "regen", "kind": "regen", "label": "Redo rejected", "help": "… (spends credits)",
   "cmd": ["python3", "tools/ludo/v19_content.py", "--regen", "--batch-name", "v19_dice"], "spends": true}
]
```

- Option types are `bool`, `int` (`min`/`max`), `string` and `choice` (`choices`).
- The browser sends only an action id and option values. The server builds the command
  from the file.
- Only `python3` is allowed, with a script inside the repo.
- Every POST needs the page's token.
- Full contract: `tools/review/README.md`.

## Formats the code reads

### Battle sprite sheets: `assets/battle/<name>.webp` + `.json`

`{"cols", "rows", "fw", "fh", "frames", "ax", "ay", "fill", "order", "fps"?}`

- `fw`/`fh` are the frame size.
- `ax`/`ay` are the feet anchor, as a fraction of the frame.
- `fill` is the figure's height as a fraction of the frame, so every sheet draws at one scale.
- `order` is the playback order (ping-pong idles, raise-fire-lower).
- Masters live in `assets/raw/battle` (not in git). `tools/ludo/pack_anims.py` packs them, and
  checks every loop's seam and clipping with `tools/sheet_tool.gd check`.
- The battlefield (`game/ui/battle_field.gd`) tints the figures in the army's colour, so they
  are white tin.

### Effect sheets: `assets/fx/<name>.webp` + `.json` (v1.9)

`{"cols", "rows", "fw", "fh", "frames", "fps", "loop", "ax", "ay", "order"?, "faces"?}`

- `ax`/`ay` is the emitter point: the muzzle for smoke, the ground for dust.
- `faces` is the direction the shot and smoke travel in the sheet. The left-hand army's
  effects are mirrored.
- Effect sheets are **never tinted**. That is why they are separate from the figures.
- `BattleField.burst(name, pos, px, toward_right, delay)` plays one, and falls back to the
  drawn smoke when the sheet is missing.
- Used today: `smoke_musket`, `cannon_blast`, `dust_kick` (a man falls), `fort_explosion`
  (a gun is destroyed). Also available: `capital_fire` (a loop), `fuse_spark`.

### Portrait loops: `assets/portraits/loops/<who>_{idle,talk}.webp` + `.json`

- 256 px frames. The generated loop's last frame duplicates its first, so it is dropped.
- A loop with a seam plays back and forth (`order`).
- A loop may carry its own `fps`: the v1.9 talk loops (Hydra, 35 frames, real mouth shapes)
  play at 12–14. Without one, a loop plays at 8.

### Video: `assets/video/*.ogv` (v1.9)

- Godot plays **Ogg Theora** only. Convert with the keg-only full build:
  `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg -i in.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 4 out.ogv`.
- Keep the mp4 masters in `assets/raw/video/`.
- **Living paintings** (`title_loop`, `victory_loop`, `defeat_loop`):
  - Their first frame is the still painting, and they loop seamlessly (the last half-second
    is crossfaded into the start).
  - `game/ui/living_painting.gd` shows the still, fades the film in over it, and cover-scales
    it.
  - Their sound goes to the Ambience bus.
- **Cutscenes** (`cut_intro`, `cut_capital_taken`, `cut_capital_lost`, `cut_eliminated`,
  `cut_victory`, `cut_defeat`):
  - 16:9 with music and effects, **no speech**. The advisor's own line plays over them.
  - `game/ui/cutscene.gd` plays each one once a war, and any key or click skips.
  - `game_screen.gd` `_film()` pauses the battle report while one plays.
- Settings → **Films**: cutscenes and living paintings / living paintings only / stills.

### Textures and interface art

- `assets/tex/felt.webp`, `rail_wood.webp`, `brass.webp` are seamless.
  - The dice tray (`game/ui/dice_stage.gd`) tiles them.
  - It takes each one's normal map from its own light and dark
    (`Image.bump_map_to_normal_map`), once per run.
- `assets/hud/plaque.png` is the brass score plate on the tray's front rail. Its parchment
  inset is about x 62–575, y 22–96 of 640×132.
- `assets/hud/fortune_star.png` and `fortune_empty.png` are Fortune's favours, a held star and
  an empty socket (`game/ui/fortune_pips.gd`; drawn stars stand in when they're missing).

### Music moods: `assets/audio/music/`

`Audio.PLAYLISTS` maps a mood to its takes, and never plays the same take twice running.

| Mood | When |
|---|---|
| `plan` | the planning phases |
| `battle`, `charge` | the battles |
| `besieged` | a human's capital has a rival army at least its size next door |
| `endgame` | the last two rounds, or someone within 85% of a conquest |
| `victory` + `march_song` | the victory screen |
| `defeat` + `lament` | the defeat screen |

`Audio.has_music(mood)` checks for a take before switching, so a mood whose files haven't
been generated yet is simply skipped.

### Sound effects: `assets/audio/sfx/*.wav`

- `tools/ludo/prep_sfx.py` trims and normalizes each one and registers it.
- `Audio.has_sfx(name)` lets new code fall back to an older sound until the new one lands.
