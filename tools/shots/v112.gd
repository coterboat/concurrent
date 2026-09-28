## v1.12 in the real client: three commanders march on the same empty land at once (the scramble,
## drawn as a free-for-all), and the border clash's losers' arrows cleared off the map.
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
	Settings.data["battles"] = "all"
	Settings.data["roll_yourself"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	await _three_way(main)
	await _five_way(main)
	for mode in ["all", "mine"]:
		Settings.data["battles"] = mode
		await _clash(main, mode)
	p.log("v112 probe done")


const SEATS := [
	{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
	{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
	{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
	{"id": "gold", "name": "Marshal Quill", "kind": "ai", "ai": "quill", "portrait": "quill"},
	{"id": "purple", "name": "Lady Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"}]


func _start(main: Control, seed: int, map_path: String = "res://maps/knife7.json", n: int = 3) -> Array:
	main.start_game({"map": map_path, "seed": seed, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": SEATS.slice(0, n)})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	return [s, gs]


func _order(s: Node, pid: String, from: String, to: String, n: int) -> void:
	var sh := Types.Sheet.new()
	sh.player_id = pid
	var pk := Types.Packet.new()
	pk.from_id = from
	pk.to_id = to
	pk.strength = n
	pk.stance = "hold"
	sh.packets = [pk]
	s.locked[pid] = sh


func _three_way(main: Control) -> void:
	var r: Array = await _start(main, 71)
	var s: Node = r[0]
	var gs: Control = r[1]
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 10, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("docks", "green", 9, 1)
	w.set_hex("quarry", "green", 2, 1)
	w.set_hex("harbor", "blue", 8, 1)
	w.set_hex("mill", "blue", 2, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 9)
	_order(s, "green", "docks", "gate", 8)
	_order(s, "blue", "harbor", "gate", 7)
	s.lock()
	var th: Control = gs.theater
	var seen := false
	var shots := 0
	var guard := 0
	while guard < 9000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			if th._scramble and not seen and str(th._state) == "ready":
				seen = true
				p.ok(th._fronts.size() == 3, "three armies in the scramble (%d)" % th._fronts.size())
				await p.frames(40)
				_stands_apart(th, "three")
				await snap("00_three_way_ready")
			match str(th._state):
				"ready", "done":
					if seen and shots < 2 and str(th._state) == "done":
						shots += 1
						await snap("01_three_way_exchange_%d" % shots)
					th.press()
				"call":
					th._answer("p")
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(seen, "three commanders marching on an empty land fight one free-for-all")
	## after the battles: the land fought over smoulders on the map, and the day wears on
	var g2 := 0
	while s.phase != Session.Phase.MANEUVER and s.phase != Session.Phase.PLANNING and g2 < 600:
		g2 += 1
		if s.phase == Session.Phase.RECAP:
			gs.recap.visible = false
			s.next_round()
		await p.frames(1)
	await p.frames(30)
	p.ok(gs.board.smoke.has("gate"), "The Gate, fought over, smoulders on the map (%s)" % str(gs.board.smoke.keys()))
	gs.board.focus_on(["gate"], 2.0)
	await p.frames(260) ## the phase banner fades
	await snap("03_smoke_over_the_gate")
	gs.board.set_daylight(gs.war_light(1.0), true)
	await p.frames(10)
	await snap("04_dusk_the_last_round")
	var mid: Color = gs.war_light(0.5)
	p.ok(gs.war_light(0.0).b > gs.war_light(0.0).r and gs.war_light(1.0).r > gs.war_light(1.0).b and mid.r >= 0.99, "the light runs from a cool morning to a red dusk")
	gs.board.set_daylight(Color(1, 1, 1), true)


func _stands_apart(th: Control, tag: String) -> void:
	## v1.13: the picture's facts, not just the count. The bug v1.12 fixed was two armies sharing a
	## side as if allied, and a ring standing beside the wrong army; assert neither can come back.
	var field: Control = th._field
	var armies: Array = field.armies
	var sides := {}
	var shared := false
	for a in armies:
		var sd: int = int(a["side"])
		if sd != 2 and sides.has(sd):
			shared = true
		sides[sd] = true
	var at: Array = armies.map(func(a): return "%s:%s" % [a["pid"], ["left", "right", "back"][int(a["side"])]])
	p.ok(armies.size() == th._fronts.size() and not shared and sides.has(0) and sides.has(1), "[%s] every army has its own ground, none sharing a side (%s)" % [tag, ", ".join(at)])
	var faces := {}
	var wrong: Array = []
	var sc: float = field.get_global_transform().get_scale().x
	var mid: float = th.get_global_rect().get_center().x
	for i in th._fronts.size():
		var face: Control = th._face_of_front(i)
		var a: Dictionary = armies[i]
		var fx: float = face.get_global_rect().get_center().x
		var right_place := false
		match int(a["side"]):
			0: right_place = fx < mid - 200.0
			1: right_place = fx > mid + 200.0
			2: right_place = absf(fx - (field.global_position.x + float(a["cx"]) * sc)) < 30.0 * sc
		if faces.has(face) or not right_place or str(face.pid) != str(a["pid"]):
			wrong.append("%s (ring at x=%d)" % [a["pid"], int(fx)])
		faces[face] = true
	p.ok(wrong.is_empty(), "[%s] each commander's ring stands over their own army %s" % [tag, str(wrong)])


func _five_way(main: Control) -> void:
	## the owner's poke: four or five commanders. Five armies on one empty land of the World:
	## the lead on the left, the next on the right, three in the back row, each ring over its army.
	var r: Array = await _start(main, 73, "res://maps/world30.json", 5)
	var s: Node = r[0]
	var gs: Control = r[1]
	var w: Types.World = s.world
	var target := ""
	var most := 0
	for t in w.territories.keys():
		var k: int = MapLib.neighbors(s.map, str(t)).size()
		if k > most:
			most = k
			target = str(t)
	var nb: PackedStringArray = MapLib.neighbors(s.map, target)
	p.ok(nb.size() >= 5, "the World has a land with five neighbours (%s: %d)" % [target, nb.size()])
	if nb.size() < 5:
		return
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	for i in 5:
		w.set_hex(nb[i], str(SEATS[i]["id"]), 11 - i, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(nb[0], target, 9)
	for i in range(1, 5):
		_order(s, str(SEATS[i]["id"]), nb[i], target, 9 - i)
	s.lock()
	var th: Control = gs.theater
	var seen := false
	var guard := 0
	while guard < 12000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			if th._scramble and not seen and str(th._state) == "ready":
				seen = true
				p.ok(th._fronts.size() == 5, "five armies in the scramble (%d)" % th._fronts.size())
				await p.frames(40)
				_stands_apart(th, "five")
				await snap("05_five_way_ready")
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer("p")
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(seen, "five commanders marching on an empty land fight one free-for-all")


func _clash(main: Control, mode: String) -> void:
	## Dad (ridge) and Varek (gate) march on each other's land: a border clash. Hask and Varek
	## clash too, away from us (harbor <-> docks). After each clash the loser's arrow must go.
	var r: Array = await _start(main, 91)
	var s: Node = r[0]
	var gs: Control = r[1]
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 9, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("gate", "blue", 6, 1)
	w.set_hex("harbor", "blue", 5, 1)
	w.set_hex("docks", "green", 7, 1)
	w.set_hex("quarry", "green", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 8)
	var bsh := Types.Sheet.new()
	bsh.player_id = "blue"
	for pr in [["gate", "ridge", 5], ["harbor", "docks", 4]]:
		var pk := Types.Packet.new()
		pk.from_id = pr[0]
		pk.to_id = pr[1]
		pk.strength = pr[2]
		pk.stance = "hold"
		bsh.packets.append(pk)
	s.locked["blue"] = bsh
	_order(s, "green", "docks", "harbor", 6)
	s.lock()
	var th: Control = gs.theater
	var cin: Control = gs.cinema
	var guard := 0
	var clashes: Array = []
	var stale: Array = []
	var shot := false
	while guard < 9000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer("p")
		elif cin.visible and not cin._waiting:
			## every clash already told: its loser's arrow must be gone from the map
			for k in range(0, mini(cin.index + 1, cin.beats.size())):
				var ev: Dictionary = (cin.beats[k] as Dictionary).get("event", {})
				if str(ev.get("kind", "")) != Types.EVENT_CLASH:
					continue
				var key := "%s|%s" % [ev["hexA"], ev["hexB"]]
				if not clashes.has(key):
					clashes.append(key)
				if k == cin.index and not cin._card.visible:
					pass
				var wid: String = str(ev["winnerId"])
				var loser: String = str(ev["playerB"]) if wid == str(ev["playerA"]) else str(ev["playerA"])
				var loser_to: String = str(ev["hexA"]) if loser == str(ev["playerB"]) else str(ev["hexB"])
				if k < cin.index or (k == cin.index and cin._rolling <= 0.0 and not cin._card.visible):
					for o in gs.board.orders:
						if str(o.get("owner", "")) == loser and str(o["to"]) == loser_to and not stale.has(key):
							stale.append(key)
							p.log("stale %s at beat %d/%d (clash beat %d, settled %s): %s" % [key, cin.index, cin.beats.size(), k, str(cin._settled.has(k)), str(o)])
							if not shot:
								shot = true
								await snap("02_clash_arrow_left_%s" % mode)
			cin.advance()
		await p.frames(1)
	p.ok(clashes.size() >= 2, "[%s] two border clashes told (%s)" % [mode, ", ".join(clashes)])
	p.ok(stale.is_empty(), "[%s] no beaten column's arrow is left on the map after its clash %s" % [mode, str(stale)])


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
