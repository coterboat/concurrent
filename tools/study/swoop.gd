## v2.4: the swoop into a battle on the land and back, frame by frame (the owner: "the zoom in between
## the main map and battle map on 3d absolutely chugs", on an RTX 3070). The real client on the land as
## the owner plays it (battle_land, map_land, motion "all", rolling for himself), several battles in one
## war. Every frame's real length (Time.get_ticks_usec, the first thing each frame does), and for each
## slow one what happened in it: resources loaded from disk (ResourceLoader.has_cached over every asset),
## nodes and resources made, pipelines compiled (Performance, by kind), draw calls, the process and
## render times (the screen's and the land's), the board's redraws (its overlay, timed). Then a table a
## phase: the swoop in, the battlefield opening, the battle, its closing and the swoop back.
##   $G --path . res://tools/probe.tscn -- --script=res://tools/study/swoop.gd
## Env: MAP=world30 BATTLES=3 SLOW_MS=50 W=1440 H=900 MAX_FPS=0 (the game's: none), CSV=<file> (every
## frame), FRAMES=1 (print every frame of the swoops). Run it with nothing else drawing on the machine.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")

const PHASES := ["swoop_in", "open", "battle", "close", "swoop_back", "report"]

var p
var main: Control
var gs: Control
var s: Node
var th: Control
var lf: Control
var board: Control
var land: Node
var battle := 0 ## which battle is being recorded (0: none)
var fought := false ## this battle's fight has begun (what follows its opening is its closing)
var closed := false ## ...and the battlefield has gone (the board swoops back)
var recs: Array = [] ## a record a frame: see _tick()
var slow_ms := 50.0
var _assets: PackedStringArray = PackedStringArray()
var _cached := {}
var _pc: Array = []
var _nodes := 0
var _res := 0
var _ov_us := 0
var _ov_n := 0
var _last_us := 0
var _last_chk := 0
var _vp_main: RID
var _vp_land: RID
var _meter: Node


class Meter extends Node:
	var tick: Callable

	func _process(_d: float) -> void:
		tick.call()


func run(probe) -> void:
	p = probe
	var w: int = int(OS.get_environment("W")) if OS.get_environment("W") != "" else 1440
	var h: int = int(OS.get_environment("H")) if OS.get_environment("H") != "" else 900
	p.get_window().size = Vector2i(w, h)
	slow_ms = float(OS.get_environment("SLOW_MS")) if OS.get_environment("SLOW_MS") != "" else 50.0
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	## the land, as the owner plays it
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	Settings.data["motion"] = "all"
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "normal"
	Engine.max_fps = int(OS.get_environment("MAX_FPS")) if OS.get_environment("MAX_FPS") != "" else 0
	p.log("study: %s, %s, window %dx%d, max_fps %d" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(), w, h, Engine.max_fps])
	_list("res://assets")
	_list("res://game")
	for a in _assets:
		_cached[a] = ResourceLoader.has_cached(a)
	var map_id: String = OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "world30"
	main = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/%s.json" % map_id, "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "deal": "random",
		"seats": [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]})
	await p.frames(5)
	s = main.session
	gs = main.current
	th = gs.theater
	lf = th._land_field
	board = gs.board
	land = gs.land
	gs.intro._done()
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while not (lf.prepared and gs.land_board.settled() and gs.land_board.active()) and guard < 3000:
		guard += 1
		await p.frames(1)
	p.log("study: the land built and the board on it in %d ms" % (Time.get_ticks_msec() - t0))
	## the board's overlay, timed
	board.overlay.draw.disconnect(board._draw_overlay)
	board.overlay.draw.connect(func():
		var o0 := Time.get_ticks_usec()
		board._draw_overlay()
		_ov_us += Time.get_ticks_usec() - o0
		_ov_n += 1)
	_vp_main = p.get_viewport().get_viewport_rid()
	_vp_land = land._vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_main, true)
	RenderingServer.viewport_set_measure_render_time(_vp_land, true)
	_pc = _pipelines()
	_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_res = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	_meter = Meter.new()
	_meter.process_priority = -1000000 ## first in every frame
	_meter.tick = _tick
	p.get_tree().root.add_child(_meter)
	var n: int = int(OS.get_environment("BATTLES")) if OS.get_environment("BATTLES") != "" else 3
	var used: Array = []
	for b in n:
		await _to_planning()
		await p.frames(90)
		var pair: Array = _pick(used)
		if pair.is_empty():
			p.log("study: no more lands to fight over")
			break
		used.append(pair[1])
		var wd: Types.World = s.world
		wd.set_hex(pair[0], "red", 16, 1)
		wd.set_hex(pair[1], "blue", 7, 1)
		s.drafts.clear()
		s.changed.emit()
		await p.frames(30)
		var err: String = s.set_attack(pair[0], pair[1], 15)
		p.log("study: battle %d: %s -> %s %s" % [b + 1, pair[0], pair[1], err])
		battle = b + 1
		fought = false
		closed = false
		s.lock()
		s.lock()
		await _play_out()
		battle = 0
		_report(b + 1)
	_report(0)
	_meter.queue_free()
	_csv()
	main.queue_free()
	await p.frames(5)


