## Every land piece (scenery.gd's models, assets/models/land/) on one sheet, each as the board
## sees it: from the south and a little above (the board's camera), at its size on the land, beside
## a tin soldier for scale. A red bar on the ground points down +Z, toward the board's camera.
##   SHOT_DIR=/dir ./scripts/shot.sh ../spike/land_view
extends RefCounted

const Scenery := preload("res://game/world3d/scenery.gd")
const Diorama := preload("res://game/world3d/diorama.gd")

var p


func run(probe) -> void:
	p = probe
	var kinds: Array = []
	for k in Scenery.SIZE.keys():
		for v in ["a", "b"]:
			if ResourceLoader.exists("res://assets/models/land/%s_%s.glb" % [k, v]):
				kinds.append([k, v])
	var cols := 8
	var rows: int = maxi(1, int(ceil(float(kinds.size()) / float(cols))))
	var cell := 190.0
	var w := 1800
	var h: int = int(140 + rows * 240)
	p.get_window().size = Vector2i(w, mini(h, 1400))
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	p.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.81, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var sc := Scenery.new()
	root.add_child(sc)
	var dio = Diorama.new()
	root.add_child(dio)
	await p.frames(2)
	for i in kinds.size():
		var k: String = kinds[i][0]
		var v: String = kinds[i][1]
		var ps: PackedScene = load("res://assets/models/land/%s_%s.glb" % [k, v])
		sc._scenes[k] = [ps]
		var foot: float = Scenery._foot(k)
		var node: Node3D = sc._make(k, k, foot)
		var cx: float = float(i % cols) * cell
		var cz: float = float(i / cols) * cell * 1.25
		node.position = Vector3(cx, 0, cz)
		root.add_child(node)
		var mat_g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(cell * 0.92, cell * 0.92)
		mat_g.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.45, 0.55, 0.32)
		mat_g.material_override = fm
		mat_g.position = Vector3(cx, -0.2, cz)
		root.add_child(mat_g)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3, 1, 40)
		bar.mesh = bm
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(0.9, 0.1, 0.1)
		bar.material_override = am
		bar.position = Vector3(cx - cell * 0.38, 0.5, cz + 20)
		root.add_child(bar)
		## a man for scale
		if dio.has_model("inf"):
			var m: Dictionary = dio._meshes["inf"]
			var mi := MeshInstance3D.new()
			mi.mesh = m["mesh"]
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = m["tex"]
			mi.material_override = mat
			var aabb: AABB = m["aabb"]
			var s: float = Diorama.FIG / aabb.size.y
			mi.scale = Vector3.ONE * s
			mi.position = Vector3(cx + cell * 0.36, -aabb.position.y * s, cz + cell * 0.3)
			root.add_child(mi)
		var lab := Label3D.new()
		lab.text = "%s %s" % [k, v]
		lab.font_size = 64
		lab.pixel_size = 0.35
		lab.modulate = Color.BLACK
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3(cx, 4, cz + cell * 0.5)
		root.add_child(lab)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = float(cols) * cell * 1.02
	var mid := Vector3((float(cols) - 1.0) * cell * 0.5, 0, (float(rows) - 1.0) * cell * 1.25 * 0.5)
	cam.position = mid + Vector3(0, 900, 900).normalized() * 3000.0
	root.add_child(cam)
	cam.look_at(mid, Vector3.UP)
	cam.current = true
	await p.frames(8)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/land_view.png")
	p.log("shot land_view (%d pieces)" % kinds.size())
