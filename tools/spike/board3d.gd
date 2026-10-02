## The case for all-3D, as something to use. The real board (its tokens, arrows, names,
## ceilings, fate marks and clicks: all still its own crisp 2D, not one line of it redrawn) over
## the map's land in 3D. The UI stays exactly as good, because it is the same UI; the land
## underneath comes alive.
##
##   $G --path . res://tools/spike/board3d.tscn -- map=known24
##   1 the chart (today's board)  2 the land under it  3 tilted  4 living (garrisons on their lands)
##   drag to pan, wheel to zoom (the board's own), N the next map
extends Node

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Board := preload("res://game/board/map_board.gd")
const Style := preload("res://game/core/style.gd")
const Terrain := preload("res://game/world3d/terrain.gd")
const WorldView := preload("res://game/world3d/world_view.gd")
const Diorama := preload("res://game/world3d/diorama.gd")

const MAPS := ["known24", "world30", "isles24", "ring26", "marches18", "knife7"]
const MODES := [
	{"name": "1  The chart: today's board", "relief": 0.0, "realism": 0.0, "paint": 0.0, "tilt": 0.0, "garrisons": false},
	{"name": "2  The land under the chart", "relief": 1.0, "realism": 1.0, "paint": 0.6, "tilt": 0.0, "garrisons": false},
	{"name": "3  Tilted", "relief": 1.0, "realism": 1.0, "paint": 0.5, "tilt": 1.0, "garrisons": false},
	{"name": "4  Living: every land's garrison on its ground", "relief": 1.0, "realism": 1.0, "paint": 0.45, "tilt": 1.0, "garrisons": true},
]

var map_id := "known24"
var map: Types.MapDef
var world: Types.World
var board: Control
var wv: Node3D
var dio: Node3D
var layer: CanvasLayer
var hud: Label
var mode := 0
var cur := {"relief": 0.0, "realism": 0.0, "paint": 0.0, "tilt": 0.0}
var _built := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			map_id = a.trim_prefix("map=")
		elif a.begins_with("mode="):
			mode = int(a.trim_prefix("mode=")) - 1
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null:
			settings.set("persist", false)
		build.call_deferred()


func vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func build() -> void:
	for n in [wv, layer]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_built = false
	map = Types.MapDef.from_file("res://maps/%s.json" % map_id)
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}, {"id": "gold", "name": "D"}]
	if map_id == "knife7":
		seats = seats.slice(0, 2)
	world = Setup.deal(map, seats, 7)
	for id in world.territories.keys():
		var ts = world.territories[id]
		if ts.owner != "":
			ts.armies = 1 + (hash(id) % 9)
			if hash(id) % 3 == 0:
				ts.garrison = 2
	layer = CanvasLayer.new()
	add_child(layer)
	board = Board.new()
	board.size = vp_size()
	layer.add_child(board)
	board.load_map(map)
	board.world = world
	board.viewer = "red"
	board.show_ceiling = true
	var mine := MapLib.player_territory_ids(world, "red")
	board.selected = mine[0]
	for n in MapLib.neighbors(map, mine[0]):
		board.targets[n] = true
	board.placements[mine[0]] = 2
	var t: String = MapLib.neighbors(map, mine[0])[0]
	board.orders = [{"from": mine[0], "to": t, "strength": 5, "owner": "red", "kind": "attack"}]
	var bl := MapLib.player_territory_ids(world, "blue")
	board.ghosts = [{"from": bl[0], "to": MapLib.neighbors(map, bl[0])[0], "strength": 3, "owner": "blue"}]
	board.refresh()
	wv = WorldView.new()
	add_child(wv)
	move_child(wv, 0)
	wv.setup(board.art, map, board.get("_state_tex"))
	dio = Diorama.new()
	dio.wv = wv
	dio.extras = false
	dio.quiet = true
	dio.size_mult = 2.6
	wv.add_child(dio)
	hud = Label.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_font_override("font", Style.font("title"))
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	hud.add_theme_constant_override("outline_size", 8)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var hl := CanvasLayer.new()
	hl.layer = 3
	layer.add_child(hl)
	hl.add_child(hud)
	_built = true
	var m: int = mode
	mode = -1
	set_mode(m, true)


