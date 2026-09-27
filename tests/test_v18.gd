## v1.8 capitals: every commander keeps a seat of government. It pays the treasury, fires
## the fortress's longer line and digs one deeper; when it falls the captor plunders half
## the fallen commander's cards and levies three in the city, and a new capital is named
## at once, which its commander may move the round after.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const MapLib := preload("res://engine/map.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const Setup := preload("res://engine/setup.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Capitals := preload("res://engine/capitals.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Session := preload("res://game/core/session.gd")
const Fortune := preload("res://engine/fortune.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_founding(report)
	_treasury_and_walls(report)
	_fall(report)
	_move(report)
	_supply_home(report)
	_old_worlds(report)
	_wars(report)
	_session(report, tree)
	_fortune_rules(report)
	_fortune_live(report)
	_fortune_wars(report)
	Combat.use_rules(null)


func _map(path: String = "") -> Types.MapDef:
	var m: Types.MapDef = H.knife7() if path == "" else Types.MapDef.from_file(path)
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.maneuvers = true
	m.dig_cap = 3
	m.rules = 17
	m.fire_line = true
	m.wild_cards = false
	m.capitals = true
	return m


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
		var ca: Array = Array((result["world"] as Types.World).players[pid].cards)
		var cb: Array = Array(seen.players[pid].cards)
		ca.sort()
		cb.sort()
		if ca != cb:
			return false
	return true


func _founding(report: Callable) -> void:
	var m := _map("res://maps/known24.json")
	var seats := [{"id": "red", "name": "a"}, {"id": "blue", "name": "b"}, {"id": "green", "name": "c"}]
	var w: Types.World = Setup.deal(m, seats, 5)
	var mine: Array = Array(MapLib.player_territory_ids(w, "red"))
	mine.sort()
	var pick: String = str(mine[-1])
	var evs: Array = []
	Setup.apply_opening(w, m, {}, {"red": pick, "blue": "nowhere"}, evs)
	var ok := true
	for pid in ["red", "blue", "green"]:
		var c: String = (w.players[pid] as Types.PlayerState).capital
		if c == "" or w.get_territory(c).owner != pid:
			ok = false
	report.call(ok and w.players["red"].capital == pick and evs.size() == 3,
		"every commander names a capital at deployment: red chose %s; a choice that isn't yours falls back to the auto pick (blue: %s)" % [pick, w.players["blue"].capital])
	## the auto pick sits deep in your own lands
	var auto: String = Capitals.auto_pick(w, m, "green")
	var friends := 0
	for n in MapLib.neighbors(m, auto):
		if w.get_territory(n).owner == "green":
			friends += 1
	var best := 0
	for t in MapLib.player_territory_ids(w, "green"):
		var f := 0
		for n in MapLib.neighbors(m, t):
			if w.get_territory(n).owner == "green":
				f += 1
		best = maxi(best, f)
	report.call(friends == best, "the auto pick has the most of its own lands around it (%s: %d of %d)" % [auto, friends, best])
	## lands claimed in turn: the first claim is the capital
	var dw: Types.World = Autoplay.draft_deal(m, [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"}, {"id": "green", "name": "c", "ai": "hask"}], 9, {"red": "general", "blue": "veteran", "green": "hask"})
	var claimed := true
	for pid in ["red", "blue", "green"]:
		var c2: String = (dw.players[pid] as Types.PlayerState).capital
		if c2 == "" or dw.get_territory(c2).owner != pid:
			claimed = false
	var solo: Types.World = Setup.draft_world(m, seats, 3)
	solo.set_hex("keep", "red", 1)
	Capitals.claimed(solo, m, "red", "keep")
	solo.set_hex("peak", "red", 1)
	Capitals.claimed(solo, m, "red", "peak")
	report.call(claimed and solo.players["red"].capital == "keep", "claiming in turn, your first claim is your capital")
	## off is off: no capital, and the world serializes as it always did
	var off := _map("res://maps/known24.json")
	off.capitals = false
	var w2: Types.World = Setup.deal(off, seats, 5)
	Setup.apply_opening(w2, off, {}, {"red": pick})
	report.call(w2.players["red"].capital == "" and not JSON.stringify(w2.to_dict()).contains("capital"), "with capitals off nobody has one, and the world's record has no trace of them")


func _treasury_and_walls(report: Callable) -> void:
	var m := _map()
	var w: Types.World = H.paint(m, {"ridge": ["red", 4], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 3], "harbor": ["blue", 2]})
	var before: int = Income.income_of(w, m, "red")
	w.players["red"].capital = "ridge"
	var with_cap: int = Income.income_of(w, m, "red")
	w.get_territory("ridge").owner = "blue"
	var lost: int = Income.income_of(w, m, "red")
	w.get_territory("ridge").owner = "red"
	report.call(with_cap == before + 2 and lost < with_cap, "the capital pays two recruits a round while you hold it (%d, %d with it, %d without)" % [before, with_cap, lost])
	Combat.use_rules(m)
	report.call(MapLib.defender_bonus(w, m, "ridge") == 1 and MapLib.defender_bonus(w, m, "mill") == 0, "a capital's defenders fire the fortress's longer line")
	report.call(Income.garrison_cap(w, m, "ridge") == mini(3, 1 + 2) + 1, "and one more man may dig in there (%d)" % Income.garrison_cap(w, m, "ridge"))
	var open_rate: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, 0)
	var cap_rate: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, MapLib.defender_bonus(w, m, "ridge"))
	report.call(cap_rate < open_rate - 0.1, "ten storm a capital held by ten at %.0f%%, open ground %.0f%%" % [cap_rate * 100.0, open_rate * 100.0])


