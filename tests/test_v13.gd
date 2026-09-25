## v1.3 rules: the melee, surges from the captured land, the man/horse/cannon deck,
## and the reinforcement phase's marches.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const Cards := preload("res://engine/cards.gd")
const Maneuver := preload("res://engine/maneuver.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Autoplay := preload("res://engine/autoplay.gd")


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	map.battle = Combat.MODE_VOLLEYS
	_melee(report, map)
	_melee_live(report, map)
	_surge(report, map)
	_cards(report)
	_marches(report, map)
	_wars(report)


func _dogpile(map: Types.MapDef) -> Types.World:
	## red from Ridge and green from Docks both storm blue's Gate
	var w: Types.World = H.paint(map, {
		"ridge": ["red", 7], "beacon": ["red", 2], "mill": ["red", 2],
		"gate": ["blue", 8], "harbor": ["blue", 2],
		"docks": ["green", 7], "quarry": ["green", 2],
	})
	w.round = 2
	return w


func _first(events: Array, kind: String) -> Dictionary:
	for e in events:
		if str(e["kind"]) == kind:
			return e
	return {}


func _conserved(before: Types.World, result: Dictionary) -> bool:
	var evs: Array = result["events"]
	return MapLib.sum_armies(result["world"]) == MapLib.sum_armies(before) + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)


func _view_agrees(before: Types.World, result: Dictionary) -> bool:
	var seen: Types.World = ViewEvents.apply_through(before, result["events"], (result["events"] as Array).size() - 1)
	for t in (result["world"] as Types.World).territories.keys():
		var a: Types.TerritoryState = result["world"].get_territory(t)
		var b: Types.TerritoryState = seen.get_territory(t)
		if a.owner != b.owner or a.armies != b.armies or a.garrison != b.garrison:
			return false
	return true


func _melee(report: Callable, map: Types.MapDef) -> void:
	var holds := 0
	var double_loss := false
	var double_win := false
	var ok := true
	var melees := 0
	var n := 300
	for seed in range(1, n + 1):
		var w := _dogpile(map)
		var red := H.sheet("red", [H.pkt("ridge", "gate", 6)])
		var green := H.sheet("green", [H.pkt("docks", "gate", 6)])
		var r: Dictionary = Resolve.resolve_round(w, map, [red, green], seed)
		var e: Dictionary = _first(r["events"], Types.EVENT_MELEE)
		if e.is_empty():
			ok = false
			continue
		melees += 1
		if (r["world"] as Types.World).get_territory("gate").owner == "blue":
			holds += 1
		for salvo in e["salvos"]:
			var wins := 0
			var losses := 0
			for v in salvo:
				if str(v["w"]) == "a":
					wins += 1
				else:
					losses += 1
			if wins == 2:
				double_loss = true
			if losses == 2:
				double_win = true
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
	report.call(melees == n, "two commanders storming one land fight a single melee (%d/%d)" % [melees, n])
	report.call(double_loss and double_win, "a defender can lose two men in one salvo, or win on both fronts")
	report.call(ok, "melees conserve armies and the replay agrees, every time")
	## the fronts split the defender's weight, so a dogpile hits like one combined attack
	## (tools/melee_sim.py; one-at-a-time in v1.2 let this defender hold ~40%)
	var p: float = float(holds) / n
	var merged: float = 1.0 - Combat.capture_rate(12, 8, Combat.MODE_VOLLEYS)
	report.call(absf(p - merged) < 0.05, "6+6 against 8: the defender holds %.0f%%, like against one attack of 12 (%.0f%%)" % [p * 100.0, merged * 100.0])
	## one invader is still a plain assault
	var w1 := _dogpile(map)
	var r1: Dictionary = Resolve.resolve_round(w1, map, [H.sheet("red", [H.pkt("ridge", "gate", 6)])], 3)
	report.call(_first(r1["events"], Types.EVENT_MELEE).is_empty() and not _first(r1["events"], Types.EVENT_INVASION).is_empty(), "a lone invader fights an ordinary assault")
	## the decisive-roll style keeps the old sequence
	var dmap: Types.MapDef = H.knife7()
	dmap.battle = Combat.MODE_DECISIVE
	var r2: Dictionary = Resolve.resolve_round(_dogpile(dmap), dmap, [H.sheet("red", [H.pkt("ridge", "gate", 6)]), H.sheet("green", [H.pkt("docks", "gate", 6)])], 3)
	report.call(_first(r2["events"], Types.EVENT_MELEE).is_empty(), "decisive battles keep one-at-a-time")


