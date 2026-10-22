## The battle on the land itself (v2.0): the battle screen's backdrop is the map's own ground in
## 3D (game/world3d/terrain.gd, for any map), and its armies stand where they came from. It
## answers the theater as BattleField does (setup, set_count, volley, charge, cheer, reload,
## retreat, burst), so the theater's dice, calls and words are untouched. It opens out of the
## 2D board (the same frame to the pixel, then the map tips up and the land rises) and closes
## back into it; when the board already stands on the land (LandBoard), out of that very camera.
## The land is the game's one world (land.gd), drawn at the screen's real resolution.
extends Control

const WorldView := preload("res://game/world3d/world_view.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Types := preload("res://engine/types.gd")
const Style := preload("res://game/core/style.gd")
const Scenery := preload("res://game/world3d/scenery.gd")
const MapLib := preload("res://engine/map.gd")

const BAND_TOP := 300.0 ## the screen the armies must stand in: below the title and the faces...
const BAND_BOTTOM := 236.0 ## ...and above the dice tray (from the bottom)
const CHART := {"relief": 0.0, "realism": 0.0, "paint": 0.0, "fog": 0.0, "sun": WorldView.SUN_CHART}

var board: Control
var land: Node ## land.gd: the game's one world
var armies: Array = [] ## the theater's army list, as given to setup
var quiet := false
var prepared: bool:
	get:
		return land != null and land.prepared
var wv: Node3D:
	get:
		return land.wv if land != null else null
var dio: Node3D: ## the battle's armies
	get:
		return land.battle if land != null and land.prepared else null
var _px: float:
	get:
		return land.px if land != null else 1.0
var _terrain: RefCounted:
	get:
		return land.wv.terrain if prepared else null
var _art: RefCounted:
	get:
		return land.wv.art if prepared else null
var _map: RefCounted:
	get:
		return land.wv.map if prepared else null
var _plates: Array = [] ## {panel, num, tag, army, sb}
var _tags := {} ## v2.2: army -> the name on its plate ("from Ridge")
var _rig_base: Dictionary = {}
var _clock := 0.0
var _land := ""
var _last_foe := {} ## army -> the army that last fired on it (its loss comes off that front)
var handoff_px := -1.0 ## how far the land's token sits from the board's at the handoff (probes: 0)
var from_board := false ## this battle left from the board on the land (not the chart)
var _seq := 0 ## the camera move under way: a newer one (a skip mid-tilt) stops the older
var _near: Array = [] ## the buildings round the fight the camera is placed for (scenery.gd)
var _top_roof := -1.0e9 ## v2.4: the highest of their roofs (a sight line above it passes them all)
var _walls := -1 ## the army holding a fort's or a capital's walls (its guns boom when it wins a volley)
var covering := false ## v2.4: the land covers the screen and the board under it rests (_cover)
var _fort := {} ## v2.4: the fort the fight is at (a scenery piece), or {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit)


func _fit() -> void:
	if land == null or size.x < 4.0 or get_viewport() == null:
		return
	land.fit(size, get_viewport().get_final_transform().get_scale().x)


func _draw() -> void:
	if prepared:
		draw_texture_rect(land.texture(), Rect2(Vector2.ZERO, size), false)


# ------------------------------------------------------------------ the world, built once a game

func prepare(p_board: Control) -> void:
	## Start building this map's land in the background (land.gd). Called when a game's map loads.
	board = p_board
	if land == null:
		return
	land.quiet = quiet
	land.prepare(board)


func _process(delta: float) -> void:
	_clock += delta
	if prepared and visible and dio != null:
		_update_plates()
		if dio.shake > 0.0 and not _rig_base.is_empty():
			var r: Dictionary = _rig_base.duplicate()
			var s: float = dio.shake * dio.shake * 1.6
			r["target"] = (r["target"] as Vector3) + Vector3(randf_range(-s, s), randf_range(-s, s) * 0.6, randf_range(-s, s))
			wv.rig = r
			wv.apply_rig()
		queue_redraw()


func wait_ready() -> bool:
	## the land is ready for a battle (waits for the background build, a frame at a time)
	if land == null:
		return false
	return await land.wait_ready()


func _on_board() -> bool:
	## the board stands on the land: a battle leaves from its camera and comes back to it
	return land != null and land.view != null and land.view.active()


# ------------------------------------------------------------------ in and out of the board

func open(land_id: String, first_spots: Array) -> void:
	## The handoff: the 3D world framed exactly as the board is, faded in over it (the same
	## picture, so only the tokens and the HUD go), then the camera comes down on the fight; from
	## the chart, the map tips up and the land rises on the way.
	_land = land_id
	visible = true
	_fit()
	from_board = _on_board()
	land.driver = "battle"
	land.show_for("battle", true)
	land.garrisons.visible = false
	land.marches.visible = false
	for k in ["hover_id", "select_id"]:
		wv.gmat.set_shader_parameter(k, -1) ## the board's highlights stay on the board
	dio.quiet = quiet
	dio.clear()
	_clear_plates()
	var region: String = _map.get_territory(land_id).region if _map.get_territory(land_id) != null else ""
	dio.ground = str(_map.region_terrain.get(region, "grass"))
	dio.heart = _art.anchors[land_id]
	var r0: Dictionary = wv.rig.duplicate() if from_board else _board_rig()
	var s0: Dictionary = land.state() if from_board else CHART.duplicate()
	land.apply_state(s0)
	## the scenery where the fight will stand is lifted off the table (before the camera is placed);
	## v2.4: a fort stays, the fight is at its walls (_at_the_fort), and the camera takes it in
	_fort = _fort_of(land_id)
	land.scenery.clear_for(first_spots, Diorama.FIG * 2.5, [] if _fort.is_empty() else [_fort])
	var r1: Dictionary = _battle_rig(land_id, first_spots, _fort_frame())
	var s1 := {"relief": 1.0, "realism": 1.0, "paint": 0.0, "fog": 1.0, "sun": WorldView.sun_for(float(r1["yaw"]))}
	wv.rig = r0
	wv.apply_rig()
	var a: Vector2 = _art.anchors[land_id]
	var on3d: Vector2 = land.project(a)
	var on2d: Vector2 = get_global_transform().affine_inverse() * (board.get_global_transform() * board.anchor(land_id))
	handoff_px = on3d.distance_to(on2d)
	modulate.a = 0.0
	_seq += 1
	var my: int = _seq
	await get_tree().process_frame
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.35)
	fade.finished.connect(func():
		if my == _seq and visible:
			_cover(true))
	await _tilt(r0, r1, s0, s1, 2.2 if from_board else 2.6, true, my)
	if my == _seq:
		_rig_base = r1


