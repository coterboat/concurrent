## A film of the board on the land in the real client, with its sound: the chart rising into the
## land, a look round (a pan, a zoom down over a land, its garrison and its village), orders drawn,
## the battle report with its columns marching, a battle down out of the board's own camera and
## back, then L: the chart, and the land again.
##   $G --path . --fixed-fps 30 --write-movie out.avi res://tools/probe.tscn -- --script=res://tools/spike/film_v20b.gd
##   MAP=world30 for another map (the battle is the Known World's own when MAP is unset)
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Session := preload("res://game/core/session.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Settings.data["music"] = 0.35
	Settings.data["sfx"] = 0.9
	Settings.data["ambience"] = 0.6
	Settings.data["voices"] = 0.9
	Audio.apply_volumes()
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "normal"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = false ## it starts on the chart, and rises
	Settings.data["dice_help_seen"] = 2
	Settings.data["tips"] = false
	var mid: String = OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "known24"
	var seats := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "general", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "ai", "ai": "general", "portrait": "ysolde"},
		{"id": "gold", "name": "Governor Quill", "kind": "ai", "ai": "veteran", "portrait": "quill"}]
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/%s.json" % mid, "seed": 7, "length": "standard", "timer": 0, "open_sheets": true, "seats": seats})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var b: Control = gs.board
	var lb: Control = gs.land_board
	await p.frames(10)
	gs.cinema.skip()
	var guard := 0
	while not gs.land.prepared and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(45)
	## the chart rises into the land
	gs.toggle_land()
	await p.frames(110)
	## a look round: across the map, and down over one of ours
	var mine: Array = Array(MapLib.player_territory_ids(s.world, "red"))
	var home: String = str(mine[0]) if not mine.is_empty() else str(b.art.order[0])
	for i in 50:
		b.zoom_at(b.anchor(home), 1.022)
		await p.frames(1)
	await p.frames(60)
	gs.select(home)
	await p.frames(50)
	for i in 120:
		b.offset += Vector2(-1.6, -0.5)
		b._apply_view()
		await p.frames(1)
	await p.frames(30)
	gs.select("")
	b.reset_view()
	await p.frames(40)
	## the reinforcements placed and sealed, then two attacks drawn on the land and sealed
	s.auto_deploy()
	await p.frames(40)
	s.lock()
	await p.frames(40)
	var drawn := 0
	for id in MapLib.player_territory_ids(s.world, "red"):
		var ts = s.world.get_territory(id)
		if ts.armies < 3 or drawn >= 2:
			continue
		for n in MapLib.neighbors(s.map, id):
			if s.world.get_territory(n).owner != "red":
				s.set_attack(id, n, ts.armies - 1)
				drawn += 1
				break
		await p.frames(30)
	await p.frames(60)
	s.lock()
	guard = 0
	while not gs.cinema.visible and guard < 600:
		guard += 1
		await p.frames(1)
	## the report: columns march; any battle of ours tips down out of the board, and rises back
	guard = 0
	var th: Control = gs.theater
	while gs.cinema.visible and guard < 6000:
		guard += 1
		if th.visible:
			match str(th._state):
				"ready":
					await p.frames(35)
					if str(th._state) == "ready":
						th.press()
				"call":
					await p.frames(45)
					if str(th._state) == "call":
						th._answer("p")
				"done":
					await p.frames(80)
					if str(th._state) == "done":
						th.press()
		elif not gs.cinema._waiting:
			await p.frames(70)
			if gs.cinema.visible and not gs.cinema._waiting and not th.visible:
				gs.cinema.advance()
		await p.frames(1)
	await p.frames(60)
	## L: the chart, then the land again
	gs.toggle_land()
	await p.frames(100)
	gs.toggle_land()
	await p.frames(120)
	p.log("film done")
