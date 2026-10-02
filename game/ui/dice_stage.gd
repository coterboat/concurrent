## Real dice on a real table. A small 3D world of its own (a SubViewport drawn into this
## Control at full screen resolution): rounded dice thrown in from the side or dropped
## from above, bouncing, tumbling edge over edge, and settling on the face the engine
## already rolled. The motion is planned backwards from the final face, so every throw
## looks loose and physical and still always lands on the right number.
## The dice are made of what their army can afford (tier_for): whittled wood for a lone
## holdout up to gold with gem pips for a grand army. Each knock on the table plays.
extends Control

const Style := preload("res://game/core/style.gd")

signal all_settled

## name, the smallest army that rolls it, and what the die is made of
const TIERS := [
	## v1.6: every die wears its commander's colour (painted edges, stained wood, coloured
	## pips or lacquer) and sits in a glow of that colour, so whose die is whose reads at a glance
	{"name": "Lone holdout", "min": 1, "size": 0.9, "body": Color(0.54, 0.35, 0.2), "stain": 0.4, "pip": Color(0.16, 0.08, 0.04), "rough": 0.85, "grain": 1.0, "wear": 1.0, "edge": 0.75, "sound": "dice_knock"},
	{"name": "Company", "min": 3, "size": 1.0, "body": Color(0.91, 0.86, 0.74), "pip": "seat_dark", "rough": 0.55, "wear": 0.35, "edge": 0.75, "sound": "dice_click"},
	{"name": "Regiment", "min": 7, "size": 1.03, "body": Color(0.97, 0.94, 0.85), "pip": "seat", "rough": 0.3, "edge": 0.9, "sound": "dice_click"},
	{"name": "Brigade", "min": 15, "size": 1.07, "body": "seat", "pip": Color(0.97, 0.93, 0.82), "rough": 0.22, "metal": 0.15, "edge": 1.0, "brass": true, "sound": "dice_click"},
	{"name": "Grand army", "min": 30, "size": 1.13, "body": Color(0.98, 0.78, 0.36), "pip": "seat", "rough": 0.26, "metal": 0.85, "pip_glow": 0.9, "star": true, "edge": 0.8, "sound": "dice_clunk"},
]

var board := true ## draw the tray (false: just the dice and their shadows, over anything)
var width := 14.0 ## ground units the camera frames across
var table_w := 0.0 ## how wide the tray is (0 = nearly all of it); the dice fly in from beyond it
var pitch := 55.0 ## degrees the camera looks down
var gravity := 34.0
var pace := 1.0 ## > 1 hurries the roll along the felt (auto-roll)
var quiet := false ## no knocks (tests, previews)
var ground_h := 0.0 ## pixels at the bottom the table fills (0 = all of it); above it the dice fly in over whatever is behind

var _vp: SubViewport
var _cam: Camera3D
var _world: Node3D
var _dice: Array = []
var _clock := 0.0
var _px := 1.0 ## viewport pixels per Control pixel
var _depth := 4.0 ## ground units the camera frames top to bottom (from width and aspect)
var _board_nodes: Array = []
var _settled_sent := true
var _knock_at := {} ## sound -> last time, so a clatter never stacks into a roar

static var _mesh: ArrayMesh
static var _shader: Shader
static var _blob: GradientTexture2D


static func tier_for(n: int) -> int:
	var t := 0
	for i in TIERS.size():
		if n >= int(TIERS[i]["min"]):
			t = i
	return t


static func tier_name(n: int) -> String:
	return str(TIERS[tier_for(n)]["name"])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 30.0
	_world.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	_world.add_child(fill)
	var env := Environment.new()
	## a black, fully clear background: the render comes out premultiplied, and is drawn so
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	## a warm lamp-lit room for the metal to reflect
	sm.sky_top_color = Color(0.62, 0.56, 0.46)
	sm.sky_horizon_color = Color(1.0, 0.9, 0.7)
	sm.ground_horizon_color = Color(0.82, 0.62, 0.38)
	sm.ground_bottom_color = Color(0.42, 0.28, 0.16)
	sm.energy_multiplier = 1.2
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = cm
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	if _vp == null or size.x < 4.0 or size.y < 4.0:
		return
	var vt: Transform2D = get_viewport().get_final_transform() if get_viewport() != null else Transform2D.IDENTITY
	_px = clampf(vt.get_scale().x, 1.0, 3.0)
	_vp.size = Vector2i(int(size.x * _px), int(size.y * _px))
	## frame `width` units across; the depth follows from the aspect and the tilt
	var dist: float = width * 0.5 * 1.04 / tan(deg_to_rad(_cam.fov * 0.5))
	var p: float = deg_to_rad(pitch)
	_cam.position = Vector3(0, sin(p) * dist, cos(p) * dist)
	_cam.rotation = Vector3(-p, 0, 0)
	var gh: float = size.y if ground_h <= 0.0 else minf(ground_h, size.y)
	var half_h: float = dist * tan(atan(tan(deg_to_rad(_cam.fov * 0.5)) * size.y / size.x)) ## world units, centre to top edge
	_depth = 2.0 * half_h * (gh / size.y) / maxf(0.3, sin(p))
	## the table sits at the bottom: lift the camera so its middle lands there
	var shift: float = half_h * (size.y - gh) / size.y
	_cam.position += _cam.transform.basis.y * shift
	_build_board()


func depth() -> float:
	return _depth


func _process(delta: float) -> void:
	if _dice.is_empty():
		return
	_clock += delta * maxf(0.5, pace)
	var moving := false
	for d in _dice:
		_pose(d)
		if not bool(d["done"]):
			moving = true
	if not moving and not _settled_sent:
		_settled_sent = true
		if not quiet and visible:
			_sfx("dice_settle", -9.0) ## v1.10: the dice come to rest
		all_settled.emit()
	queue_redraw()


