## v1.7 land traits and supply. A fortress fires a longer line and digs one deeper, a pass
## lets only so many storm it at once, two friendly ports are joined by sea, and a land cut
## off from your main body feeds nobody. Every check here is against the rule as written,
## not against what the code happens to do.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Maneuver := preload("res://engine/maneuver.gd")
const MapLib := preload("res://engine/map.gd")
const Hash := preload("res://engine/hash.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Setup := preload("res://engine/setup.gd")

const Ai := preload("res://engine/ai.gd")
const Session := preload("res://game/core/session.gd")

const MARCHES := "res://maps/marches18.json"
const ISLES := "res://maps/isles24.json"


func run(report: Callable, tree: SceneTree) -> void:
	_map_file(report)
	_fort(report)
	_pass(report)
	_port(report)
	_supply(report)
	_war(report)
	_old_saves(report)
	_pass_columns(report)
	_planner_keeps_the_rules(report)
	_session(report, tree)
	Combat.use_rules(null)


func _marches() -> Types.MapDef:
	return _rules(Types.MapDef.from_file(MARCHES))


func _isles() -> Types.MapDef:
	return _rules(Types.MapDef.from_file(ISLES))


func _rules(m: Types.MapDef) -> Types.MapDef:
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.maneuvers = true
	m.dig_cap = 3
	m.rules = 17
	m.fire_line = true
	m.wild_cards = false
	return m


# ---------------------------------------------------------------- the map file

func _map_file(report: Callable) -> void:
	for path in [MARCHES, ISLES, "res://maps/ring26.json"]:
		var m: Types.MapDef = Types.MapDef.from_file(path)
		report.call(m != null and m.territories.size() > 0, "%s loads" % path.get_file())
		if m == null:
			continue
		var undirected := true
		var known := true
		var lonely: Array = []
		for t in m.territory_ids():
			if MapLib.neighbors(m, t).is_empty():
				lonely.append(t)
			for n in MapLib.neighbors(m, t):
				if not m.territories.has(n):
					known = false
				elif not m.is_adjacent(n, t):
					undirected = false
		report.call(undirected and known, "%s adjacency is undirected and every id exists" % m.id)
		report.call(lonely.is_empty(), "%s: every land has a way in (%s)" % [m.id, lonely])
		## reachable: a map you cannot cross is not a map
		var seen := {}
		var q: Array = [m.territory_ids()[0]]
		seen[q[0]] = true
		while not q.is_empty():
			for n in MapLib.neighbors(m, str(q.pop_front())):
				if not seen.has(n):
					seen[n] = true
					q.append(n)
		report.call(seen.size() == m.territories.size(), "%s is one connected world" % m.id)

	var mm: Types.MapDef = Types.MapDef.from_file(MARCHES)
	report.call(mm.territories.size() == 18, "The Marches has eighteen lands")
	report.call(mm.supply, "The Marches asks for supply")
	report.call(Array(MapLib.trait_ids(mm, "fort")) == ["briargate", "redgate"], "each realm keeps one fortress")
	report.call(Array(MapLib.trait_ids(mm, "pass")) == ["highford", "ironford"], "each realm keeps one pass")
	## the frontier is what this map is for: the marches must interlock
	var frontier := 0
	for t in mm.territory_ids():
		if mm.get_territory(t).region != "northmarch":
			continue
		for n in MapLib.neighbors(mm, t):
			if mm.get_territory(n).region == "southmarch":
				frontier += 1
	report.call(frontier >= 7, "the two marches meet along %s borders" % frontier)
	## and the crowns never touch: you cannot skip the frontier
	var skipped := 0
	for t in mm.territory_ids():
		if mm.get_territory(t).region != "northcrown":
			continue
		for n in MapLib.neighbors(mm, t):
			if mm.get_territory(n).region in ["southcrown", "southmarch"]:
				skipped += 1
	report.call(skipped == 0, "no road from one crown to the other but through the marches")

	var isl: Types.MapDef = Types.MapDef.from_file(ISLES)
	report.call(isl.supply and MapLib.trait_ids(isl, "port").size() >= 8, "The Thousand Isles is built on harbours")


# ---------------------------------------------------------------- fortresses

func _fort(report: Callable) -> void:
	var m: Types.MapDef = _marches()
	Combat.use_rules(m)
	report.call(MapLib.defender_line_bonus(m, "redgate") == 1, "a fortress fires one more")
	report.call(MapLib.defender_line_bonus(m, "thornreach") == 0, "open ground fires five")

	## the whole point: the same men are harder to shift out of a fort
	var open_ground: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, 0)
	var in_fort: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, 1)
	report.call(abs(open_ground - 0.5) < 0.001, "ten against ten in the open is even (%.1f%%)" % [open_ground * 100.0])
	report.call(in_fort < 0.36 and in_fort > 0.32, "ten against ten in a fort is %.1f%%" % [in_fort * 100.0])

	## five men fire five either way, so a fort only counts once it is properly held
	report.call(abs(Combat.capture_rate(5, 5, Combat.MODE_VOLLEYS, 1) - 0.5) < 0.001,
		"a fort with five in it is no better than open ground")

	## and it takes one more man dug in
	var w: Types.World = H.paint(m, {"redgate": ["red", 4], "thornreach": ["red", 2], "elmspire": ["red", 2],
		"lowmeadow": ["red", 2], "ironford": ["blue", 2]})
	var fort_cap: int = Income.garrison_cap(w, m, "redgate")
	var open_cap: int = Income.garrison_cap(w, m, "thornreach")
	report.call(fort_cap == open_cap + 1, "a fortress digs one deeper than open ground (%s vs %s)" % [fort_cap, open_cap])

	## The fort is felt in battles actually fought. The comparison is the same land, the
	## same board and the same seeds with the trait taken away, so nothing but the fortress
	## can account for the difference — attacking a different land would roll different dice.
	var open_map: Types.MapDef = _marches()
	(open_map.get_territory("redgate") as Types.TerritoryDef).traits = PackedStringArray()
	var took: Array = [0, 0]
	for i in 2:
		var mm: Types.MapDef = m if i == 0 else open_map
		for s in 300:
			var w1: Types.World = H.paint(mm, {"redgate": ["red", 9], "ironford": ["blue", 10], "thornreach": ["red", 2]})
			var r1: Dictionary = H.resolve(w1, mm, [H.sheet("blue", [H.pkt("ironford", "redgate", 9)])], 9000 + s)
			if H.owner_of(r1["world"], "redgate") == "blue":
				took[i] += 1
	report.call(took[0] < took[1] - 20, "nine storm a fortress less often than the same nine storm open ground (%s vs %s of 300)" % [took[0], took[1]])

	## Amendment 18: a battle actually fought must run at the odds the sheet quotes. Before
	## v1.7 the queue gave every even volley to the defender while the sheet said 50/50.
	for pair in [[9, 9, 0], [12, 9, 0], [9, 9, 1]]:
		var att: int = pair[0]
		var deff: int = pair[1]
		var fortified: bool = pair[2] == 1
		var mm: Types.MapDef = m if fortified else open_map
		Combat.use_rules(mm)
		var quoted: float = Combat.capture_rate(att, deff, Combat.MODE_VOLLEYS, 1 if fortified else 0)
		var won := 0
		for s in 600:
			var w1: Types.World = H.paint(mm, {"redgate": ["red", deff], "ironford": ["blue", att + 1], "thornreach": ["red", 2]})
			var r1: Dictionary = H.resolve(w1, mm, [H.sheet("blue", [H.pkt("ironford", "redgate", att)])], 3000 + s)
			if H.owner_of(r1["world"], "redgate") == "blue":
				won += 1
		var got: float = float(won) / 600.0
		report.call(abs(got - quoted) < 0.06, "%s v %s%s fought at %.0f%%, quoted %.0f%%"
			% [att, deff, " in a fort" if fortified else " in the open", got * 100.0, quoted * 100.0])
	Combat.use_rules(m)

	## an even volley costs nobody: it is fired again
	var evens := 0
	for s in 120:
		## open ground both sides, so both fire a line of five and even volleys really happen
		var w1: Types.World = H.paint(m, {"thornreach": ["red", 8], "sunreach": ["blue", 9], "olivespire": ["blue", 2]})
		var r1: Dictionary = H.resolve(w1, m, [H.sheet("blue", [H.pkt("sunreach", "thornreach", 8)])], 700 + s)
		for e in H.all_of(r1["events"], Types.EVENT_INVASION):
			for roll in e.get("rolls", []):
				if str(roll.get("w", "")) == "":
					evens += 1
	report.call(evens > 0, "even volleys are recorded and fired again (%s of them)" % evens)

	## And on a map with no traits at all, at several sizes, so nothing but the rule is in
	## play. This is the check the arena's "even fights" band was mistaken for: which fights
	## a tournament produces is chosen by the commanders, so it never measured the rule.
	var plain: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	plain.battle = Combat.MODE_VOLLEYS
	plain.scramble = true
	plain.maneuvers = true
	plain.dig_cap = 3
	plain.rules = 17
	plain.fire_line = true
	plain.wild_cards = false
	Combat.use_rules(plain)
	for n in [2, 5, 9]:
		var carried := 0
		for t in 300:
			var pw: Types.World = H.paint(plain, {"keep": ["red", n], "pass": ["blue", n + 1], "peak": ["blue", 2]})
			var pr: Dictionary = H.resolve(pw, plain, [H.sheet("blue", [H.pkt("pass", "keep", n)])], 20000 + t)
			if H.owner_of(pr["world"], "keep") == "blue":
				carried += 1
		var rate: float = float(carried) / 300.0
		report.call(abs(rate - 0.5) < 0.07, "%s against %s on open ground is even: attacker took %.0f%%" % [n, n, rate * 100.0])
	Combat.use_rules(m)


