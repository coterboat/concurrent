## v2.4, the map and its table (v24-map; no rule change: rules 22 still, nothing here changes an outcome).
## The warning that a land is left bare counts only the enemy neighbours it isn't marching on (the
## owner: "only fire if there is another adjacent region that you could be attacked by outside of the
## one you're invading"); and in the regroup phase a land's number is the men who are there, apart
## from those marching in (who stay put) and those marching out.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Session := preload("res://game/core/session.gd")
const MapBoard := preload("res://game/board/map_board.gd")
const LandTip := preload("res://game/ui/land_tip.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_bare(report, tree)
	_arrivals(report, tree)


func _planning(tree: SceneTree) -> Node:
	## a war on the Knife, at round 1's orders: red (the human) against blue
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 5, "length": "short", "deal": "random", "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Varek", "kind": "ai", "ai": "varek"}]})
	s.lock()
	s.cinema_done()
	return s


func _paint(s: Node, lands: Dictionary) -> void:
	for t in lands.keys():
		var v: Array = lands[t]
		s.world.set_hex(str(t), str(v[0]), int(v[1]), int(v[2]) if v.size() > 2 else 0)
	s.sheet().packets = []
	s.sheet().placements = {}
	s.begin_orders()


func _bare_of(s: Node, land: String) -> bool:
	var name: String = s.hex_name(land)
	for w in s.warnings():
		if str(w).begins_with(name + " will be left with"):
			return true
	return false


func _bare(report: Callable, tree: SceneTree) -> void:
	var s: Node = _planning(tree)
	report.call(s.phase == Session.Phase.PLANNING and s.map.rules == 22, "round 1's orders, rules 22 (phase %d, rules %d)" % [s.phase, s.map.rules])
	## The Knife: Beacon - Ridge - Mill to the north, Ridge - The Gate, and The Gate - Harbor, Docks, Quarry
	## to the south (Harbor - Docks - Quarry along the shore)
	_paint(s, {"ridge": ["red", 2], "mill": ["red", 2], "beacon": ["blue", 2], "gate": ["blue", 5],
		"harbor": ["red", 3], "docks": ["red", 2], "quarry": ["red", 2]})
	## Docks' one enemy neighbour is The Gate: marching on it leaves nobody to walk in
	s.set_attack("docks", "gate", 1)
	report.call(not _bare_of(s, "docks"), "Docks marches on The Gate, its only enemy neighbour, and keeps 1: no warning (it was: %s)" % " / ".join(s.warnings()))
	## Ridge marches on The Gate, but Beacon is enemy too and left alone: it could walk in
	s.sheet().packets = []
	s.set_attack("ridge", "gate", 1)
	report.call(_bare_of(s, "ridge"), "Ridge marches on The Gate with Beacon's 2 left alone beside it: warned (%s)" % " / ".join(s.warnings()))
	## a land that sends columns at two neighbours fears neither of them
	s.world.set_hex("ridge", "red", 3)
	s.sheet().packets = []
	s.set_attack("ridge", "gate", 1)
	s.set_attack("ridge", "beacon", 1)
	report.call(s.sheet().packets.size() == 2 and s.projected_world().get_territory("ridge").held() == 1 and not _bare_of(s, "ridge"),
		"Ridge sends a column at The Gate and one at Beacon, keeping 1: neither is left to walk in, no warning (%s)" % " / ".join(s.warnings()))
	## a neighbour another of your lands attacks can still march on this one (they don't meet)
	s.world.set_hex("ridge", "red", 2)
	s.world.set_hex("quarry", "blue", 2)
	s.sheet().packets = []
	s.set_attack("docks", "quarry", 1)
	s.set_attack("harbor", "gate", 2)
	report.call(_bare_of(s, "docks") and not _bare_of(s, "harbor"),
		"Docks marches on Quarry while Harbor takes on The Gate: The Gate could still walk into Docks, warned; Harbor, beside only Docks and The Gate, isn't (%s)" % " / ".join(s.warnings()))
	## kept 2 or more: never a warning
	s.world.set_hex("ridge", "red", 4)
	s.sheet().packets = []
	s.set_attack("ridge", "gate", 2)
	report.call(not _bare_of(s, "ridge"), "Ridge keeps 2 at home: no warning (%s)" % " / ".join(s.warnings()))
	## neutral and empty lands never march: they don't count
	s.world.set_hex("beacon", "neutral", 3)
	s.world.set_hex("ridge", "red", 2)
	s.sheet().packets = []
	s.set_attack("ridge", "gate", 1)
	report.call(not _bare_of(s, "ridge"), "with Beacon neutral, Ridge's only enemy neighbour is the one it marches on: no warning (%s)" % " / ".join(s.warnings()))
	s.queue_free()


func _arrivals(report: Callable, tree: SceneTree) -> void:
	## the number on a land is who is there: those marching in are drawn apart (they stay put)
	var ts := Types.TerritoryState.new()
	ts.owner = "red"
	ts.armies = 3 ## 1 there and 2 marching in
	report.call(MapBoard.shown_split(ts, 2) == [0, 1], "1 there and 2 marching in: nobody who can march on, the one who stays on the shield (%s)" % str(MapBoard.shown_split(ts, 2)))
	report.call(MapBoard.shown_split(ts, 0) == [2, 1], "nobody marching in: as ever (%s)" % str(MapBoard.shown_split(ts, 0)))
	ts.armies = 4
	ts.garrison = 2
	report.call(MapBoard.shown_split(ts, 3) == [1, 2], "dug in two deep, 1 there and 3 marching in: 1 can march, 2 on the shield (%s)" % str(MapBoard.shown_split(ts, 3)))
	## the regroup phase, as the board and its tooltip see it
	var s: Node = _planning(tree)
	_paint(s, {"ridge": ["red", 5], "mill": ["red", 1], "beacon": ["red", 2], "gate": ["blue", 5],
		"harbor": ["blue", 3], "docks": ["blue", 2], "quarry": ["blue", 2]})
	s.lock() ## round 1's orders: nothing sent, so the battles are quick
	s.cinema_done()
	s.next_round()
	report.call(s.phase == Session.Phase.MANEUVER, "after the battles, the regroup phase (phase %d)" % s.phase)
	if s.phase != Session.Phase.MANEUVER:
		s.queue_free()
		return
	s.world.set_hex("ridge", "red", 5)
	s.world.set_hex("mill", "red", 1)
	s.moves[s.planner] = []
	report.call(s.add_move("ridge", "mill", 2) == "", "Ridge marches 2 to Mill")
	var bd: Control = MapBoard.new() ## the board as the tooltip reads it (no map drawn: no tree, no art)
	bd.world = s.maneuver_world()
	bd.viewer = s.planner
	bd.arriving = {"mill": 2}
	var mill: Types.TerritoryState = bd.world.get_territory("mill")
	report.call(mill.armies == 3 and MapBoard.shown_split(mill, 2) == [0, 1] and s.can_move_from("mill") == 0,
		"Mill, 1 there and 2 marching in, shows nobody who can march on, as the march rules have it (%d can)" % s.can_move_from("mill"))
	var tip: String = " | ".join(LandTip.lines(s, bd, "mill"))
	report.call(tip.contains("2 marching in") and tip.contains("0 armies"), "Mill's tooltip: who is there, and who is marching in apart (\"%s\")" % tip)
	var tip2: String = " | ".join(LandTip.lines(s, bd, "ridge"))
	report.call(tip2.contains("2 marching out") and tip2.contains("2 armies"), "Ridge's tooltip: who stays, and who is marching out (\"%s\")" % tip2)
	bd.free()
	s.queue_free()
