## v2.0: the land in 3D. Display only (no rules change: games still play rules 20). The land must
## find every border (round one's never did: a packed array in a dictionary appended to a copy, so
## there were no crossings, no roads and no passes), and the land's buildings must each have a
## proper place: a village on every land, every building on its own dry land and off the roads,
## the rules' buildings where the rules are, the names' landmarks where the names are.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapArt := preload("res://game/board/map_art.gd")
const Terrain := preload("res://game/world3d/terrain.gd")
const Scenery := preload("res://game/world3d/scenery.gd")
const LandTip := preload("res://game/ui/land_tip.gd")
const MapBoard := preload("res://game/board/map_board.gd")


func run(report: Callable, _tree: SceneTree) -> void:
	for mid in ["knife7", "ring26", "isles24"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		var art = MapArt.load_for(mid)
		var t = Terrain.build(art, map, 3)
		_borders(report, mid, art, t)
		_scenery(report, mid, art, map, t)
	_tip(report)
	_clash(report)


func _clash(report: Callable) -> void:
	## v2.0.2: a border clash told on the map: its two columns drawn by it while it's told, meeting
	## before the break, the winner carrying through once (MapBoard.clash_fx)
	var road := PackedVector2Array()
	for i in 21:
		road.append(Vector2(i, 0))
	var b = MapBoard.new()
	var fwd: PackedVector2Array = b._road_part(road, 0.0, 0.5)
	var back: PackedVector2Array = b._road_part(road, 1.0, 0.5)
	var mono := true
	for i in range(1, back.size()):
		mono = mono and back[i].x < back[i - 1].x
	report.call(fwd[0] == Vector2(0, 0) and fwd[fwd.size() - 1] == Vector2(10, 0) and back[0] == Vector2(20, 0) and back[back.size() - 1] == Vector2(10, 0) and mono,
		"v2.0.2: a clash's two columns each run their half of the road, from their own end to the middle")
	b.clash = ["cairn", "wold"]
	report.call(b.clash_hides("cairn", "wold") and b.clash_hides("wold", "cairn") and not b.clash_hides("cairn", "firth"),
		"v2.0.2: while a clash is told its two columns are drawn by it, not as plain arrows (and no others)")
	b._time = 0.1
	b.clash_won("red", "cairn", "wold", 13, 5, "blue", 8)
	var won: Dictionary = b.clash_fx["won"]
	report.call(is_equal_approx(float(won["t"]), MapBoard.CLASH_DRIVE + MapBoard.CLASH_HOLD) and b.clash_clock()["since_won"] < 0.0,
		"v2.0.2: dice that land before the columns meet wait for them to meet and push (the break at %.2f s)" % float(won["t"]))
	b._time = float(won["t"]) + 0.2
	var clock: Dictionary = b.clash_clock()
	b.clash_won("blue", "wold", "cairn", 8, 1, "red", 13)
	report.call(is_equal_approx(float(clock["since_won"]), 0.2) and clock["won_from"] == "cairn" and str(b.clash_fx["won"]["owner"]) == "red",
		"v2.0.2: the land's columns hear the break from the board, and a clash is won once")
	b._time = float(won["t"]) + MapBoard.CLASH_PUSH + 0.01
	report.call(not b.clash_hides("cairn", "wold"), "v2.0.2: once the winner has carried through, its own arrow carries on")
	b.free()
	var c = MapBoard.new()
	c._time = 5.0
	c.clash_won("blue", "wold", "cairn", 8, 2, "red", 6)
	report.call(not c.clash_fx.is_empty() and bool(c.clash_fx["hit"]) and is_equal_approx(float(c.clash_fx["won"]["t"]), 5.0),
		"v2.0.2: a clash settled after the report moved on (Next before the dice) breaks at once, already locked")
	c.free()


func _tip(report: Callable) -> void:
	## v2.0.1: a land's tip goes when the cursor leaves the board, or when the phase turns or a
	## report or dialog opens over it (the play critic: Fenmoor's tip stayed up through a report)
	var board := Control.new()
	var token := Control.new()
	board.add_child(token)
	var other := Control.new()
	report.call(not LandTip.stale(board, board, false) and not LandTip.stale(board, token, false), "v2.0.1: a tip stays while the cursor is on the board")
	report.call(LandTip.stale(board, other, false) and LandTip.stale(board, null, false), "v2.0.1: a tip goes when the cursor is on something else, or off the window")
	report.call(LandTip.stale(board, board, true), "v2.0.1: a tip goes the moment a report or dialog opens over the board, the cursor unmoved")
	board.free()
	other.free()


func _borders(report: Callable, mid: String, art, t) -> void:
	## every pair of lands that touch has a crossing on their border, and a road over it
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/art/%s_art.json" % mid))
	var pairs: Array = data.get("landAdjacency", [])
	var missing: Array = []
	var off: Array = []
	for pr in pairs:
		var x: Variant = t.crossing(str(pr[0]), str(pr[1]))
		if x == null:
			missing.append("%s|%s" % [pr[0], pr[1]])
			continue
		## on the border: the two lands within a few paces either side of it
		var near := {}
		for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6), Vector2.ZERO]:
			near[art.territory_at((x as Vector2) + d)] = true
		if not (near.has(str(pr[0])) and near.has(str(pr[1]))):
			off.append("%s|%s" % [pr[0], pr[1]])
	report.call(missing.is_empty() and pairs.size() > 0, "%s: every pair of touching lands has its crossing (%d pairs, %d missing: %s)" % [mid, pairs.size(), missing.size(), ", ".join(missing.slice(0, 4))])
	report.call(off.is_empty(), "%s: every crossing is on its border (%d off: %s)" % [mid, off.size(), ", ".join(off.slice(0, 4))])
	report.call(t.roads.size() == t.crossings.size(), "%s: a road over every crossing (%d roads, %d crossings)" % [mid, t.roads.size(), t.crossings.size()])


