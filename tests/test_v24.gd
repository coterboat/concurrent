## v2.4 (rules 23), from the owner's play on v2.3.1 (10-21). A commander storming a land from two of his
## own lands makes his battle calls with both fronts together: judged alone against the defenders'
## whole firing line, each front of a storm from two sides looked lost, so one column fell back while
## the other fought on, and the next call took the rest ("one side animated a retreat, their total
## strength didn't go down, and combat continued as before"). And a melee's even volley is fired
## again, as an assault's has been since Amendment 18 ("rerolls in dual invasions don't re-roll if
## they tie on subsequent rolls"). Rules 22 games replay exactly as they were played.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const MapLib := preload("res://engine/map.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Telemetry := preload("res://engine/telemetry.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Session := preload("res://game/core/session.gd")

## (rules 22 wars played by the engine before v2.4: tools/arena-style, five commanders; the same
## world at the end, or an old save would replay differently)
const GOLDEN := [["known24", 61, "ee81ff40"], ["isles24", 62, "3746df9f"], ["known24", 63, "49f4dd07"]]


func run(report: Callable, tree: SceneTree) -> void:
	_split_count(report)
	_together(report)
	_mixed_orders(report)
	_reserves_together(report)
	_refire(report)
	_priced(report)
	_officer_on_the_plate(report)
	_officer_at_a_fortress(report)
	_old_wars(report)
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
	m.fortune = false
	return m


func _gate(m: Types.MapDef, ridge: int, harbor: int, gate: int) -> Types.World:
	## red holds Ridge and Harbor, both on The Gate's border; blue holds The Gate
	return H.paint(m, {"ridge": ["red", ridge], "harbor": ["red", harbor], "gate": ["blue", gate], "beacon": ["blue", 1], "mill": ["blue", 1],
		"docks": ["blue", 1], "quarry": ["blue", 1]})


func _storm(m: Types.MapDef, w: Types.World, a: int, b: int, sa: String, sb: String, sd: int, live: Array = []) -> Dictionary:
	var pa: Types.Packet = H.pkt("ridge", "gate", a)
	var pb: Types.Packet = H.pkt("harbor", "gate", b)
	pa.stance = sa
	pb.stance = sb
	return Resolve.resolve_round(w, m, [H.sheet("red", [pa, pb]), H.sheet("blue")], sd, live)


func _calls_of(mel: Dictionary, from: String, call: String) -> Array:
	## the "at" of every call of that kind made by the front from that land
	var out: Array = []
	for f in mel.get("fronts", []):
		if str(f["from"]) == from:
			for c in f.get("calls", []):
				if str(c["call"]) == call:
					out.append(int(c["at"]))
	return out


func _split_count(report: Callable) -> void:
	## the measure itself, on fights written by hand
	var salvo := func(i: int, w: String) -> Dictionary: return {"i": i, "a": 1, "b": 1, "w": w}
	var base := {"kind": Types.EVENT_MELEE, "to": "gate", "defenderId": "blue", "defenderSize": 9, "salvos": [[salvo.call(0, "a"), salvo.call(1, "b")],
		[salvo.call(0, "b"), salvo.call(1, "a")], [salvo.call(0, "a"), salvo.call(1, "b")]]}
	var alone: Dictionary = base.duplicate(true)
	alone["fronts"] = [{"attackerId": "red", "from": "ridge", "size": 7, "left": 6}, {"attackerId": "red", "from": "harbor", "size": 5, "left": 3, "fellBack": true,
		"calls": [{"at": 3, "call": "f", "n": 3, "to": "harbor"}]}]
	var both: Dictionary = base.duplicate(true)
	both["fronts"] = [{"attackerId": "red", "from": "ridge", "size": 7, "left": 6, "fellBack": true, "calls": [{"at": 3, "call": "f", "n": 6, "to": "ridge"}]},
		{"attackerId": "red", "from": "harbor", "size": 5, "left": 3, "fellBack": true, "calls": [{"at": 3, "call": "f", "n": 3, "to": "harbor"}]}]
	var rival: Dictionary = alone.duplicate(true)
	rival["fronts"][0]["attackerId"] = "green"
	var dead: Dictionary = alone.duplicate(true)
	dead["fronts"][0]["size"] = 1 ## Ridge's lone man fell in the second salvo, before Harbor's call
	report.call(Telemetry.split_retreats(alone) == 1 and Telemetry.split_retreats(both) == 0 and Telemetry.split_retreats(rival) == 0 and Telemetry.split_retreats(dead) == 0,
		"the measure: a column falling back while another of its commander's fights on counts (%d); both at once, a rival's column, or one already destroyed don't (%d, %d, %d)" % [
		Telemetry.split_retreats(alone), Telemetry.split_retreats(both), Telemetry.split_retreats(rival), Telemetry.split_retreats(dead)])


