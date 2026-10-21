## v2.2 in the real client, on the land: which dice are rolling where. Dad storms The Gate from
## Ridge and from Harbor, and both fronts' dice wear his colour; each pair on the table now carries
## a tag naming its front, the same name his column carries on its plate on the field, a thread runs
## from the tag to that column as the pair is read, and the shots are seen to fly from the side that
## won the pair at the men across from it. And (rules 22) when Varek's favour throws away an exchange
## that had gone Dad's way, the battle says Fortune owes Dad for it.
##   SHOT_DIR=/dir ./scripts/shot.sh v22
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const Diorama := preload("res://game/world3d/diorama.gd")
const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")
const FrontMarks := preload("res://game/ui/front_marks.gd")

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
	await _dice_find_their_fronts()
	await _fortune_owed()
	await _free_for_all()


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


func _fight_out(th: Control) -> void:
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				th._answer(Combat.CALL_PRESS)
			"done":
				await p.frames(40)
				th.press()
		await p.frames(1)


func _plate_tag(lf: Control, ai: int) -> String:
	for q in lf._plates:
		if int(q["army"]) == ai:
			var l: Label = q["tag"]
			return l.text if l.visible else ""
	return ""


func _dice_find_their_fronts() -> void:
	var r: Array = await _game("res://maps/knife7.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	var lf: Control = th._land_field
	await _ready_land(gs)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 15, 1)
	w.set_hex("harbor", "red", 10, 1)
	w.set_hex("gate", "blue", 12, 1)
	for id in ["beacon", "mill", "docks", "quarry"]:
		w.set_hex(id, "blue", 2)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 9)
	s.set_attack("harbor", "gate", 9)
	s.set_attack("ridge", "mill", 5) ## and a plain assault in the same report (RV-005: nothing of the melee may carry into it)
	s.lock()
	s.lock()
	await _into_battle(gs, th)
	var plain_first: bool = not th._melee
	if plain_first:
		## the assault on Mill came first: fight it, and meet the melee next
		await _fight_out(th)
		await _into_battle(gs, th)
	var dio: Node3D = lf.dio
	## (B-014) a ball is in the air a third of a second: a frame a second (the bot's box) can fire
	## and land it unseen, so while the shots are watched a frame is a 60th of a second
	p.steady(true)
	await p.frames(int(dio.arrival() * 60.0) + 30)
	p.ok(th._melee and th._one_commander() and th._fronts.size() == 2, "Dad storms The Gate from two of his own lands: one battle, two fronts, one colour")
	var t0: String = _plate_tag(lf, 0)
	var t1: String = _plate_tag(lf, 1)
	p.ok(t0 == th._front_tag(0) and t1 == th._front_tag(1) and t0 != t1 and t0.begins_with("from ") and _plate_tag(lf, 2) == "",
		"on the field each of his columns carries its name on its plate (\"%s\", \"%s\"); the defenders' plate carries none" % [t0, t1])
	## roll, and watch an exchange or two: the tags on the table, the threads, the shots
	var tags_ok := true
	var tag_count := 0
	var placed_ok := true
	var ordered := true
	var threads_ok := true
	var off := 0.0
	var hues_ok := true
	var winners := {}
	var threaded := {}
	var shots := 0
	var shots_ok := true
	var shooters := {}
	var seen := {}
	var shot_taken := false
	var flight_taken := false
	var tray: Control = th._tray
	var marks: Control = th._marks
	var exchanges := 0
	var guard := 0
	while th.visible and exchanges < 3 and guard < 6000:
		guard += 1
		match str(th._state):
			"ready":
				if th._exchange > exchanges:
					exchanges = th._exchange
				if exchanges < 3:
					th.press()
			"call":
				th._answer(Combat.CALL_PRESS)
			"done":
				break
		await p.frames(1)
		## the tags: one over each pair, naming the front its left die throws for, on the far rail
		## between the pair's two dice
		if not marks.tags.is_empty() and not seen.has(marks.tags[0]["node"].get_instance_id()):
			## a new throw: its pairs lie as their fronts stand, left to right
			var last := -INF
			for tg in marks.tags:
				var x: float = lf.screen_of(int((tg["armies"] as Array)[0])).x
				ordered = ordered and x >= last
				last = x
		for k in marks.tags.size():
			var tg: Dictionary = marks.tags[k]
			if seen.has(tg["node"].get_instance_id()):
				continue
			seen[tg["node"].get_instance_id()] = true
			tag_count += 1
			var ai: int = int((tg["armies"] as Array)[0]) if not (tg["armies"] as Array).is_empty() else -1
			tags_ok = tags_ok and ai >= 0 and str(tg["text"]) == th._front_tag(ai)
			var node: Control = tg["node"]
			var cx: float = node.position.x + node.size.x * 0.5
			var l: float = tray.position.x + tray.die_screen(k * 2).x
			var rr: float = tray.position.x + tray.die_screen(k * 2 + 1).x
			placed_ok = placed_ok and cx > minf(l, rr) - 40.0 and cx < maxf(l, rr) + 40.0
		for t in marks.threads:
			var ai: int = int(t["army"])
			threaded[ai] = true
			## the thread is in the colours of whoever won its pair (Dad's or Varek's), parchment if even
			var won: String = str(t["won"])
			winners[won] = true
			hues_ok = hues_ok and ["red", "blue", ""].has(won) and (t["col"] as Color).is_equal_approx(FrontMarks.thread_colour(won))
			var want: Vector2 = lf.plate_point(ai)
			if want.x >= 0.0:
				off = maxf(off, (t["to"] as Vector2).distance_to(want))
		for tr in dio.tracers:
			var id: int = (tr["node"] as Node).get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			shots += 1
			var a: int = int(tr["army"])
			var foe: int = int(tr["foe"])
			shooters[a] = true
			if foe < 0:
				shots_ok = false
				continue
			var at: Vector2 = dio.armies[foe]["groups"][dio.group_against(foe, a)]["at"]
			shots_ok = shots_ok and (tr["aim"] as Vector2).distance_to(at) < Diorama.FIG * 3.0
		if not shot_taken and not marks.threads.is_empty() and not dio.tracers.is_empty():
			shot_taken = true
			await snap("v22_01_dice_find_their_fronts")
		elif shot_taken and not flight_taken:
			var mid: Array = dio.tracers.filter(func(tr): return float(tr["t"]) / float(tr["dur"]) > 0.35 and float(tr["t"]) / float(tr["dur"]) < 0.7)
			if mid.size() >= 3:
				flight_taken = true
				await snap("v22_03_shots_in_flight")
	p.steady(false)
	p.ok(tag_count >= 3 and tags_ok, "on the table every pair carries a tag naming the front its dice are for (%d tags)" % tag_count)
	p.ok(placed_ok, "each tag hangs over its own pair of dice")
	p.ok(ordered, "a throw's pairs lie on the table as their fronts stand on the field, left to right")
	threads_ok = off < 12.0
	p.ok(threads_ok and threaded.has(0) and threaded.has(1), "as a pair is read a thread runs from its tag to that front's plate on the field, for both fronts (%s, ends at most %.0f px off)" % [str(threaded.keys()), off])
	p.ok(hues_ok and winners.has("red") and winners.has("blue"), "each thread is in its pair's winner's colours: Dad's red when his front won it, Varek's blue when the defenders did (%s)" % str(winners.keys()))
	p.ok(shots > 0 and shots_ok and shooters.size() >= 2, "the shots fly: %d seen, each from the side that won its pair at the men facing it across the field (%d sides fired)" % [shots, shooters.size()])
	p.ok(shot_taken, "a moment with a thread and shots in the air was caught (v22_01)")
	await _fight_out(th)
	marks = th._marks
	p.ok(marks.tags.is_empty() and marks.threads.is_empty(), "the battle over, the tags and threads are gone with the dice")
	## (RV-005, the planted P2 and P3) the next battle, a plain assault, carries nothing of the melee
	p.ok(not plain_first, "the melee came before the plain assault in the report (else the next fact proves nothing)")
	await _into_battle(gs, th)
	p.ok(th.visible and not th._melee and not th._scramble, "then Dad's assault on Mill from Ridge")
	var stale: Array = []
	for ai in 3:
		var tg: String = _plate_tag(lf, ai)
		if tg != "":
			stale.append(tg)
	p.ok(stale.is_empty() and lf.dio.tracers.is_empty() and th._marks.tags.is_empty(),
		"and nothing of the melee comes with it: no front names on its plates %s, no shots in the air (%d), no tags on the table" % [str(stale), lf.dio.tracers.size()])
	await _fight_out(th)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _fortune_owed() -> void:
	## Varek holds a favour and spends it on the first exchange that goes badly for him
	var r: Array = await _game("res://maps/knife7.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	await _ready_land(gs)
	p.ok(s.map.rules >= 22 and s.map.fortune, "a new game plays rules 22 with Fortune (%d)" % s.map.rules)
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 16, 1)
	w.set_hex("gate", "blue", 12, 1)
	for id in ["beacon", "mill", "docks", "quarry", "harbor"]:
		w.set_hex(id, "blue", 2)
	(w.players["blue"] as Types.PlayerState).fortune = 1
	(w.players["red"] as Types.PlayerState).fortune = 0
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 15)
	s.lock()
	s.lock()
	await _into_battle(gs, th)
	## (RV-005 F5) before the dice: Dad's line fires on Varek's eight times; each time the first of
	## Varek's men to fall goes down no sooner than the first ball reaches him
	var dio: Node3D = th._land_field.dio
	p.steady(true) ## (B-014) a ball's landing and a man's fall a 60th of a second apart, at any frame rate
	await p.frames(int(dio.arrival() * 60.0) + 30)
	var early := 0
	var timed := 0
	for k in 8:
		var standing := {}
		for f in dio.figs:
			if int(f["army"]) == 1 and f["alive"]:
				standing[f] = true
		var old := {}
		for tr in dio.tracers:
			old[tr["node"]] = true
		dio.volley(0, 1)
		dio.set_count(1, int(dio.armies[1]["n"]) - 1, 0)
		var landed := -1.0
		var fell := -1.0
		var flying := {}
		for fr in 90:
			await p.frames(1)
			var now: float = dio._clock
			for tr in dio.tracers:
				if not old.has(tr["node"]) and int(tr["army"]) == 0:
					flying[tr["node"]] = tr
					if landed < 0.0 and float(tr["t"]) >= float(tr["dur"]):
						landed = now
			for nd in flying.keys():
				if landed < 0.0 and not dio.tracers.has(flying[nd]):
					landed = now ## struck and gone this frame
			for f in standing.keys():
				if fell < 0.0 and str(f["state"]) == "fall" and float(f["t"]) >= 0.0:
					fell = now
			if landed >= 0.0 and fell >= 0.0:
				break
		if landed >= 0.0 and fell >= 0.0:
			timed += 1
			if fell < landed - 1.5 / 60.0:
				early += 1
		await p.frames(30)
	p.steady(false)
	p.ok(timed >= 6 and early == 0, "the first man falls as the first ball reaches him, never before it (%d volleys timed, %d early)" % [timed, early])
	var spent := false
	var said := ""
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				var pend: Dictionary = s.pending
				if bool(pend.get("fortune", false)) and str(pend.get("chooser", "")) == "blue" and not spent:
					spent = true
					th._answer(Combat.CALL_FORTUNE)
				else:
					th._answer(Combat.CALL_PRESS)
			"done":
				await p.frames(40)
				th.press()
		await p.frames(1)
		if spent and said == "" and th._sub.text.contains("owed for it"):
			said = th._sub.text
			await snap("v22_02_fortune_owed")
	p.ok(spent, "an exchange went badly for Varek and he called on Fortune")
	var fits: bool = Style.font("italic").get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, th._sub.get_theme_font_size("font_size")).x <= th.size.x - 600.0
	p.ok(said.contains("Dad is owed for it") and fits, "the battle says Dad is owed for the exchange it took from him, in a line that fits between the faces: \"%s\"" % said)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _free_for_all() -> void:
	## (RV-005 F3) three commanders march on an empty land: a free-for-all's pairs lie on the table by
	## the middle of their two armies on the field, and each names both ("Ridge vs Docks")
	var seats := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 71, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": seats})
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
	var th: Control = gs.theater
	await _ready_land(gs)
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
	for o in [["green", "docks", 8], ["blue", "harbor", 7]]:
		var sh := Types.Sheet.new()
		sh.player_id = o[0]
		var pk := Types.Packet.new()
		pk.from_id = o[1]
		pk.to_id = "gate"
		pk.strength = o[2]
		pk.stance = "hold"
		sh.packets = [pk]
		s.locked[o[0]] = sh
	s.lock()
	var lf: Control = th._land_field
	var throws := 0
	var ordered := true
	var named := true
	var seen := {}
	guard = 0
	while guard < 9000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			if th._scramble and not th._marks.tags.is_empty() and not seen.has(th._marks.tags[0]["node"].get_instance_id()):
				seen[th._marks.tags[0]["node"].get_instance_id()] = true
				throws += 1
				var last := -INF
				for tg in th._marks.tags:
					var ar: Array = tg["armies"]
					var x: float = (lf.screen_of(int(ar[0])).x + lf.screen_of(int(ar[1])).x) * 0.5
					ordered = ordered and x >= last
					last = x
					named = named and str(tg["text"]) == "%s vs %s" % [th._front_tag(int(ar[0])).trim_prefix("from "), th._front_tag(int(ar[1])).trim_prefix("from ")]
				if throws == 1:
					await snap("v22_04_free_for_all")
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer(Combat.CALL_PRESS)
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(throws >= 2 and named, "in a free-for-all every pair names both its armies by where they came from (%d throws)" % throws)
	p.ok(throws >= 2 and ordered, "and a throw's pairs lie by the middle of their two armies on the field, left to right")
	main.queue_free()
	await p.frames(5)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
