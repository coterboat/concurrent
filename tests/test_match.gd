## G4: dump match.json, replay to the same world hashes. Seed stays off World.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Match := preload("res://engine/match.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const Resolve := preload("res://engine/resolve.gd")


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	_roundtrip(report, map, 42, false)
	_roundtrip(report, map, 7, true)
	_file_roundtrip(report, map)
	_setup_has_no_seed(report, map)
	_world_from_dict_hash(report, map)
	_duplicate_sheet_rejected(report, map)


func _roundtrip(report: Callable, map: Types.MapDef, seed: int, three: bool) -> void:
	var rec: Dictionary = Match.record_monkey(map, seed, three)
	report.call(rec.get("ok", false), "G4 record seed %s 3p=%s clean" % [seed, three])
	report.call(int(rec.get("rounds", 0)) >= 1, "G4 record has rounds")
	var replayed: Dictionary = Match.replay(map, rec)
	report.call(replayed.get("ok", false), "G4 replay ok (%s)" % replayed.get("error"))
	report.call(Match.hashes_match(rec, replayed), "G4 replay hashes match recorded seed %s" % seed)
	var again: Dictionary = Match.replay(map, rec)
	report.call(str(again.get("final_hash")) == str(replayed.get("final_hash")), "G4 replay is deterministic")


func _file_roundtrip(report: Callable, map: Types.MapDef) -> void:
	var rec: Dictionary = Match.record_monkey(map, 99, false)
	var path := "user://g4_match.json"
	var err: String = Match.save(path, rec)
	report.call(err == "", "G4 save match.json")
	var loaded: Dictionary = Match.load(path)
	report.call(not loaded.is_empty(), "G4 load match.json")
	report.call(int(loaded.get("matchSeed", -1)) == 99, "G4 file keeps matchSeed beside setup")
	var replayed: Dictionary = Match.replay(map, loaded)
	report.call(Match.hashes_match(rec, replayed), "G4 file replay matches in-memory record")


func _setup_has_no_seed(report: Callable, map: Types.MapDef) -> void:
	var rec: Dictionary = Match.record_monkey(map, 13, false)
	var setup: Dictionary = rec.get("setup", {})
	report.call(not setup.has("matchSeed"), "G4 setup world does not carry matchSeed")
	var parsed: Variant = JSON.parse_string(Match.to_json(rec))
	report.call(typeof(parsed) == TYPE_DICTIONARY and parsed.has("matchSeed"), "G4 json has sibling matchSeed")
	report.call(typeof(parsed) == TYPE_DICTIONARY and not parsed["setup"].has("matchSeed"), "G4 json setup has no matchSeed")


func _world_from_dict_hash(report: Callable, map: Types.MapDef) -> void:
	var play: Dictionary = Bot.play_match(map, 3, false)
	var w: Types.World = play["world"]
	var restored: Types.World = Types.World.from_dict(w.to_dict())
	report.call(Hash.world_hash(w) == Hash.world_hash(restored), "G4 World.from_dict preserves hash")
	var sheet: Types.Sheet = H.sheet("red", [H.pkt("ridge", "gate", 2, "harbor")], {"ridge": 1})
	var s2: Types.Sheet = Types.Sheet.from_dict(sheet.to_dict())
	report.call(s2.player_id == "red" and s2.packets.size() == 1, "G4 Sheet.from_dict")
	report.call((s2.packets[0] as Types.Packet).surge_to == "harbor", "G4 packet surgeTo roundtrips")


func _duplicate_sheet_rejected(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 3],
		"beacon": ["red", 1],
		"mill": ["green", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var a: Types.Sheet = H.sheet("red", [H.pkt("ridge", "gate", 1)])
	var b: Types.Sheet = H.sheet("red", [])
	var result: Dictionary = Resolve.resolve_round(world, map, [a, b], 1)
	var joined := " ".join(result["errors"])
	report.call(not result["errors"].is_empty() and joined.contains("duplicate"), "duplicate sheets are rejected")
	report.call(H.armies_of(result["world"], "ridge") == 3, "duplicate sheets do not resolve")
