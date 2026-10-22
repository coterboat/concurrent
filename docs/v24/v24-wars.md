# v24-wars: every war is kept

Alex, after Imre's and Quill's split-attack retreats couldn't be looked at again: "savegame.json going
away is dumb we should be storing all game histories in an evergrowing file that we'll keep committing
until it's large enough to warrant a supabase or something minor local. this we way can track and
simulate games over time to come up with better balancing and fun new ideas to improve the game"

## What changed

- **`game/core/war_records.gd`:** every time the game saves (deployment, each round, the marches after
  it) the same record is also written to `user://wars/<id>.json`, a file of the war's own that is never
  cleared. The id is when the war began (UTC) and its seed (`20261022T002627-4242`): it sorts by date and
  two machines never collide. The save slot is untouched: it's still cleared when a war ends.
- **The record** is the save as it was (setup, every round's orders and calls, the marches, every round's
  world hash) plus `war`, `host` (the OS) and, once the war is over, `winner`. The engine is deterministic
  and its rules are versioned, so a kept war replays exactly, battles and all.
- **A war picked up again keeps its name** (`war` is in the save). A save from before v2.4 takes a name
  from when it was saved.
- **Only a player's wars are kept:** `WarRecords.on()` keeps a war only when the save slot is the
  player's. The tests, the probes, the soak and the export smoke all move the slot aside, so none of their
  wars are kept, and a new entry point that forgets to fence the slot is caught by the slot rule it
  already breaks. A test that wants records points `WarRecords.DIR` at a folder of its own.
- **One file per war, not one ever-growing file:** two machines (the PC, the Mac, Dad's) adding to one
  file would collide in git, and a growing JSONL of whole saves would repeat every round. Per-war files
  never conflict, replay straight from the file through the game's own loader, and go into a database
  one row each when the folder outgrows git.
- **`tools/wars/collect.py`:** copies this machine's kept wars into the repo's `wars/` folder, brings a
  war still being played up to date (never takes a copy that's no further on than the repo's), and takes
  a folder or a zip someone sent (`collect.py <path>`); it reads zips in memory and never unpacks them.
- **`tools/wars/replay.gd`:** replays a kept war through `Session.load_save` from a copy in a slot of its
  own (records off, settings fenced), checks every round's hash against the one it was played to (exit 1
  if any differs: a rule that changed outcomes without a gate), and tells the war round by round with each
  commander's battles.
- **`wars/`** has a `.gdignore` (Godot doesn't import it) and the exports exclude it (`wars/*` in both
  presets), so Dad's build never ships Alex's wars.
- Words: `wars/README.md`, CLAUDE.md (two commands; the fencing gotcha now names the records), README's
  Saves row, Dad's readme (where his wars are, and that Alex may ask him to zip and send them).

## Evidence

- `tests/test_v24w.gd`, 14 facts, all passing on the first run: the tests' own wars are never kept; a
  player's are; a whole war is written a round at a time (`[1, 2, 3, 4]`), stays after the war ends with
  every round and the winner, and replays through the save's own loader to the hashes it was played to;
  a second war is kept beside it and leaves it unchanged; a war picked up again keeps its name; a save
  from before v2.4 takes its name from when it was saved and is kept under it from then on.
- End to end on the PC: an all-AI war on the Known World kept by the game (a 6-round, 3-commander war
  is 8 KB), collected into `wars/` (`1 new`, then `1 already here`), and replayed:
  `replay: ok  every round replays to the hash it was played to (6)`. At that size a thousand wars are
  under 30 MB: git holds them for a long time.

## What Alex should poke at

- Play a war (or start one and abandon it), then `python tools/wars/collect.py`: it should list it, with
  its map, its commanders and how far it got. Then replay it.

## Open

- **Dad's wars stay on his PC** until he sends the folder (his readme says where). A button that opens
  the folder (Settings) would make that easier; an upload to Supabase later needs his OK.
- **The collector is run by hand.** The coordinator runs it before each commit for now.
- A study across all kept wars (how often split attacks, retreats, Fortune; humans against the arena's
  AI wars, `engine/telemetry.gd` already summarizes a war's events) is the next step once a few wars are in.
