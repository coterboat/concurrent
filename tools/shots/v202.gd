## v2.0.2: the battle report on the land, made to feel like one. The owner, after playing v2.0:
## "make sure border clashes show both arrows colliding, with the winner's carrying through". The
## facts: the report's camera leans in on the clash with both lands clear of its card, the stage's
## banner gives way, the two arrows charge and meet head-on between the lands (each with its count),
## the tin columns march to the middle of the road and stand there face to face; at the break the
## winner's arrow drives the loser's back into its land, its count falling to the men left, the
## loser's figures fall and the winner's march on; then the winner's own arrow carries on, and when
## the report ends the camera gives back the view it found.
##   SHOT_DIR=/dir ./scripts/shot.sh v202
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Style := preload("res://game/core/style.gd")

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
	await _clash()
	await _pictures()
	await _theater()
	await _skip_mid_swoop()
	await _stills()
	await _surge_clash()
	await _old_rules_clash()
	await _region_moment()
	await _stale_question()


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


func _settle(gs: Control) -> int:
	var lb: Control = gs.land_board
	var guard := 0
	while not (lb.ready_to_show() and lb.settled()) and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(30)
	return guard


func _seats() -> Array:
	return [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"}]


func _stage(gs: Control, s: Node) -> Array:
	## a red land and a blue land on one border, each marching on the other
	var b: Control = gs.board
	var w: Types.World = s.world
	var red_land := ""
	var blue_land := ""
	for id in b.art.order:
		if w.get_territory(id).owner == "red":
			for n in MapLib.neighbors(b.map, id):
				if w.get_territory(str(n)).owner == "blue":
					red_land = id
					blue_land = str(n)
					break
		if red_land != "":
			break
	w.set_hex(red_land, "red", 14, 1)
	w.set_hex(blue_land, "blue", 9, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(red_land, blue_land, 13)
	s.lock()
	s.set_attack(blue_land, red_land, 8)
	s.lock()
	return [red_land, blue_land]


func _to_clash(cin: Control) -> int:
	var guard := 0
	while guard < 1200:
		guard += 1
		await p.frames(1)
		if cin.index >= 0 and cin.index < cin.beats.size() and str((cin.beats[cin.index] as Dictionary).get("event", {}).get("kind", "")) == Types.EVENT_CLASH:
			break
	return guard


func _clash_columns(gs: Control, a: String, b: String) -> Array:
	var out: Array = []
	for c in gs.land.marches.columns.values():
		if (c["from"] == a and c["to"] == b) or (c["from"] == b and c["to"] == a):
			out.append(c)
	return out


func _clash() -> void:
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	var lands: Array = await _stage(gs, s)
	var ra: String = lands[0]
	var bl: String = lands[1]
	p.ok(ra != "", "a red land and a blue land share a border, each marching on the other (%s, %s)" % [ra, bl])
	var cin: Control = gs.cinema
	var frames: int = await _to_clash(cin)
	p.ok(not b.clash.is_empty(), "the border clash is told on the land (%d frames in)" % frames)
	## on the land: both columns march to the middle of the road and stand there, face to face,
	## before the break (watched frame by frame, before any shot is taken)
	var held_both := false
	var g0 := 0
	while not held_both and g0 < 120:
		g0 += 1
		await p.frames(1)
		var cols0: Array = _clash_columns(gs, str(b.clash_fx["a"]), str(b.clash_fx["b"]))
		var h := 0
		for c in cols0:
			if gs.land.marches.role(c) == "charge" and absf(float(c.get("held", -1.0)) - (float(c["total"]) * 0.5 - 18.0 * gs.land.marches.size_mult * 0.45)) < 1.0:
				h += 1
		held_both = cols0.size() == 2 and h == 2
	p.ok(held_both, "on the land both columns march to the middle of the road and stand there face to face (%d frames)" % g0)
	var ev: Dictionary = cin.beats[cin.index]["event"]
	var winner: String = str(ev["winnerId"])
	var loser_land: String = bl if winner == "red" else ra
	var win_land: String = ra if winner == "red" else bl
	## the banner for this stage of the report steps out of the way
	var banner: Variant = gs.get("_banner_node")
	p.ok(banner == null or not is_instance_valid(banner) or (banner as Node).has_meta("leaving"), "the stage's banner gives way once its first clash is told")
	## the charge: both arrows on the way, neither yet at the middle
	var ca: Dictionary = b.drawn_clash
	p.ok(not ca.is_empty() and b.clash_hides(ra, bl) and b.clash_hides(bl, ra), "the clash draws its two columns itself (the plain arrows stand aside)")
	## they meet
	var guard := 0
	while not bool(b.drawn_clash.get("met", false)) and guard < 120:
		guard += 1
		await p.frames(1)
	var met: Dictionary = b.drawn_clash
	var pa: Vector2 = b.anchor(ra)
	var pb: Vector2 = b.anchor(bl)
	var mid: Vector2 = (pa + pb) * 0.5
	p.ok(bool(met.get("met", false)) and (met["a_tip"] as Vector2).distance_to(met["b_tip"]) < 1.0, "the two arrows meet head-on (%d frames after the charge)" % guard)
	p.ok((met["meet"] as Vector2).distance_to(mid) < pa.distance_to(pb) * 0.25, "they meet on the border, between the two lands (%.0f px off the middle of %.0f)" % [(met["meet"] as Vector2).distance_to(mid), pa.distance_to(pb)])
	## the camera leaned in, both lands clear of the card
	await p.frames(30)
	pa = b.anchor(ra)
	pb = b.anchor(bl)
	var card: Rect2 = (cin.get("_card") as Control).get_global_rect()
	var r_tok: float = b.token_radius()
	p.ok(b.zoom > b.fit * 1.2, "the report's camera leans in on the clash (zoom %.2f, the fit %.2f)" % [b.zoom, b.fit])
	p.ok(maxf(pa.y, pb.y) + r_tok < card.position.y and b.in_view([ra, bl]), "both lands of the clash are on the screen, clear of the battle card (lowest token %.0f, the card from %.0f)" % [maxf(pa.y, pb.y) + r_tok, card.position.y])
	## the break
	guard = 0
	while str(b.drawn_clash.get("winner", "")) == "" and guard < 600:
		guard += 1
		await p.frames(1)
	p.ok(str(b.drawn_clash.get("winner", "")) == winner, "the dice land and the clash knows its winner (%s)" % winner)
	var d0: float = (b.drawn_clash["meet"] as Vector2).distance_to(b.anchor(loser_land))
	await p.frames(12)
	var mid_push: Dictionary = b.drawn_clash
	var d1: float = (mid_push["meet"] as Vector2).distance_to(b.anchor(loser_land)) if not mid_push.is_empty() else 0.0
	p.ok(d1 < d0 - 4.0, "the winner's arrow drives the loser's back toward its own land (%.0f px from it, then %.0f)" % [d0, d1])
	## (watched over the fall, not sampled once: it takes about a third of a second, and a quick
	## frame rate can sample it half over)
	var fallen := 0
	var marching := false
	var gf := 0
	while gf < 90 and (fallen == 0 or not marching):
		gf += 1
		for c in _clash_columns(gs, ra, bl):
			var part: String = gs.land.marches.role(c)
			if part == "lost":
				var down := 0
				for f in c["figs"]:
					if not (f as Node3D).visible or (f as Node3D).transform.basis.y.normalized().y < 0.6:
						down += 1
				fallen = maxi(fallen, down)
			elif part == "won":
				marching = marching or float(c.get("pushed", 0.0)) > float(c.get("held", 0.0))
		if fallen == 0 or not marching:
			await p.frames(1)
	p.ok(fallen > 0, "on the land the beaten column's men fall where they stood (%d down)" % fallen)
	p.ok(marching, "and the winners march on through the border")
	## the winner's own arrow carries on, with the men left
	guard = 0
	while b.clash_hides(ra, bl) and guard < 120:
		guard += 1
		await p.frames(1)
	await p.frames(2)
	var left: int = int(ev["winnerRemaining"])
	var have := -1
	var loser_arrow := false
	for o in b.orders:
		if str(o["from"]) == win_land and str(o["to"]) == loser_land:
			have = int(o["strength"])
		if str(o["from"]) == loser_land and str(o["to"]) == win_land:
			loser_arrow = true
	p.ok(have == left and not loser_arrow and not b.clash_hides(ra, bl), "the winner's arrow carries on to %s with the %d still standing; the loser's is gone" % [loser_land, left])
	## the land taken next: its new owner's colour spreads over it and its token pops
	var owner0: String = b.world.get_territory(loser_land).owner
	guard = 0
	while b.world.get_territory(loser_land).owner == owner0 and guard < 900:
		guard += 1
		await p.frames(1)
	var taken: bool = b.world.get_territory(loser_land).owner != owner0
	p.ok(taken, "the winners go on to take %s (%d frames)" % [loser_land, guard])
	if taken:
		var k0: float = b.taking(loser_land)
		var idx: int = int(b.art.index[loser_land])
		var ink0: Color = b._state_img.get_pixel(idx, 0)
		var red: Color = Style.seat_color(b.world.get_territory(loser_land).owner)
		var blue: Color = Style.seat_color(owner0)
		p.ok(k0 >= 0.0 and k0 < 0.5, "%s is being taken: its colour is on the way (%.2f of the way)" % [loser_land, k0])
		p.ok(absf(ink0.r - red.r) + absf(ink0.b - red.b) > 0.05, "the land's colour doesn't swap in a frame (red %.2f blue %.2f against the new owner's %.2f %.2f)" % [ink0.r, ink0.b, red.r, red.b])
		guard = 0
		while b.taking(loser_land) >= 0.0 and guard < 120:
			guard += 1
			await p.frames(1)
		var ink1: Color = b._state_img.get_pixel(idx, 0)
		p.ok(absf(ink1.r - red.r) + absf(ink1.g - red.g) + absf(ink1.b - red.b) < 0.02, "and then it is wholly the new owner's (%d frames)" % guard)
	## the report over: the view it found
	cin.skip()
	await p.frames(10)
	p.ok(is_equal_approx(b.zoom, b.fit), "the report skipped: the camera is back at the view it found (zoom %.2f, fit %.2f)" % [b.zoom, b.fit])
	main.queue_free()
	await p.frames(5)


func _pictures() -> void:
	## the same clash again for the eye (a shot takes long enough to throw the facts' timing off):
	## the charge, the lock, the break, and the winner carried through
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	await _stage(gs, s)
	await _to_clash(gs.cinema)
	await p.frames(13)
	await snap("v202_01_charge")
	var guard := 0
	while (str(b.drawn_clash.get("winner", "")) != "" or not bool(b.drawn_clash.get("met", false))) and guard < 200:
		guard += 1
		await p.frames(1)
	await snap("v202_02_locked")
	guard = 0
	while (b.drawn_clash.is_empty() or float(b.drawn_clash.get("w", 0.0)) < 0.3) and guard < 600:
		guard += 1
		await p.frames(1)
	await snap("v202_03_break")
	await p.frames(50)
	await snap("v202_04_through")
	var guard2 := 0
	while guard2 < 900:
		guard2 += 1
		await p.frames(1)
		var any := false
		for id in b.art.order:
			if b.taking(str(id)) > 0.15:
				any = true
		if any:
			break
	await snap("v202_07_taken")
	main.queue_free()
	await p.frames(5)


func _theater() -> void:
	## the player's own clash opens the battle on the land (Show my battles, the default): the arrows
	## meet as the camera swoops down on them, and the winner carries through as it rises again
	Settings.data["battles"] = "mine"
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	var th: Control = gs.theater
	await _settle(gs)
	var lands: Array = await _stage(gs, s)
	var guard := 0
	while not gs.cinema._waiting and guard < 900:
		guard += 1
		await p.frames(1)
	var met := false
	guard = 0
	while not th.visible and guard < 300:
		guard += 1
		met = met or bool(b.drawn_clash.get("met", false))
		await p.frames(1)
	p.ok(met, "Show my battles: the clash's arrows meet on the border as the camera swoops down on them")
	await snap("v202_05_swoop")
	guard = 0
	while th.get("_state") == "idle" and guard < 600:
		guard += 1
		await p.frames(1)
	await p.frames(60)
	th._skip()
	var won := ""
	guard = 0
	while won == "" and guard < 600:
		guard += 1
		won = str(b.drawn_clash.get("winner", ""))
		await p.frames(1)
	p.ok(won != "", "back from the battle, the winner's arrow carries through on the map (%s, %d frames)" % [won, guard])
	await p.frames(8)
	await snap("v202_06_back_from_battle")
	Settings.data["battles"] = "off"
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _skip_mid_swoop() -> void:
	## (the outside review, RV-002 F5) the report skipped while the camera swoops down on a battle:
	## the view it found comes back, not the battle's
	Settings.data["battles"] = "mine"
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	await _stage(gs, s)
	var guard := 0
	while not gs.cinema._waiting and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(12) ## partway down
	var mid_zoom: float = b.zoom
	gs.cinema.skip()
	await p.frames(70) ## longer than the swoop would have run
	p.ok(mid_zoom > b.fit * 1.05 and is_equal_approx(b.zoom, b.fit), "skipped mid-swoop (zoom %.2f): the camera is back at the view it found (zoom %.2f, fit %.2f)" % [mid_zoom, b.zoom, b.fit])
	Settings.data["battles"] = "off"
	main.queue_free()
	await p.frames(5)


func _stills() -> void:
	## motion off (stills): the camera stays put through the report
	Settings.data["motion"] = "off"
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	await _stage(gs, s)
	await _to_clash(gs.cinema)
	await p.frames(40)
	p.ok(is_equal_approx(b.zoom, b.fit), "with motion off the report's camera stays where it is (zoom %.2f, fit %.2f)" % [b.zoom, b.fit])
	Settings.data["motion"] = "paintings"
	main.queue_free()
	await p.frames(5)


func _surge_clash() -> void:
	## two surges running at each other's lands meet head-on: their columns have no arrows of their
	## own on the board (each is drawn on from the land just taken), and the clash still has both
	Settings.data["battles"] = "off"
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	var w: Types.World = s.world
	var pick: Array = []
	for x in b.art.order:
		for wl in MapLib.neighbors(b.map, x):
			var rr := ""
			var bb := ""
			for n in MapLib.neighbors(b.map, x):
				if str(n) != str(wl) and not MapLib.is_adjacent(b.map, str(n), str(wl)):
					rr = str(n)
			for n in MapLib.neighbors(b.map, str(wl)):
				if str(n) != str(x) and str(n) != rr and not MapLib.is_adjacent(b.map, str(n), str(x)):
					bb = str(n)
			if rr != "" and bb != "":
				pick = [rr, str(x), str(wl), bb]
				break
		if not pick.is_empty():
			break
	p.ok(not pick.is_empty(), "four lands in a row for two surges to run at each other: %s" % str(pick))
	if pick.is_empty():
		main.queue_free()
		return
	w.set_hex(pick[0], "red", 14, 1)
	w.set_hex(pick[1], "", 0)
	w.set_hex(pick[2], "", 0)
	w.set_hex(pick[3], "blue", 14, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(pick[0], pick[1], 13)
	var e1: String = s.set_surge(0, pick[2])
	s.lock()
	s.set_attack(pick[3], pick[2], 13)
	var e2: String = s.set_surge(0, pick[1])
	s.lock()
	p.ok(e1 == "" and e2 == "", "each surges on into the other's next land (%s / %s)" % [e1, e2])
	await _to_clash(gs.cinema)
	var guard := 0
	while not bool(b.drawn_clash.get("met", false)) and guard < 120:
		guard += 1
		await p.frames(1)
	p.ok(int(b.drawn_clash.get("sides", 0)) == 2 and b.clash_hides(pick[1], pick[2]), "the surges' clash draws both columns, and their own legs stand aside while it's told (%d sides)" % int(b.drawn_clash.get("sides", 0)))
	await snap("v202_08_surge_clash")
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _old_rules_clash() -> void:
	## (the outside review, RV-003 F2) a rules 20 game (an old save): a commander's columns into one
	## land are one army, and that army fought the clash: the map tells it with the army's count
	Settings.data["battles"] = "off"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": _seats(), "rules": 20})
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
	s.set_attack("harbor", "gate", 9)
	s.lock()
	s.set_attack("gate", "ridge", 8)
	s.lock()
	await _to_clash(gs.cinema)
	var guard := 0
	while not bool(b.drawn_clash.get("met", false)) and guard < 200:
		guard += 1
		await p.frames(1)
	var ev: Dictionary = gs.cinema.beats[gs.cinema.index]["event"]
	var red_n: int = int(b.drawn_clash.get("a_n", -1)) if str(b.clash_fx["a"]) == str(ev["hexA"]) and str(ev["playerA"]) == "red" else int(b.drawn_clash.get("b_n", -1))
	var red_event: int = int(ev["sizeA"]) if str(ev["playerA"]) == "red" else int(ev["sizeB"])
	p.ok(s.map.rules == 20 and red_event == 18 and red_n == 18, "rules 20 (an old save): the clash is told with the army that fought it, his two columns as one (%d on the map, %d in the event)" % [red_n, red_event])
	## (RV-004 F1) and his column from Harbor, part of that army, stands aside while it's told
	p.ok(b.clash_hides("harbor", "gate", "red") and b.clash_hides("ridge", "gate", "red"), "rules 20: both of his columns stand aside while their army's clash is told (the map shows 18, not 18 and 9)")
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _region_moment() -> void:
	## a region falling wholly to one commander: its name flares in their colours, a ring over each land
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	await _settle(gs)
	var w: Types.World = s.world
	var region := ""
	var last := ""
	var from := ""
	for reg in b.map.region_bonus.keys():
		var ms: PackedStringArray = MapLib.region_members(b.map, str(reg))
		if ms.size() < 2:
			continue
		for m in ms:
			for n in MapLib.neighbors(b.map, m):
				if ms.has(str(n)):
					region = str(reg)
					last = m
					from = str(n)
					break
			if region != "":
				break
		if region != "":
			break
	for m in MapLib.region_members(b.map, region):
		w.set_hex(m, "red", 3, 1)
	w.set_hex(from, "red", 9, 1)
	w.set_hex(last, "", 0)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack(from, last, 8)
	s.lock()
	s.lock()
	var guard := 0
	while b.region_won(region) < 0.0 and guard < 1500:
		guard += 1
		await p.frames(1)
	p.ok(b.region_won(region) >= 0.0, "%s falls wholly to red in the report: its moment on the map (%d frames)" % [region, guard])
	## (the outside review, RV-001 F3) won and lost again in one report: the moment ends with it
	var broken: Types.World = b.world.clone()
	broken.get_territory(from).owner = "blue"
	var shown: Types.World = b.world
	b.world = broken
	b.refresh()
	var ended: bool = b.region_won(region) < 0.0
	b.world = shown
	b.refresh()
	p.ok(ended, "and lost again before its moment is over, the flare ends with it")
	await p.frames(20)
	await snap("v202_09_region_won")
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _stale_question() -> void:
	## a question about the planning goes when the planning does: "5 recruits still unplaced" up,
	## and the turn's timer seals the orders (in hotseat, the next commander's turn; then the battles)
	Settings.data["map_land"] = false
	var r: Array = await _game("res://maps/known24.json", _seats())
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	p.ok(s.income_left() > 0, "the reinforcement phase, %d recruits to place" % s.income_left())
	gs.begin_orders()
	await p.frames(3)
	var m: Variant = gs.get("_modal")
	p.ok(m != null and is_instance_valid(m), "on to the orders with recruits unplaced: the question is up")
	s.timeout_lock()
	await p.frames(3)
	m = gs.get("_modal")
	p.ok(m == null or not is_instance_valid(m) or (m as Node).is_queued_for_deletion(), "the timer seals the first commander's orders: the question goes before the next commander sits down")
	gs.begin_orders()
	await p.frames(3)
	s.timeout_lock()
	await p.frames(3)
	m = gs.get("_modal")
	p.ok(m == null or not is_instance_valid(m) or (m as Node).is_queued_for_deletion(), "and the last commander's: it isn't up over the battles")
	gs.cinema.skip()
	Settings.data["map_land"] = true
	main.queue_free()
	await p.frames(5)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
