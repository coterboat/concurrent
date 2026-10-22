## The map's land in 3D (v2.0): one world a game, built in the background when its map loads.
## The board looks at it when it stands on the land (LandBoard), and the battles fight on it
## (LandField), through the same camera: a battle tips down out of whatever the board shows and
## rises back to it. One SubViewport at the screen's real resolution, drawn only while someone
## shows it; whoever shows it draws its texture.
extends Node

const Terrain := preload("res://game/world3d/terrain.gd")
const WorldView := preload("res://game/world3d/world_view.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Scenery := preload("res://game/world3d/scenery.gd")
const Marches := preload("res://game/world3d/marches.gd")
const DiceStage := preload("res://game/ui/dice_stage.gd")

signal built

var board: Control
var view: Control ## land_board.gd, when the board can stand on the land
var prepared := false ## the world is built
var wv: Node3D ## world_view.gd
var battle: Node3D ## diorama.gd: a battle's armies
var garrisons: Node3D ## diorama.gd: every held land's men, on the board
var scenery: Node3D ## scenery.gd: villages, landmarks, forts, palaces, ships
var marches: Node3D ## marches.gd: the report's columns on the march
var px := 1.0 ## physical pixels per screen pixel
var driver := "" ## who moves the camera: "board" or "battle"
var quiet := false
var _vp: SubViewport
var _task := -1 ## the build this land will stand on
var _out := {} ## ...which hands its terrain over here, never into this node (v2.3)
var _warm: Array = [] ## v2.4: what its battles will want, loaded with it (warm_list), held so it stays at hand
var _replaced: Array[int] = [] ## v2.3: builds a newer one replaced, still running: each is waited for too
static var builds_open := 0 ## v2.3: builds started and not yet waited for, in every land (probe v23b)
var _terrain: RefCounted
var _art: RefCounted
var _map: RefCounted
var _state_tex: Texture2D
var _shown := {} ## who is drawing it: "board", "battle"
var quality := 0 ## 0 everything; each step gives up the dearest of what's left (a slower machine)
var _slow := 0.0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA ## (Compatibility has none: Linux without Vulkan)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true) ## v2.4: _land_heavy


func texture() -> Texture2D:
	return _vp.get_texture()


func fit(screen: Vector2, scale: float) -> void:
	## the viewport at the screen's size, in physical pixels
	px = clampf(scale, 1.0, 3.0)
	var want := Vector2i(int(screen.x * px), int(screen.y * px))
	if want.x > 4 and want.y > 4 and _vp.size != want:
		_vp.size = want


func show_for(who: String, on: bool) -> void:
	if on:
		_shown[who] = true
	else:
		_shown.erase(who)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if not _shown.is_empty() else SubViewport.UPDATE_DISABLED


func shown() -> bool:
	return not _shown.is_empty()


# ------------------------------------------------------------------ built once a game

func prepare(p_board: Control) -> void:
	## Start building this map's land in the background (a second or two, off the main thread);
	## the world itself is made when it's done. Called when a game's map is loaded.
	board = p_board
	if board == null or board.art == null:
		return
	if _art == board.art and (prepared or _task >= 0):
		return
	prepared = false
	_art = board.art
	_map = board.map
	_state_tex = board.get("_state_tex")
	var art = _art
	var map = _map
	_terrain = null
	## v2.3: another map asked for while a build still runs: that build is kept to be waited for,
	## never dropped. A task nobody waits for lives until Godot shuts down and is freed after
	## GDScript has gone, with the map it holds: signal 11 at exit (a war left in its first second
	## for a war on another map, then the game closed)
	if _task >= 0:
		_replaced.append(_task)
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func():
		var t: RefCounted = Terrain.build(art, map, 3)
		t.scenery = Scenery.plan(art, map, t)
		for spec in t.scenery:
			if str(spec["kind"]) == "starfort":
				t.level(art, str(spec["land"]), spec["at"], float(spec["foot"]) * 0.5) ## v2.4: a fort on level ground
		t.scenery_scenes = Scenery.load_all(t.scenery)
		out["warm"] = warm_list()
		out["terrain"] = t, false, "the land of " + str(art.id))
	builds_open += 1


static func warm_list() -> Array:
	## v2.4: what a battle on the land loads the first time it wants it, loaded with the land instead,
	## off the main thread, and held: the figures' models (the dice tray's pieces among them), the
	## figures', streaks' and dice's shaders, the sounds of the field and the charge. Each was a hitch
	## on the main thread, mid-battle or as the battlefield opened (the dice pieces: 100 ms of its first frame)
	var out: Array = []
	for k in Diorama.MODELS.keys():
		var path: String = Diorama.MODELS[k][0]
		if ResourceLoader.exists(path):
			out.append(load(path))
	for path in ["res://game/ui/dice.gdshader", "res://game/world3d/tin.gdshader", "res://game/world3d/tracer.gdshader"]:
		if ResourceLoader.exists(path):
			out.append(load(path))
	for dir in ["res://assets/audio/sfx/", "res://assets/audio/music/"]:
		for f in ResourceLoader.list_directory(dir):
			if f.get_extension() in ["mp3", "wav", "ogg"] and (dir.ends_with("sfx/") or f.begins_with("charge")):
				out.append(load(dir + f))
	return out


func busy() -> bool:
	return _task >= 0


func building() -> String:
	## the map this land is built (or being built) for
	return str(_art.id) if _art != null else ""


