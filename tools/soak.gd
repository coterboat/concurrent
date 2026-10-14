## A soak (v2.1): a whole war in the real client on the land, every battle opened and auto-rolled,
## the advisor drafting the human's sheets, to catch what no single probe hits (it found the board
## drawing shapes of no size behind a battle's camera). Not in the probe suite: a war takes 10 to 15
## minutes. Fails on its one fact; grep its log for SCRIPT ERROR and ERROR too.
##   SHOT_DIR=/dir SOAK_MAP=known24 SOAK_SEED=77 $G --path . res://tools/probe.tscn -- --script=res://tools/soak.gd
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
	while guard < 60 * 60 * 25 and s.phase != Session.Phase.GAME_OVER:
		guard += 1
		await p.frames(1)
		if s.world != null and s.world.round != last_round:
			last_round = s.world.round
			p.log("round %d at %.0f s (%d battles watched so far)" % [last_round, (Time.get_ticks_msec() - t0) / 1000.0, battles])
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
	p.ok(s.phase == Session.Phase.GAME_OVER, "a whole war played through in the client on the land (round %d, %.0f s, winner %s)" % [s.world.round if s.world else -1, (Time.get_ticks_msec() - t0) / 1000.0, s.winner])
	await snap("soak_end")
	main.queue_free()
	await p.frames(10)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.resize(1440, 900)
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
