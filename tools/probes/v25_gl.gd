## v2.5: the land on the Compatibility renderer (OpenGL: a PC with neither Vulkan nor Direct3D 12 falls
## back to it). Run by tools/shots/v25.gd in a second Godot with `--rendering-driver opengl3`, or alone:
##   SHOT_DIR=/dir $G --rendering-driver opengl3 --path . res://tools/probe.tscn -- --script=res://tools/probes/v25_gl.gd
## Under OpenGL the buildings were drawn near-black (their seating coat's multiply) and the haze greyed
## the land and turned the sea from navy to the haze's own colour. As facts: no coat and no haze there,
## the open sea reads blue, and the buildings stand in their own colours.
extends RefCounted

const Session := preload("res://game/core/session.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["map_land"] = true
	Settings.data["battle_land"] = true
	var gl: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	p.ok(gl, "the game runs on the Compatibility renderer (%s, %s)" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(3)
	main.start_game({"map": "res://maps/known24.json", "seed": 25, "length": "standard", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 3000:
		guard += 1
		if s.phase == Session.Phase.OPENING and s.is_human(s.planner):
			s.auto_deploy()
			s.lock()
		await p.frames(2)
	var land: Node = gs.land
	guard = 0
	while (land == null or not land.prepared) and guard < 1800:
		guard += 1
		await p.frames(1)
	await p.frames(90)
	p.ok(land != null and land.prepared and gs.land_board.active(), "the board stands on the land")
	if land == null or not land.prepared:
		return
	var look: Dictionary = await look_of(gs, land, "v25_gl_board")
	p.log("on %s: %s" % [RenderingServer.get_current_rendering_method(), str(look)])
	if gl:
		p.ok(int(look["coated"]) == 0 and not bool(look["fog"]), "no seating coat on the buildings and no haze over the land (%d coated, haze %s)" % [int(look["coated"]), str(look["fog"])])
	var sea: Color = look["sea"]
	p.ok(int(look["sea_n"]) >= 8 and sea.b > sea.r + 0.04, "the open sea reads blue, not the haze's grey (%s over %d points)" % [str(sea), int(look["sea_n"])])
	p.ok(int(look["buildings_n"]) >= 8 and float(look["buildings"]) > 0.2, "the buildings stand in their own colours, not near-black (median brightness %.2f over %d)" % [float(look["buildings"]), int(look["buildings_n"])])
	if not gl:
		return
	## a slow machine: three seconds of slow frames step the land down (on this renderer every slow frame
	## counts, having no timings), the step is remembered, and the next war's land starts one better
	var q0: int = land.quality
	p.ok(q0 == 0, "the land kept every effect through the war's opening on this machine (step %d): a hitch is one frame, not a slow land" % q0)
	land._slow = 0.0
	for i in 35:
		land._watch_speed(0.1)
	var stepped: int = land.quality
	p.ok(stepped == q0 + 1 and int(Settings.get_value("land_quality", 0)) == stepped, "3 s of slow frames step the land down (%d to %d), and the step is remembered (%d)" % [q0, stepped, int(Settings.get_value("land_quality", 0))])
	land._slow = 0.0
	for i in 35:
		land._watch_speed(0.1)
	var remembered: int = int(Settings.get_value("land_quality", 0))
	main.start_game({"map": "res://maps/knife7.json", "seed": 26, "length": "short", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"}]})
	await p.frames(10)
	var land2: Node = main.current.land
	guard = 0
	while (land2 == null or not land2.prepared) and guard < 1800:
		guard += 1
		await p.frames(1)
	p.ok(land2 != null and land2.prepared and land2.quality == maxi(0, remembered - 1), "the next war's land starts a step better than the one remembered (%d; remembered %d)" % [land2.quality if land2 != null else -1, remembered])
	Settings.data["land_quality"] = 0


static func look_of(gs: Control, land: Node, shot: String) -> Dictionary:
	## the land as drawn, the board's tokens and words lifted off it: the open sea's median colour, and
	## the median brightness where the buildings stand (each sampled a little above its foot)
	var tree: SceneTree = gs.get_tree()
	gs.board.overlay.visible = false
	for i in 3:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img: Image = gs.get_viewport().get_texture().get_image()
	gs.board.overlay.visible = true
	var dir: String = OS.get_environment("SHOT_DIR")
	if dir != "":
		img.save_png(dir + "/" + shot + ".png")
	var k: float = float(img.get_width()) / gs.get_viewport().get_visible_rect().size.x
	var top := 110.0
	var bottom: float = gs.get_viewport().get_visible_rect().size.y - 170.0
	var reds: Array = []
	var greens: Array = []
	var blues: Array = []
	var t: RefCounted = land.wv.terrain
	var ms: Vector2 = land.wv.art.size
	for y in range(20, int(ms.y), 40):
		for x in range(20, int(ms.x), 40):
			var at := Vector2(x, y)
			if t.coast_at(at) > -30.0:
				continue
			var sp: Vector2 = land.project(at) + gs.land_board.global_position
			if sp.x < 10 or sp.y < top or sp.x > gs.get_viewport().get_visible_rect().size.x - 120 or sp.y > bottom:
				continue
			var c: Color = img.get_pixelv(Vector2i(sp * k))
			reds.append(c.r)
			greens.append(c.g)
			blues.append(c.b)
	var lum: Array = []
	for pc in land.scenery.pieces:
		if str(pc["role"]) in ["ship", "lane", "bridge"]:
			continue
		var at: Vector2 = pc["at"]
		var sp: Vector2 = land.project(at, float(pc["h"]) * 0.45 * land.wv.relief) + gs.land_board.global_position
		if sp.x < 10 or sp.y < top or sp.x > gs.get_viewport().get_visible_rect().size.x - 120 or sp.y > bottom:
			continue
		var c: Color = img.get_pixelv(Vector2i(sp * k))
		lum.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	var coated := 0
	for mi in land.scenery.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).material_override
		if m != null and m.next_pass != null:
			coated += 1
	return {"sea": Color(_median(reds), _median(greens), _median(blues)), "sea_n": reds.size(), "buildings": _median(lum), "buildings_n": lum.size(),
		"coated": coated, "fog": land.wv.env.fog_enabled}


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])
