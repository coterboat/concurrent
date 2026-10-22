## v2.4, the map and its table (v24-map), as facts on the real client (no rule changes: rules 22):
##   1. a new war's music, and the tent's sounds, wait for the intro film to end or be skipped
##   6. the commanders take their seats on the war table, each as their die falls for the order of claims
##      (not on a screen of their own); Esc throws the rest together; on a dealt war they step up before
##      the deployment, and the board waits for them
##   2. OK on an order's card (and Enter) lets go of the land it came from; the card's ✕ only closes it
##   3. a land marching on its only enemy neighbour isn't warned that a neighbour could walk in
##   5. in the regroup phase a land's number is who is there: the men marching in ride a tab of their own
##   7. the garrison shields: ranked, number, chevrons (and G steps through them), side by side
##   4. a war picked up comes back on the view it was left on (the land: a veil, then on it at once), and
##      the 2D/3D chip shows that view lit
##   SHOT_DIR=/dir ./scripts/shot.sh v24m
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const Counsel := preload("res://game/core/counsel.gd")
const MapBoard := preload("res://game/board/map_board.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(10)
	await _film_and_seats(main)
	await _seats_skipped(main)
	await _dealt_seats(main)
	await _orders(main)
	await _shields(main)
	await _resume(main)


func _seats(n: int) -> Array:
	var all := [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"},
		{"id": "purple", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]
	return all.slice(0, n)


func _wait(cond: Callable, most: int = 900) -> int:
	var guard := 0
	while not cond.call() and guard < most:
		guard += 1
		await p.frames(1)
	return guard


func _key(gs: Control, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	gs._unhandled_input(ev)


# ------------------------------------------------------------------ 1 and 6: the film, then the seats

func _film_and_seats(main: Control) -> void:
	main.show_setup()
	await p.frames(5)
	p.ok(Audio._current == "menu", "the setup screen plays the menu's music (%s)" % Audio._current)
	Settings.data["motion"] = "all"
	main.start_game({"map": "res://maps/known24.json", "seed": 11, "length": "short", "timer": 0, "deal": "draft", "seats": _seats(4)})
	await p.frames(12)
	var s: Node = main.session
	var gs: Control = main.current
	p.ok(gs.cutscene.visible and s.phase == Session.Phase.DRAFT, "a new war opens on the intro film (phase %d)" % s.phase)
	p.ok(Audio._current == "", "1: under the film, no war music: the menu's gives way and the plan's waits (now \"%s\")" % Audio._current)
	p.ok(not Audio._amb.playing, "1: nor the tent's sounds")
	await snap("01_intro_film")
	await p.frames(30)
	gs.cutscene.skip()
	await _wait(func(): return not gs.cutscene.visible, 120)
	await p.frames(2)
	Settings.data["motion"] = "paintings"
	p.ok(Audio._current == "plan", "1: the film skipped, the war's music begins (\"%s\")" % Audio._current)
	p.ok(Audio._amb.playing, "1: and the tent's sounds")
	## 6: the commanders take their seats on the table, as their dice fall
	p.ok(gs._draft_ui.visible and gs._draft_title.text == "THE COMMANDERS TAKE THEIR SEATS", "6: the roll opens with the commanders taking their seats (\"%s\")" % gs._draft_title.text)
	await _wait(func(): return gs.intro.visible and gs.intro.seat_id != "", 600)
	var first: String = gs.intro.seat_id
	p.ok(first == "blue", "6: the rivals step up first, in their seats' order: %s" % s.name_of(first))
	var card := Rect2(gs.intro.position, gs.intro.size)
	p.ok(card.size.x < gs.size.x * 0.5 and card.size.y < gs.size.y * 0.3 and Rect2(Vector2.ZERO, gs.size).encloses(card),
		"6: the card sits on the war table, not a screen of its own, inside 1440x900 (%s)" % card)
	p.ok(gs.intro._name.text == "Grand Marshal Varek" and gs.intro._blurb.text.contains("Hard") and gs.intro._line.text.contains("hundred"),
		"6: Varek's card: his name, his manner and level, his greeting (\"%s\" / \"%s\")" % [gs.intro._blurb.text, gs.intro._line.text])
	var dim := 0
	for box in gs._draft_row.get_children():
		if (box.get_child(0) as Control).modulate.r < 0.5:
			dim += 1
	p.ok(dim == 3, "6: the strip: the three still to take their seats are dimmed (%d)" % dim)
	await _wait(func(): return gs._draft_marks.size() >= 1 and gs._seat_rolling == "", 300)
	p.ok(gs._draft_marks.size() == 1 and gs._seat_snaps.size() == 1 and gs.intro.seat_id == "blue",
		"6: his die falls while his card is up, and lies on the table under his name (%d marks, %d dice down)" % [gs._draft_marks.size(), gs._seat_snaps.size()])
	await p.frames(4)
	await snap("02_varek_takes_his_seat")
	await _wait(func(): return gs.intro.seat_id == "green" and gs._seat_rolling == "" and gs._draft_marks.size() >= 2, 600)
	p.ok(gs._seat_snaps.size() == 2, "6: Ysolde's die joins Varek's on the table (%d down)" % gs._seat_snaps.size())
	var a: Vector2 = (gs._draft_marks[0] as Control).position
	var b: Vector2 = (gs._draft_marks[1] as Control).position
	p.ok(b.x > a.x and (gs._draft_marks[0] as Label).text.begins_with("Varek ") and (gs._draft_marks[1] as Label).text.begins_with("Ysolde "),
		"6: each die lies under the last of its commander's name, left to right in the seats' order (\"%s\" at %s, \"%s\" at %s)" % [(gs._draft_marks[0] as Label).text, a, (gs._draft_marks[1] as Label).text, b])
	var card2 := Rect2(gs.intro.position, gs.intro.size)
	var hid := []
	for m in gs._draft_marks:
		var lp: Vector2 = (m as Control).position
		if card2.intersects(Rect2(lp + Vector2(50, -80), Vector2(120, 110))):
			hid.append((m as Label).text)
	p.ok(hid.is_empty(), "6: Ysolde's card keeps clear of the dice on the table and their names (card %s; covered: %s)" % [card2, str(hid)])
	await p.frames(4)
	await snap("03_ysolde_takes_her_seat")
	await _wait(func(): return gs.intro.seat_id == "red", 900)
	p.ok(s.is_human(gs.intro.seat_id) and gs.intro._blurb.text == "Your throw" and not gs.intro._line.visible,
		"6: the commander at the table throws last: \"%s\", no word" % gs.intro._blurb.text)
	await _wait(func(): return gs._seat_rolling == "" and gs._draft_marks.size() >= 4, 300)
	await p.frames(4)
	await snap("04_your_throw")
	p.ok(gs._draft_marks.size() == 4, "6: four commanders, four dice on the table (%d)" % gs._draft_marks.size())
	await _wait(func(): return gs._draft_state == "picking", 1200)
	p.ok(gs._draft_state == "picking" and gs._draft_title.text != "THE COMMANDERS TAKE THEIR SEATS" and not gs.intro.visible,
		"6: then the order of claims (%s), the card gone" % ", ".join(s.draft["order"]))
	await snap("05_order_of_claims")
	main.show_title()
	await p.frames(6)


func _seats_skipped(main: Control) -> void:
	main.start_game({"map": "res://maps/known24.json", "seed": 12, "length": "short", "timer": 0, "deal": "draft", "seats": _seats(4)})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	p.ok(not gs.cutscene.visible and gs._seating_now(), "6: with films off, the seats are taken at once")
	await _wait(func(): return gs.intro.seat_id == "green", 900)
	_key(gs, KEY_ESCAPE)
	p.ok(not gs._seating_now() or gs._seat_rolling == "*", "6: Esc: no more introductions")
	await _wait(func(): return gs._seat_rolling == "" and gs._draft_marks.size() >= 4, 300)
	p.ok(gs._draft_marks.size() == 4 and not gs.intro.visible and gs._modal == null,
		"6: the rest throw together; four dice down, and no pause menu (%d marks)" % gs._draft_marks.size())
	await p.frames(4)
	await snap("06_seats_skipped")
	await _wait(func(): return gs._draft_state == "picking", 1200)
	p.ok(gs._draft_state == "picking", "6: and on to the claims")
	main.show_title()
	await p.frames(6)


func _dealt_seats(main: Control) -> void:
	main.start_game({"map": "res://maps/known24.json", "seed": 13, "length": "short", "timer": 0, "deal": "random", "seats": _seats(3)})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	p.ok(s.phase == Session.Phase.OPENING and gs._seating_now() and not gs._draft_ui.visible, "6: a dealt war: the rivals step up before the deployment")
	await _wait(func(): return gs.intro.visible and gs.intro.seat_id != "", 300)
	var mine: String = str(Array(load("res://engine/map.gd").player_territory_ids(s.world, "red"))[0])
	gs._on_click(mine, MOUSE_BUTTON_LEFT)
	p.ok(s.placed_total() == 0, "6: the board waits while they take their seats (a click placed %d)" % s.placed_total())
	var card := Rect2(gs.intro.position, gs.intro.size)
	p.ok(absf(card.get_center().x - gs.size.x * 0.5) < 4.0, "6: with no dice, the card stands in the middle of the map (%s)" % card)
	await p.frames(20)
	await snap("07_dealt_war_seats")
	await _wait(func(): return not gs._seating_now(), 900)
	p.ok(gs._intro_done and gs._banner_node != null and is_instance_valid(gs._banner_node), "6: then the deployment, with its banner")
	gs._on_click(mine, MOUSE_BUTTON_LEFT)
	p.ok(s.placed_total() == 1, "6: and the board takes the clicks again (%d placed)" % s.placed_total())


# ------------------------------------------------------------------ 2, 3 and 5: orders and marches

func _orders(main: Control) -> void:
	var s: Node = main.session
	var gs: Control = main.current
	s.auto_deploy()
	s.lock()
	await _wait(func(): return s.phase == Session.Phase.CINEMA, 120)
	gs.cinema.skip()
	await _wait(func(): return s.phase == Session.Phase.PLANNING, 300)
	s.auto_deploy()
	gs.begin_orders()
	await p.frames(4)
	## Dad holds Wold (6) and Vale (4); Varek holds Cairn and Shoal beside Wold, and Ysolde Keep beside Vale
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), "green", 2)
	w.set_hex("wold", "red", 6)
	w.set_hex("moor", "red", 2)
	w.set_hex("firth", "red", 2)
	w.set_hex("vale", "red", 4)
	w.set_hex("marsh", "red", 2)
	w.set_hex("cairn", "blue", 2)
	w.set_hex("shoal", "blue", 3)
	w.set_hex("keep", "green", 2)
	s.drafts.clear()
	s.begin_orders()
	s.changed.emit()
	await p.frames(4)
	gs.board.focus_on(["wold", "cairn", "vale", "keep", "shoal"], 1.6)
	gs._clear_banner()
	await p.frames(150) ## the banner, and the lands just painted taking their colours, settle
	## 2: a click on Wold, a click on Cairn: an attack, its card, Wold still picked
	gs._on_click("wold", MOUSE_BUTTON_LEFT)
	gs._on_click("cairn", MOUSE_BUTTON_LEFT)
	await p.frames(4)
	p.ok(gs.order_card.visible and gs.selected == "wold" and s.packet_index("wold", "cairn") >= 0, "2: click, click: the attack on Cairn, its card up, Wold picked")
	await snap("10_order_card")
	var ok_btn: Button = _ok_of(gs.order_card)
	p.ok(ok_btn != null and ok_btn.tooltip_text.contains("let go of Wold"), "2: the card's OK says it lets go of Wold (\"%s\")" % (ok_btn.tooltip_text if ok_btn else ""))
	ok_btn.pressed.emit()
	await p.frames(3)
	p.ok(gs.selected == "" and not gs.order_card.visible and s.packet_index("wold", "cairn") >= 0, "2: OK: the order stands, the card closes, and Wold is let go")
	## the next click on a land beside it picks that land; it orders nothing from Wold
	gs._on_click("shoal", MOUSE_BUTTON_LEFT)
	p.ok(s.packet_index("wold", "shoal") < 0 and gs.selected == "shoal", "2: so the next click, on Shoal beside it, orders nothing from Wold")
	gs.select("")
	## Enter does what OK does; the ✕ only closes the card
	gs._on_click("vale", MOUSE_BUTTON_LEFT)
	gs._on_click("keep", MOUSE_BUTTON_LEFT)
	await p.frames(3)
	_key(gs, KEY_ENTER)
	await p.frames(2)
	p.ok(gs.selected == "" and not gs.order_card.visible and s.packet_index("vale", "keep") >= 0, "2: Enter: the same as OK")
	gs._on_click("vale", MOUSE_BUTTON_LEFT)
	gs.edit_order("vale", "keep")
	await p.frames(3)
	_x_of(gs.order_card).pressed.emit()
	await p.frames(2)
	p.ok(not gs.order_card.visible and gs.selected == "vale", "2: the card's ✕ only closes it: Vale stays picked")
	gs.select("")
	## 3: Vale marches on Keep, its only enemy neighbour (Marsh is ours, Wold ours): no warning; Wold,
	## marching on Cairn with Shoal left alone beside it, is warned if it keeps 1
	s.set_attack("vale", "keep", 3)
	s.set_attack("wold", "cairn", 5)
	var warn: String = " / ".join(s.warnings())
	p.ok(not warn.contains("Vale will be left") and warn.contains("Wold will be left with 1"),
		"3: Vale, left with 1 marching on its only enemy neighbour, isn't warned; Wold, with Shoal beside it, is (\"%s\")" % warn)
	var vac: Array = Counsel.advice(s).filter(func(it): return str(it.get("key", "")) == "vacate")
	p.ok(vac.size() == 1 and str(vac[0]["text"]).begins_with("Wold"), "3: the advisor's dispatch warns of Wold only (%s)" % str(vac.map(func(it): return it["text"])))
	gs._refresh()
	await p.frames(2)
	await snap("11_bare_land_warning")
	## 5: on to the regroup phase, and Wold marches 4 into Moor
	s.drafts.clear()
	s.lock()
	var guard := 0
	while guard < 9000 and s.phase != Session.Phase.MANEUVER:
		guard += 1
		match s.phase:
			Session.Phase.CINEMA:
				gs.cinema.skip()
			Session.Phase.RECAP:
				gs.recap.visible = false
				s.next_round()
			Session.Phase.PLANNING:
				s.auto_deploy()
				s.lock()
		await p.frames(2)
	p.ok(s.phase == Session.Phase.MANEUVER, "5: the regroup phase (phase %d)" % s.phase)
	w = s.world
	w.set_hex("wold", "red", 6)
	w.set_hex("moor", "red", 2)
	w.set_hex("firth", "red", 1)
	w.set_hex("cairn", "blue", 3)
	s.moves[s.planner] = []
	s.changed.emit()
	await p.frames(3)
	gs.board.focus_on(["wold", "moor", "firth", "cairn"], 2.2)
	gs._clear_banner()
	await p.frames(150)
	gs._on_click("wold", MOUSE_BUTTON_LEFT)
	gs._on_click("moor", MOUSE_BUTTON_LEFT)
	await p.frames(4)
	var b: Control = gs.board
	var mts: Types.TerritoryState = b.world.get_territory("moor")
	var shown: Array = MapBoard.shown_split(mts, 5)
	p.ok(s.move_index("wold", "moor") >= 0 and int(s.my_moves()[0]["n"]) == 5 and mts.armies == 7, "5: Wold marches 5 into Moor (Moor: 2 there, 7 once they're in)")
	p.ok(b.drawn_arriving.has("moor") and int(b.drawn_arriving["moor"][1]) == 5, "5: Moor's token wears a tab for the 5 marching in (%s)" % str(b.drawn_arriving))
	## the tab keeps clear of the march's own arrow: Wold lies to Moor's upper right, so it sits below
	var tab: Rect2 = b.drawn_arriving["moor"][0]
	p.ok(tab.get_center().y > b.anchor("moor").y, "5: the tab keeps off the head of the arrow coming in (tab %s, Moor at %s)" % [tab, b.anchor("moor")])
	p.ok(int(shown[0]) == s.can_move_from("moor") and int(shown[0]) == 1, "5: and its number is who is there and can march: %d (the rules agree: %d)" % [int(shown[0]), s.can_move_from("moor")])
	gs._on_hover("moor")
	var tip: String = gs._hover_label.text
	p.ok(tip.contains("1 army · 1 in the garrison") and tip.contains("5 marching in"), "5: Moor's tooltip says who is there and who is marching in (\"%s\")" % tip.replace("\n", " | "))
	gs._on_hover("wold")
	p.ok(gs._hover_label.text.contains("5 marching out"), "5: Wold's, who is marching out (\"%s\")" % gs._hover_label.text.replace("\n", " | "))
	gs._on_hover("")
	await p.frames(3)
	await snap("12_marching_in")
	_ok_of(gs.order_card).pressed.emit()
	await p.frames(3)
	p.ok(gs.selected == "" and s.move_index("wold", "moor") >= 0, "2: OK on the march's card lets go of Wold too")
	gs.land_card.show_for("moor")
	await p.frames(2)
	var lines: Array = []
	for c in gs.land_card._box.get_children():
		if c is Label:
			lines.append((c as Label).text)
	p.ok(" / ".join(lines).contains("1 army  ·  1 in the garrison  ·  +5 marching in"), "5: Moor's card, the same (%s)" % " / ".join(lines))
	gs.land_card.show_for("")
	main.show_title()
	await p.frames(6)


func _ok_of(card: Control) -> Button:
	for c in card._box.get_children():
		if c is Button and (c as Button).text.contains("OK"):
			return c
	return null


func _x_of(card: Control) -> Button:
	for row in card._box.get_children():
		for c in row.get_children():
			if c is Button and (c as Button).text == "✕":
				return c
	return null


# ------------------------------------------------------------------ 7: the garrison shields

func _shields(main: Control) -> void:
	main.start_game({"map": "res://maps/known24.json", "seed": 14, "length": "short", "timer": 0, "deal": "random", "capitals": false, "seats": _seats(2)})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await _wait(func(): return not gs._seating_now(), 300)
	## Dad's lands in the west, from the one man held back to a fortress's four dug in, beside Varek's
	var w: Types.World = s.world
	var depth := {"firth": 0, "cairn": 1, "moor": 2, "wold": 3, "vale": 4}
	w.set_hex("firth", "red", 3, 0)
	w.set_hex("cairn", "red", 4, 1)
	w.set_hex("moor", "red", 6, 2)
	w.set_hex("wold", "red", 5, 3)
	w.set_hex("vale", "red", 7, 4)
	w.set_hex("keep", "blue", 3, 1)
	w.set_hex("marsh", "blue", 2, 2)
	w.set_hex("shoal", "blue", 4, 3)
	s.changed.emit()
	await p.frames(4)
	var b: Control = gs.board
	b.focus_on(["firth", "cairn", "moor", "wold", "vale", "keep", "marsh"], 2.0)
	gs._clear_banner()
	await p.frames(150)
	var crop: Rect2i = _crop_of(b, depth.keys())
	var shots: Array = []
	for style in ["ranked", "number", "chevrons"]:
		b.shield_style = style
		b.refresh()
		var tag := _tag(gs, style, Vector2(crop.position) + Vector2(10, 6))
		await p.frames(3)
		var ds: Dictionary = b.drawn_shields
		match style:
			"ranked":
				var tiers: Array = []
				for t in depth.keys():
					tiers.append(int(ds[t][1]) if ds.has(t) else -9)
				p.ok(tiers == [0, 1, 2, 3, 4], "7: ranked: each depth its own shield, wood to gold on crimson (%s)" % str(tiers))
			"number":
				var plain := true
				for t in depth.keys():
					plain = plain and ds.has(t) and str(ds[t][0]) == "number"
				p.ok(plain, "7: number: the shield as it was, the number in it")
			"chevrons":
				p.ok(ds.has("firth") and str(ds["firth"][2]) == "boss" and str(ds.get("wold", [0, 0, ""])[2]) == "chevrons" and str(ds.get("vale", [0, 0, ""])[2]) == "chevrons",
					"7: chevrons: the man held back a boss, the dug in a chevron each (Firth %s, Wold %s)" % [str(ds.get("firth", [])), str(ds.get("wold", []))])
		var path := "20_shields_%s" % style
		await snap(path)
		shots.append(path)
		tag.queue_free()
	_side_by_side(shots, crop, "22_shields_side_by_side")
	## G steps through them
	b.shield_style = "ranked"
	_key(gs, KEY_G)
	p.ok(b.shield_style == "number" and str(Settings.get_value("shields")) == "number", "7: G: the next look (%s)" % b.shield_style)
	_key(gs, KEY_G)
	_key(gs, KEY_G)
	p.ok(b.shield_style == "ranked", "7: and round again (%s)" % b.shield_style)
	## a whole war's worth, on the big map, for the noise
	main.show_title()
	await p.frames(4)
	main.start_game({"map": "res://maps/known24.json", "seed": 15, "length": "short", "timer": 0, "deal": "random", "seats": _seats(4)})
	await p.frames(6)
	gs = main.current
	s = main.session
	gs.intro._done()
	await _wait(func(): return not gs._seating_now(), 300)
	gs._clear_banner()
	var k := 0
	for t in s.world.territories.keys():
		var ts: Types.TerritoryState = s.world.get_territory(str(t))
		s.world.set_hex(str(t), ts.owner, 2 + (k * 5) % 7, k % 4)
		k += 1
	s.changed.emit()
	await p.frames(150)
	var wide: Array = []
	for style in ["ranked", "number", "chevrons"]:
		gs.board.shield_style = style
		gs.board.refresh()
		var tag2 := _tag(gs, style, Vector2(gs.size.x * 0.5 - 60, 96))
		await p.frames(3)
		await snap("21_whole_map_%s" % style)
		wide.append("21_whole_map_%s" % style)
		tag2.queue_free()
	_side_by_side(wide, Rect2i(190, 84, 1062, 660), "23_whole_map_side_by_side", 0.5)
	gs.board.shield_style = "ranked"
	main.show_title()
	await p.frames(6)


func _tag(gs: Control, text: String, at: Vector2) -> Label:
	## the style's name on the screenshot, for the side by side
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.position = at
	gs.add_child(l)
	return l


func _crop_of(b: Control, ids: Array) -> Rect2i:
	var r := Rect2(b.anchor(str(ids[0])), Vector2.ZERO)
	for id in ids:
		r = r.expand(b.anchor(str(id)))
	r = r.grow(b.token_radius() * 3.2)
	return Rect2i(r)


func _side_by_side(names: Array, crop: Rect2i, out_name: String, scale: float = 1.0) -> void:
	## the same part of each screenshot, side by side in one picture (for the notes: docs/v24/v24-map.md)
	var dir := OS.get_environment("SHOT_DIR")
	var imgs: Array = []
	for n in names:
		var im := Image.load_from_file(dir + "/" + str(n) + ".png")
		if im == null or im.is_empty():
			p.log("side by side: no %s" % n)
			return
		imgs.append(im)
	var c: Rect2i = crop.intersection(Rect2i(Vector2i.ZERO, (imgs[0] as Image).get_size()))
	var gap := 12
	var w: int = int(c.size.x * scale)
	var h: int = int(c.size.y * scale)
	var out := Image.create(w * imgs.size() + gap * (imgs.size() - 1), h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.04, 0.04, 0.06))
	for i in imgs.size():
		var im: Image = (imgs[i] as Image).get_region(c)
		im.convert(Image.FORMAT_RGBA8)
		if scale != 1.0:
			im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(i * (w + gap), 0))
	out.save_png(dir + "/" + out_name + ".png")
	p.log("shot " + out_name)