func _fall(report: Callable) -> void:
	var m := _map()
	Combat.use_rules(m)
	var took := 0
	var ok := true
	var detail := ""
	for s in 30:
		var w: Types.World = H.paint(m, {"gate": ["red", 2], "ridge": ["red", 3], "beacon": ["red", 1], "mill": ["red", 1], "harbor": ["blue", 14], "docks": ["blue", 1]})
		w.round = 3
		w.players["red"].capital = "gate"
		w.players["blue"].capital = "docks"
		w.players["red"].cards = PackedStringArray(["sun@ridge", "moon@quarry", "star@mill"])
		w.get_territory("harbor").garrison = 1
		var r: Dictionary = Resolve.resolve_round(w, m, [H.sheet("blue", [H.pkt("harbor", "gate", 14)]), H.sheet("red")], 40 + s)
		var nw: Types.World = r["world"]
		if not r["errors"].is_empty():
			ok = false
			detail = " ".join(r["errors"])
			continue
		if nw.get_territory("gate").owner != "blue":
			continue
		took += 1
		var ev: Dictionary = H.first(r["events"], Types.EVENT_CAPITAL_TAKEN)
		var red: Types.PlayerState = nw.players["red"]
		var blue: Types.PlayerState = nw.players["blue"]
		if ev.is_empty() or str(ev["by"]) != "blue" or int(ev["levy"]) != 3 or (ev["cards"] as Array).size() != 2:
			ok = false
			detail = str(ev)
		if red.cards.size() != 1 or blue.cards.size() < 2 or red.capital == "gate" or red.capital == "" or nw.get_territory(red.capital).owner != "red" or not red.capital_free:
			ok = false
			detail = "red %s %s free %s, blue %s" % [red.capital, red.cards, red.capital_free, blue.cards]
		if not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
			detail = "conservation or view"
	report.call(took > 20 and ok, "a fallen capital is plundered: half the cards and a levy of three; a new capital stands at once (%d falls) %s" % [took, detail])


