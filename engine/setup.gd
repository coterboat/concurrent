## Deal and starting pools. Neutral is a doorstop, not an AI.
## No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Rng := preload("res://engine/rng.gd")
const Income := preload("res://engine/income.gd")
const Capitals := preload("res://engine/capitals.gd")
const Fortune := preload("res://engine/fortune.gd")

const KNIFE_ROUNDS := 5
const WORLD_ROUNDS := 8
const EARLY_END_FRACTION := 0.8
const NEUTRAL_GATE_ARMIES := 5
const STARTING_POOL := {2: 18, 3: 35, 4: 30, 5: 25}
## Bible 3.1: after a scattered deal, a second simultaneous placement pass.
## Both passes are sealed before anything is revealed, so they fold into one
## opening sheet whose per-hex ceiling is OPENING_PASSES × cap.
const OPENING_PASSES := 2
const SEAT_IDS := ["red", "blue", "green", "gold", "purple"]
const SEAT_COLORS := {
	"red": "#c23b2e",
	"blue": "#2e5aa6",
	"green": "#2e8b57",
	"gold": "#c9a227",
	"purple": "#7b4fa0",
}


static func starting_pool(player_count: int) -> int:
	return int(STARTING_POOL.get(player_count, 25))


static func early_end_threshold(map: Types.MapDef) -> int:
	var n: int = map.territories.size()
	## v1.8: a map may ask for more (a duel is not won at four-fifths)
	var f: float = map.dominate if map.dominate > 0.0 else EARLY_END_FRACTION
	return mini(n, int(ceil(f * float(n))))


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
	if map != null and map.pools.has(player_count):
		return int(map.pools[player_count])
	if map != null and map.starting_pool > 0 and player_count <= 2:
		return map.starting_pool
	return starting_pool(player_count)


static func opening_cap(world: Types.World, map: Types.MapDef, terr_id: String) -> int:
	return OPENING_PASSES * Income.cap_of(world, map, terr_id, false)


static func seat_color(seat_id: String) -> String:
	return str(SEAT_COLORS.get(seat_id, "#888888"))


static func deal(map: Types.MapDef, seats: Array, match_seed: int) -> Types.World:
	## seats: [{id, name}] in seat order. 2 seats add a Neutral doorstop (3.9).
	## 3+ seats: deal evenly, leftovers unoccupied (3.1).
	if seats.size() == 2:
		var w2: Types.World = deal_two_player(map, match_seed, true)
		return _rename_two(w2, seats)
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	for seat in seats:
		var sid: String = str(seat.get("id", ""))
		w.players[sid] = make_player(sid, str(seat.get("name", sid.capitalize())), seat_color(sid))
	var ids: Array = []
	for terr_id in map.territory_ids():
		ids.append(terr_id)
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "deal|%s|%sp" % [map.id, seats.size()])
	_shuffle(ids, rng)
	var each: int = ids.size() / seats.size()
	var i := 0
	for _k in each:
		for seat in seats:
			w.set_hex(str(ids[i]), str(seat.get("id", "")), 1)
			i += 1
	return w


static func _rename_two(w: Types.World, seats: Array) -> Types.World:
	## deal_two_player seats red/blue; map them onto the chosen seat ids/names.
	var remap := {"red": str(seats[0].get("id", "red")), "blue": str(seats[1].get("id", "blue"))}
	var out: Types.World = w.clone()
	out.players.clear()
	for old in ["red", "blue"]:
		var sid: String = remap[old]
		var seat: Dictionary = seats[0] if old == "red" else seats[1]
		out.players[sid] = make_player(sid, str(seat.get("name", sid.capitalize())), seat_color(sid))
	out.players[Income.NEUTRAL_ID] = w.players[Income.NEUTRAL_ID]
	for terr_id in out.territories.keys():
		var ts: Types.TerritoryState = out.territories[terr_id]
		if remap.has(ts.owner):
			ts.owner = remap[ts.owner]
	return out


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
			w.set_hex(str(ids[i]), Income.NEUTRAL_ID, map.neutral_leftover_armies)
			i += 1
	return w


