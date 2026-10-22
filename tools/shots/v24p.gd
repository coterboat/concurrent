## v2.4 (v24-3d): down to a battle on the land and back, without the chug. The owner: "the zoom in
## between the main map and battle map on 3d absolutely chugs" (on an RTX 3070). tools/study/swoop.gd
## timed it: the board's 2D overlay, drawn through the land's camera, took up to a third of a second a
## frame and went on drawing, unseen, under the battlefield through the whole fight; the battle
## camera's search took 35-50 ms of the frame the battlefield opened; a battle's dice pieces, sounds
## and earthworks were loaded from disk the first time they were wanted. Facts that hold on any
## machine (the bot's box draws a frame a second, so no timings):
##   - while the land covers the screen the board under it isn't drawn
##   - the battle camera's quick sight test agrees with the full one at every yaw and pitch it tries
##   - nothing the 3D needs (models, shaders, the field's sounds) is loaded from disk during a battle,
##     the first or the next, once the land is built
##   - the second battle stands on the first one's figures, none made afresh
##   - no pipeline is compiled in the second battle's swoops
##   - a musket's streak is a thin ribbon facing the camera, its tail never behind the muzzle
## And (the owner: "when a fort exists in a territory... have the defending army defending from
## within/outside the fort against the direction(s) of the foe(s) they're facing") a fight at a fort
## is at its walls: the fort stays on the table, on level ground; each defending group lines the
## wall that faces its column, its men outside the walls and its commander inside; the camera takes
## the fort in.
##   SHOT_DIR=/dir ./scripts/shot.sh v24p
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Scenery := preload("res://game/world3d/scenery.gd")