func _draw() -> void:
	if _vp != null:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)


# ------------------------------------------------------------------ the table

func _build_board() -> void:
	for n in _board_nodes:
		n.queue_free()
	_board_nodes = []
	clear_pieces() ## re-set by their owner on the next count
	if not board:
		return
	var w: float = table_w if table_w > 0.0 else width * 0.98
	var dd: float = _depth * 0.9
	## v1.9: the table is dressed in real materials (assets/tex: baize, mahogany, brass), with
	## a bump taken from each texture so the cloth has a nap and the wood a grain under the lamp
	var felt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, dd)
	felt.mesh = pm
	var fm := StandardMaterial3D.new()
	var baize: Texture2D = Style.tex("res://assets/tex/felt.webp")
	if baize != null:
		fm.albedo_texture = baize
		fm.uv1_scale = Vector3(w / 3.2, dd / 3.2, 1) ## a tile every ~3 units: fine cloth, never a visible repeat
		fm.albedo_color = Color(0.62, 0.7, 0.62)
		fm.normal_enabled = true
		fm.normal_texture = _bump_of("felt", baize, 3.0)
		fm.normal_scale = 0.6
	else:
		var tex: Texture2D = Style.tex("res://assets/battle/dice_tray.webp")
		if tex != null:
			fm.albedo_texture = tex
			fm.uv1_scale = Vector3(0.74, 0.62, 1)
			fm.uv1_offset = Vector3(0.13, 0.19, 0)
			fm.albedo_color = Color(0.5, 0.55, 0.5)
		else:
			fm.albedo_color = Color(0.06, 0.16, 0.1)
	fm.roughness = 1.0
	fm.metallic_specular = 0.1
	felt.material_override = fm
	_add_board(felt)
	## the lamp's pool on the cloth: dark toward the rails, so the dice sit in the light
	var vig := MeshInstance3D.new()
	var vm := PlaneMesh.new()
	vm.size = Vector2(w, dd)
	vig.mesh = vm
	vig.position.y = 0.004
	var vmat := StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vmat.albedo_texture = _vignette()
	vig.material_override = vmat
	_add_board(vig)
	## a shadow under the whole table, so it sits on the field instead of floating over it
	var drop := MeshInstance3D.new()
	var dm := PlaneMesh.new()
	dm.size = Vector2(w + 2.4, dd + 1.8)
	drop.mesh = dm
	drop.position.y = -0.02
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_texture = _blob_of()
	dmat.albedo_color = Color(0, 0, 0, 0.75)
	drop.material_override = dmat
	_add_board(drop)
	## mahogany rails with a rounded top and a brass inlay along the inside edge
	var wood := StandardMaterial3D.new()
	var mahog: Texture2D = Style.tex("res://assets/tex/rail_wood.webp")
	if mahog != null:
		wood.albedo_texture = mahog
		wood.uv1_triplanar = true
		wood.uv1_scale = Vector3(0.45, 0.45, 0.45)
		wood.albedo_color = Color(0.85, 0.78, 0.74)
		wood.normal_enabled = true
		wood.normal_texture = _bump_of("wood", mahog, 1.5)
		wood.normal_scale = 0.35
		wood.uv1_world_triplanar = true
	else:
		wood.albedo_color = Color(0.16, 0.06, 0.03)
	wood.roughness = 0.32
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	wood.clearcoat_roughness = 0.25
	var brass := StandardMaterial3D.new()
	var bt: Texture2D = Style.tex("res://assets/tex/brass.webp")
	if bt != null:
		brass.albedo_texture = bt
		brass.uv1_triplanar = true
		brass.uv1_scale = Vector3(0.9, 0.9, 0.9)
		brass.albedo_color = Color(1.0, 0.9, 0.7)
	else:
		brass.albedo_color = Color(0.85, 0.66, 0.3)
	brass.metallic = 0.85
	brass.roughness = 0.34
	const RW := 0.34 ## rail width
	const RH := 0.26 ## rail height below the rounded top
	var rails := [
		[Vector3(0, 0, -dd * 0.5 - RW * 0.5), w + RW * 2.0, true, 1.0],
		[Vector3(0, 0, dd * 0.5 + RW * 0.5), w + RW * 2.0, true, -1.0],
		[Vector3(-w * 0.5 - RW * 0.5, 0, 0), dd, false, 1.0],
		[Vector3(w * 0.5 + RW * 0.5, 0, 0), dd, false, -1.0]]
	for rl in rails:
		var at: Vector3 = rl[0]
		var length: float = rl[1]
		var along_x: bool = rl[2]
		var inward: float = rl[3]
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length, RH, RW) if along_x else Vector3(RW, RH, length)
		body.mesh = bm
		body.position = at + Vector3(0, RH * 0.5, 0)
		body.material_override = wood
		_add_board(body)
		var cap := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = RW * 0.5
		cy.bottom_radius = RW * 0.5
		cy.height = length
		cy.radial_segments = 20
		cap.mesh = cy
		cap.position = at + Vector3(0, RH, 0)
		cap.rotation = Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
		cap.scale = Vector3(0.55, 1, 1) if along_x else Vector3(1, 1, 0.55) ## a low, rounded bullnose, not a pipe
		cap.material_override = wood
		_add_board(cap)
		var inlay := MeshInstance3D.new()
		var im := BoxMesh.new()
		im.size = Vector3(length - RW * 1.6, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, length - 0.1)
		inlay.mesh = im
		var edge: Vector3 = Vector3(0, 0, inward * (RW * 0.5 + 0.02)) if along_x else Vector3(inward * (RW * 0.5 + 0.02), 0, 0)
		inlay.position = at + edge + Vector3(0, 0.03, 0)
		inlay.material_override = brass
		_add_board(inlay)
	## brass corner posts with a round finial
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var post := MeshInstance3D.new()
			var pmh := BoxMesh.new()
			pmh.size = Vector3(RW * 1.2, RH + 0.14, RW * 1.2)
			post.mesh = pmh
			var pc := Vector3(cx * (w * 0.5 + RW * 0.5), (RH + 0.14) * 0.5, cz * (dd * 0.5 + RW * 0.5))
			post.position = pc
			post.material_override = brass
			_add_board(post)
			var knob := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = RW * 0.42
			sm.height = RW * 0.84
			knob.mesh = sm
			knob.position = pc + Vector3(0, (RH + 0.14) * 0.5 + RW * 0.3, 0)
			knob.material_override = brass
			_add_board(knob)


