## v2.0 in the real client: battles on the land. A melee at the Gate (two invaders, as v13 has
## it) and a landing over a sea lane on the Known World, from the board's swoop to the land and
## back. The facts: the land is built before the first battle; the handoff is exact; everyone
## stands where they came from, in the band the battle's words leave clear; the figures standing
## always match the count (one die, one man); a column over the sea comes in boats and lands dry;
## and the board is back when it closes.
##   SHOT_DIR=/dir ./scripts/shot.sh v20
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Diorama := preload("res://game/world3d/diorama.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "fast"
	Settings.data["battle_land"] = true
	await _gate()
	await _landing()
	await _skip_mid_tilt()


func _game(map: String, seats: Array) -> Array:
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": map, "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": seats})
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
	return [main, s, gs]


func _gate() -> void:
	var r: Array = await _game("res://maps/knife7.json", [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"}])
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	var guard := 0
	while not lf.prepared and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(lf.prepared, "the land is built in the background before the first battle (%d frames)" % guard)
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
	s.set_attack("ridge", "gate", 14)
	s.lock()
	s.lock()
	s.set_attack("docks", "gate", 12)
	s.lock()
	await _into_battle(gs, th, "gate")
	p.ok(th._on_land, "the melee is fought on the land")
	p.ok(lf.handoff_px >= 0.0 and lf.handoff_px < 3.0, "the handoff: the Gate's token is where the land has it (%.1f px off)" % lf.handoff_px)
	await _fight(gs, th, lf, "gate", 2)
	await _out_of_battle(gs, th, lf, "gate")
	main.queue_free()
	await p.frames(5)


func _landing() -> void:
	## a column over a sea lane: red's from one shore, blue's land on the other
	var r: Array = await _game("res://maps/known24.json", [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}])
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	var guard := 0
	while not lf.prepared and guard < 600:
		guard += 1
		await p.frames(1)
	var art = gs.board.art
	var lane: Dictionary = art.lanes[0]
	var from: String = lane["a"]
	var to: String = lane["b"]
	var w: Types.World = s.world
	for id in w.territories.keys():
		if id != from and id != to and w.territories[id].owner == "":
			w.territories[id].owner = "blue"
	w.set_hex(from, "red", 14, 1)
	w.set_hex(to, "blue", 5, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(from, to, 13)
	s.lock()
	s.lock()
	await _into_battle(gs, th, "landing")
	p.ok(th._on_land, "the landing is fought on the land")
	var dio: Node3D = lf.dio
	guard = 0
	while dio.armies.is_empty() and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(not dio.boats.is_empty(), "a column over the sea comes in boats (%d, %s to %s)" % [dio.boats.size(), from, to])
	await p.frames(40)
	await snap("landing_02_rowing")
	guard = 0
	while not dio.boats.all(func(b): return bool(b["landed"])) and guard < 900:
		guard += 1
		await p.frames(1)
	p.ok(dio.boats.all(func(b): return bool(b["landed"])), "every boat reaches the beach")
	await p.frames(120)
	await snap("landing_03_ashore")
	var wet := 0
	for f in dio.figs:
		if f["alive"] and f["state"] != "boat" and lf.wv.terrain.height_at(f["at"]) < 0.5:
			wet += 1
	p.ok(wet == 0, "everyone who came ashore stands on dry land (%d in the sea)" % wet)
	await _fight(gs, th, lf, "landing", 1)
	await _out_of_battle(gs, th, lf, "landing")
	main.queue_free()
	await p.frames(5)


func _skip_mid_tilt() -> void:
	## "Skip battles" while the map is still tipping up: back to the board, cleanly
	var r: Array = await _game("res://maps/knife7.json", [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}])
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	var guard := 0
	while not lf.prepared and guard < 600:
		guard += 1
		await p.frames(1)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 12, 1)
	w.set_hex("gate", "blue", 6, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 11)
	s.lock()
	s.lock()
	guard = 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	await p.frames(50)
	p.ok(th._on_land and lf.visible, "skip: the land is tipping up")
	th._skip()
	guard = 0
	while (th.visible or lf.visible) and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(not th.visible and not lf.visible, "skip mid-tilt: the land closes back into the board (%d frames)" % guard)
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	await snap("skip_board_again")
	p.ok(s.pending.is_empty(), "skip mid-tilt: the round still resolves")
	main.queue_free()
	await p.frames(5)


func _into_battle(gs: Control, th: Control, tag: String) -> void:
	var guard := 0
	var swooped := false
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		if gs.cinema._waiting and not swooped:
			swooped = true
			await p.frames(20)
			await snap(tag + "_00_swoop")
		await p.frames(1)
	await p.frames(45)
	await snap(tag + "_01_tipping_up")


func _fight(gs: Control, th: Control, lf: Control, tag: String, shots: int) -> void:
	var guard := 0
	while th._state == "idle" and guard < 600:
		guard += 1
		await p.frames(1)
	var dio: Node3D = lf.dio
	await p.frames(int(dio.arrival() * 60.0) + 30)
	await snap(tag + "_02_march_in")
	## everyone where they came from, in the band the words leave clear
	var outside := 0
	for ai in dio.armies.size():
		var sp: Vector2 = lf.screen_of(ai)
		if sp.y < lf.BAND_TOP - 30.0 or sp.y > lf.size.y - lf.BAND_BOTTOM + 30.0 or sp.x < 0.0 or sp.x > lf.size.x:
			outside += 1
	var where := ""
	for ai in dio.armies.size():
		where += " %s(%.0f,%.0f)" % [dio.armies[ai]["pid"], lf.screen_of(ai).x, lf.screen_of(ai).y]
	p.ok(outside == 0, "%s: every army stands between the words and the dice (%d outside:%s)" % [tag, outside, where])
	for ai in dio.armies.size():
		var gs0: Array = dio.armies[ai]["groups"]
		if gs0.size() == 1 and (gs0[0] as Dictionary).has("cross"):
			for bi in dio.armies.size():
				var gb: Array = dio.armies[bi]["groups"]
				if bi != ai and gb.size() == 1 and (gb[0] as Dictionary).has("cross") and (gb[0]["cross"] as Vector2).distance_to(gs0[0]["cross"]) > 20.0:
					var c: Vector2 = gs0[0]["at"]
					p.ok(c.distance_to(gs0[0]["cross"]) < c.distance_to(gb[0]["cross"]), "%s: %s stands nearer its own border than %s's" % [tag, dio.armies[ai]["pid"], dio.armies[bi]["pid"]])
	var mismatch := 0
	var exchanges := 0
	var shot := 0
	guard = 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				th._answer("p")
				exchanges += 1
				## one die, one man: the figures standing are the count, army by army
				await p.frames(70)
				for ai in dio.armies.size():
					var need := 0
					var shares := 0
					for g in dio.armies[ai]["groups"]:
						var want: Dictionary = Diorama.pieces(int(g["share"]))
						need += int(want["inf"]) + int(want["cav"]) + int(want["gun"])
						shares += int(g["share"])
					var have := 0
					for f in dio.figs:
						if int(f["army"]) == ai and f["alive"] and bool(f["counts"]):
							have += 1
					if have != need or shares != int(dio.armies[ai]["n"]):
						mismatch += 1
				if shot < shots:
					shot += 1
					await snap("%s_03_after_exchange_%d" % [tag, shot])
			"done":
				await p.frames(60)
				await snap(tag + "_04_result")
				th.press()
		await p.frames(1)
	p.ok(mismatch == 0, "%s: the figures standing always match the count (%d exchanges, %d off)" % [tag, exchanges, mismatch])


func _out_of_battle(gs: Control, th: Control, lf: Control, tag: String) -> void:
	var guard := 0
	while (th.visible or lf.visible) and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(not th.visible and not lf.visible, "%s: the land closes back into the board" % tag)
	await p.frames(30)
	await snap(tag + "_05_board_again")
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(gs.board.visible, "%s: the board is the board again" % tag)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
