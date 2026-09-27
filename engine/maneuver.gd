## The regroup phase (v1.3): after the battles, every commander may march troops
## between their own neighbouring lands. One land per army: only soldiers who were
## there when the phase began may leave, so nobody moves twice. Dug-in defenders never
## march, and a land with no dug-in defender keeps one soldier.
## Everyone writes their moves at once; they only touch their own lands, so the order
## they are applied in cannot matter. Pure: no Node, no RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")


static func can_leave(world: Types.World, terr_id: String) -> int:
	## soldiers that may march out of a land at the start of the phase
	return Income.max_send(world.get_territory(terr_id))


static func validate(world: Types.World, map: Types.MapDef, pid: String, moves: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var out := {}
	for m in moves:
		var from: String = str(m.get("from", ""))
		var to: String = str(m.get("to", ""))
		var n: int = int(m.get("n", 0))
		var a: Types.TerritoryState = world.get_territory(from)
		var b: Types.TerritoryState = world.get_territory(to)
		if a == null or b == null:
			errors.append("move: no such land")
			continue
		if a.owner != pid or b.owner != pid:
			errors.append("move %s -> %s: both lands must be yours" % [from, to])
			continue
		## v1.7: two of your own ports are joined by sea, so the march may go between them.
		if from == to or not Array(MapLib.supply_links(world, map, from)).has(to):
			errors.append("move %s -> %s: one land at a time" % [from, to])
			continue
		if n < 1:
			errors.append("move %s -> %s: nobody moves" % [from, to])
			continue
		out[from] = int(out.get(from, 0)) + n
	for from in out.keys():
		if int(out[from]) > can_leave(world, str(from)):
			errors.append("move from %s: only %d can leave" % [from, can_leave(world, str(from))])
	return errors


static func apply(world: Types.World, map: Types.MapDef, by_player: Dictionary) -> Array:
	## by_player: pid -> [{from, to, n}]. Mutates world. Returns Maneuvered events.
	## Invalid moves are dropped (the session only ever sends valid ones).
	var events: Array = []
	var pids: Array = by_player.keys()
	pids.sort()
	for pid in pids:
		var moves: Array = by_player[pid]
		if moves.is_empty() or not validate(world, map, str(pid), moves).is_empty():
			continue
		for m in _sorted(moves):
			var from: String = str(m["from"])
			var to: String = str(m["to"])
			var n: int = int(m["n"])
			world.get_territory(from).armies -= n
			world.get_territory(to).armies += n
			events.append({"kind": Types.EVENT_MANEUVERED, "playerId": str(pid), "from": from, "to": to, "strength": n,
				"fromArmies": world.get_territory(from).armies, "toArmies": world.get_territory(to).armies})
	return events


static func _sorted(moves: Array) -> Array:
	var out: Array = moves.duplicate()
	out.sort_custom(func(a, b): return "%s|%s" % [a["from"], a["to"]] < "%s|%s" % [b["from"], b["to"]])
	return out


static func plan(world: Types.World, map: Types.MapDef, pid: String, prof: Dictionary = {}) -> Array:
	## An AI's moves: march spare soldiers from quiet lands toward the fighting, and
	## from a well-held front to a neighbour that faces more than it can hold.
	## v1.4, the hard commanders (prof.search) march to strike, not just to hold: the rear
	## heads for the front that faces the richest, weakest prey, and a quiet front lends
	## its spare men to the neighbour that will attack next round.
	var mine: Array = Array(MapLib.player_territory_ids(world, pid))
	mine.sort()
	if mine.is_empty():
		return []
	var dist := _front_distance(world, map, pid, mine)
	var threat := {}
	for t in mine:
		threat[t] = _threat(world, map, pid, t)
	var striker: bool = bool(prof.get("search", false))
	var pull := {}
	if striker:
		pull = _pull(world, map, pid, mine, dist)
	var moves: Array = []
	var budget := {}
	for t in mine:
		budget[t] = can_leave(world, t)
	for t in mine:
		var spare: int = int(budget[t])
		if spare <= 0:
			continue
		var ts: Types.TerritoryState = world.get_territory(t)
		var friends: Array = []
		for n in MapLib.supply_links(world, map, t): ## v1.7: our own harbours are next door by sea
			if world.get_territory(n).owner == pid:
				friends.append(n)
		if friends.is_empty():
			continue
		friends.sort()
		if int(dist.get(t, 99)) > 0:
			## a quiet land: everyone who can goes one step closer to the front
			var best := ""
			for n in friends:
				if striker:
					## any step closer will do; go toward the best prey
					if int(dist.get(n, 99)) < int(dist.get(t, 99)) and (best == "" or float(pull.get(n, 0.0)) > float(pull.get(best, 0.0))):
						best = n
				elif best == "" or int(dist.get(n, 99)) < int(dist.get(best, 99)) or (int(dist.get(n, 99)) == int(dist.get(best, 99)) and float(threat[n]) > float(threat[best])):
					best = n
			if best != "" and int(dist.get(best, 99)) < int(dist.get(t, 99)):
				moves.append({"from": t, "to": best, "n": spare})
			continue
		## a front: keep enough to face our own threat, lend the rest to a harder-pressed front
		var keep: int = int(ceil(float(threat[t]) * 1.1)) - ts.garrison
		var give: int = mini(spare, ts.armies - maxi(keep, 1))
		if give <= 0:
			continue
		var worst := ""
		var worst_gap := 0.0
		for n in friends:
			if int(dist.get(n, 99)) != 0:
				continue
			var nts: Types.TerritoryState = world.get_territory(n)
			var gap: float = float(threat[n]) - float(nts.held())
			if gap > worst_gap + 0.5:
				worst_gap = gap
				worst = n
		if worst != "" and worst_gap >= 2.0:
			moves.append({"from": t, "to": worst, "n": mini(give, int(ceil(worst_gap)))})
		elif striker:
			## nobody next door is in trouble: mass on the front with the better prey
			var host := ""
			for n in friends:
				if int(dist.get(n, 99)) != 0:
					continue
				if float(pull.get(n, 0.0)) > float(pull.get(t, 0.0)) * 1.6 + 0.4 and (host == "" or float(pull.get(n, 0.0)) > float(pull.get(host, 0.0))):
					host = n
			if host != "":
				moves.append({"from": t, "to": host, "n": give})
	return moves


static func _prey(world: Types.World, map: Types.MapDef, pid: String, t: String) -> float:
	## how good the best attack from this front looks: worth over the men in the way
	var best := 0.0
	for e in MapLib.neighbors(map, t):
		var es: Types.TerritoryState = world.get_territory(e)
		if es.owner == pid:
			continue
		var worth := 1.0
		var td: Types.TerritoryDef = map.get_territory(e)
		if td != null and td.region != "" and map.region_bonus.has(td.region):
			var members := MapLib.region_members(map, td.region)
			var have := 0
			for m in members:
				if world.get_territory(m).owner == pid:
					have += 1
			worth += float(map.region_bonus[td.region]) * float(have + 1) / float(members.size())
			if es.owner != Types.UNOCCUPIED and MapLib.holds_region(world, map, es.owner, td.region):
				worth += float(map.region_bonus[td.region]) ## break their bonus
		if es.owner != Types.UNOCCUPIED and es.owner != "neutral":
			var left: int = MapLib.player_territory_ids(world, es.owner).size()
			if left <= 2:
				worth += 3.0 + 0.5 * float(world.players[es.owner].cards.size()) ## finish them, take the chest
		best = maxf(best, worth * 6.0 / float(es.held() + 2))
	return best


static func _pull(world: Types.World, map: Types.MapDef, pid: String, mine: Array, dist: Dictionary) -> Dictionary:
	## every land's draw toward the fighting: the best prey reachable, fading with distance
	var pull := {}
	var queue: Array = []
	for t in mine:
		if int(dist.get(t, 99)) == 0:
			pull[t] = _prey(world, map, pid, t)
			queue.append(t)
	var i := 0
	while i < queue.size():
		var t: String = queue[i]
		i += 1
		for n in MapLib.supply_links(world, map, t):
			if world.get_territory(n).owner != pid:
				continue
			var v: float = float(pull[t]) * 0.8
			if not pull.has(n) or v > float(pull[n]) + 0.001:
				if int(dist.get(n, 99)) > 0:
					pull[n] = maxf(float(pull.get(n, 0.0)), v)
					queue.append(n)
	return pull


static func _threat(world: Types.World, map: Types.MapDef, pid: String, t: String) -> float:
	## the biggest enemy stack next door (what could hit us next round)
	var worst := 0.0
	for n in MapLib.neighbors(map, t):
		var ns: Types.TerritoryState = world.get_territory(n)
		if ns.owner != pid and ns.owner != Types.UNOCCUPIED:
			worst = maxf(worst, float(ns.armies))
	return worst


static func _front_distance(world: Types.World, map: Types.MapDef, pid: String, mine: Array) -> Dictionary:
	## steps from each of our lands to one that borders an enemy (fronts are 0)
	var dist := {}
	var queue: Array = []
	for t in mine:
		for n in MapLib.neighbors(map, t):
			if world.get_territory(n).owner != pid:
				dist[t] = 0
				queue.append(t)
				break
	var i := 0
	while i < queue.size():
		var t: String = queue[i]
		i += 1
		for n in MapLib.supply_links(world, map, t): ## the march home may go by sea
			if world.get_territory(n).owner == pid and not dist.has(n):
				dist[n] = int(dist[t]) + 1
				queue.append(n)
	return dist
