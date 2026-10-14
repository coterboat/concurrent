## v2.0.1 in the real client: the play critic's notes on e5764ba, at the fit zoom on a 1280×800
## window. A capital's crown keeps off the other lands' names; a region's bonus and pips keep off the
## names and the crowns, on the chart and on the land; two fate marks of a kind that would touch are
## one mark with its count; a land's tip goes when a dialog or the round's report opens over it.
##   SHOT_DIR=/dir ./scripts/shot.sh v201
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Board := preload("res://game/board/map_board.gd")
const LastRound := preload("res://game/core/last_round.gd")
const Session := preload("res://game/core/session.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1280, 800)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	await _crowns()
	await _fates()
	for land in [false, true]:
		await _game_board(land)
	await _tip()
	p.log("v201 probe done")


func _board(mid: String, seats: Array) -> Array:
	## a dealt board at the game screen's size and padding, fit to the screen, as you plan
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
	map.rules = 20
	map.capitals = true
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
	b.refresh()
	b.reset_view()
	await p.frames(4)
	return [b, map, w]


func _on_names(b: Control, box: Rect2, own: String) -> float:
	var names: Array = b.token_boxes(true, false)
	var a := 0.0
	for i in names.size():
		if str(b.art.order[i]) != own:
			a += box.intersection(names[i] as Rect2).get_area()
	return a


func _crowns() -> void:
	## every land on every map, made a capital in turn: its crown covers no other land's name
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}, {"id": "gold", "name": "D"}]
	for mid in ["knife7", "marches18", "known24", "isles24", "ring26", "world30"]:
		var r: Array = await _board(mid, seats.slice(0, 2) if mid in ["knife7", "marches18"] else seats)
		var b: Control = r[0]
		var w: Types.World = r[2]
		var hits: Array = []
		var bad_hits := 0
		var moved := 0
		var r0: float = b.token_radius()
		for id in b.art.order:
			var o: String = w.get_territory(str(id)).owner
			if o == "" or o == Types.UNOCCUPIED or o == "neutral":
				continue
			b.capital_override = {o: str(id)}
			b._names_now = []
			var box: Rect2 = b.crown_rect(str(id))
			if absf(box.get_center().x - b.anchor(str(id)).x) > 1.0 or box.size.y < clampf(r0 * 0.85, 15.0, 24.0) * 1.9:
				moved += 1
			var on: float = _on_names(b, box, str(id))
			if on > 0.0:
				## no spot clears: the name it touches is written again over the crown
				b.overlay.queue_redraw()
				await p.frames(2)
				var under: Array = []
				var names: Array = b.token_boxes(true, false)
				for i in names.size():
					if str(b.art.order[i]) != str(id) and (names[i] as Rect2).intersects(b.drawn_crowns.get(str(id), Rect2())):
						under.append(str(b.art.order[i]))
				var all_over: bool = not under.is_empty() and under.all(func(u): return b.names_over.has(u))
				hits.append("%s %d px² (%s %s)" % [id, int(on), "/".join(under), "written over it" if all_over else "NOT WRITTEN OVER"])
				if not all_over:
					bad_hits += 1
		## only where the lands are packed closer than a crown (the Ring's middle) may one touch a name
		p.ok(bad_hits == 0 and (hits.is_empty() or mid == "ring26"), "%s: every land crowned in turn, no crown hides another land's name (%d set aside from the brow's middle; touching a name, which is written over it: %s)" % [mid, moved, ", ".join(hits) if not hits.is_empty() else "none"])
		## and the real deal's capitals, drawn: the bonus keeps off them too
		b.capital_override = {}
		for pid in w.players.keys():
			var mine: Array = MapLib.player_territory_ids(w, str(pid))
			if not mine.is_empty():
				(w.players[pid] as Types.PlayerState).capital = str(mine[0])
		b._bonus_at.clear()
		b.overlay.queue_redraw()
		await p.frames(3)
		var crowns: Array = b.drawn_crowns.values()
		var on_crown: Array = []
		for reg in b.drawn_bonus.keys():
			if Board._overlap(b.drawn_bonus[reg], crowns) > 0.0:
				on_crown.append(reg)
		p.ok(b.drawn_crowns.size() == w.players.size() and on_crown.is_empty(), "%s: %d crowns drawn, no region's bonus or pips on a crown (%s)" % [mid, b.drawn_crowns.size(), str(on_crown)])
		if mid == "ring26":
			await snap("01_crowns_ring26")
		b.queue_free()
		await p.frames(2)


func _fates() -> void:
	## every land of one commander thrown back from each of its neighbours' walls: two marks of a
	## kind never touch, and the merged ones say how many
	var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}]
	var r: Array = await _board("ring26", seats)
	var b: Control = r[0]
	var map: Types.MapDef = r[1]
	var w: Types.World = r[2]
	var ghosts: Array = []
	var n := 0
	for id in MapLib.player_territory_ids(w, "red"):
		for nb in MapLib.neighbors(map, id):
			if w.get_territory(nb).owner != "red":
				ghosts.append({"from": nb, "to": id, "strength": 3, "owner": w.get_territory(nb).owner, "result": LastRound.THROWN_BACK, "fellTo": "", "kind": "attack"})
				n += 1
	b.ghosts = ghosts
	b.overlay.queue_redraw()
	await p.frames(3)
	var touching := 0
	var counted := 0
	var merged := 0
	var lim: float = (b.fate_mark_size() + 6.0) * 2.0
	for i in b.drawn_fates.size():
		var fi: Array = b.drawn_fates[i]
		counted += int(fi[2])
		if int(fi[2]) > 1:
			merged += 1
		for j in range(i + 1, b.drawn_fates.size()):
			var fj: Array = b.drawn_fates[j]
			if str(fi[0]) == str(fj[0]) and (fi[1] as Vector2).distance_to(fj[1]) < lim:
				touching += 1
	p.ok(touching == 0, "no two marks of one kind touch (%d columns thrown back, %d marks)" % [n, b.drawn_fates.size()])
	p.ok(counted == n and merged > 0, "the marks count every column (%d of %d), %d of them standing for more than one with a ×n" % [counted, n, merged])
	await snap("02_fates_merged")
	b.zoom_at(b.size * 0.5, 2.0)
	await p.frames(4)
	await snap("02b_fates_merged_zoomed")
	b.queue_free()
	await p.frames(2)


