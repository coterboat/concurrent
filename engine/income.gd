## Income, cap, connected bloc. Computed on the world you pass (post-regroup).
## Neutral region bonuses are unpaid. No Node. No UI. No RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")

const NEUTRAL_ID := "neutral"
const INCOME_FLOOR := 3


static func income_of(world: Types.World, map: Types.MapDef, player_id: String, cashed_set: int = 0) -> int:
	if player_id == NEUTRAL_ID or player_id == Types.UNOCCUPIED:
		return 0
	var terrs := MapLib.player_territory_ids(world, player_id)
	if map != null and map.supply:
		## v1.7: only the lands still joined to your main body pay. A land cut off from it
		## still fights and still holds, but it feeds nobody.
		var fed: Dictionary = MapLib.supplied_ids(world, map, player_id)
		var kept: Array = []
		for t in terrs:
			if fed.has(str(t)):
				kept.append(str(t))
		terrs = PackedStringArray(kept)
	var from_count: int = maxi(INCOME_FLOOR, terrs.size() / 3)
	var from_bloc: int = connected_bloc(world, map, player_id) / 6
	return from_count + from_bloc + region_bonus_of(world, map, player_id) + cashed_set


static func cap_of(world: Types.World, map: Types.MapDef, terr_id: String) -> int:
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner == Types.UNOCCUPIED:
		return 0
	## v1.7: no recruits reach a land the baggage train cannot. It still defends itself.
	if map != null and map.supply and not MapLib.in_supply(world, map, terr_id):
		return 0
	return 1 + MapLib.friendly_neighbor_count(world, map, terr_id)


static func garrison_cap(world: Types.World, map: Types.MapDef, terr_id: String) -> int:
	## Dug-in ceiling. Neutral does not entrench (the doorstop is a fixed stack).
	## Cap = 1 + friendly neighbors, +1 if you hold the whole region.
	## Rewards a connected hold without a second recruitment pool.
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner == Types.UNOCCUPIED or ts.owner == NEUTRAL_ID:
		return 0
	var n: int = 1 + MapLib.friendly_neighbor_count(world, map, terr_id)
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	if t != null and t.region != "" and MapLib.holds_region(world, map, ts.owner, t.region):
		n += 1
	## v1.4 (Amendment 15): never deeper than two. Interior fortresses were dead weight,
	## 60% of every man on the board by mid-game, and they slowed the late war to a crawl.
	if map.dig_cap > 0:
		n = mini(n, map.dig_cap)
	## v1.7: a fortress takes one more man dug in than open ground. Applied after the cap,
	## so the fort is the one place that goes deeper — that is the whole point of it.
	if t != null and t.has_trait("fort"):
		n += 1
	return n


static func home_split(ts: Types.TerritoryState) -> Array:
	## v1.5 display: [who can march, who stays home]. Home is the dug-in garrison; a land
	## with nobody dug in yet keeps one man back, and he stands with the garrison.
	if ts == null or ts.owner == Types.UNOCCUPIED:
		return [0, 0]
	if ts.owner == NEUTRAL_ID or ts.garrison >= 1:
		return [ts.armies, ts.garrison]
	if ts.armies >= 1:
		return [ts.armies - 1, 1]
	return [0, 0]


static func max_send(ts: Types.TerritoryState) -> int:
	## If the hex is dug in, every mobile soldier may march. Else leave 1.
	if ts == null:
		return 0
	if ts.garrison >= 1:
		return maxi(0, ts.armies)
	return maxi(0, ts.armies - 1)


static func connected_bloc(world: Types.World, map: Types.MapDef, player_id: String) -> int:
	var owned := MapLib.player_territory_ids(world, player_id)
	var best := 0
	var seen := {}
	for start in owned:
		if seen.has(start):
			continue
		var size := 0
		var q: Array = [start]
		seen[start] = true
		while not q.is_empty():
			var cur: String = q.pop_front()
			size += 1
			for n in MapLib.neighbors(map, cur):
				if seen.has(n):
					continue
				var ts: Types.TerritoryState = world.get_territory(n)
				if ts == null or ts.owner != player_id:
					continue
				seen[n] = true
				q.append(n)
		if size > best:
			best = size
	return best


static func region_bonus_of(world: Types.World, map: Types.MapDef, player_id: String) -> int:
	if player_id == NEUTRAL_ID:
		return 0
	var total := 0
	var regions: Array = map.region_bonus.keys()
	regions.sort()
	for region in regions:
		if MapLib.holds_region(world, map, player_id, str(region)):
			total += int(map.region_bonus[region])
	return total


static func score_of(world: Types.World, map: Types.MapDef, player_id: String) -> int:
	return MapLib.player_territory_ids(world, player_id).size() + region_bonus_of(world, map, player_id)
