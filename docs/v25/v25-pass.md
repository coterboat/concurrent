# v2.5 pass: what a first-time player on Dad's laptop would trip on

The general pass before the game goes to Dad, a first-time player. His PC (Alex, 11-03): a Lenovo laptop,
13 to 14 inches, likely integrated graphics, a 1920×1080 or 1366×768 screen. Branch
`claude/v25-pass-d4aa96`, on v2.4.1 (`df3b5e0`).

No rule changes: rules 23, nothing in `engine/` touched, so every save replays as it was played and the
arena's fingerprint is unchanged by construction (the arena loads only `engine/`). Done on the Windows PC
(RTX 3070; 1920×1080, 2560×1440 and 1080×1920 screens, all at 100%), Godot 4.7.1.

Written as I went. The coordinator writes the CHANGELOG and PLAYTEST from it.

## 1. Will it start on his PC? (the renderer)

**What I threw at it:**
- the renderer settings as Godot 4.7.1 reads them;
- a whole war on the Compatibility renderer (`--rendering-driver opengl3`, the OpenGL path a PC with
  neither Vulkan nor Direct3D 12 falls back to);
- the land and a battle shot under Vulkan and under OpenGL, at full quality and at the watchdog's lowest
  step (quality 4: no shadows, no MSAA, 0.7 resolution);
- the real exported `.exe`, started on OpenGL.

**Found:**
- **The fallback is on.** `project.godot` leaves the `rendering_device/fallback_to_*` switches at Godot's
  defaults, which are on: Vulkan, then Direct3D 12, then OpenGL 3.3, and OpenGL falls back to ANGLE
  (Direct3D 11 underneath) for old drivers. Nothing needed changing, but nothing held it: `test_v25` does now.
- **On OpenGL the game plays a whole war**: the Known World, 7 rounds, every battle opened on the land, no
  script error. The real `.exe` starts on OpenGL too.
- **But on OpenGL the land looked broken** (`docs/v25/v25-opengl-land.webp`: OpenGL before, OpenGL after,
  Vulkan):
  - Every building, fort and landmark was drawn near-black. The culprit is the "seating coat" (v2.0.2,
    `seat.gdshader`), a second multiply pass over each Ludo model. With it off, they're lit as on Vulkan.
    I didn't chase why Godot's GL renderer draws that pass dark: the coat is a finishing touch.
  - The sea went from navy to a flat warm grey, and the whole land greyed. The culprit is the haze
    (`env.fog_*`). With it off, the land is in Vulkan's colours, a little more saturated, and the sea is a
    deeper navy than Vulkan's (whose haze lifts it).
  - Found by turning each effect off in turn under OpenGL.
- **On OpenGL the land stepped itself down for nothing.** That renderer reports no timings, so the
  watchdog (v2.4) counts every slow frame against the land. The first frames' hitches took the land down
  a step during the war's opening, on an RTX 3070. They run 100 to 600 ms each, likely shader compiling
  (GL compiles a material the first time it's drawn).

**Fixed:**
- On the Compatibility renderer only, the buildings go without the coat (as they already went without
  the contact-shadow decals there) and the land without the haze (`scenery.gd` `_seat_coat`,
  `world_view.gd`). Vulkan and Direct3D 12 are untouched.
- A frame counts a tenth of a second at most against the land (`land.gd` `_watch_speed`). A hitch is one
  frame; sustained slowness still steps it down as before (a land at 30 fps counts in full).
  - v2.4.2's B-013 fix sits just above it: the watchdog fed the machine's own frame (`delta /
    Engine.time_scale`). It's carried here line for line, so the two branches merge clean (checked with
    `git merge-file` against `1953944`).

**Facts:** probe `v25` (45 facts, all passing) runs `tools/probes/v25_gl.gd` in a second Godot on OpenGL.
That child checks:
- the renderer is Compatibility;
- no coat and no haze there;
- the open sea's median colour reads blue: (0.00, 0.02, 0.08) over 590 points, where it was the haze's grey;
- the buildings' median brightness is 0.47, where they were near-black;
- the land kept every effect through the war's opening.

