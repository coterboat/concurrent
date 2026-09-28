## v1.10 (rules 19): Fortune in every fight. Clashes, fights for the spoils, melees and
## free-for-alls all count toward the next favour, and a favour can be spent in a melee by
## anyone in it (the defender, or the commander of any front): that exchange is thrown again
## for everyone.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const MapLib := preload("res://engine/map.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Session := preload("res://game/core/session.gd")
const Fortune := preload("res://engine/fortune.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_scramble_odds(report)
	_every_fight_counts(report)
	_melee_defender_live(report)
	_melee_attacker_live(report)
	_melee_ai(report)
	_old_rules(report)
	_second_wave(report)
	_wars(report)
	_session(report, tree)
	Combat.use_rules(null)


func _map(rules: int = 19) -> Types.MapDef:
	var m: Types.MapDef = H.knife7()
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.maneuvers = true
	m.dig_cap = 3
	m.rules = rules
	m.fire_line = true
	m.wild_cards = false
	m.fortune = true
	return m


func _conserved(before: Types.World, result: Dictionary) -> bool:
	var evs: Array = result["events"]
	return MapLib.sum_armies(result["world"]) == MapLib.sum_armies(before) + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)


func _view_agrees(before: Types.World, result: Dictionary) -> bool:
	var seen: Types.World = ViewEvents.apply_through(before, result["events"], (result["events"] as Array).size() - 1)
	var real: Types.World = result["world"]
	for t in real.territories.keys():
		var a: Types.TerritoryState = real.get_territory(t)
		var b: Types.TerritoryState = seen.get_territory(t)
		if a.owner != b.owner or a.armies != b.armies:
			return false
	for pid in real.players.keys():
		if real.players[pid].fortune != seen.players[pid].fortune:
			return false
	return true


## a melee at the gate: red from the ridge and green from the docks storm blue's gate
func _melee_world(m: Types.MapDef, blue_n: int = 12) -> Types.World:
	var w: Types.World = H.paint(m, {"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1],
		"docks": ["green", 12], "quarry": ["green", 1], "gate": ["blue", blue_n], "harbor": ["blue", 2]})
	w.round = 2
	w.get_territory("ridge").garrison = 1
	w.get_territory("docks").garrison = 1
	w.get_territory("gate").garrison = 1
	for pid in ["red", "green", "blue"]:
		w.players[pid].fortune = 2
	return w


func _melee_sheets() -> Array:
	return [H.sheet("red", [H.pkt("ridge", "gate", 11)]), H.sheet("green", [H.pkt("docks", "gate", 11)]), H.sheet("blue")]


func _scramble_odds(report: Callable) -> void:
	Combat.use_rules(_map())
	var even: Array = Combat.scramble_odds([8, 8, 8])
	var big: Array = Combat.scramble_odds([20, 5, 5])
	var sum := 0.0
	for v in big:
		sum += float(v)
	report.call(absf(float(even[0]) - 1.0 / 3.0) < 0.12 and absf(float(even[2]) - 1.0 / 3.0) < 0.12 and float(big[0]) > 0.8 and absf(sum - 1.0) < 0.001,
		"a free-for-all's odds: even armies about a third each (%s), the big one a heavy favourite (%.2f)" % [str(even), float(big[0])])
	report.call(Combat.scramble_odds([8, 8, 8]) == even, "and the same fight always quotes the same odds")


func _every_fight_counts(report: Callable) -> void:
	var m := _map()
	Combat.use_rules(m)
	## a clash lost at 80% owes the loser most of a battle
	var p: float = Fortune.clash_rate(14, 6, m.battle)
	var clash := {"kind": Types.EVENT_CLASH, "playerA": "red", "playerB": "blue", "sizeA": 14, "sizeB": 6, "winnerId": "blue", "winnerRemaining": 2, "rolls": [{"sa": 14}]}
	var fl: Dictionary = Fortune.fight_luck(clash, m.battle)
	report.call(int(fl["red"]) == int(round(-100.0 * p)) and int(fl["blue"]) == -int(fl["red"]), "a clash is weighed like any battle: red was %.0f%% to win it (%d)" % [p * 100.0, int(fl["red"])])
	var w: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	w.players["red"].fortune = 0
	Fortune.upkeep(w, w, m, [clash])
	var w18: Types.World = H.paint(_map(18), {"ridge": ["red", 3], "gate": ["blue", 3]})
	w18.players["red"].fortune = 0
	Fortune.upkeep(w18, w18, _map(18), [clash])
	report.call(w.players["red"].fortune == 1 and w18.players["red"].fortune == 0, "and under rules 19 a clash lost against the odds owes a favour (rules 18 ignored clashes)")
	## melees and free-for-alls carry every commander's swing, and it balances out
	var n := 0
	var bal := true
	var scr := 0
	for sd in range(1, 60):
		var mw: Types.World = _melee_world(m)
		var r: Dictionary = Resolve.resolve_round(mw, m, _melee_sheets(), sd)
		for e in r["events"]:
			if str(e.get("kind", "")) in [Types.EVENT_MELEE, Types.EVENT_SCRAMBLE]:
				if not (e as Dictionary).has("luck"):
					bal = false
					continue
				var tot := 0
				for v in (e["luck"] as Dictionary).values():
					tot += int(v)
				if absi(tot) > 3:
					bal = false
				if str(e["kind"]) == Types.EVENT_SCRAMBLE:
					scr += 1
				else:
					n += 1
	report.call(n > 50 and scr > 5 and bal, "every melee (%d) and free-for-all (%d) carries each commander's luck, and it sums to nothing" % [n, scr])


