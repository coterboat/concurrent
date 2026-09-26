## v1.5 in the real client: the reinforcement and orders phases, a surge dragged on and
## given a count, a set of cards turned in, physics dice in the battle, the stages of the
## battle report (the surges, all at once), and the regroup phase.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
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
	Settings.data["speed"] = "fast"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 23, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 600:
		guard += 1
		if gs.cinema.visible:
			gs.cinema.skip()
		await p.frames(1)
	p.ok(s.phase == Session.Phase.PLANNING and s.plan_step == "reinforce", "round 1 opens on the reinforcement phase")
	## the stage: red's Ridge (big) faces blue's Gate; beyond the Gate, blue's Docks
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 18, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	w.set_hex("gate", "blue", 2, 1)
	w.set_hex("docks", "blue", 3, 1)
	w.set_hex("harbor", "blue", 3, 1)
	w.set_hex("quarry", "blue", 2, 1)
	s.drafts.clear()
	s.changed.emit()
	gs.phase_banner("REINFORCEMENT PHASE", "Round 1 · place %d fresh recruits on your lands" % s.income_total())
	await p.frames(12)
	await snap("80_reinforcement_phase")
	s.auto_deploy()
	gs.primary_action()
	await p.frames(12)
	p.ok(s.plan_step == "orders", "the dial opens the orders phase")
	await snap("81_orders_phase")
	var err: String = s.set_attack("ridge", "gate", 18)
	p.ok(err == "", "attack ordered (%s)" % err)
	gs._on_drag("gate", "docks")
	await p.frames(6)
	p.ok(str(s.sheet().surges.get("gate", "")) == "docks", "dragging on from the Gate orders a surge into the Docks")
	s.set_surge_count("gate", 6)
	gs.edit_order("gate", "docks")
	await p.frames(6)
	p.ok(gs.order_card.visible and gs.order_card.kind == "surge" and s.surge_count("gate") == 6, "the surge has its own card and a count (6)")
	await snap("82_surge_card")
	gs.edit_order("", "")
	s.lock()
	## the battle: physics dice on the tray
	var th: Control = gs.theater
	guard = 0
	while not th.visible and guard < 3000:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting and gs.cinema._wait <= 0.0:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(th.visible, "your battle opens on the battlefield")
	guard = 0
	var shot := 0
	while th.visible and guard < 6000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
				await p.frames(14)
				if shot == 0:
					shot = 1
					await snap("83_dice_rolling")
			"call":
				th._answer("p")
			"done":
				if shot < 2:
					shot = 2
					await snap("84_battle_verdict")
				th.press()
		await p.frames(1)
	## the report goes on: the stages, the surge
	var stages: Array = []
	guard = 0
	var surge_shot := false
	while gs.cinema.visible and guard < 3000:
		guard += 1
		var bt: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.index >= 0 and gs.cinema.index < gs.cinema.beats.size() else {}
		if bt.has("stage") and not stages.has(bt["stage"]):
			stages.append(bt["stage"])
			if str(bt["stage"]) == "surge" and not surge_shot:
				surge_shot = true
				await p.frames(12)
				await snap("85_surges_stage")
		if th.visible:
			th._skip()
		elif not gs.cinema._waiting and gs.cinema._wait <= 0.0:
			gs.cinema.advance()
		await p.frames(1)
	var all_stages: Array = []
	for bb in gs.cinema.beats:
		if bb.has("stage"):
			all_stages.append(str(bb["stage"]))
	p.ok(all_stages.has("assault") and all_stages.has("surge"), "the report announces its stages (%s)" % ", ".join(all_stages))
	var surged := false
	for e in s.events:
		if str(e["kind"]) == Types.EVENT_SURGE:
			surged = int(e["strength"]) <= 6
	p.ok(surged or s.world.get_territory("gate").owner != "red", "the surge pushed on with its count")
	var sheets: Array = []
	for d in s.rounds_log[-1]:
		sheets.append(Types.Sheet.from_dict(d))
	var again: Dictionary = Resolve.resolve_round(s.pre_world, s.map, sheets, s.match_seed)
	p.ok(Hash.world_hash(again["world"]) == Hash.world_hash(s.world), "the round replays to the same world")
	## the regroup phase
	guard = 0
	while s.phase == Session.Phase.RECAP and guard < 10:
		guard += 1
		s.next_round()
		await p.frames(3)
	if s.phase == Session.Phase.MANEUVER:
		await p.frames(10)
		await snap("86_regroup_phase")
		p.ok(true, "the regroup phase opens with its banner")
	## a set of cards turned in: announced in the next report
	if s.phase == Session.Phase.MANEUVER:
		s.lock()
		await p.frames(5)
	if s.phase == Session.Phase.PLANNING:
		s.map.cards = true ## the Isthmus has no cards: deal them in for this check
		s.world.players["red"].cards = PackedStringArray(["sun", "moon", "star"])
		s.sheet().cash_set = PackedStringArray(["sun", "moon", "star"])
		s.auto_deploy()
		s.begin_orders()
		var lerr: String = s.lock()
		p.log("sealed with a set: phase %d err '%s' hand %s" % [s.phase, lerr, str(s.world.players["red"].cards)])
		guard = 0
		var cash_seen := false
		while guard < 1500 and s.phase != Session.Phase.RECAP:
			guard += 1
			var bt2: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.visible and gs.cinema.index >= 0 and gs.cinema.index < gs.cinema.beats.size() else {}
			if bt2.has("cash") and not cash_seen:
				cash_seen = true
				await p.frames(40)
				await snap("87_cards_turned_in")
			if th.visible:
				th._skip()
			elif gs.cinema.visible and not gs.cinema._waiting and gs.cinema._wait <= 0.0:
				gs.cinema.advance()
			await p.frames(1)
		p.ok(cash_seen, "a set turned in is announced in the report")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
