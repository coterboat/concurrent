## What grows on the land: woods where the terrain is wooded, scattered trees on the grass,
## pines up the mountains, and rocks on the high ground. Model-railway trees, like the tin
## soldiers: a table you could reach into. Placed by a jittered grid seeded by the map, so a
## map's woods are always where they were. Kept clear of every land's stage (its battles).
extends Node3D

var wv: Node3D
var count := 0


func grow(p_wv: Node3D) -> void:
	wv = p_wv
	var t = wv.terrain
	var art = wv.art
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(art.id)) + 4242
	var broad: Array = [] ## Transform3D
	var pine: Array = []
	var rock: Array = []
	var step := 9.0
	var stages: Array = []
	for id in art.order:
		stages.append([art.anchors[id], float(art.depth.get(id, 60.0)) * 0.55])
	## the villages and landmarks (scenery.gd's plan): no tree grows through a roof
	var built := {}
	for s in t.scenery:
		var at: Vector2 = s["at"]
		var r: float = float(s["foot"]) * 0.6
		for cy in range(int(floor((at.y - r) / 24.0)), int(floor((at.y + r) / 24.0)) + 1):
			for cx in range(int(floor((at.x - r) / 24.0)), int(floor((at.x + r) / 24.0)) + 1):
				built[Vector2i(cx, cy)] = true
	var clear := func(q: Vector2) -> bool:
		## dry land off the roads, the buildings and every land's battlefield
		if t.coast_at(q) < 5.0 or t.road_at(q) < 13.0 or built.has(Vector2i(int(floor(q.x / 24.0)), int(floor(q.y / 24.0)))):
			return false
		for s in stages:
			if q.distance_to(s[0]) < s[1]:
				return false
		return true
	var y := step * 0.5
	while y < art.size.y:
		var x := step * 0.5
		while x < art.size.x:
			var p := Vector2(x + rng.randf_range(-0.45, 0.45) * step, y + rng.randf_range(-0.45, 0.45) * step)
			x += step
			if not clear.call(p):
				continue
			var h: float = t.height_at(p)
			var n: Vector3 = t.normal_at(p)
			var wd: float = t.woods_at(p)
			var r := rng.randf()
			var steep: float = 1.0 - n.y
			if steep > 0.35:
				if h > 60.0 and r < 0.04:
					rock.append(_xf(p, h, rng, rng.randf_range(2.5, 5.0)))
				continue
			if h > 140.0:
				continue
			if wd > 0.35 and r < wd * 0.85:
				(pine if h > 70.0 or rng.randf() < 0.35 else broad).append(_xf(p, h, rng, rng.randf_range(0.8, 1.25)))
			elif h > 75.0 and r < 0.07:
				pine.append(_xf(p, h, rng, rng.randf_range(0.7, 1.1)))
			elif r < 0.024:
				## v2.0.2: a fuller countryside: a lone tree, or a copse of two to four
				broad.append(_xf(p, h, rng, rng.randf_range(0.8, 1.2)))
				if r < 0.012:
					for k in rng.randi_range(1, 3):
						var q: Vector2 = p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 12.0)
						var hq: float = t.height_at(q)
						if clear.call(q) and hq < 140.0 and 1.0 - t.normal_at(q).y < 0.35:
							broad.append(_xf(q, hq, rng, rng.randf_range(0.7, 1.1)))
			elif h > 55.0 and r < 0.03:
				rock.append(_xf(p, h, rng, rng.randf_range(2.0, 4.0)))
		y += step
	_multi(_broadleaf(), broad)
	_multi(_pine(), pine)
	_multi(_rock(), rock)
	count = broad.size() + pine.size() + rock.size()


func _xf(p: Vector2, h: float, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
	return Transform3D(b, Vector3(p.x, h - 0.6, p.y))


func _multi(mesh: Mesh, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		var v: float = randf_range(0.82, 1.12)
		mm.set_instance_color(i, Color(v, v * randf_range(0.95, 1.05), v))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


func _mat(col: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


func _broadleaf() -> Mesh:
	## a model-railway oak: a trunk and a crown of four lumps (v2.0.2: it was two), darker
	## underneath where the light doesn't reach, so it reads round from above
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.7
	trunk.bottom_radius = 1.0
	trunk.height = 5.5
	trunk.radial_segments = 6
	trunk.rings = 1
	_append(am, trunk, Transform3D(Basis(), Vector3(0, 2.75, 0)), _mat(Color(0.33, 0.24, 0.16)), 0.0, 5.0, 0.6, 1.0)
	var leaf := _mat(Color(0.25, 0.39, 0.16))
	var leaf2 := _mat(Color(0.30, 0.45, 0.19))
	for lobe in [[Vector3(0, 8.4, 0), 4.6, leaf], [Vector3(2.3, 9.8, 1.1), 3.1, leaf2], [Vector3(-2.2, 9.5, -1.3), 3.3, leaf],
			[Vector3(0.5, 12.0, -0.5), 2.7, leaf2]]:
		var s := SphereMesh.new()
		s.radius = float(lobe[1])
		s.height = float(lobe[1]) * 1.65
		s.radial_segments = 10
		s.rings = 6
		_append(am, s, Transform3D(Basis(), lobe[0]), lobe[2], 4.5, 14.0, 0.5, 1.12)
	return am


func _pine() -> Mesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.5
	trunk.bottom_radius = 0.8
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	_append(am, trunk, Transform3D(Basis(), Vector3(0, 1.5, 0)), _mat(Color(0.3, 0.22, 0.15)), 0.0, 3.0, 0.6, 1.0)
	var needles := _mat(Color(0.15, 0.29, 0.17))
	for k in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 4.4 - k * 0.95
		cone.height = 5.6 - k * 0.8
		cone.radial_segments = 9
		cone.rings = 1
		## each tier dark at its skirt and lit at its tip
		var y0: float = 4.4 + k * 2.7
		_append(am, cone, Transform3D(Basis(), Vector3(0, y0, 0)), needles, y0 - 2.8, y0 + 2.8, 0.55, 1.1)
	return am


func _rock() -> Mesh:
	var am := ArrayMesh.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.3
	s.radial_segments = 6
	s.rings = 3
	_append(am, s, Transform3D(Basis().scaled(Vector3(1.3, 1.0, 0.9)), Vector3(0, 0.3, 0)), _mat(Color(0.47, 0.45, 0.42), 0.95))
	return am


func _append(am: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, mat: Material, y0: float = 0.0, y1: float = 1.0, lo: float = 1.0, hi: float = 1.0) -> void:
	## (v2.0.2: shaded from lo at height y0 to hi at y1, in its vertex colours)
	var arrays: Array = prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (xf.basis * norms[i]).normalized()
		var v: float = lerpf(lo, hi, clampf((verts[i].y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0))
		cols[i] = Color(v, v, v)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TANGENT] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, mat)
