## A soak (v2.1): a whole war in the real client on the land, every battle opened and auto-rolled,
## the advisor drafting the human's sheets, to catch what no single probe hits (it found the board
## drawing shapes of no size behind a battle's camera). Not in the probe suite: a war takes 10 to 15
## minutes. Grep its log for SCRIPT ERROR and ERROR too.
## v2.5: each round's line says what the war holds (nodes, objects, memory) and how the frames went
## (frames over 50 ms, the slowest, the land's quality step), and two more facts hold the leaks: the
## nodes and the memory at the end of the war are what they were after its first battles, give or take
## what a bigger war's report holds. Run it on the Compatibility renderer with `--rendering-driver opengl3`.
##   SHOT_DIR=/dir SOAK_MAP=known24 SOAK_SEED=77 $G --path . res://tools/probe.tscn -- --script=res://tools/soak.gd
## SOAK_QUALITY=4 starts the land on its lowest step (no shadows, no MSAA, 0.7 resolution).
extends RefCounted

const Counsel := preload("res://game/core/counsel.gd")
const Session := preload("res://game/core/session.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "all"
	Settings.data["roll_yourself"] = false
	Settings.data["speed"] = "fast"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	## v2.5: SOAK_QUALITY=4 plays the war on the land's lowest step (a land starts one better than the
	## step remembered: land.gd)
	if OS.get_environment("SOAK_QUALITY") != "":
		Settings.data["land_quality"] = int(OS.get_environment("SOAK_QUALITY")) + 1
	var map: String = OS.get_environment("SOAK_MAP") if OS.get_environment("SOAK_MAP") != "" else "known24"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	var seats := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "general", "portrait": "varek"},
		{"id": "green", "name": "Ysolde", "kind": "ai", "ai": "veteran", "portrait": "ysolde"},
		{"id": "gold", "name": "Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]
	main.start_game({"map": "res://maps/%s.json" % map, "seed": int(OS.get_environment("SOAK_SEED")) if OS.get_environment("SOAK_SEED") != "" else 77, "length": "short", "timer": 0, "seats": seats, "deal": "random"})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var th: Control = gs.theater
	var t0: int = Time.get_ticks_msec()
	var last_round := -1
	var battles := 0
	var guard := 0
	var shots := 0
	var was_open := false
	var slow := 0 ## frames over 50 ms this round
	var worst := 0.0
	var last_us := Time.get_ticks_usec()
	var marks := {} ## round -> [nodes, objects, static memory]
	while guard < 60 * 60 * 25 and s.phase != Session.Phase.GAME_OVER:
		guard += 1
		await p.frames(1)
		var now_us := Time.get_ticks_usec()
		var ms: float = float(now_us - last_us) / 1000.0
		last_us = now_us
		if guard > 30:
			worst = maxf(worst, ms)
			slow += 1 if ms > 50.0 else 0
		if th.visible and not was_open:
			battles += 1
		was_open = th.visible
		if s.world != null and s.world.round != last_round:
			last_round = s.world.round
			var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			var objs: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
			var mem: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
			marks[last_round] = [nodes, objs, mem]
			p.log("round %d at %.0f s (%d battles watched so far): %d nodes, %d objects, %.0f MB, %.0f MB video; %d frames over 50 ms, the slowest %.0f ms; the land at quality %d (%s)" % [last_round,
				(Time.get_ticks_msec() - t0) / 1000.0, battles, nodes, objs, mem, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				slow, worst, gs.land.quality if gs.land != null else -1, RenderingServer.get_current_rendering_method()])
			slow = 0
			worst = 0.0
		var m: Variant = gs.get("_modal")
		if m != null and is_instance_valid(m) and (m as Node).has_meta("planning"):
			(m as Node).queue_free()
		if th.visible:
			match str(th._state):
				"ready", "done":
					if guard % 20 == 0:
						th.press()
				"call":
					if guard % 20 == 0:
						th._answer("p")
			if str(th._state) == "ready" and shots < 6 and guard % 600 == 0:
				shots += 1
				await snap("soak_battle_%d" % shots)
			continue
		match s.phase:
			Session.Phase.OPENING:
				if s.is_human(s.planner):
					s.auto_deploy()
					s.lock()
			Session.Phase.DRAFT:
				if gs.has_method("draft_advise") and guard % 30 == 0:
					gs.draft_advise()
			Session.Phase.PASS:
				if gs.has_method("_pass_ready"):
					gs._pass_ready()
			Session.Phase.PLANNING:
				if s.is_human(s.planner) and guard % 10 == 0:
					Counsel.adopt(s, Counsel.draft(s))
					if s.plan_step != "orders":
						s.begin_orders()
					s.lock()
			Session.Phase.MANEUVER:
				if s.is_human(s.planner) and guard % 10 == 0:
					s.lock()
			Session.Phase.RECAP:
				if gs.recap.visible and guard % 30 == 0:
					gs.recap.continue_pressed.emit()
			Session.Phase.CINEMA:
				if gs.cinema.visible and not gs.cinema._waiting and guard % 15 == 0:
					gs.cinema.advance()
		if s.phase == Session.Phase.RECAP and guard % 1800 == 0:
			await snap("soak_recap_r%d" % last_round)
	p.ok(s.phase == Session.Phase.GAME_OVER, "a whole war played through in the client on the land (round %d, %.0f s, winner %s, %d battles watched)" % [s.world.round if s.world else -1, (Time.get_ticks_msec() - t0) / 1000.0, s.winner, battles])
	## the leaks: from round 3 (its first battles fought, the land and the report built) to the end
	var first: Array = marks.get(3, marks.get(2, []))
	if not first.is_empty() and marks.size() >= 3:
		var nodes_end: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var mem_end: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		p.ok(nodes_end < int(first[0]) + 800, "no nodes pile up over the war: %d after round %d's battles, %d at the end" % [int(first[0]), 3 if marks.has(3) else 2, nodes_end])
		p.ok(mem_end < float(first[2]) * 1.25 + 40.0, "no memory piles up over the war: %.0f MB after the first battles, %.0f MB at the end" % [float(first[2]), mem_end])
	await snap("soak_end")
	main.queue_free()
	await p.frames(10)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.resize(1440, 900)
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
