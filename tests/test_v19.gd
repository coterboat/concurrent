## v1.9 (rules 18): Fortune's ledger kept exchange by exchange, so favours come back; and a
## war chest divided by the dice when several commanders take a fallen one's last lands.
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
	_luck_measured(report)
	_ledger(report)
	_old_rules(report)
	_spoils_split(report)
	_wars(report)
	_session(report, tree)
	Combat.use_rules(null)


func _map(rules: int = 18) -> Types.MapDef:
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
		if Array(real.players[pid].cards) != Array(seen.players[pid].cards) or real.players[pid].fortune != seen.players[pid].fortune:
			return false
	return true


func _luck_measured(report: Callable) -> void:
	## A battle pressed to the end: the exchanges' swings add up to the outcome less the odds
	## it began with. Over many battles the dice owe nobody anything (the swing averages out).
	var m := _map()
	Combat.use_rules(m)
	var exact := true
	var n := 0
	var total := 0.0
	var fell := 0
	var fell_luck := 0
	var detail := ""
	for sd in range(1, 260):
		var w: Types.World = H.paint(m, {"ridge": ["red", 9], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 7], "harbor": ["blue", 2]})
		w.round = 2
		var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("blue")], sd)
		var e: Dictionary = H.first(r["events"], Types.EVENT_INVASION)
		if e.is_empty() or not e.has("luck"):
			exact = false
			detail = "no luck on the event"
			continue
		n += 1
		total += float(e["luck"]) / 100.0
		if bool(e.get("fellBack", false)):
			fell += 1
			if int(e["luck"]) != 0:
				fell_luck += 1
			continue
		if (e.get("calls", []) as Array).any(func(c): return str(c.get("call", "")) != ""):
			continue ## reserves change the fight: not a telescoping sum
		var p: float = Combat.capture_rate(8, 7, m.battle, 0)
		var want: int = int(round(100.0 * ((1.0 if bool(e["attackerWon"]) else 0.0) - p)))
		if absi(int(e["luck"]) - want) > 1:
			exact = false
			detail = "seed %d: %d, want %d" % [sd, int(e["luck"]), want]
	report.call(exact and n > 200, "every assault carries the dice's swing; pressed to the end it is the outcome less the odds (%d battles) %s" % [n, detail])
	report.call(absf(total / n) < 0.06, "and it averages out: %.3f of a battle per assault" % (total / n))
	report.call(fell == 0 or fell_luck > 0, "a battle abandoned halfway still counts the exchanges fought (%d fell back, %d with a swing)" % [fell, fell_luck])


func _ledger(report: Callable) -> void:
	var m := _map()
	var w: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	w.players["red"].fortune = 0
	w.players["blue"].fortune = 0
	## half a battle of bad luck owes a favour, whether the battle was lost or abandoned
	var evs: Array = [{"kind": Types.EVENT_INVASION, "to": "gate", "attackerId": "red", "defenderId": "blue", "attackerSize": 9, "defenderSize": 5,
		"attackerWon": false, "winnerRemaining": 4, "fellBack": true, "luck": -55}]
	Fortune.upkeep(w, w, m, evs)
	var red: Types.PlayerState = w.players["red"]
	report.call(red.fortune == 1 and red.fortune_meter == 55 - Fortune.BATTLE_18 and H.all_of(evs, Types.EVENT_FORTUNE).size() == 1,
		"fall back after the dice rob you of half a battle and Fortune owes you (✦%d, %d towards the next)" % [red.fortune, red.fortune_meter])
	report.call(w.players["blue"].fortune_meter == Fortune.FLOOR_18, "the lucky side's ledger runs the other way, but only so far (%d)" % w.players["blue"].fortune_meter)
	## a rethrow isn't held against you: the event's swing already leaves the thrown-away exchange out
	var w2: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	w2.players["red"].fortune_meter = 30
	Fortune.upkeep(w2, w2, m, [{"kind": Types.EVENT_INVASION, "to": "gate", "attackerId": "red", "defenderId": "blue", "attackerSize": 9, "defenderSize": 5,
		"attackerWon": true, "winnerRemaining": 4, "luck": 0, "calls": [{"call": Combat.CALL_FORTUNE, "by": "red"}]}])
	report.call(w2.players["red"].fortune_meter == 30, "a battle won on a rethrow costs the ledger only what the dice that stood did (%d)" % w2.players["red"].fortune_meter)
	report.call(is_equal_approx(Fortune.meter_share(m, 25), 0.5) and Fortune.meter_share(m, -10) == 0.0, "the next star fills toward the next favour")


func _old_rules(report: Callable) -> void:
	## games begun before v1.9 keep the v1.8 ledger: no swing on the event, retreats ignored
	var m := _map(17)
	Combat.use_rules(m)
	var w: Types.World = H.paint(m, {"ridge": ["red", 9], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 7], "harbor": ["blue", 2]})
	w.round = 2
	var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("blue")], 7)
	var e: Dictionary = H.first(r["events"], Types.EVENT_INVASION)
	var w2: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	Fortune.upkeep(w2, w2, m, [{"kind": Types.EVENT_INVASION, "to": "gate", "attackerId": "red", "defenderId": "blue", "attackerSize": 9, "defenderSize": 5,
		"attackerWon": false, "winnerRemaining": 4, "fellBack": true}])
	report.call(not e.has("luck") and w2.players["red"].fortune_meter == 0 and Fortune.bar(m) == Fortune.BATTLE,
		"rules 17 (v1.8 games) replay with the old ledger: no swing recorded, a retreat ignored, the old bar")