func _add_board(n: Node3D) -> void:
	_world.add_child(n)
	_board_nodes.append(n)


# ------------------------------------------------------------------ the pieces (v1.9)
## Painted tin miniatures (Ludo 3D, assets/models) stand at the back corners of the table,
## one for each side, on a plinth in its colour: the Risk piece its army is worth (a cannon
## for ten, a horse for five, a man), so they change as the men fall. At the end the
## winner's becomes the colour-bearer and the loser's topples.

var _pieces := {} ## side (0 left, 1 right) -> {node, kind}
static var _piece_scenes := {}
const PIECE_H := 1.9 ## how tall a piece stands, in table units


static func piece_for(n: int) -> String:
	return "cannon" if n >= 10 else ("cavalry" if n >= 5 else "infantry")


static func has_pieces() -> bool:
	return ResourceLoader.exists("res://assets/models/infantry.glb")


static func warm_pieces() -> void:
	## load the four pieces once, before the first battle needs them (no hitch mid-throw)
	for k in ["infantry", "cavalry", "cannon", "flag"]:
		var path := "res://assets/models/%s.glb" % k
		if not _piece_scenes.has(path):
			_piece_scenes[path] = load(path) if ResourceLoader.exists(path) else null


func set_piece(side: int, kind: String, tint: Color) -> void:
	## show (or swap) a side's piece; "" clears it
	var cur: Dictionary = _pieces.get(side, {})
	if not cur.is_empty() and str(cur["kind"]) == kind and not bool(cur.get("down", false)):
		return
	if not cur.is_empty():
		(cur["node"] as Node).queue_free()
		_pieces.erase(side)
	if kind == "" or _world == null or not board:
		return
	var path := "res://assets/models/%s.glb" % kind
	if not _piece_scenes.has(path):
		_piece_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _piece_scenes[path]
	if ps == null:
		return
	var holder := Node3D.new()
	var pivot := Node3D.new() ## turns the model about its own centre
	holder.add_child(pivot)
	var model: Node3D = ps.instantiate()
	pivot.add_child(model)
	## fit it: base on the cloth, PIECE_H tall (cannon lower and longer)
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		var bb: AABB = m3.get_aabb()
		var xf: Transform3D = model.global_transform.affine_inverse() * m3.global_transform if m3.is_inside_tree() else _rel_xf(model, m3)
		bb = xf * bb
		box = bb if first else box.merge(bb)
		first = false
	if first or box.size.y <= 0.0001:
		holder.queue_free()
		return
	var want: float = PIECE_H * (0.48 if kind == "cannon" else 1.0)
	var k: float = want / box.size.y
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
	## the plinth in the side's colour
	var plinth := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.46
	cm.bottom_radius = 0.5
	cm.height = 0.08
	plinth.mesh = cm
	plinth.position.y = 0.04
	var pm := StandardMaterial3D.new()
	pm.albedo_color = tint
	pm.metallic = 0.3
	pm.roughness = 0.4
	plinth.material_override = pm
	holder.add_child(plinth)
	model.position.y += 0.08
	## beside the table, just outside its rails (the dice land on the cloth between them)
	var w: float = table_w if table_w > 0.0 else width * 0.98
	var shadow := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(1.5, 1.1)
	shadow.mesh = sm
	shadow.position.y = 0.005
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _blob_of()
	smat.albedo_color = Color(0, 0, 0, 0.65)
	shadow.material_override = smat
	holder.add_child(shadow)
	holder.position = Vector3((-1.0 if side == 0 else 1.0) * minf(w * 0.5 + 1.15, width * 0.5 - 0.8), 0.0, 0.1)
	## each faces the other side, turned a little toward us. The cannon was modelled
	## side-on (its barrel along +x); the men and the horse face +z.
	var base: float = 0.0 if kind == "cannon" else 90.0
	pivot.rotation.y = deg_to_rad(base)
	holder.rotation.y = deg_to_rad(-40.0 if side == 0 else 220.0)
	_world.add_child(holder)
	_pieces[side] = {"node": holder, "kind": kind}
	## it drops onto the table
	holder.position.y = 0.6
	var tw := holder.create_tween()
	tw.tween_property(holder, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func topple(side: int) -> void:
	## the beaten side's piece goes over
	var cur: Dictionary = _pieces.get(side, {})
	if cur.is_empty():
		return
	cur["down"] = true
	var n: Node3D = cur["node"]
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "rotation:z", (1.0 if side == 0 else -1.0) * PI * 0.47, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(n, "position:y", 0.12, 0.45)


func clear_pieces() -> void:
	for side in _pieces.keys():
		(_pieces[side]["node"] as Node).queue_free()
	_pieces = {}


static var _bumps := {}


static func _bump_of(key: String, t: Texture2D, strength: float) -> Texture2D:
	## a normal map taken from the texture's own light and dark, made once per run
	if _bumps.has(key):
		return _bumps[key]
	var img: Image = t.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > 512:
		img.resize(512, 512 * img.get_height() / img.get_width(), Image.INTERPOLATE_BILINEAR)
	img.bump_map_to_normal_map(strength)
	img.generate_mipmaps()
	var nt := ImageTexture.create_from_image(img)
	_bumps[key] = nt
	return nt


static var _vig: GradientTexture2D


static func _vignette() -> GradientTexture2D:
	if _vig != null:
		return _vig
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.0, 0.01, 0.0, 0.55))
	g.add_point(0.55, Color(0, 0, 0, 0.04))
	_vig = GradientTexture2D.new()
	_vig.gradient = g
	_vig.fill = GradientTexture2D.FILL_RADIAL
	_vig.fill_from = Vector2(0.5, 0.5)
	_vig.fill_to = Vector2(1.05, 0.5)
	_vig.width = 256
	_vig.height = 128
	return _vig


