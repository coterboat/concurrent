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