func _start(land: bool) -> Array:
	Settings.data["map_land"] = land
	Settings.data["battle_land"] = false
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/ring26.json", "seed": 41, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"},
		{"id": "gold", "name": "Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
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
	while s.phase != Session.Phase.PLANNING and guard < 900:
		guard += 1
		await p.frames(1)
	if land:
		while not (gs.land_board.ready_to_show() and gs.land_board.settled()) and guard < 2400:
			guard += 1
			await p.frames(1)
	await p.frames(30)
	return [main, s, gs]


func _game_board(land: bool) -> void:
	## the Ring in a real game at the fit zoom, on the chart and on the land: no bonus, no pips and
	## no crown on a land's name (the Ring's Crown region, seven lands packed in the middle, may
	## take a sliver, as v114 allows)
	var r: Array = await _start(land)
	var main: Control = r[0]
	var gs: Control = r[2]
	var b: Control = gs.board
	var view := "the land" if land else "the chart"
	p.ok(not land or b.projector.is_valid(), "%s: the board stands where it should" % view)
	var crowns: Array = b.drawn_crowns.values()
	var bad: Array = []
	for reg in b.drawn_bonus.keys():
		var box: Rect2 = b.drawn_bonus[reg]
		var on: float = _on_names(b, box, "")
		var oc: float = Board._overlap(box, crowns)
		if on > (120.0 if reg == "crown" else 0.0) or oc > (box.get_area() * 0.35 if reg == "crown" else 0.0):
			bad.append("%s: %d px² of names, %d px² of crowns" % [reg, int(on), int(oc)])
	var crowned: Array = []
	for id in b.drawn_crowns.keys():
		if _on_names(b, b.drawn_crowns[id], str(id)) > 0.0:
			crowned.append(id)
	p.ok(b.drawn_bonus.size() == (b.map.region_bonus as Dictionary).size() and bad.is_empty(),
		"%s at the fit zoom: %d region bonuses, none on a land's name or a crown (%s)" % [view, b.drawn_bonus.size(), ", ".join(bad) if not bad.is_empty() else "clear"])
	p.ok(b.drawn_crowns.size() == 4 and crowned.is_empty(), "%s: %d crowns, none on another land's name (%s)" % [view, b.drawn_crowns.size(), str(crowned)])
	await snap("03_ring_fit_%s" % ("land" if land else "chart"))
	main.queue_free()
	await p.frames(5)


func _point(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	await p.frames(3)


func _tip() -> void:
	## a land's tip shows while you point at it, and goes when a dialog or the round's report opens
	## over the board, though the cursor never moved
	var r: Array = await _start(false)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var b: Control = gs.board
	var id: String = str(b.art.order[b.art.order.size() / 2])
	var at: Vector2 = b.get_global_transform_with_canvas() * b.anchor(id)
	## (the window shows the 1440×900 canvas scaled; a motion event is in window pixels)
	at = at * (Vector2(p.get_window().size) / p.get_viewport().get_visible_rect().size)
	await _point(at + Vector2(1, 0))
	await _point(at)
	p.ok(gs._hover_tip.visible and b.hovered == id, "pointing at %s shows its tip" % id)
	gs.open_menu()
	await p.frames(3)
	p.ok(not gs._hover_tip.visible, "the pause menu opens over the board: the tip goes")
	gs._modal.queue_free()
	gs._modal = null
	await p.frames(2)
	await _point(at + Vector2(1, 1))
	p.ok(gs._hover_tip.visible, "pointing at it again brings the tip back")
	s.auto_deploy()
	s.lock()
	var guard := 0
	var during := false
	while s.phase != Session.Phase.RECAP and guard < 4000:
		guard += 1
		if s.phase == Session.Phase.CINEMA:
			gs.cinema.skip()
		if gs.theater.visible:
			gs.theater._skip()
		if s.phase == Session.Phase.MANEUVER:
			s.lock()
		await p.frames(2)
		if gs._hover_tip.visible and not during:
			during = true
			p.log("a tip up in %s (recap %s, theater %s)" % [Session.Phase.keys()[s.phase], str(gs.recap.visible), str(gs.theater.visible)])
	await p.frames(3)
	p.ok(s.phase == Session.Phase.RECAP and gs.recap.visible and not gs._hover_tip.visible and not during and gs.tip_covered(),
		"through the battles and the round's report, with the cursor still where it was, no tip (%s)" % Session.Phase.keys()[s.phase])
	await snap("04_report_no_tip")
	main.queue_free()
	await p.frames(2)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