static func _blob_of() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.7, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 64
	return t


# ------------------------------------------------------------------ throwing
## v1.5: real physics. Every throw is simulated first, all dice together, as rigid cubes:
## gravity, the felt, the rails (a die flying higher than a rail clears it) and each other.
## Then each die's pips are turned (a symmetry of the cube, so the shape never changes)
## until the face that landed on top is the one the engine rolled, and the recording plays.

const SIM_DT := 1.0 / 240.0
const REC_EVERY := 4 ## a recorded pose every 4 steps: 60 a second, interpolated in between
const RAIL_H := 0.34
const MAX_SIM := 3.4
const FACE_NORMALS := {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.RIGHT, 5: Vector3.LEFT, 3: Vector3.BACK, 4: Vector3.FORWARD}
const LOCAL_AXES := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]

var arrange := true ## square the dice up into their places once they stop (the tray); false: leave them where they lie
var _end := 0.0 ## seconds (of simulation) until the last die is still
var _glide := 0.28 ## the squaring-up, after the dice stop


func clear() -> void:
	for d in _dice:
		(d["node"] as Node).queue_free()
		(d["shadow"] as Node).queue_free()
		if d.has("halo"):
			(d["halo"] as Node).queue_free()
	_dice = []
	_settled_sent = true
	queue_redraw()


func throw(specs: Array) -> float:
	## specs: [{value, n (army size, picks the tier), tint, to: Vector2 (x, z where it should
	##   end up), from: Vector3 (optional: where it leaves the hand), delay, drop (fall from above)}]
	## Returns the seconds until the last die is still (and squared up).
	clear()
	_clock = 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in specs.size():
		_dice.append(_make(specs[i], i, rng))
	_end = _simulate()
	for d in _dice:
		_fix_faces(d, rng)
		_pose(d)
	_settled_sent = false
	if not quiet and visible and not specs.is_empty():
		_sfx("dice_throw", -6.0) ## v1.10: they leave the hand
	return (_end + (_glide if arrange else 0.0)) / maxf(0.5, pace)


func settle_now() -> void:
	_clock = 999.0
	for d in _dice:
		_pose(d)


func die_screen(i: int) -> Vector2:
	## where die i ends up, in this Control's coordinates
	if i < 0 or i >= _dice.size():
		return Vector2.ZERO
	var d: Dictionary = _dice[i]
	var e: Vector3 = _rest_at(d)
	return _cam.unproject_position(e) / _px


func rail_screen(x: float) -> Vector2:
	## v1.9: the top of the front rail at table x, in this Control's coordinates (the score
	## plates hang there)
	if _cam == null:
		return Vector2.ZERO
	return _cam.unproject_position(Vector3(x, 0.3, _depth * 0.9 * 0.5 + 0.34)) / _px


func table_x(i: int) -> float:
	## where die i comes to rest across the table, in table units
	if i < 0 or i >= _dice.size():
		return 0.0
	return _rest_at(_dice[i]).x


func shown(i: int) -> int:
	## the number on top of die i as drawn at rest (the check that the pips were turned right)
	var d: Dictionary = _dice[i]
	var rq: Array = d["rec_q"]
	var q: Quaternion = (rq[-1] as Quaternion) * (d["S"] as Quaternion)
	var bs := Basis(q.normalized())
	for v in FACE_NORMALS.keys():
		if (bs * (FACE_NORMALS[v] as Vector3)).y > 0.9:
			return int(v)
	return 0


func sim_stats() -> Dictionary:
	var knocks := 0
	for d in _dice:
		knocks += (d["impacts"] as Array).size()
	return {"end": _end, "knocks": knocks}


func ground_screen(p: Vector3) -> Vector2:
	return _cam.unproject_position(p) / _px


func mark(i: int, how: String) -> void:
	## the duel is decided: the winner's die lights up, the loser's goes dark
	if i < 0 or i >= _dice.size():
		return
	var d: Dictionary = _dice[i]
	var m: ShaderMaterial = d["mat"]
	var tw := create_tween()
	match how:
		"win":
			tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 0.0, 1.0, 0.12)
			tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.35, 0.5)
			d["hop"] = _clock
		"lose":
			tw.tween_method(func(v: float): m.set_shader_parameter("dim", v), 0.0, 1.0, 0.25)
		"tie":
			tw.tween_method(func(v: float): m.set_shader_parameter("dim", v), 0.0, 0.5, 0.25)


