## How much the board on the land costs a frame, against the chart: the frame time, the 3D
## viewport's own GPU time, at the whole map and zoomed in.
##   SHOT_DIR=/tmp ./scripts/shot.sh ../spike/perf_board
extends RefCounted

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Settings.data["map_land"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/world30.json", "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "B", "kind": "ai", "ai": "general", "portrait": "varek"},
		{"id": "green", "name": "C", "kind": "ai", "ai": "general", "portrait": "ysolde"}]})
	await p.frames(5)
	var gs: Control = main.current
	gs.intro._done()
	gs.cinema.skip()
	var lb = gs.land_board
	var guard := 0
	while not (lb.ready_to_show() and lb.settled()) and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(30)
	RenderingServer.viewport_set_measure_render_time(gs.land._vp.get_viewport_rid(), true)
	await _measure(gs, "land, whole map")
	var wv = gs.land.wv
	wv.env.ssao_enabled = false
	await _measure(gs, "  without SSAO")
	wv.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	await _measure(gs, "  and 2 shadow splits")
	wv.sun.shadow_enabled = false
	await _measure(gs, "  and no shadows")
	gs.land._vp.msaa_3d = Viewport.MSAA_DISABLED
	await _measure(gs, "  and no MSAA")
	wv.props.visible = false
	await _measure(gs, "  and no woods")
	wv.props.visible = true
	gs.land._vp.msaa_3d = Viewport.MSAA_2X
	wv.sun.shadow_enabled = true
	wv.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	wv.env.ssao_enabled = true
	for i in 7:
		gs.board.zoom_at(gs.board.size * 0.5, 1.2)
	await p.frames(30)
	await _measure(gs, "land, zoomed in")
	gs.board.reset_view()
	gs.toggle_land()
	await p.frames(120)
	await _measure(gs, "chart")
	main.queue_free()


func _measure(gs: Control, what: String) -> void:
	var t0 := Time.get_ticks_usec()
	var n := 180
	var gpu := 0.0
	for i in n:
		await p.get_tree().process_frame
		if gs.land.shown():
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(gs.land._vp.get_viewport_rid())
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	p.log("PERF %s: %.2f ms a frame (%.0f fps), the land's GPU %.2f ms" % [what, ms, 1000.0 / ms, gpu / float(n)])
