## Drive the real game through its screens and screenshot each one.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const MapLib := preload("res://engine/map.gd")

var p

func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Settings.data["music"] = 0.0
	Settings.data["sfx"] = 0.0
	Settings.data["ambience"] = 0.0
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(60)
	await snap("01_title")
	main.show_setup()
	await p.frames(10)
	await snap("02_setup")
	main.start_game({"map": "res://maps/known24.json", "seed": 99, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	var gs: Control = main.current
	await p.frames(30)
	await snap("03a_intro")
	gs.intro._done()
	await p.frames(5)
	var s: Node = main.session
	var mine := MapLib.player_territory_ids(s.world, "red")
	gs.select(mine[0])
	gs.place(mine[0], 1)
	await p.frames(5)
	await snap("03_opening")
	s.auto_deploy()
	s.lock()
	await p.frames(40)
	await snap("04_deploy_cinema")
	gs.cinema.skip()
	await p.frames(10)
	## round 1: attack from the biggest stack
	var best := ""
	for t in MapLib.player_territory_ids(s.world, "red"):
		if best == "" or s.world.get_territory(t).armies > s.world.get_territory(best).armies:
			best = t
	gs.select(best)
	for n in MapLib.neighbors(s.map, best):
		if s.world.get_territory(n).owner != "red":
			gs.order_attack(best, n)
			break
	await p.frames(8)
	await snap("05_planning")
	gs.edit_order("", "")
	gs.select(best)
	await p.frames(4)
	await snap("05b_land_card")
	gs.open_plan()
	await p.frames(8)
	await snap("05c_plan")
	for c in gs.get_children():
		if c.get_script() == load("res://game/ui/plan_dialog.gd"):
			c.queue_free()
	s.auto_deploy()
	gs.try_seal()
	await p.frames(30)
	await snap("06_cinema_reveal")
	## step until the battlefield opens, roll twice, then look
	var g2 := 0
	while not gs.theater.visible and s.phase == Session.Phase.CINEMA and g2 < 30:
		gs.cinema.advance()
		await p.frames(3)
		g2 += 1
	if gs.theater.visible:
		await p.frames(40)
		await snap("07a_theater_ready")
		gs.theater.press()
		await p.frames(80)
		await snap("07_theater_roll")
		for k in 12:
			gs.theater.press()
			await p.frames(70)
		await snap("07b_theater_result")
		gs.theater._skip()
		await p.frames(20)
	gs.cinema.skip()
	await p.frames(10)
	await snap("08_recap")
	gs._open_rules(2)
	await p.frames(10)
	await snap("09_rules")
	for c in gs.get_children():
		if c.get_script() == load("res://game/ui/howto_screen.gd"):
			c.queue_free()
	main.open_settings()
	await p.frames(10)
	await snap("10_settings")
	main.settings_panel.closed.emit()
	## fast-forward to the end
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 400:
		guard += 1
		match s.phase:
			Session.Phase.RECAP:
				gs.recap.visible = false
				s.next_round()
			Session.Phase.PLANNING, Session.Phase.OPENING:
				s.auto_deploy()
				s.lock()
			Session.Phase.MANEUVER:
				s.lock() ## the regroup phase: no marches, go on (it used to stall here)
			Session.Phase.CINEMA:
				gs.cinema.skip()
		await p.frames(3)
	await p.frames(70)
	p.ok(s.phase == Session.Phase.GAME_OVER, "the fast-forward reaches the end of the war (round %d)" % s.world.round)
	await snap("11_game_over")

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