func _make(spec: Dictionary, i: int, rng: RandomNumberGenerator) -> Dictionary:
	var tier: int = tier_for(int(spec.get("n", 5)))
	var tdef: Dictionary = TIERS[tier]
	var s: float = float(tdef["size"])
	var tint: Color = spec.get("tint", Color.WHITE)
	var node := MeshInstance3D.new()
	node.mesh = _die_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = _die_shader()
	_dress(mat, tdef, tint)
	node.material_override = mat
	_world.add_child(node)
	var shadow := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(1.9, 1.9)
	shadow.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = _blob_tex()
	sm.albedo_color = Color(0, 0, 0, 0.5)
	shadow.material_override = sm
	_world.add_child(shadow)
	## v1.6: a glow of the commander's colour on the felt under the die
	var halo := MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(2.3, 2.3)
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.albedo_texture = _blob_tex()
	hmat.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	halo.material_override = hmat
	_world.add_child(halo)
	var to: Vector2 = spec.get("to", Vector2.ZERO)
	var drop: bool = bool(spec.get("drop", false))
	var h: float = 0.5 * s
	var p0: Vector3
	var v0: Vector3
	if drop:
		p0 = Vector3(to.x + rng.randf_range(-1.2, 1.2), rng.randf_range(5.0, 6.5), to.y + rng.randf_range(-1.6, -0.6))
		var tf: float = sqrt(2.0 * p0.y / gravity)
		v0 = Vector3((to.x - p0.x) / tf * 0.6, rng.randf_range(-1.0, 0.5), (to.y - p0.z) / tf * 0.6)
	else:
		## tossed in over the far rail from its own side of the table: a short, lively throw
		## that tumbles, bounces off the felt and its neighbours, and rolls to a stop near its place
		var from: Vector3 = spec.get("from", Vector3(-1, 0, 0))
		var side: float = -1.0 if from.x < 0.0 else 1.0
		p0 = Vector3(to.x + side * rng.randf_range(0.5, 0.9), rng.randf_range(2.6, 3.3), to.y - rng.randf_range(2.0, 2.5))
		if spec.has("from_dir"):
			## the diorama: thrown in from the bearing its commander stands on
			var fd: Vector2 = (spec["from_dir"] as Vector2).normalized().rotated(rng.randf_range(-0.25, 0.25))
			var reach: float = rng.randf_range(2.6, 3.2)
			p0 = Vector3(to.x + fd.x * reach, rng.randf_range(2.4, 3.1), to.y + fd.y * reach)
		var flat := Vector2(to.x - p0.x, to.y - p0.z)
		var land: Vector2 = Vector2(p0.x, p0.z) + flat * rng.randf_range(0.72, 0.86)
		var tf2: float = rng.randf_range(0.36, 0.44)
		var lv: Vector2 = (land - Vector2(p0.x, p0.z)) / tf2
		var vy: float = (0.5 * gravity * tf2 * tf2 - (p0.y - h)) / tf2
		v0 = Vector3(lv.x, vy, lv.y)
	var q0 := Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, TAU))
	var w0: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(9.0, 17.0)
	return {"node": node, "shadow": shadow, "halo": halo, "tint": tint, "mat": mat, "s": s, "h": h, "tier": tier, "sound": str(tdef["sound"]),
		"value": clampi(int(spec.get("value", 1)), 1, 6), "E": to, "t0": float(spec.get("delay", 0.0)),
		"p": p0, "v": v0, "q": q0, "w": w0, "asleep": false, "still": 0.0, "last_knock": -1.0,
		"rec_p": [], "rec_q": [], "impacts": [], "next_impact": 0, "S": Quaternion.IDENTITY,
		"hop": -9.0, "done": false}


func _dress(m: ShaderMaterial, t: Dictionary, tint: Color) -> void:
	var seat_body: Color = tint.darkened(0.2)
	var body: Color = seat_body if typeof(t["body"]) == TYPE_STRING else t["body"]
	if t.has("stain"):
		body = body.lerp(tint.darkened(0.15), float(t["stain"])) ## wood stained in the commander's colour
	var pip: Color
	if typeof(t["pip"]) == TYPE_STRING:
		pip = tint.darkened(0.3) if str(t["pip"]) == "seat_dark" else tint.lightened(0.05)
	else:
		pip = t["pip"]
	m.set_shader_parameter("body_col", body)
	m.set_shader_parameter("pip_col", pip)
	var brass: bool = bool(t.get("brass", false))
	m.set_shader_parameter("edge_col", Color(0.86, 0.68, 0.32) if brass else tint.lightened(0.08))
	m.set_shader_parameter("edge_metal", 0.9 if brass else 0.15)
	m.set_shader_parameter("glow_col", Color(1.0, 0.85, 0.45).lerp(tint.lightened(0.3), 0.35))
	m.set_shader_parameter("edge_w", float(t.get("edge", 0.0)))
	m.set_shader_parameter("body_metal", float(t.get("metal", 0.0)))
	m.set_shader_parameter("body_rough", float(t.get("rough", 0.5)))
	m.set_shader_parameter("pip_metal", 0.0 if float(t.get("pip_glow", 0.0)) <= 0.0 else 0.3)
	m.set_shader_parameter("pip_rough", 0.25 if float(t.get("pip_glow", 0.0)) > 0.0 else 0.6)
	m.set_shader_parameter("pip_glow", float(t.get("pip_glow", 0.0)))
	m.set_shader_parameter("grain", float(t.get("grain", 0.0)))
	m.set_shader_parameter("wear", float(t.get("wear", 0.0)))
	m.set_shader_parameter("star", 1.0 if bool(t.get("star", false)) else 0.0)
	m.set_shader_parameter("dim", 0.0)
	m.set_shader_parameter("flash", 0.0)