func close() -> void:
	## Back to the board: the fallen are cleared from the table, the camera rises back to where
	## the board looks (the land sinking into the chart if the board is the chart), and the board
	## under it shows through (the same frame again).
	if not prepared or not visible:
		visible = false
		_release()
		return
	_clear_plates()
	_seq += 1
	var my: int = _seq
	_rig_base = {}
	dio.sweep()
	await get_tree().create_timer(0.55).timeout
	var r1: Dictionary = wv.rig.duplicate()
	var s1: Dictionary = land.state()
	var back_on: bool = _on_board()
	var r0: Dictionary = land.view.rig_now() if back_on else _board_rig()
	var s0: Dictionary = land.view.state_for(land.view.t) if back_on else CHART.duplicate()
	## (the board may move while the camera rises: it rises to where the board is)
	await _tilt(r1, r0, s1, s0, 1.6, false, my, Callable(land.view, "rig_now") if back_on else Callable())
	_cover(false) ## the board shows through again as the land fades
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.3)
	await fade.finished
	if my != _seq:
		return
	dio.clear()
	visible = false
	_release()


func abort() -> void:
	_seq += 1
	_rig_base = {}
	if dio != null:
		dio.clear()
	_clear_plates()
	visible = false
	_release()


func _cover(on: bool) -> void:
	## v2.4: while the land covers the whole screen the board under it isn't drawn. It went on drawing
	## every frame through the battle's camera, unseen, and on the land a frame of it could take a
	## third of a second as the camera tipped down (the owner: "the zoom in between the main map and
	## battle map on 3d absolutely chugs"); every frame of the fight paid for it too
	covering = on
	if board != null and is_instance_valid(board) and board.get("overlay") != null:
		(board.overlay as CanvasItem).visible = not on


func _release() -> void:
	## the camera goes back to the board (if it stands on the land), the garrisons come back
	_cover(false)
	if land == null:
		return
	land.show_for("battle", false)
	if land.driver == "battle":
		land.driver = "board" if _on_board() else ""
	if land.prepared:
		land.garrisons.visible = true
		land.marches.visible = true
		land.scenery.restore()


