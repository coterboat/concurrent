## v2.2 (rules 22): an exchange Fortune throws away is owed to the side it had gone well for. The
## owner: "if you have fortune used against you and get screwed out of good rolls that should give
## you a little fortune score to tip the scales back." What the erased exchange was worth to them
## (its swing in their chances, in hundredths of a battle) goes into their ledger at the round's
## end, on top of the battle's own luck; the one who spent the favour isn't charged for it. Rules 21
## games keep the ledger as it was.
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
	_assault(report)
	_melee(report)
	_each_call_its_own(report)
	_wars(report)
	_session(report, tree)
	Combat.use_rules(null)


func _conserved(before: Types.World, result: Dictionary) -> bool:
	var evs: Array = result["events"]
	return MapLib.sum_armies(result["world"]) == MapLib.sum_armies(before) + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)


func _view_agrees(before: Types.World, result: Dictionary) -> bool:
	var seen: Types.World = ViewEvents.apply_through(before, result["events"], (result["events"] as Array).size() - 1)
	var real: Types.World = result["world"]
	for t in real.territories.keys():
		var a: Types.TerritoryState = real.get_territory(t)
		var b: Types.TerritoryState = seen.get_territory(t)
		if a.owner != b.owner or a.armies != b.armies or a.garrison != b.garrison:
			return false
	return true


func _map(rules: int) -> Types.MapDef:
	var m: Types.MapDef = H.knife7()
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.dig_cap = 3
	m.rules = rules
	m.fire_line = true
	m.wild_cards = false
	m.fortune = true
	return m


func _worth(w: Types.World, pid: String) -> int:
	## a commander's standing with Fortune: favours in hand at a bar apiece, and the ledger
	var ps: Types.PlayerState = w.players[pid]
	return ps.fortune * Fortune.BATTLE_18 + ps.fortune_meter


func _assault(report: Callable) -> void:
	## red storms The Gate; blue's officers spend blue's favour when an exchange goes badly for blue
	var found := 0
	var exact := true
	var spender_same := true
	var old_none := true
	var books := true
	for sd in range(1, 121):
		var res: Dictionary = {}
		var worth := {}
		for rules in [22, 21]:
			var m: Types.MapDef = _map(rules)
			var w: Types.World = H.paint(m, {"ridge": ["red", 13], "gate": ["blue", 11], "beacon": ["red", 1], "mill": ["red", 1],
				"harbor": ["blue", 1], "docks": ["blue", 1], "quarry": ["blue", 1]})
			(w.players["blue"] as Types.PlayerState).fortune = 1
			(w.players["red"] as Types.PlayerState).fortune = 0
			var bs: Types.Sheet = H.sheet("blue")
			bs.fortune_auto = true
			var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 12)]), bs], sd)
			books = books and _conserved(w, r) and _view_agrees(w, r)
			res[rules] = r
			worth[rules] = {"red": _worth(r["world"], "red") - _worth(w, "red"), "blue": _worth(r["world"], "blue") - _worth(w, "blue")}
		var inv: Dictionary = H.first(res[22]["events"], Types.EVENT_INVASION)
		var spent := false
		for c in inv.get("calls", []):
			spent = spent or (str(c.get("call", "")) == Combat.CALL_FORTUNE and str(c.get("by", "")) == "blue")
		if not spent:
			continue
		found += 1
		var owed: int = int((inv.get("rebate", {}) as Dictionary).get("red", 0))
		var inv21: Dictionary = H.first(res[21]["events"], Types.EVENT_INVASION)
		old_none = old_none and not inv21.has("rebate")
		## (the ledger is clamped at its floor and a bar a favour: compare only where neither bites)
		var ps22: Types.PlayerState = (res[22]["world"] as Types.World).players["red"]
		var ps21: Types.PlayerState = (res[21]["world"] as Types.World).players["red"]
		if ps22.fortune_meter > Fortune.FLOOR_18 and ps21.fortune_meter > Fortune.FLOOR_18 and ps22.fortune < Fortune.MOST:
			exact = exact and owed > 0 and int(worth[22]["red"]) - int(worth[21]["red"]) == owed
		spender_same = spender_same and int(worth[22]["blue"]) == int(worth[21]["blue"])
	report.call(found > 0 and exact, "rules 22: Varek's favour throws away an exchange that had gone Dad's way, and Dad's ledger is owed what it was worth (%d seeds where it was spent)" % found)
	report.call(found > 0 and spender_same, "the one who spent the favour isn't charged for it: Varek's ledger is as rules 21 keeps it")
	report.call(old_none, "rules 21 untouched: no rebate on the battle, the ledger as it was")
	report.call(books, "every man accounted for, and the report rebuilds the world, both rules")


