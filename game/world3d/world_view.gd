## The map as a 3D world: the ground raised from terrain.gd's heights, the sea, the sun, the
## sky, and a camera that can stand exactly where the 2D board's view is (looking straight
## down, nearly orthographic) and then tip down onto the land. World units are map pixels:
## x east, z south, y up.
extends Node3D

const Terrain := preload("res://game/world3d/terrain.gd")

var art: RefCounted
var map: RefCounted
var terrain: RefCounted
var ground: MeshInstance3D
var water: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment
var cam: Camera3D
var gmat: ShaderMaterial
var wmat: ShaderMaterial
var props: Node3D ## props.gd: woods and rocks, rising with the land
var scenery: Node3D ## scenery.gd: the villages and landmarks, rising with it too
var fog_k := 1.0 ## the haze, 0..1 of its full depth (it scales with how far the camera stands)
const SUN_CHART := Vector3(-0.62, 0.62, -0.48) ## toward the sun over the chart: the north-west, as the board is shaded

## the camera rig: looks at `target` from `pitch` degrees above the horizon, from the side
## `yaw` degrees round from the south, framing `span` world units top to bottom
var rig := {"target": Vector3.ZERO, "pitch": 90.0, "yaw": 0.0, "fov": 1.2, "span": 600.0}
var relief := 0.0:
	set(v):
		relief = v
		if gmat:
			gmat.set_shader_parameter("relief", v)
			wmat.set_shader_parameter("relief", v)
			wmat.set_shader_parameter("fade", smoothstep(0.02, 0.35, v))
			water.visible = v > 0.01
		if props:
			## the woods come up once the land has: they grow from the risen ground, never dot the chart
			var g: float = smoothstep(0.35, 0.9, v)
			props.visible = g > 0.01
			props.scale = Vector3(1.0, maxf(v * g, 0.01), 1.0)
			if scenery:
				scenery.visible = g > 0.01
				scenery.scale = props.scale
var realism := 0.0:
	set(v):
		realism = v
		if gmat:
			gmat.set_shader_parameter("realism", v)
var paint := 0.0: ## the chart's colours on the lit land (the board in 3D)
	set(v):
		paint = v
		if gmat:
			gmat.set_shader_parameter("paint", v)
			wmat.set_shader_parameter("paint", v)


