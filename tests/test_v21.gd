## v2.1 (rules 21): one commander's columns from different lands are separate fronts, as two
## commanders' would be (the owner: "if i'm attacking from two places, rather than have my army show
## up as one large force, let's use the same logic for when two opponents are attacking a third…
## it allows for a pesky defender to hold out a huge force by separating the power between two
## different places"). A land stormed from two sides is a melee whose defenders hold every front; a
## border clash is fought by the column on that border alone; the fronts that stand join up and take
## the land together (they never fight each other); columns into an empty land walk in together.
## Rules 20 games merge them into one force, as they always did.
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
const LastRound := preload("res://game/core/last_round.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_two_fronts(report)
	_clash_by_border(report)
	_walk_in_together(report)
	_surge_together(report)
	_fates_by_column(report)
	_fate_of_a_broken_front(report)
	_wars(report)
	_session(report, tree)
	_one_battle(report, tree)
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
	return m


func _gate_world(m: Types.MapDef, gate: int) -> Types.World:
	## red holds Ridge and Harbor, both on The Gate's border; blue holds The Gate
	return H.paint(m, {"ridge": ["red", 10], "harbor": ["red", 10], "gate": ["blue", gate], "beacon": ["blue", 1], "mill": ["blue", 1],
		"docks": ["blue", 1], "quarry": ["blue", 1]})


func _two_fronts(report: Callable) -> void:
	for rules in [21, 20]:
		var m: Types.MapDef = _map(rules)
		var shape := true
		var books := true
		var joined := 0
		var held := 0
		var line_ok := true
		for sd in range(1, 41):
			var w: Types.World = _gate_world(m, 9)
			var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 9), H.pkt("harbor", "gate", 9)]), H.sheet("blue")], sd)
			var evs: Array = res["events"]
			var melees: Array = H.all_of(evs, Types.EVENT_MELEE)
			var invs: Array = H.all_of(evs, Types.EVENT_INVASION)
			books = books and _conserved(w, res) and _view_agrees(w, res)
			if rules == 21:
				if melees.size() != 1 or not invs.is_empty():
					shape = false
					continue
				var fr: Array = melees[0]["fronts"]
				var froms: Array = fr.map(func(f): return str(f["from"]))
				froms.sort()
				shape = shape and fr.size() == 2 and froms == ["harbor", "ridge"] and int(fr[0]["size"]) == 9 and int(fr[1]["size"]) == 9 \
					and str(fr[0]["attackerId"]) == "red" and str(fr[1]["attackerId"]) == "red"
				## the defenders' whole firing line faces both fronts in every salvo
				for salvo in melees[0]["salvos"]:
					if (salvo as Array).size() == 2 and (int(salvo[0]["fd"]) != int(salvo[1]["fd"]) or int(salvo[0]["sd"]) != int(salvo[1]["sd"])):
						line_ok = false
				var after: Types.World = res["world"]
				if after.get_territory("gate").owner == "red":
					var standing := 0
					for f in fr:
						if not bool(f.get("fellBack", false)):
							standing += int(f["left"])
					var fights_among: int = H.all_of(evs, Types.EVENT_SCRAMBLE).size() + H.all_of(evs, Types.EVENT_SPOILS).size()
					if fights_among == 0 and after.get_territory("gate").armies == standing:
						joined += 1
				else:
					held += 1
			else:
				shape = shape and melees.is_empty() and invs.size() == 1 and int(invs[0]["attackerSize"]) == 18
		if rules == 21:
			report.call(shape, "rules 21: Dad storms The Gate from Ridge and from Harbor: one melee, two fronts of his own (9 and 9), not one army of 18")
			report.call(line_ok, "the defenders' whole firing line faces both fronts in every salvo")
			report.call(joined > 0 and held > 0, "where the walls fall, his two fronts join up and take it together, with every man still standing (%d of 40); some seeds the defenders hold (%d)" % [joined, held])
		else:
			report.call(shape, "rules 20 untouched: the two columns are one army of 18, one invasion")
		report.call(books, "rules %d: every man accounted for, and the report rebuilds the world, on all 40 seeds" % rules)


