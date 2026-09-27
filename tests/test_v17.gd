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

const NARROW := "res://maps/narrow14.json"


func run(report: Callable, tree: SceneTree) -> void:
	_map_file(report)
	_fort(report)
	_pass(report)
	_port(report)
	_supply(report)
	_war(report)
	Combat.use_rules(null)


func _narrow() -> Types.MapDef:
	var m: Types.MapDef = Types.MapDef.from_file(NARROW)
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
	var m: Types.MapDef = Types.MapDef.from_file(NARROW)
	report.call(m != null and m.territories.size() == 14, "narrow14 loads with fourteen lands")
	report.call(m.supply, "narrow14 asks for supply")
	report.call(Array(MapLib.trait_ids(m, "fort")) == ["northgate", "southgate"], "both gates are fortresses")
	report.call(Array(MapLib.trait_ids(m, "pass")) == ["bridgehead", "thespit"], "the bridge and the spit are passes")
	report.call(Array(MapLib.trait_ids(m, "port")) == ["coldharbor", "gullrock", "warmharbor"], "three ports")
	var undirected := true
	for t in m.territory_ids():
		for n in MapLib.neighbors(m, t):
			if not m.is_adjacent(n, t):
				undirected = false
	report.call(undirected, "narrow14 adjacency is undirected")
	## the two realms may only meet through the Narrows
	var cross := 0
	for t in m.territory_ids():
		for n in MapLib.neighbors(m, t):
			var a: String = m.get_territory(t).region
			var b: String = m.get_territory(n).region
			if (a == "frostmarch" and b == "sunmarch") or (a == "sunmarch" and b == "frostmarch"):
				cross += 1
	report.call(cross == 0, "the realms never touch: every road crosses the Narrows")


# ---------------------------------------------------------------- fortresses

func _fort(report: Callable) -> void:
	var m: Types.MapDef = _narrow()
	Combat.use_rules(m)
	report.call(MapLib.defender_line_bonus(m, "northgate") == 1, "a fortress fires one more")
	report.call(MapLib.defender_line_bonus(m, "hallow") == 0, "open ground fires five")

	## the whole point: the same men are harder to shift out of a fort
	var open_ground: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, 0)
	var in_fort: float = Combat.capture_rate(10, 10, Combat.MODE_VOLLEYS, 1)
	report.call(abs(open_ground - 0.5) < 0.001, "ten against ten in the open is even (%.1f%%)" % [open_ground * 100.0])
	report.call(in_fort < 0.36 and in_fort > 0.32, "ten against ten in a fort is %.1f%%" % [in_fort * 100.0])

	## five men fire five either way, so a fort only counts once it is properly held
	report.call(abs(Combat.capture_rate(5, 5, Combat.MODE_VOLLEYS, 1) - 0.5) < 0.001,
		"a fort with five in it is no better than open ground")

	## and it takes one more man dug in
	var w: Types.World = H.paint(m, {"northgate": ["red", 4], "hallow": ["red", 2], "coldharbor": ["red", 2],
		"stonewatch": ["red", 2], "bridgehead": ["blue", 2]})
	var fort_cap: int = Income.garrison_cap(w, m, "northgate")
	var open_cap: int = Income.garrison_cap(w, m, "hallow")
	report.call(fort_cap == open_cap + 1, "a fortress digs one deeper than open ground (%s vs %s)" % [fort_cap, open_cap])

	## The fort is felt in battles actually fought. The comparison is the same land, the
	## same board and the same seeds with the trait taken away, so nothing but the fortress
	## can account for the difference — attacking a different land would roll different dice.
	var open_map: Types.MapDef = _narrow()
	(open_map.get_territory("northgate") as Types.TerritoryDef).traits = PackedStringArray()
	var took: Array = [0, 0]
	for i in 2:
		var mm: Types.MapDef = m if i == 0 else open_map
		for s in 300:
			var w1: Types.World = H.paint(mm, {"northgate": ["red", 9], "bridgehead": ["blue", 10], "hallow": ["red", 2]})
			var r1: Dictionary = H.resolve(w1, mm, [H.sheet("blue", [H.pkt("bridgehead", "northgate", 9)])], 9000 + s)
			if H.owner_of(r1["world"], "northgate") == "blue":
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
			var w1: Types.World = H.paint(mm, {"northgate": ["red", deff], "bridgehead": ["blue", att + 1], "hallow": ["red", 2]})
			var r1: Dictionary = H.resolve(w1, mm, [H.sheet("blue", [H.pkt("bridgehead", "northgate", att)])], 3000 + s)
			if H.owner_of(r1["world"], "northgate") == "blue":
				won += 1
		var got: float = float(won) / 600.0
		report.call(abs(got - quoted) < 0.06, "%s v %s%s fought at %.0f%%, quoted %.0f%%"
			% [att, deff, " in a fort" if fortified else " in the open", got * 100.0, quoted * 100.0])
	Combat.use_rules(m)

	## an even volley costs nobody: it is fired again
	var evens := 0
	for s in 120:
		var w1: Types.World = H.paint(m, {"hallow": ["red", 8], "elkwood": ["blue", 9], "coldharbor": ["blue", 2]})
		var r1: Dictionary = H.resolve(w1, m, [H.sheet("blue", [H.pkt("elkwood", "hallow", 8)])], 700 + s)
		for e in H.all_of(r1["events"], Types.EVENT_INVASION):
			for roll in e.get("rolls", []):
				if str(roll.get("w", "")) == "":
					evens += 1
	report.call(evens > 0, "even volleys are recorded and fired again (%s of them)" % evens)


