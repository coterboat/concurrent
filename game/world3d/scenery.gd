## The land's buildings (v2.0): a village in every land, in its region's terrain; a landmark where
## a land's name calls for one (a mill, a gate, a watch, a haven...); and the rules as scenery: a
## star fort on a fort land, a blockhouse on a pass, a quay on a port's shore, a palace where a
## commander keeps a capital (the palace takes the village's place). Bridges carry the roads over
## the lowland rivers, ships ride the chart's sea, and a frigate plies every sea lane.
## Wargame terrain pieces from Ludo (tools/ludo/v20_content.py), set beside each land's stage on
## the side away from its borders, so its battles are fought in front of them, never on them.
## plan() is static and runs with the terrain (off the main thread), so the woods can keep clear.
extends Node3D

const DIR := "res://assets/models/land/"
## each piece's size on the land, in map pixels: its height ("h") or its widest side ("w")
const SIZE := {
	"village_grass": ["w", 96.0], "village_forest": ["w", 92.0], "village_moor": ["w", 84.0], "village_coast": ["w", 92.0],
	"village_desert": ["w", 96.0], "village_snow": ["w", 92.0], "village_mountain": ["w", 80.0], "village_ash": ["w", 92.0],
	"windmill": ["h", 92.0], "watchtower": ["h", 82.0], "lighthouse": ["h", 104.0], "gatehouse": ["w", 104.0],
	"keep": ["h", 92.0], "palace": ["w", 140.0], "church": ["h", 96.0], "farm": ["w", 108.0], "harbour": ["w", 104.0],
	"bridge": ["w", 46.0], "starfort": ["w", 132.0], "redoubt": ["w", 84.0], "blockhouse": ["w", 70.0], "camp": ["w", 88.0],
	"oasis": ["w", 96.0], "stones": ["w", 70.0], "quarry": ["w", 96.0], "ship": ["w", 120.0], "frigate": ["w", 92.0],
}
## a land's name, read for its landmark (the first word found wins)
const BY_NAME := [["mill", "windmill"], ["quarry", "quarry"], ["lantern", "lighthouse"], ["light", "lighthouse"],
	["beacon", "watchtower"], ["watch", "watchtower"], ["gate", "gatehouse"], ["keep", "keep"], ["hold", "keep"],
	["helm", "keep"], ["throne", "keep"], ["court", "keep"], ["crown", "keep"], ["spire", "church"], ["moot", "church"],
	["oasis", "oasis"], ["mirage", "oasis"], ["well", "oasis"], ["stone", "stones"], ["cairn", "stones"], ["tor", "stones"],
	["crag", "stones"], ["field", "farm"], ["meadow", "farm"], ["fold", "farm"], ["camp", "camp"]]
const PORT_WORDS := ["harbor", "harbour", "haven", "port", "quay", "dock", "bay", "strand"]
const VILLAGES := ["grass", "forest", "moor", "coast", "desert", "snow", "mountain", "ash"]
const LENGTHWISE := ["bridge", "harbour", "ship", "frigate"] ## laid along +X, whichever way they were modelled
const TURN := {} ## a model's own half-turn where it came the wrong way round (radians)

var wv: Node3D ## world_view.gd
var pieces: Array = [] ## {kind, land, node, at, role} role: village | landmark | port | bridge | ship | lane
var ships: Array = [] ## {node, a, b, t, speed, bob, lane}
var _scenes := {} ## kind -> [PackedScene...] (its variants)
var _palaces := {} ## land -> the palace standing in for its village
var _plan: Array = [] ## where everything goes (plan()), built or not
var _clock := 0.0


# ------------------------------------------------------------------ where everything goes (static)