var p
var _watch: PackedStringArray = PackedStringArray() ## what a battle on the land must find loaded already
var _cached := {}
var _covered_draws := 0 ## the board's overlay, drawn while the land covered it
var _covered_frames := 0


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = false
	_list("res://assets/models", ["glb"])
	_list("res://game", ["gdshader"])
	_list("res://assets/audio/sfx", ["mp3", "wav", "ogg"])
	_list("res://assets/battle", ["webp", "png"]) ## (told, not held against the 3D: the battle's own)
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/marches18.json", "seed": 24, "length": "standard", "timer": 0, "open_sheets": true, "deal": "random",
		"seats": [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await _to_planning(s, gs)
	var lf: Control = gs.theater._land_field
	var guard := 0
	while not (lf.prepared and gs.land_board.active() and gs.land_board.settled()) and guard < 3000:
		guard += 1
		await p.frames(1)
	p.ok(lf.prepared and gs.land_board.active(), "the land is built and the board stands on it (%d frames)" % guard)
	gs.board.overlay.draw.connect(func():
		if lf.covering:
			_covered_draws += 1)
	await p.frames(10)
	for a in _watch:
		_cached[a] = ResourceLoader.has_cached(a)
	var used: Array = []
	var first: Dictionary = await _battle(s, gs, _pick(s, gs, used), "01")
	await _to_planning(s, gs)
	var second: Dictionary = await _battle(s, gs, _pick(s, gs, used), "02")
	await _to_planning(s, gs)
	Settings.data["roll_yourself"] = true ## (the fort is photographed before the first throw)
	var third: Dictionary = await _battle(s, gs, ["blackford", "coldwater", "redgate"], "03")
	## the fort
	var ft: Dictionary = third.get("fort", {})
	p.ok(not ft.is_empty() and bool(ft["kept"]), "at a fort the fort stays on the table (Redgate's)")
	p.ok(not ft.is_empty() and float(ft["fall"]) < 1.0, "on level ground (%.1f of fall under its walls)" % float(ft.get("fall", -1.0)))
	p.ok(not ft.is_empty() and int(ft["groups"]) == 2 and int(ft["lined"]) == int(ft["groups"]),
		"each defending group lines the wall that faces its column (%d of %d)" % [ft.get("lined", 0), ft.get("groups", 0)])
	p.ok(not ft.is_empty() and int(ft["men"]) > 0 and int(ft["outside"]) == int(ft["men"]), "its men stand outside the walls (%d of %d)" % [ft.get("outside", 0), ft.get("men", 0)])
	p.ok(not ft.is_empty() and bool(ft["general_in"]), "and its commander inside them")
	p.ok(not ft.is_empty() and bool(ft["framed"]), "the camera takes the fort in (between the words and the dice)")
	## the board under the land
	p.ok(_covered_frames > 0 and _covered_draws == 0,
		"while the land covers the screen the board under it isn't drawn (%d draws in %d frames covered)" % [_covered_draws, _covered_frames])
	p.ok(gs.board.overlay.visible, "and it is drawn again once the land has gone")
	## nothing loaded mid-battle
	for b in [first, second, third]:
		p.ok((b["loads"] as Array).is_empty(), "battle %s: nothing the 3D needs is loaded from disk during it (%s)" % [b["tag"], ", ".join(b["loads"]) if not (b["loads"] as Array).is_empty() else "none"])
		if not (b["other"] as Array).is_empty():
			p.log("battle %s also loaded (the battle's own, not the 3D's): %s" % [b["tag"], ", ".join(b["other"])])
	## the figures, and the field, the same
	var made: Dictionary = first["nodes"]
	var again := 0
	for id in second["nodes"].keys():
		if made.has(id):
			again += 1
	p.ok(second["nodes"].size() > 0 and again == second["nodes"].size(),
		"the second battle stands on the first one's figures (%d of %d)" % [again, second["nodes"].size()])
	p.ok(first["dio"] != null and first["dio"] == second["dio"], "on the same battlefield (the land's own)")
	p.ok(int(second["pipelines"]) == 0, "no pipeline is compiled in the second battle's swoops (%d)" % int(second["pipelines"]))
	## the camera's search
	for b in [first, second, third]:
		p.ok(int(b["sight_tried"]) > 0 and int(b["sight_off"]) == 0, "battle %s: the camera's quick sight test agrees with the full one (%d tried, %d off)" % [b["tag"], b["sight_tried"], b["sight_off"]])
	## the streaks
	var st: Dictionary = first["streaks"]
	for k in ["seen", "ribbon", "behind"]:
		st[k] = int(st[k]) + int(second["streaks"][k])
	st["widest"] = maxf(float(st["widest"]), float(second["streaks"]["widest"]))
	p.ok(int(st["seen"]) > 0, "musket balls are seen to fly (%d streaks)" % int(st["seen"]))
	p.ok(int(st["seen"]) > 0 and int(st["ribbon"]) == int(st["seen"]), "each a ribbon facing the camera, not a cone (%d of %d)" % [st["ribbon"], st["seen"]])
	p.ok(int(st["seen"]) > 0 and float(st["widest"]) <= Diorama.FIG * 0.06, "thin: %.2f across at the ball (it was %.2f)" % [st["widest"], Diorama.FIG * 0.15])
	p.ok(int(st["seen"]) > 0 and int(st["behind"]) == 0, "its tail never reaching back past the muzzle (%d did)" % st["behind"])
	main.queue_free()
	await p.frames(5)


func _list(dir: String, exts: Array) -> void:
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with("/"):
			_list(dir + "/" + f.trim_suffix("/"), exts)
		elif f.get_extension() in exts:
			_watch.append(dir + "/" + f)


func _loaded() -> Array:
	## what has come into the cache since the last look (the watched assets)
	var out: Array = []
	for a in _watch:
		var c: bool = ResourceLoader.has_cached(a)
		if c and not bool(_cached.get(a, false)):
			out.append(a.get_file())
		_cached[a] = c
	return out


func _pipelines() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) + int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))


func _pick(s: Node, gs: Control, used: Array) -> Array:
	## a land of Dad's beside one of Varek's, over a land border, neither a fort nor a pass
	var lf: Control = gs.theater._land_field
	for id in gs.board.art.order:
		if MapLib.has_trait(s.map, id, "fort") or MapLib.has_trait(s.map, id, "pass") or used.has(id):
			continue
		for nb in MapLib.neighbors(s.map, id):
			if used.has(nb) or MapLib.has_trait(s.map, nb, "fort") or MapLib.has_trait(s.map, nb, "pass"):
				continue
			if lf.wv.terrain.crossing(nb, id) != null:
				used.append(id)
				used.append(str(nb))
				return [id, str(nb)]
	return []


func _to_planning(s: Node, gs: Control) -> void:
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 3000:
		guard += 1
		match s.phase:
			Session.Phase.RECAP:
				gs.recap.visible = false
				s.next_round()
			Session.Phase.OPENING:
				s.auto_deploy()
				s.lock()
			Session.Phase.MANEUVER:
				s.lock()
			Session.Phase.CINEMA:
				if gs.cinema.visible and not gs.cinema._waiting:
					gs.cinema.skip()
		await p.frames(2)


