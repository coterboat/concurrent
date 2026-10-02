## Every diorama model as the game turns it (Diorama.MODELS' yaw), seen from the front (the
## camera down +Z, where a figure should face) and from its right side. A figure set right looks
## at the camera in the top row and faces left in the bottom row.
##   SHOT_DIR=/dir ./scripts/shot.sh ../spike/models_view   (or via probe.tscn --script=)
extends RefCounted

const Diorama := preload("res://game/world3d/diorama.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1800, 560)
	var vp := SubViewport.new()
	vp.size = Vector2i(1800, 560)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	p.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var dio = Diorama.new()
	root.add_child(dio)
	await p.frames(2)
	var kinds: Array = Diorama.MODELS.keys().filter(func(k): return dio.has_model(k))
	var x := 0.0
	for k in kinds:
		for row in 2:
			var f := Node3D.new()
			var mi := MeshInstance3D.new()
			var m: Dictionary = dio._meshes[k]
			mi.mesh = m["mesh"]
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = m["tex"]
			mi.material_override = mat
			var aabb: AABB = m["aabb"]
			var sc: float = 1.0 / maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
			mi.scale = Vector3.ONE * sc
			mi.position = Vector3(0, -aabb.position.y * sc, 0)
			mi.rotation = Vector3(0, float(m["yaw"]), 0)
			f.add_child(mi)
			## the bottom row: the same figure turned a quarter, so we see its right side
			f.position = Vector3(x, 1.25 - float(row) * 1.25, 0)
			f.rotation = Vector3(0, 0.0 if row == 0 else -PI * 0.5, 0)
			root.add_child(f)
			var arrow := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.02, 0.4)
			arrow.mesh = bm
			var am := StandardMaterial3D.new()
			am.albedo_color = Color(0.9, 0.1, 0.1)
			arrow.material_override = am
			arrow.position = Vector3(0, 0.01, 0.2)
			f.add_child(arrow)
		var lab := Label3D.new()
		lab.text = k
		lab.font_size = 48
		lab.pixel_size = 0.004
		lab.modulate = Color.BLACK
		lab.position = Vector3(x, 2.35, 0)
		root.add_child(lab)
		x += 1.3
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(2.6, x / (1800.0 / 560.0) * 1.05)
	cam.position = Vector3((x - 1.3) * 0.5, 1.15, 6.0)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	root.add_child(cam)
	cam.current = true
	await p.frames(6)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/models_view.png")
	p.log("shot models_view (%s)" % ", ".join(kinds))