func setup(p_art: RefCounted, p_map: RefCounted, state_tex: Texture2D, p_terrain: RefCounted = null) -> void:
	art = p_art
	map = p_map
	terrain = p_terrain if p_terrain != null else Terrain.build(art, map, 3)
	var ms: Vector2 = art.size
	## the ground: a vertex for every cell of the heights, raised in the shader
	gmat = ShaderMaterial.new()
	gmat.shader = load("res://game/world3d/ground.gdshader")
	gmat.set_shader_parameter("height_tex", ImageTexture.create_from_image(terrain.height_image))
	var hm: Image = terrain.height_image.duplicate()
	hm.generate_mipmaps()
	gmat.set_shader_parameter("height_mip", ImageTexture.create_from_image(hm))
	gmat.set_shader_parameter("ground_tex", ImageTexture.create_from_image(terrain.ground_image))
	gmat.set_shader_parameter("data_n", art.data_texture)
	gmat.set_shader_parameter("data_l", art.data_texture)
	gmat.set_shader_parameter("state_tex", state_tex)
	gmat.set_shader_parameter("land_tex", load("res://assets/tex/land.webp"))
	gmat.set_shader_parameter("sea_tex", load("res://assets/tex/sea.webp"))
	gmat.set_shader_parameter("paper_tex", load("res://assets/tex/parchment.webp"))
	gmat.set_shader_parameter("grain_tex", _grain())
	gmat.set_shader_parameter("map_size", ms)
	gmat.set_shader_parameter("cell", terrain.cell)
	gmat.set_shader_parameter("n_terr", float(art.order.size()))
	_ground_detail()
	var pm := PlaneMesh.new()
	pm.size = ms
	pm.subdivide_width = terrain.w - 1
	pm.subdivide_depth = terrain.h - 1
	ground = MeshInstance3D.new()
	ground.mesh = pm
	ground.material_override = gmat
	ground.position = Vector3(ms.x * 0.5, 0.0, ms.y * 0.5)
	ground.custom_aabb = AABB(Vector3(-ms.x * 0.5, terrain.lo - 5.0, -ms.y * 0.5), Vector3(ms.x, terrain.hi - terrain.lo + 10.0, ms.y))
	add_child(ground)
	## the sea, out to the horizon
	wmat = ShaderMaterial.new()
	wmat.shader = load("res://game/world3d/water.gdshader")
	wmat.set_shader_parameter("height_tex", gmat.get_shader_parameter("height_tex"))
	wmat.set_shader_parameter("data_l", art.data_texture)
	wmat.set_shader_parameter("sea_tex", load("res://assets/tex/sea.webp"))
	wmat.set_shader_parameter("wave_a", _waves(11))
	wmat.set_shader_parameter("wave_b", _waves(23))
	wmat.set_shader_parameter("map_size", ms)
	var wm := PlaneMesh.new()
	wm.size = Vector2(60000, 60000)
	water = MeshInstance3D.new()
	water.mesh = wm
	water.material_override = wmat
	water.position = Vector3(ms.x * 0.5, 0.0, ms.y * 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	props = load("res://game/world3d/props.gd").new()
	add_child(props)
	props.grow(self)
	## the sun, from the north-west as the chart's own shading has it
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.7 ## v2.0.2: a firmer sun and less sky (was 1.55, ambient 0.75): the relief reads
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	aim_sun(SUN_CHART)
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.30, 0.42, 0.58)
	psm.sky_horizon_color = Color(0.80, 0.76, 0.68)
	psm.ground_horizon_color = Color(0.70, 0.67, 0.60)
	psm.ground_bottom_color = Color(0.16, 0.17, 0.18)
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 6.0
	env.ssao_intensity = 2.1
	env.ssao_light_affect = 0.15 ## the creases darken in the sun too, a little: things sit in the land
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.74, 0.70)
	env.fog_density = 0.0
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.5
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.current = true
	add_child(cam)
	apply_rig()


## the ground textures (Ludo's, a tabletop's terrain mats), one layer a terrain, in terrain.gd's order
const DETAIL := ["grass", "forest", "moor", "grass", "desert", "snow", "ash", "rock", "sand", "field"]


func _ground_detail() -> void:
	## the ground's own texture, blended by each terrain's share of the ground (when the mats exist)
	var imgs: Array[Image] = []
	var means := PackedVector3Array()
	var cache := {}
	for name in DETAIL:
		var path: String = "res://assets/tex/ground/%s.webp" % name
		if not ResourceLoader.exists(path):
			gmat.set_shader_parameter("has_detail", false)
			return
		if not cache.has(name):
			var img: Image = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGB8)
			if img.get_width() != 1024 or img.get_height() != 1024:
				img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
			var small: Image = img.duplicate()
			small.resize(1, 1, Image.INTERPOLATE_BILINEAR)
			var m: Color = small.get_pixel(0, 0)
			img.generate_mipmaps()
			cache[name] = [img, Vector3(m.r, m.g, m.b)]
		imgs.append(cache[name][0])
		means.append(cache[name][1])
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	gmat.set_shader_parameter("detail_tex", arr)
	gmat.set_shader_parameter("detail_mean", means)
	gmat.set_shader_parameter("weights_a", ImageTexture.create_from_image(terrain.weights_a))
	gmat.set_shader_parameter("weights_b", ImageTexture.create_from_image(terrain.weights_b))
	if not (terrain.scenery as Array).is_empty():
		gmat.set_shader_parameter("fields_tex", ImageTexture.create_from_image(load("res://game/world3d/scenery.gd").fields(terrain.scenery, terrain)))
	gmat.set_shader_parameter("has_detail", true)


