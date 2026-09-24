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
		{"id": "green", "name": "The Quartermaster", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	var gs: Control = main.current
	var s: Node = main.session
	var mine := MapLib.player_territory_ids(s.world, "red")
	gs._select(mine[0])
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
	gs._select(best)
	for n in MapLib.neighbors(s.map, best):
		if s.world.get_territory(n).owner != "red":
			gs.order_attack(best, n)
			break
	await p.frames(5)
	await snap("05_planning")
	s.auto_deploy()
	gs.try_seal()
	await p.frames(30)
	await snap("06_cinema_reveal")
	## step to the first real fight and let the dice settle
	for i in 6:
		gs.cinema.paused = true
		gs.cinema.advance()
		await p.frames(2)
		if gs.cinema._card.visible:
			break
	await p.frames(90)
	await snap("07_cinema_battle")
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
	while s.phase != Session.Phase.GAME_OVER and guard < 80:
		guard += 1
		match s.phase:
			Session.Phase.RECAP:
				gs.recap.visible = false
				s.next_round()
			Session.Phase.PLANNING:
				s.auto_deploy()
				s.lock()
			Session.Phase.CINEMA:
				gs.cinema.skip()
		await p.frames(3)
	await p.frames(70)
	await snap("11_game_over")

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
