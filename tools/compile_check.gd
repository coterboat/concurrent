## Load every script under engine/, game/, tools/, tests/ and report the ones that fail.
##   godot --headless --path . --script res://tools/compile_check.gd
extends SceneTree

func _initialize() -> void:
	var bad := 0
	var n := 0
	for root in ["res://engine", "res://game", "res://tests"]:
		for path in _walk(root):
			n += 1
			var s: Script = load(path)
			if s == null or not s.can_instantiate():
				bad += 1
				print("FAIL ", path)
	print("compile check: %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)

func _walk(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_walk(dir + "/" + sub))
	return out