# ------------------------------------------------------------------ 4: a war picked up, on its view

func _resume(main: Control) -> void:
	## a save of its own: every worktree on this machine shares user://, and other probes' wars landed in
	## the one probe.gd gives (a war picked up here was once another session's)
	var was: String = Session.SAVE_PATH
	Session.SAVE_PATH = "user://probe_v24m_savegame.json"
	Settings.data["map_land"] = true
	main.start_game({"map": "res://maps/known24.json", "seed": 16, "length": "short", "timer": 0, "deal": "random", "seats": _seats(3)})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await _wait(func(): return not gs._seating_now(), 300)
	p.ok(gs._veil == null, "4: a new war has no veil (its land rises from the chart as ever)")
	s.auto_deploy()
	s.lock()
	await _wait(func(): return s.phase == Session.Phase.CINEMA, 120)
	gs.cinema.skip()
	await _wait(func(): return s.phase == Session.Phase.PLANNING, 300)
	p.ok(Session.has_save(), "4: deployed, the war is saved")
	main.show_title()
	await p.frames(10)
	main.continue_game()
	gs = main.current
	await p.frames(2)
	p.ok(gs._veil != null and gs._veil.visible and gs.land_board.t < 0.01 and gs.land_view() == "3D",
		"4: picked up on the land: a veil while it's laid out (not the chart), the chip on 3D (t %.2f, chip %s)" % [gs.land_board.t, gs.land_view()])
	p.ok((gs._land_lbl[0] as Label).get_theme_color("font_color") == _gold() and (gs._land_lbl[1] as Label).get_theme_font_size("font_size") < 15,
		"4: the chip: 3D lit, 2D dim")
	await snap("30_resume_veil")
	var g: int = await _wait(func(): return gs.land.prepared, 900)
	await p.frames(1)
	p.ok(gs.land_board.t >= 0.999, "4: the land laid out (%d frames), the board is on it at once, not rising from the chart (t %.2f)" % [g, gs.land_board.t])
	await _wait(func(): return gs._veil == null, 120)
	await p.frames(10)
	p.ok(gs._veil == null and gs.land_board.active(), "4: the veil lifts onto the land")
	await snap("31_resume_on_the_land")
	## left on the chart, it comes back on the chart
	gs.toggle_land()
	await p.frames(4)
	main.show_title()
	await p.frames(10)
	main.continue_game()
	gs = main.current
	await p.frames(4)
	p.ok(gs._veil == null and not gs.land_board.on and gs.land_view() == "2D" and (gs._land_lbl[1] as Label).get_theme_color("font_color") == _gold(),
		"4: picked up on the chart: the chart at once, the chip on 2D (veil %s, chip %s)" % [str(gs._veil != null), gs.land_view()])
	p.ok(main.session.map.id == "known24", "4: the war picked up is this one (%s)" % main.session.map.id)
	## the land turned on later in the war rises from the chart, as ever: no veil
	gs.toggle_land()
	await p.frames(2)
	p.ok(gs._veil == null and gs.land_board.on and gs.land_view() == "3D", "4: L in a war picked up on the chart: the land rises from it, no veil, the chip on 3D")
	await snap("32_resume_on_the_chart")
	Settings.data["map_land"] = false
	main.show_title()
	await p.frames(6)
	if Session.has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Session.SAVE_PATH))
	Session.SAVE_PATH = was


func _gold() -> Color:
	return load("res://game/core/style.gd").GOLD


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