func _wait(id: int) -> void:
	WorkerThreadPool.wait_for_task_completion(id)
	builds_open -= 1


func _notification(what: int) -> void:
	## v2.0.2: freed while its land is still being built (a game closed in its first second or two):
	## the build finishes first. v2.3: and any build it replaced (see prepare())
	if what == NOTIFICATION_PREDELETE:
		for id in _replaced:
			_wait(id)
		_replaced.clear()
		if _task >= 0:
			_wait(_task)
			_task = -1


func _process(delta: float) -> void:
	for id in _replaced.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			_wait(id)
			_replaced.erase(id)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_wait(_task)
		_task = -1
		_terrain = _out.get("terrain")
		_warm = _out.get("warm", [])
		DiceStage.warm_pieces() ## (loaded already: the dice tray takes them from here)
		_build_world()
	if prepared and shown():
		_watch_speed(delta)


func _watch_speed(delta: float) -> void:
	## On a slower machine the land gives up its dearest effects, a step at a time, until it runs
	## smoothly: under 40 frames a second for a few seconds together, and down a step it goes.
	if quality >= 4:
		return
	if delta > 1.0 / 40.0 and _land_heavy(delta):
		_slow += delta
	else:
		_slow = maxf(0.0, _slow - delta * 0.5)
	if _slow > 3.0:
		_slow = 0.0
		set_quality(quality + 1)


func _land_heavy(delta: float) -> bool:
	## v2.4: a slow frame counts against the land only when drawing the land is a good share of it.
	## The board on the land was slow for its 2D drawing (the board's tokens and labels), and the land
	## gave up its shadows and its sharpness for nothing: down to its last step by the second battle,
	## on an RTX 3070 drawing it in 2 to 5 ms. (The Compatibility renderer has no timings: as before.)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return true
	var rid: RID = _vp.get_viewport_rid()
	var ms: float = maxf(RenderingServer.viewport_get_measured_render_time_gpu(rid), RenderingServer.viewport_get_measured_render_time_cpu(rid))
	return ms > delta * 1000.0 * 0.35


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 4)
	if wv == null:
		return
	wv.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality < 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	wv.env.ssao_enabled = quality < 1
	for mi in wv.props.get_children():
		if mi is GeometryInstance3D:
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.msaa_3d = Viewport.MSAA_2X if quality < 2 else Viewport.MSAA_DISABLED
	wv.sun.shadow_enabled = quality < 3
	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_vp.scaling_3d_scale = 1.0 if quality < 4 else 0.7


func wait_ready() -> bool:
	## the land is ready (waits for the background build, a frame at a time)
	var guard := 0
	while not prepared and _task >= 0 and guard < 900:
		await get_tree().process_frame
		guard += 1
	return prepared


func _build_world() -> void:
	if _terrain == null:
		return
	if wv != null:
		wv.queue_free()
	prepared = false
	wv = WorldView.new()
	_vp.add_child(wv)
	wv.setup(_art, _map, _state_tex, _terrain)
	scenery = Scenery.new()
	scenery.wv = wv
	wv.add_child(scenery)
	scenery.build()
	wv.scenery = scenery
	wv.relief = wv.relief
	garrisons = Diorama.new()
	garrisons.wv = wv
	garrisons.extras = false
	garrisons.quiet = true
	garrisons.size_mult = 2.4
	wv.add_child(garrisons)
	battle = Diorama.new()
	battle.wv = wv
	battle.quiet = quiet
	wv.add_child(battle)
	marches = Marches.new()
	marches.wv = wv
	marches.kit = garrisons
	wv.add_child(marches)
	prepared = true
	built.emit()


# ------------------------------------------------------------------ what the camera sees

func project(p: Vector2, lift: float = 0.0) -> Vector2:
	## a map point on the land, to screen pixels (of whoever draws the land full screen)
	## v2.3: height_at(), which is flat while a new map's land is still being built (a board drawn in
	## that moment asked a null terrain: "Nonexistent function 'height_at' in base 'Nil'")
	var v := Vector3(p.x, height_at(p) * wv.relief + lift, p.y)
	if wv.cam.is_position_behind(v):
		return Vector2(-99999, -99999)
	return wv.cam.unproject_position(v) / px


func unproject(s: Vector2) -> Vector2:
	## a ray from the eye through a screen point, onto the ground (refined over the hills)
	var o: Vector3 = wv.cam.project_ray_origin(s * px)
	var d: Vector3 = wv.cam.project_ray_normal(s * px)
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	var hgt := 0.0
	var q := Vector3.ZERO
	for i in 6:
		q = o + d * ((hgt - o.y) / d.y)
		hgt = height_at(Vector2(q.x, q.z)) * wv.relief
	return Vector2(q.x, q.z)


func height_at(p: Vector2) -> float:
	return _terrain.height_at(p) if _terrain != null else 0.0


func state() -> Dictionary:
	## how the land looks now: what a camera move starts from
	return {"relief": wv.relief, "realism": wv.realism, "paint": wv.paint, "fog": wv.fog_k,
		"sun": wv.sun.basis.z} ## toward the sun (aim_sun looks the light down the other way)


func apply_state(s: Dictionary) -> void:
	wv.relief = float(s["relief"])
	wv.realism = float(s["realism"])
	wv.paint = float(s["paint"])
	wv.fog_k = float(s["fog"])
	wv.aim_sun((s["sun"] as Vector3).normalized())