func _battle(s: Node, gs: Control, pair: Array, tag: String) -> Dictionary:
	var th: Control = gs.theater
	var lf: Control = th._land_field
	var out := {"tag": tag, "loads": [], "other": [], "nodes": {}, "pipelines": 0, "sight_tried": 0, "sight_off": 0,
		"streaks": {"seen": 0, "ribbon": 0, "widest": 0.0, "behind": 0}, "dio": null}
	if pair.size() < 2:
		p.fail("battle %s: no two lands to fight over" % tag)
		return out
	var w: Types.World = s.world
	var to: String = pair[pair.size() - 1]
	var froms: Array = pair.slice(0, pair.size() - 1)
	for f in froms:
		w.set_hex(f, "red", 16 if froms.size() == 1 else 12, 1)
	w.set_hex(to, "blue", 7 if froms.size() == 1 else 10, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	for f in froms:
		var err: String = s.set_attack(f, to, 15 if froms.size() == 1 else 11)
		p.ok(err == "", "battle %s: Dad marches from %s on %s %s" % [tag, f, to, err])
	_loaded() ## (what the board loaded meanwhile is not the battle's)
	s.lock()
	s.lock()
	var fought := false ## its fight has begun: what follows its opening is its closing
	var placed := false
	var shot := {}
	var seen_tr := {}
	var pc := _pipelines()
	var guard := 0
	var tail := 0
	var calling := 0
	while guard < 20000:
		guard += 1
		var fight: bool = th.visible and str(th._state) != "idle"
		if fight:
			fought = true
		## the swoops: the board's in, the land tipping up and down, the board's back
		var swoop: bool = not fight and (gs.cinema._waiting or th.visible or lf.visible or (fought and gs.board._back_tw != null and gs.board._back_tw.is_valid() and gs.board._back_tw.is_running()))
		var now := _pipelines()
		if swoop:
			out["pipelines"] = int(out["pipelines"]) + now - pc
		pc = now
		if lf.covering:
			_covered_frames += 1
		for f in _loaded():
			(out["loads"] as Array).append(f)
		if th.visible and lf.dio != null and not (lf.dio.armies as Array).is_empty():
			out["dio"] = lf.dio
			if not placed or tag == "01":
				## the first battle: every figure it ever stood up; the next: those it opens with
				for f in lf.dio.figs:
					out["nodes"][(f["node"] as Node).get_instance_id()] = true
			if not placed:
				placed = true
				_sight(lf, out)
				if not lf._fort.is_empty():
					out["fort"] = _fort_facts(lf)
					var wait := 0
					while wait < 600 and lf.dio.figs.any(func(f): return str(f["state"]) in ["new", "march", "boat"]):
						wait += 1
						await p.frames(1)
					await p.frames(20)
					await snap("v24p_%s_04_at_the_fort" % tag)
			_streaks(lf, out["streaks"], seen_tr)
			if tag == "01" and not shot.has("volley") and (lf.dio.tracers as Array).filter(func(t): return not bool(t["gun"]) and is_instance_valid(t["node"]) and (t["node"] as Node3D).visible).size() >= 3:
				shot["volley"] = true
				await snap("v24p_%s_02_volley" % tag)
			match str(th._state):
				"ready":
					if th.manual:
						th.press()
				"call":
					calling += 1
					if calling > 20:
						calling = 0
						th._answer("p")
				"done":
					th.press()
		elif gs.cinema.visible and not gs.cinema._waiting:
			if fought:
				tail += 1
				if tail > 30:
					break
			elif gs.cinema._wait > 0.3:
				gs.cinema._wait = 0.3
		elif gs.cinema._waiting and not th.visible and not shot.has("swoop"):
			shot["swoop"] = true
			await p.frames(6)
			await snap("v24p_%s_01_swoop" % tag)
		elif not gs.cinema.visible and s.phase != Session.Phase.CINEMA and s.phase != Session.Phase.RESOLVING:
			break
		await p.frames(1)
	await snap("v24p_%s_03_board_again" % tag)
	## a load that isn't the 3D's (the battle's own backdrop) is told, not held against it
	var mine: Array = []
	for f in out["loads"]:
		if str(f).get_extension() in ["glb", "gdshader", "mp3", "wav", "ogg"]:
			mine.append(f)
		else:
			(out["other"] as Array).append(f)
	out["loads"] = mine
	return out


func _streaks(lf: Control, st: Dictionary, seen: Dictionary) -> void:
	for tr in lf.dio.tracers:
		if bool(tr["gun"]) or not is_instance_valid(tr["node"]):
			continue
		var mi: MeshInstance3D = tr["node"]
		var key: int = mi.get_instance_id()
		if float(tr["t"]) <= 0.0 or not mi.visible or seen.has(key):
			continue
		seen[key] = true
		st["seen"] = int(st["seen"]) + 1
		var mat: ShaderMaterial = mi.material_override as ShaderMaterial
		if mi.mesh is QuadMesh and mat != null and mat.shader != null and mat.shader.resource_path.ends_with("tracer.gdshader"):
			st["ribbon"] = int(st["ribbon"]) + 1
		var sk: Array = lf.dio.streak_of(tr)
		st["widest"] = maxf(float(st["widest"]), float(sk[2]))
		var dir: Vector3 = ((tr["to"] as Vector3) - (tr["from"] as Vector3)).normalized()
		if ((sk[0] as Vector3) - (tr["from"] as Vector3)).dot(dir) < -0.05:
			st["behind"] = int(st["behind"]) + 1


func _fort_facts(lf: Control) -> Dictionary:
	## the fight at the fort, as the armies are placed (where every man is going to stand)
	var fort: Dictionary = lf._fort
	var at: Vector2 = fort["at"]
	var r: float = float(fort["r"])
	var t = lf.wv.terrain
	var lo := 1.0e9
	var hi := -1.0e9
	for j in 17:
		var q: Vector2 = at if j == 16 else at + Vector2(cos(float(j) * TAU / 16.0), sin(float(j) * TAU / 16.0)) * r * (0.45 if j % 2 == 0 else 0.85)
		lo = minf(lo, t.height_at(q))
		hi = maxf(hi, t.height_at(q))
	var dio: Node3D = lf.dio
	var di: int = dio.armies.size() - 1
	var lined := 0
	var groups: Array = dio.armies[di]["groups"]
	for dg in groups:
		var foe: int = int(dg.get("foe", -1))
		if foe < 0 or foe >= di:
			continue
		var col: Vector2 = dio.armies[foe]["groups"][0]["at"]
		var d: Vector2 = (dg["at"] as Vector2) - at
		var c: Vector2 = col - at
		## at the wall (not off across the field), facing its column, the column further out the same way
		if d.length() > r * 0.85 and d.length() < r * 0.85 + Diorama.FIG * 3.0 and (dg["dir"] as Vector2).dot(c.normalized()) > 0.95 and c.length() > d.length():
			lined += 1
	var men := 0
	var outside := 0
	var general_in := false
	for f in dio.figs:
		if int(f["army"]) != di:
			continue
		var from_fort: float = (f["home"] as Vector2).distance_to(at)
		if bool(f["counts"]):
			men += 1
			if from_fort >= r * 0.85:
				outside += 1
		if str(f["kind"]) == "general":
			general_in = from_fort < r * 0.5
	var sp: Vector2 = lf.wv.cam.unproject_position(Vector3(at.x, t.height_at(at), at.y)) / lf._px
	var framed: bool = sp.y > lf.BAND_TOP - 40.0 and sp.y < lf.size.y - lf.BAND_BOTTOM + 40.0 and sp.x > 0.0 and sp.x < lf.size.x
	return {"kept": (fort["node"] as Node3D).visible, "fall": hi - lo, "groups": groups.size(), "lined": lined, "men": men, "outside": outside,
		"general_in": general_in, "framed": framed}


func _sight(lf: Control, out: Dictionary) -> void:
	## the quick sight test against the full one (every hill sample, every building near the fight),
	## at every yaw and pitch the camera's search tries, for this battle's spots
	var spots: Array = lf.dio.spots()
	lf._battle_rig(lf._land, spots) ## (finds the buildings near the fight, and their highest roof)
	var c := Vector2.ZERO
	for sp in spots:
		c += sp
	c /= float(maxi(spots.size(), 1))
	for step in 24:
		for k in 9:
			var r := {"target": Vector3(c.x, lf._terrain.height_at(c), c.y), "pitch": 36.0 + 4.0 * k, "yaw": float(step) * 15.0, "fov": 32.0, "span": 300.0}
			out["sight_tried"] = int(out["sight_tried"]) + 1
			if lf._sees_all(r, spots) != _sees_all_full(lf, r, spots):
				out["sight_off"] = int(out["sight_off"]) + 1


static func _sees_all_full(lf: Control, r: Dictionary, spots: Array) -> bool:
	## v2.3's test: every sample of every line against every hill and every building near the fight
	var eye: Vector3 = lf.wv.rig_eye(r)
	for s in spots:
		var pt := Vector3(s.x, lf._terrain.height_at(s) + Diorama.FIG * 0.7, s.y)
		for i in range(1, 40):
			var q: Vector3 = eye.lerp(pt, float(i) / 40.0)
			if lf._terrain.height_at(Vector2(q.x, q.z)) > q.y + 1.0:
				return false
			if not (lf._near as Array).is_empty() and i > 4 and i < 38 and Scenery.blocks(q, lf._near):
				return false
	return true


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