func _clash_by_border(report: Callable) -> void:
	## blue marches out of The Gate on Ridge while red storms The Gate from Ridge and Harbor
	for rules in [21, 20]:
		var m: Types.MapDef = _map(rules)
		var w: Types.World = _gate_world(m, 12)
		var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 9), H.pkt("harbor", "gate", 9)]),
			H.sheet("blue", [H.pkt("gate", "ridge", 8)])], 7)
		var cl: Dictionary = H.first(res["events"], Types.EVENT_CLASH)
		var red_size: int = int(cl.get("sizeB", -1)) if str(cl.get("playerB", "")) == "red" else int(cl.get("sizeA", -1))
		if rules == 21:
			report.call(not cl.is_empty() and red_size == 9, "rules 21: the border clash on Ridge's border is fought by the column crossing it (9), not by Harbor's too (red brought %d)" % red_size)
		else:
			report.call(not cl.is_empty() and red_size == 18, "rules 20 untouched: the merged army of 18 meets the column in the field (red brought %d)" % red_size)
		report.call(_conserved(w, res) and _view_agrees(w, res), "rules %d: the clash and what follows add up, and the report agrees" % rules)


func _walk_in_together(report: Callable) -> void:
	var m: Types.MapDef = _map(21)
	var w: Types.World = H.paint(m, {"ridge": ["red", 10], "harbor": ["red", 10], "gate": ["", 0], "beacon": ["blue", 1], "mill": ["blue", 1],
		"docks": ["blue", 1], "quarry": ["blue", 1]})
	var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 5), H.pkt("harbor", "gate", 4)]), H.sheet("blue")], 3)
	var after: Types.World = res["world"]
	var fought: int = H.all_of(res["events"], Types.EVENT_SCRAMBLE).size() + H.all_of(res["events"], Types.EVENT_SPOILS).size()
	report.call(after.get_territory("gate").owner == "red" and after.get_territory("gate").armies == 9 and fought == 0 and _view_agrees(w, res),
		"rules 21: into an empty land his two columns walk in together (9 there, no fight among them)")


func _surge_together(report: Callable) -> void:
	## (the outside review, RV-001 F1) his two fronts take The Gate together and push on with its
	## surge, the one order the land carries, from both of their lands
	var m: Types.MapDef = _map(21)
	var fired := 0
	var books := true
	for sd in range(1, 21):
		var w: Types.World = H.paint(m, {"ridge": ["red", 10], "harbor": ["red", 10], "gate": ["blue", 3], "quarry": ["blue", 1],
			"beacon": ["blue", 1], "mill": ["blue", 1], "docks": ["blue", 1]})
		var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 9, "quarry"), H.pkt("harbor", "gate", 9, "quarry")]), H.sheet("blue")], sd)
		books = books and _conserved(w, res) and _view_agrees(w, res)
		if (res["world"] as Types.World).get_territory("gate").owner != "red":
			continue
		var surges: Array = H.all_of(res["events"], Types.EVENT_SURGE).filter(func(e): return str(e.get("from", "")) == "gate" and str(e.get("to", "")) == "quarry")
		if surges.size() == 1:
			fired += 1
	report.call(fired > 0 and books, "rules 21: his two fronts take The Gate and push on to Quarry with its one surge (%d of 20 seeds); every man accounted for" % fired)


func _fates_by_column(report: Callable) -> void:
	## (the outside review, RV-002's class) last round's marks: Dad's column from Ridge beaten on
	## Ridge's border died there; his column from Harbor never fought it, and its mark says what it did
	var m: Types.MapDef = _map(21)
	var checked := 0
	var ok := true
	for sd in range(1, 41):
		var w: Types.World = H.paint(m, {"ridge": ["red", 7], "harbor": ["red", 10], "gate": ["blue", 18], "beacon": ["blue", 1], "mill": ["blue", 1],
			"docks": ["blue", 1], "quarry": ["blue", 1]})
		var sheets: Array = [H.sheet("red", [H.pkt("ridge", "gate", 6), H.pkt("harbor", "gate", 9)]), H.sheet("blue", [H.pkt("gate", "ridge", 14)])]
		var res: Dictionary = Resolve.resolve_round(w, m, sheets, sd)
		var cl: Dictionary = H.first(res["events"], Types.EVENT_CLASH)
		if cl.is_empty() or str(cl["winnerId"]) != "blue":
			continue
		checked += 1
		var gs: Array = LastRound.ghosts(w, res["world"], sheets, res["events"], 21)
		for g in gs:
			if str(g["owner"]) != "red":
				continue
			if str(g["from"]) == "ridge":
				ok = ok and str(g["result"]) == LastRound.CLASH
			elif str(g["from"]) == "harbor":
				ok = ok and str(g["result"]) != LastRound.CLASH
	report.call(checked > 0 and ok, "rules 21: last round's marks: the column from Ridge died in the clash on its border, the column from Harbor didn't (%d seeds where Varek won the clash)" % checked)


