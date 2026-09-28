## Run one test file, for quick iteration (the full suite is tests/runner.gd):
##   godot --headless --path . --script res://tools/test_one.gd -- tests/test_v110.gd
extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	## v1.13: the same fences as tests/runner.gd. A test that plays a session saves as it goes, and
	## the player's own save slot (user://savegame.json, shared with the game) must never be it.
	load("res://game/core/session.gd").SAVE_PATH = "user://test_savegame.json"
	var st: Node = root.get_node_or_null("Settings")
	if st != null:
		st.set("persist", false)
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- tests/test_xxx.gd")
		quit(2)
		return
	var path: String = args[0] if args[0].begins_with("res://") else "res://" + args[0]
	var obj = load(path).new()
	if obj.get_method_argument_count("run") >= 2:
		obj.run(Callable(self, "_ok"), self)
	else:
		obj.run(Callable(self, "_ok"))
	print("%s  passed=%d  failed=%d" % ["ok  " if failed == 0 else "FAIL", passed, failed])
	quit(0 if failed == 0 else 1)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  ok   " + msg)
	else:
		failed += 1
		print("  FAIL " + msg)
