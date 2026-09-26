## v1.4 in the real client: dice on the table (an assault, then a three-way melee that ends
## in a scramble), the land draft (dice dropped on the map, claims round the table), a
## surge drawn as a march, and the war chest changing hands.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	await _battles(main)
	await _draft(main)


func _battles(main: Control) -> void:
	main.start_game({"map": "res://maps/knife7.json", "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	for i in 3:
		s.auto_deploy()
		s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	## a three-way storm of the Gate: red (Ridge) and green (Docks) and blue holding it with 3
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 34, 1)
	w.set_hex("beacon", "red", 3)
	w.set_hex("mill", "red", 3)
	w.set_hex("gate", "blue", 4, 1)
	w.set_hex("harbor", "blue", 16, 1)
	w.set_hex("docks", "green", 12, 1)
	w.set_hex("quarry", "green", 3)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 33)
	s.lock()
	s.set_attack("harbor", "gate", 1) ## blue reinforces its own Gate (joins the defence)
	s.lock()
	s.set_attack("docks", "gate", 11)
	s.lock()
	var th: Control = gs.theater
	var guard := 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(th.visible and th._melee, "two invaders open a melee on the battlefield")
	await p.frames(40)
	guard = 0
	var shots := 0
	var saw_scramble := false
	while th.visible and guard < 4000:
		guard += 1
		match str(th._state):
			"ready":
				if shots == 0:
					th._toggle_help()
					await p.frames(6)
					await snap("68_dice_help")
					th._toggle_help()
				th.press()
				await p.frames(12)
				if shots < 2:
					shots += 1
					await snap("60_dice_flight_%d" % shots)
			"call":
				th._answer("p")
			"done":
				if th._scramble and not saw_scramble:
					saw_scramble = true
					await snap("63_scramble_done")
				elif not th._scramble:
					await snap("62_melee_done")
				th.press()
		if str(th._state) == "rolling" and not th._reads.is_empty() and shots == 2:
			shots += 1
			await p.frames(20)
			await snap("61_dice_readouts")
		if th._scramble and str(th._state) == "rolling" and not saw_scramble and guard % 50 == 0:
			await snap("63_scramble_rolling")
			saw_scramble = true
		await p.frames(1)
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(s.pending.is_empty(), "the round resolved")
	var sheets: Array = []
	for d in s.rounds_log[-1]:
		sheets.append(Types.Sheet.from_dict(d))
	var again: Dictionary = Resolve.resolve_round(s.pre_world, s.map, sheets, s.match_seed)
	p.ok(Hash.world_hash(again["world"]) == Hash.world_hash(s.world), "the melee and its scramble replay to the same world")
	var kinds := []
	for e in s.events:
		kinds.append(str(e["kind"]))
	p.log("events: " + " ".join(kinds))


func _draft(main: Control) -> void:
	main.start_game({"map": "res://maps/known24.json", "seed": 5, "length": "standard", "timer": 0, "deal": "draft", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	p.ok(s.phase == Session.Phase.DRAFT, "a drafted game opens on the land draft")
	await p.get_tree().create_timer(2.2).timeout
	await snap("64_draft_dice_falling")
	var guard := 0
	while gs._draft_state != "picking" and guard < 600:
		guard += 1
		await p.frames(1)
	await snap("65_draft_order")
	guard = 0
	var shot := false
	while s.phase == Session.Phase.DRAFT and guard < 5000:
		guard += 1
		if s.is_human(s.draft_turn()) and gs._draft_state == "picking":
			if not shot:
				shot = true
				await p.frames(30)
				await snap("66_draft_your_pick")
			gs.draft_advise()
		await p.frames(1)
	p.ok(s.phase == Session.Phase.OPENING, "every land claimed: deployment begins")
	var mine := 0
	for t in s.map.territory_ids():
		if s.world.get_territory(str(t)).owner == "red":
			mine += 1
	p.ok(mine == 8, "the human claimed 8 lands (%d)" % mine)
	await p.frames(10)
	await snap("67_draft_done")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