func _tilt(a: Dictionary, b: Dictionary, sa: Dictionary, sb: Dictionary, dur: float, opening: bool, my: int, b_now: Callable = Callable()) -> void:
	var t := 0.0
	while t < dur and my == _seq:
		if b_now.is_valid():
			b = b_now.call()
		t = minf(t + get_process_delta_time(), dur)
		var k: float = t / dur
		var zoom_t: float = _ease(clampf(k / 0.9, 0.0, 1.0))
		var tilt_t: float = _ease(clampf((k - 0.15) / 0.85, 0.0, 1.0))
		if not opening:
			## closing: rise first, flatten as the camera straightens
			zoom_t = _ease(clampf((k - 0.1) / 0.9, 0.0, 1.0))
			tilt_t = _ease(clampf(k / 0.85, 0.0, 1.0))
		var up_k: float = smoothstep(0.08, 0.75, k) if opening else smoothstep(0.25, 0.92, k)
		var real_k: float = smoothstep(0.12, 0.8, k) if opening else smoothstep(0.2, 0.85, k)
		wv.relief = lerpf(float(sa["relief"]), float(sb["relief"]), up_k)
		wv.realism = lerpf(float(sa["realism"]), float(sb["realism"]), real_k)
		wv.paint = lerpf(float(sa["paint"]), float(sb["paint"]), real_k)
		wv.fog_k = lerpf(float(sa["fog"]), float(sb["fog"]), up_k)
		var r: Dictionary = wv.lerp_rig(a, b, zoom_t, tilt_t)
		var tg: Vector3 = r["target"]
		r["target"] = Vector3(tg.x, lerpf((a["target"] as Vector3).y, (b["target"] as Vector3).y, zoom_t), tg.z)
		wv.aim_sun((sa["sun"] as Vector3).lerp(sb["sun"], tilt_t).normalized())
		wv.rig = r
		wv.apply_rig()
		queue_redraw()
		await get_tree().process_frame


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _board_rig() -> Dictionary:
	## the rig that frames exactly what the 2D board shows (relief flat, straight down)
	var gt: Transform2D = board.get_global_transform()
	var centre: Vector2 = gt.affine_inverse() * (get_global_transform() * (size * 0.5))
	var c: Vector2 = board.screen_to_map(centre)
	var span: float = size.y / (float(board.zoom) * gt.get_scale().y / get_global_transform().get_scale().y)
	return {"target": Vector3(c.x, 0.0, c.y), "pitch": 90.0, "yaw": 0.0, "fov": 1.2, "span": span}


func _battle_rig(land_id: String, spots: Array, frame: Array = []) -> Dictionary:
	## The camera for a fight. The battle's words leave a band of screen clear between the title
	## and the dice tray, wide and short, so the camera stands on the side from which the armies
	## spread across the screen rather than towards it, rises until no hill hides any of them,
	## comes in as close as the band allows, and sets the fight in the middle of the band.
	## v2.4: `frame` is ground it takes in as well, that needn't be seen whole (a fort's walls)
	var heart: Vector2 = _art.anchors[land_id]
	if spots.is_empty():
		spots = [heart]
	var seen: Array = spots
	spots = spots + frame
	var c := Vector2.ZERO
	for s in spots:
		c += s
	c /= float(spots.size())
	_near = land.scenery.near(c, 900.0) if land != null and land.scenery != null else []
	_top_roof = -1.0e9
	for pc in _near:
		_top_roof = maxf(_top_roof, float(pc["base"]) + float(pc["h"]))
	var band_h: float = size.y - BAND_TOP - BAND_BOTTOM
	var band_w: float = size.x - 120.0
	var best: Dictionary = {}
	var best_span := 1.0e9
	for step in 24:
		var yaw: float = float(step) * 15.0
		var back := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		var right := Vector2(back.y, -back.x)
		var lat := Vector2(1.0e9, -1.0e9)
		var dep := Vector2(1.0e9, -1.0e9)
		for s in spots:
			var d: Vector2 = (s as Vector2) - c
			lat = Vector2(minf(lat.x, d.dot(right)), maxf(lat.y, d.dot(right)))
			dep = Vector2(minf(dep.x, d.dot(back)), maxf(dep.y, d.dot(back)))
		var r := {"target": Vector3(c.x, _terrain.height_at(c), c.y), "pitch": 36.0, "yaw": yaw, "fov": 32.0, "span": 300.0}
		while float(r["pitch"]) < 70.0 and not _sees_all(r, seen):
			r["pitch"] = float(r["pitch"]) + 4.0
		## the span (world units, top to bottom of the screen) that fits the spread into the band
		var need_w: float = (lat.y - lat.x + Diorama.FIG * 6.0) * size.y / band_w
		var need_h: float = ((dep.y - dep.x) * sin(deg_to_rad(r["pitch"])) + Diorama.FIG * 3.5) * size.y / band_h
		var span: float = maxf(maxf(need_w, need_h), 150.0) * (1.0 + (float(r["pitch"]) - 36.0) / 60.0)
		if span < best_span - 0.5:
			best_span = span
			r["span"] = clampf(span, 150.0, 900.0)
			best = r
	## the fight in the middle of the band; wider only if it still doesn't fit
	for i in 8:
		_centre_in_band(best, c)
		if _in_band(best, spots):
			break
		best["span"] = float(best["span"]) * 1.1
	return best


