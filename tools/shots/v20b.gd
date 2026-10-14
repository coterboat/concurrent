## v2.0, round two: the board standing on the land in the real client (land_board.gd). The facts:
## the land comes up under the board once it's built; the board's own UI rides it (every token
## on screen, a click on any token comes back to its own land); the garrisons stand by their
## tokens, one for every two men; the board's highlights are on the ground; a battle leaves from
## this same camera and comes back to it; L puts the chart back, and the land again.
##   SHOT_DIR=/dir ./scripts/shot.sh v20b
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Scenery := preload("res://game/world3d/scenery.gd")
const MapLib := preload("res://engine/map.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "fast"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	var maps: PackedStringArray = OS.get_environment("MAPS").split(",") if OS.get_environment("MAPS") != "" else PackedStringArray(["known24", "world30"])
	for m in maps:
		await _board_on_land(m)
	await _battle_from_land()


func _game(map: String, seats: Array) -> Array:
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": map, "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": seats})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	for i in seats.size():
		s.auto_deploy()
		s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	return [main, s, gs]


func _seats(n: int) -> Array:
	var all := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"},
		{"id": "gold", "name": "Quill", "kind": "human", "ai": "", "portrait": "quill"}]
	return all.slice(0, n)


func _settle(gs: Control) -> int:
	var lb: Control = gs.land_board
	var guard := 0
	while not (lb.ready_to_show() and lb.settled()) and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(30)
	return guard


func _board_on_land(mid: String) -> void:
	var r: Array = await _game("res://maps/%s.json" % mid, _seats(4))
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	var lb: Control = gs.land_board
	var frames: int = await _settle(gs)
	p.ok(lb.active() and is_equal_approx(lb.t, 1.0), "%s: the board stands on the land once it's built (%d frames)" % [mid, frames])
	p.ok(not b.terrain.visible and b.projector.is_valid(), "%s: the chart is under the land, the board's UI rides the land" % mid)
	await snap("%s_01_board_on_land" % mid)
	_tokens_ride(mid, b, "whole map")
	## the garrisons: every held land's men by its token
	var want := 0
	for id in b.art.order:
		var ts = b.world.get_territory(id)
		if ts != null and ts.owner != "" and ts.armies + ts.garrison > 0:
			want += clampi(int(ceil(float(ts.armies + ts.garrison) / 2.0)), 1, 5)
	var have := 0
	var colours := 0
	for f in gs.land.garrisons.figs:
		if f["alive"] and bool(f["counts"]):
			have += 1
		elif f["alive"] and f["kind"] == "flag":
			colours += 1
	p.ok(have == want, "%s: every held land's garrison stands on the board (%d figures, %d wanted)" % [mid, have, want])
	var caps := 0
	for pid in b.world.players.keys():
		if MapLib.capital_of(b.world, b.map, str(pid)) != "":
			caps += 1
	p.ok(colours == caps, "%s: every capital's garrison carries the colours (%d flags, %d capitals)" % [mid, colours, caps])
	_scenery_facts(mid, gs)
	## the board's highlights reach the ground
	var mine: String = ""
	for id in b.art.order:
		if b.world.get_territory(id).owner == s.planner:
			mine = id
			break
	gs.select(mine)
	await p.frames(10)
	var gsel: int = int(gs.land.wv.gmat.get_shader_parameter("select_id"))
	p.ok(gsel == int(b.art.index.get(mine, -2)), "%s: the land selected on the board is lit on the ground (%s)" % [mid, mine])
	await snap("%s_02_selected" % mid)
	## V: the regions view, on the ground too
	gs.toggle_view()
	await p.frames(6)
	p.ok(int(gs.land.wv.gmat.get_shader_parameter("view_mode")) == 1, "%s: V paints the regions on the land as on the chart" % mid)
	await snap("%s_02b_regions" % mid)
	gs.toggle_view()
	await p.frames(3)
	## zoomed in: the camera comes lower, the UI still rides, and the land you zoom on stays put
	## (once the map is wider than the screen: until then the board keeps it centred, as the chart does)
	var mid_land := ""
	var near := 1.0e9
	for id in b.art.order:
		var dd: float = (b.art.anchors[id] as Vector2).distance_to(b.art.size * 0.5)
		if dd < near:
			near = dd
			mid_land = id
	b.zoom_at(b.anchor(mid_land), 1.4)
	await p.frames(6)
	var worst := 0.0
	for i in 5:
		var was: Vector2 = b.anchor(mid_land)
		b.zoom_at(was, 1.15)
		await p.frames(6)
		worst = maxf(worst, b.anchor(mid_land).distance_to(was))
	p.ok(worst < 6.0, "%s: zooming in on %s keeps it under the cursor (worst %.1f px)" % [mid, mid_land, worst])
	await p.frames(40)
	p.ok(float(gs.land.wv.rig["pitch"]) < lb.PITCH_FAR - 4.0, "%s: zoomed in, the camera comes down over the land (pitch %.0f°)" % [mid, gs.land.wv.rig["pitch"]])
	_tokens_ride(mid, b, "zoomed in")
	await snap("%s_03_zoomed" % mid)
	gs.select("")
	b.reset_view()
	## L: the chart, then the land again
	gs.toggle_land()
	var guard := 0
	while lb.active() and guard < 600:
		guard += 1
		await p.frames(1)
	await p.frames(5)
	p.ok(not lb.active() and b.terrain.visible and not b.projector.is_valid() and not bool(Settings.data["map_land"]),
		"%s: L puts the chart back (%d frames)" % [mid, guard])
	await snap("%s_04_chart" % mid)
	gs.toggle_land()
	frames = await _settle(gs)
	p.ok(lb.active() and bool(Settings.data["map_land"]), "%s: L again, and the board is on the land (%d frames)" % [mid, frames])
	main.queue_free()
	await p.frames(5)