# ---------------------------------------------------------------- passes

func _pass(report: Callable) -> void:
	var m: Types.MapDef = _narrow()
	report.call(MapLib.column_cap(m, "bridgehead") == 6, "only six may storm a pass")
	report.call(MapLib.column_cap(m, "hallow") == 0, "open ground takes as many as you can send")
	var w: Types.World = H.paint(m, {"northgate": ["red", 12], "bridgehead": ["blue", 3], "hallow": ["red", 2]})
	var too_many: PackedStringArray = Validate.validate_sheet(w, m, H.sheet("red", [H.pkt("northgate", "bridgehead", 7)]))
	report.call(too_many.size() > 0, "seven into a pass is refused")
	var at_cap: PackedStringArray = Validate.validate_sheet(w, m, H.sheet("red", [H.pkt("northgate", "bridgehead", 6)]))
	report.call(at_cap.size() == 0, "six into a pass is allowed")
	## the cap is on the column, not on the land: two columns may still converge
	var w2: Types.World = H.paint(m, {"northgate": ["red", 12], "thebeacon": ["red", 8], "bridgehead": ["blue", 3]})
	var both: PackedStringArray = Validate.validate_sheet(w2, m,
		H.sheet("red", [H.pkt("northgate", "bridgehead", 6), H.pkt("thebeacon", "bridgehead", 6)]))
	report.call(both.size() == 0, "two columns of six may converge on a pass")


# ---------------------------------------------------------------- ports

func _port(report: Callable) -> void:
	var m: Types.MapDef = _narrow()
	## coldharbor and warmharbor are ports on opposite shores and share no land border
	report.call(not m.is_adjacent("coldharbor", "warmharbor"), "the two shore ports do not border each other")
	var w: Types.World = H.paint(m, {"coldharbor": ["red", 6], "warmharbor": ["red", 3], "elkwood": ["red", 2],
		"gullrock": ["blue", 2]})
	w.round = 2
	report.call(Array(MapLib.supply_links(w, m, "coldharbor")).has("warmharbor"), "your own ports are joined by sea")
	report.call(Maneuver.validate(w, m, "red", [{"from": "coldharbor", "to": "warmharbor", "n": 3}]).is_empty(),
		"troops may march from one of your ports to another")
	## but only between your own: an enemy port is no use to you
	var w2: Types.World = H.paint(m, {"coldharbor": ["red", 6], "warmharbor": ["blue", 3], "elkwood": ["red", 2]})
	w2.round = 2
	report.call(not Array(MapLib.supply_links(w2, m, "coldharbor")).has("warmharbor"), "an enemy port is not your harbour")
	report.call(not Maneuver.validate(w2, m, "red", [{"from": "coldharbor", "to": "warmharbor", "n": 3}]).is_empty(),
		"you cannot march into an enemy port by sea")
	## a port is not a road for armies: you still cannot attack down it
	report.call(Validate.validate_sheet(w2, m, H.sheet("red", [H.pkt("coldharbor", "warmharbor", 3)])).size() > 0,
		"a port carries the baggage train, not an assault")


