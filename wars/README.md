# Kept wars

Every war played in the game is kept (v2.4, `game/core/war_records.gd`): a file per war, named by
when it began and its seed, written every round until it ends, finished or abandoned. Each holds the
war's setup and every round's orders, so it replays exactly, battles and all.

- **Bring them in:** `python tools/wars/collect.py` copies this machine's wars here (and brings a war
  still being played up to date). `python tools/wars/collect.py <folder or zip>` takes wars someone
  sent. Then commit `wars/`.
- **Replay one:** `$G --headless --path . --script res://tools/wars/replay.gd -- wars/<id>.json` checks
  every round against the hash it was played to and tells the war round by round.
- **Where the game keeps them:** Godot's user folder for CONCURRENT, under `wars/`
  (Windows `%APPDATA%\Godot\app_userdata\CONCURRENT\wars`, macOS
  `~/Library/Application Support/Godot/app_userdata/CONCURRENT/wars`).
- The tests, the probes and the export smoke move the save slot aside, so their wars are never kept.
- `.gdignore` keeps Godot from importing this folder, and the exports leave it out.

When this folder outgrows git, the files go into a database as they are (one row per war).