func _scenery(report: Callable, mid: String, art, map: Types.MapDef, t) -> void:
	var plan: Array = Scenery.plan(art, map, t)
	var again: Array = Scenery.plan(art, map, t)
	report.call(str(plan) == str(again), "%s: the land's buildings stand where they stood (the plan is seeded by the map)" % mid)
	var villages := {}
	var bad: Array = []
	var landmark := {}
	var ports := {}
	for s in plan:
		match str(s["role"]):
			"village":
				villages[s["land"]] = true
			"landmark":
				landmark[s["land"]] = s["kind"]
			"port":
				ports[s["land"]] = true
		if s["role"] in ["village", "landmark"]:
			var at: Vector2 = s["at"]
			if art.territory_at(at) != str(s["land"]) or t.coast_at(at) < 3.0 or t.road_at(at) < float(s["foot"]) * 0.3:
				bad.append("%s@%s" % [s["kind"], s["land"]])
	report.call(villages.size() == art.order.size(), "%s: a village on every land (%d of %d)" % [mid, villages.size(), art.order.size()])
	report.call(bad.is_empty(), "%s: every village and landmark on its own dry land, off the roads (%d wrong: %s)" % [mid, bad.size(), ", ".join(bad.slice(0, 4))])
	match mid:
		"knife7":
			report.call(landmark.get("mill") == "windmill" and landmark.get("beacon") == "watchtower" and landmark.get("gate") == "gatehouse" and landmark.get("quarry") == "quarry",
				"knife7: the names' landmarks (the Mill's windmill, the Beacon's tower, the Gate, the Quarry): %s" % [landmark])
			report.call(ports.has("harbor") and ports.has("docks"), "knife7: a quay at the Harbor and the Docks (%s)" % [ports.keys()])
		"ring26":
			var gates: Array = []
			for id in art.order:
				if map.get_territory(id).has_trait("pass"):
					gates.append(id)
			report.call(landmark.get("thethrone") == "starfort" and gates.all(func(g): return landmark.get(g) == "blockhouse"),
				"ring26: the rules as buildings (the Throne's star fort, a blockhouse on every pass: %s)" % [gates])
		"isles24":
			var port_lands: Array = []
			for id in art.order:
				if map.get_territory(id).has_trait("port"):
					port_lands.append(id)
			var quays: int = port_lands.filter(func(id): return ports.has(id)).size()
			report.call(quays >= port_lands.size() - 2, "isles24: a quay on the shore of the ports (%d of %d)" % [quays, port_lands.size()])
