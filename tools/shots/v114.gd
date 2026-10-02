## v1.14 in the real client: a senior pass on the polish. The board keeps its marks off each
## other: a region's bonus and pips keep off the tokens and their names, CUT OFF moves clear of a
## fate mark, the fate marks are half as big again and the scramble's is a broken banner, not the
## threat plate's swords. The roster never squeezes a name to nothing.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Board := preload("res://game/board/map_board.gd")
const LastRound := preload("res://game/core/last_round.gd")
const Session := preload("res://game/core/session.gd")
const CardsDialog := preload("res://game/ui/cards_dialog.gd")
const PlanDialog := preload("res://game/ui/plan_dialog.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	await _bonus_clear()
	await _fates()
	await _roster()
	await _keys()
	p.log("v114 probe done")


func _board(mid: String, seats: Array) -> Array:
	## a dealt board at the game screen's size and padding, fit to the screen, as you plan
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
	map.rules = 20
	var w: Types.World = Setup.deal(map, seats, 7)
	for id in w.territories.keys():
		var ts = w.territories[id]
		if ts.owner != "":
			ts.armies = 1 + (hash(id) % 6)
			ts.garrison = 1
	var b: Control = Board.new()
	b.size = Vector2(1440, 900)
	b.pad_top = 84
	b.pad_bottom = 160
	p.get_tree().root.add_child(b)
	b.load_map(map)
	b.world = w
	b.viewer = "red"
	b.show_ceiling = true
	b.refresh()
	b.reset_view()
	await p.frames(4)
	return [b, map, w]


func _bonus_clear() -> void:
	## every region's bonus and pips, on every map, keep off every token and name
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}, {"id": "gold", "name": "D"}]
	for mid in ["knife7", "marches18", "known24", "isles24", "ring26", "world30"]:
		var r: Array = await _board(mid, seats.slice(0, 2) if mid in ["knife7", "marches18"] else seats)
		var b: Control = r[0]
		## no bonus on a land's name, ever; on a token's box only where its own lands have no room
		## (the Ring's Crown: seven lands packed in the middle), and then on little of it
		var names: Array = b.token_boxes(true, false)
		var tokens: Array = b.token_boxes(false, true)
		var hits: Array = []
		var worst := 0.0
		for reg in b.drawn_bonus.keys():
			var box: Rect2 = b.drawn_bonus[reg]
			var on_name: float = Board._overlap(box, names)
			var on_token: float = Board._overlap(box, tokens)
			worst = maxf(worst, on_token / box.get_area())
			## the Ring's Crown: seven lands packed in the middle of a map drawn 656 px square, and its
			## inner sea narrower than its pips. No clear spot exists; it takes the least-covered one.
			var packed: bool = mid == "ring26" and reg == "crown"
			if (on_name > (120.0 if packed else 0.0)) or on_token > box.get_area() * (0.35 if packed else 0.25):
				hits.append("%s: %d px² of names, %d px² of tokens" % [reg, int(on_name), int(on_token)])
		p.ok(b.drawn_bonus.size() == (b.map.region_bonus as Dictionary).size() and hits.is_empty(),
			"%s: %d region bonuses, none on a land's name, at most %d%% on a token's box (%s)" % [mid, b.drawn_bonus.size(), int(worst * 100.0), ", ".join(hits) if not hits.is_empty() else "clear"])
		await snap("01_bonus_" + mid)
		b.queue_free()
		await p.frames(2)