# ---------------------------------------------------------------- passes

func _pass(report: Callable) -> void:
	var m: Types.MapDef = _marches()
	report.call(MapLib.column_cap(m, "ironford") == 6, "only six may storm a pass")
	report.call(MapLib.column_cap(m, "thornreach") == 0, "open ground takes as many as you can send")
	var w: Types.World = H.paint(m, {"redgate": ["red", 12], "ironford": ["blue", 3], "thornreach": ["red", 2]})
	var too_many: PackedStringArray = Validate.validate_sheet(w, m, H.sheet("red", [H.pkt("redgate", "ironford", 7)]))
	report.call(too_many.size() > 0, "seven into a pass is refused")
	var at_cap: PackedStringArray = Validate.validate_sheet(w, m, H.sheet("red", [H.pkt("redgate", "ironford", 6)]))
	report.call(at_cap.size() == 0, "six into a pass is allowed")
	## the cap is on the column, not on the land: two columns may still converge
	var w2: Types.World = H.paint(m, {"redgate": ["red", 12], "elmspire": ["red", 8], "ironford": ["blue", 3]})
	var both: PackedStringArray = Validate.validate_sheet(w2, m,
		H.sheet("red", [H.pkt("redgate", "ironford", 6), H.pkt("elmspire", "ironford", 6)]))
	report.call(both.size() == 0, "two columns of six may converge on a pass")


