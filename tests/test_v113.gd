## v1.13: the map says what the engine knows. Display only (no rules change: games still play
## rules 20). Last round's columns carry their fate (took it, thrown back, fell back, beaten in the
## scramble, died on the border in a clash), and the planning screen's numbers add up to the
## engine's.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const MapLib := preload("res://engine/map.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Income := preload("res://engine/income.gd")
const LastRound := preload("res://game/core/last_round.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")
const Moments := preload("res://game/ui/moments.gd")
const Session := preload("res://game/core/session.gd")
const Style := preload("res://game/core/style.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_clash(report)
	_thrown_back(report)
	_scramble(report)
	_own_march(report)
	_facts(report)
	_moments(report)
	_wars(report)
	_session(report, tree)
	_bot_0b2fe07(report)
	Combat.use_rules(null)


func _knife() -> Types.MapDef:
	var m: Types.MapDef = H.knife7()
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.dig_cap = 3
	m.rules = 20
	m.fire_line = true
	return m


func _fates(w: Types.World, m: Types.MapDef, sheets: Array, seed: int) -> Array:
	var res: Dictionary = Resolve.resolve_round(w, m, sheets, seed)
	return [LastRound.ghosts(w, res["world"], sheets, res["events"]), res]


func _of(ghosts: Array, pid: String) -> Dictionary:
	for g in ghosts:
		if str(g["owner"]) == pid:
			return g
	return {}


func _clash(report: Callable) -> void:
	## Dad at Ridge and Varek at The Gate march on each other: one column dies on the border
	var m := _knife()
	var seen := 0
	for sd in range(1, 12):
		var w: Types.World = H.paint(m, {"ridge": ["red", 9], "gate": ["blue", 8], "beacon": ["red", 1], "harbor": ["blue", 1]})
		var sheets := [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("blue", [H.pkt("gate", "ridge", 7)])]
		var r: Array = _fates(w, m, sheets, sd)
		var clash: Dictionary = H.first(r[1]["events"], Types.EVENT_CLASH)
		if clash.is_empty():
			continue
		seen += 1
		var winner: String = str(clash["winnerId"])
		var loser: String = "blue" if winner == "red" else "red"
		var lg: Dictionary = _of(r[0], loser)
		var wg: Dictionary = _of(r[0], winner)
		report.call(str(lg["result"]) == LastRound.CLASH and str(lg["by"]) == winner and str(wg["result"]) != LastRound.CLASH,
			"seed %d: the beaten column (%s) died on the border at %s's hand; the winner's didn't (%s)" % [sd, loser, winner, wg["result"]])
		if seen >= 3:
			break
	report.call(seen >= 3, "border clashes seen (%d)" % seen)


func _thrown_back(report: Callable) -> void:
	## two men against a dug-in fortress of twelve: never taken; thrown back or fallen back, by Varek
	var m := _knife()
	var kinds := {}
	for sd in range(1, 30):
		var w: Types.World = H.paint(m, {"ridge": ["red", 6], "gate": ["blue", 12], "harbor": ["blue", 1]})
		w.get_territory("gate").garrison = 3
		var r: Array = _fates(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 5)]), H.sheet("blue")], sd)
		var g: Dictionary = _of(r[0], "red")
		kinds[str(g["result"])] = int(kinds.get(str(g["result"]), 0)) + 1
		var ok: bool = str(g["by"]) == "blue" and [LastRound.THROWN_BACK, LastRound.FELL_BACK].has(str(g["result"]))
		if str(g["result"]) == LastRound.FELL_BACK:
			ok = ok and int(g["left"]) > 0 and str(g["fellTo"]) != ""
		if not ok:
			report.call(false, "seed %d: a column beaten at the walls says so (%s)" % [sd, str(g)])
			return
	report.call(true, "a column beaten at the walls is thrown back, or falls back with its survivors, by the defender (%s)" % str(kinds))
	var line: String = LastRound.said({"owner": "red", "strength": 5, "result": LastRound.FELL_BACK, "by": "blue", "left": 2, "fellTo": "ridge"},
		func(p): return {"red": "Dad", "blue": "Varek"}[p], func(t): return t.capitalize())
	report.call(line == "Dad's 5 were beaten by Varek; 2 fell back to Ridge.", "said: %s" % line)
	var one: String = LastRound.said({"owner": "red", "strength": 1, "result": LastRound.THROWN_BACK, "by": "blue"},
		func(p): return {"red": "Dad", "blue": "Varek"}[p], func(t): return t)
	report.call(one == "Dad's lone man was thrown back by Varek.", "said, one man: %s" % one)