## 2. Will it fit his screen?

**What I threw at it.** Every screen a new player meets, each checked by a probe that walks every visible
control and lists any running off the screen, and measures the smallest text in real pixels:
- the title, setup, the tutorial's setup and settings;
- all 19 How to Play pages;
- the introductions, deployment, the orders, a land selected and the advisor's drafted sheet;
- a battle and the round's report.

At three window sizes, 1440×900 (the house standard), 1366×705 (a 1366×768 laptop's window, maximized)
and 1280×650 (a 1280×720 screen's), and at the text sizes Large (1.15) and Extra large (1.3). F11 to
fullscreen and back is in the walk (section 3).

**Found:**
- **Nothing clips at any window size at Normal text.** Whatever the window, the UI is laid out in at least
  1440×900 and scaled to fit (`canvas_items`, `expand`), so a small window only makes the words smaller.
  At 1366×705 the smallest text is 9.4 px (the 3D chip), body text 11 px and up, How to Play's 15 and up.
- **The window ran off a laptop's screen.** Its least size was 1180×720. A 1366×768 screen leaves 728
  under the taskbar, and the title bar and borders take 39 more (measured here: 16 wider, 39 taller). So
  the window was placed with its title bar above the top of the screen, out of reach. A 1280×720 screen
  was worse.
- **A 14-inch 1080p laptop runs Windows at 150%, and the game ignores it.** Godot sizes in real pixels, so
  on such a screen it opens the desktop's 85% window (1387×867), every word three-fifths the size Windows
  gives everything else. Likely Dad's case. (Worked out: this PC's screens are all at 100%, and changing
  that is a system setting.)
- **The land drew 1.6 times the pixels on a small window.** Its viewport was held to at least the UI's
  size (1743×900 on a 1366×705 window), on exactly the machines with the least to spare.
- **"Extra large" text broke the war's own screen.** At 1.3 the UI is laid out in 1108×692, and the bar
  ran off the foot of the screen: the ORDERS dial cut in half, the advisor's words and his Advisor's plan
  button below the edge. How to Play's Previous/Next, the settings' Done and the setup's Begin went too.
- **At "Large" (1.15) everything fits but the settings panel**, which stood 827 tall in a 783 screen, its
  Done below the edge. (The setup's map cards cut their names at Large: cosmetic, Q3.)

**Fixed:**
- **The window** (`game/core/window_fit.gd`, peeled out of `main.gd`):
  - its least size is never more than the screen holds;
  - it's centred with its title bar and borders counted;
  - a screen too small for 85% opens it maximized. "Too small" is under about 1390×850 as Windows shows
    the screen, so a 1366×768 laptop, a 1440×900 one, and a 1920×1080 laptop at 125% or 150%;
  - leaving fullscreen (F11) on such a screen comes back maximized;
  - a 1920×1080 desktop at 100% still opens a 1414×884 window, and a 4K monitor at 150% an 85% one.
- **The land renders at the window's real pixels** when the window is smaller than 1440×900 (`land.gd`).
- **Text size offers Normal and Large.** Large is the most the screens hold. A saved Extra large reads as
  Large (`settings.gd` `UI_SCALE_MAX`). On a 1366×768 laptop, Large takes the words from 78% to 90% of
  their design size.
- **The settings panel scrolls its rows** when the screen is shorter than they are; its title and Done
  stay put.
- **A laptop's first launch reads Large** (`main.gd` `first_text_size`). Alex 11-03, Dad's Lenovo, and the
  coordinator's go-ahead for robust defaults. A screen the window opens maximized on (a laptop's, as Windows
  shows it) starts at Large:
  - 1366×768: from 78% to 90% of the words' design size;
  - 1920×1080 at 150%: from 111% to 128%, where Windows gives everything else 150%.

  It happens only before a text size was ever saved: Alex's machines keep theirs, a desktop's screen keeps
  Normal, and Settings, Text size goes back to Normal any time. It isn't applied in the probes (a probe
  isn't the main scene), so their layouts are unchanged.

**Click targets on a laptop** (probe `v25` logs the smallest buttons of each screen, in the screen's own
pixels, at Large text):
- The big ones are fine: the dial 150 px, ROLL and the title's buttons 54 px, the zoom buttons 40.
- The small ones are the chips: Auto-place, Clear, Cards, Review, ◀ Recruits, ? Dice, Auto-roll and Skip
  battles. They're 22 to 24 px tall on a 1366×768 laptop, 28 to 31 at 1440×900, and about 20 at Normal
  text. That's small for a touchpad and older eyes; each has a bigger way round (the dial does the
  advisor's plan, Space rolls, Esc skips), but Q6 asks about raising them.

**Facts** (`tests/test_v25.gd`, probe `v25`):
- the window rule for seven screens (1366×768 to 4K) and for Windows at 100%, 125% and 150%;
- on a 1366×768 laptop's screen the real window maximizes with its least size inside;
- every screen above fits at Large text on a 1440×900 window and on a 1366×705 one: all 19 How to Play
  pages, the dial, the battle, the report;
- a saved 1.3 reads as 1.15;
- a first launch on a laptop's screen reads Large, a desktop's Normal, and a text size once saved is kept;
- on 1366×705 the land draws 1366×705 pixels.

## 3. A first-time player's war, end to end

**A walk, as Dad meets it** (`tools/first_war.gd`). It plays in the real save slot and settings, so it
refuses any user folder that isn't fresh; Windows keeps that folder under `%APPDATA%`, so the walk gets a
fresh one through `APPDATA`. It runs in two launches:
- **Step 1, the first launch:**
  1. The title offers the tutorial and nothing to continue.
  2. The settings are changed through the panel and written as they change.
  3. The tutorial starts and is left at its first orders. The title then offers it as Continue.
  4. New Game opens on the readme's war: the Known World, Standard, against Oren and Quill. Begin asks
     before ending the tutorial.
  5. The war is on the land, rules 23. Two rounds are played with his battles opened and rolled.
  6. Quit to title from the pause menu: the title offers the war at round 3. Two wars kept.
- **Step 2, the game opened again:**
  1. The settings came back, and the title offers round 3.
  2. F11 to fullscreen and back.
  3. Continue picks the war up at round 3, on the land.
  4. Played to its end (round 8 of 8), the ending shown, back on the title with nothing to continue.
  5. Both wars kept, and each replays to every round's hash (`tools/wars/replay.gd`).

**Where it ran:**
- **The project (the editor's Godot):** 22 of 22.
- **The exported game:** the pack inside a fresh `CONCURRENT.exe` (592 MB), run by the editor's Godot
  (`--main-pack`): 22 of 22. The exported `.exe` itself doesn't run `--script` (given the walk, it ran
  seven minutes and wrote and printed nothing), so that is how its pack is walked.
- **The real `.exe`**, from the outside (`exe_smoke.ps1`, in the shared notes): started on a fresh user
  folder, its window read back from Windows, a screenshot. It opens on its title (New Game, "First time?
  Play the Tutorial") at 1904×1190, 85% of the 2560×1440 screen, title bar on the screen; on OpenGL too.

**The words a new player reads, against rules 23.** A read-only audit (every How to Play page, the rules'
help, the README, Dad's readme, the tutorial and the advisor, every on-screen string); each finding was
checked against the code before it was fixed:
- **"(ties go to the attacker)" on the battle card**, after a win whose last volley's sums happened to
  match. That's true only of one decisive roll under rules before 17. In a fight of volleys an even volley
  is fired again, and the sums it compared were only the last volley's (`cinema.gd`).
- **The "Your lands" hint** said to click a land again "(or press +)" to add armies. A first click places
  one, and the only + on the screen is the zoom. In the orders it said "click your selected land again to
  add a recruit", where that click lets go of the land (`orders_panel.gd`). Now each says what a click
  does there.
- **The tutorial's round 2** pointed at "the gold shield". Since v2.4 one man dug in shows brass (gold is
  three) (`counsel.gd`).
- **The final round's advice**, "spend every soldier" and "soldiers left standing are worth nothing",
  invites stripping every border on the last round. Men who march leave home, and a bare land is walked
  into, so that costs lands on the score. Now: take what land you can, and keep enough at home to hold
  what you have. The advisor's voiced line is unchanged (Q4).
- **The battle's "so every volley is even"** meant "on level footing", where "an even volley" is the game's
  word for a tie that is fired again. Now: "so the dice alone decide each volley".
- **The dice line said "at most 5 a side" at a capital or a fortress**, where the defenders fire six. It
  adds "; 6 behind these walls" there (`battle_theater.gd`).
- **A scramble's plaque said an even volley is "fired again"**. In a scramble it costs nobody and isn't.
- **How to Play:**
  - "one more man digs in" read as a man turned garrison: he's a fresh man, free;
  - the levée (a Standard rule) was never explained on the Recruits page;
  - the regroup page ended "then the next round's orders begin" (the reinforcements come first).
  - The README said the same about digging in.
- **"Save & quit to title"** promised a save it doesn't make. The war is saved after every round, so
  quitting mid-round comes back to the round's start. It's "Quit to title" now, and the pause card says
  so.

## 4. Soaks, and the land on a laptop's graphics

**A whole war in the real client on the land, every battle opened** (`tools/soak.gd`). It now reports
each round's nodes, objects, memory, video memory, frames over 50 ms and the land's step, with two leak
facts; `SOAK_QUALITY=4` starts the land on its lowest step.

| map | renderer | rounds | battles | nodes after round 3 → end | memory | script errors |
|---|---|---|---|---|---|---|
| The Isthmus (knife7) | Vulkan | 5 | 8 | 691 → 801 | 208 → 229 MB | 0 |
| The Marches (marches18) | Vulkan | 9 | 44 | 916 → 1079 | 231 → 250 MB | 0 |
| The Known World (known24) | Vulkan | 7 | 39 | 1024 → 1183 | 226 → 247 MB | 0 |
| The Thousand Isles (isles24) | Vulkan | 9 | 41 | 1067 → 1261 | 232 → 252 MB | 0 |
| The Ring (ring26) | Vulkan | 9 | 57 | 1066 → 1329 | 247 → 266 MB | 0 |
| The Wide World (world30) | Vulkan | 9 | 58 | 1094 → 1338 | 226 → 243 MB | 0 |
| The Wide World (world30) | OpenGL | 9 | 58 | 1080 → 1328 | 182 → 204 MB | 0 |
| The Known World, before the fixes | OpenGL | 7 | | | | 0 |

- **No leak.** The nodes that rise over a war are all inside the land's 3D world (a census of the Ring by
  branch: 565, 599, 623, 660, 736, 736, 762 and 838 there, round by round, the rest of the screen flat).
  That is v2.4's figure pool: every figure a battle needed is kept to stand again, taken from the pool
  first, so it grows to the biggest battle so far and no further. Memory gains 17 to 22 MB over a war.
  Video memory sits at 1.2 to 1.4 GB on Vulkan once the land and a battle are loaded, 1.0 GB on OpenGL.
- **Errors:** the only ERROR lines are Godot's at exit (textures and text-server RIDs still held when the
  probe quits mid-scene). OpenGL lists each texture on a line of its own (96 of them); Vulkan counts them
  on one.