# ---------------------------------------------------------------- ports

func _port(report: Callable) -> void:
	## Ports belong to The Thousand Isles, where every crossing is a harbour.
	var m: Types.MapDef = _isles()
	report.call(MapLib.has_trait(m, "vanewick", "port") and MapLib.has_trait(m, "kestrelport", "port"),
		"Vanewick and Kestrel Port are harbours")
	report.call(not m.is_adjacent("vanewick", "kestrelport"), "and they are on different islands")
	var w: Types.World = H.paint(m, {"vanewick": ["red", 6], "kestrelport": ["red", 3], "vanemoor": ["red", 2],
		"reachrock": ["blue", 2]})
	w.round = 2
	report.call(Array(MapLib.supply_links(w, m, "vanewick")).has("kestrelport"), "your own ports are joined by sea")
	report.call(Maneuver.validate(w, m, "red", [{"from": "vanewick", "to": "kestrelport", "n": 3}]).is_empty(),
		"troops may march from one of your harbours to another")
	## but only between your own: an enemy harbour is no use to you
	var w2: Types.World = H.paint(m, {"vanewick": ["red", 6], "kestrelport": ["blue", 3], "vanemoor": ["red", 2]})
	w2.round = 2
	report.call(not Array(MapLib.supply_links(w2, m, "vanewick")).has("kestrelport"), "an enemy harbour is not yours")
	report.call(not Maneuver.validate(w2, m, "red", [{"from": "vanewick", "to": "kestrelport", "n": 3}]).is_empty(),
		"you cannot march into an enemy harbour by sea")
	## a port carries supply, not an assault
	report.call(Validate.validate_sheet(w2, m, H.sheet("red", [H.pkt("vanewick", "kestrelport", 3)])).size() > 0,
		"a harbour carries the baggage train, not the assault")
	## a map without ports is unaffected
	var mm: Types.MapDef = _marches()
	report.call(MapLib.trait_ids(mm, "port").is_empty(), "The Marches has no harbours")
	var wm: Types.World = H.paint(mm, {"kingsholt": ["red", 4], "elmspire": ["red", 2], "redgate": ["blue", 2]})
	wm.round = 2
	report.call(Array(MapLib.supply_links(wm, mm, "kingsholt")) == Array(MapLib.neighbors(mm, "kingsholt")),
		"with no harbours, supply follows the land borders and nothing else")


