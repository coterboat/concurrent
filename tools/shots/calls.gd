## Battle calls, live: an assault from a dug-in Ridge with reserves at home.
## Shots: the march-in, the call, the reserves joining, a second call, the fall back,
## and the chart-dressed board. Checks that the paused round replays exactly.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Settings.data["music"] = 0.0
	Settings.data["sfx"] = 0.0
	Settings.data["ambience"] = 0.0
	Settings.data["voices"] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 31, "length": "standard", "timer": 0, "battle": "volleys", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	await snap("33_board_chart")
	## stage it: Ridge dug in with 12, the Gate held by 9
	var w: Types.World = s.world
	for t in ["ridge", "beacon", "mill"]:
		w.set_hex(t, "red", 3)
	w.set_hex("ridge", "red", 12, 1)
	for t in ["gate", "harbor", "docks", "quarry"]:
		w.set_hex(t, "blue", 2)
	w.set_hex("gate", "blue", 9)
	s.drafts.clear()
	s.changed.emit()
	var err: String = s.set_attack("ridge", "gate", 6)
	p.ok(err == "", "order: 6 from Ridge at the Gate (%s)" % err)
	gs.edit_order("ridge", "gate")
	await p.frames(6)
	await snap("34_order_card_stance")
	gs.edit_order("", "")
	s.auto_deploy()
	gs.try_seal()
	## wait for the battlefield and its first call
	var th: Control = gs.theater
	var guard := 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(th.visible, "the battlefield opens for the assault")
	await p.frames(40)
	await snap("35_theater_march_in")
	guard = 0
	while th._state != "call" and guard < 900:
		guard += 1
		if th._state == "ready":
			th.press()
		await p.frames(1)
	p.ok(th._state == "call" and not s.pending.is_empty(), "after the opening exchange the round waits for the call (%s)" % th._state)
	await p.frames(10)
	await snap("36_the_call")
	var res: int = int(s.pending.get("reserves", 0))
	th._answer("r")
	await p.frames(30)
	await snap("37_reserves_march_in")
	p.ok(res > 0 and th._a_left >= res, "the reserves joined (+%d)" % res)
	guard = 0
	while th._state != "call" and th._state != "done" and guard < 1200:
		guard += 1
		if th._state == "ready":
			th.press()
		await p.frames(1)
	if th._state == "call":
		await snap("38_second_call")
		th._answer("f")
		await p.frames(45)
		await snap("39_fall_back")
		guard = 0
		while th._state != "done" and guard < 600:
			guard += 1
			await p.frames(1)
		await snap("40_fell_back_result")
	else:
		p.log("battle ended before a second call")
		await snap("40_battle_result")
	## close out the round and prove the paused round replays exactly
	guard = 0
	while (th.visible or gs.cinema.visible) and guard < 1200:
		guard += 1
		if th.visible and th._state == "done":
			th.press()
		elif th.visible and th._state == "call":
			th._answer("p")
		elif th.visible and th._state == "ready":
			th.press()
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(s.pending.is_empty(), "the round finished resolving")
	var sheets: Array = []
	for d in s.rounds_log[-1]:
		sheets.append(Types.Sheet.from_dict(d))
	var again: Dictionary = Resolve.resolve_round(s.pre_world, s.map, sheets, s.match_seed)
	p.ok(Hash.world_hash(again["world"]) == Hash.world_hash(s.world), "the saved round (with its live calls) replays to the same world")
	var calls: Dictionary = (s.rounds_log[-1] as Array)[0].get("calls", {}) if str((s.rounds_log[-1] as Array)[0].get("playerId", "")) == "red" else {}
	for d in s.rounds_log[-1]:
		if str(d.get("playerId", "")) == "red":
			calls = d.get("calls", {})
	p.ok(not calls.is_empty(), "the live calls are on the saved sheet: %s" % JSON.stringify(calls))
	await p.frames(10)
	await snap("41_after_round")
	## the Known World and the Wide World, dressed as charts
	for mid in ["known24", "world30"]:
		main.start_game({"map": "res://maps/%s.json" % mid, "seed": 8, "length": "standard", "timer": 0, "seats": [
			{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Viceroy Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"},
			{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
		await p.frames(8)
		main.current.intro._done()
		await p.frames(20)
		await snap("42_chart_" + mid)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
