## v2.1 (rules 21) in the real client, on the land: one commander storming a land from two of his
## own is a battle of two fronts, his columns standing apart where they came from, one face and "and
## from …" for the second; a big battle brings each army's train (horse and guns as well as its men,
## never its count); and the battle's words are wiped when it ends ("THE LAST MAN STANDING!" and
## "FALL BACK!" stayed into the next battle).
##   SHOT_DIR=/dir ./scripts/shot.sh v21
extends RefCounted

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
	await _two_fronts()
	await _clash_spares_the_other()
	await _mixed_melee()
	await _big_battle()


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


func _seats() -> Array:
	return [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]


func _ready_land(gs: Control) -> void:
	var lf: Control = gs.theater._land_field
	var guard := 0
	while not lf.prepared and guard < 600:
		guard += 1
		await p.frames(1)


func _into_battle(gs: Control, th: Control) -> void:
	var guard := 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	guard = 0
	while th._state == "idle" and guard < 600:
		guard += 1
		await p.frames(1)


func _value(dio: Node3D, ai: int) -> int:
	## what an army's counting pieces stand for: a man, a horse for five, a gun for ten
	var v := 0
	for f in dio.figs:
		if int(f["army"]) == ai and f["alive"] and bool(f["counts"]):
			v += {"inf": 1, "cav": 5, "gun": 10}.get(str(f["kind"]), 0)
	return v


func _fight_out(gs: Control, th: Control) -> void:
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				th._answer("p")
			"done":
				await p.frames(40)
				th.press()
		await p.frames(1)


func _two_fronts() -> void:
	var r: Array = await _game("res://maps/knife7.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	await _ready_land(gs)
	p.ok(s.map.rules >= 21, "a new game plays rules 21 or later (%d)" % s.map.rules)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 10, 1)
	w.set_hex("harbor", "red", 10, 1)
	w.set_hex("gate", "blue", 9, 1)
	for id in ["beacon", "mill", "docks", "quarry"]:
		w.set_hex(id, "blue", 2)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 9)
	s.set_attack("harbor", "gate", 9)
	s.lock()
	s.lock()
	await _into_battle(gs, th)
	var fronts: Array = th._fronts
	p.ok(th._melee and fronts.size() == 2 and str(fronts[0]["attackerId"]) == "red" and str(fronts[1]["attackerId"]) == "red",
		"Dad storms The Gate from Ridge and from Harbor: one battle of two fronts, both his (%d fronts)" % fronts.size())
	p.ok(th._sub.text.contains("from two sides"), "the battle says so: \"%s\"" % th._sub.text)
	var ex: Array = th._extra
	p.ok(ex.is_empty() and th._count_a.text == "9 + 9", "his second front has no ring of its own: its men stand beside his on his own count (\"%s\")" % th._count_a.text)
	var dio: Node3D = lf.dio
	await p.frames(int(dio.arrival() * 60.0) + 30)
	var reds: Array = []
	var blue := Vector2.ZERO
	for a in dio.armies:
		if str(a["pid"]) == "red":
			reds.append((a["groups"][0]["at"]) as Vector2)
		else:
			blue = a["groups"][0]["at"]
	var between := false
	if reds.size() == 2:
		## the defenders stand between his columns: from them, the two lie on opposite sides
		between = ((reds[0] as Vector2) - blue).normalized().dot(((reds[1] as Vector2) - blue).normalized()) < 0.0
	p.ok(reds.size() == 2 and between, "on the land his two columns come at the defenders from two sides, the defenders between them")
	await snap("v21_01_two_fronts")
	## the words of a battle go with it
	th._shout_text("THE LAST MAN STANDING!", Color(1, 0.9, 0.5))
	await _fight_out(gs, th)
	var guard := 0
	while lf.visible and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(th._shout.text == "" and is_zero_approx(th._shout.modulate.a), "the battle's shout is wiped when it ends (\"%s\", %.2f)" % [th._shout.text, th._shout.modulate.a])
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _clash_spares_the_other() -> void:
	## (the outside review, RV-002 F1) Dad marches on The Gate from Ridge and from Harbor; Varek
	## marches out of The Gate on Ridge. The clash is Ridge's column against his; Harbor's column, on
	## another border, marches on with all its men, and its arrow stays on the map
	Settings.data["battles"] = "off"
	var r: Array = await _game("res://maps/knife7.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 10, 1)
	w.set_hex("harbor", "red", 10, 1)
	w.set_hex("gate", "blue", 14, 1)
	for id in ["beacon", "mill", "docks", "quarry"]:
		w.set_hex(id, "blue", 2)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 9)
	s.set_attack("harbor", "gate", 7)
	s.lock()
	s.set_attack("gate", "ridge", 8)
	s.lock()
	var cin: Control = gs.cinema
	var guard := 0
	while guard < 1500:
		guard += 1
		await p.frames(1)
		if cin.index >= 0 and cin.index < cin.beats.size() and str((cin.beats[cin.index] as Dictionary).get("event", {}).get("kind", "")) == Types.EVENT_CLASH:
			break
	## past the break
	guard = 0
	while (b.clash_fx.is_empty() or not b.clash_fx.has("won") or b.clash_hides("ridge", "gate")) and guard < 600:
		guard += 1
		await p.frames(1)
	var harbor := -1
	for o in b.orders:
		if str(o["from"]) == "harbor" and str(o["to"]) == "gate":
			harbor = int(o["strength"])
	p.ok(harbor == 7, "rules 21: the clash on Ridge's border leaves Dad's column from Harbor marching on The Gate with all its men (%d)" % harbor)
	gs.cinema.skip()
	Settings.data["battles"] = "mine"
	main.queue_free()
	await p.frames(5)


