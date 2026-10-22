## Replay a kept war (v2.4, game/core/war_records.gd) through the session's own loader: every round's
## world hash is checked against the one kept when it was played, then the war is told round by
## round (each commander's lands and armies) with each commander's battles. Exit 1 if the war
## doesn't replay to its own hashes (a rule changed outcomes without a gate: CLAUDE.md, the engine's laws).
##   $G --headless --path . --script res://tools/wars/replay.gd -- wars/<id>.json
## The war's file is only read: it's replayed from a copy in a slot of the tool's own.
extends SceneTree

const Session := preload("res://game/core/session.gd")
const WarRecords := preload("res://game/core/war_records.gd")
const SLOT := "user://replay_savegame.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("replay: which war? (wars/<id>.json)")
		quit(2)
		return
	var src: String = args[0]
	if not (src.begins_with("res://") or src.begins_with("user://") or src.is_absolute_path()):
		src = "res://" + src
	var text: String = FileAccess.get_file_as_string(src)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("replay: no war at %s" % src)
		quit(2)
		return
	var rec: Dictionary = parsed
	## fence everything a session could touch: the player's save slot, settings, the records
	Session.SAVE_PATH = SLOT
	WarRecords.enabled = false
	var st: Node = root.get_node_or_null("Settings")
	if st != null:
		st.set("persist", false)
	var f := FileAccess.open(SLOT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var s: Node = Session.new()
	s.instant = true
	root.add_child(s)
	var ok: bool = s.load_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SLOT))
	var kept: Array = rec.get("hashes", [])
	var bad := -1
	for i in mini(kept.size(), s.hashes.size()):
		if str(kept[i]) != str(s.hashes[i]):
			bad = i
			break
	var same: bool = ok and bad < 0 and kept.size() == s.hashes.size()
	var cfg: Dictionary = rec.get("config", {})
	var who: Array = []
	for seat in s.seats:
		who.append("%s (%s)" % [seat["name"], "human" if str(seat.get("kind", "")) == "human" else str(seat.get("ai", "ai"))])
	print("war %s on %s, rules %d, played on %s" % [rec.get("war", "?"), str(cfg.get("map", "?")).get_file().get_basename(), int(cfg.get("rules", 0)), rec.get("host", "?")])
	print("  " + ", ".join(who))
	print("  %d rounds; %s" % [s.rounds_log.size(), ("won by " + s.name_of(s.winner)) if s.winner != "" else "unfinished (last saved %s)" % rec.get("saved", "?")])
	for snap in s.history:
		var line: Array = []
		for seat in s.seats:
			var pid: String = seat["id"]
			if int(snap["terr"].get(pid, 0)) > 0:
				line.append("%s %d lands %d men" % [seat["name"], int(snap["terr"][pid]), int(snap["armies"][pid])])
		print("  round %2d: %s" % [int(snap["round"]), " · ".join(line)])
	for seat in s.seats:
		var st2: Dictionary = s.stats.get(seat["id"], {})
		print("  %s: %d battles, %d won, %d lands taken, %d men lost" % [seat["name"], int(st2.get("battles", 0)), int(st2.get("won", 0)), int(st2.get("captures", 0)), int(st2.get("armies_lost", 0))])
	if same:
		print("replay: ok  every round replays to the hash it was played to (%d)" % kept.size())
	elif not ok:
		print("replay: FAIL  the war wouldn't load")
	elif bad >= 0:
		print("replay: FAIL  round %d replays to another world than it was played to" % (bad + 1))
	else:
		print("replay: FAIL  %d rounds kept, %d replayed" % [kept.size(), s.hashes.size()])
	s.free()
	quit(0 if same else 1)