- **Frame times:** the soaks ran beside my other runs on one machine, so their slow-frame counts measure
  the sharing, not the game. The Ring's land even stepped down to 2 under that load. The quiet
  measurement is below.

**The land's cost on a laptop.** Measured quietly on the RTX 3070 at 1920×1080, the land's own GPU time a
frame (`viewport_get_measured_render_time_gpu`):

| step | on the board | in a battle |
|---|---|---|
| 0 (everything) | 5.3 ms | 4.1 ms |
| 1 (no SSAO, 2 shadow splits) | 4.5 | 3.3 |
| 2 (no MSAA, props cast no shadow) | 3.6 | 3.0 |
| 3 (no shadows) | 3.2 | 2.4 |
| 4 (0.7 resolution) | 2.2 | 1.8 |

An estimate, not a measurement: integrated graphics draw roughly an eighth of what the 3070 does (Iris Xe)
down to a twentieth (an older UHD 620).
- **On an Iris Xe at 1080p:** the board at step 0 is about 40 ms (25 fps), and about 18 ms at step 4.
  The watchdog takes it there in a few seconds, and now remembers it.
- **On a UHD 620:** about 45 ms even at step 4. That's where "press L for the flat chart" in Dad's readme
  earns its place.
- **At 1366×768:** about half the pixels, so about half these times (the land now draws the window's own
  pixels).