func _melee_live(report: Callable, map: Types.MapDef) -> void:
	## both invaders are watching humans: the round pauses for each of their calls in turn
	var w := _dogpile(map)
	var red := H.sheet("red", [H.pkt("ridge", "gate", 6)])
	var green := H.sheet("green", [H.pkt("docks", "gate", 6)])
	var pauses := 0
	var who := {}
	var r: Dictionary = Resolve.resolve_round(w, map, [red, green], 11, ["red", "green"])
	while r.has("pending") and pauses < 60:
		pauses += 1
		var p: Dictionary = r["pending"]
		who[str(p["attacker"])] = true
		var sh: Types.Sheet = red if str(p["attacker"]) == "red" else green
		var list: Array = sh.calls.get(str(p["key"]), [])
		list.append(Combat.CALL_PRESS)
		sh.calls[str(p["key"])] = list
		r = Resolve.resolve_round(w, map, [red, green], 11, ["red", "green"])
	report.call(pauses > 0 and who.size() == 2, "a melee pauses for each watching invader's call (%d calls)" % pauses)
	var again: Dictionary = Resolve.resolve_round(w, map, [Types.Sheet.from_dict(red.to_dict()), Types.Sheet.from_dict(green.to_dict())], 11)
	report.call(Hash.world_hash(again["world"]) == Hash.world_hash(r["world"]), "the called melee replays from the saved sheets")


func _surge(report: Callable, map: Types.MapDef) -> void:
	## red converges on the Gate from the Docks and the Quarry (both border it), with the
	## surge ordered from the Gate itself
	var ok := 0
	var tried := 0
	for seed in range(1, 60):
		var w: Types.World = H.paint(map, {
			"ridge": ["blue", 2], "beacon": ["blue", 2], "mill": ["blue", 2],
			"gate": ["blue", 3], "harbor": ["red", 2],
			"docks": ["red", 9], "quarry": ["red", 9],
		})
		w.round = 2
		var sh := H.sheet("red", [H.pkt("docks", "gate", 8), H.pkt("quarry", "gate", 8)])
		sh.surges["gate"] = "ridge" ## ordered from the Gate, not from either origin
		var r: Dictionary = Resolve.resolve_round(w, map, [sh], seed)
		var cap: Dictionary = {}
		for e in r["events"]:
			if str(e["kind"]) == Types.EVENT_OCCUPIED and str(e["terrId"]) == "gate":
				cap = e
		if cap.is_empty():
			continue
		tried += 1
		var sg: Dictionary = _first(r["events"], Types.EVENT_SURGE)
		if not sg.is_empty() and str(sg["from"]) == "gate" and int(sg["strength"]) == int(cap["armies"]) - 1:
			ok += 1
	report.call(tried > 0 and ok == tried, "armies converging from two lands surge on together from the land they took (%d/%d)" % [ok, tried])
	## a surge with no attack on its land is refused
	var w2: Types.World = H.paint(map, {"docks": ["red", 5], "gate": ["blue", 2], "ridge": ["blue", 2], "quarry": ["red", 2], "harbor": ["red", 2], "beacon": ["blue", 1], "mill": ["blue", 1]})
	var bad := H.sheet("red", [])
	bad.surges["gate"] = "ridge"
	report.call(not Resolve.resolve_round(w2, map, [bad], 1)["errors"].is_empty(), "a surge from a land nobody attacks is refused")


