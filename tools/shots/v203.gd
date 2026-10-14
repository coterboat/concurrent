## v2.0.2, round two: the board's garrisons on the land are kept up, not re-formed, and a big army
## brings its train. The owner: "when troops are added it resets all of them in a region marching
## every time. it should be a seamless +1/-1 at each point", and "add in cavalry and cannons to the
## map … once forces gain enough size. not to replace soldiers, but as additions". The facts: a
## recruit placed keeps every man standing where he stood (the new one steps in from just behind),
## one taken back is lifted off, the other lands don't stir, and a zoom only shuffles them; a land of
## 20 stands its 5 men and a horseman and a gun as well, of 34 two of each; a column of 18 on the
## march has a horseman at its head and a gun at its tail.
##   SHOT_DIR=/dir ./scripts/shot.sh v203
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "off"
	Settings.data["speed"] = "normal"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	await _garrisons()
	await _column()


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


func _settle(gs: Control) -> void:
	var lb: Control = gs.land_board
	var guard := 0
	while not (lb.ready_to_show() and lb.settled()) and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(40)


func _seats() -> Array:
	return [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]


func _figs(gs: Control, land: String, alive_only: bool = true) -> Array:
	var ai: int = gs.board.art.order.find(land)
	return gs.land.garrisons.figs.filter(func(f): return int(f["army"]) == ai and (f["alive"] or not alive_only))


func _ids(list: Array) -> Dictionary:
	var out := {}
	for f in list:
		out[(f["node"] as Node3D).get_instance_id()] = f
	return out