func _simulate() -> float:
	## all the dice at once, fixed steps, until every one of them is still
	var g := Vector3(0, -gravity, 0)
	var wall_x: float = (table_w if table_w > 0.0 else width * 0.98) * 0.5 - 0.02
	var wall_z: float = (_depth * 0.9) * 0.5 - 0.02
	if not board:
		wall_x = width * 0.5 - 0.6
		wall_z = _depth * 0.5 - 0.6
	var t := 0.0
	var step := 0
	var n: int = _dice.size()
	while t < MAX_SIM:
		step += 1
		t += SIM_DT
		var awake := 0
		for d in _dice:
			if t < float(d["t0"]) or bool(d["asleep"]):
				continue
			awake += 1
			var v: Vector3 = d["v"] + g * SIM_DT
			var w: Vector3 = d["w"]
			var p: Vector3 = d["p"] + v * SIM_DT
			var q: Quaternion = d["q"]
			var wl: float = w.length()
			if wl > 0.0001:
				q = (Quaternion(w / wl, wl * SIM_DT) * q).normalized()
			d["v"] = v
			d["p"] = p
			d["q"] = q
			_contacts(d, t, wall_x, wall_z)
		## dice against dice: rounded enough to meet as spheres
		for i in n:
			var a: Dictionary = _dice[i]
			if t < float(a["t0"]):
				continue
			for j in range(i + 1, n):
				var b: Dictionary = _dice[j]
				if t < float(b["t0"]):
					continue
				_bump(a, b, t)
		## rest
		for d in _dice:
			if bool(d["asleep"]) or t < float(d["t0"]):
				continue
			var up_dot: float = _flatness(Quaternion(d["q"]))
			if (d["v"] as Vector3).length() < 0.25 and (d["w"] as Vector3).length() < 0.7 and (d["p"] as Vector3).y < float(d["h"]) * 1.08 and up_dot > 0.995:
				d["still"] = float(d["still"]) + SIM_DT
				if float(d["still"]) > 0.12:
					d["asleep"] = true
					d["q"] = _flatten(Quaternion(d["q"]))
					var pp: Vector3 = d["p"]
					d["p"] = Vector3(pp.x, float(d["h"]), pp.z)
					d["v"] = Vector3.ZERO
					d["w"] = Vector3.ZERO
			else:
				d["still"] = 0.0
		if step % REC_EVERY == 0:
			for d in _dice:
				(d["rec_p"] as Array).append(d["p"])
				(d["rec_q"] as Array).append(d["q"])
		if awake == 0 and t > _max_delay():
			break
	## anyone still going when time runs out settles over a few frames where they are
	var extra := 0
	for d in _dice:
		if not bool(d["asleep"]):
			var q_from: Quaternion = d["q"]
			var q_to: Quaternion = _flatten(q_from)
			var p_from: Vector3 = d["p"]
			var p_to := Vector3(p_from.x, float(d["h"]), p_from.z)
			for k in range(1, 9):
				var u: float = float(k) / 8.0
				(d["rec_p"] as Array).append(p_from.lerp(p_to, u))
				(d["rec_q"] as Array).append(q_from.slerp(q_to, u))
			d["q"] = q_to
			d["p"] = p_to
			extra = 8
	## everyone's recording ends together
	for d in _dice:
		var rp: Array = d["rec_p"]
		var rq: Array = d["rec_q"]
		var want: int = int(ceil(t / (SIM_DT * REC_EVERY))) + extra
		while rp.size() < want and rp.size() > 0:
			rp.append(rp[rp.size() - 1])
			rq.append(rq[rq.size() - 1])
	return t + float(extra) * SIM_DT * REC_EVERY


func _max_delay() -> float:
	var m := 0.0
	for d in _dice:
		m = maxf(m, float(d["t0"]))
	return m


func _contacts(d: Dictionary, t: float, wall_x: float, wall_z: float) -> void:
	var p: Vector3 = d["p"]
	var h: float = float(d["h"])
	var reach: float = h * 1.75
	var near_floor: bool = p.y < reach
	var near_wall: bool = absf(p.x) > wall_x - reach or absf(p.z) > wall_z - reach
	if not near_floor and not near_wall:
		return
	var basis := Basis(Quaternion(d["q"]))
	var hc: float = h * 0.94 ## the corners are rounded off
	var inv_m := 1.0
	var inv_i: float = 6.0 / (4.0 * h * h) ## a solid cube: I = m s^2 / 6
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var r: Vector3 = basis * Vector3(cx * hc, cy * hc, cz * hc)
				var c: Vector3 = d["p"] + r
				if c.y < 0.0:
					_impulse(d, r, Vector3.UP, -c.y, 0.3, 0.62, t) ## baize: grippy, a little soft
				if c.y > (RAIL_H if board else 1.5):
					continue ## flying over the rails (or, with no tray, over a low invisible fence)
				if c.x > wall_x:
					_impulse(d, r, Vector3.LEFT, c.x - wall_x, 0.45, 0.3, t)
				elif c.x < -wall_x:
					_impulse(d, r, Vector3.RIGHT, -wall_x - c.x, 0.45, 0.3, t)
				if c.z > wall_z:
					_impulse(d, r, Vector3.FORWARD, c.z - wall_z, 0.45, 0.3, t)
				elif c.z < -wall_z:
					_impulse(d, r, Vector3.BACK, -wall_z - c.z, 0.45, 0.3, t)