func _fates() -> void:
	## the fate marks half as big again, each its own; a cut-off land's CUT OFF keeps clear of a
	## fate mark at its walls (the cross used to sit on the words)
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}]
	var r: Array = await _board("isles24", seats)
	var b: Control = r[0]
	var map: Types.MapDef = r[1]
	var w: Types.World = r[2]
	var cut: Array = []
	for id in MapLib.player_territory_ids(w, "red"):
		if not MapLib.in_supply(w, map, id):
			cut.append(id)
	var ghosts: Array = []
	var aimed := ""
	for x in cut:
		for n in MapLib.neighbors(map, x):
			var d: Vector2 = b.anchor(n) - b.anchor(x)
			if aimed == "" and d.y < -20.0 and absf(d.x) < absf(d.y) * 1.5:
				ghosts.append({"from": n, "to": x, "strength": 4, "owner": w.get_territory(n).owner, "result": LastRound.THROWN_BACK, "fellTo": "", "kind": "attack"})
				aimed = x
	## the three fates elsewhere, for the picture: thrown back, fell back, beaten in a scramble
	var kinds := [LastRound.FELL_BACK, LastRound.OUTFOUGHT, LastRound.THROWN_BACK]
	for id in MapLib.player_territory_ids(w, "blue"):
		if kinds.is_empty():
			break
		var to: String = MapLib.neighbors(map, id)[0]
		if to == aimed:
			continue
		ghosts.append({"from": id, "to": to, "strength": 3, "owner": "blue", "result": kinds.pop_front(), "fellTo": id, "kind": "attack"})
	b.ghosts = ghosts
	b.overlay.queue_redraw()
	await p.frames(3)
	var drawn: Array = b.drawn_fates.map(func(f): return str(f[0]))
	p.ok(drawn.has(LastRound.FELL_BACK) and drawn.has(LastRound.OUTFOUGHT) and drawn.has(LastRound.THROWN_BACK),
		"three fates, three marks: %s" % str(drawn))
	var old_size: float = clampf(b.token_radius() * 0.32, 6.0, 9.0)
	p.ok(b.fate_mark_size() >= old_size * 1.45, "the fate marks are half as big again (%.1f, were %.1f), on a solid disc" % [b.fate_mark_size(), old_size])
	p.ok(aimed != "" and b.drawn_cut.has(aimed), "a cut-off land with a column thrown back from its walls from above (%s)" % aimed)
	if aimed != "":
		var plate: Vector2 = b.drawn_cut[aimed]
		var nearest := INF
		for f in b.drawn_fates:
			nearest = minf(nearest, (f[1] as Vector2).distance_to(plate))
		p.ok(nearest > b.fate_mark_size() + 16.0, "%s's CUT OFF keeps clear of the cross at its walls (%d px away; the plate %s, under its name)" % [aimed, int(nearest), str(plate)])
	var on_names: Array = []
	for f in b.drawn_fates:
		var m: float = b.fate_mark_size() + 6.0
		for nb in b.token_boxes(true, false):
			if (nb as Rect2).intersects(Rect2(f[1] - Vector2(m, m), Vector2(m, m) * 2.0)):
				on_names.append(str(f[0]))
	p.ok(on_names.is_empty(), "no fate mark sits on a land's name (%d marks; on names: %s)" % [b.drawn_fates.size(), str(on_names)])
	await snap("02_fates_and_cut_off")
	b.zoom_at(b.anchor(aimed) if aimed != "" else b.size * 0.5, 2.0)
	await p.frames(4)
	await snap("02b_fates_zoomed")
	b.queue_free()
	await p.frames(2)


func _roster() -> void:
	## the Isthmus has no cards: the roster's "3 lands · +7" left the stars and crown nothing for
	## the name but "Da" (and Varek's, crowned, nothing at all)
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 7, "length": "short", "timer": 0, "capitals": true, "fortune": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]})
	await p.frames(8)
	var gs: Control = main.current
	gs.intro._done()
	var s: Node = main.session
	var guard := 0
	while s.phase == Session.Phase.DRAFT and guard < 200:
		guard += 1
		if s.is_human(s.draft_turn()):
			s.claim(s.draft_pick_for("red"))
		else:
			s.ai_claim()
		await p.frames(1)
	gs.roster.refresh()
	await p.frames(4)
	var shown: Array = []
	var whole := true
	for pid in ["red", "blue"]:
		var l: Label = gs.roster._rows[pid]["name"]
		var need: float = minf(l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x, gs.roster.NAME_MIN)
		shown.append("%s %d of %d px" % [l.text, int(l.size.x), int(need)])
		if l.size.x + 1.0 < need:
			whole = false
	p.ok(whole, "the roster gives each name its room, on a map without cards (%s)" % ", ".join(shown))
	await snap("03_roster_isthmus")
	main.queue_free()
	await p.frames(2)


