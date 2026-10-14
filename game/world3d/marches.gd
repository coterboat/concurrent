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
## v2.0.2: a border clash on the board (MapBoard.clash_clock: {a, b, u, won_from, since_won}). Its
## two columns charge to the middle of the road and stand there face to face; at the break the
## loser's men fall where they stand and the winner's march on through, those it lost falling out.
var clash := {}
const CHARGE := 0.6 ## seconds to the middle of the road


func show_orders(orders: Array) -> void:
	## the arrows that are live now: [{from, to, strength, owner}]; a column for each, the rest go
	var want := {}
	for o in orders:
		if float(o.get("alpha", 1.0)) < 0.95:
			continue
		var key := "%s>%s|%s" % [o["from"], o["to"], o.get("owner", "")]
		want[key] = o
	for key in columns.keys():
		if not want.has(key) and not (role(columns[key]) == "lost" and float(clash["since_won"]) < 1.4):
			_drop(key) ## (a beaten column stays to fall)
	for key in want.keys():
		var o: Dictionary = want[key]
		var n: int = clampi(int(ceil(float(int(o.get("strength", 1))) / 3.0)), 1, 4)
		if columns.has(key):
			var c: Dictionary = columns[key]
			c["keep"] = n ## a column cut down keeps marching: the men it lost fall out of it
			if role(c) == "":
				_muster(c, n)
				_train(c, int(o.get("strength", 1)))
			continue
		_raise(key, str(o["from"]), str(o["to"]), str(o.get("owner", "")), n)
		if columns.has(key):
			_train(columns[key], int(o.get("strength", 1)))


func _train(c: Dictionary, men: int) -> void:
	## v2.0.2: a big column brings its train along, as well as its men: a horseman riding at its
	## head from 10 men, a gun trundling at its tail from 16 (the garrisons' thresholds)
	for spec in [["horse", "cav", 1.3, men >= 10], ["gun", "gun", 1.35, men >= 16]]:
		var have: Node3D = c.get(spec[0], null)
		if bool(spec[3]) and have == null and kit._meshes.has(spec[1]):
			c[spec[0]] = _piece(str(spec[1]), c["color"], float(spec[2]))
		elif not bool(spec[3]) and have != null:
			have.queue_free()
			c[spec[0]] = null


func role(c: Dictionary) -> String:
	## a column's part in the clash on the board: "" (none), "charge", "won" or "lost"
	if clash.is_empty():
		return ""
	var a: String = str(clash["a"])
	var b: String = str(clash["b"])
	if not ((c["from"] == a and c["to"] == b) or (c["from"] == b and c["to"] == a)):
		return ""
	if float(clash["since_won"]) < 0.0:
		return "charge"
	return "won" if c["from"] == str(clash["won_from"]) else "lost"


func _muster(c: Dictionary, n: int) -> void:
	## the column's figures to n, without starting it over
	var figs: Array = c["figs"]
	while figs.size() > n:
		(figs.pop_back() as Node3D).queue_free()
	while figs.size() < n:
		figs.append(_fig(c["color"]))
	c["n"] = n


func clear() -> void:
	for key in columns.keys():
		_drop(key)


func count() -> int:
	return columns.size()