static func plan(art: RefCounted, map: RefCounted, t: RefCounted) -> Array:
	## Every piece's place on this map: [{kind, land, at, yaw, foot, role}]. Deterministic (seeded by
	## the map), so a map's villages are always where they were.
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(art.id)) + 913
	for id in art.order:
		var a: Vector2 = art.anchors[id]
		var depth: float = float(art.depth.get(id, 60.0))
		var td = map.get_territory(id)
		var region: String = td.region if td != null else ""
		var terr: String = str(map.region_terrain.get(region, "grass"))
		var scale: float = clampf(depth / 95.0, 0.72, 1.15)
		## the ways in: every border crossing and every beach a lane lands on (battles come from there)
		var avoid: Array = [Vector2(0, 1), Vector2(1, 0.25).normalized()] ## the name plate below, the garrison to the right
		for k in t.crossings.keys():
			var pr: PackedStringArray = str(k).split("|")
			if pr[0] == id or pr[1] == id:
				avoid.append(((t.crossings[k] as Vector2) - a).normalized())
		for l in art.lanes:
			if l["a"] == id:
				avoid.append(((l["pa"] as Vector2) - a).normalized())
			elif l["b"] == id:
				avoid.append(((l["pb"] as Vector2) - a).normalized())
		var used: Array = [] ## [at, radius]
		var village: String = "village_" + (terr if terr in VILLAGES else "grass")
		var vfoot: float = float(SIZE[village][1]) * scale
		var v: Variant = _fit(art, t, id, a, depth, vfoot, avoid, used, rng)
		if v != null:
			out.append({"kind": village, "land": id, "at": v[0], "yaw": rng.randf_range(-0.4, 0.4), "foot": v[1], "role": "village"})
			used.append([v[0], float(v[1]) * 0.55])
		## the landmark: the rules first (a fort, a pass), then the name
		var lm := ""
		if td != null and td.has_trait("fort"):
			lm = "starfort"
		elif td != null and td.has_trait("pass"):
			lm = "blockhouse"
		else:
			for pair in BY_NAME:
				if id.contains(pair[0]):
					lm = pair[1]
					break
			if lm == "lighthouse" and t.coast_at(a) > 30.0:
				lm = "watchtower" ## a light far inland is a beacon tower
		if lm != "":
			var lfoot: float = _foot(lm) * scale
			var l2: Variant = _fit(art, t, id, a, depth, lfoot, avoid, used, rng)
			if l2 != null:
				out.append({"kind": lm, "land": id, "at": l2[0], "yaw": rng.randf_range(-0.35, 0.35), "foot": l2[1], "role": "landmark"})
				used.append([l2[0], float(l2[1]) * 0.55])
		## a port's quay on its shore (or a land named for its harbour)
		var portish: bool = td != null and td.has_trait("port")
		for w in PORT_WORDS:
			if id.contains(w):
				portish = true
		if portish:
			var q: Variant = _shore(art, t, id, a, depth, used)
			if q != null:
				var qfoot: float = float(SIZE["harbour"][1]) * scale
				out.append({"kind": "harbour", "land": id, "at": q[0], "yaw": q[1], "foot": qfoot, "role": "port"})
				used.append([q[0], qfoot * 0.5])
	## bridges: where a road crosses a lowland river (the border between two lowland lands)
	for k in t.crossings.keys():
		var x: Vector2 = t.crossings[k]
		var pr2: PackedStringArray = str(k).split("|")
		if t.height_at(x) > 50.0 or t.coast_at(x) < 14.0:
			continue
		var along: Vector2 = ((art.anchors[pr2[1]] as Vector2) - (art.anchors[pr2[0]] as Vector2)).normalized()
		out.append({"kind": "bridge", "land": pr2[0], "at": x, "yaw": -along.angle(), "foot": float(SIZE["bridge"][1]),
			"role": "bridge", "flat": true})
	## the chart's ships, and a frigate on every sea lane
	for o in art.ornaments:
		if str(o["kind"]) == "ship":
			out.append({"kind": "ship", "land": "", "at": o["pos"], "yaw": PI if bool(o.get("flip", false)) else 0.0,
				"foot": clampf(float(o["r"]) * 1.6, 70.0, 150.0), "role": "ship"})
	for l in art.lanes:
		var pa: Vector2 = l["pa"]
		var pb: Vector2 = l["pb"]
		if pa.distance_to(pb) < 60.0:
			continue
		out.append({"kind": "frigate", "land": "", "at": pa.lerp(pb, 0.5), "a": pa, "b": pb, "yaw": 0.0,
			"foot": float(SIZE["frigate"][1]) * 0.8, "role": "lane"})
	return out


