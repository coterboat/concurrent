## v2.3, the handoff pass (no rule change: rules 22). The words a first-time player reads, said right
## for the seat called You ("You seiz Varek's war chest", "You is owed for it", "You raise … and
## carries off"); and a storm from two lands priced as the two fronts it is (rules 21) wherever the
## game quotes odds: the order card, the dispatch, the advisor's plan and the AI's own planning.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const AI := preload("res://engine/ai.gd")
const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")
const Rng := preload("res://engine/rng.gd")
const MapLib := preload("res://engine/map.gd")
const Setup := preload("res://engine/setup.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_grammar(report)
	_fronts_priced(report)
	_ai_split(report)
	_session(report, tree)
	Combat.use_rules(null)


func _grammar(report: Callable) -> void:
	var want := {"seizes": "seize", "carries": "carry", "goes": "go", "buzzes": "buzz", "takes": "take", "marches": "march",
		"is": "are", "has": "have", "storms": "storm", "wins": "win", "raises": "raise", "surges": "surge", "loses": "lose"}
	var bad: Array = []
	for v in want.keys():
		if Style.verb_for("You", str(v)) != str(want[v]):
			bad.append("%s→%s" % [v, Style.verb_for("You", str(v))])
		if Style.verb_for("Varek", str(v)) != str(v):
			bad.append("Varek %s" % v)
	report.call(bad.is_empty(), "the seat called You takes the plain verb, every other seat the one given (wrong: %s)" % str(bad))
	report.call(Style.says("You", "seizes") + " Varek's war chest" == "You seize Varek's war chest", "\"You seize Varek's war chest\" (it read \"You seiz\")")
	report.call(Style.says("you", "is") == "you are" and Style.says("Dad", "is") == "Dad is", "\"you are owed for it\", \"Dad is owed for it\"")


func _map(rules: int) -> Types.MapDef:
	var m: Types.MapDef = H.knife7()
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.dig_cap = 3
	m.rules = rules
	m.fire_line = true
	m.wild_cards = false
	m.fortune = false
	return m


func _fronts_priced(report: Callable) -> void:
	var m: Types.MapDef = _map(22)
	Combat.use_rules(m)
	report.call(is_equal_approx(Combat.fronts_capture_rate([11], 9), Combat.capture_rate(11, 9, Combat.MODE_VOLLEYS)), "one front is priced as it always was")
	var split: float = Combat.fronts_capture_rate([6, 5], 9)
	var one: float = Combat.capture_rate(11, 9, Combat.MODE_VOLLEYS)
	report.call(split < one - 0.08, "11 against 9 from two lands (6 and 5) is worth less than 11 from one (%.2f against %.2f)" % [split, one])
	## the price against the battles themselves: The Gate stormed from Ridge (6) and Harbor (5)
	var won := 0
	var n := 300
	for sd in range(1, n + 1):
		var w: Types.World = H.paint(m, {"ridge": ["red", 7], "harbor": ["red", 6], "gate": ["blue", 9],
			"beacon": ["blue", 1], "mill": ["blue", 1], "docks": ["blue", 1], "quarry": ["blue", 1]})
		var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 6), H.pkt("harbor", "gate", 5)]), H.sheet("blue")], sd * 7919)
		if (res["world"] as Types.World).get_territory("gate").owner == "red":
			won += 1
	var real: float = float(won) / n
	report.call(absf(real - split) < 0.07, "the price matches the battles: %d of %d taken (%.2f), priced %.2f" % [won, n, real, split])
	var lo: float = Combat.fronts_capture_rate([4, 4, 3], 9)
	report.call(lo < Combat.fronts_capture_rate([8, 3], 9) + 0.001 and lo < Combat.capture_rate(11, 9, Combat.MODE_VOLLEYS), "three fronts are priced no better than two")
	## RV-006 F1: three fronts priced exactly. Three 1-man columns against 2: each wins 15/36, loses
	## 21/36, so P = P(2+ win) + P(exactly 1) / 2 = 0.589 (folding two of them into one priced 0.658)
	var tri: float = Combat.fronts_capture_rate([1, 1, 1], 2)
	report.call(absf(tri - 0.5888) < 0.002, "three lone men against two: %.3f, the exact 0.589" % tri)
	## and against the battles: The Gate stormed from Ridge, Harbor and Docks at once
	var won3 := 0
	for sd in range(1, n + 1):
		var w3: Types.World = H.paint(m, {"ridge": ["red", 5], "harbor": ["red", 4], "docks": ["red", 4], "gate": ["blue", 7],
			"beacon": ["blue", 1], "mill": ["blue", 1], "quarry": ["blue", 1]})
		var res3: Dictionary = Resolve.resolve_round(w3, m, [H.sheet("red", [H.pkt("ridge", "gate", 4), H.pkt("harbor", "gate", 3), H.pkt("docks", "gate", 3)]), H.sheet("blue")], sd * 7919)
		if (res3["world"] as Types.World).get_territory("gate").owner == "red":
			won3 += 1
	var p3: float = Combat.fronts_capture_rate([4, 3, 3], 7)
	report.call(absf(float(won3) / n - p3) < 0.07, "three fronts against the battles: 4 + 3 + 3 at a Gate of 7, %d of %d taken (%.2f), priced %.2f" % [won3, n, float(won3) / n, p3])
	m.fire_line = false
	Combat.use_rules(m)
	report.call(is_equal_approx(Combat.fronts_capture_rate([6, 5], 9), Combat.capture_rate(11, 9, Combat.MODE_VOLLEYS)), "without the firing line the old sum (the defenders split themselves there)")
	m.fire_line = true
	Combat.use_rules(m)


