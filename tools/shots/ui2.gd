## Tutorial, hotseat pass screen, and a card hand on the Wide World.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const MapLib := preload("res://engine/map.gd")
const Types := preload("res://engine/types.gd")

var p

func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Settings.data["music"] = 0.0
	Settings.data["sfx"] = 0.0
	Settings.data["ambience"] = 0.0
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_tutorial()
	await p.frames(10)
	main.current.intro._done()
	await snap("20_tutorial_open")
	var s: Node = main.session
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	main.current.cinema.skip()
	await p.frames(10)
	await snap("21_tutorial_r1")
	## hotseat
	main.start_game({"map": "res://maps/knife7.json", "seed": 5, "length": "standard", "timer": 90, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Alex", "kind": "human", "ai": "", "portrait": "player"}]})
	await p.frames(10)
	await snap("22_hotseat_pass")
	## wide world with cards in hand, zoomed
	main.start_game({"map": "res://maps/world30.json", "seed": 12, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Old Bear Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
		{"id": "gold", "name": "Lady Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"},
		{"id": "purple", "name": "Commander Imre", "kind": "ai", "ai": "imre", "portrait": "imre"}]})
	await p.frames(5)
	s = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(5)
	for i in 2:
		s.auto_deploy()
		gs.try_seal()
		await p.frames(5)
		gs.cinema.skip()
		await p.frames(5)
		gs.recap.visible = false
		s.next_round()
		await p.frames(5)
	s.world.players["red"].cards = PackedStringArray(["sun", "moon", "wild", "star"])
	var mine := MapLib.player_territory_ids(s.world, "red")
	if mine.size() > 0:
		gs.select(mine[0])
	gs.board.zoom_at(gs.board.anchor(mine[0]) if mine.size() > 0 else gs.board.size * 0.5, 1.8)
	await p.frames(10)
	await snap("23_world_cards_zoom")
	gs.board.reset_view()
	gs.select("")
	gs.toggle_view()
	await p.frames(8)
	await snap("24_world_regions_view")
	gs.toggle_view()

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