static func fields(plan: Array, t: RefCounted) -> Image:
	## The ploughed fields round the lowland villages: two or three strips beside each, turned
	## every which way, off the roads and the shore. A mask, one byte a cell, for the ground shader.
	var img := Image.create(t.w, t.h, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	for s in plan:
		if s["role"] != "village" or not (str(s["kind"]) in ["village_grass", "village_coast", "village_moor", "village_desert"]):
			continue
		var at: Vector2 = s["at"]
		var foot: float = float(s["foot"])
		for k in rng.randi_range(2, 3):
			var ang: float = rng.randf() * TAU
			var c: Vector2 = at + Vector2(cos(ang), sin(ang)) * foot * rng.randf_range(0.75, 1.05)
			var half := Vector2(rng.randf_range(0.28, 0.45), rng.randf_range(0.16, 0.26)) * foot
			var turn: float = rng.randf() * PI
			var ax := Vector2(cos(turn), sin(turn))
			var ay := Vector2(-ax.y, ax.x)
			var r: float = half.length()
			for cy in range(int((c.y - r) / t.cell.y), int((c.y + r) / t.cell.y) + 1):
				for cx in range(int((c.x - r) / t.cell.x), int((c.x + r) / t.cell.x) + 1):
					if cx < 0 or cy < 0 or cx >= t.w or cy >= t.h:
						continue
					var p := Vector2((cx + 0.5) * t.cell.x, (cy + 0.5) * t.cell.y)
					var d: Vector2 = p - c
					var u: float = absf(d.dot(ax)) / half.x
					var v: float = absf(d.dot(ay)) / half.y
					if u > 1.0 or v > 1.0 or t.coast_at(p) < 6.0 or t.road_at(p) < 7.0:
						continue
					var edge: float = clampf(minf(1.0 - u, 1.0 - v) * 6.0, 0.0, 1.0)
					img.set_pixel(cx, cy, Color(maxf(img.get_pixel(cx, cy).r, edge), 0, 0))
	return img


static func _foot(kind: String) -> float:
	var s: Array = SIZE.get(kind, ["w", 90.0])
	return float(s[1]) * (0.8 if s[0] == "h" else 1.0)


static func _fit(art: RefCounted, t: RefCounted, id: String, a: Vector2, depth: float, foot: float, avoid: Array, used: Array, rng: RandomNumberGenerator) -> Variant:
	## [where, how wide]: the piece at its size if it fits, smaller where the land is tight
	for k in [1.0, 0.82, 0.66]:
		var p: Variant = _spot(art, t, id, a, depth, foot * k, avoid, used, rng)
		if p != null:
			return [p, foot * k]
	return null


static func _spot(art: RefCounted, t: RefCounted, id: String, a: Vector2, depth: float, foot: float, avoid: Array, used: Array, rng: RandomNumberGenerator) -> Variant:
	## the best place beside the land's stage for a piece this wide: on its own land, on dry
	## level ground, off the roads, clear of what's already there, facing away from the ways in
	var stage: float = depth * 0.55
	var best: Variant = null
	var best_s := -1.0e9
	var spin: float = rng.randf() * TAU
	for ring in [1.0, 1.3, 1.65, 2.0]:
		## at the stage's edge (its far side, away from the ways in, is never fought over)
		var rad: float = stage * 0.85 + foot * 0.45 + 4.0 + (ring - 1.0) * foot * 0.9
		for k in 28:
			var ang: float = spin + float(k) * TAU / 28.0
			var d := Vector2(cos(ang), sin(ang))
			var p: Vector2 = a + d * rad
			var ok := true
			var lo := 1.0e9
			var hi := -1.0e9
			for j in 9:
				var q: Vector2 = p if j == 8 else p + Vector2(cos(float(j) * TAU / 8.0), sin(float(j) * TAU / 8.0)) * foot * 0.42
				if art.territory_at(q) != id or t.coast_at(q) < 3.0:
					ok = false
					break
				var hq: float = t.height_at(q)
				lo = minf(lo, hq)
				hi = maxf(hi, hq)
			if not ok or hi - lo > 22.0 + foot * 0.15 or hi > 125.0:
				continue
			if t.road_at(p) < foot * 0.42:
				continue
			for u in used:
				if p.distance_to(u[0]) < float(u[1]) + foot * 0.55:
					ok = false
					break
			if not ok:
				continue
			var clear := PI
			for v in avoid:
				clear = minf(clear, absf(d.angle_to(v)))
			var score: float = clear * 2.0 - (ring - 1.0) * 1.2 - (hi - lo) * 0.03
			if score > best_s:
				best_s = score
				best = p
	return best


static func _shore(art: RefCounted, t: RefCounted, id: String, a: Vector2, depth: float, used: Array) -> Variant:
	## [where a quay stands on this land's shore, its turn to face the sea], nearest the heart
	var best: Variant = null
	var best_d := 1.0e9
	for k in 36:
		var d := Vector2(cos(float(k) * TAU / 36.0), sin(float(k) * TAU / 36.0))
		var r := depth * 0.5
		while r < depth * 3.0:
			var p: Vector2 = a + d * r
			if art.territory_at(p) != id and t.coast_at(p) > 2.0:
				break
			if t.coast_at(p) < 9.0:
				var ok: bool = t.height_at(p) < 30.0
				for u in used:
					if p.distance_to(u[0]) < float(u[1]) + 50.0:
						ok = false
				if ok and r < best_d:
					best_d = r
					best = [p - d * 6.0, -d.angle() + PI * 0.5]
				break
			r += 4.0
	return best


# ------------------------------------------------------------------ the pieces themselves

func build() -> void:
	var t = wv.terrain
	var list: Array = t.scenery if not (t.scenery as Array).is_empty() else plan(wv.art, wv.map, t)
	_plan = list
	if not (t.scenery_scenes as Dictionary).is_empty():
		_scenes = (t.scenery_scenes as Dictionary).duplicate()
	for spec in list:
		var node: Node3D = _make(str(spec["kind"]), str(spec["land"]), float(spec["foot"]))
		if node == null:
			continue
		var at: Vector2 = spec["at"]
		var h := 0.0
		if spec["role"] in ["ship", "lane"]:
			h = 0.0
		elif bool(spec.get("flat", false)):
			h = maxf(t.height_at(at), 0.0)
		else:
			h = _seat(t, at, float(spec["foot"]))
		node.position = Vector3(at.x, h, at.y)
		node.rotation.y = float(spec["yaw"])
		add_child(node)
		if not (spec["role"] in ["ship", "lane"]) and spec["kind"] != "bridge":
			_contact(node)
		pieces.append({"kind": spec["kind"], "land": spec["land"], "node": node, "at": at, "role": spec["role"],
			"r": float(node.get_meta("r")), "h": float(node.get_meta("h")), "base": h})
		if spec["role"] == "village" or spec["kind"] == "camp":
			_smoke(node, float(node.get_meta("h")), str(spec["kind"]))
		if spec["role"] in ["ship", "lane"]:
			ships.append({"node": node, "a": spec.get("a", at), "b": spec.get("b", at), "t": randf(), "lane": spec["role"] == "lane",
				"speed": 9.0, "bob": randf() * TAU})


func near(c: Vector2, reach: float) -> Array:
	## the standing buildings within reach of a point (what a battle there could be filmed through)
	var out: Array = []
	for p in pieces:
		if p["role"] in ["ship", "lane", "bridge"] or not (p["node"] as Node3D).visible or _cleared.has(p):
			continue
		if (p["at"] as Vector2).distance_to(c) < reach + float(p["r"]):
			out.append(p)
	return out


static func blocks(q: Vector3, among: Array) -> bool:
	## a point inside one of these buildings (the battle camera's line of sight: a church is a hill too)
	for p in among:
		var at: Vector2 = p["at"]
		if Vector2(q.x, q.z).distance_to(at) < float(p["r"]) * 0.8 and q.y < float(p["base"]) + float(p["h"]):
			return true
	return false


func clear_of(p: Vector2, pad: float) -> Vector2:
	## a spot stepped out of any building's footprint (where a figure would stand in a wall)
	for piece in pieces:
		if piece["role"] in ["ship", "lane", "bridge"] or not (piece["node"] as Node3D).visible:
			continue
		var at: Vector2 = piece["at"]
		var r: float = float(piece["r"]) * 0.85 + pad
		var d: float = p.distance_to(at)
		if d < r:
			p = at + ((p - at).normalized() if d > 0.01 else Vector2(1, 0)) * r
	return p


var _puff_mesh: QuadMesh


func _smoke(node: Node3D, h: float, kind: String) -> void:
	## a thread of smoke from the chimneys (and the ruins still smoulder, and the camp's fire burns)
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2(9, 9)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0.8))
		gr.set_color(1, Color(1, 1, 1, 0.0))
		g.gradient = gr
		m.albedo_texture = g
		_puff_mesh.material = m
	var p := CPUParticles3D.new()
	p.mesh = _puff_mesh
	p.amount = 10
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0
	p.direction = Vector3(0.35, 1.0, 0.15)
	p.spread = 12.0
	p.gravity = Vector3(1.2, 2.0, 0.4) ## the wind takes it
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	var dark: bool = kind == "village_ash" or kind == "camp"
	var c: Color = Color(0.35, 0.33, 0.32) if dark else Color(0.86, 0.85, 0.83)
	ramp.set_color(0, Color(c, 0.0))
	ramp.add_point(0.15, Color(c, 0.55))
	ramp.set_color(ramp.get_point_count() - 1, Color(c, 0.0))
	p.color_ramp = ramp
	p.position = Vector3(0, h * (0.55 if kind == "camp" else 0.92), 0)
	node.add_child(p)


