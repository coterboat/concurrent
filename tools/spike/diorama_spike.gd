## The diorama spike: the 2D board swoops in on a land as the game does, hands off to the 3D
## world without a seam, the map tips up and the land rises into relief, and the armies of a
## three-way melee march in from the borders they really crossed. Then two exchanges.
##
## Interactive:  $G --path . res://tools/spike/diorama.tscn -- map=known24 land=throne
##   Space replays, 1-6 picks a map, N the next land; once it settles, drag to orbit, wheel to zoom.
## Screenshots and facts: SHOT_DIR=/dir ./scripts/shot.sh diorama
extends Node

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Board := preload("res://game/board/map_board.gd")
const Style := preload("res://game/core/style.gd")
const WorldView := preload("res://game/world3d/world_view.gd")
const Diorama := preload("res://game/world3d/diorama.gd")

const MAPS := ["known24", "world30", "isles24", "ring26", "marches18", "knife7"]
const NAMES := {"red": "Dad", "blue": "Grand Marshal Varek", "green": "Viceroy Ysolde", "gold": "Captain Oren"}

var map_id := "known24"
var land := ""
var map: Types.MapDef
var world: Types.World
var board: Control
var wv: Node3D
var dio: Node3D
var ui: CanvasLayer
var plates: Array = [] ## {panel, army}
var spec: Dictionary
var settled := false
var _orbit := false
var _busy := false
var _snap: Callable = Callable() ## the probe's camera, at named moments


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			map_id = a.trim_prefix("map=")
		elif a.begins_with("land="):
			land = a.trim_prefix("land=")
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		_run.call_deferred(OS.get_cmdline_user_args().has("quit"))


func _run(then_quit: bool) -> void:
	## run alone (the film, or someone pressing play): never touch the player's settings
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null:
		settings.set("persist", false)
	await play()
	if then_quit:
		await _wait(1.0)
		get_tree().quit()


func vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func pick_battle() -> void:
	map = Types.MapDef.from_file("res://maps/%s.json" % map_id)
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}, {"id": "gold", "name": "D"}]
	world = Setup.deal(map, seats, 7)
	## the land with the most land borders (or the one asked for); over a sea lane only if it must
	var art = load("res://game/board/map_art.gd").load_for(map_id)
	var by_sea := func(a: String, b: String) -> bool:
		for l in art.lanes:
			if (l["a"] == a and l["b"] == b) or (l["a"] == b and l["b"] == a):
				return true
		return false
	if land == "" or map.get_territory(land) == null:
		var best := -1
		for id in map.territory_ids():
			var k: int = Array(MapLib.neighbors(map, id)).filter(func(n): return not by_sea.call(id, n)).size()
			if k > best:
				best = k
				land = id
	var nb: Array = Array(MapLib.neighbors(map, land))
	nb.sort_custom(func(p, q): return (0 if not by_sea.call(land, p) else 1) < (0 if not by_sea.call(land, q) else 1) or ((by_sea.call(land, p) == by_sea.call(land, q)) and p < q))
	var fronts := []
	var who := ["red", "green", "gold"]
	var sizes := [12, 7, 16]
	for i in mini(3, nb.size()):
		fronts.append({"pid": who[i], "from": nb[i], "n": sizes[i], "color": Style.seat_color(who[i])})
	spec = {"to": land, "defender": {"pid": "blue", "n": 18, "color": Style.seat_color("blue")}, "fronts": fronts}
	for id in world.territories.keys():
		var ts = world.territories[id]
		if ts.owner != "":
			ts.armies = 1 + (hash(id) % 6)
	world.territories[land].owner = "blue"
	world.territories[land].armies = 18
	for f in fronts:
		world.territories[f["from"]].owner = f["pid"]
		world.territories[f["from"]].armies = int(f["n"]) + 1