func _together(report: Callable) -> void:
	## Imre's storm (officer's judgment) and Quill's (fall back if it turns): 7 from Ridge and 5 from
	## Harbor against a Gate of 10, on the same 200 seeds under both rules
	var taken := {}
	for stance in ["judgment", "careful"]:
		for rules in [23, 22]:
			var m: Types.MapDef = _map(rules)
			var splits := 0
			var falls := 0
			var apart := 0
			var books := true
			var won := 0
			for sd in range(1, 201):
				var w: Types.World = _gate(m, 8, 6, 10)
				var res: Dictionary = _storm(m, w, 7, 5, stance, stance, sd)
				books = books and _conserved(w, res) and _view_agrees(w, res)
				if (res["world"] as Types.World).get_territory("gate").owner == "red":
					won += 1
				var mel: Dictionary = H.first(res["events"], Types.EVENT_MELEE)
				splits += Telemetry.split_retreats(mel)
				var ats: Array = _calls_of(mel, "ridge", Combat.CALL_FALL_BACK) + _calls_of(mel, "harbor", Combat.CALL_FALL_BACK)
				falls += ats.size()
				if ats.size() == 2 and int(ats[0]) != int(ats[1]):
					apart += 1
			taken["%s%d" % [stance, rules]] = won
			if rules == 23:
				report.call(splits == 0 and apart == 0 and falls > 0,
					"rules 23, %s: his two columns fall back together or not at all (%d fell back over 200 storms; none left the other fighting on, none a call apart)" % [stance, falls])
			else:
				report.call(splits > 20, "rules 22 untouched (%s): each column judged alone, one falls back while the other fights on (%d times in 200 storms)" % [stance, splits])
			report.call(books, "rules %d, %s: every man accounted for, and the report rebuilds the world" % [rules, stance])
	report.call(int(taken["judgment23"]) > int(taken["judgment22"]) + 40 and int(taken["careful23"]) > int(taken["careful22"]) + 40,
		"judged together, a storm worth sending is no longer thrown away a column at a time: The Gate falls %d times in 200 (was %d) under officer's judgment, %d (was %d) when they fall back if it turns" % [
		int(taken["judgment23"]), int(taken["judgment22"]), int(taken["careful23"]), int(taken["careful22"])])


func _mixed_orders(report: Callable) -> void:
	## a commander who orders one column to the last man and the other to fall back if it turns gets
	## what he ordered: the careful one goes when the whole storm's odds turn, the other never does
	var m: Types.MapDef = _map(23)
	var hold_fell := 0
	var careful_fell := {23: 0, 22: 0}
	for rules in [23, 22]:
		m = _map(rules)
		for sd in range(1, 201):
			var w: Types.World = _gate(m, 8, 6, 10)
			var res: Dictionary = _storm(m, w, 7, 5, Combat.STANCE_HOLD, Combat.STANCE_CAREFUL, sd)
			var mel: Dictionary = H.first(res["events"], Types.EVENT_MELEE)
			if rules == 23:
				hold_fell += _calls_of(mel, "ridge", Combat.CALL_FALL_BACK).size()
			careful_fell[rules] = int(careful_fell[rules]) + _calls_of(mel, "harbor", Combat.CALL_FALL_BACK).size()
	report.call(hold_fell == 0 and int(careful_fell[23]) > 0 and int(careful_fell[23]) < int(careful_fell[22]),
		"rules 23, one column to the last man and one careful: the careful one falls back on the whole storm's odds (%d times in 200, %d when judged alone), the other never (%d)" % [
		int(careful_fell[23]), int(careful_fell[22]), hold_fell])