func _centre_in_band(r: Dictionary, c: Vector2) -> void:
	## move the camera's target so the fight's middle sits in the middle of the band
	var saved: Dictionary = wv.rig
	var rel: float = wv.relief
	wv.relief = 1.0
	var hc: float = _terrain.height_at(c)
	for k in 3:
		wv.rig = r
		wv.apply_rig()
		var band_c := Vector2(size.x * 0.5, (BAND_TOP + size.y - BAND_BOTTOM) * 0.5) * _px
		var o: Vector3 = wv.cam.project_ray_origin(band_c)
		var dn: Vector3 = wv.cam.project_ray_normal(band_c)
		if absf(dn.y) < 0.001:
			break
		var q: Vector3 = o + dn * ((hc - o.y) / dn.y)
		var tg: Vector3 = r["target"]
		r["target"] = tg + Vector3(c.x - q.x, 0.0, c.y - q.z)
	wv.relief = rel
	wv.rig = saved
	wv.apply_rig()


func _sees_all(r: Dictionary, spots: Array) -> bool:
	## no hill and no building between the camera and anyone. v2.4: the same answer, asked only where
	## it could be no: a point of the line above the highest ground and the highest roof hides nothing,
	## and only a building whose walls come near the line can stand in it (asked of every building at
	## every point, the camera's search took 35-50 ms, in the frame the battlefield opens)
	var eye: Vector3 = wv.rig_eye(r)
	var top: float = _terrain.hi
	for s in spots:
		var p := Vector3(s.x, _terrain.height_at(s) + Diorama.FIG * 0.7, s.y)
		var in_way: Array = _near_line(eye, p)
		for i in range(1, 40):
			var q: Vector3 = eye.lerp(p, float(i) / 40.0)
			if q.y + 1.0 < top and _terrain.height_at(Vector2(q.x, q.z)) > q.y + 1.0:
				return false
			if not in_way.is_empty() and i > 4 and i < 38 and q.y < _top_roof and Scenery.blocks(q, in_way):
				return false
	return true


func _near_line(a: Vector3, b: Vector3) -> Array:
	## the buildings round the fight whose walls come near enough the line from a to b, seen from
	## above, to stand in it (Scenery.blocks: within 0.8 of its reach of a point of the line)
	var out: Array = []
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for pc in _near:
		var at: Vector2 = pc["at"]
		if Geometry2D.get_closest_point_to_segment(at, a2, b2).distance_to(at) < float(pc["r"]) * 0.8:
			out.append(pc)
	return out


func _in_band(r: Dictionary, spots: Array) -> bool:
	var saved: Dictionary = wv.rig
	var rel: float = wv.relief
	wv.relief = 1.0
	wv.rig = r
	wv.apply_rig()
	var ok := true
	for s in spots:
		var p: Vector2 = wv.cam.unproject_position(Vector3(s.x, _terrain.height_at(s) + Diorama.FIG, s.y)) / _px
		if p.y < BAND_TOP or p.y > size.y - BAND_BOTTOM or p.x < 60.0 or p.x > size.x - 60.0:
			ok = false
			break
	wv.relief = rel
	wv.rig = saved
	wv.apply_rig()
	return ok


# ------------------------------------------------------------------ the theater's army list, placed

func spots_for(land: String, e: Dictionary, b: Dictionary) -> Array:
	## where the armies of this fight will stand (before they're placed: the camera's brief)
	return (_plan(land, e, b, [])["spots"] as Array)