var _cleared: Array = [] ## the pieces lifted off the table for a battle


func clear_for(spots: Array, pad: float) -> int:
	## A battle here: the buildings standing where it will be fought are lifted off the table (they
	## shrink away as the camera comes down), as a player moves the scenery aside to fight.
	restore()
	for p in pieces:
		if p["role"] in ["ship", "lane", "bridge"] or not (p["node"] as Node3D).visible:
			continue
		var at: Vector2 = p["at"]
		for s in spots:
			if (s as Vector2).distance_to(at) < float(p["r"]) + pad:
				_cleared.append(p)
				var n: Node3D = p["node"]
				var tw := n.create_tween()
				tw.tween_property(n, "scale", Vector3(1.0, 0.001, 1.0) * 0.001, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_callback(func(): n.visible = false)
				break
	return _cleared.size()


func restore() -> void:
	## ...and put back when the battle's done
	for p in _cleared:
		var n: Node3D = p["node"]
		if not is_instance_valid(n):
			continue
		n.visible = true
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cleared.clear()


func cleared() -> int:
	return _cleared.size()


func has(kind: String) -> bool:
	return not _variants(kind).is_empty()


func count(role: String) -> int:
	return pieces.filter(func(p): return p["role"] == role).size()


static func _seat(t: RefCounted, at: Vector2, foot: float) -> float:
	## sit a piece on the lowest of the ground under it, a little into it (no gap under a wall)
	var lo: float = t.height_at(at)
	for j in 8:
		lo = minf(lo, t.height_at(at + Vector2(cos(float(j) * TAU / 8.0), sin(float(j) * TAU / 8.0)) * foot * 0.42))
	return lo - 1.5


func _variants(kind: String) -> Array:
	if _scenes.has(kind):
		return _scenes[kind]
	_scenes[kind] = variants_of(kind)
	return _scenes[kind]


static func variants_of(kind: String) -> Array:
	var out: Array = []
	for v in ["a", "b", "c"]:
		var path: String = DIR + kind + "_" + v + ".glb"
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out


static func load_all(list: Array) -> Dictionary:
	## every model a plan needs (and the palace), loaded ahead: off the main thread, with the land
	var out := {}
	for spec in list:
		var k: String = str(spec["kind"])
		if not out.has(k):
			out[k] = variants_of(k)
	out["palace"] = variants_of("palace")
	return out


static var _contact_tex: GradientTexture2D
static var _coats := {} ## a model's own material -> it with the seating coat over it (one per model)


static func _seat_coat(inst: Node) -> void:
	## v2.0.2: the model's own material, with a second coat over it (seat.gdshader): its grass
	## plate's lime toned toward the land's greens and its foot darkened where it meets the ground
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or m.get_surface_count() < 1:
			continue
		var src: Material = m.surface_get_material(0)
		if not (src is StandardMaterial3D) or (src as StandardMaterial3D).albedo_texture == null:
			continue
		var key: int = src.get_instance_id()
		if not _coats.has(key):
			var coat := ShaderMaterial.new()
			coat.shader = load("res://game/world3d/seat.gdshader")
			coat.set_shader_parameter("albedo_tex", (src as StandardMaterial3D).albedo_texture)
			var box: AABB = m.get_aabb()
			coat.set_shader_parameter("base_y", box.position.y)
			coat.set_shader_parameter("tall", box.size.y)
			var dup: StandardMaterial3D = src.duplicate()
			dup.next_pass = coat
			_coats[key] = dup
		(mi as MeshInstance3D).material_override = _coats[key]


func _contact(node: Node3D) -> void:
	## v2.0.2: a building stands on its own shadow: a soft dark pool on the ground round its foot,
	## reaching a little up its walls, so it sits on the land rather than on top of it (Forward+;
	## the Compatibility renderer draws no decals, and the building simply stands as before)
	if _contact_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.75))
		_contact_tex = GradientTexture2D.new()
		_contact_tex.gradient = g
		_contact_tex.fill = GradientTexture2D.FILL_RADIAL
		_contact_tex.fill_from = Vector2(0.5, 0.5)
		_contact_tex.fill_to = Vector2(1.0, 0.5)
		_contact_tex.width = 128
		_contact_tex.height = 128
	var r: float = float(node.get_meta("r"))
	var h: float = float(node.get_meta("h"))
	var dc := Decal.new()
	var tall: float = clampf(h * 0.3, 8.0, 40.0)
	dc.size = Vector3(r * 2.7, tall, r * 2.7)
	dc.position = Vector3(0.0, tall * 0.2, 0.0)
	dc.texture_albedo = _contact_tex
	dc.modulate = Color(0.05, 0.04, 0.03, 0.6)
	dc.albedo_mix = 1.0
	dc.upper_fade = 0.6
	dc.lower_fade = 0.2
	node.add_child(dc)
	node.set_meta("contact", true)


