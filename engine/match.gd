## match.json record + replay. Seed is a sibling of setup, never on World.
## No Node. No UI. No unseeded RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Bot := preload("res://engine/bot.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")


static func from_play(play: Dictionary, map: Types.MapDef, match_seed: int) -> Dictionary:
	return {
		"mapId": map.id,
		"matchSeed": match_seed,
		"setup": play.get("setup", {}),
		"sheets": play.get("sheets", []),
		"hashes": play.get("hashes", []),
		"finalHash": play.get("final_hash", ""),
	}


static func record_monkey(map: Types.MapDef, match_seed: int, three_player: bool = false) -> Dictionary:
	var play: Dictionary = Bot.play_match(map, match_seed, three_player)
	var rec: Dictionary = from_play(play, map, match_seed)
	rec["ok"] = play.get("ok", false)
	rec["violations"] = play.get("violations", PackedStringArray())
	rec["rounds"] = play.get("rounds", 0)
	return rec


static func replay(map: Types.MapDef, record: Dictionary) -> Dictionary:
	var seed: int = int(record.get("matchSeed", 0))
	var setup: Variant = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		return {"ok": false, "error": "match.json missing setup", "hashes": [], "final_hash": ""}
	if setup.has("matchSeed"):
		return {"ok": false, "error": "seed leaked onto World setup", "hashes": [], "final_hash": ""}
	var world: Types.World = Types.World.from_dict(setup)
	if world.map_id == "":
		world.map_id = map.id
	var hashes: Array = []
	var sheets_all: Variant = record.get("sheets", [])
	if typeof(sheets_all) != TYPE_ARRAY:
		return {"ok": false, "error": "match.json sheets is not a list", "hashes": [], "final_hash": ""}
	for round_sheets in sheets_all:
		if typeof(round_sheets) != TYPE_ARRAY:
			return {"ok": false, "error": "round sheets is not a list", "hashes": [], "final_hash": ""}
		var sheets: Array = []
		for raw in round_sheets:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			sheets.append(Types.Sheet.from_dict(raw))
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, seed)
		if not result["errors"].is_empty():
			return {
				"ok": false,
				"error": " ".join(result["errors"]),
				"hashes": hashes,
				"final_hash": Hash.world_hash(world),
				"world": world,
			}
		world = result["world"]
		hashes.append(Hash.world_hash(world))
	return {
		"ok": true,
		"error": "",
		"hashes": hashes,
		"final_hash": Hash.world_hash(world),
		"world": world,
	}


static func hashes_match(record: Dictionary, replayed: Dictionary) -> bool:
	if not replayed.get("ok", false):
		return false
	var a: Array = record.get("hashes", [])
	var b: Array = replayed.get("hashes", [])
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return str(record.get("finalHash", "")) == str(replayed.get("final_hash", ""))


static func to_json(record: Dictionary) -> String:
	var slim := {
		"mapId": record.get("mapId", ""),
		"matchSeed": int(record.get("matchSeed", 0)),
		"setup": record.get("setup", {}),
		"sheets": record.get("sheets", []),
		"hashes": record.get("hashes", []),
		"finalHash": record.get("finalHash", ""),
	}
	return JSON.stringify(slim, "\t")


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func save(path: String, record: Dictionary) -> String:
	var abs_path := _abs(path)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (err %s)" % [abs_path, FileAccess.get_open_error()]
	f.store_string(to_json(record))
	return ""


static func load(path: String) -> Dictionary:
	var abs_path := _abs(path)
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {}
	return from_json(f.get_as_text())


static func _abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/") or (path.length() >= 2 and path.substr(1, 1) == ":"):
		return path
	return ProjectSettings.globalize_path("res://" + path)