func aim_sun(toward: Vector3) -> void:
	sun.basis = Basis.looking_at(-toward.normalized(), Vector3.UP)


static func sun_for(yaw_deg: float) -> Vector3:
	## a lamp over the table: from behind the camera's left shoulder, high, so the side of
	## everything we look at is lit
	var a: float = deg_to_rad(yaw_deg + 38.0)
	return Vector3(sin(a) * 0.62, 0.78, cos(a) * 0.62).normalized()


func rig_eye(r: Dictionary) -> Vector3:
	## where the camera stands for this rig
	var d: float = float(r["span"]) / (2.0 * tan(deg_to_rad(r["fov"]) * 0.5))
	var pitch: float = deg_to_rad(r["pitch"])
	var yaw: float = deg_to_rad(r["yaw"])
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return (r["target"] as Vector3) + (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized() * d


func apply_rig() -> void:
	var fov: float = rig["fov"]
	var d: float = float(rig["span"]) / (2.0 * tan(deg_to_rad(fov) * 0.5))
	var pitch: float = deg_to_rad(rig["pitch"])
	var yaw: float = deg_to_rad(rig["yaw"])
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var t: Vector3 = rig["target"]
	var z: Vector3 = (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var x: Vector3 = Vector3.UP.cross(back).normalized()
	var y: Vector3 = z.cross(x)
	cam.transform = Transform3D(Basis(x, y, z), t + z * d)
	cam.fov = fov
	cam.near = maxf(0.5, d * 0.02)
	cam.far = d * 4.0 + 9000.0
	if sun:
		sun.directional_shadow_max_distance = clampf(d * 2.5, 600.0, 8000.0)
	if env:
		env.fog_density = fog_k * 0.22 / maxf(d, 1.0)


func rig_from_board(board: Control, vp_size: Vector2) -> Dictionary:
	## the rig that frames exactly what the 2D board shows (relief flat, straight down)
	var c: Vector2 = board.screen_to_map(vp_size * 0.5)
	return {"target": Vector3(c.x, 0.0, c.y), "pitch": 90.0, "yaw": 0.0, "fov": 1.2, "span": vp_size.y / float(board.zoom)}


func ground_at(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p) * relief, p.y)


func lerp_rig(a: Dictionary, b: Dictionary, t: float, tilt_t: float) -> Dictionary:
	## framing and lens in log space (a dolly zoom: the land keeps its size as the lens widens)
	var ta: float = tan(deg_to_rad(a["fov"]) * 0.5)
	var tb: float = tan(deg_to_rad(b["fov"]) * 0.5)
	var tf: float = exp(lerpf(log(ta), log(tb), t))
	return {
		"target": (a["target"] as Vector3).lerp(b["target"], t),
		"pitch": lerpf(a["pitch"], b["pitch"], tilt_t),
		"yaw": float(a["yaw"]) + wrapf(float(b["yaw"]) - float(a["yaw"]), -180.0, 180.0) * tilt_t, ## the short way round
		"fov": rad_to_deg(atan(tf) * 2.0),
		"span": exp(lerpf(log(float(a["span"])), log(float(b["span"])), t)),
	}


func _grain() -> ImageTexture:
	## three tiling noises in one texture's channels
	var imgs := []
	for k in 3:
		var nz := FastNoiseLite.new()
		nz.seed = 77 + k * 31
		nz.frequency = 0.02 + 0.015 * k
		nz.fractal_octaves = 4
		imgs.append(nz.get_seamless_image(256, 256))
	var out := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			out.set_pixel(x, y, Color(imgs[0].get_pixel(x, y).r, imgs[1].get_pixel(x, y).r, imgs[2].get_pixel(x, y).r))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


func _waves(sd: int) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = sd
	nz.frequency = 0.03
	nz.fractal_octaves = 3
	nt.noise = nz
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.width = 256
	nt.height = 256
	nt.generate_mipmaps = true
	return nt