func _fate_of_a_broken_front(report: Callable) -> void:
	## (the outside review, RV-003 F1) his front from Ridge is destroyed while his front from Harbor
	## takes The Gate: Ridge's mark says it was thrown back, Harbor's that it took it
	var m: Types.MapDef = _map(21)
	var checked := 0
	var ok := true
	for sd in range(1, 61):
		var w: Types.World = H.paint(m, {"ridge": ["red", 3], "harbor": ["red", 16], "gate": ["blue", 6], "beacon": ["blue", 1], "mill": ["blue", 1],
			"docks": ["blue", 1], "quarry": ["blue", 1]})
		var sheets: Array = [H.sheet("red", [H.pkt("ridge", "gate", 2), H.pkt("harbor", "gate", 15)]), H.sheet("blue")]
		var res: Dictionary = Resolve.resolve_round(w, m, sheets, sd)
		if (res["world"] as Types.World).get_territory("gate").owner != "red":
			continue
		var mel: Dictionary = H.first(res["events"], Types.EVENT_MELEE)
		var ridge_left := -1
		for f in mel.get("fronts", []):
			if str(f["from"]) == "ridge":
				ridge_left = int(f["left"])
		if ridge_left != 0:
			continue
		checked += 1
		for g in LastRound.ghosts(w, res["world"], sheets, res["events"], 21):
			if str(g["owner"]) == "red" and str(g["from"]) == "ridge":
				ok = ok and str(g["result"]) == LastRound.THROWN_BACK
			elif str(g["owner"]) == "red" and str(g["from"]) == "harbor":
				ok = ok and str(g["result"]) == LastRound.TOOK
	report.call(checked > 0 and ok, "rules 21: last round's marks: his front from Ridge destroyed, his front from Harbor took The Gate: one marked thrown back, the other took it (%d seeds)" % checked)


func _wars(report: Callable) -> void:
	for mid in ["known24", "isles24"]:
		var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.maneuvers = true
		m.dig_cap = 3
		m.rules = 21
		m.fire_line = true
		m.capitals = true
		m.fortune = true
		m.levee = 3
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}, {"id": "purple", "name": "e", "ai": "recruit"}]
		var r: Dictionary = Autoplay.play(m, seats, 61, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var two_sided := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 61)
			if not _view_agrees(w, res) or not _conserved(w, res):
				ok = false
			for e in H.all_of(res["events"], Types.EVENT_MELEE):
				var seen := {}
				for f in e["fronts"]:
					if seen.has(str(f["attackerId"])):
						two_sided += 1
					seen[str(f["attackerId"])] = true
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s under rules 21, five commanders: legal, replays, conserved, the report agrees (%d lands stormed from two sides by one commander) %s" % [mid, two_sided, " ".join(r["violations"])])


func _one_battle(report: Callable, tree: SceneTree) -> void:
	## (round 3's class) a commander storming a land from two sides fought one battle, not two: the
	## war's tally (the game-over screen's battles won) counts it once
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	var blank := {"battles": 0, "won": 0, "armies_lost": 0, "captures": 0, "walkins": 0, "walked": 0}
	s.stats = {"red": blank.duplicate(), "blue": blank.duplicate()}
	s._tally([{"kind": Types.EVENT_MELEE, "to": "gate", "defenderId": "blue", "defenderSize": 9, "defenderLeft": 0, "salvos": [],
		"fronts": [{"attackerId": "red", "from": "ridge", "size": 9, "left": 6}, {"attackerId": "red", "from": "harbor", "size": 9, "left": 5}]}])
	var r: Dictionary = s.stats["red"]
	report.call(int(r["battles"]) == 1 and int(r["won"]) == 1 and int(r["armies_lost"]) == 7 and int(s.stats["blue"]["battles"]) == 1,
		"rules 21: two fronts of one commander are one battle won in the war's tally (%d battles, %d won, %d lost)" % [int(r["battles"]), int(r["won"]), int(r["armies_lost"])])
	s.queue_free()


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 5, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules >= 21, "a new game plays rules 21 or later (%d)" % s.map.rules)
	s.queue_free()
