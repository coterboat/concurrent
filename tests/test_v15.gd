## v1.5 rules: surges that meet head-on clash, surges carry a count, dig-in reaches three,
## the man who stays home is shown with the garrison (and the literal "he digs in for good"
## switch still works), and planning comes in two steps.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const Setup := preload("res://engine/setup.gd")
const Validate := preload("res://engine/validate.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Income := preload("res://engine/income.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Session := preload("res://game/core/session.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_surge_clash(report)
	_surge_count(report)
	_dig_in(report)
	_wars(report)
	_plan_steps(report, tree)


func _map(rules: int) -> Types.MapDef:
	var map: Types.MapDef = H.knife7()
	map.battle = Combat.MODE_VOLLEYS
	map.scramble = true
	map.maneuvers = true
	map.dig_cap = 3 if rules >= 15 else 2
	map.rules = rules
	return map


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


func _race(map: Types.MapDef) -> Array:
	## red walks into the empty Gate and surges on to the Docks; blue walks into the empty
	## Docks and surges on to the Gate: the two surges run straight at each other
	var w: Types.World = H.paint(map, {"ridge": ["red", 10], "beacon": ["red", 1], "mill": ["red", 1],
		"harbor": ["blue", 10], "quarry": ["blue", 1]})
	w.round = 2
	for t in ["ridge", "harbor"]:
		w.get_territory(t).garrison = 1
	var red := H.sheet("red", [H.pkt("ridge", "gate", 10, "docks")])
	red.surges["gate"] = "docks"
	var blue := H.sheet("blue", [H.pkt("harbor", "docks", 10, "gate")])
	blue.surges["docks"] = "gate"
	return [w, red, blue]


func _surge_clash(report: Callable) -> void:
	var clashes := 0
	var ok := true
	for seed in range(1, 41):
		var map := _map(15)
		var r0: Array = _race(map)
		var res: Dictionary = Resolve.resolve_round(r0[0], map, [r0[1], r0[2]], seed)
		var evs: Array = res["events"]
		var first_surge: int = H.index_of_kind(evs, Types.EVENT_SURGE)
		var clash_i := -1
		for k in evs.size():
			if str(evs[k]["kind"]) == Types.EVENT_CLASH and k > first_surge:
				clash_i = k
		if first_surge >= 0 and clash_i > first_surge:
			clashes += 1
		if not res["errors"].is_empty() or not _conserved(r0[0], res) or not _view_agrees(r0[0], res):
			ok = false
	report.call(clashes == 40 and ok, "two surges running at each other's lands meet in a border clash (%d/40); conserved, the view agrees" % clashes)
	## old games let them pass each other in the night
	var map0 := _map(0)
	var r1: Array = _race(map0)
	var res0: Dictionary = Resolve.resolve_round(r1[0], map0, [r1[1], r1[2]], 3)
	var late_clash := false
	var seen_surge := false
	for e in res0["events"]:
		if str(e["kind"]) == Types.EVENT_SURGE:
			seen_surge = true
		elif seen_surge and str(e["kind"]) == Types.EVENT_CLASH:
			late_clash = true
	report.call(seen_surge and not late_clash, "saves from before v1.5 keep the old surges")


func _surge_count(report: Callable) -> void:
	var map := _map(15)
	var w: Types.World = H.paint(map, {"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1], "docks": ["blue", 2], "harbor": ["blue", 1], "quarry": ["blue", 1]})
	w.round = 2
	w.get_territory("ridge").garrison = 1
	var red := H.sheet("red", [H.pkt("ridge", "gate", 12, "docks")])
	red.surges["gate"] = "docks"
	red.surge_n["gate"] = 3
	var res: Dictionary = Resolve.resolve_round(w, map, [red, H.sheet("blue")], 5)
	var e: Dictionary = H.first(res["events"], Types.EVENT_SURGE)
	report.call(not e.is_empty() and int(e["strength"]) == 3 and int(e["originRemaining"]) == 9, "a surge ordered with 3 pushes on with 3; the rest hold the Gate (%s)" % str(e.get("strength", "none")))
	var bad := H.sheet("red", [H.pkt("ridge", "gate", 5)])
	bad.surge_n["gate"] = 2
	report.call(not Validate.validate_sheet(w, map, bad).is_empty(), "a surge count without a surge is refused")
	var round_trip := Types.Sheet.from_dict(red.to_dict())
	report.call(int(round_trip.surge_n.get("gate", 0)) == 3, "the surge count is saved with the sheet")


func _dig_in(report: Callable) -> void:
	## the display: the big number is who can march, the shield who stays home
	var m0 := _map(15)
	var ws: Types.World = H.paint(m0, {"ridge": ["red", 5], "gate": ["blue", 4], "docks": ["neutral", 5]})
	ws.get_territory("gate").garrison = 2
	var a: Array = Income.home_split(ws.get_territory("ridge"))
	var b: Array = Income.home_split(ws.get_territory("gate"))
	var c: Array = Income.home_split(ws.get_territory("docks"))
	report.call(a == [4, 1] and b == [4, 2] and c == [5, 0] and int(a[0]) == Income.max_send(ws.get_territory("ridge")), "the shield shows who stays home (%s %s %s)" % [str(a), str(b), str(c)])
	## the literal switch: the man left behind digs in for good
	var map := _map(15)
	map.first_digs_in = true
	## the man who stays behind digs in when the others march
	var w: Types.World = H.paint(map, {"ridge": ["red", 6], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 3], "harbor": ["blue", 1]})
	w.round = 2
	var res: Dictionary = Resolve.resolve_round(w, map, [H.sheet("red", [H.pkt("ridge", "gate", 5)]), H.sheet("blue")], 7)
	var ridge: Types.TerritoryState = (res["world"] as Types.World).get_territory("ridge")
	report.call(ridge.garrison >= 1 and ridge.armies == 0 and _conserved(w, res) and _view_agrees(w, res), "the man left behind digs in (Ridge: %d dug in, %d army)" % [ridge.garrison, ridge.armies])
	## a fresh conquest digs in its first soldier at the end of the round (no free man)
	var w2: Types.World = H.paint(map, {"ridge": ["red", 8], "beacon": ["red", 1], "mill": ["red", 1], "harbor": ["blue", 2]})
	w2.round = 2
	w2.get_territory("ridge").garrison = 1
	var res2: Dictionary = Resolve.resolve_round(w2, map, [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("blue")], 7)
	var gate: Types.TerritoryState = (res2["world"] as Types.World).get_territory("gate")
	report.call(gate.owner == "red" and gate.garrison == 1 and gate.armies == 7 and _conserved(w2, res2) and _view_agrees(w2, res2), "a fresh conquest digs in its first soldier (Gate: %d dug in + %d)" % [gate.garrison, gate.armies])
	## dig-in reaches three, never more
	var w3: Types.World = H.paint(map, {"beacon": ["red", 3], "ridge": ["red", 3], "mill": ["red", 3], "gate": ["red", 3]})
	var cap: int = Income.garrison_cap(w3, map, "ridge")
	report.call(cap == 3, "dig-in reaches three on a well-supported land (cap %d)" % cap)
	## deployment digs in the first soldier on every land
	var dealt: Types.World = Setup.deal(map, [{"id": "red", "name": "a"}, {"id": "blue", "name": "b"}], 4)
	Setup.apply_opening(dealt, map, {})
	var all_dug := true
	for t in dealt.territories.keys():
		var ts: Types.TerritoryState = dealt.get_territory(t)
		if ts.owner != Types.UNOCCUPIED and ts.owner != "neutral" and ts.garrison < 1:
			all_dug = false
	report.call(all_dug, "every land starts the war with its first soldier dug in")


func _wars(report: Callable) -> void:
	for mid in ["known24", "world30"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		map.battle = Combat.MODE_VOLLEYS
		map.maneuvers = true
		map.wild_cards = false
		map.scramble = true
		map.dig_cap = 3
		map.rules = 15
		map.first_digs_in = mid == "world30" ## the literal switch gets a whole war too
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "hask"},
			{"id": "green", "name": "c", "ai": "varek"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(map, seats, 15)
		var deepest := 0
		var bare := 0
		for t in (r["world"] as Types.World).territories.keys():
			var ts: Types.TerritoryState = (r["world"] as Types.World).get_territory(t)
			deepest = maxi(deepest, ts.garrison)
			if map.first_digs_in and ts.owner != Types.UNOCCUPIED and ts.owner != "neutral" and ts.garrison < 1:
				bare += 1
		report.call(r["ok"] and str(r["winner"]) != "" and deepest <= 3 and bare == 0, "%s under v1.5 rules%s: legal, finished, nobody dug in past three (%s)" % [mid, " (first man digs in)" if map.first_digs_in else "", " ".join(r["violations"])])


func _plan_steps(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/known24.json", "seed": 8, "length": "short", "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Mum", "kind": "human", "ai": ""},
		{"id": "green", "name": "Quill", "kind": "ai", "ai": "quill"}]})
	s.auto_deploy()
	s.lock()
	s.auto_deploy()
	s.lock()
	var guard := 0
	while s.phase == Session.Phase.CINEMA and guard < 5:
		guard += 1
		s.cinema_done()
	report.call(s.phase == Session.Phase.PLANNING and s.plan_step == "reinforce", "a round's planning opens on the reinforcement phase")
	s.begin_orders()
	report.call(s.plan_step == "orders", "then the orders phase")
	s.back_to_reinforce()
	report.call(s.plan_step == "reinforce", "and back to the recruits if you want")
	s.begin_orders()
	s.lock()
	report.call(s.planner == "blue" and s.plan_step == "reinforce", "the next commander starts on the reinforcement phase")
	report.call(s.map.rules >= 15 and s.map.dig_cap == 3, "new games play by v1.5 rules or later (dig-in up to 3)")
	s.queue_free()