func _move(report: Callable) -> void:
	var m := _map()
	var w: Types.World = H.paint(m, {"ridge": ["red", 3], "beacon": ["red", 2], "mill": ["red", 1], "gate": ["blue", 5], "harbor": ["blue", 2]})
	w.round = 4
	w.players["red"].capital = "ridge"
	w.players["red"].capital_free = true
	w.players["blue"].capital = "harbor"
	var sh := H.sheet("red")
	sh.capital = "beacon"
	var r: Dictionary = Resolve.resolve_round(w, m, [sh, H.sheet("blue")], 7)
	var nw: Types.World = r["world"]
	report.call(r["errors"].is_empty() and nw.players["red"].capital == "beacon" and not nw.players["red"].capital_free,
		"the round after a fall, the commander may move the new capital (%s)" % nw.players["red"].capital)
	var r2: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red"), H.sheet("blue")], 7)
	report.call(not (r2["world"] as Types.World).players["red"].capital_free and (r2["world"] as Types.World).players["red"].capital == "ridge",
		"or keep it; either way the choice was that round's")
	var bad := H.sheet("blue")
	bad.capital = "gate"
	report.call(not Validate.validate_sheet(w, m, bad).is_empty(), "a capital that still stands cannot be moved")
	var bad2 := H.sheet("red")
	bad2.capital = "gate"
	report.call(not Validate.validate_sheet(w, m, bad2).is_empty(), "nor can it be moved onto someone else's land")
	var rt := Types.Sheet.from_dict(sh.to_dict())
	report.call(rt.capital == "beacon", "the choice is saved with the sheet")


func _supply_home(report: Callable) -> void:
	## on a supply map the road home runs to the capital, not merely to your largest body
	var m := _map("res://maps/isles24.json")
	var w: Types.World = H.paint(m, {
		"vanetor": ["red", 2], "vanefell": ["red", 2], "vaneholt": ["red", 2], "vanemoor": ["red", 2],
		"thalecliff": ["red", 4], "thaleharbour": ["blue", 3], "thalewood": ["blue", 2]})
	w.players["red"].capital = "thalecliff"
	var fed: Dictionary = MapLib.supplied_ids(w, m, "red")
	report.call(fed.has("thalecliff") and not fed.has("vaneholt"), "with capitals, supply runs from the capital: the four lands on Great Vane are the ones cut off")
	w.players["red"].capital = ""
	var fed2: Dictionary = MapLib.supplied_ids(w, m, "red")
	report.call(fed2.size() == 4 and not fed2.has("thalecliff"), "with no capital standing, the largest body is home, as in v1.7")


func _old_worlds(report: Callable) -> void:
	## a world from before v1.8 hashes exactly as it did
	var m := _map()
	var w: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	var d: Dictionary = w.to_dict()
	report.call(not (d["players"]["red"] as Dictionary).has("capital") and Types.World.from_dict(d).players["red"].capital == "", "worlds without capitals serialize and hash as before")