func _make(kind: String, land: String, foot: float) -> Node3D:
	var vs: Array = _variants(kind)
	if vs.is_empty():
		return null
	var ps: PackedScene = vs[absi(hash(land + kind)) % vs.size()]
	var inst: Node3D = ps.instantiate()
	var aabb: AABB = _aabb(inst)
	if aabb.size.length() < 0.0001:
		inst.free()
		return null
	var s: Array = SIZE.get(kind, ["w", 90.0])
	var want: float = foot if s[0] == "w" else foot / 0.8
	var have: float = maxf(aabb.size.x, aabb.size.z) if s[0] == "w" else aabb.size.y
	var sc: float = want / maxf(have, 0.0001)
	if not (kind in ["ship", "frigate"]):
		_seat_coat(inst)
	var root := Node3D.new()
	root.add_child(inst)
	root.set_meta("h", aabb.size.y * sc)
	root.set_meta("r", maxf(aabb.size.x, aabb.size.z) * sc * 0.5)
	inst.scale = Vector3.ONE * sc
	## centred on its spot, its foot on the ground
	var centre := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5) * sc
	var turn: float = float(TURN.get(kind, 0.0))
	if kind in LENGTHWISE and aabb.size.z > aabb.size.x:
		turn += PI * 0.5 ## a long piece lies along +X (a bridge along its road, a ship along her course)
	inst.rotation.y = turn
	inst.position = -(Basis(Vector3.UP, turn) * centre)
	return root