func setup(list: Array) -> void:
	## BattleField's way in (no geography): a generic two-sided fight at the land
	setup_at(list, _land, {}, {})


func setup_at(list: Array, land: String, e: Dictionary, b: Dictionary) -> void:
	armies = list
	_last_foe = {}
	_tags = {}
	## who holds the walls: a fort's or a capital's defenders have guns on them (they boom when they win)
	_walls = -1
	var kind: String = str(e.get("kind", ""))
	if land != "" and board != null and (MapLib.has_trait(_map, land, "fort") or MapLib.is_capital(board.world, _map, land)):
		if kind == Types.EVENT_MELEE:
			_walls = (e.get("fronts", []) as Array).size()
		elif kind == Types.EVENT_INVASION:
			_walls = 1
	var plan: Dictionary = _plan(land, e, b, list)
	dio.heart = plan["heart"]
	dio.place(plan["armies"])
	dio.live = true
	_make_plates()


func arrival() -> float:
	return dio.arrival() if dio != null else 0.0


func _plan(land: String, e: Dictionary, b: Dictionary, list: Array) -> Dictionary:
	## Each of the theater's armies, where it stands: fronts at the borders they crossed, the
	## defender split to face them; a clash on the border between the two lands; a scramble's
	## armies each at their own way in.
	var kind: String = str(e.get("kind", ""))
	var heart: Vector2 = _art.anchors.get(land, Vector2.ZERO)
	var out: Array = []
	var spots: Array = []
	var col := func(i: int) -> Color:
		return Style.seat_color(str(list[i]["pid"])) if i < list.size() else Color.GRAY
	var n_of := func(i: int, fallback: int) -> int:
		return int(list[i]["n"]) if i < list.size() else fallback
	var pid_of := func(i: int) -> String:
		return str(list[i]["pid"]) if i < list.size() else ""
	if kind == Types.EVENT_MELEE or kind == Types.EVENT_SCRAMBLE:
		var fronts: Array = e.get("fronts", [])
		var total := 0
		for f in fronts:
			total += int(f["size"])
		var groups: Array = []
		for i in fronts.size():
			var f: Dictionary = fronts[i]
			var g: Dictionary = dio.front_group(land, str(f.get("from", "")), n_of.call(i, int(f["size"])))
			g["foe"] = fronts.size() if kind == Types.EVENT_MELEE else -1
			out.append({"pid": pid_of.call(i), "color": col.call(i), "n": n_of.call(i, int(f["size"])), "groups": [g]})
			spots.append(g["at"])
			if kind == Types.EVENT_MELEE:
				groups.append({"x": g["cross"], "dist": g["dist"], "w": int(f["size"]), "foe": i})
		if kind == Types.EVENT_MELEE:
			var di: int = fronts.size()
			var dn: int = n_of.call(di, int(e.get("defenderSize", 1)))
			var left: int = dn
			var dg: Array = []
			for k in groups.size():
				var gg: Dictionary = groups[k]
				var share: int = left if k == groups.size() - 1 else int(round(float(dn) * float(gg["w"]) / float(maxi(total, 1))))
				share = clampi(share, 0, left)
				left -= share
				var out_dir: Vector2 = ((gg["x"] as Vector2) - heart).normalized()
				var at: Vector2 = heart + out_dir * minf(float(gg["dist"]) * 0.18, Diorama.FIG * 3.2)
				dg.append({"at": at, "dir": out_dir, "share": share, "foe": gg["foe"]})
				spots.append(at)
			out.append({"pid": pid_of.call(di), "color": col.call(di), "n": dn, "groups": dg})
	elif kind == Types.EVENT_CLASH:
		## both columns marched at once and met on the border between their lands
		var ha: String = str(e.get("hexA", ""))
		var hb: String = str(e.get("hexB", ""))
		var x: Vector2 = dio.crossing(hb, ha) if _art.anchors.has(ha) and _art.anchors.has(hb) else heart
		var pa: Vector2 = _art.anchors.get(ha, x + Vector2(-100, 0))
		var pb: Vector2 = _art.anchors.get(hb, x + Vector2(100, 0))
		var ab: Vector2 = (pb - pa).normalized()
		heart = x
		var ga := {"at": x - ab * Diorama.FIG * 3.2, "dir": ab, "share": n_of.call(0, 1), "cross": x, "dist": pa.distance_to(x), "foe": 1}
		var gb := {"at": x + ab * Diorama.FIG * 3.2, "dir": -ab, "share": n_of.call(1, 1), "cross": x, "dist": pb.distance_to(x), "foe": 0}
		out = [{"pid": pid_of.call(0), "color": col.call(0), "n": n_of.call(0, 1), "groups": [ga]},
			{"pid": pid_of.call(1), "color": col.call(1), "n": n_of.call(1, 1), "groups": [gb]}]
		spots = [ga["at"], gb["at"]]
	elif kind == Types.EVENT_INVASION and _art.anchors.has(str(e.get("from", ""))):
		var g: Dictionary = dio.front_group(land, str(e["from"]), n_of.call(0, 1))
		g["foe"] = 1
		var out_dir: Vector2 = ((g["cross"] as Vector2) - heart).normalized()
		var dat: Vector2 = heart + out_dir * minf(float(g["dist"]) * 0.15, Diorama.FIG * 2.8)
		out = [{"pid": pid_of.call(0), "color": col.call(0), "n": n_of.call(0, 1), "groups": [g]},
			{"pid": pid_of.call(1), "color": col.call(1), "n": n_of.call(1, 1), "groups": [{"at": dat, "dir": out_dir, "share": n_of.call(1, 1), "foe": 0}]}]
		spots = [g["at"], dat]
	else:
		## two armies with no way in on the log (the spoils): face to face across the land's heart
		var across := Vector2(1, 0)
		for i in maxi(2, list.size()):
			var sgn: float = -1.0 if i % 2 == 0 else 1.0
			var at: Vector2 = heart + across * sgn * Diorama.FIG * 3.5 + Vector2(0, Diorama.FIG * 2.5 * float(i / 2))
			out.append({"pid": pid_of.call(i), "color": col.call(i), "n": n_of.call(i, 1), "groups": [{"at": at, "dir": -across * sgn, "share": n_of.call(i, 1), "foe": (i + 1) % 2, "dist": 160.0}]})
			spots.append(at)
	## v2.1: a big army brings its train into battle as well as its men, with its biggest group
	for a in out:
		var tr: Dictionary = Diorama.battle_train(int(a["n"]))
		if (a["groups"] as Array).is_empty() or int(tr["horse"]) + int(tr["guns"]) == 0:
			continue
		var big: Dictionary = a["groups"][0]
		for g in a["groups"]:
			if int(g["share"]) > int(big["share"]):
				big = g
		big["horse"] = int(tr["horse"])
		big["guns"] = int(tr["guns"])
		big["train"] = true
	## v2.4: a fort's defenders hold its walls
	var fort: Dictionary = _fort_of(land)
	if not fort.is_empty() and (kind == Types.EVENT_MELEE or kind == Types.EVENT_INVASION) and out.size() >= 2:
		heart = _at_the_fort(out, fort)
	## the camera frames every group whole: its front and its rear rank (and its horse and guns)
	spots = []
	for a in out:
		for g in a["groups"]:
			var men: int = int(Diorama.pieces(int(g["share"]))["inf"])
			var files: int = Diorama.files_for(men, g.has("fort"))
			var heavy: bool = (int(g["share"]) > 12 or bool(g.get("train", false))) and not g.has("fort") ## (at a fort: beside the men)
			var depth: float = ceil(float(men) / float(files)) * Diorama.FIG * 1.05 + Diorama.FIG * (2.4 if heavy else 1.0)
			if g.has("fort"):
				depth = _deep(g) - Diorama.FIG * 0.2 ## (its rear rank, at the foot of the wall: the walls are the fort's)
			spots.append(g["at"])
			spots.append((g["at"] as Vector2) - (g["dir"] as Vector2) * depth)
			if bool(g.get("by_sea", false)) and g.has("sea_from"):
				## a landing: the beach and the last of the water the boats cross
				var x: Vector2 = g["cross"]
				spots.append(x)
				spots.append(x + ((g["sea_from"] as Vector2) - x) * 0.3)
	return {"armies": out, "spots": spots, "heart": heart}