func _impulse(d: Dictionary, r: Vector3, n: Vector3, depth: float, e: float, mu: float, t: float) -> void:
	## one corner against a plane: a restitution impulse, then friction, then push it out
	var h: float = float(d["h"])
	var inv_i: float = 6.0 / (4.0 * h * h)
	var v: Vector3 = d["v"]
	var w: Vector3 = d["w"]
	var vc: Vector3 = v + w.cross(r)
	var vn: float = vc.dot(n)
	d["p"] = (d["p"] as Vector3) + n * depth * 0.5
	if vn >= 0.0:
		return
	var rn: Vector3 = r.cross(n)
	var k: float = 1.0 + rn.length_squared() * inv_i
	var bounce: float = e if vn < -1.2 else 0.0 ## slow contacts just stop: no jitter at rest
	var jn: float = -(1.0 + bounce) * vn / k
	v += n * jn
	w += rn * (jn * inv_i)
	## friction against the sliding
	vc = v + w.cross(r)
	var vt: Vector3 = vc - n * vc.dot(n)
	var vtl: float = vt.length()
	if vtl > 0.0001:
		var tdir: Vector3 = vt / vtl
		var rt: Vector3 = r.cross(tdir)
		var kt: float = 1.0 + rt.length_squared() * inv_i
		var jt: float = minf(vtl / kt, mu * jn)
		v -= tdir * jt
		w -= rt * (jt * inv_i)
	d["v"] = v
	d["w"] = w * 0.999
	if jn > 0.9 and t - float(d["last_knock"]) > 0.05:
		d["last_knock"] = t
		(d["impacts"] as Array).append([t, clampf(jn / 5.0, 0.12, 1.0)])


func _bump(a: Dictionary, b: Dictionary, t: float) -> void:
	var pa: Vector3 = a["p"]
	var pb: Vector3 = b["p"]
	var ra: float = float(a["h"]) * 1.12
	var rb: float = float(b["h"]) * 1.12
	var dvec: Vector3 = pb - pa
	var dist: float = dvec.length()
	if dist >= ra + rb or dist < 0.0001:
		return
	var sa: bool = bool(a["asleep"])
	var sb: bool = bool(b["asleep"])
	if sa and sb:
		return
	var n: Vector3 = dvec / dist
	var rel: Vector3 = (b["v"] as Vector3) - (a["v"] as Vector3)
	var vn: float = rel.dot(n)
	## a die at rest is a wall unless it's hit hard; only a real knock wakes it
	if (sa or sb) and vn > -1.0:
		var over: float = ra + rb - dist
		if sa:
			b["p"] = pb + n * over
			if vn < 0.0:
				b["v"] = (b["v"] as Vector3) - n * (1.3 * vn)
		else:
			a["p"] = pa - n * over
			if vn < 0.0:
				a["v"] = (a["v"] as Vector3) + n * (1.3 * vn)
		return
	var push: float = (ra + rb - dist) * 0.5
	a["p"] = pa - n * push
	b["p"] = pb + n * push
	if vn >= 0.0:
		return
	a["asleep"] = false
	b["asleep"] = false
	var j: float = -(1.0 + 0.4) * vn * 0.5
	a["v"] = (a["v"] as Vector3) - n * j
	b["v"] = (b["v"] as Vector3) + n * j
	## a glancing knock sets them spinning
	var tang: Vector3 = rel - n * vn
	a["w"] = (a["w"] as Vector3) + n.cross(tang) * 0.35
	b["w"] = (b["w"] as Vector3) - n.cross(tang) * 0.35
	if j > 0.8:
		for d in [a, b]:
			if t - float(d["last_knock"]) > 0.05:
				d["last_knock"] = t
				(d["impacts"] as Array).append([t, clampf(j / 4.0, 0.15, 1.0)])


func _flatness(q: Quaternion) -> float:
	var bs := Basis(q)
	return maxf(absf(bs.x.y), maxf(absf(bs.y.y), absf(bs.z.y)))


func _up_axis(q: Quaternion) -> Vector3:
	## the die's own axis that points most nearly up
	var bs := Basis(q)
	var best: Vector3 = Vector3.UP
	var bd := -2.0
	for a in LOCAL_AXES:
		var dd: float = (bs * a).y
		if dd > bd:
			bd = dd
			best = a
	return best


func _flatten(q: Quaternion) -> Quaternion:
	## the nearest pose that sits flat on a face
	var a: Vector3 = _up_axis(q)
	var world_a: Vector3 = (Basis(q) * a).normalized()
	var fix: Quaternion = Quaternion(world_a, Vector3.UP) if world_a.dot(Vector3.UP) < 0.99999 else Quaternion.IDENTITY
	return (fix * q).normalized()


func _fix_faces(d: Dictionary, rng: RandomNumberGenerator) -> void:
	## turn the pips (a symmetry of the cube) so the face that landed on top shows the roll
	var rec: Array = d["rec_q"]
	var q_end: Quaternion = rec[-1] if not rec.is_empty() else Quaternion(d["q"])
	var n_body: Vector3 = _up_axis(q_end)
	var f_v: Vector3 = FACE_NORMALS[int(d["value"])]
	var sym: Quaternion
	if f_v.is_equal_approx(n_body):
		sym = Quaternion.IDENTITY
	elif f_v.is_equal_approx(-n_body):
		var perp: Vector3 = Vector3.RIGHT if absf(f_v.x) < 0.5 else Vector3.UP
		sym = Quaternion(perp, PI)
	else:
		sym = Quaternion(f_v.cross(n_body).normalized(), PI * 0.5)
	var twist := Quaternion(n_body, float(rng.randi_range(0, 3)) * PI * 0.5)
	d["S"] = (twist * sym).normalized()


func _rest_at(d: Dictionary) -> Vector3:
	var rp: Array = d["rec_p"]
	var last: Vector3 = rp[rp.size() - 1] if rp.size() > 0 else (d["p"] as Vector3)
	if arrange:
		var e: Vector2 = d["E"]
		return Vector3(e.x, last.y, e.y)
	return last