func _scenery_facts(mid: String, gs: Control) -> void:
	## the land's buildings: a village on every land (whose village model is in), each on its own
	## dry land, off the roads, beside the stage and never where a battle there would stand
	var sc: Node3D = gs.land.scenery
	var b: Control = gs.board
	var t = gs.land.wv.terrain
	var want := 0
	for id in b.art.order:
		var td = b.map.get_territory(id)
		var terr: String = str(b.map.region_terrain.get(td.region, "grass"))
		if sc.has("village_" + (terr if terr in Scenery.VILLAGES else "grass")):
			want += 1
	var have: int = sc.count("village")
	p.ok(have == want, "%s: a village on every land (%d of %d with a village model in)" % [mid, have, want])
	var bad := []
	var in_way := []
	var dio: Node3D = gs.land.battle
	for piece in sc.pieces:
		if piece["role"] in ["ship", "lane", "bridge", "port"]:
			continue
		var at: Vector2 = piece["at"]
		var id: String = piece["land"]
		if b.art.territory_at(at) != id or t.coast_at(at) < 3.0 or t.road_at(at) < 6.0:
			bad.append("%s@%s" % [piece["kind"], id])
		## where a battle in this land would stand: every column at its border, the defenders at the heart
		var spots: Array = [b.art.anchors[id]]
		for k in t.crossings.keys():
			var pr: PackedStringArray = str(k).split("|")
			if pr[0] == id or pr[1] == id:
				var other: String = pr[1] if pr[0] == id else pr[0]
				spots.append(dio.front_group(id, other, 6)["at"])
		for sp in spots:
			if (sp as Vector2).distance_to(at) < float(piece["r"]) * 0.8:
				in_way.append("%s@%s" % [piece["kind"], id])
				break
	p.ok(bad.is_empty(), "%s: every building on its own dry land, off the roads (%d wrong: %s)" % [mid, bad.size(), ", ".join(bad.slice(0, 5))])
	## the rules as buildings: a palace flying its commander's colours at every capital
	if sc.has("palace") and b.map.capitals:
		var caps: Array = []
		for pid in b.world.players.keys():
			var c: String = MapLib.capital_of(b.world, b.map, str(pid))
			if c != "":
				caps.append(c)
		var standing: Array = sc.palaces()
		p.ok(caps.size() > 0 and caps.all(func(c): return standing.has(c)), "%s: a palace at every capital (%s; palaces at %s)" % [mid, caps, standing])
	p.ok(in_way.is_empty(), "%s: no building where a battle in its land would stand (%d: %s)" % [mid, in_way.size(), ", ".join(in_way.slice(0, 5))])