# ------------------------------------------------------------------ v2.4: a fight at a fort

func _fort_of(land_id: String) -> Dictionary:
	## the land's star fort as it stands on the land (scenery.gd), if the rules give it one
	if land_id == "" or land == null or land.scenery == null or _map == null or not MapLib.has_trait(_map, land_id, "fort"):
		return {}
	for pc in land.scenery.pieces:
		if str(pc["land"]) == land_id and str(pc["kind"]) == "starfort":
			return pc
	return {}


func _fort_frame() -> Array:
	## the fort's ground, for the camera to take in (it needn't see over every wall of it)
	if _fort.is_empty():
		return []
	var at: Vector2 = _fort["at"]
	var r: float = float(_fort["r"]) * 0.9
	return [at + Vector2(r, 0), at - Vector2(r, 0), at + Vector2(0, r), at - Vector2(0, r)]


func _at_the_fort(out: Array, fort: Dictionary) -> Vector2:
	## The owner: "when a fort exists in a territory... have the defending army defending from
	## within/outside the fort against the direction(s) of the foe(s) they're facing". The fort stays
	## on the table and the fight is at its walls: each of the defender's groups lines the wall that
	## faces its foe, two deep, its horse and guns beside it and its drummer and colours inside the
	## walls with the commander; each column halts on its road in, facing that wall a few men's
	## heights off. Only where they stand changes, never the dice. Returns the fight's heart: the fort.
	var at: Vector2 = fort["at"]
	var wall: float = float(fort["r"]) * 0.85 + Diorama.FIG * 0.4 ## (scenery.clear_of keeps a man this far out)
	var di: int = out.size() - 1 ## the defender is the last army
	for dg in out[di]["groups"]:
		var foe: int = int(dg.get("foe", -1))
		if foe < 0 or foe >= di or (out[foe]["groups"] as Array).is_empty():
			continue
		var ag: Dictionary = out[foe]["groups"][0]
		var x: Vector2 = ag.get("cross", ag["at"])
		var toward: Vector2 = (x - at).normalized() if x.distance_to(at) > 1.0 else -(ag["dir"] as Vector2)
		var d: float = wall + _deep(dg)
		dg["at"] = at + toward * d
		dg["dir"] = toward
		dg["fort"] = at
		dg["fort_r"] = float(fort["r"])
		var stand: float = d + Diorama.FIG * 4.0
		var dx: float = x.distance_to(at)
		if stand > dx - Diorama.FIG:
			stand = maxf(dx - Diorama.FIG, d + Diorama.FIG * 2.5)
		ag["at"] = at + toward * stand
		ag["dir"] = -toward
		ag["dist"] = dx
	return at