**A first-time war on OpenGL, both launches** (`tools/first_war.gd` with `--rendering-driver opengl3`):
23 of 23. The remembered step carried between the launches: with four Godots sharing the machine, the
land settled at 2 in the first and 4 in the second, then started the second war at 1 better.

**Tests:**
- **The full suite:** `CONCURRENT ok passed=831 failed=0` (815, plus test_v25's 16), no SCRIPT ERROR.
- **`check.sh`:** green.
- **The probes this pass touches**, one at a time on a quiet machine: v25 45 facts, v23 41 or 42 (the
  tutorial end to end, answering the new question; 41 when the war is won before its last round, as
  PLAYTEST says it can be), v24m 59, v113 36, v24b 28, v114 23, v19 12, v17 11, ui 1. All pass. The rest are untouched by this branch; v202, v21, v22 and v24p are v2.4.2's.
- **The arena:** 40 wars on the Known World (`deal=draft levee=3`, four AIs) with 0 violations, 0 split
  retreats a game, and Hask 15 of 40 (as in v2.4). The bot's command prints `fingerprint 12f8de1f36de`,
  which is main's: the arena loads only `engine/`, untouched here.
- **The monkey:** 1,000 of 1,000, no leaked armies.

## 5. Anything else that would make Dad stop playing

- **A new war wiped the saved one without a word.** "Tutorial" (on the title or in How to Play) and
  "Begin the Campaign" both replaced the war on Continue, so a war played over three evenings went at one
  click on Tutorial. Now they ask first: "Start a new war? Your war on The Known World is saved at round 5.
  Starting a new war ends it." [Start the new war] [Keep my war] (`main.gd` `new_war`,
  `game/ui/confirm.gd`). It's kept in `wars/` either way.