func _melee(report: Callable) -> void:
	## red and green storm The Gate together; blue's officers spend blue's favour in the melee
	var found := 0
	var shared := true
	var both := 0
	var books := true
	for sd in range(1, 121):
		var m: Types.MapDef = _map(22)
		var w: Types.World = H.paint(m, {"ridge": ["red", 9], "docks": ["green", 9], "gate": ["blue", 12], "beacon": ["red", 1], "mill": ["red", 1],
			"harbor": ["blue", 1], "quarry": ["blue", 1]})
		(w.players["blue"] as Types.PlayerState).fortune = 1
		var bs: Types.Sheet = H.sheet("blue")
		bs.fortune_auto = true
		var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("green", [H.pkt("docks", "gate", 8)]), bs], sd)
		books = books and _conserved(w, r) and _view_agrees(w, r)
		var mel: Dictionary = H.first(r["events"], Types.EVENT_MELEE)
		if (mel.get("defCalls", []) as Array).filter(func(c): return str(c.get("call", "")) == Combat.CALL_FORTUNE).is_empty():
			continue
		found += 1
		var rb: Dictionary = mel.get("rebate", {})
		## owed: every invader whose front stood in that exchange (a front already gone wasn't in it)
		var call: Dictionary = (mel["defCalls"] as Array).filter(func(c): return str(c.get("call", "")) == Combat.CALL_FORTUNE)[0]
		var fr: Array = mel["fronts"]
		for i in fr.size():
			var stood: bool = int((call["fronts"] as Array)[i]) > 0
			var owed: int = int(rb.get(str(fr[i]["attackerId"]), 0))
			shared = shared and (owed > 0) == stood
		shared = shared and not rb.has("blue")
		if int((call["fronts"] as Array)[0]) > 0 and int((call["fronts"] as Array)[1]) > 0:
			both += 1
	report.call(found > 0 and shared and both > 0, "rules 22: in a melee, the defenders' favour owes every invader whose front stood in that exchange its share (%d seeds; %d with both invaders owed)" % [found, both])
	report.call(books, "the melee's men accounted for, and the report rebuilds the world")


func _each_call_its_own(report: Callable) -> void:
	## (RV-005 F4) a melee can have several Fortune calls: the defender's and an invader's. Each call
	## names whom it owes (the battle's narration reads it), and they add up to the battle's rebate.
	## Before, every call was told with the battle's sum, so an invader's call named the other invader
	## (owed for the defender's call) as owed for his.
	var found := 0
	var own := true
	var adds := true
	var books := true
	for sd in range(1, 241):
		var m: Types.MapDef = _map(22)
		var w: Types.World = H.paint(m, {"ridge": ["red", 9], "docks": ["green", 9], "gate": ["blue", 12], "beacon": ["red", 1], "mill": ["red", 1],
			"harbor": ["blue", 1], "quarry": ["blue", 1]})
		(w.players["blue"] as Types.PlayerState).fortune = 1
		(w.players["red"] as Types.PlayerState).fortune = 1
		var bs: Types.Sheet = H.sheet("blue")
		bs.fortune_auto = true
		var rs: Types.Sheet = H.sheet("red", [H.pkt("ridge", "gate", 8)])
		rs.fortune_auto = true
		var r: Dictionary = Resolve.resolve_round(w, m, [rs, H.sheet("green", [H.pkt("docks", "gate", 8)]), bs], sd)
		books = books and _conserved(w, r) and _view_agrees(w, r)
		var mel: Dictionary = H.first(r["events"], Types.EVENT_MELEE)
		var calls: Array = (mel.get("defCalls", []) as Array).duplicate()
		for f in mel.get("fronts", []):
			calls.append_array(f.get("calls", []))
		calls = calls.filter(func(c): return str(c.get("call", "")) == Combat.CALL_FORTUNE)
		var by: Array = calls.map(func(c): return str(c["by"]))
		if not (by.has("blue") and by.has("red")):
			continue
		found += 1
		var sum := {}
		for c in calls:
			var ow: Dictionary = c.get("owed", {})
			own = own and not ow.has(str(c["by"]))
			if str(c["by"]) == "red":
				own = own and (ow.is_empty() or ow.keys() == ["blue"])
			for op in ow.keys():
				sum[op] = int(sum.get(op, 0)) + int(ow[op])
		var rb: Dictionary = mel.get("rebate", {})
		for op in rb.keys():
			adds = adds and absi(int(sum.get(op, 0)) - int(rb[op])) <= calls.size()
		adds = adds and sum.keys().all(func(op): return rb.has(op))
	report.call(found > 0 and own, "rules 22: in a melee where Varek and Dad both call on Fortune, each call names only whom it owes: Dad's, Varek alone; never the one who spent it (%d seeds)" % found)
	report.call(found > 0 and adds, "the calls' debts add up to the battle's rebate (to the rounding), which is what the ledger books")
	report.call(books, "those melees' men accounted for, and the report rebuilds the world")


func _wars(report: Callable) -> void:
	for mid in ["known24", "isles24"]:
		var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.maneuvers = true
		m.dig_cap = 3
		m.rules = 22
		m.fire_line = true
		m.capitals = true
		m.fortune = true
		m.levee = 3
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}, {"id": "purple", "name": "e", "ai": "recruit"}]
		var r: Dictionary = Autoplay.play(m, seats, 73, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var rebates := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 73)
			if not _view_agrees(w, res) or not _conserved(w, res):
				ok = false
			rebates += (res["events"] as Array).filter(func(e): return e.has("rebate")).size()
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s under rules 22, five commanders: legal, replays, conserved, the report agrees (%d battles owed a rebate) %s" % [mid, rebates, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 5, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules == 22, "a new game plays rules 22")
	s.queue_free()
