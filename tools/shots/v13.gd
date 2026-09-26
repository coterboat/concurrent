## v1.3 in the real client: a melee (two invaders, cannon and horse), the swoop into
## it, a border clash on the map, the reinforcement phase, the cards on the table,
## and the garrison shields. Checks that everything replays to the same world.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Maneuver := preload("res://engine/maneuver.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "fast" ## v1.4 dice take their time: throw them quickly here
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	## three humans at one table, sheets open (no pass screens) so the probe can write them all
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
	## the stage: blue's Gate (16 + 2 dug in) between red's Ridge and green's Docks
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 15, 1)
	w.set_hex("beacon", "red", 3)
	w.set_hex("mill", "red", 3)
	w.set_hex("gate", "blue", 16, 2)
	w.set_hex("harbor", "blue", 4, 1)
	w.set_hex("docks", "green", 13, 1)
	w.set_hex("quarry", "green", 3)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	await snap("50_garrison_shields")
	p.ok(s.planner == "red", "red writes first")
	s.set_attack("ridge", "gate", 14)
	s.lock()
	p.ok(s.planner == "blue", "then blue")
	s.lock()
	p.ok(s.planner == "green", "then green")
	s.set_attack("docks", "gate", 12)
	s.lock()
	## into the battle report: wait for the swoop, then the battlefield
	var th: Control = gs.theater
	var guard := 0
	var swooped := false
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		if gs.cinema._waiting and not swooped:
			swooped = true
			await p.frames(20)
			await snap("51_swoop_in")
		await p.frames(1)
	p.ok(th.visible and th._melee, "two invaders on one land open a melee on the battlefield")
	await p.frames(50)
	await snap("52_melee_march_in")
	guard = 0
	var calls := 0
	var shots := 0
	var shot_salvo := false
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				calls += 1
				if calls == 1:
					await p.frames(8)
					await snap("54_melee_call")
				th._answer("r" if calls == 1 else "p")
			"done":
				if not shot_salvo:
					await snap("55_melee_result")
				shot_salvo = true
				th.press()
		if str(th._state) == "rolling" and not shot_salvo and guard > 30 and guard % 97 == 0 and shots < 2:
			shots += 1
			await snap("53_melee_salvo")
		await p.frames(1)
	p.ok(calls >= 2, "both watching invaders made calls (%d)" % calls)
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(s.pending.is_empty() and s.phase == Session.Phase.RECAP, "the round resolved (%d)" % s.phase)
	var sheets: Array = []
	for d in s.rounds_log[-1]:
		sheets.append(Types.Sheet.from_dict(d))
	var again: Dictionary = Resolve.resolve_round(s.pre_world, s.map, sheets, s.match_seed)
	p.ok(Hash.world_hash(again["world"]) == Hash.world_hash(s.world), "the melee (with its live calls) replays to the same world")
	## the reinforcement phase
	s.next_round()
	await p.frames(5)
	p.ok(s.phase == Session.Phase.MANEUVER, "after the report: the reinforcement phase")
	var from := ""
	var to := ""
	for a in ["beacon", "mill", "ridge", "quarry", "docks", "harbor", "gate"]:
		if s.world.get_territory(a).owner != s.planner or s.can_move_from(a) < 1:
			continue
		for b in s.map.get_territory(a).adjacent:
			if s.world.get_territory(b).owner == s.planner:
				from = a
				to = b
	if from != "":
		gs.select(from)
		await p.frames(3)
		gs.order_march(from, to)
		await p.frames(6)
		await snap("56_reinforcement_phase")
	else:
		await snap("56_reinforcement_phase")
	for i in 3:
		if s.phase == Session.Phase.MANEUVER:
			s.lock()
	await p.frames(4)
	p.ok(s.phase == Session.Phase.PLANNING, "sealed marches open the next orders")
	## a border clash on the map (battles shown on the map only)
	Settings.data["battles"] = "off"
	w = s.world
	for t in ["ridge", "beacon", "mill"]:
		w.set_hex(t, "red", 6)
	for t in ["gate", "harbor", "docks", "quarry"]:
		w.set_hex(t, "blue", 6)
	s.drafts.clear()
	s.set_attack("ridge", "gate", 5)
	s.lock()
	s.set_attack("gate", "ridge", 5)
	s.lock()
	s.lock()
	guard = 0
	while not gs.cinema.visible and guard < 300:
		guard += 1
		await p.frames(1)
	guard = 0
	var clash_shot := false
	var clash_checked := false
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.board.clash.is_empty() and not clash_shot:
			clash_shot = true
			await p.frames(10)
			await snap("57_border_clash")
		## v1.6: once the clash is decided, the loser's arrow is gone from the map
		if clash_shot and gs.cinema._rolling <= 0.0 and gs.cinema._card.visible and not clash_checked:
			clash_checked = true
			await p.frames(4)
			var bt: Dictionary = gs.cinema.beats[gs.cinema.index]
			var ev: Dictionary = bt.get("event", {})
			if str(ev.get("kind", "")) == "Clash":
				var lo: String = str(ev["playerB"]) if str(ev["winnerId"]) == str(ev["playerA"]) else str(ev["playerA"])
				var gone := true
				for o in gs.board.orders:
					if str(o.get("owner", "")) == lo and (str(o["to"]) == str(ev["hexA"]) or str(o["to"]) == str(ev["hexB"])):
						gone = false
				p.ok(gone, "the loser of the border clash no longer marches on the map (%s)" % lo)
		elif not gs.cinema._waiting and gs.cinema._wait <= 0.0:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(clash_shot, "a border clash is marked on the map")
	Settings.data["battles"] = "mine"
	## cards on the Wide World
	main.start_game({"map": "res://maps/world30.json", "seed": 12, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(5)
	s = main.session
	gs = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	guard = 0
	while s.phase != Session.Phase.PLANNING and guard < 600:
		guard += 1
		if gs.cinema.visible:
			gs.cinema.skip()
		await p.frames(1)
	p.ok(s.phase == Session.Phase.PLANNING, "round 1 orders on the Wide World")
	s.world.players["red"].cards = PackedStringArray(["sun", "moon", "sun", "star", "sun"])
	s.changed.emit()
	gs.open_cards()
	await p.frames(8)
	await snap("58_cards_hand")
	var dlg: Control = null
	for c in gs.get_children():
		if c.has_method("_pick_best"):
			dlg = c
	p.ok(dlg != null, "the Cards button opens the hand")
	if dlg == null:
		return
	dlg._pick_best()
	dlg._turn()
	await p.frames(6)
	await snap("59_cards_turned_in")
	p.ok(s.sheet().cash_set.size() == 3, "a set is turned in from the table")
	dlg._close()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
