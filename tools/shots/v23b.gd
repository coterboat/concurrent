## v2.3 the crash at exit: a war left in its first second, while its land was still being built, for
## a war on another map, and then the game closed: signal 11. The war being left still heard the
## next one start (it's freed at the end of the frame), loaded the new map and began building that
## land too, and its first build was never waited for: Godot freed that task at shutdown, after
## GDScript had gone. Facts: the war left behind keeps its own map, every build of the land is
## waited for, the new war's land stands on its own map, and the game closes clean (probes.sh fails
## on the exit code; tools/study/quit_early.gd is the headless repro).
##   SHOT_DIR=/dir ./scripts/shot.sh v23b
extends RefCounted

const Land := preload("res://game/world3d/land.gd")
const MapBoard := preload("res://game/board/map_board.gd")
const Types := preload("res://engine/types.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["map_land"] = true
	Settings.data["battle_land"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(10)
	var open0: int = Land.builds_open
	main.start_game(_config("known24"))
	await p.frames(10)
	var first: Control = main.current
	var first_land: Node = first.land
	p.ok(first_land.busy() and not first_land.prepared, "the first war's land is still being built when it's left")
	main.start_game(_config("world30"))
	## the war being left is freed at the end of this frame: until then it must not take up the next
	p.ok(first.board.art.id == "known24" and first_land.building() == "known24",
		"the war being left keeps its own map (board %s, land %s)" % [first.board.art.id, first_land.building()])
	var guard := 0
	while not main.current.land.prepared and guard < 900:
		guard += 1
		await p.frames(1)
	p.ok(not is_instance_valid(first), "the war left behind is gone")
	p.ok(main.current.land.prepared and main.current.land.building() == "world30",
		"the new war's land stands on its own map (%s, built in %d frames)" % [main.current.land.building(), guard])
	p.ok(Land.builds_open == open0, "every build of the land was waited for (%d left open)" % (Land.builds_open - open0))
	await p.frames(30)
	await snap("01_second_war")
	await _mid_build(open0)
	## and the game closes: probes.sh fails on a crash at exit (it was signal 11)


func _mid_build(open0: int) -> void:
	## a land asked for another map while its first build still runs: it stands on the one asked for
	## last, and the build it replaced is still waited for (it was dropped: the crash at exit)
	var a: Control = _board("isles24")
	var b: Control = _board("marches18")
	var land: Node = Land.new()
	p.get_tree().root.add_child(land)
	land.prepare(a)
	await p.frames(2)
	land.prepare(b)
	p.ok(land.busy() and land._replaced.size() == 1, "a build replaced mid-way is kept to be waited for (%d)" % land._replaced.size())
	var guard := 0
	while not land.prepared and guard < 900:
		guard += 1
		await p.frames(1)
	p.ok(land.prepared and land.building() == "marches18" and land.wv.art.id == "marches18",
		"the land stands on the map asked for last (%s, built in %d frames)" % [land.wv.art.id if land.wv else "nothing", guard])
	land.free()
	a.free()
	b.free()
	p.ok(Land.builds_open == open0, "freed, it has waited for both builds (%d left open)" % (Land.builds_open - open0))


func _board(map_id: String) -> Control:
	var bd: Control = MapBoard.new()
	bd.visible = false
	p.get_tree().root.add_child(bd)
	bd.load_map(Types.MapDef.from_file("res://maps/%s.json" % map_id))
	return bd


func _config(map_id: String) -> Dictionary:
	return {"map": "res://maps/%s.json" % map_id, "seed": 7, "length": "short", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]}


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