func _spoils_split(report: Callable) -> void:
	## green's last two lands fall to red and to blue in the same round
	var m := _map()
	m.fortune = false
	Combat.use_rules(m)
	var split := 0
	var ok := true
	var detail := ""
	var uneven := false
	for sd in range(1, 80):
		var w: Types.World = H.paint(m, {"gate": ["red", 20], "ridge": ["red", 2], "beacon": ["red", 1], "mill": ["red", 1], "docks": ["blue", 20], "harbor": ["green", 1], "quarry": ["green", 1]})
		w.round = 3
		w.players["green"].cards = PackedStringArray(["sun@harbor", "moon@quarry", "star@mill", "sun@gate", "moon@docks"])
		var sheets := [H.sheet("red", [H.pkt("gate", "quarry", 19)]), H.sheet("blue", [H.pkt("docks", "harbor", 19)]), H.sheet("green")]
		var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd)
		var nw: Types.World = r["world"]
		if nw.players["green"].alive:
			continue
		var caps: Array = H.all_of(r["events"], Types.EVENT_CARDS_CAPTURED)
		if caps.size() < 2:
			continue
		split += 1
		var sp: Dictionary = (caps[0] as Dictionary).get("split", {})
		var got := 0
		var shares: Dictionary = sp.get("shares", {})
		var rolls: Dictionary = sp.get("rolls", {})
		for pid in ["red", "blue"]:
			got += int(shares.get(pid, -99))
			if nw.players[pid].cards.size() != int(shares.get(pid, -99)):
				ok = false
				detail = "seed %d: %s holds %d, share %s" % [sd, pid, nw.players[pid].cards.size(), shares]
		if got != 5 or nw.players["green"].cards.size() != 0:
			ok = false
			detail = "seed %d: shares %s" % [sd, shares]
		## in proportion to the throws: the higher throw never gets fewer cards
		var hi: String = "red" if int(rolls["red"]) > int(rolls["blue"]) else "blue"
		var lo: String = "blue" if hi == "red" else "red"
		if int(rolls["red"]) != int(rolls["blue"]) and int(shares[hi]) < int(shares[lo]):
			ok = false
			detail = "seed %d: rolls %s shares %s" % [sd, rolls, shares]
		if absi(int(shares["red"]) - int(shares["blue"])) >= 3:
			uneven = true
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
			detail = "seed %d: conservation or the report" % sd
		## and it replays
		if Hash.world_hash(Resolve.resolve_round(w, m, sheets, sd)["world"]) != Hash.world_hash(nw):
			ok = false
			detail = "seed %d: replay" % sd
	report.call(split > 30 and ok, "two commanders take the last lands at once: the dice divide the chest, every card handed out, in proportion to the throws (%d wars) %s" % [split, detail])
	report.call(uneven, "a big throw against a small one takes the lion's share")
	## a lone taker still takes it all, and rules 17 keep the old way (the last land's taker)
	var m17 := _map(17)
	m17.fortune = false
	var one := true
	for sd in range(1, 30):
		var w: Types.World = H.paint(m17, {"gate": ["red", 20], "ridge": ["red", 2], "beacon": ["red", 1], "mill": ["red", 1], "docks": ["blue", 20], "harbor": ["green", 1], "quarry": ["green", 1]})
		w.round = 3
		w.players["green"].cards = PackedStringArray(["sun@harbor", "moon@quarry", "star@mill"])
		var r: Dictionary = Resolve.resolve_round(w, m17, [H.sheet("red", [H.pkt("gate", "quarry", 19)]), H.sheet("blue", [H.pkt("docks", "harbor", 19)]), H.sheet("green")], sd)
		var caps: Array = H.all_of(r["events"], Types.EVENT_CARDS_CAPTURED)
		if caps.size() > 1 or (caps.size() == 1 and (caps[0] as Dictionary).has("split")):
			one = false
	report.call(one, "games begun before v1.9 hand the whole chest to the last land's taker, as they were played")


func _wars(report: Callable) -> void:
	for mid in ["known24", "world30"]:
		var m: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		m.battle = Combat.MODE_VOLLEYS
		m.scramble = true
		m.maneuvers = true
		m.dig_cap = 3
		m.rules = 18
		m.fire_line = true
		m.capitals = true
		m.fortune = true
		m.levee = 3
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(m, seats, 33, 0, true)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var gained := 0
		var splits := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 33)
			if not _view_agrees(w, res):
				ok = false
			gained += H.all_of(res["events"], Types.EVENT_FORTUNE).size()
			for e in H.all_of(res["events"], Types.EVENT_CARDS_CAPTURED):
				if (e as Dictionary).has("split"):
					splits += 1
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s under rules 18: legal, replays, the report agrees every round (%d favours paid, %d chests divided) %s" % [mid, gained, splits, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/known24.json", "seed": 5, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules == 18 and int(s.config["rules"]) == 18, "a new game plays rules 18")
	s.queue_free()
