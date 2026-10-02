## The board on the land (v2.0): the map's own land in 3D under the board's own UI. The board
## draws exactly what it always has (tokens, arrows, names, ceilings, fates; its clicks too), each
## at its land's point on the ground, through map_board.gd's projector and unprojector. Coming on,
## it is the chart to the pixel (straight down, a nearly flat lens), then the land rises and the
## camera tips back; the further in you zoom, the lower it comes. Every held land's garrison
## stands by its token. A battle tips down out of this same camera and comes back to it.
## In the game: L, or the 3D/2D chip by the zoom buttons (Settings "map_land").
extends Control

const WorldView := preload("res://game/world3d/world_view.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Style := preload("res://game/core/style.gd")
const MapLib := preload("res://engine/map.gd")

const PITCH_FAR := 58.0 ## the camera's angle over the land with the whole map in view...
const PITCH_NEAR := 42.0 ## ...and zoomed all the way in
const FOV := 28.0
const PAINT := 0.6 ## the chart's colours laid over the lit land
const RISE := 1.3 ## seconds to rise from the chart onto the land (and back)
const FIT_CLOSER := 0.9 ## the whole map, tipped back, framed this much closer (it stands shorter)

var board: Control
var land: Node ## land.gd
var on := false ## the board is wanted on the land
var t := 0.0 ## 0 the chart, 1 the land
var garrisons_on := true
var _h := 0.0 ## the camera's target height, eased
var _h_set := false
var _last_rig := {}
var _sig := -1
var _sig_t := 0.0


func attach(p_board: Control, p_land: Node) -> void:
	board = p_board
	land = p_land
	land.set("view", self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(self)
	board.move_child(self, board.terrain.get_index() + 1)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func set_on(v: bool, instant: bool = false) -> void:
	on = v
	if instant:
		t = 1.0 if on and ready_to_show() else 0.0


func ready_to_show() -> bool:
	return land != null and land.prepared and board != null and board.art != null


func active() -> bool:
	## the land is what the board shows (wholly or on the way)
	return t > 0.0005 and ready_to_show()


func settled() -> bool:
	return is_equal_approx(t, 1.0 if on and ready_to_show() else 0.0)


func _process(delta: float) -> void:
	if board == null or land == null:
		return
	var goal := 1.0 if on and ready_to_show() else 0.0
	var moving := not is_equal_approx(t, goal)
	t = move_toward(t, goal, delta / RISE)
	var act := active()
	visible = act
	board.terrain.visible = not act
	board.ships_drawn = not (act and land.prepared and land.scenery.has("ship"))
	board.projector = Callable(self, "_project") if act else Callable()
	board.unprojector = Callable(self, "_unproject") if act else Callable()
	board.view_fix = Callable(self, "_hold") if act else Callable()
	if land.has_method("show_for"):
		land.show_for("board", act)
	_sounds(act)
	if not act:
		if _sig != -1 and land.prepared:
			land.garrisons.clear()
			_sig = -1
		if moving:
			board.overlay.queue_redraw()
		return
	land.fit(size, get_viewport().get_final_transform().get_scale().x)
	if land.driver != "battle":
		_mirror()
		if land.driver != "board":
			_sig_t = 0.0 ## back from a battle: the garrisons as they stand now
		land.driver = "board"
		land.apply_state(state_for(t))
		var r: Dictionary = rig(delta)
		land.wv.rig = r
		land.wv.apply_rig()
		if moving or r != _last_rig:
			board.overlay.queue_redraw()
		_last_rig = r
		_garrison(delta)
		## the battle report: a column marches every live arrow
		if board.flow and t > 0.6:
			land.marches.show_orders(board.orders)
		elif land.marches.count() > 0:
			land.marches.clear()
	queue_redraw()


func _exit_tree() -> void:
	Audio.land_bed_silence() ## the game closed: the land falls quiet with it


func _draw() -> void:
	if active():
		draw_texture_rect(land.texture(), Rect2(Vector2.ZERO, size), false)


# ------------------------------------------------------------------ the camera

func state_for(k: float) -> Dictionary:
	## how the land looks k of the way from the chart (0) onto the land (1)
	var tilt: float = smoothstep(0.15, 1.0, k)
	var up: float = smoothstep(0.0, 0.75, k)
	return {"relief": up, "realism": smoothstep(0.05, 0.8, k), "paint": PAINT, "fog": 0.35 * up,
		"sun": WorldView.SUN_CHART.lerp(WorldView.sun_for(0.0), tilt).normalized()}


func rig(delta: float = 0.0) -> Dictionary:
	## the board's own view (its offset and zoom), as a camera on the land: the same middle and
	## the same scale across the middle, looking down at the pitch for this zoom
	var k: float = smoothstep(0.15, 1.0, t)
	var c: Vector2 = (size * 0.5 - board.offset) / board.zoom
	var span: float = size.y / board.zoom
	var zt: float = clampf((board.zoom / maxf(board.fit, 0.0001) - 1.0) / 2.5, 0.0, 1.0)
	var pitch: float = lerpf(90.0, lerpf(PITCH_FAR, PITCH_NEAR, sqrt(zt)), k)
	var ta: float = tan(deg_to_rad(1.2) * 0.5)
	var tb: float = tan(deg_to_rad(FOV) * 0.5)
	var fov: float = rad_to_deg(atan(exp(lerpf(log(ta), log(tb), k))) * 2.0)
	## the ground under the middle, eased, so a pan over a range doesn't bob the camera
	var h: float = _ground(c, span)
	if not _h_set or delta <= 0.0:
		_h = h
		_h_set = true
	else:
		_h = lerpf(_h, h, 1.0 - exp(-delta * 5.0))
	## tipped back, the map stands shorter on the screen: come in a tenth closer over the whole map
	span *= lerpf(1.0, lerpf(FIT_CLOSER, 1.0, zt), k)
	return {"target": Vector3(c.x, _h * land.wv.relief, c.y), "pitch": pitch, "yaw": 0.0, "fov": fov, "span": span}


func rig_now() -> Dictionary:
	## where a battle closing comes back to
	var r: Dictionary = rig(0.0)
	return r


func _ground(c: Vector2, span: float) -> float:
	var s := span * 0.1
	var sum := 0.0
	for o in [Vector2.ZERO, Vector2(s, 0), Vector2(-s, 0), Vector2(0, s), Vector2(0, -s)]:
		sum += land.height_at(c + o)
	return maxf(sum / 5.0, 0.0)


func _hold(screen_p: Vector2, ground: Vector2) -> void:
	## after a zoom: move the board's view until that ground point is back under the cursor
	## (the camera for the new zoom stands lower and nearer, so the flat sum misses it a little)
	if land.driver == "battle":
		return
	for i in 4:
		land.wv.rig = rig(0.0)
		land.wv.apply_rig()
		var miss: Vector2 = screen_p - land.project(ground)
		if miss.length() < 0.5:
			break
		var k: float = sin(deg_to_rad(float(land.wv.rig["pitch"])))
		board.offset += Vector2(miss.x, miss.y / maxf(k, 0.4))
		board._apply_view()
	land.wv.rig = rig(0.0)
	land.wv.apply_rig()
	_last_rig = {}


func _project(p: Vector2) -> Vector2:
	return land.project(p)


func _unproject(s: Vector2) -> Vector2:
	return land.unproject(s)


func _mirror() -> void:
	## the board's highlights on the ground: the selected and hovered land, the pulse, the view
	var m: ShaderMaterial = board.get("_mat")
	var g: ShaderMaterial = land.wv.gmat
	if m == null or g == null:
		return
	for k in ["hover_id", "select_id", "pulse", "view_mode", "daylight"]:
		var v: Variant = m.get_shader_parameter(k)
		if v != null:
			g.set_shader_parameter(k, v)
	## the day the war has reached lights the land too: a cool morning, a red dusk
	var day: Variant = m.get_shader_parameter("daylight")
	if day is Vector3:
		var d: Vector3 = day
		land.wv.sun.light_color = Color(1.0, 0.94, 0.84) * Color(d.x, d.y, d.z)
		land.wv.wmat.set_shader_parameter("daylight", d)


# ------------------------------------------------------------------ what you hear, close to

func _sounds(act: bool) -> void:
	## come down close and the land is heard: the wind over it, the surf where the middle of the
	## view is near a shore, a ship's timbers where one sails by. Silent over the whole map, in a
	## battle (it has its own), and on the chart.
	var levels := {}
	if act and land.driver == "board" and board.zoom > board.fit * 1.25:
		var close: float = clampf((board.zoom / board.fit - 1.25) / 1.5, 0.0, 1.0) * t
		var c: Vector2 = (size * 0.5 - board.offset) / board.zoom
		var coast: float = absf(land.wv.terrain.coast_at(c))
		var shore: float = 1.0 - smoothstep(30.0, 160.0, coast)
		levels["land_wind"] = close * (0.75 - 0.35 * shore)
		levels["shore_surf"] = close * shore
		var ship := 0.0
		for s in land.scenery.ships:
			var at: Vector3 = (s["node"] as Node3D).position
			ship = maxf(ship, 1.0 - smoothstep(60.0, 260.0, Vector2(at.x, at.z).distance_to(c)))
		levels["ship_creak"] = close * ship * 0.8
	Audio.land_bed(levels)


# ------------------------------------------------------------------ the garrisons

func _garrison(delta: float) -> void:
	## every held land's men by its token, a few toy soldiers in its commander's colour: one for
	## every two, five at most. Kept up to date twice a second: a land that changes hands is
	## repainted, one that grows or shrinks gains or loses men where they stand.
	_sig_t -= delta
	if _sig_t > 0.0:
		return
	_sig_t = 0.5
	var w = board.world
	if w == null or not garrisons_on or t < 0.6:
		if _sig != -1:
			land.garrisons.clear()
			_sig = -1
		return
	var list: Array = []
	var sig := 17
	var capital_lands := {}
	for pid in w.players.keys():
		var cap: String = MapLib.capital_of(w, board.map, str(pid))
		if cap != "":
			capital_lands[cap] = true
	for id in board.art.order:
		## every land has its place in the list (an empty one stands no one), so a land is the
		## same army from one look to the next
		var ts = w.get_territory(id)
		var n := 0
		if ts != null and ts.owner != "" and ts.armies + ts.garrison > 0:
			n = clampi(int(ceil(float(ts.armies + ts.garrison) / 2.0)), 1, 5)
		var a: Vector2 = board.art.anchors[id]
		var at: Vector2 = a + garrison_offset(id)
		var pid: String = ts.owner if ts != null else ""
		list.append({"pid": pid, "color": Style.seat_color(pid), "n": n, "land": id,
			"groups": [{"at": at, "dir": Vector2(0, 1), "share": n, "dist": 30.0, "colours": capital_lands.has(id)}]})
		sig = hash([sig, id, pid, n, capital_lands.has(id)])
	## the capitals: a palace where each commander keeps one (the one being chosen, too)
	var caps := {}
	var colors := {}
	for pid in w.players.keys():
		var c: String = MapLib.capital_of(w, board.map, str(pid))
		if board.capital_override.has(pid):
			c = str(board.capital_override[pid])
		if c != "":
			caps[c] = str(pid)
			colors[str(pid)] = Style.seat_color(str(pid))
	## the dug in (two deep or more): earthworks round their garrison
	var dug := {}
	for id in board.art.order:
		var ts2 = w.get_territory(id)
		if ts2 != null and ts2.owner != "" and ts2.garrison >= 2:
			dug[id] = (board.art.anchors[id] as Vector2) + garrison_offset(id) - Vector2(0, Diorama.FIG * 2.4 * 0.5)
	sig = hash([sig, caps, dug.keys()])
	if sig == _sig:
		return
	_sig = sig
	land.garrisons.regarrison(list)
	land.scenery.set_capitals(caps, colors)
	land.scenery.set_dug(dug)


func garrison_offset(id: String) -> Vector2:
	## beside the token, to the side its name plate isn't
	var r: float = float(board.token_radius()) / maxf(board.zoom, 0.0001)
	return Vector2(maxf(r * 1.6, Diorama.FIG * 2.6), Diorama.FIG * 0.6)