func _drop(key: String) -> void:
	var c: Dictionary = columns[key]
	for f in c["figs"]:
		(f as Node3D).queue_free()
	for k in ["horse", "gun"]:
		if c.get(k, null) != null:
			(c[k] as Node3D).queue_free()
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
		"t": randf() * 2.0, "n": n, "sea": sea, "from": from, "to": to, "color": col}


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
	var size: float = aabb.size.z if kind == "boat" else (aabb.size.x if kind == "gun" else aabb.size.y)
	var sc: float = FIG * size_mult * h_men / maxf(size, 0.0001)
	mi.set_meta("sc", sc)
	mi.set_meta("foot", -aabb.position.y * sc)
	mi.set_meta("yaw", float(m["yaw"]) + (PI if kind == "gun" else 0.0)) ## a gun on the march is towed, its muzzle trailing
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
		var run: float = total + gap * (float(c["n"]) + 1.6) + FIG * 4.0
		c["t"] = float(c["t"]) + delta
		var head: float = fmod(float(c["t"]) * SPEED, run)
		## v2.0.2: in a clash, to the middle of the road; then through it, or down
		var part: String = role(c)
		var hold: float = maxf(total * 0.5 - FIG * size_mult * 0.45, 0.0)
		var falls := 99 ## figures from this one on fall
		var fall_t := 0.0
		match part:
			"charge":
				head = hold * ease(minf(float(clash["u"]) / CHARGE, 1.0), 0.6)
				c["held"] = head
			"won":
				head = float(c.get("held", hold)) + float(clash["since_won"]) * SPEED * 1.6
				c["pushed"] = head
				falls = int(c.get("keep", c["n"]))
				fall_t = float(clash["since_won"])
			"lost":
				head = float(c.get("held", hold)) - minf(float(clash["since_won"]), 0.4) * SPEED * 0.6
				falls = 0
				fall_t = float(clash["since_won"])
			_:
				if c.has("pushed"):
					## the clash is over: march on from where the winners got to
					c["t"] = float(c["pushed"]) / SPEED
					head = fmod(float(c["pushed"]), run)
					c.erase("pushed")
					_muster(c, int(c.get("keep", c["n"])))
				c.erase("held")
		var boat_set := false
		var nf: int = (c["figs"] as Array).size()
		for i in nf:
			var mi: MeshInstance3D = c["figs"][i]
			var d: float = head - float(i) * gap
			var topple := 0.0
			var sink := 0.0
			if i >= falls:
				## struck down: over backwards, then into the ground
				topple = smoothstep(0.0, 0.35, fall_t - 0.08 * float(i - falls))
				sink = smoothstep(0.45, 0.85, fall_t)
			if _put(c, mi, d, _clock * 7.5 + float(i) * 1.3, 1.0, topple, sink) and not boat_set and c["boat"] != null:
				var at: Array = _at(c, d)
				_place_boat(c["boat"], at[0], at[1])
				boat_set = true
		## the train: the horseman rides ahead of the men (behind them in a clash, where the men
		## meet the enemy), the gun rolls behind them
		var down: bool = falls == 0
		var horse_d: float = head + gap * 1.2 if part == "" else head - gap * (float(nf) + 0.3)
		var gun_d: float = head - gap * (float(nf) + (0.4 if part == "" else 1.5))
		if c.get("horse", null) != null:
			_put(c, c["horse"], horse_d, _clock * 5.0, 0.6, smoothstep(0.0, 0.35, fall_t) if down else 0.0, smoothstep(0.45, 0.85, fall_t) if down else 0.0)
		if c.get("gun", null) != null:
			_put(c, c["gun"], gun_d, _clock * 3.0, 0.2, smoothstep(0.1, 0.45, fall_t) if down else 0.0, smoothstep(0.45, 0.85, fall_t) if down else 0.0)
		if c["boat"] != null:
			(c["boat"] as Node3D).visible = boat_set


func _put(c: Dictionary, mi: MeshInstance3D, d: float, ph: float, bounce: float, topple: float, sink: float) -> bool:
	## one piece of a column, d along its road: it rises out of the land it leaves and sinks into
	## the one it reaches, hops as it goes, and (struck down) topples backwards and sinks. True
	## when it is on the sea (in the boat).
	var total: float = c["total"]
	var at: Array = _at(c, d)
	var p: Vector2 = at[0]
	var dir: Vector2 = at[1]
	var grow: float = smoothstep(0.0, FIG * 1.5, d) * (1.0 - smoothstep(total - FIG * 1.5, total, d)) * (1.0 - sink)
	if at[2]:
		grow = 0.0
	var hop: float = absf(sin(ph)) * FIG * size_mult * 0.12 * bounce * (1.0 - topple)
	mi.visible = grow > 0.01
	var yaw: float = atan2(dir.x, dir.y) + float(mi.get_meta("yaw"))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, sin(ph) * 0.1 * bounce * (1.0 - topple))
	if topple > 0.0:
		var fwd := Vector3(dir.x, 0.0, dir.y)
		basis = Basis(fwd.cross(Vector3.UP).normalized(), topple * 1.45) * basis
	var sc: float = float(mi.get_meta("sc")) * maxf(grow, 0.001)
	mi.transform = Transform3D(basis.scaled(Vector3.ONE * sc), wv.ground_at(p) + Vector3(0.0, float(mi.get_meta("foot")) * maxf(grow, 0.001) + hop, 0.0))
	return bool(at[2])


func _place_boat(boat: MeshInstance3D, p: Vector2, dir: Vector2) -> void:
	var yaw: float = atan2(dir.x, dir.y) + float(boat.get_meta("yaw"))
	var bob: float = sin(_clock * 2.2) * 0.6
	boat.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(boat.get_meta("sc"))), Vector3(p.x, float(boat.get_meta("foot")) + bob, p.y))