# ---------------------------------------------------------------- supply

func _supply(report: Callable) -> void:
	var m: Types.MapDef = _narrow()
	## red holds a solid western body plus one stranded land across the sea
	var w: Types.World = H.paint(m, {
		"elkwood": ["red", 2], "hallow": ["red", 2], "coldharbor": ["red", 2], "northgate": ["red", 2],
		"redhill": ["red", 4],
		"southgate": ["blue", 3], "thespit": ["blue", 3], "almsfield": ["blue", 2]})
	var fed: Dictionary = MapLib.supplied_ids(w, m, "red")
	report.call(fed.size() == 4 and not fed.has("redhill"), "the stranded land is out of supply")
	report.call(MapLib.in_supply(w, m, "northgate"), "the main body is in supply")
	report.call(not MapLib.in_supply(w, m, "redhill"), "Redhill, cut off across the sea, is not")
	report.call(Income.cap_of(w, m, "redhill") == 0, "no recruits reach a land out of supply")
	report.call(Income.cap_of(w, m, "northgate") > 0, "recruits reach the main body")

	## it still defends itself — being cut off is not being disarmed
	var before: int = w.get_territory("redhill").held()
	var r: Dictionary = H.resolve(w, m, [H.sheet("blue", [H.pkt("southgate", "redhill", 2)])], 77)
	report.call(before == 4 and (r["errors"] as PackedStringArray).is_empty(), "a cut-off land still fights")

	## income counts only what is fed
	var all_in: Types.World = H.paint(m, {
		"elkwood": ["red", 2], "hallow": ["red", 2], "coldharbor": ["red", 2], "northgate": ["red", 2],
		"stonewatch": ["red", 2], "southgate": ["blue", 3]})
	var cut: Types.World = H.paint(m, {
		"elkwood": ["red", 2], "hallow": ["red", 2], "coldharbor": ["red", 2], "northgate": ["red", 2],
		"redhill": ["red", 2], "southgate": ["blue", 3]})
	report.call(Income.income_of(all_in, m, "red") >= Income.income_of(cut, m, "red"),
		"five joined lands pay at least as well as four and a stranded one")

	## a port keeps an island fed: gullrock alone would be cut off, but it is a port
	var by_sea: Types.World = H.paint(m, {
		"coldharbor": ["red", 3], "elkwood": ["red", 2], "hallow": ["red", 2], "gullrock": ["red", 2],
		"southgate": ["blue", 3]})
	report.call(MapLib.in_supply(by_sea, m, "gullrock"), "a port keeps the island in supply")
	var stranded: Types.World = H.paint(m, {
		"elkwood": ["red", 3], "hallow": ["red", 2], "northgate": ["red", 2], "gullrock": ["red", 2],
		"southgate": ["blue", 3]})
	report.call(not MapLib.in_supply(stranded, m, "gullrock"), "lose the harbour and the island starves")

	## supply off is supply ignored
	var off: Types.MapDef = _narrow()
	off.supply = false
	report.call(MapLib.in_supply(w, off, "redhill"), "with supply off every land is fed")


# ---------------------------------------------------------------- a whole war

func _war(report: Callable) -> void:
	var m: Types.MapDef = _narrow()
	var seats: Array = [{"id": "red", "name": "general", "ai": "general"}, {"id": "blue", "name": "veteran", "ai": "veteran"}]
	var a: Dictionary = Autoplay.play(m, seats, 4242, 0, false)
	report.call(bool(a["ok"]), "a whole war on narrow14 is legal: %s" % [" | ".join(a["violations"])])
	var b: Dictionary = Autoplay.play(_narrow(), seats, 4242, 0, false)
	report.call(str(a.get("hash", "")) == str(b.get("hash", "")) and int(a["roundsPlayed"]) == int(b["roundsPlayed"]),
		"the same seed replays to the same war")
