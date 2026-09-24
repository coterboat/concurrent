## Random-legal planner. Not clever. Week-1 content so resolve cannot leak armies.
## No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Setup := preload("res://engine/setup.gd")
const Rng := preload("res://engine/rng.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Events := preload("res://engine/events.gd")


static func opening_placements(world: Types.World, map: Types.MapDef, player_id: String, rng: RefCounted) -> Dictionary:
	var place := {}
	var owned: Array = Array(MapLib.player_territory_ids(world, player_id))
	_shuffle(owned, rng)
	var left: int = Setup.remaining_pool(world, player_id, Setup._human_count(world), map)
	for terr_id in owned:
		if left <= 0:
			break
		var cap: int = Income.cap_of(world, map, terr_id)
		if cap <= 0:
			continue
		var want: int = rng.roll_int(0, mini(cap, left))
		if rng.chance(1, 6):
			want = mini(left, cap + rng.roll_int(1, 4)) ## overflow vanishes
		if want > 0:
			place[terr_id] = want
			left -= mini(want, left)
	return place


static func legal_sheet(world: Types.World, map: Types.MapDef, player_id: String, rng: RefCounted) -> Types.Sheet:
	var sheet := Types.Sheet.new()
	sheet.player_id = player_id
	var ps: Types.PlayerState = world.players.get(player_id, null)
	if ps == null or not ps.alive or player_id == Income.NEUTRAL_ID:
		return sheet

	var projected: Types.World = world.clone()
	if world.round > 1 and rng.chance(1, 3):
		sheet.regroup = _random_regroup(projected, map, player_id, rng)
		if sheet.regroup != null:
			Validate._apply_regroup_to(projected, sheet)

	sheet.placements = _random_placements(projected, map, player_id, rng)
	Validate._apply_placements_to(projected, map, sheet)
	sheet.packets = _random_packets(projected, map, player_id, rng)

	var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
	if errs.size() > 0:
		## Hold rather than emit an illegal sheet. The monkey counts these.
		var hold := Types.Sheet.new()
		hold.player_id = player_id
		return hold
	return sheet


static func play_match(map: Types.MapDef, match_seed: int, three_player: bool = false) -> Dictionary:
	var world: Types.World
	if three_player:
		world = Setup.deal_knife7_three_player(map, match_seed)
	else:
		world = Setup.deal_two_player(map, match_seed, true)
	var violations := PackedStringArray()
	_check_world(world, violations, "deal")

	var opening := {}
	for pid in MapLib.living_player_ids(world):
		var rng: RefCounted = Rng.derive_stream(match_seed, 0, "open|" + pid)
		opening[pid] = opening_placements(world, map, pid, rng)
	Setup.apply_opening(world, map, opening)
	_check_world(world, violations, "opening")
	var setup: Dictionary = world.to_dict()

	var rounds := 0
	var hashes: Array = []
	var recorded_sheets: Array = []
	var max_rounds: int = Setup.KNIFE_ROUNDS + 2
	while rounds < max_rounds:
		_check_world(world, violations, "pre-r%s" % world.round)
		var before: int = MapLib.sum_armies(world)
		var sheets: Array = []
		for pid in MapLib.living_player_ids(world):
			var rng: RefCounted = Rng.derive_stream(match_seed, world.round, "bot|" + pid)
			var sheet: Types.Sheet = legal_sheet(world, map, pid, rng)
			var verr: PackedStringArray = Validate.validate_sheet(world, map, sheet)
			if verr.size() > 0:
				violations.append("P4 bot sheet illegal r%s %s: %s" % [world.round, pid, " ".join(verr)])
			sheets.append(sheet)
		var round_dicts: Array = []
		for s in sheets:
			round_dicts.append((s as Types.Sheet).to_dict())
		recorded_sheets.append(round_dicts)
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, match_seed)
		if not result["errors"].is_empty():
			violations.append("resolve errors r%s: %s" % [world.round, " ".join(result["errors"])])
			break
		var after_world: Types.World = result["world"]
		var events: Array = result["events"]
		_check_world(after_world, violations, "post-r%s" % world.round)
		var expected: int = before + _placed_added(events) + _entrenched_added(events) - _combat_deaths(events)
		var got: int = MapLib.sum_armies(after_world)
		if got != expected:
			violations.append("P2 army leak r%s expected %s got %s" % [world.round, expected, got])
		hashes.append(Hash.world_hash(after_world))
		world = after_world
		rounds += 1
		if _winner(events) != "":
			break
	return {
		"ok": violations.is_empty(),
		"violations": violations,
		"rounds": rounds,
		"hashes": hashes,
		"world": world,
		"final_hash": Hash.world_hash(world),
		"setup": setup,
		"sheets": recorded_sheets,
		"opening": opening,
	}