- **A save that couldn't be read left a Continue to nowhere.** A save cut short (a crash or a power cut
  mid-write), or one a newer build wrote, put "Continue · , round ?" on the title, or a Continue that led
  back to the title every time. Now:
  - the save is written whole beside the slot, then put in place;
  - a save with no summary isn't offered;
  - one that can't be picked up is set aside (`savegame.unreadable.json`, kept for Alex), with a line on
    the title saying so (`session.gd`, `title_screen.gd`).
- **A slow laptop chugged through the land's steps every war.** The watchdog started each war's land with
  every effect, and stepped down 3 s at a time: on integrated graphics, ten seconds and more of a
  chugging land every war, the first swoop to a battle among them. Now the land starts on the step this
  machine settled on last time, less one (`land.gd`, settings key `land_quality`). That way a machine
  that was only busy once climbs back a step a war, and a minute smooth at a better step is remembered.
  On Alex's PC nothing changes (it never steps down).
- **A machine the land hasn't measured yet starts it lower on integrated graphics** (`game/world3d/adapter.gd`,
  `land.gd` `_remembered`). This is what Dad's first war meets.
  - **How the graphics are told apart:** the driver says integrated or discrete on Vulkan and Direct3D 12.
    On OpenGL, which can't tell, the name does: Intel (but not Arc), a Ryzen's "Radeon(TM) Graphics" or
    Vega, and the software renderers (llvmpipe, SwiftShader, Microsoft Basic Render).
  - **Where it starts:** such a machine is taken to have settled on step 3, so its land starts at 2: no
    SSAO, no MSAA, two shadow splits. That's 3.6 ms on the 3070 against 5.3 at full, so about 29 ms
    against 42 on an Iris Xe. The watchdog takes it lower within seconds if that's still slow.
  - **And back up:** a minute smooth remembers the better step, so a capable Iris Xe climbs back to full
    over three wars.
  - **On a graphics card** it starts with everything, as before (`test_v25` names 13 adapters; probe
    `v25`: step 0 on this RTX 3070).
