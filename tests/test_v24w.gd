## v2.4: every war is kept (game/core/war_records.gd). The save slot holds one war and is cleared
## when it ends; the war records keep each war in a file of its own, written as the war goes,
## finished or not, and a kept war replays to the hashes it was played to. The wars the tests, the
## probes and the export smoke play (each moves the save slot aside) are never kept.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const WarRecords := preload("res://game/core/war_records.gd")
const Hash := preload("res://engine/hash.gd")

var _dir := "" ## a folder for this run alone: other sessions' test runs on the same machine keep their own


func run(report: Callable, tree: SceneTree) -> void:
	_fenced(report)
	_dir = "user://test_wars_%d" % OS.get_process_id()
	WarRecords.DIR = _dir
	_clean()
	_kept(report, tree)
	_old_save(report, tree)
	_clean()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
	WarRecords.DIR = WarRecords.DEFAULT_DIR


func _fenced(report: Callable) -> void:
	WarRecords.DIR = WarRecords.DEFAULT_DIR
	report.call(not WarRecords.on(Session.SAVE_PATH), "the tests' own wars are never kept (their save slot is %s)" % Session.SAVE_PATH)
	report.call(WarRecords.on(WarRecords.PLAYERS_SLOT), "a player's war is (the save slot as the game ships)")
	WarRecords.enabled = false
	report.call(not WarRecords.on(WarRecords.PLAYERS_SLOT), "and none while a tool replays a kept war")
	WarRecords.enabled = true


func _war(tree: SceneTree, seed: int) -> Node:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": seed, "length": "short", "deal": "random", "seats": [
		{"id": "red", "name": "Varek", "kind": "ai", "ai": "varek"},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren"}]})
	return s


func _kept(report: Callable, tree: SceneTree) -> void:
	var s: Node = _war(tree, 77)
	var id: String = s.war_id
	var path: String = WarRecords.path_of(id)
	report.call(id.ends_with("-77") and id.begins_with(Time.get_datetime_string_from_system(true).left(4)),
		"a new war is named by when it began and its seed (%s)" % id)
	report.call(FileAccess.file_exists(path), "deployed, it's kept in a file of its own (%s)" % path)
	var seen: Array = []
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 80:
		guard += 1
		if s.phase == Session.Phase.CINEMA:
			s.cinema_done()
		elif s.phase == Session.Phase.RECAP:
			seen.append(_rounds_in(path))
			s.next_round()
		else:
			break
	report.call(s.phase == Session.Phase.GAME_OVER and s.winner != "", "the war plays to its end (%s, round %d)" % [s.winner, s.world.round])
	report.call(not Session.has_save(), "the save slot is cleared when it ends, as ever")
	var grew := seen.size() >= 2
	for i in range(1, seen.size()):
		grew = grew and int(seen[i]) == int(seen[i - 1]) + 1
	report.call(grew, "the record was written as the war went, a round at a time (%s)" % str(seen))
	var rec: Dictionary = _read(path)
	report.call(str(rec.get("winner", "")) == s.winner and (rec.get("sheets", []) as Array).size() == s.rounds_log.size(),
		"the war's own file stays after it ends: every round in it (%d), and the winner named" % s.rounds_log.size())
	## the kept war, through the save's own loader
	var t: Node = Session.new()
	t.instant = true
	tree.root.add_child(t)
	_write(Session.SAVE_PATH, rec)
	var ok: bool = t.load_save()
	report.call(ok and t.hashes == rec["hashes"] and Hash.world_hash(t.world) == Hash.world_hash(s.world) and t.winner == s.winner,
		"the kept war replays round by round to the hashes it was played to (%d rounds)" % t.hashes.size())
	report.call(t.war_id == id, "and a war picked up again keeps its name")
	t.clear_save()
	t.queue_free()
	## the next war is a file of its own, and the first is untouched
	var before: String = FileAccess.get_file_as_string(path)
	var s2: Node = _war(tree, 78)
	report.call(s2.war_id != id and FileAccess.file_exists(WarRecords.path_of(s2.war_id)) and FileAccess.get_file_as_string(path) == before,
		"a new war is kept beside it and leaves it as it was (%s)" % s2.war_id)
	s2.clear_save()
	s2.queue_free()
	s.queue_free()


func _old_save(report: Callable, tree: SceneTree) -> void:
	## a save from before v2.4 has no name: it takes one from when it was saved, and is kept under it
	var s: Node = _war(tree, 79)
	var rec: Dictionary = _read(WarRecords.path_of(s.war_id))
	rec.erase("war")
	rec["saved"] = "2026-10-20 21:05:09"
	_write(Session.SAVE_PATH, rec)
	var t: Node = Session.new()
	t.instant = true
	tree.root.add_child(t)
	report.call(t.load_save() and t.war_id == "20261020T210509-79", "a save from before v2.4 takes its name from when it was saved (%s)" % t.war_id)
	t.save()
	report.call(FileAccess.file_exists(WarRecords.path_of("20261020T210509-79")), "and is kept under it from then on")
	t.clear_save()
	t.queue_free()
	s.queue_free()


func _rounds_in(path: String) -> int:
	return (_read(path).get("sheets", []) as Array).size()


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write(path: String, rec: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()


func _clean() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