static func _aabb(n: Node) -> AABB:
	## the model's box in its own space (every mesh under it, through their transforms)
	var box := AABB()
	var first := true
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walk: Node = m
		while walk != null and walk != n:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var b: AABB = xf * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ------------------------------------------------------------------ the rules, as they change

func set_capitals(caps: Dictionary, colors: Dictionary) -> void:
	## caps: land -> its commander (a capital). The palace stands where the land's village was,
	## its colours flying in the commander's own.
	for land in _palaces.keys():
		if not caps.has(land):
			(_palaces[land] as Node3D).queue_free()
			_palaces.erase(land)
			pieces = pieces.filter(func(p): return not (p["land"] == land and p["role"] == "palace"))
			for p in pieces:
				if p["land"] == land and p["role"] == "village":
					(p["node"] as Node3D).visible = true
	for land in caps.keys():
		var col: Color = colors.get(caps[land], Color.WHITE)
		if _palaces.has(land):
			_flag_colour(_palaces[land], col)
			continue
		## the village's place (its model may not be in yet: the plan has its spot all the same)
		var spot: Variant = null
		for sp in _plan:
			if sp["land"] == land and sp["role"] == "village":
				spot = sp
		if spot == null:
			continue
		var node: Node3D = _make("palace", land, maxf(float(spot["foot"]) * 1.2, float(SIZE["palace"][1]) * 0.8))
		if node == null:
			continue
		var at: Vector2 = spot["at"]
		node.position = Vector3(at.x, _seat(wv.terrain, at, float(spot["foot"])), at.y)
		node.rotation.y = float(spot["yaw"])
		_add_flag(node, col)
		add_child(node)
		_contact(node)
		_palaces[land] = node
		pieces.append({"kind": "palace", "land": land, "node": node, "at": at, "role": "palace",
			"r": float(node.get_meta("r")), "h": float(node.get_meta("h")), "base": node.position.y})
		for p in pieces:
			if p["land"] == land and p["role"] == "village":
				(p["node"] as Node3D).visible = false


