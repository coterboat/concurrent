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
     Since v1.11 a redo reads the note: it becomes direction for a voice line and a rewritten
     prompt for a picture or film (`tools/ludo/notes.py`, guided by
     [PROMPTING.md](PROMPTING.md)). A voice redo rolls 3 takes into `.takes/` beside the file,
     keeping the rejected one as `<name>.r<N>`; the table plays them side by side, and
     accepting one records it as the item's **pick**, which install copies.

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

## Voices on this Mac: VoiceStudio (free, local)

[VoiceStudio](https://github.com/debpalash/VoiceStudio) (cloned to `~/Documents/GitHub/VoiceStudio`)
runs k2-fsa's OmniVoice on the Mac's GPU. It serves a local API at `http://127.0.0.1:3900`, and an
MCP server at `/mcp/` (`.mcp.json`). No credits and no key; nothing leaves the machine.

- `tools/voicestudio/vs.py` is the client: `generate(text, out, ref_audio, ref_text, seed)` clones a
  voice from a reference clip plus its transcript, and `instruct="male, elderly, low pitch, british
  accent"` designs one instead. OmniVoice also reads `[laughter]`, `[sigh]` and
  `[dissatisfaction-hnn]` in the text.
- `tools/voicestudio/vs_samples.py` is the first pass (v1.14). Each voice is cloned from its own
  accepted takes (`REFS`) and says four lines the game already has. 3 takes of each go into the review
  batch `vs_voices`, loudness-matched to the Ludo take, and `0` in the table plays that Ludo take.
  Install replaces only what's accepted; Redo is free and reads the notes.
- `tools/voicestudio/vs_designs.py` designs new voices from a description alone (none of our audio
  goes in): three identities per commander (gender, age, pitch, accent, whisper, and a seed that
  picks the person). Each records a voice card (its greeting plus one line), and its other lines are
  cloned from that card so every line is the same person. Batch `vs_designs`. Its one button saves
  the identities whose card you accepted as VoiceStudio profiles.
- About 11 s to make a take of 3–6 s once the model is warm (17 s cold). The advisor and the commanders are saved in VoiceStudio as
  profiles named "CONCURRENT · …", so they can be used in its app too.

## Formats the code reads

### Battle sprite sheets: `assets/battle/<name>.webp` + `.json`

`{"cols", "rows", "fw", "fh", "frames", "ax", "ay", "fill", "order", "fps"?, "shot"?, "muzzle"?, "down"?}`

- `shot`/`muzzle` (a firing sheet) and `down` (a fall) are read off the frames by
  `v19_content.py` when it posts the sheet, and the battlefield times the flash and the fall to
  them. A sheet whose marks can't be found says so in its review check ("NO SHOT/FALL MARKS"):
  don't install it without them. `v19_content.py --remark <name>` re-reads them without touching
  the sheet or its verdict.

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
  `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg -i in.mp4 -c:v libtheora -q:v 5 -c:a libvorbis -q:a 4 out.ogv`.
  Quality 5 looks the same as 7 on these upscaled 480p films and is about 40% smaller (v1.10
  re-encoded all nine: 49 MB → 28 MB).
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

## Storage: what goes in git (v1.11)

Media is committed to plain git, not Git LFS. `./scripts/repo_size.sh` shows where it stands.
On 27 Sep 2026: the history (a full clone) was 338 MB, the current files 267 MB, and old versions
of assets only about 70 MB of it.

Why not LFS yet:

- **LFS doesn't make a clone smaller today.** It moves future versions of media out of git.
  Switching now, without rewriting history, means a fresh clone downloads the 338 MB history
  plus every current file again from LFS.
- **LFS downloads are metered.** GitHub gives 10 GiB a month free. The playtest bot clones on
  every push, 30–90 times a month at 270 MB or more each. Over the quota, LFS stops serving
  files, and a clone gets 130-byte pointer files where the art should be.
- **Half-adopting it is noisy.** Adding the LFS rules made 85 unchanged voice files show as
  modified in a test clone.

What keeps the size down instead:

- Masters (`assets/raw/`) and review takes (`review/`) are gitignored. Only what the game uses
  is committed.
- Encode for size. Films are Theora at `-q:v 5` (the pipeline's setting since v1.11; a redo
  used to write q7 at twice the size). Voices are mp3, and sheets and art are webp.
- Look at a big asset before committing it: `./scripts/repo_size.sh` lists the largest.

**When to switch:** when the history nears ~1 GB. Then it is one planned step that rewrites
history: `git lfs migrate import --everything --include="*.png,*.webp,*.mp3,*.wav,*.ogv,*.glb"`,
a force-push, re-clones everywhere, the bot set up with `git lfs install` and a persistent
clone, and a pointer check in the probes. That needs the owner's go-ahead. `git-lfs` is already
installed on the dev Mac (Homebrew).

