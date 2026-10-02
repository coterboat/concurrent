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
	var y := step * 0.5
	while y < art.size.y:
		var x := step * 0.5
		while x < art.size.x:
			var p := Vector2(x + rng.randf_range(-0.45, 0.45) * step, y + rng.randf_range(-0.45, 0.45) * step)
			x += step
			var c: float = t.coast_at(p)
			if c < 5.0:
				continue
			var near_stage := false
			for s in stages:
				if p.distance_to(s[0]) < s[1]:
					near_stage = true
					break
			if near_stage or t.road_at(p) < 13.0 or built.has(Vector2i(int(floor(p.x / 24.0)), int(floor(p.y / 24.0)))):
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
			elif r < 0.012:
				broad.append(_xf(p, h, rng, rng.randf_range(0.8, 1.2)))
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
	## a lollipop oak: a trunk and two lumps of crown
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.7
	trunk.bottom_radius = 1.0
	trunk.height = 5.0
	trunk.radial_segments = 6
	trunk.rings = 1
	_append(am, trunk, Transform3D(Basis(), Vector3(0, 2.5, 0)), _mat(Color(0.33, 0.24, 0.16)))
	var crown := SphereMesh.new()
	crown.radius = 4.6
	crown.height = 7.6
	crown.radial_segments = 9
	crown.rings = 5
	_append(am, crown, Transform3D(Basis(), Vector3(0, 8.6, 0)), _mat(Color(0.24, 0.38, 0.16)))
	var c2 := SphereMesh.new()
	c2.radius = 3.0
	c2.height = 5.0
	c2.radial_segments = 8
	c2.rings = 4
	_append(am, c2, Transform3D(Basis(), Vector3(1.6, 11.0, 0.8)), _mat(Color(0.28, 0.43, 0.18)))
	return am


func _pine() -> Mesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.5
	trunk.bottom_radius = 0.8
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	_append(am, trunk, Transform3D(Basis(), Vector3(0, 1.5, 0)), _mat(Color(0.3, 0.22, 0.15)))
	for k in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 4.2 - k * 1.1
		cone.height = 6.0 - k * 1.0
		cone.radial_segments = 8
		cone.rings = 1
		_append(am, cone, Transform3D(Basis(), Vector3(0, 5.0 + k * 3.4, 0)), _mat(Color(0.14, 0.27, 0.16)))
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


func _append(am: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var arrays: Array = prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (xf.basis * norms[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, mat)