- **What `land.gd` changes around v2.4.2's line** (`_process`, `_watch_speed(delta / maxf(Engine.time_scale,
  0.0001))`, carried verbatim), for the merge:
  - the constants `Adapter` and `WEAK_START` at the top, and `var _smooth`;
  - `fit()`: `px` clamped from 0.5, not 1.0;
  - `_watch_speed()`: a frame counts at most 0.1 s (`_slow += minf(delta, 0.1)`), a step down is
    remembered (`Settings.remember("land_quality", …)`), and a minute smooth remembers the better step;
  - `_build_world()` ends `set_quality(maxi(quality, _remembered() - 1))`, with the new `_remembered()`
    after it;
  - `_land_heavy()` is unchanged.

  Everything is measured on the real frame (the delta v2.4.2 divides by the time scale).
- **Dad's readme** (`scripts/dad_readme.txt`) now says:
  - extract the zip first (started from inside the zip, Windows stops to ask);
  - on a laptop: Text size Large and F11 if the words are small, L for the flat chart if the land is slow;
  - that a new war ends the saved one, so the game asks.

## What Alex should poke at

1. **On a laptop** (Dad's if you can), a first launch: the window should open maximized, the words at
   Large (Settings, Text size), the land a few effects down on integrated graphics. Then F11.
2. **With a war saved**, click Tutorial, or New Game then Begin: it should ask, and "Keep my war" should
   keep it.
3. **The OpenGL look** (any PC): `CONCURRENT.exe --rendering-driver opengl3`. The buildings should be lit
   and the sea blue (it's a little more saturated than Vulkan, having no haze).
4. **On integrated graphics:** is the land smooth? It should settle at a lower step within a few seconds
   and start the next war one step better.
5. **The new words:**
   - the "Your lands" hint (open the Review drawer with nothing selected);
   - the final round's counsel;
   - "Quit to title";
   - How to Play's Recruits, Digging in and regroup pages.

## Open questions (my pick first)

Answered (Alex, 3 Nov, after the build): the pick on all six, C12 to C17 in the CHANGELOG. The chips (6) get a
pass of their own.

1. **Extra large is gone** (it hid the ORDERS dial). Large is the most the screens hold.
   - a) leave it so, my pick;
   - b) rework the bar, How to Play, the settings and the setup to fit 1108×692, a bigger job.
2. **The setup's map cards cut their names at Large text.** The chosen map is lit and the rest fits.
   - a) leave it, my pick;
   - b) rework the card (a smaller picture at narrow widths).
3. **The final round's voiced line** ("Throw in everything. Leave nothing in the barracks.") now says the
   opposite of the words under it, which say to keep enough at home.
   - a) keep the voice, my pick: it's the advisor's;
   - b) a new take.
4. **OpenGL's first-use hitches** (a few frames of 100 to 600 ms the first time a battle's pieces are drawn,
   once a launch).
   - a) leave them, my pick: they no longer cost the land its quality;
   - b) draw every battle material once, offscreen, while the land is built.
5. **Small words left as they are** (low, from the audit):
   - the hotseat names seat one "You" ("Pass the computer to You");
   - two map blurbs overstate (the Isles' "starves": a cut-off army only pays nothing);
   - a few subtitles have stray commas, which a voice line can't lose without a new take.
   - a) leave all three for now, my pick;
   - b) fix the words.
6. **The war's chips are 22 to 24 px on a laptop** (Auto-place, Clear, Cards, Review, ◀ Recruits, ? Dice,
   Auto-roll, Skip battles).
   - a) raise them to about 32 px in a pass of their own, my pick: the command bar is full at 900 high, so
     it's a re-layout with its probes, not a tweak;
   - b) leave them: each has a bigger way round (the dial, Space, Esc).

(Answered on the way: Large text by default on a laptop. The coordinator's message of 11-03 counted it a
robust default, so it's in, kept to a first launch that hasn't saved a text size.)