func _mixed_melee() -> void:
	## (RV-004 F2) Dad from Ridge and from Harbor, Ysolde from Docks, all on The Gate: two armies on
	## three fronts, and the battle says so; Ysolde has her face, Dad's second front its land
	var seats: Array = _seats() + [{"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"}]
	var r: Array = await _game("res://maps/knife7.json", seats)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	await _ready_land(gs)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 10, 1)
	w.set_hex("harbor", "red", 10, 1)
	w.set_hex("docks", "green", 10, 1)
	w.set_hex("gate", "blue", 12, 1)
	for id in ["beacon", "mill", "quarry"]:
		w.set_hex(id, "blue", 2)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 8)
	s.set_attack("harbor", "gate", 8)
	s.lock()
	s.lock()
	s.set_attack("docks", "gate", 8)
	s.lock()
	await _into_battle(gs, th)
	var ex: Array = th._extra
	var faces: int = ex.size()
	var joined: bool = th._count_a.text == "8 + 8" or (ex.size() == 1 and str((ex[0]["count"] as Label).text) == "8 + 8")
	p.ok(th._melee and th._fronts.size() == 3 and th._sub.text.begins_with("2 armies storm it from three sides"),
		"Dad from two lands and Ysolde from a third: \"%s\"" % th._sub.text)
	p.ok(faces == 1 and joined, "beside the lead, one more ring (two commanders, two rings), and Dad's two fronts on his one count \"8 + 8\" (%d more rings)" % faces)
	## four armies on the field (three fronts and the defenders): every one in the band the words and
	## the dice leave clear
	var lf: Control = th._land_field
	var dio: Node3D = lf.dio
	await p.frames(int(dio.arrival() * 60.0) + 40)
	var outside := 0
	var where := ""
	for ai in dio.armies.size():
		var sp: Vector2 = lf.screen_of(ai)
		where += " %s(%.0f,%.0f)" % [dio.armies[ai]["pid"], sp.x, sp.y]
		if sp.y < lf.BAND_TOP - 30.0 or sp.y > lf.size.y - lf.BAND_BOTTOM + 30.0 or sp.x < 0.0 or sp.x > lf.size.x:
			outside += 1
	p.ok(dio.armies.size() == 4 and outside == 0, "four armies on the field, every one between the words and the dice (%d outside:%s)" % [outside, where])
	await snap("v21_05_mixed_melee")
	th._skip()
	var guard := 0
	while th.visible and guard < 600:
		guard += 1
		await p.frames(1)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _big_battle() -> void:
	var r: Array = await _game("res://maps/knife7.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	await _ready_land(gs)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 40, 1)
	w.set_hex("gate", "blue", 31, 2)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 38)
	s.lock()
	s.lock()
	await _into_battle(gs, th)
	var dio: Node3D = lf.dio
	await p.frames(int(dio.arrival() * 60.0) + 40)
	var ok := true
	var desc := ""
	for ai in dio.armies.size():
		var n: int = int(dio.armies[ai]["n"])
		var tr: Dictionary = Diorama.battle_train(n)
		var horse: int = dio.figs.filter(func(f): return int(f["army"]) == ai and f["alive"] and f["kind"] == "cav" and not bool(f["counts"])).size()
		var guns: int = dio.figs.filter(func(f): return int(f["army"]) == ai and f["alive"] and f["kind"] == "gun" and not bool(f["counts"])).size()
		desc += " %s %d: %d horse %d guns, count %d;" % [dio.armies[ai]["pid"], n, horse, guns, _value(dio, ai)]
		ok = ok and horse == int(tr["horse"]) and guns == int(tr["guns"]) and _value(dio, ai) == n
	p.ok(ok, "a big battle: each army brings its train as well as its men, and its counting pieces are still its count:%s" % desc)
	await snap("v21_02_big_battle")
	## a few exchanges in: still the count, and the train still standing
	var calls := 0
	var guard := 0
	var counted := true
	while th.visible and calls < 3 and guard < 6000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				await p.frames(70)
				for ai in dio.armies.size():
					counted = counted and _value(dio, ai) == int(dio.armies[ai]["n"])
				calls += 1
				th._answer("p")
		await p.frames(1)
	var train_up: int = dio.figs.filter(func(f): return f["alive"] and not bool(f["counts"]) and (f["kind"] == "cav" or f["kind"] == "gun")).size()
	p.ok(counted and train_up > 0, "three exchanges in: the counting pieces are still the count, and no casualty took a gun or horse of the train (%d standing)" % train_up)
	await snap("v21_03_big_battle_fighting")
	## to the end: an army destroyed is down to the last piece, its train with it (RV-001 F2)
	var standing := -1
	guard = 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				th._answer("p")
			"done":
				await p.frames(90)
				for ai in dio.armies.size():
					if int(dio.armies[ai]["n"]) == 0:
						standing = dio.figs.filter(func(f): return int(f["army"]) == ai and f["alive"]).size()
				await snap("v21_04_big_battle_end")
				th.press()
				break
		await p.frames(1)
	p.ok(standing == 0, "the battle's loser is destroyed to the last piece, its horse and guns too (%d left standing)" % standing)
	await _fight_out(gs, th)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
