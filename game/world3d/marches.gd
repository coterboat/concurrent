## The columns on the march (v2.0): while the battle report plays on the board on the land, every
## live arrow has its column of tin soldiers marching it, down the road from its land's heart over
## the border to the next (or rowed over a sea lane in a longboat), again and again, as the chart's
## chevrons run along its arrows. One figure for every three men, four at most, in their
## commander's colours; they rise out of the land they leave and sink into the one they reach.
extends Node3D

const FIG := 18.0
const SPEED := 46.0 ## map px a second

var wv: Node3D ## world_view.gd
var kit: Node3D ## a diorama.gd whose models these figures wear
var size_mult := 2.4
var columns := {} ## key -> {path: PackedVector2Array, lens, total, figs: [MeshInstance3D], boat, t, color, n, sea: [i0, i1]}
var _clock := 0.0


func show_orders(orders: Array) -> void:
	## the arrows that are live now: [{from, to, strength, owner}]; a column for each, the rest go
	var want := {}
	for o in orders:
		if float(o.get("alpha", 1.0)) < 0.95:
			continue
		var key := "%s>%s|%s" % [o["from"], o["to"], o.get("owner", "")]
		want[key] = o
	for key in columns.keys():
		if not want.has(key):
			_drop(key)
	for key in want.keys():
		var o: Dictionary = want[key]
		var n: int = clampi(int(ceil(float(int(o.get("strength", 1))) / 3.0)), 1, 4)
		if columns.has(key) and int(columns[key]["n"]) == n:
			continue
		if columns.has(key):
			_drop(key)
		_raise(key, str(o["from"]), str(o["to"]), str(o.get("owner", "")), n)


func clear() -> void:
	for key in columns.keys():
		_drop(key)


func count() -> int:
	return columns.size()


func _drop(key: String) -> void:
	var c: Dictionary = columns[key]
	for f in c["figs"]:
		(f as Node3D).queue_free()
	if c["boat"] != null:
		(c["boat"] as Node3D).queue_free()
	columns.erase(key)


func _raise(key: String, from: String, to: String, owner: String, n: int) -> void:
	var art = wv.art
	if not art.anchors.has(from) or not art.anchors.has(to):
		return
	var a: Vector2 = art.anchors[from]
	var b: Vector2 = art.anchors[to]
	var pts := PackedVector2Array()
	var sea := Vector2i(-1, -1)
	var x: Variant = wv.terrain.crossing(from, to)
	if x != null:
		pts = PackedVector2Array([a, x, b])
	else:
		var lane: Variant = null
		for l in art.lanes:
			if l["a"] == from and l["b"] == to:
				lane = [l["pa"], l["pb"]]
			elif l["b"] == from and l["a"] == to:
				lane = [l["pb"], l["pa"]]
		if lane == null:
			pts = PackedVector2Array([a, b])
		else:
			pts = PackedVector2Array([a, lane[0], lane[1], b])
			sea = Vector2i(1, 2)
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i - 1].distance_to(pts[i]))
	var col: Color = load("res://game/core/style.gd").seat_color(owner)
	var figs: Array = []
	for i in n:
		figs.append(_fig(col))
	var boat: Node3D = null
	if sea.x >= 0 and kit._meshes.has("boat"):
		boat = _piece("boat", Color.WHITE, 3.2)
	columns[key] = {"path": pts, "lens": lens, "total": lens[lens.size() - 1], "figs": figs, "boat": boat,
		"t": randf() * 2.0, "n": n, "sea": sea}


func _fig(col: Color) -> MeshInstance3D:
	var kind: String = "inf_march" if kit._meshes.has("inf_march") else "inf"
	return _piece(kind, col, 1.0)


func _piece(kind: String, col: Color, h_men: float) -> MeshInstance3D:
	var m: Dictionary = kit._meshes[kind]
	var mi := MeshInstance3D.new()
	mi.mesh = m["mesh"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/world3d/tin.gdshader")
	mat.set_shader_parameter("albedo_tex", m["tex"])
	var hue: float = m["hue"]
	mat.set_shader_parameter("team", col)
	mat.set_shader_parameter("key_hue", maxf(hue, 0.0))
	mat.set_shader_parameter("repaint", hue >= 0.0 and not (hue == 0.0 and (col.h < 0.06 or col.h > 0.96) and col.s > 0.6))
	mi.material_override = mat
	var aabb: AABB = m["aabb"]
	var size: float = aabb.size.z if kind == "boat" else aabb.size.y
	var sc: float = FIG * size_mult * h_men / maxf(size, 0.0001)
	mi.set_meta("sc", sc)
	mi.set_meta("foot", -aabb.position.y * sc)
	mi.set_meta("yaw", float(m["yaw"]))
	add_child(mi)
	return mi


func _at(c: Dictionary, d: float) -> Array:
	## [where along the path, which way it goes, on the sea]
	var pts: PackedVector2Array = c["path"]
	var lens: PackedFloat32Array = c["lens"]
	d = clampf(d, 0.0, float(c["total"]))
	for i in range(1, pts.size()):
		if d <= lens[i] or i == pts.size() - 1:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			var k: float = clampf((d - lens[i - 1]) / seg, 0.0, 1.0)
			var sea: Vector2i = c["sea"]
			return [pts[i - 1].lerp(pts[i], k), (pts[i] - pts[i - 1]).normalized(), sea.x >= 0 and i - 1 == sea.x]
	return [pts[pts.size() - 1], Vector2(0, 1), false]


func _process(delta: float) -> void:
	_clock += delta
	if columns.is_empty() or not is_visible_in_tree():
		return
	for c in columns.values():
		var total: float = c["total"]
		var gap: float = FIG * size_mult * 1.15
		var run: float = total + gap * float(c["n"]) + FIG * 4.0
		c["t"] = float(c["t"]) + delta
		var head: float = fmod(float(c["t"]) * SPEED, run)
		var boat_set := false
		for i in (c["figs"] as Array).size():
			var mi: MeshInstance3D = c["figs"][i]
			var d: float = head - float(i) * gap
			var at: Array = _at(c, d)
			var p: Vector2 = at[0]
			var dir: Vector2 = at[1]
			var on_sea: bool = at[2]
			## they rise out of the land they leave and sink into the one they reach
			var grow: float = smoothstep(0.0, FIG * 1.5, d) * (1.0 - smoothstep(total - FIG * 1.5, total, d))
			if on_sea:
				grow = 0.0
				if not boat_set and c["boat"] != null:
					_place_boat(c["boat"], p, dir)
					boat_set = true
			var ph: float = _clock * 7.5 + float(i) * 1.3
			var hop: float = absf(sin(ph)) * FIG * size_mult * 0.12
			var sc: float = float(mi.get_meta("sc")) * maxf(grow, 0.001)
			mi.visible = grow > 0.01
			var yaw: float = atan2(dir.x, dir.y) + float(mi.get_meta("yaw"))
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, sin(ph) * 0.1)
			mi.transform = Transform3D(basis.scaled(Vector3.ONE * sc), wv.ground_at(p) + Vector3(0.0, float(mi.get_meta("foot")) * maxf(grow, 0.001) + hop, 0.0))
		if c["boat"] != null:
			(c["boat"] as Node3D).visible = boat_set


func _place_boat(boat: MeshInstance3D, p: Vector2, dir: Vector2) -> void:
	var yaw: float = atan2(dir.x, dir.y) + float(boat.get_meta("yaw"))
	var bob: float = sin(_clock * 2.2) * 0.6
	boat.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(boat.get_meta("sc"))), Vector3(p.x, float(boat.get_meta("foot")) + bob, p.y))