func _find_melee_pending(m: Types.MapDef, want_side: String, live: Array) -> Dictionary:
	for sd in range(1, 400):
		var w: Types.World = _melee_world(m, 14)
		var sheets: Array = _melee_sheets()
		var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd, live)
		if r.has("pending") and bool(r["pending"].get("fortune", false)) and str(r["pending"]["side"]) == want_side and bool(r["pending"].get("melee", false)):
			return {"seed": sd, "w": w, "sheets": sheets, "pending": r["pending"]}
	return {}


func _finish(w: Types.World, m: Types.MapDef, sheets: Array, sd: int, live: Array, first: Array) -> Dictionary:
	## answer the first pause with `first`, every later one by standing and pressing on
	var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd, live)
	var k := 0
	while r.has("pending") and k < 60:
		var pk: Dictionary = r["pending"]
		var chooser: String = str(pk.get("chooser", pk["attacker"]))
		var sh: Types.Sheet = null
		for s in sheets:
			if (s as Types.Sheet).player_id == chooser:
				sh = s
		var lst: Array = sh.calls.get(str(pk["key"]), [])
		if k == 0:
			lst.append_array(first)
		elif bool(pk.get("fortune", false)):
			lst.append(Combat.CALL_STAND)
			if str(pk.get("side", "")) == "a" and not bool(pk.get("ended", false)):
				lst.append(Combat.CALL_PRESS)
		else:
			lst.append(Combat.CALL_PRESS)
		sh.calls[str(pk["key"])] = lst
		r = Resolve.resolve_round(w, m, sheets, sd, live)
		k += 1
	return r


func _melee_defender_live(report: Callable) -> void:
	var m := _map()
	Combat.use_rules(m)
	var f: Dictionary = _find_melee_pending(m, "d", ["blue"])
	report.call(not f.is_empty() and str(f["pending"]["chooser"]) == "blue" and str(f["pending"]["key"]).begins_with("melee|"),
		"a watching defender in a melee is offered Fortune after a bad exchange (seed %s)" % str(f.get("seed", -1)))
	if f.is_empty():
		return
	var w: Types.World = f["w"]
	var sheets: Array = f["sheets"]
	var r: Dictionary = _finish(w, m, sheets, int(f["seed"]), ["blue"], [Combat.CALL_FORTUNE])
	var mel: Dictionary = H.first(r["events"], Types.EVENT_MELEE)
	var dc: Array = mel.get("defCalls", [])
	report.call(dc.size() == 1 and str(dc[0]["by"]) == "blue" and int(dc[0]["d"]) == int(f["pending"]["d0"]) and r["world"].players["blue"].fortune == 1,
		"the favour is spent and the whole exchange thrown again for everyone (%s)" % str(dc))
	var again: Dictionary = Resolve.resolve_round(w, m, sheets, int(f["seed"]))
	report.call(not again.has("pending") and Hash.world_hash(again["world"]) == Hash.world_hash(r["world"]) and _conserved(w, r) and _view_agrees(w, r),
		"it replays exactly from the recorded calls; conserved; the report's count of favours agrees")


func _melee_attacker_live(report: Callable) -> void:
	var m := _map()
	Combat.use_rules(m)
	var f: Dictionary = _find_melee_pending(m, "a", ["red"])
	report.call(not f.is_empty() and str(f["pending"]["chooser"]) == "red" and int(f["pending"]["front"]) >= 0,
		"a watching attacker on one front of a melee is offered Fortune when their front's exchange goes badly (seed %s)" % str(f.get("seed", -1)))
	if f.is_empty():
		return
	var w: Types.World = f["w"]
	var sheets: Array = f["sheets"]
	var r: Dictionary = _finish(w, m, sheets, int(f["seed"]), ["red"], [Combat.CALL_FORTUNE])
	var mel: Dictionary = H.first(r["events"], Types.EVENT_MELEE)
	var spent := 0
	for fr in mel.get("fronts", []):
		for c in fr.get("calls", []):
			if str(c.get("call", "")) == Combat.CALL_FORTUNE and str(c.get("by", "")) == "red":
				spent += 1
	var again: Dictionary = Resolve.resolve_round(w, m, sheets, int(f["seed"]))
	report.call(spent == 1 and Hash.world_hash(again["world"]) == Hash.world_hash(r["world"]) and _conserved(w, r) and _view_agrees(w, r),
		"spent on red's front, replayed exactly, conserved, the report agrees")


