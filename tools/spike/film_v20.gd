## A film of a battle on the land in the real client, with its sound: the board, the swoop, the
## land rising, the fight played by a scripted commander (a beat between throws, "press on" at
## every call), the land sinking back into the board.
##   $G --path . --fixed-fps 30 --write-movie out.avi res://tools/probe.tscn -- --script=res://tools/spike/film_v20.gd
##   FILM=landing for the landing over a sea lane on the Known World; BOARD=land to start on the land
extends RefCounted

const Types := preload("res://engine/types.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	## the film has its sound (probe.gd keeps the player's settings unsaved)
	Settings.data["music"] = 0.35
	Settings.data["sfx"] = 0.9
	Settings.data["ambience"] = 0.5
	Settings.data["voices"] = 0.9
	Audio.apply_volumes()
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "normal"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = OS.get_environment("BOARD") == "land" ## BOARD=land: the board on the land (v2.0, round two)
	Settings.data["dice_help_seen"] = 2
	var landing: bool = OS.get_environment("FILM") == "landing"
	var seats := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]
	if not landing:
		seats.append({"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"})
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/%s.json" % ("known24" if landing else "knife7"), "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": seats})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	for i in seats.size():
		s.auto_deploy()
		s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	var th: Control = gs.theater
	var guard := 0
	while not th._land_field.prepared and guard < 900:
		guard += 1
		await p.frames(1)
	if bool(Settings.data["map_land"]):
		await p.frames(100) ## the land rises under the board
	var w: Types.World = s.world
	if landing:
		var lane: Dictionary = gs.board.art.lanes[0]
		for id in w.territories.keys():
			if w.territories[id].owner == "":
				w.territories[id].owner = "blue"
		w.set_hex(lane["a"], "red", 12, 1)
		w.set_hex(lane["b"], "blue", 6, 1)
		s.drafts.clear()
		s.changed.emit()
		await p.frames(30)
		s.set_attack(lane["a"], lane["b"], 11)
		s.lock()
		s.lock()
	else:
		w.set_hex("ridge", "red", 11, 1)
		w.set_hex("beacon", "red", 3)
		w.set_hex("mill", "red", 3)
		w.set_hex("gate", "blue", 12, 2)
		w.set_hex("harbor", "blue", 4, 1)
		w.set_hex("docks", "green", 10, 1)
		w.set_hex("quarry", "green", 3)
		s.drafts.clear()
		s.changed.emit()
		await p.frames(45)
		s.set_attack("ridge", "gate", 10)
		s.lock()
		s.lock()
		s.set_attack("docks", "gate", 9)
		s.lock()
	## the report plays; the commander watches, throws, and presses on
	guard = 0
	while guard < 9000:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting and not th.visible:
			gs.cinema.advance()
			await p.frames(25)
		if th.visible:
			match str(th._state):
				"ready":
					await p.frames(30)
					if str(th._state) == "ready":
						th.press()
				"call":
					await p.frames(45)
					if str(th._state) == "call":
						th._answer("p")
				"done":
					await p.frames(90)
					if str(th._state) == "done":
						th.press()
		if not gs.cinema.visible and not th.visible and guard > 200:
			break
		await p.frames(1)
	await p.frames(60)
	p.log("film done")
