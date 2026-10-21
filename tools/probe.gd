## EO7-style probe harness. Boots a Godot instance, runs a probe body, quits.
##
##   godot --headless --path . res://tools/probe.tscn -- --script=res://tools/probes/plan_bugs.gd
##
## `p.log`, `p.fail`, `p.ok` so a case can fail the process.
extends Node

const PREFIX := "PROBE"

var _script_path: String = ""
var _failed := false
## v2.3 (B-013, B-014): the bot's box draws a frame a second or slower (software GL), so a moment
## of half a second can begin and end between two frames. `steady()` holds the game to `_step` of
## a second a frame for a probe that samples such a moment; `--box=K` plays every frame as K/60 of
## a second, as such a box does, to see one here (`PROBE_ARGS=--box=40 ./scripts/probes.sh v202`)
var _box := 1.0
var _steady := false
var _step := 1.0 / 60.0
var _last_us := 0
var _frame := 1.0 / 60.0 ## the slowest recent frame, in real seconds (as the box sees them)


func _ready() -> void:
	## Probes drive the real client; keep them out of the player's save slot.
	load("res://game/core/session.gd").SAVE_PATH = "user://probe_savegame.json"
	## ...and out of the player's settings: probes mute audio, and must never save that
	Settings.persist = false
	## v2.0: probes count frames; Forward+ on Metal runs at the display's rate (120 Hz on a
	## ProMotion screen), so hold every probe to the 60 frames a second they were written for
	Engine.max_fps = 60
	Settings.data["battle_land"] = false ## v2.0: the older probes watch the painted field (diorama turns the land on)
	Settings.data["map_land"] = false ## v2.0: ...and the chart (v20 and board3d turn the land on)
	Settings.data["motion"] = "paintings" ## v1.9: no cutscenes over the older probes' screenshots (v19 turns them on)
	_parse_args()
	Engine.time_scale = _box
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
	log_line("done (%d frames)" % Engine.get_process_frames())
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


func steady(on: bool, step := 1.0 / 60.0) -> void:
	## while on, a frame moves the game on by `step` at most, however long it took to draw
	_steady = on
	_step = step
	_pace()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		## the slowest recent frame: the next one's pace is set before it is drawn
		_frame = maxf(float(now - _last_us) / 1e6 * _box, _frame * 0.8)
	_last_us = now
	_pace()


func _pace() -> void:
	Engine.time_scale = clampf(_step / maxf(_frame, 1e-4) * _box, 0.01, _box) if _steady else _box


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--script="):
			_script_path = arg.trim_prefix("--script=")
		elif arg.begins_with("--box="):
			_box = maxf(float(arg.trim_prefix("--box=")), 0.01)