static func _deep(g: Dictionary) -> float:
	## how far a group lining a fort's walls stands from its front rank to its rear one, with a step
	## to spare (diorama.gd _form: two deep, its train beside it, its colours inside the walls)
	var men: int = int(Diorama.pieces(int(g["share"]))["inf"])
	var ranks: int = int(ceil(float(men) / float(Diorama.files_for(men, true))))
	return float(ranks - 1) * Diorama.FIG * 1.05 + Diorama.FIG * 0.5


func _fort_guns(foe: int) -> void:
	## the fort's own guns speak from the bastion facing the foe
	if _fort.is_empty() or dio == null or foe < 0 or foe >= dio.armies.size():
		return
	var at: Vector2 = _fort["at"]
	var them: Vector2 = dio.armies[foe]["groups"][dio.group_against(foe, _walls)]["at"]
	var toward: Vector2 = (them - at).normalized() if them.distance_to(at) > 1.0 else Vector2(0, 1)
	dio.gun_smoke(at + toward * float(_fort["r"]) * 0.72, toward)


# ------------------------------------------------------------------ BattleField's calls

func set_count(ai: int, n: int) -> void:
	if dio != null:
		dio.set_count(ai, n, int(_last_foe.get(ai, -1)))


func volley(ai: int, foe: int = -1) -> String:
	## the land plays its own sounds (a crack per musket, the cannon's thump and its ball): the
	## theater gets nothing to play
	if dio == null:
		return ""
	if foe >= 0:
		_last_foe[foe] = ai
	var did: String = dio.volley(ai, foe)
	if ai == _walls and randf() < 0.6:
		_fort_guns(foe) ## v2.4: seen to fire too, at a fort
		if not quiet:
			Audio.field("fort_gun", -5.0) ## the guns on the walls
	return "cavalry" if did == "cavalry" else ""


func charge(ai: int) -> String:
	return dio.charge(ai) if dio != null else ""


func cheer(ai: int) -> void:
	if dio != null:
		dio.cheer(ai)
		dio.live = false


func reload(ai: int) -> void:
	if dio != null:
		dio.reload(ai)


func retreat(ai: int) -> void:
	if dio != null:
		dio.retreat(ai)


