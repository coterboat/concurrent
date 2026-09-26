## v1.4 on the map: a surge drawn as a march (planned, then hopping A → B → C in the
## report), a battle card with its dice, and a war chest changing hands.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "off"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/known24.json", "seed": 77, "length": "standard", "timer": 0, "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Commodore Hask", "kind": "human", "ai": "", "portrait": "hask"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	for i in 2:
		s.auto_deploy()
		s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	## red: a big stack next to two weak blue lands in a line; blue holds cards and little else
	var w: Types.World = s.world
	var a := ""
	var b := ""
	var c := ""
	for x in s.map.territory_ids():
		for y in s.map.get_territory(str(x)).adjacent:
			for z in s.map.get_territory(str(y)).adjacent:
				if a == "" and str(z) != str(x) and not s.map.is_adjacent(str(x), str(z)):
					a = str(x)
					b = str(y)
					c = str(z)
	for t in s.map.territory_ids():
		w.set_hex(str(t), "red", 2)
	w.set_hex(a, "red", 30, 1)
	w.set_hex(b, "blue", 2)
	w.set_hex(c, "blue", 1)
	w.players["blue"].cards = PackedStringArray(["sun", "moon", "star"])
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(a, b, 29)
	var idx: int = s.sheet().packets.size() - 1
	var err: String = s.set_surge(idx, c)
	p.ok(err == "", "a surge is ordered from %s on to %s (%s)" % [b, c, err])
	gs.select("")
	s.changed.emit()
	await p.frames(6)
	await snap("70_surge_planned")
	s.lock()
	s.lock()
	var guard := 0
	while not gs.cinema.visible and guard < 600:
		guard += 1
		await p.frames(1)
	var shot_card := false
	var shot_surge := false
	var shot_chest := false
	guard = 0
	while gs.cinema.visible and guard < 3000:
		guard += 1
		var bt: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.index >= 0 and gs.cinema.index < gs.cinema.beats.size() else {}
		if bt.has("fight") and not shot_card and gs.cinema._card.visible and gs.cinema._rolling <= 0.0:
			shot_card = true
			await snap("71_battle_card")
		if bt.has("surge_arrow") and not shot_surge:
			shot_surge = true
			await p.frames(40)
			await snap("72_surge_hop")
		if bt.has("cards_to") and not shot_chest:
			shot_chest = true
			await p.frames(28)
			await snap("73_war_chest")
		if gs.cinema._wait <= 0.0 and gs.cinema._rolling <= 0.0:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(shot_surge, "the surge hop plays as its own march")
	p.ok(shot_chest, "the war chest changes hands")
	p.ok(s.world.players["red"].cards.size() >= 3, "red holds blue's cards (%d)" % s.world.players["red"].cards.size())


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