# ---------------------------------------------------------------- supply

func _supply(report: Callable) -> void:
	var m: Types.MapDef = _isles()
	## red holds a solid body on Great Vane and one stranded land away on Thale
	var w: Types.World = H.paint(m, {
		"vanetor": ["red", 2], "vanefell": ["red", 2], "vaneholt": ["red", 2], "vanemoor": ["red", 2],
		"thalecliff": ["red", 4],
		"thaleharbour": ["blue", 3], "thalewood": ["blue", 2], "sealstone": ["blue", 2]})
	var fed: Dictionary = MapLib.supplied_ids(w, m, "red")
	report.call(fed.size() == 4 and not fed.has("thalecliff"), "the stranded land is out of supply")
	report.call(MapLib.in_supply(w, m, "vaneholt"), "the main body is in supply")
	report.call(not MapLib.in_supply(w, m, "thalecliff"), "Thale Cliff, cut off across the sea, is not")
	report.call(Income.cap_of(w, m, "thalecliff") == 0, "no recruits reach a land out of supply")
	report.call(Income.cap_of(w, m, "vaneholt") > 0, "recruits reach the main body")

	## it still defends itself — being cut off is not being disarmed
	var before: int = w.get_territory("thalecliff").held()
	var r: Dictionary = H.resolve(w, m, [H.sheet("blue", [H.pkt("thaleharbour", "thalecliff", 2)])], 77)
	report.call(before == 4 and (r["errors"] as PackedStringArray).is_empty(), "a cut-off land still fights")

	## income counts only what is fed
	var joined: Types.World = H.paint(m, {
		"vanetor": ["red", 2], "vanefell": ["red", 2], "vaneholt": ["red", 2], "vanemoor": ["red", 2],
		"vanehead": ["red", 2], "thaleharbour": ["blue", 3]})
	var cut: Types.World = H.paint(m, {
		"vanetor": ["red", 2], "vanefell": ["red", 2], "vaneholt": ["red", 2], "vanemoor": ["red", 2],
		"thalecliff": ["red", 2], "thaleharbour": ["blue", 3]})
	report.call(Income.income_of(joined, m, "red") >= Income.income_of(cut, m, "red"),
		"five joined lands pay at least as well as four and a stranded one")

	## a harbour keeps an island fed: Kestrel Port alone would be cut off, but it is a port
	var by_sea: Types.World = H.paint(m, {
		"vanewick": ["red", 3], "vanemoor": ["red", 2], "vanehead": ["red", 2], "kestrelport": ["red", 2],
		"reachrock": ["blue", 3]})
	report.call(MapLib.in_supply(by_sea, m, "kestrelport"), "a harbour keeps the far island in supply")
	var stranded: Types.World = H.paint(m, {
		"vanetor": ["red", 3], "vanefell": ["red", 2], "vaneholt": ["red", 2], "kestrelport": ["red", 2],
		"reachrock": ["blue", 3]})
	report.call(not MapLib.in_supply(stranded, m, "kestrelport"), "lose the harbour behind it and the island starves")

	## supply off is supply ignored
	var off: Types.MapDef = _isles()
	off.supply = false
	report.call(MapLib.in_supply(w, off, "thalecliff"), "with supply off every land is fed")


# ---------------------------------------------------------------- a whole war

