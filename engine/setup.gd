## Deal and starting pools. Neutral is a doorstop, not an AI.
## No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Rng := preload("res://engine/rng.gd")
const Income := preload("res://engine/income.gd")

const KNIFE_ROUNDS := 5
const WORLD_ROUNDS := 8
const EARLY_END_FRACTION := 0.8
const NEUTRAL_GATE_ARMIES := 5
const STARTING_POOL := {2: 18, 3: 35, 4: 30, 5: 25}


static func starting_pool(player_count: int) -> int:
	return int(STARTING_POOL.get(player_count, 25))


static func early_end_threshold(map: Types.MapDef) -> int:
	var n: int = map.territories.size()
	return int(ceil(EARLY_END_FRACTION * float(n)))


static func make_player(id: String, display_name: String, color: String) -> Types.PlayerState:
	var p := Types.PlayerState.new()
	p.id = id
	p.display_name = display_name
	p.color = color
	p.alive = true
	return p


static func deal_knife7_two_player(map: Types.MapDef, match_seed: int, pin_neutral_on_gate: bool = true) -> Types.World:
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	w.players["red"] = make_player("red", "Red", "#c23b2e")
	w.players["blue"] = make_player("blue", "Blue", "#2e5aa6")
	w.players[Income.NEUTRAL_ID] = make_player(Income.NEUTRAL_ID, "Neutral", "#6b6560")

	var ids: Array = []
	for terr_id in map.territory_ids():
		ids.append(terr_id)
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "deal|knife7")
	_shuffle(ids, rng)

	var red_ids: Array = [ids[0], ids[1], ids[2]]
	var blue_ids: Array = [ids[3], ids[4], ids[5]]
	var leftover: String = str(ids[6])
	if pin_neutral_on_gate:
		leftover = _swap_gate(red_ids, blue_ids, leftover)

	for terr_id in red_ids:
		w.set_hex(terr_id, "red", 1)
	for terr_id in blue_ids:
		w.set_hex(terr_id, "blue", 1)
	w.set_hex(leftover, Income.NEUTRAL_ID, NEUTRAL_GATE_ARMIES)
	return w


static func deal_knife7_three_player(map: Types.MapDef, match_seed: int) -> Types.World:
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	w.players["red"] = make_player("red", "Red", "#c23b2e")
	w.players["green"] = make_player("green", "Green", "#2e8b57")
	w.players["blue"] = make_player("blue", "Blue", "#2e5aa6")
	var ids: Array = []
	for terr_id in map.territory_ids():
		ids.append(terr_id)
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "deal|knife7|3p")
	_shuffle(ids, rng)
	var seats := ["red", "green", "blue"]
	for i in 6:
		w.set_hex(str(ids[i]), seats[i % 3], 1)
	w.set_hex(str(ids[6]), Types.UNOCCUPIED, 0)
	return w


static func pool_for(map: Types.MapDef, player_count: int) -> int:
	if map != null and map.starting_pool > 0:
		return map.starting_pool
	return starting_pool(player_count)


static func rounds_for(map: Types.MapDef) -> int:
	if map != null and map.rounds > 0:
		return map.rounds
	return KNIFE_ROUNDS if map != null and map.id == "knife7" else WORLD_ROUNDS


static func remaining_pool(world: Types.World, player_id: String, player_count: int, map: Types.MapDef = null) -> int:
	var have := 0
	for terr_id in world.territories.keys():
		var ts: Types.TerritoryState = world.territories[terr_id]
		if ts.owner == player_id:
			have += ts.armies
	return maxi(0, pool_for(map, player_count) - have)


static func deal_two_player(map: Types.MapDef, match_seed: int, pin_neutral: bool = true) -> Types.World:
	if map.deal_each <= 3 and map.territories.size() == 7:
		return deal_knife7_two_player(map, match_seed, pin_neutral)
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	w.players["red"] = make_player("red", "Red", "#c23b2e")
	w.players["blue"] = make_player("blue", "Blue", "#2e5aa6")
	w.players[Income.NEUTRAL_ID] = make_player(Income.NEUTRAL_ID, "Neutral", "#6b6560")
	var pin: String = map.pin_neutral
	var each: int = map.deal_each if map.deal_each > 0 else 9
	var ids: Array = []
	for terr_id in map.territory_ids():
		if str(terr_id) == pin:
			continue
		ids.append(str(terr_id))
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "deal|" + map.id)
	_shuffle(ids, rng)
	var i := 0
	for _r in each:
		if i >= ids.size():
			break
		w.set_hex(str(ids[i]), "red", 1)
		i += 1
	for _b in each:
		if i >= ids.size():
			break
		w.set_hex(str(ids[i]), "blue", 1)
		i += 1
	if pin != "" and map.get_territory(pin) != null:
		w.set_hex(pin, Income.NEUTRAL_ID, map.neutral_armies if map.neutral_armies > 0 else NEUTRAL_GATE_ARMIES)
	if map.neutral_leftover:
		while i < ids.size():
			w.set_hex(str(ids[i]), Income.NEUTRAL_ID, 1)
			i += 1
	return w


static func apply_opening(world: Types.World, map: Types.MapDef, placements_by_player: Dictionary) -> void:
	## Simultaneous: caps from the post-deal snapshot, then apply.
	var caps := {}
	for terr_id in world.territories.keys():
		caps[str(terr_id)] = Income.cap_of(world, map, str(terr_id))
	var pids: Array = placements_by_player.keys()
	pids.sort()
	for pid in pids:
		var place: Dictionary = placements_by_player[pid]
		var keys: Array = place.keys()
		keys.sort()
		var remaining: int = remaining_pool(world, pid, _human_count(world), map)
		for terr_id in keys:
			if remaining <= 0:
				break
			var ts: Types.TerritoryState = world.get_territory(str(terr_id))
			if ts == null or ts.owner != pid:
				continue
			var want: int = int(place[terr_id])
			if want <= 0:
				continue
			var spent: int = mini(want, remaining)
			var add: int = mini(spent, int(caps.get(str(terr_id), 0)))
			remaining -= spent
			if add > 0:
				ts.armies += add


static func _human_count(world: Types.World) -> int:
	var n := 0
	for pid in world.players.keys():
		if str(pid) == Income.NEUTRAL_ID or str(pid).begins_with("__"):
			continue
		n += 1
	return n


static func _swap_gate(red_ids: Array, blue_ids: Array, leftover: String) -> String:
	if leftover == "gate":
		return leftover
	if "gate" in red_ids:
		red_ids.erase("gate")
		red_ids.append(leftover)
		return "gate"
	if "gate" in blue_ids:
		blue_ids.erase("gate")
		blue_ids.append(leftover)
		return "gate"
	return leftover


static func _shuffle(arr: Array, rng: RefCounted) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.rand_index(i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