static func _check_world(world: Types.World, violations: PackedStringArray, tag: String) -> void:
	var err: String = MapLib.hex_invariant_error(world)
	if err != "":
		violations.append("%s %s" % [tag, err])


static func _placed_added(events: Array) -> int:
	var n := 0
	for e in events:
		if str(e.get("kind", "")) == Types.EVENT_PLACED:
			n += int(e.get("added", 0))
	return n


static func _entrenched_added(events: Array) -> int:
	var n := 0
	for e in events:
		if str(e.get("kind", "")) == Types.EVENT_ENTRENCHED:
			n += 1
	return n


static func _combat_deaths(events: Array) -> int:
	var n := 0
	for e in events:
		var kind: String = str(e.get("kind", ""))
		if kind == Types.EVENT_CLASH or kind == Types.EVENT_SPOILS:
			n += int(e.get("sizeA", 0)) + int(e.get("sizeB", 0)) - int(e.get("winnerRemaining", 0))
		elif kind == Types.EVENT_INVASION:
			n += int(e.get("attackerSize", 0)) + int(e.get("defenderSize", 0)) - int(e.get("winnerRemaining", 0))
	return n


static func _winner(events: Array) -> String:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			return str(e.get("winner", ""))
	return ""


static func _random_regroup(world: Types.World, map: Types.MapDef, player_id: String, rng: RefCounted) -> Types.Regroup:
	var opts: Array = []
	for from_id in MapLib.player_territory_ids(world, player_id):
		var ts: Types.TerritoryState = world.get_territory(from_id)
		if ts == null or Income.max_send(ts) < 1:
			continue
		for to_id in MapLib.neighbors(map, from_id):
			var other: Types.TerritoryState = world.get_territory(to_id)
			if other != null and other.owner == player_id:
				opts.append([from_id, to_id, Income.max_send(ts)])
	if opts.is_empty():
		return null
	var pick: Array = opts[rng.rand_index(opts.size())]
	var r := Types.Regroup.new()
	r.from_id = str(pick[0])
	r.to_id = str(pick[1])
	r.strength = rng.roll_int(1, int(pick[2]) - 1)
	return r


static func _random_placements(world: Types.World, map: Types.MapDef, player_id: String, rng: RefCounted) -> Dictionary:
	var place := {}
	var owned: Array = Array(MapLib.player_territory_ids(world, player_id))
	_shuffle(owned, rng)
	var income: int = Income.income_of(world, map, player_id)
	var left := income
	for terr_id in owned:
		if left <= 0:
			break
		var cap: int = Income.cap_of(world, map, terr_id)
		if cap <= 0:
			continue
		var want: int = rng.roll_int(0, cap)
		if rng.chance(1, 5):
			want += rng.roll_int(1, 3)
		if want > 0:
			place[terr_id] = want
			left -= mini(want, left)
	return place


static func _random_packets(world: Types.World, map: Types.MapDef, player_id: String, rng: RefCounted) -> Array:
	var packets: Array = []
	var budget := {}
	var owned: Array = Array(MapLib.player_territory_ids(world, player_id))
	for terr_id in owned:
		var ts: Types.TerritoryState = world.get_territory(terr_id)
		budget[terr_id] = Income.max_send(ts)
	_shuffle(owned, rng)
	for from_id in owned:
		var left: int = int(budget.get(from_id, 0))
		if left < 1:
			continue
		if rng.chance(2, 5):
			continue
		var dests: Array = []
		for n in MapLib.neighbors(map, from_id):
			var ts: Types.TerritoryState = world.get_territory(n)
			if ts != null and ts.owner != player_id:
				dests.append(n)
		if dests.is_empty():
			continue
		var to_id: String = str(dests[rng.rand_index(dests.size())])
		var strength: int = rng.roll_int(1, left)
		var surge := ""
		if rng.chance(1, 3):
			var surge_opts: Array = []
			for n in MapLib.neighbors(map, to_id):
				if n != from_id:
					surge_opts.append(n)
			if not surge_opts.is_empty():
				surge = str(surge_opts[rng.rand_index(surge_opts.size())])
		var p := Types.Packet.new()
		p.from_id = from_id
		p.to_id = to_id
		p.strength = strength
		p.surge_to = surge
		packets.append(p)
		budget[from_id] = left - strength
	return packets


static func _shuffle(arr: Array, rng: RefCounted) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.rand_index(i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
