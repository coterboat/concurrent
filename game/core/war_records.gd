## v2.4: every war is kept. The save slot (Session.SAVE_PATH) holds one war, its setup and every
## round's orders, and it goes when that war ends or another begins. Each save is also written here,
## to a file of the war's own that is never cleared: a war replays from it exactly, battles and all
## (the engine is deterministic and its rules are versioned), so finished and abandoned wars alike
## can be replayed, counted and studied later. `tools/wars/collect.py` brings a machine's wars into
## the repo's `wars/` folder; `tools/wars/replay.gd` replays one and checks every round's hash.
extends RefCounted

const PLAYERS_SLOT := "user://savegame.json" ## Session.SAVE_PATH as the game ships
const DEFAULT_DIR := "user://wars"
static var DIR := DEFAULT_DIR ## a test points this at a folder of its own, and keeps its wars there
static var enabled := true ## off while a tool replays a kept war


static func on(save_path: String) -> bool:
	## only a player's wars: whatever moves the save slot aside (the tests, the probes, the export
	## smoke) keeps none, unless it has pointed DIR at a folder of its own
	return enabled and (save_path == PLAYERS_SLOT or DIR != DEFAULT_DIR)


static func new_id(seed: int, when: String = "") -> String:
	## when the war began (UTC), then its seed: the names sort by date, and no two machines' collide.
	## `when` names a war from before v2.4 by the time its save was written
	var t: String = when if when != "" else Time.get_datetime_string_from_system(true, false)
	return "%s-%d" % [t.replace("-", "").replace(":", "").replace(" ", "T"), seed]


static func path_of(id: String) -> String:
	return DIR.path_join(id + ".json")


static func keep(rec: Dictionary) -> void:
	var id: String = str(rec.get("war", ""))
	if id == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(path_of(id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rec))