func palaces() -> Array:
	return _palaces.keys()


var _dug := {} ## land -> the earthworks round its dug-in garrison


func set_dug(dug: Dictionary) -> void:
	## dug: land -> where its dug-in garrison stands, for every land dug in two deep or more: an
	## earthwork redoubt thrown up round the men (it goes when they're gone)
	for land in _dug.keys():
		if not dug.has(land):
			(_dug[land] as Node3D).queue_free()
			_dug.erase(land)
	for land in dug.keys():
		var at: Vector2 = dug[land]
		if _dug.has(land):
			var n0: Node3D = _dug[land]
			if Vector2(n0.position.x, n0.position.z).distance_to(at) < 1.0:
				continue
			n0.queue_free()
			_dug.erase(land)
		var node: Node3D = _make("redoubt", land, float(SIZE["redoubt"][1]) * 1.45)
		if node == null:
			continue
		node.position = Vector3(at.x, _seat(wv.terrain, at, 100.0), at.y)
		add_child(node)
		_dug[land] = node


func dug() -> Array:
	return _dug.keys()


func _add_flag(node: Node3D, col: Color) -> void:
	## the colours on a staff over the palace
	var inst: Node3D = node.get_child(0)
	var h: float = _aabb(inst).size.y * inst.scale.y
	var staff := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 34.0
	staff.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.75, 0.45)
	sm.metallic = 0.6
	staff.material_override = sm
	staff.position = Vector3(0, h + 15.0, 0)
	node.add_child(staff)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(22, 14)
	q.subdivide_width = 8
	flag.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = load("res://game/world3d/flag.gdshader")
	fm.set_shader_parameter("colour", col)
	flag.material_override = fm
	flag.position = Vector3(11.5, h + 25.0, 0)
	flag.name = "Flag"
	node.add_child(flag)


func _flag_colour(node: Node3D, col: Color) -> void:
	var f: Node = node.get_node_or_null("Flag")
	if f is MeshInstance3D:
		((f as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("colour", col)


# ------------------------------------------------------------------ the ships at sea

func _process(delta: float) -> void:
	_clock += delta
	if not is_visible_in_tree():
		return
	for s in ships:
		var n: Node3D = s["node"]
		var bob: float = sin(_clock * 0.9 + float(s["bob"]))
		if bool(s["lane"]):
			## a frigate plies its lane: out, round, and back
			var a: Vector2 = s["a"]
			var b: Vector2 = s["b"]
			var span: float = maxf(a.distance_to(b), 1.0)
			s["t"] = fmod(float(s["t"]) + delta * float(s["speed"]) / (span * 2.0), 1.0)
			var u: float = float(s["t"]) * 2.0
			var out: bool = u < 1.0
			var k: float = u if out else 2.0 - u
			k = 0.12 + 0.76 * (k * k * (3.0 - 2.0 * k))
			var p: Vector2 = a.lerp(b, k)
			var dir: Vector2 = (b - a).normalized() * (1.0 if out else -1.0)
			n.position = Vector3(p.x, 0.5 + bob * 0.6, p.y)
			n.rotation.y = lerp_angle(n.rotation.y, -dir.angle(), minf(1.0, delta * 1.5)) ## her bow down +X
		else:
			n.position.y = 0.5 + bob * 0.8
		n.rotation.z = sin(_clock * 0.7 + float(s["bob"])) * 0.035