func _war(report: Callable) -> void:
	var m: Types.MapDef = _marches()
	var seats: Array = [{"id": "red", "name": "general", "ai": "general"}, {"id": "blue", "name": "veteran", "ai": "veteran"}]
	var a: Dictionary = Autoplay.play(m, seats, 4242, 0, false)
	report.call(bool(a["ok"]), "a whole war on The Marches is legal: %s" % [" | ".join(a["violations"])])
	var b: Dictionary = Autoplay.play(_marches(), seats, 4242, 0, false)
	report.call(str(a.get("hash", "")) == str(b.get("hash", "")) and int(a["roundsPlayed"]) == int(b["roundsPlayed"]),
		"the same seed replays to the same war")
	var four: Array = [{"id": "red", "name": "general", "ai": "general"}, {"id": "blue", "name": "veteran", "ai": "veteran"},
		{"id": "green", "name": "hask", "ai": "hask"}, {"id": "gold", "name": "quill", "ai": "quill"}]
	for path in ["res://maps/ring26.json", "res://maps/isles24.json"]:
		var mm: Types.MapDef = _rules(Types.MapDef.from_file(path))
		var r1: Dictionary = Autoplay.play(mm, four, 616, 0, false)
		report.call(bool(r1["ok"]), "a whole four-handed war on %s is legal: %s" % [mm.id, " | ".join(r1["violations"])])
		var r2: Dictionary = Autoplay.play(_rules(Types.MapDef.from_file(path)), four, 616, 0, false)
		report.call(str(r1.get("hash", "")) == str(r2.get("hash", "")), "%s replays to the same war" % mm.id)


# ---------------------------------------------------------------- the review's fixes

func _old_saves(report: Callable) -> void:
	## Amendment 18 belongs to games begun under v1.7 rules. A v1.6 save must replay exactly
	## as it was fought, or its sheets stop matching the world they were written for.
	var fought := {}
	var blanks := {}
	for rules in [16, 17]:
		var m: Types.MapDef = _marches()
		m.rules = rules
		Combat.use_rules(m)
		var won := 0
		var even := 0
		for s in 300:
			var w1: Types.World = H.paint(m, {"thornreach": ["red", 9], "sunreach": ["blue", 10], "olivespire": ["blue", 2]})
			var r1: Dictionary = H.resolve(w1, m, [H.sheet("blue", [H.pkt("sunreach", "thornreach", 9)])], 5000 + s)
			if H.owner_of(r1["world"], "thornreach") == "blue":
				won += 1
			for e in H.all_of(r1["events"], Types.EVENT_INVASION):
				for roll in e.get("rolls", []):
					if str(roll.get("w", "")) == "":
						even += 1
		fought[rules] = float(won) / 300.0
		blanks[rules] = even
	report.call(int(blanks[16]) == 0 and int(blanks[17]) > 0 and float(fought[16]) < float(fought[17]) - 0.08,
		"a v1.6 game replays as it was fought (9 v 9: %.0f%%, every volley has a winner); v1.7 games refire the even ones (%.0f%%)" % [float(fought[16]) * 100.0, float(fought[17]) * 100.0])
	Combat.use_rules(null)


func _pass_columns(report: Callable) -> void:
	var m: Types.MapDef = _marches()
	Combat.use_rules(m)
	## a surge into a pass is a column of six, however many took the land before it
	var over := 0
	var surged := 0
	for s in 40:
		var w: Types.World = H.paint(m, {"stagfield": ["red", 20], "coldwater": ["red", 2], "lowmeadow": ["blue", 1], "highford": ["blue", 2], "briargate": ["blue", 1]})
		w.round = 2
		w.get_territory("stagfield").garrison = 1
		var sh := H.sheet("red", [H.pkt("stagfield", "lowmeadow", 19, "highford")])
		sh.surges["lowmeadow"] = "highford"
		var r: Dictionary = H.resolve(w, m, [sh, H.sheet("blue")], 800 + s)
		for e in H.all_of(r["events"], Types.EVENT_SURGE):
			surged += 1
			if int(e["strength"]) > 6:
				over += 1
	report.call(surged > 30 and over == 0, "a surge into a pass pushes on with six at most (%d surges, %d over)" % [surged, over])
	## the reserves only top the column back up to six from each road in
	var widest := 0
	var called := 0
	for s in 60:
		var w2: Types.World = H.paint(m, {"elmspire": ["red", 16], "kingsholt": ["red", 2], "ironford": ["blue", 9], "blackford": ["blue", 2]})
		w2.round = 2
		w2.get_territory("elmspire").garrison = 1
		var p := H.pkt("elmspire", "ironford", 6)
		p.stance = Combat.STANCE_BOLD
		var r2: Dictionary = H.resolve(w2, m, [H.sheet("red", [p]), H.sheet("blue")], 900 + s)
		for e in H.all_of(r2["events"], Types.EVENT_INVASION):
			if int(e.get("reservesAdded", 0)) > 0:
				called += 1
			for roll in e.get("rolls", []):
				widest = maxi(widest, int(roll.get("sa", 0)))
	report.call(called > 10 and widest <= 6, "reserves storming a pass top the column up to six, never past it (%d calls, widest %d)" % [called, widest])
	## older games on the same map keep their surges whole
	var m16: Types.MapDef = _marches()
	m16.rules = 16
	var w3: Types.World = H.paint(m16, {"stagfield": ["red", 20], "coldwater": ["red", 2], "lowmeadow": ["blue", 1], "highford": ["blue", 2], "briargate": ["blue", 1]})
	w3.round = 2
	w3.get_territory("stagfield").garrison = 1
	var sh3 := H.sheet("red", [H.pkt("stagfield", "lowmeadow", 19, "highford")])
	sh3.surges["lowmeadow"] = "highford"
	var e3: Dictionary = H.first(H.resolve(w3, m16, [sh3, H.sheet("blue")], 801)["events"], Types.EVENT_SURGE)
	report.call(int(e3.get("strength", 0)) > 6, "a game begun before the cap surges as it always did (%d)" % int(e3.get("strength", 0)))
	Combat.use_rules(null)