func _scramble(report: Callable) -> void:
	## three commanders on one empty land: one takes it, two were beaten in the fight for it
	var m := _knife()
	var w: Types.World = H.paint(m, {"ridge": ["red", 10], "docks": ["green", 9], "harbor": ["blue", 8]})
	var sheets := [H.sheet("red", [H.pkt("ridge", "gate", 9)]), H.sheet("green", [H.pkt("docks", "gate", 8)]), H.sheet("blue", [H.pkt("harbor", "gate", 7)])]
	var r: Array = _fates(w, m, sheets, 3)
	var holder: String = r[1]["world"].get_territory("gate").owner
	var took := 0
	var beaten := 0
	for g in r[0]:
		if str(g["result"]) == LastRound.TOOK and str(g["owner"]) == holder:
			took += 1
		elif str(g["result"]) == LastRound.OUTFOUGHT and str(g["by"]) == holder:
			beaten += 1
	report.call(took == 1 and beaten == 2, "a scramble: %s took it, and the other two were beaten by them (%d took, %d beaten)" % [holder, took, beaten])


func _own_march(report: Callable) -> void:
	var m := _knife()
	var w: Types.World = H.paint(m, {"ridge": ["red", 6], "beacon": ["red", 1], "harbor": ["blue", 1]})
	var r: Array = _fates(w, m, [H.sheet("red", [H.pkt("ridge", "beacon", 4)]), H.sheet("blue")], 1)
	report.call(str(_of(r[0], "red")["result"]) == "", "a march between your own lands has nothing to say")


func _facts(report: Callable) -> void:
	## the Knife is a line: Beacon - Ridge - Mill on the north shore, Ridge - The Gate - the south.
	## Red's capital is Mill; Ridge is all that joins Beacon to it.
	var m := _knife()
	m.supply = true
	m.capitals = true
	var w: Types.World = H.paint(m, {"mill": ["red", 3], "ridge": ["red", 2], "beacon": ["red", 1], "gate": ["blue", 12], "harbor": ["blue", 1]})
	(w.players["red"] as Types.PlayerState).capital = "mill"
	(w.players["blue"] as Types.PlayerState).capital = "harbor"
	var hin: Dictionary = BoardFacts.hinges(w, m, "red")
	report.call(hin.size() == 1 and hin.has("ridge") and Array(hin["ridge"]) == ["beacon"], "Ridge holds the road home for Beacon, and nothing else is a hinge (%s)" % str(hin))
	report.call(w.get_territory("ridge").owner == "red", "working out the hinges leaves the world as it was")
	var th: Dictionary = BoardFacts.threats(w, m, "red")
	report.call(th.has("ridge") and bool(th["ridge"]["danger"]) and str(th["ridge"]["owner"]) == "blue" and int(th["ridge"]["max"]) >= 11 and not th.has("mill"),
		"Ridge (2) faces Varek's Gate (%s) and is marked in danger; Mill, bordered by no enemy, isn't listed" % str(th.get("ridge", {})))
	var sh: Dictionary = BoardFacts.shares(w, m)
	report.call(str(sh["northshore"]["leader"]) == "red" and int(sh["northshore"]["to_go"]) == 0 and str(sh["southshore"]["leader"]) == "blue" and int(sh["southshore"]["to_go"]) == 2,
		"region shares: red holds all the north shore, blue 1 of 3 of the south")
	report.call(BoardFacts.ways_in(m, "northshore") == [["gate", "ridge"]] and BoardFacts.ways_in(m, "southshore").size() == 3, "one way into the north shore (The Gate to Ridge), three into the south")
	var isles: Types.MapDef = Types.MapDef.from_file("res://maps/isles24.json")
	var vane: Array = BoardFacts.ways_in(isles, "vane")
	report.call(vane == [["morrowfen", "vanestrand"], ["reachrock", "vanewick"]], "Great Vane has two ways in: Morrow Fen to Vane Strand, Reach Rock to Vanewick (%s)" % str(vane))
	## a capital is in danger as soon as it could be outnumbered at all
	var w2: Types.World = H.paint(m, {"ridge": ["red", 6], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 5], "harbor": ["blue", 1]})
	(w2.players["red"] as Types.PlayerState).capital = "ridge"
	(w2.players["blue"] as Types.PlayerState).capital = "harbor"
	var t2: Dictionary = BoardFacts.threats(w2, m, "red")
	report.call(bool(t2["ridge"]["capital"]) and bool(t2["ridge"]["danger"]) == (int(t2["ridge"]["max"]) > int(t2["ridge"]["held"])), "the capital's danger mark: could it be outnumbered at all (%s)" % str(t2["ridge"]))