func _wars(report: Callable) -> void:
	for mid in ["known24", "world30", "marches18"]:
		var m := _map("res://maps/%s.json" % mid)
		m.cards = m.cards or mid != "marches18"
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"}]
		if mid != "marches18":
			seats.append({"id": "green", "name": "c", "ai": "hask"})
			seats.append({"id": "gold", "name": "d", "ai": "quill"})
		var r: Dictionary = Autoplay.play(m, seats, 18)
		var fell := 0
		var w: Types.World = Types.World.from_dict(r["setup"])
		var view_ok := true
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 18)
			fell += H.all_of(res["events"], Types.EVENT_CAPITAL_TAKEN).size()
			if not _view_agrees(w, res):
				view_ok = false
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and view_ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s with capitals: legal, replays, the report agrees every round (%d capitals fell) %s" % [mid, fell, " ".join(r["violations"])])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/known24.json", "seed": 12, "length": "short", "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"},
		{"id": "green", "name": "Quill", "kind": "ai", "ai": "quill"}]})
	report.call(s.map.capitals and s.capital_choosable(), "new games have capitals, and deployment asks where yours stands")
	var mine: Array = Array(MapLib.player_territory_ids(s.world, "red"))
	mine.sort()
	var want: String = str(mine[0])
	var err: String = s.set_capital(want)
	report.call(err == "" and s.capital_shown("red") == want and s.capital_shown("blue") == "", "you name it; the others' stay sealed until deployment ends")
	report.call(s.set_capital(str(MapLib.player_territory_ids(s.world, "blue")[0])) != "", "a rival's land cannot be your capital")
	s.auto_deploy()
	s.lock()
	var guard := 0
	while s.phase == Session.Phase.CINEMA and guard < 5:
		guard += 1
		s.cinema_done()
	var ok := true
	for pid in ["red", "blue", "green"]:
		var c: String = s.world.players[pid].capital
		if c == "" or s.world.get_territory(c).owner != pid:
			ok = false
	report.call(ok and s.world.players["red"].capital == want and not s.capital_choosable(), "after deployment every capital stands, yours where you put it")
	## the luck ledger: each one-on-one battle against the odds quoted as it began
	var inv := {"kind": Types.EVENT_INVASION, "to": "keep", "attackerId": "red", "defenderId": "blue", "attackerSize": 12, "defenderSize": 12, "attackerWon": true, "winnerRemaining": 3, "rolls": []}
	s._luck([inv], s.world)
	var lr: Dictionary = s.luck_of("red")
	var lb: Dictionary = s.luck_of("blue")
	var p: float = Combat.capture_rate(12, 12, s.map.battle, MapLib.defender_bonus(s.world, s.map, "keep"))
	report.call(int(lr["n"]) == 1 and absf(float(lr["expected"]) - p) < 0.001 and absf(float(lr["swing"]) - (1.0 - p)) < 0.001 and absf(float(lb["swing"]) + (1.0 - p)) < 0.001,
		"the luck ledger: winning a %.0f%% battle is worth %+.2f to the winner and %+.2f to the loser" % [p * 100.0, float(lr["swing"]), float(lb["swing"])])
	s.queue_free()


# ---------------------------------------------------------------- v1.8 Fortune

func _fmap() -> Types.MapDef:
	var m := _map()
	m.fortune = true
	return m


func _fortune_rules(report: Callable) -> void:
	report.call(Fortune.bad_for(9, 9, 6, 9) == "a" and Fortune.bad_for(9, 9, 9, 6) == "d" and Fortune.bad_for(9, 9, 8, 8) == "" and Fortune.bad_for(2, 9, 0, 8) == "a",
		"a bad exchange: it ended your battle, or cost you two more men than them")
	Combat.use_rules(_fmap())
	report.call(Fortune.doctrine("a", 10, 10, 7, 10, 0, Combat.MODE_VOLLEYS) and not Fortune.doctrine("a", 3, 12, 1, 12, 0, Combat.MODE_VOLLEYS),
		"the AI calls on Fortune when an exchange swung a real fight, not to save a lost cause")
	## the ledger: losing a battle you were 90% to win owes you most of a favour
	var m := _fmap()
	var w: Types.World = H.paint(m, {"ridge": ["red", 3], "gate": ["blue", 3]})
	w.players["red"].fortune = 1
	var evs: Array = [{"kind": Types.EVENT_INVASION, "to": "gate", "attackerId": "red", "defenderId": "blue", "attackerSize": 14, "defenderSize": 5, "attackerWon": false, "winnerRemaining": 1}]
	var p: float = Combat.capture_rate(14, 5, Combat.MODE_VOLLEYS, 0)
	Fortune.upkeep(w, w, m, evs)
	var red: Types.PlayerState = w.players["red"]
	report.call(red.fortune == 2 and red.fortune_meter == int(round(100.0 * p)) - Fortune.BATTLE and H.all_of(evs, Types.EVENT_FORTUNE).size() == 1,
		"lose a %.0f%% battle and Fortune owes you: ✦%d, %d hundredths towards the next" % [p * 100.0, red.fortune, red.fortune_meter])
	report.call(w.players["blue"].fortune_meter < 0, "and the lucky defender's ledger runs the other way (%d)" % w.players["blue"].fortune_meter)
	## nobody holds more than three
	red.fortune = 3
	red.fortune_meter = 70
	Fortune.upkeep(w, w, m, evs.duplicate(true))
	report.call(red.fortune == 3 and red.fortune_meter <= Fortune.BATTLE, "no more than three in hand")
	var d: Dictionary = H.paint(_map(), {"ridge": ["red", 3]}).to_dict()
	report.call(not JSON.stringify(d).contains("fortune"), "worlds without Fortune serialize as before")


