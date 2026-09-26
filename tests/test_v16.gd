## v1.6 rules: the firing line (at most five men fire in a volley, even volleys are fired
## again), campaign cards that name a land (a free soldier there when you hold it), hands
## that follow the battle report, and last round's arrows as they really went.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const Cards := preload("res://engine/cards.gd")
const Validate := preload("res://engine/validate.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Rng := preload("res://engine/rng.gd")
const ViewEvents := preload("res://game/view_events.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_odds(report)
	_melee(report)
	_cards(report)
	_war(report)
	Combat.use_rules(null)


func _map16(path: String = "") -> Types.MapDef:
	var map: Types.MapDef = H.knife7() if path == "" else Types.MapDef.from_file(path)
	map.battle = Combat.MODE_VOLLEYS
	map.scramble = true
	map.maneuvers = true
	map.dig_cap = 3
	map.rules = 16
	map.fire_line = true
	map.wild_cards = false
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
	for pid in (result["world"] as Types.World).players.keys():
		if Array((result["world"] as Types.World).players[pid].cards) != Array(seen.players[pid].cards):
			return false
	return true


func _odds(report: Callable) -> void:
	Combat.use_rules(_map16())
	var even: float = Combat.capture_rate(12, 12, Combat.MODE_VOLLEYS)
	var one_up: float = Combat.capture_rate(7, 6, Combat.MODE_VOLLEYS)
	var big: float = Combat.capture_rate(25, 20, Combat.MODE_VOLLEYS)
	var two_to_one: float = Combat.capture_rate(12, 6, Combat.MODE_VOLLEYS)
	report.call(absf(even - 0.5) < 0.005 and one_up < 0.66 and big < 0.82 and two_to_one > 0.94,
		"the firing line: 12 v 12 even (%.1f%%), 7 v 6 %.1f%%, 25 v 20 %.1f%%, 12 v 6 %.1f%%" % [even * 100, one_up * 100, big * 100, two_to_one * 100])
	## the engine agrees with the odds it quotes
	var wins := 0
	var n := 4000
	for i in n:
		var r = Combat.invasion(7, 6, Rng.derive_stream(3, 1, "o|%d" % i), Combat.MODE_VOLLEYS)
		if r.attacker_won:
			wins += 1
	report.call(absf(float(wins) / n - one_up) < 0.025, "battles fought match the quoted odds: 7 v 6 won %.1f%% of %d" % [100.0 * wins / n, n])
	var r2 = Combat.invasion(14, 9, Rng.derive_stream(4, 1, "line"), Combat.MODE_VOLLEYS)
	var capped := true
	for roll in r2.rolls:
		if int(roll.get("fa", 99)) > Combat.LINE or int(roll.get("fd", 99)) > Combat.LINE:
			capped = false
	report.call(capped and (r2.rolls[0] as Dictionary).has("fa"), "every volley records its firing line, never more than five")
	Combat.use_rules(null)
	report.call(absf(Combat.capture_rate(12, 12, Combat.MODE_VOLLEYS) - 0.587) < 0.01, "old games keep the old odds (12 v 12 at 58.7%)")


func _melee(report: Callable) -> void:
	## 6 + 6 against 8 fights like one attack of 12: the same loss ratio
	var map := _map16()
	var holds := 0
	var ok := true
	for seed in range(1, 201):
		var w: Types.World = H.paint(map, {"ridge": ["red", 7], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 8], "harbor": ["blue", 2], "docks": ["green", 7], "quarry": ["green", 1]})
		w.round = 2
		for t in ["ridge", "docks"]:
			w.get_territory(t).garrison = 1
		var r: Dictionary = Resolve.resolve_round(w, map, [H.sheet("red", [H.pkt("ridge", "gate", 6)]), H.sheet("green", [H.pkt("docks", "gate", 6)]), H.sheet("blue")], seed)
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
		if (r["world"] as Types.World).get_territory("gate").owner == "blue":
			holds += 1
	Combat.use_rules(map)
	var single: float = 1.0 - Combat.capture_rate(12, 8, Combat.MODE_VOLLEYS)
	report.call(ok and absf(float(holds) / 200.0 - single) < 0.1, "a 6 + 6 melee on 8 is held %.0f%% of the time (one attack of 12: %.0f%%); conserved" % [100.0 * holds / 200.0, single * 100])


func _cards(report: Callable) -> void:
	var map := _map16("res://maps/known24.json")
	map.cards = true
	var lands: Array = Array(map.territory_ids())
	var kinds: Dictionary = Cards.deck_kinds(7, lands)
	var counts := {}
	for t in lands:
		counts[kinds[t]] = int(counts.get(kinds[t], 0)) + 1
	report.call(kinds.size() == lands.size() and int(counts.get("sun", 0)) == 8 and int(counts.get("moon", 0)) == 8, "every land has one card, the kinds dealt evenly (%s)" % str(counts))
	var taken := {}
	var dup := false
	for i in lands.size():
		var c: String = Cards.draw_land(7, 1 + i, "red", lands, taken)
		if taken.has(Cards.land(c)) or Cards.kind(c) != str(kinds[Cards.land(c)]):
			dup = true
		taken[Cards.land(c)] = true
	report.call(not dup, "a card nobody holds is drawn, of its land's kind, until the deck is out")
	report.call(Cards.is_set(["sun@a", "moon@b", "star@c"]) and Cards.is_set(["sun@a", "sun@b", "sun@c"]) and not Cards.is_set(["sun@a", "sun@b", "moon@c"]), "sets are made by the kinds on the cards")
	var hand := PackedStringArray(["sun@firth", "sun@moor", "sun@cairn", "moon@vale", "star@keep"])
	var pick: PackedStringArray = Cards.best_set(hand, {"vale": true, "keep": true})
	report.call(Array(pick).has("moon@vale") and Array(pick).has("star@keep"), "the best set is the one that brings free soldiers (%s)" % ", ".join(pick))
	## turning in: +value recruits, and a free soldier on each held land named
	var w := Types.World.empty_from_map(map)
	w.round = 3
	w.players["red"] = H.player("red")
	w.players["blue"] = H.player("blue")
	var red_lands: Array = lands.slice(0, 12)
	for t in lands:
		w.set_hex(str(t), "red" if red_lands.has(t) else "blue", 3)
	var mine: String = str(red_lands[0])
	var theirs: String = str(lands[20])
	w.players["red"].cards = PackedStringArray(["sun@" + mine, "moon@" + theirs, "star@" + str(red_lands[1])])
	var sh := H.sheet("red")
	sh.cash_set = w.players["red"].cards.duplicate()
	var r: Dictionary = Resolve.resolve_round(w, map, [sh, H.sheet("blue")], 11)
	var ev: Dictionary = H.first(r["events"], Types.EVENT_SET_CASHED)
	var nw: Types.World = r["world"]
	report.call(Array(ev.get("lands", [])) == [mine, str(red_lands[1])] and nw.get_territory(mine).held() >= 4 and nw.get_territory(theirs).owner == "blue", "a card naming a land you hold puts a free soldier there (%s)" % str(ev.get("lands", [])))
	report.call(_conserved(w, r) and _view_agrees(w, r), "turn-ins are conserved and the report's hands agree with the world")
	## the free soldier can march the same round (the sheet's projection includes him)
	var sh2 := H.sheet("red", [H.pkt(mine, str(MapLib.neighbors(map, mine)[0]), 3)])
	sh2.cash_set = PackedStringArray(["sun@" + mine, "moon@" + theirs, "star@" + str(red_lands[1])])
	var nb: String = str(MapLib.neighbors(map, mine)[0])
	var legal: bool = Validate.validate_sheet(w, map, sh2).is_empty()
	report.call(legal or w.get_territory(nb).owner == "red", "the free soldier counts toward what can march this round")


func _war(report: Callable) -> void:
	for mid in ["known24", "world30"]:
		var map := _map16("res://maps/%s.json" % mid)
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "hask"},
			{"id": "green", "name": "c", "ai": "varek"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(map, seats, 16)
		var named := 0
		var bare := 0
		for pid in (r["world"] as Types.World).players.keys():
			for c in (r["world"] as Types.World).players[pid].cards:
				if Cards.land(c) != "":
					named += 1
				else:
					bare += 1
		report.call(r["ok"] and str(r["winner"]) != "" and bare == 0, "%s under v1.6 rules: legal, finished, every card names a land (%d in hand) (%s)" % [mid, named, " ".join(r["violations"])])
		## replays to the same world, and the view agrees every round
		var w: Types.World = Types.World.from_dict(r["setup"])
		var view_ok := true
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for d in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(d))
			var res: Dictionary = Resolve.resolve_round(w, map, sheets, 16)
			if not _view_agrees(w, res):
				view_ok = false
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, map, r["maneuvers"][k])
		report.call(view_ok and Hash.world_hash(w) == Hash.world_hash(r["world"]), "%s: the war replays, and the report (hands included) agrees every round" % mid)