func build() -> void:
	for n in [board, wv, dio, ui]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	if board != null:
		(board.get_parent() as Node).queue_free()
	plates.clear()
	settled = false
	pick_battle()
	wv = WorldView.new()
	add_child(wv)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	board = Board.new()
	board.size = vp_size()
	layer.add_child(board)
	board.load_map(map)
	board.world = world
	board.viewer = "red"
	board.battle = {land: true}
	board.refresh()
	wv.setup(board.art, map, board.get("_state_tex"))
	dio = Diorama.new()
	dio.wv = wv
	wv.add_child(dio)
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	dio.setup_dice(ui)
	print("SPIKE terrain %s %dx%d in %d ms, %d props, battle at %s from %s" % [map_id, wv.terrain.w, wv.terrain.h, wv.terrain.millis, wv.props.count, land, str(spec["fronts"].map(func(f): return f["from"]))])


func battle_rig() -> Dictionary:
	## look at the fight from the side no army comes from, high enough to see every column
	var heart: Vector2 = board.art.anchors[land]
	var mean := Vector2.ZERO
	var far := 0.0
	for f in spec["fronts"]:
		var x: Vector2 = dio.crossing(land, f["from"])
		mean += (x - heart).normalized()
		far = maxf(far, heart.distance_to(x))
	var back: Vector2 = -mean.normalized() if mean.length() > 0.2 else Vector2(0, 1)
	back = back.rotated(deg_to_rad(28.0))
	var yaw: float = rad_to_deg(atan2(back.x, back.y))
	var r := {"target": Vector3(0, 0, 0), "pitch": 36.0, "yaw": yaw, "fov": 34.0, "span": clampf(far * 1.25, 190.0, 420.0)}
	var tp: Vector2 = heart + mean.normalized() * far * 0.15
	r["target"] = Vector3(tp.x, wv.terrain.height_at(tp), tp.y)
	## where the armies will stand: the camera rises until no hill stands between it and any of them
	var spots: Array = [heart]
	for f in spec["fronts"]:
		var x: Vector2 = dio.crossing(land, f["from"])
		spots.append(x + (heart - x).normalized() * heart.distance_to(x) * 0.34)
	## the side that sees every army from the lowest angle (the most drama), nearest the first choice
	var best: Dictionary = {}
	for off in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 115.0, -115.0, 150.0, -150.0, 180.0]:
		var c: Dictionary = r.duplicate()
		c["yaw"] = yaw + off
		c["pitch"] = 34.0
		while float(c["pitch"]) < 74.0 and not _sees_all(c, spots):
			c["pitch"] = float(c["pitch"]) + 4.0
		if best.is_empty() or float(c["pitch"]) < float(best["pitch"]) - 0.1:
			best = c
	return best


func _sees_all(r: Dictionary, spots: Array) -> bool:
	var eye: Vector3 = wv.rig_eye(r)
	for s in spots:
		var p: Vector3 = Vector3(s.x, wv.terrain.height_at(s) + dio.FIG * 0.7, s.y)
		for i in range(1, 40):
			var q: Vector3 = eye.lerp(p, float(i) / 40.0)
			if wv.terrain.height_at(Vector2(q.x, q.z)) > q.y + 1.0:
				return false
	return true


