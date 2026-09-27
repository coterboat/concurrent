## Static map queries. No Node. No UI. No RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")


static func neighbors(map: Types.MapDef, terr_id: String) -> PackedStringArray:
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	if t == null:
		return PackedStringArray()
	var ids: Array = Array(t.adjacent)
	ids.sort()
	return PackedStringArray(ids)


static func is_adjacent(map: Types.MapDef, a: String, b: String) -> bool:
	return map.is_adjacent(a, b)


static func friendly_neighbor_count(world: Types.World, map: Types.MapDef, terr_id: String) -> int:
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner == Types.UNOCCUPIED:
		return 0
	var n := 0
	for adj in neighbors(map, terr_id):
		var other: Types.TerritoryState = world.get_territory(adj)
		if other != null and other.owner == ts.owner:
			n += 1
	return n


static func player_territory_ids(world: Types.World, player_id: String) -> PackedStringArray:
	var ids: Array = []
	for terr_id in world.territories.keys():
		var ts: Types.TerritoryState = world.territories[terr_id]
		if ts.owner == player_id:
			ids.append(str(terr_id))
	ids.sort()
	return PackedStringArray(ids)


static func region_members(map: Types.MapDef, region: String) -> PackedStringArray:
	var ids: Array = []
	for terr_id in map.territory_ids():
		var t: Types.TerritoryDef = map.get_territory(terr_id)
		if t != null and t.region == region and region != "":
			ids.append(terr_id)
	ids.sort()
	return PackedStringArray(ids)


static func sum_armies(world: Types.World) -> int:
	var n := 0
	for terr_id in world.territories.keys():
		var ts: Types.TerritoryState = world.territories[terr_id]
		n += ts.armies + ts.garrison
	return n


static func hex_invariant_error(world: Types.World) -> String:
	for terr_id in world.territories.keys():
		var ts: Types.TerritoryState = world.territories[terr_id]
		if ts.armies < 0:
			return "%s has negative armies %s" % [terr_id, ts.armies]
		if ts.garrison < 0:
			return "%s has negative garrison %s" % [terr_id, ts.garrison]
		if ts.owner == Types.UNOCCUPIED:
			if ts.armies != 0 or ts.garrison != 0:
				return "%s unoccupied but armies %s garrison %s" % [terr_id, ts.armies, ts.garrison]
		elif ts.armies + ts.garrison < 1:
			return "%s owned-empty by %s" % [terr_id, ts.owner]
	return ""


static func living_player_ids(world: Types.World) -> PackedStringArray:
	var ids: Array = []
	for pid in world.players.keys():
		var ps: Types.PlayerState = world.players[pid]
		if ps == null or not ps.alive:
			continue
		if str(pid) == "neutral" or str(pid).begins_with("__"):
			continue
		ids.append(str(pid))
	ids.sort()
	return PackedStringArray(ids)


static func holds_region(world: Types.World, map: Types.MapDef, player_id: String, region: String) -> bool:
	var members := region_members(map, region)
	if members.is_empty():
		return false
	for terr_id in members:
		var ts: Types.TerritoryState = world.get_territory(terr_id)
		if ts == null or ts.owner != player_id:
			return false
	return true


# ---------------------------------------------------------------- v1.7 land traits

static func has_trait(map: Types.MapDef, terr_id: String, name: String) -> bool:
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	return t != null and t.has_trait(name)


static func trait_ids(map: Types.MapDef, name: String) -> PackedStringArray:
	var ids: Array = []
	for terr_id in map.territory_ids():
		if has_trait(map, str(terr_id), name):
			ids.append(str(terr_id))
	ids.sort()
	return PackedStringArray(ids)


static func defender_line_bonus(map: Types.MapDef, terr_id: String) -> int:
	## A fortress's defenders fire a longer line. 0 everywhere else. It only bites once the
	## fort holds more than five: five men fire five either way. That is the rule's own
	## shape, and it reads true — a fortress is worth what you garrison it with.
	if map == null or not has_trait(map, terr_id, "fort"):
		return 0
	return maxi(0, map.fort_bonus)


static func column_cap(map: Types.MapDef, terr_id: String) -> int:
	## Most men who may be sent in one attacking column into this land. 0 = no cap.
	if map == null or not has_trait(map, terr_id, "pass"):
		return 0
	return maxi(0, map.pass_cap)


# ---------------------------------------------------------------- v1.7 supply

static func supply_links(world: Types.World, map: Types.MapDef, terr_id: String) -> PackedStringArray:
	## Neighbours for supply and for marching: the land borders, plus every other
	## friendly port if this land is a port (ships carry the baggage train).
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner == Types.UNOCCUPIED:
		return neighbors(map, terr_id)
	var ids: Array = Array(neighbors(map, terr_id))
	if has_trait(map, terr_id, "port"):
		for other in trait_ids(map, "port"):
			if str(other) == terr_id or ids.has(str(other)):
				continue
			var o: Types.TerritoryState = world.get_territory(str(other))
			if o != null and o.owner == ts.owner:
				ids.append(str(other))
	ids.sort()
	return PackedStringArray(ids)


static func supplied_ids(world: Types.World, map: Types.MapDef, player_id: String) -> Dictionary:
	## The lands of `player_id` that are in supply: the largest connected body of their
	## empire, where friendly ports count as joined by sea. Everything cut off from it is
	## out of supply. Ties are broken by the first land in sorted order, so a replay of the
	## same world always picks the same body.
	var owned := player_territory_ids(world, player_id)
	var out := {}
	if owned.is_empty():
		return out
	var seen := {}
	var best: Array = []
	for start in owned:
		if seen.has(start):
			continue
		var comp: Array = []
		var q: Array = [start]
		seen[start] = true
		while not q.is_empty():
			var cur: String = q.pop_front()
			comp.append(cur)
			for n in supply_links(world, map, cur):
				if seen.has(n):
					continue
				var ts: Types.TerritoryState = world.get_territory(n)
				if ts == null or ts.owner != player_id:
					continue
				seen[n] = true
				q.append(n)
		if comp.size() > best.size():
			best = comp
	for t in best:
		out[str(t)] = true
	return out


static func in_supply(world: Types.World, map: Types.MapDef, terr_id: String) -> bool:
	## Always true when the map does not use supply.
	if map == null or not map.supply:
		return true
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner == Types.UNOCCUPIED or ts.owner == "neutral":
		return true
	return supplied_ids(world, map, ts.owner).has(terr_id)