func _moments(report: Callable) -> void:
	## the big moments are found in what the engine reports
	var m := _knife()
	Combat.use_rules(m)
	report.call(Moments.upset(true, 3, 12, true) and not Moments.upset(true, 3, 12, false) and not Moments.upset(true, 12, 3, true) and Moments.upset(true, 12, 3, false),
		"an upset: three taking a land from twelve, or twelve thrown back by three; not the other way round")
	var p: float = Moments.winner_chance(true, 12, 3, true)
	report.call(p > 0.7 and absf(Moments.winner_chance(true, 12, 3, false) - (1.0 - p)) < 0.0001, "the winner's chance is the odds bar's number (%.2f)" % p)
	report.call(Moments.winner_chance(true, 10, 8, true, 1) < Moments.winner_chance(true, 10, 8, true, 0), "a fortress's longer line (eight defenders, six firing) counts against the attacker's odds (%.2f < %.2f)" % [Moments.winner_chance(true, 10, 8, true, 1), Moments.winner_chance(true, 10, 8, true, 0)])
	report.call(Moments.leader({"red": 9, "blue": 7}) == "red" and Moments.leader({"red": 9, "blue": 9}) == "", "the sole leader, or nobody when the top is shared")
	var h := [{"score": {"red": 9, "blue": 7}}, {"score": {"red": 9, "blue": 11}}]
	report.call(Moments.lead_change(h) == {"from": "red", "to": "blue"}, "a lead change: Varek overtakes Dad")
	report.call(Moments.lead_change([{"score": {"red": 9, "blue": 9}}, {"score": {"red": 10, "blue": 9}}]) == {"from": "", "to": "red"}, "a shared lead taken alone is a change")
	report.call(Moments.lead_change([{"score": {"red": 9, "blue": 7}}, {"score": {"red": 12, "blue": 7}}]).is_empty() and Moments.lead_change([h[1]]).is_empty(),
		"no change when the leader holds on, nor after only one round")
	var log := [{"round": 3, "pid": "red", "by": "blue", "land": "mill"}]
	var back: Array = Moments.retaken([{"kind": Types.EVENT_OCCUPIED, "terrId": "mill", "playerId": "red", "armies": 4}, {"kind": Types.EVENT_OCCUPIED, "terrId": "mill", "playerId": "green", "armies": 2}], log)
	report.call(back.size() == 1 and str(back[0]["pid"]) == "red" and int(back[0]["round"]) == 3, "a capital won back by the commander who lost it (and only by them)")


func _wars(report: Callable) -> void:
	## whole AI wars: every column that marched on someone else's land has a fate, and the fate
	## agrees with the world after the round (the map can't say "took it" of a land it lost)
	for mid in ["isles24", "known24", "ring26"]:
		var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.maneuvers = true
		m.dig_cap = 3
		m.rules = 20
		m.fire_line = true
		m.capitals = true
		m.fortune = true
		m.levee = 3
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(m, seats, 61, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var bad: Array = []
		var tally := {}
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 61)
			var after: Types.World = res["world"]
			var gs: Array = LastRound.ghosts(w, after, sheets, res["events"])
			var clashes: int = H.all_of(res["events"], Types.EVENT_CLASH).size()
			var died := {} ## one per column that died: a commander's columns bound for one land march as one
			for g in gs:
				var res_k: String = str(g["result"])
				tally[res_k] = int(tally.get(res_k, 0)) + 1
				var mine_before: bool = w.get_territory(str(g["to"])).owner == str(g["owner"])
				var mine_after: bool = after.get_territory(str(g["to"])).owner == str(g["owner"])
				if str(g["surgeFate"]) == LastRound.CLASH:
					died["surge|%s|%s" % [g["owner"], g["to"]]] = true
				if res_k == LastRound.CLASH:
					died["%s|%s" % [g["owner"], g["to"]]] = true
				elif res_k == "" and not mine_before:
					bad.append("r%d %s->%s no fate" % [k, g["from"], g["to"]])
				elif res_k == LastRound.TOOK and not mine_after:
					bad.append("r%d %s->%s took but lost" % [k, g["from"], g["to"]])
				elif LastRound.FAILED.has(res_k) and mine_after:
					bad.append("r%d %s->%s %s but holds it" % [k, g["from"], g["to"], res_k])
			if died.size() != clashes:
				bad.append("r%d %d clashes, %d columns died on the border" % [k, clashes, died.size()])
			w = after
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		var missed: int = int(tally.get(LastRound.MISSED, 0))
		var failed := 0
		for f in LastRound.FAILED:
			failed += int(tally.get(f, 0))
		report.call(bad.is_empty() and missed * 10 <= maxi(1, failed), "%s: every column's fate agrees with the world, and few are unexplained (%s) %s" % [mid, str(tally), " ".join(bad.slice(0, 4))])