func _cards(report: Callable) -> void:
	var wilds := 0
	var kinds := {}
	for i in 3000:
		var c: String = Cards.draw(99, i, "red", 24, false)
		kinds[c] = true
		if c == Types.CARD_WILD:
			wilds += 1
	report.call(wilds == 0 and kinds.size() == 3, "the v1.3 deck is men, horses and cannon only")
	var always := true
	var types := [Types.CARD_SUN, Types.CARD_MOON, Types.CARD_STAR]
	for a in 3:
		for b in 3:
			for c in 3:
				for d in 3:
					for e in 3:
						var hand := PackedStringArray([types[a], types[b], types[c], types[d], types[e]])
						if Cards.best_set(hand).size() != 3:
							always = false
	report.call(always, "any five cards hold a set (three alike or one of each)")


func _marches(report: Callable, map: Types.MapDef) -> void:
	var w: Types.World = H.paint(map, {
		"beacon": ["red", 6], "ridge": ["red", 2], "mill": ["red", 3],
		"gate": ["blue", 5], "harbor": ["blue", 2], "docks": ["blue", 2], "quarry": ["blue", 2],
	})
	w.round = 3
	report.call(Maneuver.validate(w, map, "red", [{"from": "beacon", "to": "ridge", "n": 5}]).is_empty(), "Beacon may send 5 of 6 to the Ridge")
	report.call(not Maneuver.validate(w, map, "red", [{"from": "beacon", "to": "ridge", "n": 6}]).is_empty(), "one stays home (no dug-in defender)")
	report.call(not Maneuver.validate(w, map, "red", [{"from": "beacon", "to": "mill", "n": 1}]).is_empty(), "no marching two lands in one go")
	report.call(not Maneuver.validate(w, map, "red", [{"from": "ridge", "to": "gate", "n": 1}]).is_empty(), "no marching into an enemy land")
	var plan: Array = Maneuver.plan(w, map, "red")
	var to_front := false
	for m in plan:
		if str(m["from"]) == "beacon" and str(m["to"]) == "ridge":
			to_front = true
	report.call(to_front and Maneuver.validate(w, map, "red", plan).is_empty(), "the AI marches the quiet Beacon's men up to the Ridge (%s)" % JSON.stringify(plan))
	var before: int = MapLib.sum_armies(w)
	var evs: Array = Maneuver.apply(w, map, {"red": plan})
	report.call(MapLib.sum_armies(w) == before and not evs.is_empty(), "marches move men, never make or lose them")


func _wars(report: Callable) -> void:
	for mid in ["known24", "world30"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		map.battle = Combat.MODE_VOLLEYS
		map.maneuvers = true
		map.wild_cards = false
		var seats := [{"id": "red", "name": "a", "ai": "ysolde"}, {"id": "blue", "name": "b", "ai": "hask"},
			{"id": "green", "name": "c", "ai": "varek"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(map, seats, 5)
		var melees := 0
		for rd in r["rounds"]:
			melees += int(rd.get("melees", 0))
		report.call(r["ok"] and str(r["winner"]) != "", "%s under v1.3 rules: legal, conserved, finished (%s)" % [mid, " ".join(r["violations"])])
		## replay the record, marches included, and check the battle replay every round
		var w: Types.World = Types.World.from_dict(r["setup"])
		var view_ok := true
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for d in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(d))
			var res: Dictionary = Resolve.resolve_round(w, map, sheets, 5)
			if not _view_agrees(w, res):
				view_ok = false
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				Maneuver.apply(w, map, r["maneuvers"][k])
		report.call(view_ok and Hash.world_hash(w) == Hash.world_hash(r["world"]), "%s: the record (with marches) replays to the same world; %d melees" % [mid, melees])