func _garrisons() -> void:
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	var mine := ""
	var other := ""
	for id in b.art.order:
		var ts = b.world.get_territory(id)
		if ts.owner == "red" and ts.armies + ts.garrison <= 6:
			if mine == "":
				mine = id
			elif other == "":
				other = id
	p.ok(mine != "" and other != "", "two of red's lands to watch (%s, and %s)" % [mine, other])
	var before: Dictionary = _ids(_figs(gs, mine))
	var others: Dictionary = _ids(_figs(gs, other))
	var men0: int = b.world.get_territory(mine).armies + b.world.get_territory(mine).garrison
	await snap("v203_01_before")
	## +2: one more man in the garrison (one for every two)
	var err: String = s.add_place(mine, 2)
	await p.frames(45)
	var now: Array = _figs(gs, mine)
	var kept := 0
	var far := 0
	var fresh := 0
	for f in now:
		var id: int = (f["node"] as Node3D).get_instance_id()
		if before.has(id):
			kept += 1
		else:
			fresh += 1
			if float(f.get("dur", 2.6)) > 0.81:
				far += 1
	for f in now:
		if before.has((f["node"] as Node3D).get_instance_id()) and f["state"] == "march" and float(f.get("dur", 2.6)) > 0.61:
			far += 1
	var men1: int = b.world.get_territory(mine).armies + b.world.get_territory(mine).garrison
	var want: int = clampi(int(ceil(float(men1) / 2.0)), 1, 5)
	var counting: int = now.filter(func(f): return bool(f["counts"])).size()
	p.ok(err == "" and men1 == men0 + 2, "two recruits placed on %s (%d → %d men)" % [mine, men0, men1])
	p.ok(kept == before.size() and counting == want, "every man who stood on %s still stands, and the garrison is its %d (%d kept, %d new)" % [mine, want, kept, fresh])
	p.ok(far == 0, "nobody marches in from afar: the new man steps in from just behind, the rest only shuffle (%d from afar)" % far)
	var still := true
	var others_now: Dictionary = _ids(_figs(gs, other))
	for id in others.keys():
		still = still and others_now.has(id)
	p.ok(still and others_now.size() == others.size(), "%s, next door, doesn't stir" % other)
	await snap("v203_02_placed")
	## taken back: lifted off the table, the rest untouched
	s.add_place(mine, -2)
	await p.frames(45)
	var back: Array = _figs(gs, mine)
	var lifted: int = _figs(gs, mine, false).filter(func(f): return not f["alive"] and f["state"] == "lift" and not (f["node"] as Node3D).visible).size()
	var all_old := true
	var back_ids: Dictionary = _ids(back)
	for id in before.keys():
		all_old = all_old and back_ids.has(id)
	p.ok(all_old and back.filter(func(f): return bool(f["counts"])).size() == clampi(int(ceil(float(men0) / 2.0)), 1, 5) and (fresh == 0 or lifted >= 1),
		"taken back: the extra man is lifted off the table and gone from it, the others stand where they stood (%d lifted)" % lifted)
	## a zoom moves the garrisons' spots (they keep beside their tokens): they shuffle, nobody's new
	var all_before: Dictionary = _ids(gs.land.garrisons.figs.filter(func(f): return f["alive"]))
	b.zoom_at(b.size * 0.5, 1.5)
	await p.frames(60)
	var all_after: Dictionary = _ids(gs.land.garrisons.figs.filter(func(f): return f["alive"]))
	var same := 0
	for id in all_before.keys():
		if all_after.has(id):
			same += 1
	p.ok(same == all_before.size() and all_after.size() == all_before.size(), "zoomed in: every garrison keeps its men, shuffled to their spots (%d of %d the same)" % [same, all_before.size()])
	b.reset_view()
	await p.frames(30)
	## the train: horse and guns as well as the men
	var w: Types.World = s.world
	w.set_hex(mine, "red", 19, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(60)
	var t20: Array = _figs(gs, mine)
	var horse: int = t20.filter(func(f): return f["kind"] == "cav" and not bool(f["counts"])).size()
	var guns: int = t20.filter(func(f): return f["kind"] == "gun" and not bool(f["counts"])).size()
	var men20: int = t20.filter(func(f): return bool(f["counts"])).size()
	p.ok(horse == 1 and guns == 1 and men20 == 5, "a land of 20: its 5 men stand, and a horseman and a gun as well (%d horse, %d guns, %d men)" % [horse, guns, men20])
	b.swoop_to([mine], 3.0, 0.05)
	await p.frames(60)
	await snap("v203_03_train_20")
	w.set_hex(mine, "red", 33, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(60)
	var t34: Array = _figs(gs, mine)
	horse = t34.filter(func(f): return f["kind"] == "cav").size()
	guns = t34.filter(func(f): return f["kind"] == "gun").size()
	p.ok(horse == 2 and guns == 2 and t34.filter(func(f): return bool(f["counts"])).size() == 5, "a land of 34: two horsemen and two guns with its men (%d, %d)" % [horse, guns])
	await snap("v203_04_train_34")
	b.restore_view()
	main.queue_free()
	await p.frames(5)


func _column() -> void:
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	var w: Types.World = s.world
	var from := ""
	var to := ""
	for id in b.art.order:
		if w.get_territory(id).owner == "red":
			for n in MapLib.neighbors(b.map, id):
				if w.get_territory(str(n)).owner == "blue" and MapLib.is_adjacent(b.map, id, str(n)):
					from = id
					to = str(n)
					break
		if from != "":
			break
	w.set_hex(from, "red", 20, 1)
	w.set_hex(to, "blue", 2, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(from, to, 18)
	s.lock()
	s.lock()
	var col: Dictionary = {}
	var seen_horse := false
	var seen_gun := false
	var guard := 0
	while guard < 900 and not (seen_horse and seen_gun):
		guard += 1
		await p.frames(1)
		for c in gs.land.marches.columns.values():
			if c["from"] == from and c["to"] == to:
				col = c
				seen_horse = seen_horse or (c.get("horse", null) != null and (c["horse"] as Node3D).visible)
				seen_gun = seen_gun or (c.get("gun", null) != null and (c["gun"] as Node3D).visible)
	## (a short road is shorter than the whole column: the horseman may ride into the land it takes
	## before the gun has rolled out of the one it left)
	p.ok(seen_horse and seen_gun, "a column of 18 on the march: a horseman rides at its head and a gun rolls at its tail (%d frames)" % guard)
	if not col.is_empty():
		b.swoop_to([from, to], 2.6, 0.05)
		await p.frames(20)
		await snap("v203_05_column_train")
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
