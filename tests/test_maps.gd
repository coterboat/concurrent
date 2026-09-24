## Known World graph + 2p deal. G8 golden map.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Session := preload("res://game/match_session.gd")

const KNOWN := "res://maps/known24.json"


func run(report: Callable, tree: SceneTree) -> void:
	var map: Types.MapDef = Types.MapDef.from_file(KNOWN)
	report.call(map != null, "known24.json loads")
	if map == null:
		return
	report.call(map.id == "known24", "map id is known24")
	report.call(map.display_name == "The Known World", "map name is The Known World")
	report.call(map.territories.size() == 24, "twenty-four territories")
	report.call(map.region_bonus.size() == 6, "six region bonuses")
	report.call(int(map.region_bonus.get("midsea", 0)) == 4, "Midsea bonus 4")
	report.call(int(map.region_bonus.get("southrim", 0)) == 2, "Southern Rim bonus 2")
	report.call(map.layout.size() == 24, "every hex has a layout point")
	report.call(map.pin_neutral == "strait", "Neutral pins The Strait")

	var symmetric := true
	var unknown := false
	for terr_id in map.territory_ids():
		var t: Types.TerritoryDef = map.get_territory(terr_id)
		for n in t.adjacent:
			if not map.territories.has(n):
				unknown = true
			elif not map.is_adjacent(n, terr_id):
				symmetric = false
	report.call(symmetric, "known24 adjacency is undirected")
	report.call(not unknown, "known24 every adjacent id exists")

	for region in ["westreach", "crownlands", "midsea", "spine", "eastshore", "southrim"]:
		report.call(MapLib.region_members(map, region).size() == 4, "%s has 4 lands" % region)

	report.call(_reachable(map, "firth", "lantern", true), "west reaches east")
	report.call(_reachable(map, "firth", "lantern", false), "northern land route west→east exists without Midsea")
	report.call(not _reachable(map, "dune", "firth", false), "Southern Rim cannot reach Westreach if Midsea is removed")
	report.call(_reachable(map, "dune", "lagoon", false), "Southern Rim stays connected without Midsea")

	var world: Types.World = Setup.deal_two_player(map, 11, true)
	report.call(world.get_territory("strait").owner == Income.NEUTRAL_ID, "deal pins Neutral on The Strait")
	report.call(world.get_territory("strait").armies == 5, "The Strait has 5 Neutral")
	report.call(MapLib.player_territory_ids(world, "red").size() == 9, "red is dealt 9")
	report.call(MapLib.player_territory_ids(world, "blue").size() == 9, "blue is dealt 9")
	var empty := 0
	for terr_id in map.territory_ids():
		if world.get_territory(terr_id).owner == Types.UNOCCUPIED:
			empty += 1
	report.call(empty == 5, "five lands start unoccupied (got %s)" % empty)
	report.call(Setup.rounds_for(map) == 8, "Known World is 8 rounds")
	report.call(Setup.pool_for(map, 2) == 30, "Known World 2p pool is 30")

	var s: Node = Session.new()
	tree.root.add_child(s)
	s.new_game(true, 11, false, KNOWN)
	report.call(s.map.id == "known24", "session boots Known World")
	report.call(s.phase == Session.Phase.OPENING, "Known World starts at opening")
	report.call(s.pool_left() == 21, "9 standing, 21 left in a pool of 30")
	s.lock()
	report.call(s.phase == Session.Phase.PLANNING, "Known World monkey opening auto-locks")
	s.queue_free()


func _reachable(map: Types.MapDef, start: String, goal: String, use_midsea: bool) -> bool:
	var seen := {}
	var q: Array = [start]
	seen[start] = true
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == goal:
			return true
		var t: Types.TerritoryDef = map.get_territory(cur)
		if t == null:
			continue
		for n in t.adjacent:
			var nt: Types.TerritoryDef = map.get_territory(n)
			if not use_midsea and nt != null and nt.region == "midsea" and cur != n:
				if t.region != "midsea":
					continue
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return false
