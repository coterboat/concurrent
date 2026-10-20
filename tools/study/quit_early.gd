## Start a war and quit in its first frames (while the land is still being built), as a player
## closing the window right after pressing Start would. Prints its frames; a crash ends it early.
##   godot --headless --path . --script res://tools/study/quit_early.gd -- frames=120 maps=known24,world30
## Up to v2.3 this crashed at exit (signal 11): the war being left heard the next one start, began
## building the new map's land too, and dropped its first build unwaited; Godot freed that task at
## shutdown, after GDScript (land.gd, game_screen.gd; probe v23b holds it). With frames=600, or one
## map, or the same map twice, or noland, it closed clean even then.
## Switches: frames=N or frames=N,M (a count for each map in turn), gap=N (the title for N frames
## between the wars), noland, nomapland, nobattleland, title, finish
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	load("res://game/core/session.gd").SAVE_PATH = "user://smoke_savegame.json"
	var st: Node = root.get_node("Settings")
	st.persist = false
	for k in ["music", "sfx", "ambience", "voices"]:
		st.data[k] = 0.0
	st.data["motion"] = "paintings"
	var frames := 10
	var each: PackedStringArray = [] ## frames=10,600: a count for each map in turn
	var gap := 0 ## gap=N: the title screen for N frames between the wars
	var maps: PackedStringArray = ["known24"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("frames="):
			each = a.trim_prefix("frames=").split(",")
			frames = int(each[0])
		elif a == "nomapland":
			st.data["map_land"] = false
		elif a == "nobattleland":
			st.data["battle_land"] = false
		elif a == "noland":
			st.data["map_land"] = false
			st.data["battle_land"] = false
		elif a.begins_with("gap="):
			gap = int(a.trim_prefix("gap="))
		elif a.begins_with("maps="):
			maps = a.trim_prefix("maps=").split(",")
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	for mi in maps.size():
		var m: String = maps[mi]
		if mi < each.size():
			frames = int(each[mi])
		if mi > 0 and gap > 0:
			main.show_title()
			for i in gap:
				await process_frame
		main.start_game({"map": "res://maps/%s.json" % m, "seed": 7, "length": "short", "timer": 0, "deal": "random", "seats": [
			{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
			{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
		for i in frames:
			await process_frame
		print("QUIT_EARLY started %s, %d frames, land prepared: %s" % [m, frames, str(main.current.land.prepared if main.current.land else false)])
	if OS.get_cmdline_user_args().has("title"):
		main.show_title()
		for i in 300:
			await process_frame
	if OS.get_cmdline_user_args().has("finish"):
		var ld: Node = main.current.land if main.current.get("land") else null
		if ld != null and ld._task >= 0:
			ld._wait(ld._task)
			ld._task = -1
			print("QUIT_EARLY finished the land build first")
	print("QUIT_EARLY quitting")
	quit(0)