func _pose(d: Dictionary) -> void:
	var node: MeshInstance3D = d["node"]
	var shadow: MeshInstance3D = d["shadow"]
	var t: float = _clock
	if t < float(d["t0"]):
		node.visible = false
		shadow.visible = false
		return
	node.visible = true
	shadow.visible = true
	var rp: Array = d["rec_p"]
	var rq: Array = d["rec_q"]
	var frames: int = rp.size()
	if frames == 0:
		return
	var rec_dt: float = SIM_DT * REC_EVERY
	var f: float = t / rec_dt - 1.0
	var pos: Vector3
	var q: Quaternion
	if f >= float(frames - 1):
		pos = rp[frames - 1]
		q = rq[frames - 1]
		if arrange:
			## the dealer squares them up into their places
			var u: float = clampf((t - _end) / _glide, 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			pos = pos.lerp(_rest_at(d), u)
		d["done"] = t >= _end + (_glide if arrange else 0.0)
	elif f <= 0.0:
		pos = rp[0]
		q = rq[0]
	else:
		var i0: int = int(floor(f))
		var k: float = f - float(i0)
		pos = (rp[i0] as Vector3).lerp(rp[i0 + 1], k)
		q = (rq[i0] as Quaternion).slerp(rq[i0 + 1], k)
	var hop: float = _clock - float(d["hop"])
	var lift: float = 0.35 * sin(clampf(hop / 0.3, 0.0, 1.0) * PI) if hop < 0.3 else 0.0
	var s: float = float(d["s"])
	var basis := Basis((q * (d["S"] as Quaternion)).normalized())
	node.transform = Transform3D(basis.scaled(Vector3.ONE * s), pos + Vector3(0, lift, 0))
	var hgt: float = maxf(0.0, pos.y - float(d["h"])) + lift
	shadow.position = Vector3(pos.x + hgt * 0.18, 0.012, pos.z + hgt * 0.1)
	shadow.visible = not board or absf(shadow.position.x) < (table_w if table_w > 0.0 else width) * 0.49
	var sc: float = s * (1.0 + hgt * 0.12)
	shadow.scale = Vector3(sc, 1, sc)
	(shadow.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, clampf(0.55 - hgt * 0.07, 0.12, 0.55))
	if d.has("halo"):
		var halo: MeshInstance3D = d["halo"]
		halo.visible = shadow.visible
		halo.position = Vector3(pos.x, 0.018, pos.z)
		halo.scale = Vector3(s, 1, s)
		var tint: Color = d["tint"]
		(halo.material_override as StandardMaterial3D).albedo_color = Color(tint.r, tint.g, tint.b, clampf(0.7 - hgt * 0.25, 0.0, 0.7))
	## knocks on the table, as the recording passes them
	var ni: int = int(d["next_impact"])
	var imps: Array = d["impacts"]
	while ni < imps.size() and t >= float(imps[ni][0]):
		_knock(d, float(imps[ni][1]))
		ni += 1
	d["next_impact"] = ni


func _sfx(name: String, db: float) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio != null:
		audio.sfx(name, db, 0.08)


func _knock(d: Dictionary, strength: float) -> void:
	if quiet or not visible:
		return
	var snd: String = str(d["sound"])
	var now: float = _clock
	if now - float(_knock_at.get(snd, -1.0)) < 0.035:
		return
	_knock_at[snd] = now
	var audio: Node = get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("knock"):
		audio.knock(snd, strength)


# ------------------------------------------------------------------ assets made here

static func _die_shader() -> Shader:
	if _shader == null:
		_shader = load("res://game/ui/dice.gdshader")
	return _shader


static func _blob_tex() -> GradientTexture2D:
	if _blob == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.75))
		_blob = GradientTexture2D.new()
		_blob.gradient = g
		_blob.fill = GradientTexture2D.FILL_RADIAL
		_blob.fill_from = Vector2(0.5, 0.5)
		_blob.fill_to = Vector2(1.0, 0.5)
		_blob.width = 64
		_blob.height = 64
	return _blob


static func _die_mesh() -> ArrayMesh:
	## a unit cube with rounded edges: a subdivided box whose points are pulled onto a
	## sphere of radius R around the inner box
	if _mesh != null:
		return _mesh
	const N := 7
	const R := 0.12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.UP, Vector3.RIGHT], [Vector3.FORWARD, Vector3.DOWN, Vector3.RIGHT],
	]
	var inner := 0.5 - R
	for fdef in faces:
		var nrm: Vector3 = fdef[0]
		var eu: Vector3 = fdef[1]
		var ev: Vector3 = fdef[2]
		var grid: Array = []
		for j in N + 1:
			for i in N + 1:
				var a: float = float(i) / N - 0.5
				var b: float = float(j) / N - 0.5
				var p: Vector3 = nrm * 0.5 + eu * a + ev * b
				var c := Vector3(clampf(p.x, -inner, inner), clampf(p.y, -inner, inner), clampf(p.z, -inner, inner))
				var dirv: Vector3 = p - c
				var n: Vector3 = dirv.normalized() if dirv.length() > 0.0001 else nrm
				grid.append([c + n * R, n])
		for j in N:
			for i in N:
				var k0: int = j * (N + 1) + i
				var quad := [grid[k0], grid[k0 + 1], grid[k0 + N + 2], grid[k0 + N + 1]]
				for tri in [[0, 1, 2], [0, 2, 3]]:
					for idx in tri:
						st.set_normal(quad[idx][1])
						st.add_vertex(quad[idx][0])
	_mesh = st.commit()
	return _mesh