func _reserves_together(report: Callable) -> void:
	## both homes keep men who could march: when his officers throw in the reserves, both columns do, at one call
	var m: Types.MapDef = _map(23)
	var called := 0
	var apart := 0
	var books := true
	for sd in range(1, 121):
		var w: Types.World = _gate(m, 12, 10, 12)
		var res: Dictionary = _storm(m, w, 6, 5, Combat.STANCE_JUDGMENT, Combat.STANCE_JUDGMENT, sd)
		books = books and _conserved(w, res) and _view_agrees(w, res)
		var mel: Dictionary = H.first(res["events"], Types.EVENT_MELEE)
		var at := -1
		for f in mel.get("fronts", []):
			for c in f.get("calls", []):
				if str(c["call"]) == Combat.CALL_RESERVES and (at < 0 or int(c["at"]) < at):
					at = int(c["at"])
		if at < 0:
			continue
		called += 1
		## every column still fighting at that call throws its reserves in at it
		for k in (mel["fronts"] as Array).size():
			var mine: Array = _calls_of(mel, str(mel["fronts"][k]["from"]), Combat.CALL_RESERVES)
			if _men_at(mel, k, at) > 0 and not mine.has(at):
				apart += 1
	report.call(called > 0 and apart == 0 and books, "rules 23: his officers call up both columns' reserves at one call, never one column's alone while the other fights (%d storms called them; every man accounted for)" % called)


func _men_at(mel: Dictionary, k: int, at: int) -> int:
	## front k's men at the call made after `at` salvos (no Fortune in these fights)
	var f: Dictionary = mel["fronts"][k]
	var n: int = int(f["size"])
	for c in f.get("calls", []):
		if int(c["at"]) < at:
			if str(c["call"]) == Combat.CALL_RESERVES:
				n += int(c.get("n", 0))
			elif str(c["call"]) == Combat.CALL_FALL_BACK:
				return 0
	var salvos: Array = mel.get("salvos", [])
	for s in mini(at, salvos.size()):
		for v in salvos[s]:
			if int(v["i"]) == k and str(v["w"]) == "b":
				n -= 1
	return n


func _refire(report: Callable) -> void:
	## every front fights to the last man (no calls), so every salvo can be read
	for rules in [23, 22]:
		var m: Types.MapDef = _map(rules)
		var fired_again := 0
		var lost_ties := 0
		var undecided := 0
		var twice := 0
		var books := true
		for sd in range(1, 151):
			var w: Types.World = _gate(m, 10, 10, 10)
			var res: Dictionary = _storm(m, w, 9, 9, Combat.STANCE_HOLD, Combat.STANCE_HOLD, sd)
			books = books and _conserved(w, res) and _view_agrees(w, res)
			var mel: Dictionary = H.first(res["events"], Types.EVENT_MELEE)
			for salvo in mel.get("salvos", []):
				var last := {}
				var seen := {}
				for v in salvo:
					var i: int = int(v["i"])
					if seen.has(i):
						twice += 1
						if str(last[i]) == "":
							fired_again += 1
					seen[i] = true
					last[i] = str(v["w"])
				for i in last.keys():
					if str(last[i]) == "":
						if rules >= 23:
							undecided += 1
						else:
							lost_ties += 1
		if rules == 23:
			report.call(fired_again > 0 and undecided == 0 and twice == fired_again,
				"rules 23: a melee's even volley is fired again within its salvo: %d fired again over 150 storms, and every front's volley in every salvo decided" % fired_again)
		else:
			report.call(twice == 0 and lost_ties > 0, "rules 22 untouched: an even volley costs nobody and is one of the exchange's three (%d of them), never fired again" % lost_ties)
		report.call(books, "rules %d: the melee adds up, and the report rebuilds the world" % rules)