func _list(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		var ext: String = f.get_extension().to_lower()
		if ext in ["glb", "webp", "png", "jpg", "ogv", "mp3", "wav", "ogg", "tres", "res", "ttf", "svg", "gdshader"]:
			_assets.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_list(dir + "/" + d)


func _pipelines() -> Array:
	return [int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)),
		int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)), int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)),
		int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))]


func _pick(used: Array) -> Array:
	## a red land with a blue neighbour over a land border (no boats: the same kind of fight each time)
	for id in board.art.order:
		var ts: Types.TerritoryState = s.world.get_territory(id)
		if ts == null or ts.owner != "red":
			continue
		for nb in MapLib.neighbors(s.map, id):
			var tn: Types.TerritoryState = s.world.get_territory(nb)
			if tn != null and tn.owner == "blue" and not used.has(nb) and land.wv.terrain.crossing(nb, id) != null:
				return [id, str(nb)]
	return []


func _to_planning() -> void:
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 6000:
		guard += 1
		match s.phase:
			Session.Phase.DRAFT:
				s.claim(s.draft_pick_for(s.draft_turn()))
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


func _play_out() -> void:
	## the report plays as it does for the owner: the camera swoops on his battle, he rolls each
	## exchange (a beat after it's ready), presses on, and leaves the field when it's done
	var guard := 0
	var wait := 0
	var tail := 0
	while guard < 20000:
		guard += 1
		if th.visible:
			match str(th._state):
				"ready":
					wait += 1
					if wait > 36:
						wait = 0
						th.press()
				"call":
					wait += 1
					if wait > 30:
						wait = 0
						th._answer("p")
				"done":
					wait += 1
					if wait > 90:
						wait = 0
						th.press()
				_:
					wait = 0
		elif gs.cinema.visible and not gs.cinema._waiting:
			if closed:
				tail += 1
				if tail > 90:
					break ## the swoop back is done and the report goes on
			elif gs.cinema._wait > 0.3:
				gs.cinema._wait = 0.3 ## the report's other beats, quickly, to this battle
		elif not gs.cinema.visible and s.phase != Session.Phase.CINEMA and s.phase != Session.Phase.RESOLVING:
			break
		await p.frames(1)


func _phase() -> String:
	if th.visible or lf.visible:
		if th.visible and str(th._state) != "idle":
			fought = true
			return "battle"
		return "close" if fought else "open"
	if fought:
		closed = true
	if gs.cinema._waiting and not fought:
		return "swoop_in"
	if closed and board._back_tw != null and board._back_tw.is_valid() and board._back_tw.is_running():
		return "swoop_back"
	return "report"


func _tick() -> void:
	var now := Time.get_ticks_usec()
	var t0 := now
	var loads: Array = []
	var gone := 0
	for a in _assets:
		var c: bool = ResourceLoader.has_cached(a)
		if c != bool(_cached[a]):
			_cached[a] = c
			if c:
				loads.append(a.get_file())
			else:
				gone += 1
	var pc: Array = _pipelines()
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var res: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	if battle > 0:
		var r := {
			"b": battle, "ph": _phase(), "ms": float(now - _last_us - _last_chk) / 1000.0,
			"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"rc": RenderingServer.viewport_get_measured_render_time_cpu(_vp_main) + RenderingServer.get_frame_setup_time_cpu(),
			"rg": RenderingServer.viewport_get_measured_render_time_gpu(_vp_main),
			"lc": RenderingServer.viewport_get_measured_render_time_cpu(_vp_land),
			"lg": RenderingServer.viewport_get_measured_render_time_gpu(_vp_land),
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"pc": [pc[0] - _pc[0], pc[1] - _pc[1], pc[2] - _pc[2], pc[3] - _pc[3], pc[4] - _pc[4]],
			"nodes": nodes - _nodes, "res": res - _res, "loads": loads, "gone": gone,
			"ov_n": _ov_n, "ov_ms": float(_ov_us) / 1000.0,
			"figs": land.battle.figs.size() if land.battle != null else 0,
			"garr": land.garrisons.figs.size() if land.garrisons != null else 0,
			"q": land.quality,
			## (a board timed by hand, a `_prof` dict of its overlay's sections -> usec, gets them listed)
			"prof": (board.get("_prof") as Dictionary).duplicate() if board.get("_prof") != null else {},
		}
		recs.append(r)
		if OS.get_environment("FRAMES") != "" and r["ph"] != "report" and r["ph"] != "battle":
			p.log("frame " + _line(r))
	_pc = pc
	_nodes = nodes
	_res = res
	_ov_us = 0
	_ov_n = 0
	if board.get("_prof") != null:
		(board.get("_prof") as Dictionary).clear()
	_last_us = now
	_last_chk = Time.get_ticks_usec() - t0


