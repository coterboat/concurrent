## EO7-style probe harness. Boots a Godot instance, runs a probe body, quits.
##
##   godot --headless --path . res://tools/probe.tscn -- --script=res://tools/probes/plan_bugs.gd
##
## `p.log`, `p.fail`, `p.ok` so a case can fail the process.
extends Node

const PREFIX := "PROBE"

var _script_path: String = ""
var _failed := false


func _ready() -> void:
	## Probes drive the real client; keep them out of the player's save slot.
	load("res://game/core/session.gd").SAVE_PATH = "user://probe_savegame.json"
	## ...and out of the player's settings: probes mute audio, and must never save that
	Settings.persist = false
	_parse_args()
	if _script_path == "":
		push_error("probe: --script=res://... is required")
		get_tree().quit(2)
		return
	if not ResourceLoader.exists(_script_path):
		push_error("probe: no such resource: %s" % _script_path)
		get_tree().quit(2)
		return
	var body_script: Script = load(_script_path)
	if body_script == null or not body_script.can_instantiate():
		push_error("probe: %s failed to compile" % _script_path)
		get_tree().quit(2)
		return
	var body: Object = body_script.new()
	if not body.has_method("run"):
		push_error("probe: %s has no run(p) function" % _script_path)
		get_tree().quit(2)
		return
	log_line("script=%s" % _script_path)
	# _ready is still wiring children; wait one frame so add_child on the tree works.
	await get_tree().process_frame
	await body.run(self)
	log_line("done")
	get_tree().quit(1 if _failed else 0)


func log_line(msg: String) -> void:
	print("%s %s" % [PREFIX, msg])


func log(msg: String) -> void:
	log_line(msg)


func ok(cond: bool, msg: String) -> void:
	if cond:
		log_line("ok   %s" % msg)
	else:
		fail(msg)


func fail(msg: String) -> void:
	_failed = true
	log_line("FAIL %s" % msg)


func frames(n: int) -> void:
	for i in maxi(1, n):
		await get_tree().process_frame


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--script="):
			_script_path = arg.trim_prefix("--script=")
