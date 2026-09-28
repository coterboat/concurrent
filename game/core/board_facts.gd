## v1.13: what the planning map says that the engine already knows. Pure functions of a world
## (no Node, no UI, no RNG): the board draws them, the land tooltip words them, the tests pin them.
## Display only; nothing here changes an outcome.
##   threats: how much could land on each of your lands next round, and from whom
##   hinges:  your lands that hold the road home for others (supply maps)
##   shares:  who holds how much of each region
##   ways_in: how many crossings lead into a region, and where
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")


static func threats(w: Types.World, map: Types.MapDef, pid: String) -> Dictionary:
	## land -> {max, owner, from, held, danger, capital}. `max` is the biggest single commander's
	## punch (every man they can march from their bordering lands, plus the most they could place
	## there); `held` is everyone on the land. A land is in `danger` when that punch clearly
	## outnumbers it; a capital, as soon as it could be outnumbered at all.
	var out := {}
	var cap: String = MapLib.capital_of(w, map, pid)
	for t in MapLib.player_territory_ids(w, pid):
		var th: Dictionary = threat_on(w, map, pid, str(t))
		if th.is_empty():
			continue
		var ts: Types.TerritoryState = w.get_territory(str(t))
		var held: int = ts.armies + ts.garrison
		var mx: int = int(th["max"])
		var is_cap: bool = str(t) == cap
		var danger: bool = (mx > held) if is_cap else (mx >= held + 3 and float(mx) >= float(held) * 1.5)
		out[str(t)] = {"max": mx, "owner": str(th["owner"]), "from": str(th["from"]), "held": held, "danger": danger, "capital": is_cap}
	return out


static func threat_on(w: Types.World, map: Types.MapDef, pid: String, t: String) -> Dictionary:
	## {owner, max, from}: the biggest single-owner punch that could land on t, everyone who can
	## march from their bordering lands plus what they could place there ({} when nobody borders it)
	var by_owner := {}
	var from := {}
	for n in MapLib.neighbors(map, t):
		var ns: Types.TerritoryState = w.get_territory(n)
		var o: String = ns.owner
		if o == pid or o == Types.UNOCCUPIED or o == Income.NEUTRAL_ID:
			continue
		var punch: int = Income.max_send(ns) + mini(Income.cap_of(w, map, n), Income.income_of(w, map, o))
		by_owner[o] = int(by_owner.get(o, 0)) + punch
		if not from.has(o) or punch > int(from[o][1]):
			from[o] = [n, punch]
	var best := {}
	for o in by_owner.keys():
		if best.is_empty() or int(by_owner[o]) > int(best["max"]):
			best = {"owner": o, "max": int(by_owner[o]), "from": from[o][0]}
	return best


static func hinges(w: Types.World, map: Types.MapDef, pid: String) -> Dictionary:
	## land -> [the lands of yours it would cut off if it fell]. Supply maps only, and never the
	## capital (if it falls the court flees, and the road home runs somewhere new).
	var out := {}
	if map == null or not map.supply:
		return out
	var fed: Dictionary = MapLib.supplied_ids(w, map, pid)
	var cap: String = MapLib.capital_of(w, map, pid)
	for t in fed.keys():
		if str(t) == cap:
			continue
		var ts: Types.TerritoryState = w.get_territory(str(t))
		var was: String = ts.owner
		ts.owner = Income.NEUTRAL_ID ## as if it fell (put back below: the world is borrowed)
		var still: Dictionary = MapLib.supplied_ids(w, map, pid)
		ts.owner = was
		var lost: Array = []
		for o in fed.keys():
			if str(o) != str(t) and not still.has(o):
				lost.append(str(o))
		if not lost.is_empty():
			lost.sort()
			out[str(t)] = lost
	return out


static func shares(w: Types.World, map: Types.MapDef) -> Dictionary:
	## region -> {members, by: {owner: n}, leader, led, to_go}. `to_go` is how many lands the
	## leader still needs (0: they hold it all). Empty and neutral lands count for nobody.
	var out := {}
	for r in map.region_bonus.keys():
		var members: PackedStringArray = MapLib.region_members(map, str(r))
		var by := {}
		for t in members:
			var o: String = w.get_territory(t).owner
			if o == Types.UNOCCUPIED or o == Income.NEUTRAL_ID:
				continue
			by[o] = int(by.get(o, 0)) + 1
		var leader := ""
		for o in by.keys():
			if leader == "" or int(by[o]) > int(by[leader]) or (int(by[o]) == int(by[leader]) and str(o) < leader):
				leader = str(o)
		var led: int = int(by.get(leader, 0))
		out[str(r)] = {"members": members, "by": by, "leader": leader, "led": led, "to_go": members.size() - led}
	return out


static func ways_in(map: Types.MapDef, region: String) -> Array:
	## [[outside, inside], ...]: every crossing into the region, sorted
	var inside := {}
	for t in MapLib.region_members(map, region):
		inside[t] = true
	var out: Array = []
	for t in inside.keys():
		for n in MapLib.neighbors(map, str(t)):
			if not inside.has(n):
				out.append([str(n), str(t)])
	out.sort_custom(func(a, b): return str(a[1]) + str(a[0]) < str(b[1]) + str(b[0]))
	return out