func key(code: Key, ctrl: bool = false) -> void:
	## a real key press and release, through the viewport (as a player's hand would)
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		ev.ctrl_pressed = ctrl
		Input.parse_input_event(ev)
		await p.frames(2)


func _keys() -> void:
	## the keys do what the screen says, and a dialog over the table takes them
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/known24.json", "seed": 3, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"}]})
	await p.frames(10)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await p.frames(3)
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 600:
		guard += 1
		await p.frames(1)
	s.auto_deploy()
	## ctrl-enter behind the pause menu: nothing happens to the sheet
	gs.open_menu()
	await p.frames(2)
	await key(KEY_ENTER, true)
	p.ok(s.phase == Session.Phase.PLANNING and s.plan_step == "reinforce" and gs._modal != null,
		"ctrl-enter behind the pause menu leaves the sheet alone (still %s, the menu still up)" % s.plan_step)
	await key(KEY_C)
	await key(KEY_C)
	var cards := 0
	for c in gs.get_children():
		if c.get_script() == CardsDialog:
			cards += 1
	p.ok(s.map.cards and cards == 0, "C behind the pause menu opens no cards (%d)" % cards)
	await key(KEY_ESCAPE)
	p.ok(gs._modal == null, "Esc closes the pause menu")
	## C opens your cards once; a second C doesn't stack another hand over it
	await key(KEY_C)
	await key(KEY_C)
	cards = 0
	for c in gs.get_children():
		if c.get_script() == CardsDialog and not c.is_queued_for_deletion():
			cards += 1
	p.ok(cards == 1, "C opens your cards, and a second C opens no second hand (%d)" % cards)
	await key(KEY_ESCAPE)
	await p.frames(2)
	cards = 0
	for c in gs.get_children():
		if c.get_script() == CardsDialog and not c.is_queued_for_deletion():
			cards += 1
	p.ok(cards == 0 and gs._modal == null, "Esc closes them, and opens no pause menu")
	## Esc closes the settings (it used to open the pause menu hidden behind them)
	main.open_settings()
	await p.frames(3)
	await key(KEY_ESCAPE)
	p.ok(main.settings_panel == null and gs._modal == null, "Esc closes the settings, and opens nothing behind them")
	## ctrl-enter in the reinforcement step does what the dial does: on to the orders, not sealed
	await key(KEY_ENTER, true)
	p.ok(s.phase == Session.Phase.PLANNING and s.plan_step == "orders", "ctrl-enter with the recruits placed moves on to the orders, as the dial does (%s)" % s.plan_step)
	## the advisor's plan: Esc keeps your own
	gs.open_plan()
	await p.frames(3)
	await key(KEY_ESCAPE)
	var plans := 0
	for c in gs.get_children():
		if c.get_script() == PlanDialog and not c.is_queued_for_deletion():
			plans += 1
	p.ok(plans == 0 and gs._modal == null, "Esc on the advisor's plan keeps your own, and opens no pause menu")
	## seal; the round's report takes Space to go on (not in its first moment)
	await key(KEY_ENTER, true)
	guard = 0
	while s.phase != Session.Phase.RECAP and guard < 4000:
		guard += 1
		if s.phase == Session.Phase.CINEMA:
			gs.cinema.skip()
		if gs.theater.visible:
			gs.theater._skip()
		if s.phase == Session.Phase.MANEUVER:
			s.lock()
		await p.frames(1)
	p.ok(s.phase == Session.Phase.RECAP and gs.recap.visible, "the round's report is up (%s)" % Session.Phase.keys()[s.phase])
	await key(KEY_SPACE)
	p.ok(s.phase == Session.Phase.RECAP, "a Space at once doesn't skip it unread")
	await snap("04_round_report_you")
	await p.get_tree().create_timer(1.0).timeout
	await key(KEY_SPACE)
	await p.frames(4)
	p.ok(s.phase != Session.Phase.RECAP and not gs.recap.visible, "a moment later, Space goes on to the next round (%s)" % Session.Phase.keys()[s.phase])
	main.queue_free()
	await p.frames(2)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
