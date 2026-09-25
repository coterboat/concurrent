## Battle calls (v1.2): press on, throw in the reserves, fall back.
## The round pauses at a live call and replays exactly once the call is on the sheet.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Autoplay := preload("res://engine/autoplay.gd")

const V := "volleys"


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	map.battle = V
	_hold_is_v11(report, map)
	_pause_and_resume(report, map)
	_reserves(report, map)
	_fall_back(report, map)
	_cut_off(report, map)
	_doctrine(report)
	_sheet_roundtrip(report)
	_wars(report)


func _board(map: Types.MapDef) -> Types.World:
	## Red's Ridge is dug in with 12 mobile; 6 go for the Gate, 6 wait at home.
	var w: Types.World = H.paint(map, {
		"ridge": ["red", 12], "beacon": ["red", 3], "mill": ["red", 2],
		"gate": ["blue", 9], "harbor": ["blue", 2], "docks": ["green", 3], "quarry": ["green", 3],
	})
	w.round = 2
	w.get_territory("ridge").garrison = 1
	return w


func _attack(stance: String, n: int = 6) -> Types.Sheet:
	var p: Types.Packet = H.pkt("ridge", "gate", n)
	p.stance = stance
	return H.sheet("red", [p])


func _invasion(events: Array) -> Dictionary:
	for e in events:
		if str(e["kind"]) == Types.EVENT_INVASION:
			return e
	return {}


func _conserved(before: Types.World, result: Dictionary) -> bool:
	var evs: Array = result["events"]
	var expected: int = MapLib.sum_armies(before) + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)
	return MapLib.sum_armies(result["world"]) == expected


func _view_agrees(before: Types.World, result: Dictionary) -> bool:
	var seen: Types.World = ViewEvents.apply_through(before, result["events"], (result["events"] as Array).size() - 1)
	var real: Types.World = result["world"]
	for t in real.territories.keys():
		var a: Types.TerritoryState = real.get_territory(t)
		var b: Types.TerritoryState = seen.get_territory(t)
		if a.owner != b.owner or a.armies != b.armies or a.garrison != b.garrison:
			return false
	return true


func _hold_is_v11(report: Callable, map: Types.MapDef) -> void:
	## No stance, no calls: exactly the v1.1 battle, roll for roll.
	var ok := true
	for seed in range(1, 40):
		var w := _board(map)
		var r: Dictionary = Resolve.resolve_round(w, map, [_attack("")], seed)
		var e: Dictionary = _invasion(r["events"])
		var f = Combat.invasion(6, 9, Rng.derive_stream(seed, 2, "invasion|gate|red|ridge"), V)
		if e.is_empty() or JSON.stringify(e["rolls"]) != JSON.stringify(f.rolls) or bool(e["attackerWon"]) != f.attacker_won or int(e["winnerRemaining"]) != f.winner_remaining or e.has("calls"):
			ok = false
	report.call(ok, "standing order 'to the last man' fights the v1.1 battle, volley for volley")


func _pause_and_resume(report: Callable, map: Types.MapDef) -> void:
	var w := _board(map)
	var sheet := _attack(Combat.STANCE_HOLD)
	var r: Dictionary = Resolve.resolve_round(w, map, [sheet], 7, ["red"])
	var p: Dictionary = r.get("pending", {})
	report.call(not p.is_empty() and str(p["key"]) == "invasion|gate|red|ridge" and int(p["rolls"]) == 3,
		"a watched battle pauses after the opening exchange (%s)" % JSON.stringify(p))
	report.call(int(p.get("reserves", 0)) == 6 and str(p.get("refuge", "")) == "ridge",
		"the call offers Ridge's 6 reserves and Ridge as the refuge")
	var e: Dictionary = _invasion(r["events"])
	report.call(bool(e.get("pending", false)) and (e["rolls"] as Array).size() == 3, "the paused battle is on the log with its three volleys")
	## press on until it's over: every re-run keeps the log so far
	var prefix_ok := true
	var guard := 0
	var prev: Array = r["events"]
	while r.has("pending") and guard < 40:
		guard += 1
		var list: Array = sheet.calls.get(str(r["pending"]["key"]), [])
		list.append(Combat.CALL_PRESS)
		sheet.calls[str(r["pending"]["key"])] = list
		r = Resolve.resolve_round(w, map, [sheet], 7, ["red"])
		var now: Array = r["events"]
		for i in prev.size() - 1:
			if JSON.stringify(prev[i]) != JSON.stringify(now[i]):
				prefix_ok = false
		var pe: Dictionary = _invasion(now)
		var pr: Array = pe["rolls"]
		var old_rolls: Array = _invasion(prev)["rolls"]
		if JSON.stringify(pr.slice(0, old_rolls.size())) != JSON.stringify(old_rolls):
			prefix_ok = false
		prev = now
	report.call(not r.has("pending") and prefix_ok, "pressing on resumes the same battle; nothing already shown changes (%d calls)" % guard)
	var replay: Dictionary = Resolve.resolve_round(w, map, [Types.Sheet.from_dict(sheet.to_dict())], 7)
	report.call(Hash.world_hash(replay["world"]) == Hash.world_hash(r["world"]), "the saved sheet replays the called battle to the same world")
	var plain: Dictionary = Resolve.resolve_round(w, map, [_attack(Combat.STANCE_HOLD)], 7)
	report.call(Hash.world_hash(plain["world"]) == Hash.world_hash(r["world"]), "pressing every time = fighting to the last man")