func _line(r: Dictionary) -> String:
	var pc: Array = r["pc"]
	var bits := "b%d %-10s %6.1f ms  proc %5.1f  render %5.1f/%5.1f gpu  land %5.1f/%5.1f gpu  draws %4d objs %4d" % [
		r["b"], r["ph"], r["ms"], r["proc"], r["rc"], r["rg"], r["lc"], r["lg"], r["draws"], r["objs"]]
	if pc.any(func(x): return x != 0):
		bits += "  pipelines c%d m%d s%d d%d sp%d" % pc
	if int(r["nodes"]) != 0:
		bits += "  nodes %+d" % int(r["nodes"])
	if int(r["res"]) != 0:
		bits += "  res %+d" % int(r["res"])
	if int(r["ov_n"]) > 0:
		bits += "  overlay %dx %.1f ms" % [r["ov_n"], r["ov_ms"]]
	if not (r["loads"] as Array).is_empty():
		bits += "  LOADED " + ", ".join(r["loads"])
	if int(r["gone"]) > 0:
		bits += "  (released %d)" % r["gone"]
	bits += "  figs %d garr %d q%d" % [r["figs"], r["garr"], r["q"]]
	var prof: Dictionary = r.get("prof", {})
	if not prof.is_empty() and float(r["ov_ms"]) > 5.0:
		var ks: Array = prof.keys()
		ks.sort_custom(func(x, y): return int(prof[x]) > int(prof[y]))
		var parts: Array = []
		for k in ks.slice(0, 7):
			parts.append("%s %.1f" % [k, float(prof[k]) / 1000.0])
		bits += "  [" + ", ".join(parts) + "]"
	return bits


func _report(b: int) -> void:
	## a phase a row: frames, the worst, how many over 50 ms (and 33), the time over a 60 Hz frame
	var mine: Array = recs.filter(func(r): return b == 0 or int(r["b"]) == b)
	p.log("study: === %s ===" % ("battle %d" % b if b > 0 else "every battle"))
	for ph in PHASES:
		var rows: Array = mine.filter(func(r): return r["ph"] == ph)
		if rows.is_empty():
			continue
		var worst := 0.0
		var over := 0
		var over33 := 0
		var lost := 0.0
		var total := 0.0
		var pcs := 0
		var loads := 0
		for r in rows:
			worst = maxf(worst, float(r["ms"]))
			total += float(r["ms"])
			if float(r["ms"]) > 50.0:
				over += 1
			if float(r["ms"]) > 33.4:
				over33 += 1
			lost += maxf(0.0, float(r["ms"]) - 16.7)
			for x in r["pc"]:
				pcs += int(x)
			loads += (r["loads"] as Array).size()
		p.log("study: %-10s %4d frames %6.2f s  worst %6.1f ms  >50ms %3d  >33ms %3d  over 60Hz %6.0f ms  pipelines %3d  loads %3d" % [
			ph, rows.size(), total / 1000.0, worst, over, over33, lost, pcs, loads])
	if b > 0:
		for r in mine:
			if float(r["ms"]) > slow_ms or not (r["loads"] as Array).is_empty() or (r["pc"] as Array).any(func(x): return x != 0):
				if r["ph"] != "report" or float(r["ms"]) > slow_ms:
					p.log("slow " + _line(r))


func _csv() -> void:
	var path: String = OS.get_environment("CSV")
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("battle,phase,ms,proc,render_cpu,render_gpu,land_cpu,land_gpu,draws,objs,pc_canvas,pc_mesh,pc_surface,pc_draw,pc_spec,nodes,res,overlay_n,overlay_ms,figs,garr,quality,loads")
	for r in recs:
		var pc: Array = r["pc"]
		f.store_line("%d,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%d,%d,%d,%s" % [r["b"], r["ph"], r["ms"], r["proc"], r["rc"], r["rg"], r["lc"], r["lg"],
			r["draws"], r["objs"], pc[0], pc[1], pc[2], pc[3], pc[4], r["nodes"], r["res"], r["ov_n"], r["ov_ms"], r["figs"], r["garr"], r["q"], " ".join(r["loads"])])
	f.close()