func _fortune_live(report: Callable) -> void:
	## blue (a human, watching) defends; find a battle whose first exchange goes badly for blue
	var m := _fmap()
	Combat.use_rules(m)
	var found := -1
	var pend: Dictionary = {}
	var w: Types.World
	var sheets: Array = []
	for sd in range(1, 400):
		w = H.paint(m, {"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 10], "harbor": ["blue", 2]})
		w.round = 2
		w.get_territory("ridge").garrison = 1
		w.get_territory("gate").garrison = 1
		for pid in ["red", "blue"]:
			w.players[pid].fortune = 1
		var ra := H.sheet("red", [H.pkt("ridge", "gate", 11)])
		ra.calls = {}
		sheets = [ra, H.sheet("blue")]
		var r: Dictionary = Resolve.resolve_round(w, m, sheets, sd, ["blue"])
		if r.has("pending") and bool(r["pending"].get("fortune", false)) and str(r["pending"]["chooser"]) == "blue":
			found = sd
			pend = r["pending"]
			break
	report.call(found > 0 and str(pend["side"]) == "d", "a watching defender is asked after a bad exchange (seed %d)" % found)
	if found < 0:
		return
	## blue calls on Fortune
	(sheets[1] as Types.Sheet).calls[str(pend["key"])] = [Combat.CALL_FORTUNE]
	var r2: Dictionary = Resolve.resolve_round(w, m, sheets, found, ["blue"])
	while r2.has("pending"):
		var pk: Dictionary = r2["pending"]
		var chooser: String = str(pk.get("chooser", pk["attacker"]))
		var sh: Types.Sheet = sheets[0] if chooser == "red" else sheets[1]
		var lst: Array = sh.calls.get(str(pk["key"]), [])
		lst.append(Combat.CALL_STAND if bool(pk.get("fortune", false)) else Combat.CALL_PRESS)
		sh.calls[str(pk["key"])] = lst
		r2 = Resolve.resolve_round(w, m, sheets, found, ["blue"])
	var inv: Dictionary = H.first(r2["events"], Types.EVENT_INVASION)
	var fcalls: Array = (inv.get("calls", []) as Array).filter(func(c): return str(c.get("call", "")) == Combat.CALL_FORTUNE)
	var nw: Types.World = r2["world"]
	report.call(fcalls.size() == 1 and str(fcalls[0]["by"]) == "blue" and int(fcalls[0]["d"]) == int(pend["d0"]) and nw.players["blue"].fortune <= 1,
		"the favour is spent and the exchange thrown again from %d v %d" % [int(pend["a0"]), int(pend["d0"])])
	## replayed without anyone watching, the recorded choices give the same war
	var again: Dictionary = Resolve.resolve_round(w, m, sheets, found)
	report.call(not again.has("pending") and Hash.world_hash(again["world"]) == Hash.world_hash(nw) and _conserved(w, r2) and _view_agrees(w, r2),
		"the battle replays exactly from the recorded calls; conserved, and the report agrees")
	var seen: Types.World = ViewEvents.apply_through(w, r2["events"], (r2["events"] as Array).size() - 1)
	report.call(seen.players["blue"].fortune == nw.players["blue"].fortune, "the report's count of favours follows the battle")
	## a human who isn't watching never has their favours spent for them
	var spent := 0
	for sd in range(1, 120):
		var w3: Types.World = H.paint(m, {"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 10], "harbor": ["blue", 2]})
		w3.round = 2
		w3.get_territory("ridge").garrison = 1
		for pid in ["red", "blue"]:
			w3.players[pid].fortune = 2
		var r3: Dictionary = Resolve.resolve_round(w3, m, [H.sheet("red", [H.pkt("ridge", "gate", 11)]), H.sheet("blue")], sd)
		for e in H.all_of(r3["events"], Types.EVENT_INVASION):
			for c in e.get("calls", []):
				if str(c.get("call", "")) == Combat.CALL_FORTUNE:
					spent += 1
	report.call(spent == 0, "favours are never spent behind a commander's back (%d)" % spent)
	## an AI's officers do call on it, once a battle a side at most
	var ai_spent := 0
	var twice := false
	for sd in range(1, 160):
		var w4: Types.World = H.paint(m, {"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["blue", 10], "harbor": ["blue", 2]})
		w4.round = 2
		w4.get_territory("ridge").garrison = 1
		for pid in ["red", "blue"]:
			w4.players[pid].fortune = 3
		var sa := H.sheet("red", [H.pkt("ridge", "gate", 11)])
		sa.fortune_auto = true
		var sb := H.sheet("blue")
		sb.fortune_auto = true
		var r4: Dictionary = Resolve.resolve_round(w4, m, [sa, sb], sd)
		for e in H.all_of(r4["events"], Types.EVENT_INVASION):
			var sides := {}
			for c in e.get("calls", []):
				if str(c.get("call", "")) == Combat.CALL_FORTUNE:
					ai_spent += 1
					if sides.has(str(c["side"])):
						twice = true
					sides[str(c["side"])] = true
		if not _conserved(w4, r4) or not _view_agrees(w4, r4):
			twice = true
	report.call(ai_spent > 10 and not twice, "AI officers call on Fortune (%d times in 159 battles), never twice a side in one battle; conserved" % ai_spent)


func _fortune_wars(report: Callable) -> void:
	for mid in ["known24", "ring26"]:
		var m := _map("res://maps/%s.json" % mid)
		m.fortune = true
		m.cards = true
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"},
			{"id": "green", "name": "c", "ai": "hask"}, {"id": "gold", "name": "d", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(m, seats, 21)
		var w: Types.World = Types.World.from_dict(r["setup"])
		var ok := true
		var spent := 0
		for k in (r["sheets"] as Array).size():
			var sheets: Array = []
			for dd in r["sheets"][k]:
				sheets.append(Types.Sheet.from_dict(dd))
			var res: Dictionary = Resolve.resolve_round(w, m, sheets, 21)
			var seen: Types.World = ViewEvents.apply_through(w, res["events"], (res["events"] as Array).size() - 1)
			for pid in (res["world"] as Types.World).players.keys():
				if seen.players[pid].fortune != (res["world"] as Types.World).players[pid].fortune:
					ok = false
			for e in H.all_of(res["events"], Types.EVENT_INVASION):
				for c in e.get("calls", []):
					if str(c.get("call", "")) == Combat.CALL_FORTUNE:
						spent += 1
			if not _view_agrees(w, res):
				ok = false
			w = res["world"]
			if k < (r["maneuvers"] as Array).size() and not (r["maneuvers"][k] as Dictionary).is_empty():
				load("res://engine/maneuver.gd").apply(w, m, r["maneuvers"][k])
		report.call(r["ok"] and ok and Hash.world_hash(w) == Hash.world_hash(r["world"]),
			"%s with Fortune: legal, replays, the report's favours agree every round (%d spent) %s" % [mid, spent, " ".join(r["violations"])])
