## v1.10 in the real client: a melee and a free-for-all shown like any battle (odds bar, Fortune's
## stars, the pieces), Fortune offered to a defender beset from two sides, and the final chart
## drawn the same size in all three of its modes.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["speed"] = "fast"
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)

	## --- we and Hask storm Varek's gate together: a melee, then the scramble for it
	var s: Node
	var gs: Control
	var seen_melee := false
	var seen_scramble := false
	var melee_bar := false
	var scramble_bar := false
	var melee_stars := false
	var pieces := false
	for sd in range(1, 12):
		main.start_game({"map": "res://maps/knife7.json", "seed": 30 + sd, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": [
			{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
			{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
			{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
		await p.frames(6)
		s = main.session
		gs = main.current
		gs.intro._done()
		s.auto_deploy()
		s.lock()
		await p.frames(5)
		gs.cinema.skip()
		var guard := 0
		while s.phase != Session.Phase.PLANNING and guard < 1200:
			guard += 1
			await p.frames(1)
		var w: Types.World = s.world
		for t in w.territories.keys():
			w.set_hex(str(t), Types.UNOCCUPIED, 0)
		w.set_hex("ridge", "red", 14, 1)
		w.set_hex("beacon", "red", 2, 1)
		w.set_hex("mill", "red", 2, 1)
		w.set_hex("docks", "green", 14, 1)
		w.set_hex("quarry", "green", 2, 1)
		w.set_hex("gate", "blue", 5, 1)
		w.set_hex("harbor", "blue", 3, 1)
		for pid in ["red", "green", "blue"]:
			w.players[pid].fortune = 2
		s.drafts.clear()
		s.changed.emit()
		await p.frames(4)
		s.set_attack("ridge", "gate", 13)
		var gsh := Types.Sheet.new()
		gsh.player_id = "green"
		var gp := Types.Packet.new()
		gp.from_id = "docks"
		gp.to_id = "gate"
		gp.strength = 13
		gp.stance = "hold"
		gsh.packets = [gp]
		s.locked["green"] = gsh
		var bsh := Types.Sheet.new()
		bsh.player_id = "blue"
		s.locked["blue"] = bsh
		s.lock()
		var th: Control = gs.theater
		guard = 0
		while guard < 9000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
			guard += 1
			if th.visible:
				if th._melee and not seen_melee and str(th._state) == "ready":
					seen_melee = true
					melee_bar = th._odds_bar.p >= 0.0
					melee_stars = th._fort_a.visible and th._fort_b.visible
					pieces = th._tray._pieces.size() == 2
					await p.frames(20)
					await snap("00_melee")
				if th._scramble and not seen_scramble and str(th._state) == "ready":
					seen_scramble = true
					scramble_bar = not th._odds_bar.multi.is_empty()
					await p.frames(20)
					await snap("01_scramble")
				match str(th._state):
					"ready", "done":
						th.press()
					"call":
						th._answer("p" if not th._btn_fortune.visible else "n")
			elif gs.cinema.visible and not gs.cinema._waiting:
				gs.cinema.advance()
			await p.frames(1)
		if seen_melee and seen_scramble:
			break
	p.ok(seen_melee, "a melee opens on the battlefield")
	p.ok(melee_bar, "the melee draws its odds bar")
	p.ok(melee_stars, "and Fortune's stars for both sides")
	p.ok(pieces, "and the painted pieces stand beside the table")
	p.ok(seen_scramble and scramble_bar, "the scramble for the spoils draws every army's chance in its colours")

	## --- Varek and Hask storm our gate: offered Fortune as the defender
	var offered := false
	for sd in range(1, 30):
		main.start_game({"map": "res://maps/knife7.json", "seed": 60 + sd, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": [
			{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
			{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
			{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
		await p.frames(6)
		s = main.session
		gs = main.current
		gs.intro._done()
		s.auto_deploy()
		s.lock()
		await p.frames(5)
		gs.cinema.skip()
		var guard2 := 0
		while s.phase != Session.Phase.PLANNING and guard2 < 1200:
			guard2 += 1
			await p.frames(1)
		var w2: Types.World = s.world
		for t in w2.territories.keys():
			w2.set_hex(str(t), Types.UNOCCUPIED, 0)
		w2.set_hex("gate", "red", 12, 1)
		w2.set_hex("beacon", "red", 2, 1)
		w2.set_hex("mill", "red", 2, 1)
		w2.set_hex("ridge", "blue", 12, 1)
		w2.set_hex("docks", "green", 12, 1)
		w2.set_hex("harbor", "green", 2, 1)
		w2.set_hex("quarry", "blue", 2, 1)
		for pid in ["red", "green", "blue"]:
			w2.players[pid].fortune = 2
		s.drafts.clear()
		s.changed.emit()
		await p.frames(4)
		var b2 := Types.Sheet.new()
		b2.player_id = "blue"
		var bp2 := Types.Packet.new()
		bp2.from_id = "ridge"
		bp2.to_id = "gate"
		bp2.strength = 11
		bp2.stance = "hold"
		b2.packets = [bp2]
		var g2 := Types.Sheet.new()
		g2.player_id = "green"
		var gp2 := Types.Packet.new()
		gp2.from_id = "docks"
		gp2.to_id = "gate"
		gp2.strength = 11
		gp2.stance = "hold"
		g2.packets = [gp2]
		s.locked["blue"] = b2
		s.locked["green"] = g2
		s.lock()
		var th2: Control = gs.theater
		guard2 = 0
		while guard2 < 9000 and not offered and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
			guard2 += 1
			if th2.visible:
				match str(th2._state):
					"ready", "done":
						th2.press()
					"call":
						if th2._btn_fortune.visible:
							offered = true
							await p.frames(15)
							await snap("02_defender_fortune")
							th2._answer("F")
							await p.frames(40)
							await snap("03_melee_thrown_again")
						else:
							th2._answer("p")
			elif gs.cinema.visible and not gs.cinema._waiting:
				gs.cinema.advance()
			await p.frames(1)
		if offered:
			break
	p.ok(offered, "beset from two sides, the defender is offered Fortune after a bad exchange")
	var spent := false
	for e in s.events:
		if str(e.get("kind", "")) == Types.EVENT_MELEE:
			for c in e.get("defCalls", []):
				if str(c.get("by", "")) == "red":
					spent = true
	p.ok(spent, "and the favour spent is on the record as ours")

	## --- the final chart: the same size in every mode
	var gl := 0
	while s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER and gl < 3000:
		gl += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		if gs.theater.visible and str(gs.theater._state) in ["ready", "done"]:
			gs.theater.press()
		await p.frames(1)
	s.capital_log.append({"round": 1, "pid": "blue", "by": "red", "land": "ridge"})
	gs.game_over.show_result()
	await p.frames(30)
	var charts: Array = gs.game_over.find_children("*", "", true, false).filter(func(c): return c.get("mode") != null and c.has_method("_draw") and c.get("session") != null)
	var sizes: Array = []
	if not charts.is_empty():
		var chart: Control = charts[0]
		for md in ["terr", "armies", "score"]:
			chart.mode = md
			for c in gs.game_over.find_children("*", "Button", true, false):
				if (c as Button).text == {"terr": "Lands", "armies": "Armies", "score": "Score"}[md]:
					(c as Button).pressed.emit()
			await p.frames(8)
			sizes.append(chart.size)
			await snap("04_chart_" + md)
	p.ok(sizes.size() == 3 and sizes[0] == sizes[1] and sizes[1] == sizes[2], "the chart draws the same size in every mode %s" % str(sizes))
	p.log("v110 probe done")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