func _priced(report: Callable) -> void:
	## the price the order card, the advisor, the AI and the battle screen quote, against the battles
	var m: Types.MapDef = _map(23)
	Combat.use_rules(m)
	report.call(Combat.refire, "a rules 23 game prices its melees with even volleys fired again")
	var n := 300
	for case in [[[6, 5], 9, 7, 6], [[4, 3, 3], 7, 5, 4]]:
		var sizes: Array = case[0]
		var won := 0
		for sd in range(1, n + 1):
			var w: Types.World
			var res: Dictionary
			if sizes.size() == 2:
				w = _gate(m, int(case[2]), int(case[3]), int(case[1]))
				res = _storm(m, w, int(sizes[0]), int(sizes[1]), Combat.STANCE_HOLD, Combat.STANCE_HOLD, sd * 7919)
			else:
				w = H.paint(m, {"ridge": ["red", 5], "harbor": ["red", 4], "docks": ["red", 4], "gate": ["blue", int(case[1])],
					"beacon": ["blue", 1], "mill": ["blue", 1], "quarry": ["blue", 1]})
				res = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 4), H.pkt("harbor", "gate", 3), H.pkt("docks", "gate", 3)]), H.sheet("blue")], sd * 7919)
			if (res["world"] as Types.World).get_territory("gate").owner == "red":
				won += 1
		Combat.use_rules(m)
		var p: float = Combat.fronts_capture_rate(sizes, int(case[1]))
		report.call(absf(float(won) / n - p) < 0.07, "rules 23: %s against %d priced %.2f, the battles took it %d of %d (%.2f)" % [str(sizes), int(case[1]), p, won, n, float(won) / n])
	var m22: Types.MapDef = _map(22)
	Combat.use_rules(m22)
	report.call(not Combat.refire, "a rules 22 game prices them as they were fought")


func _officer_on_the_plate(report: Callable) -> void:
	## a commander watching his own storm is asked column by column; the plate carries his columns'
	## numbers (for the odds of them together), and what his officers would call there (auto-roll):
	## the very call they make when nobody watches, under the game's own rules
	for rules in [23, 22]:
		var m: Types.MapDef = _map(rules)
		var asked := 0
		var agree := 0
		var carried := true
		for sd in range(1, 41):
			var w: Types.World = _gate(m, 8, 6, 10)
			var live: Dictionary = _storm(m, w, 7, 5, Combat.STANCE_JUDGMENT, Combat.STANCE_JUDGMENT, sd, ["red"])
			var pend: Dictionary = live.get("pending", {})
			if pend.is_empty() or not bool(pend.get("melee", false)) or bool(pend.get("fortune", false)):
				continue
			asked += 1
			var mine: Array = pend.get("mine", [])
			carried = carried and mine.size() == 2 and int(mine[0]) == int(pend["a"]) and pend.has("officer")
			## the officers, left to it, make that very call at that very moment
			var off: Dictionary = _storm(m, _gate(m, 8, 6, 10), 7, 5, Combat.STANCE_JUDGMENT, Combat.STANCE_JUDGMENT, sd)
			var mel: Dictionary = H.first(off["events"], Types.EVENT_MELEE)
			var f: Dictionary = mel["fronts"][int(pend["front"])]
			if _call_at(f.get("calls", []), int(pend["rolls"])) == str(pend.get("officer", "")):
				agree += 1
		report.call(asked > 0 and carried and agree == asked, "rules %d: the call plate carries his columns' numbers, and the officers' call on it is the one they make unwatched (%d of %d)" % [rules, agree, asked])


func _call_at(calls: Array, at: int) -> String:
	## the call made after `at` volleys (a press isn't written down)
	for c in calls:
		if int(c["at"]) == at and str(c["call"]) != Combat.CALL_FORTUNE and str(c["call"]) != Combat.CALL_STAND:
			return str(c["call"])
	return Combat.CALL_PRESS


