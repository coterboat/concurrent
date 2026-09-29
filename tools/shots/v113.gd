## v1.13 in the real client: the map says what the engine knows. Last round's columns carry their
## fate (a cross where one was thrown back; a column beaten in a border clash stops where it
## died), your lands that could be outnumbered wear a sword plate, a land that holds the road home
## for others an amber ring, each region's label a pip per land in its holder's colour, and the
## land tooltip, the recap and the roster say the rest in words.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const LastRound := preload("res://game/core/last_round.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")
const Resolve := preload("res://engine/resolve.gd")
const Income := preload("res://engine/income.gd")

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
	var r: Array = await _start(main, 113)
	await _fates(r[0], r[1])
	await _threats(r[0], r[1])
	_recap(r[0], r[1])
	await _lead(r[0], r[1])
	await _howto()
	await _upset(main)
	await _bot_0b2fe07(main)
	p.log("v113 probe done")


func _howto() -> void:
	## the rules book's new page, and it fits the 1440x900 screen
	var HowTo: Script = load("res://game/ui/howto_screen.gd")
	var idx := -1
	for i in HowTo.PAGES.size():
		if str(HowTo.PAGES[i][0]) == "Reading the map":
			idx = i
	p.ok(idx >= 0, "How to Play has a page on reading the map")
	var h: Control = HowTo.new()
	h.overlay = true
	h.start_page = maxi(0, idx)
	p.get_tree().root.add_child(h)
	await p.frames(12)
	var body: Label = h._body
	var bottom: float = body.get_global_rect().end.y
	p.ok(body.text.contains("SWORD PLATE") and bottom <= 900.0 and body.get_visible_line_count() >= body.get_line_count(),
		"the page fits the screen (%d of %d lines shown, its text ends at y=%d)" % [body.get_visible_line_count(), body.get_line_count(), int(bottom)])
	await snap("05_howto_reading_the_map")
	h.queue_free()
	await p.frames(2)