func _session(report: Callable, tree: SceneTree) -> void:
	## the live session: its ghosts carry their fates, and the recruits it shows add up
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/isles24.json", "seed": 7, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"},
		{"id": "green", "name": "Hask", "kind": "ai", "ai": "hask"}]})
	var fated := true
	var sums := true
	var failed := 0
	var checked := 0
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 80:
		guard += 1
		match s.phase:
			Session.Phase.OPENING:
				s.auto_deploy()
				s.lock()
			Session.Phase.PLANNING:
				for g in s.ghosts:
					if not (g as Dictionary).has("result"):
						fated = false
					elif LastRound.FAILED.has(str(g["result"])):
						failed += 1
				var b: Dictionary = s.income_breakdown()
				var parts: int = int(b["lands"]) + int(b["bloc"]) + int(b["regions"]) + int(b["capital"]) + int(b["levee"]) + int(b["cards"])
				checked += 1
				if parts != s.income_total():
					sums = false
					report.call(false, "round %d: the recruits' parts (%s) make %d, not the %d recruits" % [s.world.round, str(b), parts, s.income_total()])
				s.auto_deploy()
				s.lock()
			Session.Phase.MANEUVER:
				s.advise_moves()
				s.lock()
			Session.Phase.CINEMA:
				s.cinema_done()
			Session.Phase.RECAP:
				s.next_round()
			Session.Phase.DRAFT:
				s.ai_claim() if not s.is_human(s.draft_turn()) else s.claim(s.draft_pick_for("red"))
			_:
				break
	report.call(fated and failed > 0, "a live war's ghost arrows carry their fates (%d failed columns seen)" % failed)
	report.call(sums and checked >= 3, "the recruits' breakdown adds up to the recruits, capital and levée included, only supplied lands paying (%d rounds)" % checked)
	s.queue_free()


func _bot_0b2fe07(report: Callable) -> void:
	## the playtest bot's report on 0b2fe07: B-005 (the human seat called You) and B-008 (a merged column)
	report.call(Style.owns("You", true) == "Your" and Style.owns("you") == "your" and Style.owns("Varek") == "Varek's"
		and Style.says(Style.who("You"), "was") == "you were" and Style.who("Grand Marshal Varek") == "Grand Marshal Varek",
		"B-005: the seat called You reads \"Your\", \"your\", \"you were\"; others keep their names")
	var names := func(pid): return {"red": "You", "blue": "Grand Marshal Varek"}.get(pid, pid)
	var hexes := func(h): return {"silvermarch": "Silvermarch", "thethrone": "The Throne", "ivorymarch": "Ivorymarch"}.get(h, h)
	var ghosts := [
		{"from": "silvermarch", "to": "ivorymarch", "strength": 7, "owner": "red", "result": LastRound.TOOK, "by": "", "left": 0, "fellTo": ""},
		{"from": "thethrone", "to": "ivorymarch", "strength": 3, "owner": "red", "result": LastRound.TOOK, "by": "", "left": 0, "fellTo": ""},
		{"from": "gate", "to": "ivorymarch", "strength": 5, "owner": "blue", "result": LastRound.THROWN_BACK, "by": "red", "left": 0, "fellTo": ""},
		{"from": "gate", "to": "elsewhere", "strength": 2, "owner": "red", "result": LastRound.TOOK, "by": "", "left": 0, "fellTo": ""}]
	var lines: Array = LastRound.merged(ghosts, "ivorymarch").map(func(g): return LastRound.said(g, names, hexes))
	report.call(lines == ["Your 10 (from Silvermarch and The Throne) took it.", "Grand Marshal Varek's 5 were thrown back by you."],
		"B-008: one merged column is one sentence, its origins named: %s" % str(lines))