func _reserves(report: Callable, map: Types.MapDef) -> void:
	var ok_all := true
	var joined := 0
	for seed in range(1, 30):
		var w := _board(map)
		var sheet := _attack(Combat.STANCE_HOLD)
		sheet.calls["invasion|gate|red|ridge"] = [Combat.CALL_RESERVES]
		var r: Dictionary = Resolve.resolve_round(w, map, [sheet], seed)
		var e: Dictionary = _invasion(r["events"])
		if (e["rolls"] as Array).size() <= 3:
			continue ## decided in the opening exchange: no call was made
		joined += 1
		var rolls: Array = e["rolls"]
		var third: Dictionary = rolls[2]
		var fourth: Dictionary = rolls[3]
		var a_after3: int = int(third["sa"]) - (1 if str(third["w"]) == "b" else 0)
		if int(e.get("reservesAdded", 0)) != 6 or int(fourth["sa"]) != a_after3 + 6:
			ok_all = false
		var ridge: Types.TerritoryState = (r["world"] as Types.World).get_territory("ridge")
		if ridge.owner != "red" or ridge.armies != 0 or ridge.garrison < 1:
			ok_all = false
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok_all = false
	report.call(ok_all and joined > 10, "reserves: Ridge's 6 march in after the opening, Ridge keeps its dug-in man, armies conserved, replay agrees (%d battles)" % joined)


func _fall_back(report: Callable, map: Types.MapDef) -> void:
	var ok_all := true
	var n := 0
	for seed in range(1, 30):
		var w := _board(map)
		var sheet := _attack(Combat.STANCE_HOLD)
		sheet.calls["invasion|gate|red|ridge"] = [Combat.CALL_FALL_BACK]
		var r: Dictionary = Resolve.resolve_round(w, map, [sheet], seed)
		var e: Dictionary = _invasion(r["events"])
		if not bool(e.get("fellBack", false)):
			## only if the opening exchange already settled it
			var last: Dictionary = (e["rolls"] as Array)[-1]
			if (e["rolls"] as Array).size() > 3 or (int(last["sa"]) > 1 and int(last["sd"]) > 1):
				ok_all = false
			continue
		n += 1
		var after: Types.World = r["world"]
		var left: int = int(e.get("attackerLeft", -1))
		if not bool(e.get("fellBack", false)) or bool(e["attackerWon"]) or str(e.get("refuge", "")) != "ridge":
			ok_all = false
		## 6 stayed home, the survivors join them (digging in adds to the garrison, not here)
		if after.get_territory("ridge").armies != 6 + left or left < 1:
			ok_all = false
		if after.get_territory("gate").owner != "blue":
			ok_all = false
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok_all = false
	report.call(ok_all and n > 10, "fall back: survivors return to Ridge, the Gate holds, armies conserved, replay agrees (%d battles)" % n)


func _cut_off(report: Callable, map: Types.MapDef) -> void:
	## Blue takes Docks (sorted first) while Red's Docks army fights for the Harbor:
	## no friendly land borders the Harbor, so Red cannot fall back.
	var w: Types.World = H.paint(map, {
		"ridge": ["red", 2], "beacon": ["red", 2], "mill": ["red", 2],
		"docks": ["red", 10], "quarry": ["blue", 14], "harbor": ["green", 9], "gate": ["green", 2],
	})
	w.round = 2
	var red := H.sheet("red", [H.pkt("docks", "harbor", 9)])
	var blue := H.sheet("blue", [H.pkt("quarry", "docks", 13)])
	var found := false
	for seed in range(1, 20):
		var r: Dictionary = Resolve.resolve_round(w, map, [red, blue], seed, ["red"])
		if not r.has("pending"):
			continue
		var docks_fell := false
		for e in r["events"]:
			if str(e["kind"]) == Types.EVENT_OCCUPIED and str(e["terrId"]) == "docks" and str(e["playerId"]) == "blue":
				docks_fell = true
		if docks_fell:
			found = str(r["pending"]["refuge"]) == ""
			## a recorded fall back with nowhere to go is a press
			red.calls = {str(r["pending"]["key"]): [Combat.CALL_FALL_BACK]}
			var r2: Dictionary = Resolve.resolve_round(w, map, [red, blue], seed)
			var e2: Dictionary = {}
			for e in r2["events"]:
				if str(e["kind"]) == Types.EVENT_INVASION and str(e["to"]) == "harbor":
					e2 = e
			found = found and not e2.is_empty() and not bool(e2.get("fellBack", false)) and not e2.has("calls")
			red.calls = {}
			break
	report.call(found, "cut off: with home lost and no friendly neighbour, there is no falling back")