func play() -> void:
	if _busy:
		return
	_busy = true
	build()
	await get_tree().process_frame
	await get_tree().process_frame
	await _moment("01_board")
	## the game's own swoop, on the 2D board
	var tw: Tween = board.swoop_to([land], 2.8, 0.8)
	if tw != null:
		await tw.finished
	await _moment("02_board_swooped")
	## the handoff: the 3D world under the board, framed exactly as the board is
	var r0: Dictionary = wv.rig_from_board(board, vp_size())
	var r1: Dictionary = battle_rig()
	wv.relief = 0.0
	wv.realism = 0.0
	wv.fog_k = 0.0
	wv.rig = r0
	wv.apply_rig()
	await get_tree().process_frame
	await get_tree().process_frame
	board.get_parent().set("visible", true)
	await _moment("03_handoff_3d_under")
	var fade := create_tween()
	fade.tween_property(board, "modulate:a", 0.0, 0.45)
	## the map tips up, the land rises, the lens widens as the camera comes down
	var dur := 3.8
	var t := 0.0
	var staged := false
	var shot_mid := false
	var shot_late := false
	var heart: Vector2 = board.art.anchors[land]
	while t < dur:
		var dt: float = get_process_delta_time()
		t = minf(t + dt, dur)
		var k: float = t / dur
		var zoom_t: float = _ease(clampf(k / 0.9, 0.0, 1.0))
		var tilt_t: float = _ease(clampf((k - 0.18) / 0.82, 0.0, 1.0))
		wv.relief = smoothstep(0.08, 0.75, k)
		wv.realism = smoothstep(0.12, 0.8, k)
		var r: Dictionary = wv.lerp_rig(r0, r1, zoom_t, tilt_t)
		var tgt: Vector3 = r["target"]
		r["target"] = Vector3(tgt.x, wv.terrain.height_at(Vector2(tgt.x, tgt.z)) * wv.relief, tgt.z)
		wv.fog_k = smoothstep(0.55, 1.0, k)
		wv.aim_sun(WorldView.SUN_CHART.lerp(WorldView.sun_for(r1["yaw"]), tilt_t).normalized())
		wv.rig = r
		wv.apply_rig()
		if k > 0.62 and not staged:
			staged = true
			dio.stage(spec)
			_make_plates()
		if k > 0.35 and not shot_mid:
			shot_mid = true
			await _moment("04_tipping_up")
		if k > 0.7 and not shot_late:
			shot_late = true
			await _moment("05_rising")
		_update_plates()
		await get_tree().process_frame
	board.get_parent().set("visible", false)
	settled = true
	await _wait(1.6)
	await _moment("06_columns_in")
	## exchanges: every commander throws from where their men stand; then, front by front,
	## the higher die's side fires and one of the other side's men goes down
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for ex in 3:
		## the fronts first, the defender last (one group facing each front)
		var pairs := []
		var di: int = dio.armies.size() - 1
		for ai in di:
			pairs.append({"army": ai, "foe": di, "a": rng.randi_range(1, 6), "d": rng.randi_range(1, 6)})
		var settle: float = dio.throw(pairs)
		await _wait(minf(settle, 1.0) * 0.55)
		if ex == 0:
			await _moment("07_dice_flying")
		await _wait(settle - minf(settle, 1.0) * 0.55 + 0.25)
		if ex == 0:
			await _moment("08_dice_down")
		for k in pairs.size():
			var pr: Dictionary = pairs[k]
			var a_won: bool = int(pr["a"]) > int(pr["d"])
			var tie: bool = int(pr["a"]) == int(pr["d"])
			dio.mark(k, "tie" if tie else ("win" if a_won else "lose"), "tie" if tie else ("lose" if a_won else "win"))
			if not tie:
				var winner: int = pr["army"] if a_won else pr["foe"]
				var loser: int = pr["foe"] if a_won else pr["army"]
				dio.volley(winner, loser)
				dio.set_count(loser, int(dio.armies[loser]["n"]) - 1, winner)
			await _wait(0.6)
		if ex == 0:
			await _moment("09_fallen")
		await _wait(0.8)
	await _moment("10_after_three")
	_busy = false


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		t += get_process_delta_time()
		_update_plates()
		await get_tree().process_frame


func _moment(name: String) -> void:
	if _snap.is_valid():
		await _snap.call(name)


func _process(_d: float) -> void:
	if settled and not _busy:
		_update_plates()


# ------------------------------------------------------------------ plates (Risk 2's: count, colours, name)

func _make_plates() -> void:
	for p in plates:
		(p["panel"] as Control).queue_free()
	plates.clear()
	for ai in dio.armies.size():
		var a: Dictionary = dio.armies[ai]
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.82)
		sb.border_color = a["color"]
		sb.set_border_width_all(2)
		sb.border_width_left = 10
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 16
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var num := Label.new()
		num.add_theme_font_override("font", Style.font("title"))
		num.add_theme_font_size_override("font_size", 26)
		num.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
		var nm := Label.new()
		nm.text = NAMES.get(a["pid"], a["pid"])
		nm.add_theme_font_override("font", Style.font("body"))
		nm.add_theme_font_size_override("font_size", 17)
		nm.add_theme_color_override("font_color", (a["color"] as Color).lightened(0.35))
		hb.add_child(num)
		hb.add_child(nm)
		panel.add_child(hb)
		ui.add_child(panel)
		plates.append({"panel": panel, "army": ai, "num": num})