func _tokens_ride(mid: String, b: Control, when: String) -> void:
	var off := 0
	var wrong := 0
	for id in b.art.order:
		var sp: Vector2 = b.anchor(id)
		var inside: bool = Rect2(Vector2.ZERO, b.size).has_point(sp)
		if when == "whole map" and not inside:
			off += 1
		if inside and b.land_at(sp) != id:
			wrong += 1
	if when == "whole map":
		p.ok(off == 0, "%s, %s: every token is on screen (%d off)" % [mid, when, off])
	p.ok(wrong == 0, "%s, %s: a click on every token comes back to its own land (%d wrong)" % [mid, when, wrong])


func _battle_from_land() -> void:
	## the Gate's melee, out of the board on the land and back into it
	var r: Array = await _game("res://maps/knife7.json", _seats(3))
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	await _settle(gs)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 15, 1)
	w.set_hex("beacon", "red", 3)
	w.set_hex("mill", "red", 3)
	w.set_hex("gate", "blue", 16, 2)
	w.set_hex("harbor", "blue", 4, 1)
	w.set_hex("docks", "green", 13, 1)
	w.set_hex("quarry", "green", 3)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 14)
	s.lock()
	s.lock()
	s.set_attack("docks", "gate", 12)
	s.lock()
	var guard := 0
	var marching := 0
	var live := 0
	var shot := false
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		if gs.board.flow and gs.land.marches.count() > marching:
			marching = gs.land.marches.count()
			live = gs.board.orders.filter(func(o): return float(o.get("alpha", 1.0)) >= 0.95).size()
		if gs.board.flow and gs.land.marches.count() > 0 and not shot:
			shot = true
			await p.frames(70)
			await snap("gate_00_columns_marching")
		await p.frames(1)
	p.ok(marching > 0 and marching == live, "the report: a column marches each live arrow on the land (%d columns, %d arrows)" % [marching, live])
	await p.frames(2)
	p.ok(th._on_land and lf.from_board, "the battle leaves from the board on the land")
	p.ok(lf.handoff_px >= 0.0 and lf.handoff_px < 3.0, "the handoff: the Gate's token is where the land has it (%.1f px off)" % lf.handoff_px)
	p.ok(not gs.land.garrisons.visible, "the board's garrisons stand aside for the battle")
	var lifted: int = gs.land.scenery.cleared()
	p.ok(lifted >= 1, "the Gate's buildings where the melee stands are lifted off the table (%d)" % lifted)
	await p.frames(40)
	await snap("gate_01_down_from_the_board")
	guard = 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				th._answer("p")
			"done":
				await p.frames(30)
				th.press()
		await p.frames(1)
	guard = 0
	while lf.visible and guard < 600:
		guard += 1
		await p.frames(1)
	await p.frames(10)
	await snap("gate_02_back_on_the_board")
	## the report goes on (its camera swoops back out): then the land's camera is the board's
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	## v2.0.2: the report's camera glides back to the view it found as the report ends
	guard = 0
	while gs.board.camera_moving() and guard < 300:
		guard += 1
		await p.frames(1)
	await p.frames(40)
	var lb: Control = gs.land_board
	var eye_now: Vector3 = gs.land.wv.cam.global_position
	var eye_board: Vector3 = gs.land.wv.rig_eye(lb.rig_now())
	p.ok(gs.land.driver == "board" and gs.land.garrisons.visible, "the battle hands the camera back to the board")
	p.ok(gs.land.scenery.cleared() == 0 and gs.land.scenery.pieces.all(func(pc): return (pc["node"] as Node3D).visible or pc["role"] == "village"),
		"and the buildings are put back")
	p.ok(eye_now.distance_to(eye_board) < 2.0, "the camera is where the board looks (%.1f off)" % eye_now.distance_to(eye_board))
	await snap("gate_03_report_done")
	main.queue_free()
	await p.frames(5)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