static func apply_opening(world: Types.World, map: Types.MapDef, placements_by_player: Dictionary, capitals: Dictionary = {}, events: Array = []) -> void:
	## Simultaneous: caps from the post-deal snapshot, then apply.
	var caps := {}
	for terr_id in world.territories.keys():
		caps[str(terr_id)] = opening_cap(world, map, str(terr_id))
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
	## (first_digs_in) on every land the first soldier digs in, so every other man is free to march
	if map != null and map.first_digs_in:
		for terr_id in world.territories.keys():
			var t2: Types.TerritoryState = world.get_territory(str(terr_id))
			if t2.owner != Types.UNOCCUPIED and t2.owner != Income.NEUTRAL_ID and t2.garrison < 1 and t2.armies >= 1:
				t2.armies -= 1
				t2.garrison = 1
	## v1.8: every commander names a capital (after a draft, their first claim already is one)
	Capitals.found(world, map, capitals, events)
	Fortune.found(world, map) ## v1.8: every commander starts the war with one favour


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


# ---------------------------------------------------------------- the land draft (v1.4)
## "Claimed in turn": instead of a random deal, every commander throws a die for the
## order of choosing, then they claim lands one at a time, round the table, until each
## holds as many as the deal would have given. The two-seat doorstop is still pinned
## neutral first, and what nobody claims is left as the deal would leave it.

static func draft_world(map: Types.MapDef, seats: Array, match_seed: int) -> Types.World:
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	for seat in seats:
		var sid: String = str(seat.get("id", ""))
		w.players[sid] = make_player(sid, str(seat.get("name", sid.capitalize())), seat_color(sid))
	if seats.size() == 2:
		w.players[Income.NEUTRAL_ID] = make_player(Income.NEUTRAL_ID, "Neutral", "#6b6560")
		var pin: String = _draft_pin(map)
		if pin != "":
			var armies: int = NEUTRAL_GATE_ARMIES if _knife_duel(map) else (map.neutral_armies if map.neutral_armies > 0 else NEUTRAL_GATE_ARMIES)
			w.set_hex(pin, Income.NEUTRAL_ID, armies)
	return w


static func _knife_duel(map: Types.MapDef) -> bool:
	return map.deal_each <= 3 and map.territories.size() == 7


static func _draft_pin(map: Types.MapDef) -> String:
	if _knife_duel(map):
		return "gate" if map.get_territory("gate") != null else ""
	return map.pin_neutral if map.pin_neutral != "" and map.get_territory(map.pin_neutral) != null else ""


static func draft_quota(map: Types.MapDef, seat_count: int) -> int:
	## the lands each commander claims: exactly what the random deal would hand them
	if seat_count == 2:
		if _knife_duel(map):
			return 3
		var free: int = map.territories.size() - (1 if _draft_pin(map) != "" else 0)
		return mini(map.deal_each if map.deal_each > 0 else 9, free / 2)
	return map.territories.size() / maxi(1, seat_count)


static func order_roll(match_seed: int, pids: Array) -> Dictionary:
	## Everyone throws one die; ties throw again among themselves until every place is
	## settled. Returns {throws: [[{pid, die}]], order: [pid, ...]} — highest first.
	var throws: Array = []
	var order: Array = []
	var groups: Array = [pids.duplicate()]
	var k := 0
	while not groups.is_empty() and k < 40:
		var grp: Array = groups.pop_front()
		if grp.size() == 1:
			order.append(grp[0])
			continue
		var rng: RefCounted = Rng.derive_stream(match_seed, 0, "order|%d" % k)
		k += 1
		var t: Array = []
		for pid in grp:
			t.append({"pid": str(pid), "die": int(rng.roll_d6())})
		throws.append(t)
		## split into groups by die, highest first; each tied group throws again in place
		var by_die := {}
		for r in t:
			var d: int = int(r["die"])
			if not by_die.has(d):
				by_die[d] = []
			by_die[d].append(r["pid"])
		var dice: Array = by_die.keys()
		dice.sort()
		dice.reverse()
		var next: Array = []
		for d in dice:
			next.append(by_die[d])
		groups = next + groups
	return {"throws": throws, "order": order}


static func draft_turns(order: Array, quota: int, free: int) -> Array:
	## straight round the table in the rolled order, as in Risk, until everyone has their quota
	var turns: Array = []
	for r in quota:
		for pid in order:
			if turns.size() >= free:
				return turns
			turns.append(pid)
	return turns


static func finish_draft(w: Types.World, map: Types.MapDef, seat_count: int) -> void:
	## lands nobody claimed: the two-seat doorstop keeps them neutral, as the deal would
	if seat_count != 2 or not map.neutral_leftover or _knife_duel(map):
		return
	var ids: Array = Array(map.territory_ids())
	ids.sort()
	for t in ids:
		var ts: Types.TerritoryState = w.get_territory(str(t))
		if ts.owner == Types.UNOCCUPIED:
			w.set_hex(str(t), Income.NEUTRAL_ID, map.neutral_leftover_armies)
