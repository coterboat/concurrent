## v1.12 (rules 20): a fallen capital's court flees somewhere safe and arrives with its guard (one
## fresh troop, the garrison dug in to the full); and a map can be amended from a rules version on
## (the Thousand Isles: Great Vane pays 3, not 4), so older saves replay on the map they had.
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
const Income := preload("res://engine/income.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_amendments(report)
	_court(report)
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
	for pid in real.players.keys():
		if str(real.players[pid].capital) != str(seen.players[pid].capital):
			return false
	return true


func _amendments(report: Callable) -> void:
	var m: Types.MapDef = Types.MapDef.from_file("res://maps/isles24.json")
	report.call(int(m.region_bonus["vane"]) == 4, "the Thousand Isles as drawn: Great Vane pays 4")
	m.rules = 20
	var twenty: int = int(m.region_bonus["vane"])
	m.rules = 19
	var back: int = int(m.region_bonus["vane"])
	m.rules = 20
	report.call(twenty == 3 and back == 4 and int(m.region_bonus["vane"]) == 3 and int(m.region_bonus["reach"]) == 5,
		"rules 20 amend it to 3; set back to 19, it pays 4 again (a save replays on its own map)")
	## a sea lane added by an amendment, on a map made for the test
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/knife7.json"))
	d["amendments"] = [{"since": 20, "lanes": [["beacon", "mill"]]}]
	var k: Types.MapDef = Types.MapDef.from_dict(d)
	var off0: bool = not k.is_adjacent("beacon", "mill") and not k.lane_live("beacon", "mill")
	k.rules = 20
	var on: bool = k.is_adjacent("beacon", "mill") and k.is_adjacent("mill", "beacon") and Array(MapLib.neighbors(k, "beacon")).has("mill") and k.lane_live("beacon", "mill")
	k.rules = 19
	var off1: bool = not k.is_adjacent("beacon", "mill") and not k.is_adjacent("mill", "beacon")
	report.call(off0 and on and off1 and k.lane_live("ridge", "gate"), "an amended sea lane is there only under the rules that added it, both ways")


func _court_world(m: Types.MapDef) -> Types.World:
	## Red's capital is The Gate; its biggest stack is at Harbor, but Docks is deepest in its lands
	var w: Types.World = H.paint(m, {"gate": ["red", 2], "harbor": ["red", 9], "docks": ["red", 1], "quarry": ["red", 1],
		"ridge": ["blue", 14], "beacon": ["blue", 1], "mill": ["blue", 1]})
	(w.players["red"] as Types.PlayerState).capital = "gate"
	(w.players["blue"] as Types.PlayerState).capital = "beacon"
	return w


func _court(report: Callable) -> void:
	for rules in [20, 19]:
		var m: Types.MapDef = H.knife7()
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.dig_cap = 3
		m.rules = rules
		m.fire_line = true
		m.wild_cards = false
		m.capitals = true
		var won := false
		for sd in range(1, 40):
			var w: Types.World = _court_world(m)
			var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("blue", [H.pkt("ridge", "gate", 13)]), H.sheet("red")], sd)
			var after: Types.World = res["world"]
			if after.get_territory("gate").owner != "blue":
				continue
			won = true
			var cap: String = str((after.players["red"] as Types.PlayerState).capital)
			var docks: Types.TerritoryState = after.get_territory("docks")
			var guards: Array = (res["events"] as Array).filter(func(e): return bool(e.get("courtGuard", false)))
			var dug: Array = (res["events"] as Array).filter(func(e): return bool(e.get("court", false)))
			if rules == 20:
				var full: int = Income.garrison_cap(after, m, "docks")
				report.call(cap == "docks", "rules 20: the court flees deep into its own lands (Docks), not to its biggest stack (it went to %s)" % cap)
				report.call(docks.armies == 2 and docks.garrison == full and full == 4 and guards.size() == 1 and dug.size() == 1 and int(dug[0].get("added", 0)) >= 1,
					"it arrives with its guard: one fresh troop (%d there) and the garrison dug in to the full (%d of %d)" % [docks.armies, docks.garrison, full])
			else:
				report.call(cap == "harbor" and guards.is_empty() and dug.is_empty() and after.get_territory("harbor").armies == 9,
					"rules 19 untouched: the new capital is the best-held land (%s), no guard, no dig-in" % cap)
			report.call(_conserved(w, res) and _view_agrees(w, res), "rules %d: every man accounted for, and the report rebuilds the world" % rules)
			break
		report.call(won, "rules %d: Varek takes The Gate within the seeds tried" % rules)


func _wars(report: Callable) -> void:
	for mid in ["isles24", "known24"]:
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
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}, {"id": "purple", "name": "e", "ai": "recruit"}]
		var r: Dictionary = Autoplay.play(m, seats, 52, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var courts := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 52)
			if not _view_agrees(w, res) or not _conserved(w, res):
				ok = false
			courts += (res["events"] as Array).filter(func(e): return bool(e.get("courtGuard", false))).size()
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s under rules 20, five commanders: legal, replays, conserved, the report agrees (%d courts fled) %s" % [mid, courts, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/isles24.json", "seed": 5, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules == 20 and int(s.map.region_bonus["vane"]) == 3, "a new game plays rules 20, and on the Thousand Isles Great Vane pays 3")
	s.queue_free()