func _officer_at_a_fortress(report: Callable) -> void:
	## (the coordinator, after the merge) a plain assault's pause carries the officers' call too, so a
	## battle watched on auto-roll calls as one skipped: behind a capital's walls (a fortress's longer
	## line) the odds are worse, and the session's own officer_call() never counted that
	for rules in [23, 22]:
		var m: Types.MapDef = _map(rules)
		m.capitals = true
		var asked := 0
		var differ := 0
		var agree := 0
		for sd in range(1, 121):
			var w: Types.World = H.paint(m, {"ridge": ["red", 11], "harbor": ["red", 2], "gate": ["blue", 12], "beacon": ["blue", 1], "mill": ["blue", 1],
				"docks": ["blue", 1], "quarry": ["blue", 1]})
			(w.players["blue"] as Types.PlayerState).capital = "gate"
			(w.players["red"] as Types.PlayerState).capital = "harbor"
			var pk: Types.Packet = H.pkt("ridge", "gate", 10)
			pk.stance = Combat.STANCE_CAREFUL
			var live: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [pk]), H.sheet("blue")], sd, ["red"])
			var pend: Dictionary = live.get("pending", {})
			if pend.is_empty() or bool(pend.get("melee", false)) or bool(pend.get("fortune", false)):
				continue
			asked += 1
			var a: int = int(pend["a"])
			var d: int = int(pend["d"])
			var go: bool = str(pend["refuge"]) != ""
			var walls: String = Combat.doctrine(str(pend["stance"]), a, d, int(pend["reserves"]), go, 1)
			if walls != Combat.doctrine(str(pend["stance"]), a, d, int(pend["reserves"]), go, 0):
				differ += 1
			var off: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [pk]), H.sheet("blue")], sd)
			var inv: Dictionary = H.first(off["events"], Types.EVENT_INVASION)
			if str(pend.get("officer", "")) == walls and _call_at(inv.get("calls", []), int(pend["rolls"])) == walls:
				agree += 1
		report.call(differ > 0 and agree == asked,
			"rules %d: an assault on a capital paused for its call carries the officers' call, the walls counted, and it is the call they make unwatched (%d of %d; at %d of them the walls change the call)" % [rules, agree, asked, differ])


func _old_wars(report: Callable) -> void:
	for g in GOLDEN:
		var m: Types.MapDef = _war_map(str(g[0]), 22)
		var r: Dictionary = Autoplay.play(m, _seats(), int(g[1]), 0, true)
		report.call(r["ok"] and str(Hash.world_hash(r["world"])) == str(g[2]),
			"rules 22 untouched: the %s war on seed %d ends on the world it always did (%s, want %s)" % [g[0], int(g[1]), str(Hash.world_hash(r["world"])), g[2]])


func _war_map(id: String, rules: int) -> Types.MapDef:
	var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % id)
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.maneuvers = true
	m.dig_cap = 3
	m.rules = rules
	m.fire_line = true
	m.capitals = true
	m.fortune = true
	m.levee = 3
	return m


func _seats() -> Array:
	return [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "quill"},
		{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "imre"}, {"id": "purple", "name": "e", "ai": "veteran"}]


func _wars(report: Callable) -> void:
	for spec in [["known24", 61], ["isles24", 62]]:
		var m: Types.MapDef = _war_map(str(spec[0]), 23)
		var r: Dictionary = Autoplay.play(m, _seats(), int(spec[1]), 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var two_sided := 0
		var splits := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, int(spec[1]))
			if not _view_agrees(w, res) or not _conserved(w, res):
				ok = false
			for e in H.all_of(res["events"], Types.EVENT_MELEE):
				splits += Telemetry.split_retreats(e)
				var seen := {}
				for f in e["fronts"]:
					if seen.has(str(f["attackerId"])):
						two_sided += 1
					seen[str(f["attackerId"])] = true
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]) and splits == 0,
			"%s under rules 23, five commanders: legal, replays to the same world, conserved, the report agrees; %d lands stormed from two sides by one commander, no column left fighting alone by a retreat (%d) %s" % [
			spec[0], two_sided, splits, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 5, "length": "short", "deal": "random", "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules == 23 and Combat.refire, "a new game plays rules 23 (%d)" % s.map.rules)
	s.queue_free()