func _melee_ai(report: Callable) -> void:
	var m := _map()
	Combat.use_rules(m)
	var spent := 0
	var twice := false
	var ok := true
	for sd in range(1, 140):
		var w: Types.World = _melee_world(m)
		var sheets: Array = _melee_sheets()
		for s in sheets:
			(s as Types.Sheet).fortune_auto = true
		var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd)
		for e in H.all_of(r["events"], Types.EVENT_MELEE):
			var seen := {}
			var calls: Array = (e.get("defCalls", []) as Array).duplicate()
			for fr in e.get("fronts", []):
				calls.append_array(fr.get("calls", []))
			for c in calls:
				if str(c.get("call", "")) == Combat.CALL_FORTUNE:
					spent += 1
					if seen.has(str(c["by"])):
						twice = true
					seen[str(c["by"])] = true
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
	report.call(spent > 10 and not twice and ok, "AI commanders call on Fortune in melees (%d times in 139), never twice in one battle; conserved, the report agrees" % spent)
	## and nobody's favours are spent behind their back
	var none := 0
	for sd in range(1, 60):
		var w2: Types.World = _melee_world(m)
		var r2: Dictionary = Resolve.resolve_round(w2, m, _melee_sheets(), sd)
		for e in H.all_of(r2["events"], Types.EVENT_MELEE):
			none += (e.get("defCalls", []) as Array).size()
			for fr in e.get("fronts", []):
				for c in fr.get("calls", []):
					if str(c.get("call", "")) == Combat.CALL_FORTUNE:
						none += 1
	report.call(none == 0, "without a watching commander or AI doctrine, no favour is ever spent (%d)" % none)


func _old_rules(report: Callable) -> void:
	var m := _map(18)
	Combat.use_rules(m)
	var clean := true
	for sd in range(1, 30):
		var w: Types.World = _melee_world(m)
		var sheets: Array = _melee_sheets()
		for s in sheets:
			(s as Types.Sheet).fortune_auto = true
		var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd)
		for e in r["events"]:
			if str(e.get("kind", "")) in [Types.EVENT_MELEE, Types.EVENT_SCRAMBLE] and ((e as Dictionary).has("luck") or (e as Dictionary).has("defCalls")):
				clean = false
	report.call(clean, "rules 18 games replay their melees as they were: no Fortune, no swing on the record")


func _second_wave(report: Callable) -> void:
	## red storms the harbor from the docks, and surges on into it from the gate: if the first
	## wave takes the harbor, the second marches in (rules 19); before, it stayed put
	var joined := 0
	var stayed := 0
	var ok := true
	for rules in [19, 18]:
		var m := _map(rules)
		m.fortune = false
		Combat.use_rules(m)
		for sd in range(1, 40):
			var w: Types.World = H.paint(m, {"ridge": ["red", 16], "docks": ["red", 16], "beacon": ["red", 1], "mill": ["red", 1],
				"gate": ["blue", 1], "harbor": ["blue", 2], "quarry": ["blue", 1]})
			w.round = 2
			var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 15, "harbor"), H.pkt("docks", "harbor", 15)]), H.sheet("blue")], sd)
			var nw: Types.World = r["world"]
			if nw.get_territory("gate").owner != "red" or nw.get_territory("harbor").owner != "red":
				continue
			var sev: Dictionary = H.first(r["events"], Types.EVENT_SURGE)
			if rules == 19:
				if sev.is_empty() or not bool(sev.get("joins", false)) or nw.get_territory("gate").armies != 1:
					ok = false
				else:
					joined += 1
			else:
				if not sev.is_empty():
					ok = false
				else:
					stayed += 1
			if not _conserved(w, r) or not _view_agrees(w, r):
				ok = false
	report.call(ok and joined > 20 and stayed > 20, "a second wave whose land the first already took marches in to hold it (%d); rules 18 games keep it where it broke through (%d)" % [joined, stayed])


func _wars(report: Callable) -> void:
	for mid in ["known24", "world30"]:
		var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.maneuvers = true
		m.dig_cap = 3
		m.rules = 19
		m.fire_line = true
		m.capitals = true
		m.fortune = true
		m.levee = 3
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}, {"id": "purple", "name": "e", "ai": "recruit"}]
		var r: Dictionary = Autoplay.play(m, seats, 44, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var melee_f := 0
		var gained := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 44)
			if not _view_agrees(w, res) or not _conserved(w, res):
				ok = false
			gained += H.all_of(res["events"], Types.EVENT_FORTUNE).size()
			for e in H.all_of(res["events"], Types.EVENT_MELEE):
				melee_f += (e.get("defCalls", []) as Array).size()
				for fr in e.get("fronts", []):
					for c in fr.get("calls", []):
						if str(c.get("call", "")) == Combat.CALL_FORTUNE:
							melee_f += 1
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s under rules 19, five commanders: legal, replays, conserved, the report agrees (%d favours paid, %d spent in melees) %s" % [mid, gained, melee_f, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/known24.json", "seed": 5, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules >= 19, "a new game plays rules 19 or later (%d)" % s.map.rules)
	s.queue_free()