func _update_plates() -> void:
	for p in plates:
		var ai: int = p["army"]
		if ai >= dio.armies.size():
			continue
		var n: int = int(dio.armies[ai]["n"])
		var top: Vector3 = dio.centre_of(ai)
		(p["num"] as Label).text = str(n)
		var panel: Control = p["panel"]
		if wv.cam.is_position_behind(top):
			panel.visible = false
			continue
		panel.visible = true
		var s: Vector2 = wv.cam.unproject_position(top)
		panel.position = s - Vector2(panel.size.x * 0.5, panel.size.y)
	## no plate covers another: the lower of two that meet steps down below it
	var shown: Array = plates.filter(func(q): return (q["panel"] as Control).visible)
	shown.sort_custom(func(p1, p2): return (p1["panel"] as Control).position.y < (p2["panel"] as Control).position.y)
	for i in shown.size():
		var pi: Control = shown[i]["panel"]
		for j in i:
			var pj: Control = shown[j]["panel"]
			var ri := Rect2(pi.position, pi.size).grow(3.0)
			var rj := Rect2(pj.position, pj.size)
			if ri.intersects(rj):
				pi.position.y = rj.end.y + 4.0


# ------------------------------------------------------------------ looking round

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE:
			play()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_6:
			map_id = MAPS[e.keycode - KEY_1]
			land = ""
			play()
		elif e.keycode == KEY_N and map != null:
			var ids: Array = Array(map.territory_ids())
			land = ids[(ids.find(land) + 1) % ids.size()]
			play()
	if not settled or _busy or wv == null:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_orbit = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			wv.rig["span"] = maxf(60.0, float(wv.rig["span"]) * 0.9)
			wv.apply_rig()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wv.rig["span"] = minf(2400.0, float(wv.rig["span"]) * 1.1)
			wv.apply_rig()
	elif e is InputEventMouseMotion and _orbit:
		wv.rig["yaw"] = float(wv.rig["yaw"]) - e.relative.x * 0.3
		wv.rig["pitch"] = clampf(float(wv.rig["pitch"]) + e.relative.y * 0.2, 8.0, 89.0)
		wv.apply_rig()


# ------------------------------------------------------------------ the gallery: a map's land, whole

func gallery(snap: Callable) -> void:
	## the whole map raised and lit, then its high ground up close
	build()
	board.get_parent().set("visible", false)
	wv.relief = 1.0
	wv.realism = 1.0
	var ms: Vector2 = board.art.size
	var r := {"target": Vector3(ms.x * 0.5, 0.0, ms.y * 0.52), "pitch": 50.0, "yaw": 0.0, "fov": 30.0, "span": ms.y * 0.95}
	wv.rig = r
	wv.fog_k = 0.35
	wv.aim_sun(WorldView.sun_for(0.0))
	wv.apply_rig()
	for i in 6:
		await get_tree().process_frame
	await snap.call("gallery_whole")
	## the highest land, close: where the mountains are, if the map has any
	var best := ""
	var top := -1.0e9
	for id in board.art.order:
		var hv: float = wv.terrain.height_at(board.art.anchors[id])
		if hv > top:
			top = hv
			best = id
	var a: Vector2 = board.art.anchors[best]
	wv.rig = {"target": Vector3(a.x, top, a.y), "pitch": 32.0, "yaw": 25.0, "fov": 34.0, "span": 520.0}
	wv.aim_sun(WorldView.sun_for(25.0))
	wv.apply_rig()
	for i in 6:
		await get_tree().process_frame
	await snap.call("gallery_high_" + best)