func _doctrine(report: Callable) -> void:
	report.call(Combat.doctrine(Combat.STANCE_HOLD, 2, 9, 6, true) == Combat.CALL_PRESS, "to the last man: presses even at 2 vs 9")
	report.call(Combat.doctrine(Combat.STANCE_CAREFUL, 2, 9, 6, true) == Combat.CALL_FALL_BACK, "careful: falls back at 2 vs 9")
	report.call(Combat.doctrine(Combat.STANCE_CAREFUL, 2, 9, 6, false) == Combat.CALL_PRESS, "careful, cut off: fights on")
	report.call(Combat.doctrine(Combat.STANCE_BOLD, 5, 6, 4, true) == Combat.CALL_RESERVES, "all in: calls the reserves at 5 vs 6")
	report.call(Combat.doctrine(Combat.STANCE_BOLD, 9, 2, 4, true) == Combat.CALL_PRESS, "all in: no reserves needed at 9 vs 2")
	report.call(Combat.doctrine(Combat.STANCE_JUDGMENT, 4, 6, 5, true) == Combat.CALL_RESERVES, "judgment: reserves when they swing it (4+5 vs 6)")
	report.call(Combat.doctrine(Combat.STANCE_JUDGMENT, 2, 9, 0, true) == Combat.CALL_FALL_BACK, "judgment: falls back when it's hopeless")
	report.call(Combat.doctrine(Combat.STANCE_JUDGMENT, 6, 5, 0, true) == Combat.CALL_PRESS, "judgment: presses a winning fight")


func _sheet_roundtrip(report: Callable) -> void:
	var s := _attack(Combat.STANCE_BOLD)
	s.calls["invasion|gate|red|ridge"] = ["p", "r", "f"]
	var back: Types.Sheet = Types.Sheet.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	report.call((back.packets[0] as Types.Packet).stance == Combat.STANCE_BOLD and JSON.stringify(back.calls) == JSON.stringify(s.calls),
		"stance and live calls survive the save file")
	var old := _attack("")
	report.call(not old.to_dict().has("calls") and not (old.to_dict()["packets"][0] as Dictionary).has("stance"), "v1.1 sheets serialize exactly as before")


func _wars(report: Callable) -> void:
	## Whole wars with every temperament: legal, conserved, and the battle replay
	## lands on the engine's world after every round.
	var total_f := 0
	for mid in ["known24", "world30"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		map.battle = V
		var seats := [{"id": "red", "name": "a", "ai": "ysolde"}, {"id": "blue", "name": "b", "ai": "quill"},
			{"id": "green", "name": "c", "ai": "varek"}, {"id": "gold", "name": "d", "ai": "hask"}]
		var r: Dictionary = Autoplay.play(map, seats, 77)
		report.call(r["ok"] and str(r["winner"]) != "", "%s: four temperaments at war — legal, conserved, finished (%s)" % [mid, " ".join(r["violations"])])
		var calls := {"r": 0, "f": 0, "p": 0}
		var view_ok := true
		var w: Types.World = Types.World.from_dict(r["setup"])
		for round_sheets in r["sheets"]:
			var sheets: Array = []
			for d in round_sheets:
				sheets.append(Types.Sheet.from_dict(d))
			var res: Dictionary = Resolve.resolve_round(w, map, sheets, 77)
			for e in res["events"]:
				for c in e.get("calls", []):
					calls[str(c["call"])] += 1
			if not _view_agrees(w, res):
				view_ok = false
			w = res["world"]
		report.call(calls["r"] + calls["f"] > 0, "%s: officers made %d reserve and %d fall-back calls" % [mid, calls["r"], calls["f"]])
		total_f += calls["f"]
		report.call(view_ok, "%s: the battle replay agrees with the engine every round" % mid)
	report.call(total_f > 0, "somebody fell back somewhere (%d)" % total_f)