func _bot_0b2fe07(main: Control) -> void:
	## The playtest bot's report on 0b2fe07 (B-005..B-008), as facts on the screen: a human seat
	## named "You", round 2, your own assault paused for a call.
	main.start_game({"map": "res://maps/knife7.json", "seed": 7, "length": "standard", "timer": 0, "capitals": true, "fortune": true, "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var guard := 0
	while (s.phase != Session.Phase.PLANNING or s.world.round < 2) and guard < 3000:
		guard += 1
		match s.phase:
			Session.Phase.DRAFT:
				if s.is_human(s.draft_turn()):
					s.claim(s.draft_pick_for("red"))
				else:
					s.ai_claim()
			Session.Phase.RECAP:
				gs.recap.visible = false
				s.next_round()
			Session.Phase.PLANNING, Session.Phase.OPENING:
				s.auto_deploy()
				s.lock()
			Session.Phase.MANEUVER:
				s.lock()
			Session.Phase.CINEMA:
				gs.cinema.skip()
		await p.frames(2)
	## B-005: the recap names the human seat as "you", never "You's"
	var evs := [
		{"kind": Types.EVENT_CAPITAL_TAKEN, "playerId": "red", "by": "blue", "terrId": "ridge"},
		{"kind": Types.EVENT_CLASH, "hexA": "gate", "hexB": "ridge", "playerA": "blue", "playerB": "red", "winnerId": "blue"},
		{"kind": Types.EVENT_CARDS_CAPTURED, "from": "red", "to": "blue", "cards": []},
		{"kind": Types.EVENT_PLAYER_ELIMINATED, "playerId": "red"}]
	var all: String = " / ".join(gs.recap._lines(evs).map(func(l): return str(l[1])))
	p.ok(not all.contains("You's") and not all.contains("You has") and all.contains("took your capital") and all.contains("beat your column")
		and all.contains("seized your cards") and all.contains("You have been eliminated"), "B-005: the recap says \"your\" and \"you have\" (%s)" % all)
	## B-006 / B-007: your assault in round 2 pauses for a call; while the camera swoops down to it
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 14, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("gate", "blue", 6, 1)
	w.set_hex("harbor", "blue", 3, 1)
	w.set_hex("docks", "green", 4, 1)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 13)
	_order(s, "blue", [])
	_order(s, "green", [])
	s.lock()
	var cin: Control = gs.cinema
	var th: Control = gs.theater
	var banner := ""
	var paused := false
	var escaped := false
	var opened_after := false
	guard = 0
	while guard < 6000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if not escaped and cin._waiting and not th.visible:
			banner = gs._plate_round.text
			paused = not s.pending.is_empty() and s.world.round == 2 ## the case B-006 was: not absorbed yet
			var ev := InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.pressed = true
			Input.parse_input_event(ev)
			escaped = true
			await p.frames(90) ## the swoop would have ended and the battlefield opened by now
			opened_after = th.visible
		elif th.visible:
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer("p")
		elif cin.visible and not cin._waiting:
			cin.advance()
		await p.frames(1)
	p.ok(escaped and paused and banner.begins_with("Round 2"), "B-006: while your battle waits for a call (paused %s), the banner says the round being fought (%s)" % [paused, banner])
	p.ok(escaped and not opened_after and cin._theater_off, "B-007: Esc during the swoop skips the battles; the battlefield doesn't open")


func _start(main: Control, seed: int) -> Array:
	main.start_game({"map": "res://maps/isles24.json", "seed": seed, "length": "standard", "timer": 0, "capitals": true, "fortune": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var guard := 0
	while s.phase == Session.Phase.DRAFT and guard < 400:
		guard += 1
		if s.is_human(s.draft_turn()):
			s.claim(s.draft_pick_for("red"))
		else:
			s.ai_claim()
		await p.frames(1)
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	guard = 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	return [s, gs]


func _paint(s: Node, lands: Dictionary, capitals: Dictionary) -> void:
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	for t in lands.keys():
		var v: Array = lands[t]
		w.set_hex(str(t), str(v[0]), int(v[1]), int(v[2]) if v.size() > 2 else 1)
	for pid in capitals.keys():
		(w.players[pid] as Types.PlayerState).capital = str(capitals[pid])
	s.drafts.clear()
	s.changed.emit()


func _order(s: Node, pid: String, legs: Array) -> void:
	var sh := Types.Sheet.new()
	sh.player_id = pid
	for leg in legs:
		var pk := Types.Packet.new()
		pk.from_id = leg[0]
		pk.to_id = leg[1]
		pk.strength = leg[2]
		pk.stance = "hold"
		sh.packets.append(pk)
	s.locked[pid] = sh


func _fates(s: Node, gs: Control) -> void:
	## Great Vane: Dad (capital Vanemoor) sends 6 from Vanetor at Varek's Vaneholt while Varek sends
	## 8 the other way (a border clash on the road between them), and 3 from Vanefell at Hask's
	## Vanehead, 10 dug in (thrown back, or fallen back). Then Dad plans the next round.
	_paint(s, {"vanemoor": ["red", 4, 3], "vanefell": ["red", 5], "vanetor": ["red", 7], "vaneholt": ["blue", 14, 3], "vanewick": ["blue", 2],
		"vanehead": ["green", 10, 3], "vanestrand": ["green", 2], "reachrock": ["blue", 3], "morrowfen": ["green", 2]},
		{"red": "vanemoor", "blue": "vanewick", "green": "vanestrand"})
	await p.frames(4)
	s.set_attack("vanetor", "vaneholt", 6)
	s.set_attack("vanefell", "vanehead", 3)
	_order(s, "blue", [["vaneholt", "vanetor", 8]])
	_order(s, "green", [])
	s.lock()
	var th: Control = gs.theater
	var guard := 0
	while guard < 12000 and s.phase != Session.Phase.PLANNING:
		guard += 1
		if th.visible:
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer("p")
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		elif s.phase == Session.Phase.RECAP:
			if gs.recap.visible:
				await p.frames(20)
				await snap("00_recap")
			gs.recap.visible = false
			s.next_round()
		elif s.phase == Session.Phase.MANEUVER:
			s.lock()
		await p.frames(1)
	await p.frames(30)
	var mine: Array = s.ghosts.filter(func(g): return str(g["owner"]) == "red")
	var fated: bool = mine.size() == 2 and mine.all(func(g): return str(g.get("result", "")) != "")
	p.ok(fated, "Dad's two columns carry their fates (%s)" % str(mine.map(func(g): return "%s->%s %s" % [g["from"], g["to"], g["result"]])))
	var clash_dead: Array = s.ghosts.filter(func(g): return str(g.get("result", "")) == LastRound.CLASH)
	var clashes: int = s.events.filter(func(e): return str(e.get("kind", "")) == Types.EVENT_CLASH).size()
	p.ok(clashes == 1 and clash_dead.size() == 1, "the border clash on the Vanetor road: one column died there, and the map keeps its arrow, halfway (%d clash, %d dead)" % [clashes, clash_dead.size()])
	var head: Dictionary = mine.filter(func(g): return str(g["to"]) == "vanehead")[0]
	p.ok([LastRound.THROWN_BACK, LastRound.FELL_BACK].has(str(head["result"])) and str(head["by"]) == "green", "the 3 sent at Hask's Vanehead were beaten there (%s)" % head["result"])
	p.ok(gs.board.ghosts.size() == s.ghosts.size() + s.move_ghosts.size(), "the board draws last round's columns while you plan")
	## the tooltip over Vanehead says what became of them
	gs._on_hover("vanehead")
	var tip: String = gs._hover_label.text
	var want: String = LastRound.said(head, s.name_of, s.hex_name)
	p.ok(tip.contains("Last round: ") and tip.contains(want), "hovering Vanehead: \"%s\"" % tip.replace("\n", " | "))
	gs._on_hover("")
	gs.board.focus_on(["vanetor", "vaneholt", "vanehead", "vanefell"], 2.0)
	await _banner_gone(gs)
	await snap("01_fates_on_the_map")
	gs._on_hover("vanehead")
	await p.frames(6)
	await snap("02_tooltip_last_round")
	gs._on_hover("")
	await _three_fates(s, gs)


func _three_fates(s: Node, gs: Control) -> void:
	## v1.13.2 (the play critic): each fate its own mark. Thrown back, a red cross; fell back, a
	## chevron pointing the way they went; beaten in a scramble, crossed swords
	var b: Control = gs.board
	var kept: Array = b.ghosts
	b.ghosts = [
		{"from": "vanetor", "to": "vaneholt", "strength": 6, "owner": "red", "result": LastRound.THROWN_BACK, "by": "blue", "left": 0, "fellTo": ""},
		{"from": "vanefell", "to": "vanehead", "strength": 3, "owner": "red", "result": LastRound.FELL_BACK, "by": "green", "left": 2, "fellTo": "vanefell"},
		{"from": "vaneholt", "to": "vanemoor", "strength": 5, "owner": "blue", "result": LastRound.OUTFOUGHT, "by": "green", "left": 0, "fellTo": ""}]
	b.refresh()
	await p.frames(4)
	var fates: Array = b.drawn_fates.map(func(f): return str(f[0]))
	fates.sort()
	var want: Array = [LastRound.FELL_BACK, LastRound.OUTFOUGHT, LastRound.THROWN_BACK]
	want.sort()
	p.ok(fates == want, "three fates, three marks: %s" % str(fates))
	await snap("02b_three_fates")
	b.ghosts = kept
	b.refresh()
	await p.frames(2)


func _threats(s: Node, gs: Control) -> void:
	## Dad holds Vanemoor (the capital), Vanefell and Vanetor; Vanefell is all that joins Vanetor
	## to the capital. Varek's 14 at Vaneholt border all three.
	_paint(s, {"vanemoor": ["red", 3, 1], "vanefell": ["red", 2], "vanetor": ["red", 2], "vaneholt": ["blue", 14, 3], "vanewick": ["blue", 2],
		"vanehead": ["green", 4, 2], "vanestrand": ["green", 2], "reachrock": ["blue", 3], "morrowfen": ["green", 2], "morrowquay": ["green", 3]},
		{"red": "vanemoor", "blue": "vanewick", "green": "vanestrand"})
	s.changed.emit()
	await p.frames(8)
	var b: Control = gs.board
	p.ok(b.hinges.has("vanefell") and Array(b.hinges["vanefell"]).has("vanetor"), "Vanefell wears the amber ring: it holds the road home for Vanetor (%s)" % str(b.hinges))
	p.ok(b.threats.has("vanetor") and bool(b.threats["vanetor"]["danger"]) and str(b.threats["vanetor"]["owner"]) == "blue", "Vanetor (2) could be outnumbered by Varek: a sword plate (%s)" % str(b.threats.get("vanetor", {})))
	p.ok(b.threats.has("vanemoor") and bool(b.threats["vanemoor"]["capital"]) and bool(b.threats["vanemoor"]["danger"]), "the capital could be outnumbered: it rings crimson (%s)" % str(b.threats.get("vanemoor", {})))
	gs._on_hover("vanefell")
	var tip: String = gs._hover_label.text
	p.ok(tip.contains("The road home for Vane Tor") and tip.contains("ways into Great Vane"), "hovering Vanefell: \"%s\"" % tip.replace("\n", " | "))
	## v1.13.2: the tooltip keeps off the middle: on Vanefell's outer side (it's left of centre), or
	## above or below it reaching outward; never over the land, and no wider than LandTip.WIDE
	var tr := Rect2(gs._hover_tip.position, gs._hover_tip.size)
	var at: Vector2 = b.anchor("vanefell")
	var gap: float = b.token_radius() + 16.0
	var near: float = at.distance_to(Vector2(clampf(at.x, tr.position.x, tr.end.x), clampf(at.y, tr.position.y, tr.end.y)))
	p.ok(near >= gap - 0.5 and Rect2(Vector2.ZERO, gs.size).encloses(tr) and tr.get_center().x <= at.x + gap and tr.size.x <= 400.5,
		"the tooltip keeps clear of Vanefell and off the middle (%s, the land at %s)" % [tr, at])
	gs._on_hover("vanetor")
	var tip2: String = gs._hover_label.text
	p.ok(tip2.contains("could bring up to"), "hovering Vanetor: \"%s\"" % tip2.replace("\n", " | "))
	gs._on_hover("vanestrand")
	var tip3: String = gs._hover_label.text
	p.ok(tip3.contains("→ Vane Strand (here)"), "an entrance to Great Vane says so: \"%s\"" % tip3.replace("\n", " | "))
	gs._on_hover("")
	## strip the land that holds the road home, and sealing warns you
	s.set_attack("vanefell", "vaneholt", 2)
	var warn: String = " / ".join(s.warnings())
	p.ok(warn.contains("It holds the road home for Vane Tor"), "sealing with Vanefell stripped warns of the road home: \"%s\"" % warn)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	## what you do changes it: reinforce Vanetor and its plate goes
	var before: bool = bool(b.threats["vanetor"]["danger"])
	for i in 6:
		s.add_place("vanetor", 1)
	await p.frames(4)
	## v1.13.2: an enemy land's ceiling (≤N) only where it borders you, or while you hover it
	var bordering := func(id: String) -> bool:
		for nb in MapLib.neighbors(s.map, id):
			if s.world.get_territory(nb).owner == "red":
				return true
		return false
	var enemy: Array = Array(s.map.territory_ids()).filter(func(t): return s.world.get_territory(t).owner not in ["red", Types.UNOCCUPIED])
	var far: Array = enemy.filter(func(t): return not bordering.call(t) and s.world.get_territory(t).owner != "neutral" and Income.cap_of(s.world, s.map, t) > 0)
	## a ceiling says something only where recruits can land (not neutral, not cut off)
	var could: Array = enemy.filter(func(t): return s.world.get_territory(t).owner != "neutral" and Income.cap_of(s.world, s.map, t) > 0)
	var want: Array = could.filter(func(t): return bordering.call(t))
	var shown: Array = b.drawn_ceilings.duplicate()
	shown.sort()
	want.sort()
	p.ok(not shown.is_empty() and shown == want,
		"enemy ceilings only on your borders: %s (of %d enemy lands that could show one)" % [", ".join(shown), could.size()])
	if not far.is_empty():
		b.hovered = str(far[0])
		b.refresh()
		await p.frames(3)
		p.ok(b.drawn_ceilings.has(str(far[0])), "hovering %s, away from your borders, shows its ceiling (hovered %s, shown %s, ceilings %s)" % [far[0], b.hovered, b.drawn_ceilings, b.show_ceiling])
		b.hovered = ""
		b.refresh()
		await p.frames(2)
	p.ok(before and (not b.threats.has("vanetor") or not bool(b.threats["vanetor"]["danger"]) or int(b.threats["vanetor"]["held"]) > 2), "placing recruits on Vanetor updates what it faces (held %s)" % str(b.threats.get("vanetor", {}).get("held", "?")))
	s.clear_placements()
	await p.frames(4)
	b.focus_on(["vanemoor", "vanefell", "vanetor", "vaneholt", "vanewick"], 2.0)
	await p.frames(40)
	await snap("03_threats_and_the_road_home")
	## the region's pips: Great Vane is Dad's 3, Varek's 2, Hask's 2
	var sh: Dictionary = BoardFacts.shares(s.world, s.map)["vane"]
	p.ok(str(sh["leader"]) == "red" and int(sh["led"]) == 3 and int(sh["to_go"]) == 4, "Great Vane's pips: Dad holds 3 of 7 (%s)" % str(sh["by"]))
	b.reset_view()
	await p.frames(40)
	await snap("04_region_pips")
	## the roster says what each commander raises next round
	var subs: Array = _labels(gs.roster).filter(func(t): return t.contains(" lands · +"))
	p.ok(subs.size() == 3, "the roster shows each commander's recruits for next round (%s)" % ", ".join(subs))
	## the recruits' breakdown names the capital's treasury (and adds up; tests/test_v113.gd)
	var bd: Dictionary = s.income_breakdown()
	p.ok(int(bd["capital"]) == 2, "the recruits' breakdown counts the capital's treasury (%s)" % str(bd))


func _recap(s: Node, gs: Control) -> void:
	## the recap names what it used to leave out: a melee held, a scramble won, a fall-back, a capital
	var evs := [
		{"kind": Types.EVENT_MELEE, "to": "vaneholt", "defenderId": "blue", "defenderSize": 9, "defenderLeft": 3, "fronts": [{"attackerId": "red"}, {"attackerId": "green"}]},
		{"kind": Types.EVENT_SCRAMBLE, "to": "vanewick", "winnerId": "green", "winnerLeft": 2, "fronts": [{"playerId": "red"}, {"playerId": "green"}, {"playerId": "blue"}]},
		{"kind": Types.EVENT_INVASION, "from": "vanefell", "to": "vanehead", "attackerId": "red", "defenderId": "green", "attackerWon": false, "fellBack": true, "attackerLeft": 2, "refuge": "vanefell"},
		{"kind": Types.EVENT_CAPITAL_TAKEN, "playerId": "blue", "by": "red", "terrId": "vanewick"},
		{"kind": Types.EVENT_CLASH, "hexA": "vanetor", "hexB": "vaneholt", "playerA": "blue", "playerB": "red", "winnerId": "red"}]
	var lines: Array = gs.recap._lines(evs).map(func(l): return str(l[1]))
	var all: String = " / ".join(lines)
	p.ok(all.contains("held Vaneholt against Dad and Commodore Hask at once"), "recap: a melee held")
	p.ok(all.contains("Commodore Hask won the scramble for Vanewick"), "recap: a scramble won")
	p.ok(all.contains("(2 fell back to Vanefell)"), "recap: a fall-back")
	p.ok(all.contains("Dad took Grand Marshal Varek's capital, Vanewick"), "recap: a capital taken")
	p.ok(all.contains("on the road between Vane Tor and Vaneholt"), "recap: a border clash named by its road (%s)" % all)


func _banner_gone(gs: Control) -> void:
	## the phase banner frees itself after ~2.6 s, however fast the frames run
	var guard := 0
	while guard < 2000 and gs._banner_node != null and is_instance_valid(gs._banner_node):
		guard += 1
		await p.frames(1)
	await p.frames(20)


func _lead(s: Node, gs: Control) -> void:
	## the recap opens with the moments: a new leader on points, a capital won back
	var real_h: Array = s.history.duplicate(true)
	var real_log: Array = s.capital_log.duplicate(true)
	var real_ev: Array = s.events
	s.history = [{"round": 1, "score": {"red": 5, "blue": 7, "green": 4}}, {"round": 2, "score": {"red": 9, "blue": 7, "green": 4}}]
	s.capital_log = [{"round": 1, "pid": "red", "by": "blue", "land": "vanemoor"}]
	s.events = [{"kind": Types.EVENT_OCCUPIED, "terrId": "vanemoor", "playerId": "red", "armies": 4}]
	gs.recap.show_round()
	await p.frames(20)
	var text: String = " / ".join(_labels(gs.recap))
	p.ok(text.contains("Dad takes the lead from Grand Marshal Varek."), "the recap opens with the lead changing hands")
	p.ok(text.contains("Dad won back Vanemoor, the capital lost in round 1."), "and a capital won back")
	await snap("06_recap_moments")
	gs.recap.visible = false
	s.history = real_h
	s.capital_log = real_log
	s.events = real_ev
	## the endgame carries into the battles
	var was: String = Audio.heat
	Audio.heat = "endgame"
	var bm: String = Audio.battle_music()
	Audio.heat = ""
	p.ok(bm == ("endgame" if Audio.has_music("endgame") else "battle") and Audio.battle_music() == "battle", "the battles play the endgame's music in the last rounds (%s)" % bm)
	Audio.heat = was


func _upset(main: Control) -> void:
	## Varek's 3 from Ridge against Hask's 6 at The Gate (2 of them dug in), on the Knife: find a
	## war where the 3 take it (the engine's own dice, seed by seed), then play that round in the
	## real client
	var land := {"beacon": ["red", 2], "mill": ["red", 2], "ridge": ["blue", 4], "gate": ["green", 4, 2], "harbor": ["green", 2]}
	var r: Array = await _knife_war(main, 1, land)
	var sheets := [_sheet("blue", [["ridge", "gate", 3]]), _sheet("green", []), _sheet("red", [])]
	var found := -1
	for sd in range(1, 400):
		var res: Dictionary = Resolve.resolve_round((r[0] as Node).world.clone(), (r[0] as Node).map, sheets, sd)
		if (res["world"] as Types.World).get_territory("gate").owner == "blue":
			found = sd
			break
	p.ok(found > 0, "a war where Varek's 3 take Hask's 6 at The Gate (seed %d)" % found)
	if found < 0:
		return
	r = await _knife_war(main, found, land)
	var s: Node = r[0]
	var gs: Control = r[1]
	_order(s, "blue", [["ridge", "gate", 3]])
	_order(s, "green", [])
	s.lock()
	var th: Control = gs.theater
	var shout := ""
	var closing := ""
	var guard := 0
	while guard < 9000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			if str(th._state) == "done" and shout == "":
				await p.frames(4)
				shout = str(th._shout.text)
				closing = str(th._odds_bar.edge) ## the bar draws its own words: head over it, edge under
				await snap("07_against_all_odds")
			match str(th._state):
				"ready", "done":
					th.press()
				"call":
					th._answer("p")
		elif gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(shout == "AGAINST ALL ODDS!", "the battlefield shouts it, whoever fought (\"%s\")" % shout)
	p.ok(closing.contains("against") and closing.contains("% odds"), "and the odds bar closes with the odds they beat (%s)" % closing)


func _knife_war(main: Control, sd: int, land: Dictionary) -> Array:
	main.start_game({"map": "res://maps/knife7.json", "seed": sd, "length": "standard", "timer": 0, "capitals": false, "fortune": false, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(3)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(3)
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	_paint(s, land, {})
	return [s, gs]


func _sheet(pid: String, legs: Array) -> Types.Sheet:
	var sh := Types.Sheet.new()
	sh.player_id = pid
	for leg in legs:
		var pk := Types.Packet.new()
		pk.from_id = leg[0]
		pk.to_id = leg[1]
		pk.strength = leg[2]
		pk.stance = "hold"
		sh.packets.append(pk)
	return sh


func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
