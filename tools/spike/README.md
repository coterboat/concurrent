# The diorama spike

The battle on the land itself, Risk 2's way, for any map. Pure presentation: nothing in `engine/`
changed, and the spike reads only what a battle event already carries (each front's `from`, its
size, the defender's).

## Run it

In this worktree (it renders with **Forward+**, set in `project.godot` here):

    $G --path . res://tools/spike/diorama.tscn -- map=known24
    $G --path . res://tools/spike/diorama.tscn -- map=world30 land=farwatch

Space replays, 1–6 picks a map, N the next land. Once the camera settles, drag to look round, wheel
to zoom. Add `quit` to close when it's done; with `--fixed-fps 30 --write-movie out.avi` that makes a
film.

Screenshots and facts: `SHOT_DIR=/dir MAPS=known24,world30 ./scripts/shot.sh diorama`, and
`GALLERY=1` for every map's land, whole and its high ground. Headless reliefs of every map, timed:
`$G --headless --path . --script res://tools/spike/terrain_dump.gd -- out=/dir`.

## What's in it

| File | What it does |
|---|---|
| `game/world3d/terrain.gd` | The lie of the land for any map, from mapgen's data texture and each region's terrain: coasts (beaches, cliffs where mountains meet the sea), rolling hills by terrain, ridged mountain ranges, dunes, river valleys on the borders between lowland lands, a level stage round every token, and a road from each land's heart over the middle of every border it shares (a pass in the hills). Seeded by the map, so a map always has the same land. 0.5–2 s a map. |
| `game/world3d/ground.gdshader` | The ground. With `realism` 0 it paints exactly what `map.gdshader` paints (as light, so the 2D board and the 3D world match to the pixel); with 1 it is lit land: grass, rock textured from the side on cliffs, snow up high, woods, rivers, beaches, a wash of each owner's colour at the land's edge. |
| `game/world3d/water.gdshader` | The sea, coloured by the depth of the ground under it, surf at the shore. |
| `game/world3d/world_view.gd` | The world: ground, sea, sun, sky, haze, and the camera rig that can stand where the 2D board's view is (straight down, nearly orthographic) and then tip onto the land (a dolly zoom: the land keeps its size as the lens widens). |
| `game/world3d/props.gd` | Model-railway woods, lone trees, pines up the hills, rocks; off the roads and the stages. |
| `game/world3d/diorama.gd` | A battle staged: each column at the border it crossed (the terrain's own crossing, or the beach a sea lane lands on), the defender split to face every front in proportion (as the rule splits him), painted tin soldiers recoloured to their commander, a toy's hop as they march in, a kick and smoke when they fire, a topple when the dice say so; the fallen stay down. The dice: `DiceStage`'s own physics (planned back from the engine's face), its dice moved into this world, one table per front on the ground between the lines, each die thrown from its commander's side. |
| `tools/spike/diorama_spike.gd` | The run: the real 2D board swoops in as the game does, the 3D world takes over under it, the map tips up and the land rises, the camera finds the side that sees every army from lowest down, three exchanges. Risk 2's plates over each army. |
| `tools/shots/diorama.gd` | The probe: the handoff is exact (the board's centre and the land's token land where the 3D world has them, 0 px), every column stands inside the land it attacks and nearer its own border than any other, nobody stands in the sea, every crossing is on the right side of its border, every army is on screen. |
| `game/ui/dice_stage.gd` | One addition, inert unless asked for: a die spec may carry `from_dir`, the bearing it is thrown in from. |

## Round two: in the real game (v2.0 draft, see docs/CHANGELOG.md)

| File | What it does |
|---|---|
| `game/world3d/land_field.gd` | The battle screen's backdrop when a battle is on the land: its own SubViewport at the screen's resolution, the land built in a background thread when a game's map loads, the handoff out of the board and back, the theater's armies placed with their geography (`setup_at`), the camera that frames them in the band the UI leaves clear, Risk 2 count plates. Answers BattleField's calls. |
| `game/ui/battle_theater.gd` | Hooks only: the land field beside the flat one, chosen per battle (Settings → Battlefield), `open` before the first engagement and `close` after the last. |
| `game/world3d/diorama.gd` | Rewritten as a general stage: any number of armies, groups (the defender's split), poses, boats, falls on the ground's own sound, the quickening drum, the sweep off the table. |
| `tools/ludo/v20_content.py` | The poses, the longboat and the sounds; review batch `review/v20_diorama` (run the review table from this checkout). |
| `tools/shots/v20.gd` | The real client: a melee at the Gate, a landing over a sea lane, a skip in the middle of the tilt. |
| `tools/spike/board3d.tscn`, `tools/shots/board3d.gd` | The proof: the real board over the land (chart, land, tilted, living). |
| `tools/spike/film_v20.gd`, `film_board3d.gd` | Films, with sound: `--fixed-fps 30 --write-movie out.avi res://tools/probe.tscn -- --script=...` |

## Round three: the board on the land, in the game (v2.0 draft)

| File | What it does |
|---|---|
| `game/world3d/land.gd` | The game's one land: built in a background thread when a map loads (terrain, the scenery plan, its models), one SubViewport the board and the battles both draw; the camera's driver ("board" or "battle"); the quality steps a slow machine takes. |
| `game/world3d/land_board.gd` | The board standing on the land: the board's projector and unprojector, its view as a camera (58° over the whole map, 42° zoomed in), the rise from the chart and back (L), the board's highlights on the ground, the garrisons, the report's marching columns, the land's sounds up close. |
| `game/world3d/scenery.gd` | Where every building goes (static `plan`, seeded by the map) and the buildings themselves: villages by terrain, landmarks by name, the rules as buildings (star fort, blockhouse, quay, palace with its commander's colours, a redoubt round a dug-in garrison), bridges, ships, frigates on the lanes. |
| `game/world3d/marches.gd` | The battle report's columns: tin soldiers marching each live arrow by road (a longboat over a lane). |
| `game/world3d/flag.gdshader` | A palace's colours, rippling. |
| `tools/shots/v20b.gd` | The probe: the board on the land in the real client, on three maps. |
| `tests/test_v20.gd` | Every touching pair of lands has its crossing and its road; a village on every land; the rules' and the names' buildings where they belong. |
| `tools/spike/scenery_plan.gd` | Headless: every map's scenery plan drawn over its relief. |
| `tools/spike/land_view.gd` | Every land piece on one sheet, at its size, beside a tin soldier. |
| `tools/spike/perf_board.gd` | What the land costs a frame, against the chart, effect by effect. |
| `tools/spike/film_v20b.gd` | A film of a round on the board on the land, with its sound. |

## Not done yet

- A windmill's sails that turn, smoke from the chimneys, a flag that isn't a quad (each piece is one mesh).
- A fallen horse; a gun crew of more than one.
- The compass rose and the title cartouche stay painted on the chart's sea over the land.