func _ai_split(report: Callable) -> void:
	## The Gate (6) is red's (the AI's) one real target, and Ridge and Harbor both border it. Before rules 21
	## two columns were one force, and the AI split freely; since, they are two fronts, and a split
	## it sends has to be worth sending as two fronts.
	var priced := true
	var splits := {20: 0, 22: 0}
	var sent := {20: 0, 22: 0}
	var worst := 1.0
	for rules in [22, 20]:
		var m: Types.MapDef = _map(rules)
		for sd in range(1, 41):
			var w: Types.World = H.paint(m, {"ridge": ["red", 8], "harbor": ["red", 7], "beacon": ["red", 2], "mill": ["red", 2],
				"docks": ["red", 2], "gate": ["blue", 6], "quarry": ["blue", 1]})
			var prof: Dictionary = AI.profile_for("general")
			prof["search"] = false
			var sheet: Types.Sheet = AI.plan(w, m, "red", Rng.derive_stream(sd, 1, "red"), prof)
			var by_from := {}
			for raw in sheet.packets:
				var pk: Types.Packet = raw
				if pk.to_id == "gate":
					by_from[pk.from_id] = int(by_from.get(pk.from_id, 0)) + pk.strength
			if by_from.size() > 1:
				splits[rules] = int(splits[rules]) + 1
				for v in by_from.values():
					sent[rules] = int(sent[rules]) + int(v)
				if rules == 22:
					Combat.use_rules(m)
					var p_split: float = Combat.fronts_capture_rate(by_from.values(), 6)
					worst = minf(worst, p_split)
					## at least the odds it plans for (the hard commanders' nerve included), give or take its noise
					if p_split < float(prof["p_win"]) - 0.07 - 0.1:
						priced = false
	report.call(int(splits[20]) > 0, "the temptation is real: under rules 20 the AI splits on The Gate (%d of 40 seeds)" % int(splits[20]))
	report.call(priced and int(splits[22]) > 0, "rules 22: every attack the AI sends from two lands is one worth sending as two fronts (%d of 40 split; the worst %.2f)" % [int(splits[22]), worst])
	report.call(int(splits[22]) > 0 and float(sent[22]) / int(splits[22]) > float(sent[20]) / maxi(1, int(splits[20])), "knowing a split costs, it brings more men to one: %.1f a split attack under rules 22, %.1f under 20" % [float(sent[22]) / maxi(1, int(splits[22])), float(sent[20]) / maxi(1, int(splits[20]))])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 5, "length": "short", "deal": "random", "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules >= 22, "a new game plays rules 22 or later (%d): nothing in this pass changed an outcome" % s.map.rules)
	## the Isthmus deals the north shore 15 to place on three lands that hold 4, 6 and 4
	var room := 0
	for t in MapLib.player_territory_ids(s.world, s.planner):
		room += s.place_cap(t)
	var pool: int = Setup.pool_for(s.map, 2) - 3
	report.call(s.phase == Session.Phase.OPENING and s.income_total() == mini(pool, room) and room < pool,
		"deployment on the Isthmus offers what the lands can take: %d (the pool's %d could never all be placed)" % [s.income_total(), pool])
	s.auto_deploy()
	var full := true
	for t in MapLib.player_territory_ids(s.world, s.planner):
		full = full and s.placed_on(t) == s.place_cap(t)
	report.call(s.income_left() == 0 and full, "every land filled to its cap and nothing left over, so SEAL asks no question about a man who could never be placed")
	s.lock()
	s.lock()
	s.cinema_done()
	## stage The Gate stormed from Ridge and Harbor in the planner's own sheet
	var w: Types.World = s.world
	w.set_hex("ridge", "red", 7)
	w.set_hex("harbor", "red", 6)
	w.set_hex("gate", "blue", 9)
	var sh: Types.Sheet = s.sheet()
	sh.packets = [H.pkt("ridge", "gate", 6), H.pkt("harbor", "gate", 5)]
	var o: Dictionary = s.odds_into("gate", 9)
	var one: Dictionary = s.odds(11, 9, "gate")
	report.call(int(o["total"]) == 11 and int(o["fronts"]) == 2 and float(o["p"]) < float(one["p"]) - 0.08,
		"the order card's odds for 6 from Ridge and 5 from Harbor are the two fronts' (%.2f), not 11 as one (%.2f)" % [float(o["p"]), float(one["p"])])
	s.map.rules = 20
	var o20: Dictionary = s.odds_into("gate", 9)
	report.call(is_equal_approx(float(o20["p"]), float(one["p"])), "an old game's (rules 20) columns merge, and its odds are one force's")
	s.map.rules = 22
	## three lone lands (none borders another of yours) take one recruit each
	report.call(s.phase == Session.Phase.PLANNING and s.plan_step == "reinforce", "round 1 opens on the reinforcement phase (phase %d, %s)" % [s.phase, s.plan_step])
	sh.packets = []
	for t in ["beacon", "mill", "docks", "gate"]:
		w.set_hex(t, "blue", 2)
	for t in ["ridge", "harbor", "quarry"]:
		w.set_hex(t, "red", 2)
	(w.players["red"] as Types.PlayerState).capital = "ridge"
	s.clear_placements()
	var lone := 0
	for t in ["ridge", "harbor", "quarry"]:
		lone += s.place_cap(t)
	report.call(s.income_left() > lone and s.placeable_left() == lone and s.no_room() == s.income_left() - lone,
		"three lone lands: %d recruits, %d can be placed, %d have no room" % [s.income_left(), s.placeable_left(), s.no_room()])
	s.auto_deploy()
	report.call(s.placeable_left() == 0 and s.no_room() > 0, "placed for him, nothing is left that could go anywhere (so nothing asks): %d have no room" % s.no_room())
	var nags: Array = Array(s.warnings()).filter(func(t): return str(t).contains("not placed yet"))
	report.call(nags.is_empty(), "and the dispatch's warnings don't call them unplaced (RV-006): %s" % str(nags))
	s.queue_free()