func burst(name: String, _pos: Vector2, _px2: float, _toward_right: bool = true, _delay: float = 0.0, _dur: float = 0.0) -> bool:
	if dio == null:
		return false
	if name == "capital_fire":
		dio.fire_burst(dio.heart, 10)
		return true
	return false


# ------------------------------------------------------------------ plates: Risk 2's, a count over each army

func _clear_plates() -> void:
	for p in _plates:
		(p["panel"] as Control).queue_free()
	_plates.clear()


func _make_plates() -> void:
	_clear_plates()
	for ai in dio.armies.size():
		var a: Dictionary = dio.armies[ai]
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.8)
		sb.border_color = a["color"]
		sb.set_border_width_all(2)
		sb.border_width_left = 8
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		panel.add_theme_stylebox_override("panel", sb)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var num := Label.new()
		num.add_theme_font_override("font", Style.font("title"))
		num.add_theme_font_size_override("font_size", 22)
		num.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
		row.add_child(num)
		## v2.2: a front's name, the same one its dice carry on the tray's rail
		var tag := Label.new()
		tag.add_theme_font_override("font", Style.font("italic"))
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", (a["color"] as Color).lightened(0.55))
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.size_flags_vertical = Control.SIZE_FILL
		tag.text = str(_tags.get(ai, ""))
		tag.visible = tag.text != ""
		row.add_child(tag)
		add_child(panel)
		panel.pivot_offset = Vector2(20, 14)
		_plates.append({"panel": panel, "num": num, "tag": tag, "army": ai, "sb": sb})


func _update_plates() -> void:
	for p in _plates:
		var ai: int = p["army"]
		if ai >= dio.armies.size():
			continue
		var n: int = int(dio.armies[ai]["n"])
		(p["num"] as Label).text = str(n)
		var panel: Control = p["panel"]
		var top: Vector3 = dio.centre_of(ai)
		if wv.cam.is_position_behind(top) or bool(dio.armies[ai]["fled"]):
			panel.visible = false
			continue
		panel.visible = n > 0
		var s: Vector2 = wv.cam.unproject_position(top) / _px
		panel.position = s - Vector2(panel.size.x * 0.5, panel.size.y)
	## no plate covers another
	var shown: Array = _plates.filter(func(q): return (q["panel"] as Control).visible)
	shown.sort_custom(func(p1, p2): return (p1["panel"] as Control).position.y < (p2["panel"] as Control).position.y)
	for i in shown.size():
		var pi: Control = shown[i]["panel"]
		for j in i:
			var pj: Control = shown[j]["panel"]
			if Rect2(pi.position, pi.size).grow(2.0).intersects(Rect2(pj.position, pj.size)):
				pi.position.y = pj.position.y + pj.size.y + 3.0


func set_tag(ai: int, text: String) -> void:
	## v2.2: name an army's plate (a melee's fronts: "from Ridge"), so its dice can be found on it
	_tags[ai] = text
	for p in _plates:
		if int(p["army"]) == ai:
			(p["tag"] as Label).text = text
			(p["tag"] as Label).visible = text != ""


func plate_point(ai: int) -> Vector2:
	## the foot of army ai's plate on screen (a pair's thread from the tray ends there), or
	## (-1, -1) when it isn't shown
	for p in _plates:
		var panel: Control = p["panel"]
		if int(p["army"]) == ai and panel.visible:
			return position + panel.position + Vector2(panel.size.x * 0.5, panel.size.y)
	return Vector2(-1, -1)


func pulse(ai: int, col: Color) -> void:
	## v2.2: army ai's dice are being read: its plate swells and its rim lights
	for p in _plates:
		if int(p["army"]) != ai:
			continue
		var panel: Control = p["panel"]
		var sb: StyleBoxFlat = p["sb"]
		var base: Color = dio.armies[ai]["color"] if dio != null and ai < dio.armies.size() else sb.border_color
		panel.pivot_offset = panel.size * 0.5
		var tw := panel.create_tween().set_parallel(true)
		panel.scale = Vector2(1.22, 1.22)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		sb.border_color = col
		tw.tween_method(func(c: Color): sb.border_color = c, col, base, 0.6)


func screen_of(ai: int) -> Vector2:
	## where army ai stands on screen (probes)
	return wv.cam.unproject_position(dio.centre_of(ai) - Vector3(0, Diorama.FIG * 2.3, 0)) / _px