func _planner_keeps_the_rules(report: Callable) -> void:
	## The planner must draw up sheets that are legal as drawn. A sheet that breaks a rule is
	## cut back by _legalize, which strikes every surge and drops attacks from the end until
	## it passes — so one column too wide for a pass used to cost a commander half its turn.
	var four: Array = [{"id": "red", "name": "general", "ai": "general"}, {"id": "blue", "name": "veteran", "ai": "veteran"},
		{"id": "green", "name": "hask", "ai": "hask"}, {"id": "gold", "name": "quill", "ai": "quill"}]
	var two: Array = [{"id": "red", "name": "general", "ai": "general"}, {"id": "blue", "name": "hask", "ai": "hask"}]
	var total := 0
	var log: Array = []
	for path in [MARCHES, "res://maps/ring26.json"]:
		for sd in [11, 12]:
			Ai.repairs = 0
			Ai.repair_log = []
			var r: Dictionary = Autoplay.play(_rules(Types.MapDef.from_file(path)), two if path == MARCHES else four, sd)
			total += Ai.repairs
			log.append_array(Ai.repair_log.slice(0, 2))
	report.call(total == 0, "the commanders never order a column too wide for a pass (sheets cut back: %d) %s" % [total, " | ".join(log)])


func _session(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": MARCHES, "seed": 3, "length": "short", "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	report.call(s.map.rules >= 17, "new games play by v1.7 rules (%d)" % s.map.rules)
	## orders: "attack with all" into a pass is six from one land
	s.world = H.paint(s.map, {"elmspire": ["red", 14], "kingsholt": ["red", 2], "ironford": ["blue", 3], "blackford": ["blue", 2]})
	s.world.round = 2
	s.world.get_territory("elmspire").garrison = 1
	s.phase = Session.Phase.PLANNING
	s.planner = "red"
	s.plan_step = "orders"
	s.drafts["red"] = s._empty("red")
	var err: String = s.set_attack("elmspire", "ironford")
	var idx: int = s.packet_index("elmspire", "ironford")
	var n: int = (s.sheet().packets[idx] as Types.Packet).strength if idx >= 0 else -1
	report.call(err == "" and n == 6 and s.max_attack("elmspire", "ironford", idx) == 6 and s.max_send("elmspire", idx) == 14,
		"attacking a pass with everything sends the six it allows (%d)" % n)
	s.set_packet_strength(idx, 12)
	report.call((s.sheet().packets[idx] as Types.Packet).strength == 6, "and no more can be dialled in")
	s.queue_free()
	## ports: a march across the sea in the regroup phase
	var p: Node = Session.new()
	p.instant = true
	tree.root.add_child(p)
	p.new_game({"map": ISLES, "seed": 3, "length": "short", "open_sheets": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	p.world = H.paint(p.map, {"vanewick": ["red", 6], "kestrelport": ["red", 3], "vanemoor": ["red", 2], "reachrock": ["blue", 2]})
	p.world.round = 2
	p.world.get_territory("vanewick").garrison = 1
	p.planner = "red"
	report.call(p.marches_to("vanewick", "kestrelport") and not p.map.is_adjacent("vanewick", "kestrelport"),
		"the regroup phase lets you march between your own ports")
	p.queue_free()