func set_mode(m: int, snap: bool = false) -> void:
	m = clampi(m, 0, MODES.size() - 1)
	var was: int = mode
	mode = m
	var md: Dictionary = MODES[m]
	hud.text = str(md["name"]) + "     (1-4 · drag · wheel · N: next map)"
	var on3d: bool = m > 0
	board.terrain.visible = not on3d
	board.projector = Callable(self, "_project") if on3d else Callable()
	board.unprojector = Callable(self, "_unproject") if on3d else Callable()
	if snap:
		for k in cur.keys():
			cur[k] = float(md[k])
	if bool(md["garrisons"]) and (was < 0 or not bool(MODES[maxi(was, 0)]["garrisons"])):
		_garrison()
	elif not bool(md["garrisons"]):
		dio.clear()
	_apply()


func _garrison() -> void:
	## every held land's garrison, a few tin soldiers by its token, in its commander's colour
	var list: Array = []
	for id in world.territories.keys():
		var ts = world.territories[id]
		if ts.owner == "":
			continue
		var a: Vector2 = board.art.anchors[id]
		var at: Vector2 = a + Vector2(Diorama.FIG * 3.6, Diorama.FIG * 1.4)
		var n: int = clampi(int(ceil(float(ts.armies) / 2.0)), 1, 5)
		list.append({"pid": ts.owner, "color": Style.seat_color(ts.owner), "n": n, "groups": [{"at": at, "dir": Vector2(0, 1), "share": n, "dist": 30.0}]})
	dio.place(list)


func _process(delta: float) -> void:
	if not _built:
		return
	var md: Dictionary = MODES[mode]
	var moving := false
	for k in cur.keys():
		var goal: float = float(md[k])
		if absf(float(cur[k]) - goal) > 0.001:
			cur[k] = move_toward(float(cur[k]), goal, delta / 1.6)
			moving = true
	_apply()
	if moving or mode > 0:
		board.overlay.queue_redraw()


func _apply() -> void:
	wv.relief = smoothstep(0.0, 1.0, cur["relief"])
	wv.realism = smoothstep(0.0, 1.0, cur["realism"])
	wv.paint = cur["paint"]
	var t: float = smoothstep(0.0, 1.0, cur["tilt"])
	var r: Dictionary = wv.rig_from_board(board, vp_size())
	var tg: Vector3 = r["target"]
	r["target"] = Vector3(tg.x, wv.terrain.height_at(Vector2(tg.x, tg.z)) * wv.relief, tg.z)
	r["pitch"] = lerpf(90.0, 50.0, t)
	var ta: float = tan(deg_to_rad(1.2) * 0.5)
	var tb: float = tan(deg_to_rad(30.0) * 0.5)
	r["fov"] = rad_to_deg(atan(exp(lerpf(log(ta), log(tb), t))) * 2.0)
	wv.fog_k = 0.35 * wv.relief
	wv.aim_sun(WorldView.SUN_CHART.lerp(WorldView.sun_for(0.0), t).normalized())
	wv.rig = r
	wv.apply_rig()


func _project(p: Vector2) -> Vector2:
	var v := Vector3(p.x, wv.terrain.height_at(p) * wv.relief, p.y)
	if wv.cam.is_position_behind(v):
		return Vector2(-99999, -99999)
	return wv.cam.unproject_position(v)


func _unproject(s: Vector2) -> Vector2:
	## a ray from the eye through the screen, onto the ground (refined over the hills)
	var o: Vector3 = wv.cam.project_ray_origin(s)
	var d: Vector3 = wv.cam.project_ray_normal(s)
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	var hgt := 0.0
	var q := Vector3.ZERO
	for i in 5:
		q = o + d * ((hgt - o.y) / d.y)
		hgt = wv.terrain.height_at(Vector2(q.x, q.z)) * wv.relief
	return Vector2(q.x, q.z)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.keycode >= KEY_1 and e.keycode <= KEY_4:
		set_mode(e.keycode - KEY_1)
	elif e.keycode == KEY_N:
		map_id = MAPS[(MAPS.find(map_id) + 1) % MAPS.size()]
		build()
