## regroup → place → vacate → A clash → B invasion → C spoils → D surge → upkeep.
## One lock. Seed is not stored on World. No Node. No UI. No unseeded RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Events := preload("res://engine/events.gd")
const MapLib := preload("res://engine/map.gd")
const Setup := preload("res://engine/setup.gd")


class Transit extends RefCounted:
	var owner: String = ""
	var from_id: String = ""
	var from_ids: PackedStringArray = PackedStringArray()
	var to_id: String = ""
	var strength: int = 0
	var surge_to: String = ""


static func resolve_round(world: Types.World, map: Types.MapDef, sheets: Array, match_seed: int) -> Dictionary:
	var errors := PackedStringArray()
	var by_player := {}
	for raw in sheets:
		var sheet: Types.Sheet = raw
		if sheet == null:
			continue
		if by_player.has(sheet.player_id):
			errors.append("duplicate sheet for %s" % sheet.player_id)
			continue
		by_player[sheet.player_id] = sheet
		for err in Validate.validate_sheet(world, map, sheet):
			errors.append(err)
	if errors.size() > 0:
		return {"world": world, "events": [], "errors": errors}

	var w: Types.World = world.clone()
	var held := {}
	for terr_id in world.territories.keys():
		held[str(terr_id)] = world.get_territory(str(terr_id)).owner
	var events: Array = []
	_apply_regroups(w, map, by_player, events)
	_apply_placements(w, map, by_player, events)
	var transits: Array = _vacate(w, by_player, events)
	transits = _merge_same_owner(transits)
	transits = _resolve_clashes(w, transits, match_seed, events)
	var surge_book := {}
	_resolve_destinations(w, transits, match_seed, events, surge_book)
	_resolve_surges(w, map, match_seed, events, surge_book)
	_entrench(w, map, held, events)
	_upkeep(w, map, events)
	return {"world": w, "events": events, "errors": PackedStringArray()}


static func _apply_regroups(w: Types.World, map: Types.MapDef, by_player: Dictionary, events: Array) -> void:
	if w.round <= 1:
		return
	var pids: Array = by_player.keys()
	pids.sort()
	for pid in pids:
		var sheet: Types.Sheet = by_player[pid]
		if sheet.regroup == null:
			continue
		Validate._apply_regroup_to(w, sheet)
		var r: Types.Regroup = sheet.regroup
		var from_ts: Types.TerritoryState = w.get_territory(r.from_id)
		var to_ts: Types.TerritoryState = w.get_territory(r.to_id)
		events.append(Events.regroup_applied(pid, r.from_id, r.to_id, r.strength, from_ts.armies, to_ts.armies))


static func _apply_placements(w: Types.World, map: Types.MapDef, by_player: Dictionary, events: Array) -> void:
	var pids: Array = by_player.keys()
	pids.sort()
	for pid in pids:
		var sheet: Types.Sheet = by_player[pid]
		var income: int = Income.income_of(w, map, pid)
		var remaining := income
		var keys: Array = sheet.placements.keys()
		keys.sort()
		for terr_id in keys:
			var want: int = int(sheet.placements[terr_id])
			if want <= 0:
				continue
			var ts: Types.TerritoryState = w.get_territory(str(terr_id))
			if ts == null or ts.owner != pid:
				continue
			var cap: int = Income.cap_of(w, map, str(terr_id))
			var spent: int = mini(want, remaining)
			var add: int = mini(spent, cap)
			var overflow: int = spent - add
			remaining -= spent
			if add > 0:
				ts.armies += add
			if add > 0 or overflow > 0:
				events.append(Events.placed(pid, str(terr_id), add, ts.armies, overflow))


static func _vacate(w: Types.World, by_player: Dictionary, events: Array) -> Array:
	var transits: Array = []
	var pids: Array = by_player.keys()
	pids.sort()
	for pid in pids:
		var sheet: Types.Sheet = by_player[pid]
		var packets: Array = sheet.packets.duplicate()
		packets.sort_custom(func(a, b): return _pkt_key(a) < _pkt_key(b))
		for raw in packets:
			var p: Types.Packet = raw
			var ts: Types.TerritoryState = w.get_territory(p.from_id)
			ts.armies -= p.strength
			var left: int = ts.armies
			if left < 1 and ts.garrison < 1:
				_take(w, events, p.from_id, Types.UNOCCUPIED, 0)
				left = 0
			elif left < 1:
				ts.armies = 0
				left = 0
			events.append(Events.vacated(pid, p.from_id, p.to_id, p.strength, left))
			var t := Transit.new()
			t.owner = pid
			t.from_id = p.from_id
			t.from_ids = PackedStringArray([p.from_id])
			t.to_id = p.to_id
			t.strength = p.strength
			t.surge_to = p.surge_to
			transits.append(t)
	return transits


static func _pkt_key(p: Types.Packet) -> String:
	return "%s|%s|%s" % [p.from_id, p.to_id, p.surge_to]


static func _resolve_clashes(w: Types.World, transits: Array, match_seed: int, events: Array) -> Array:
	var pairs: Array = []
	for i in transits.size():
		for j in range(i + 1, transits.size()):
			var a: Transit = transits[i]
			var b: Transit = transits[j]
			if a.owner == b.owner:
				continue
			if _is_reciprocal(a, b):
				pairs.append([a, b])
	pairs.sort_custom(func(x, y): return _clash_key(x[0], x[1]) < _clash_key(y[0], y[1]))
	var used := {}
	for pair in pairs:
		var a: Transit = pair[0]
		var b: Transit = pair[1]
		if used.has(a) or used.has(b) or a.strength < 1 or b.strength < 1:
			continue
		used[a] = true
		used[b] = true
		if a.owner > b.owner:
			var tmp: Transit = a
			a = b
			b = tmp
		var key := "clash|%s|%s|%s|%s" % [_min_s(a.from_id, a.to_id), _max_s(a.from_id, a.to_id), a.owner, b.owner]
		var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
		var fight = Combat.clash(a.strength, b.strength, rng)
		events.append(Events.clash_event(a.from_id, a.to_id, a.owner, b.owner, fight))
		if fight.attacker_won:
			a.strength = fight.winner_remaining
			b.strength = 0
		else:
			b.strength = fight.winner_remaining
			a.strength = 0
	var leftover: Array = []
	for t in transits:
		if t.strength >= 1:
			leftover.append(t)
	return leftover


static func _clash_key(a: Transit, b: Transit) -> String:
	return "%s|%s|%s|%s" % [_min_s(a.from_id, a.to_id), _max_s(a.from_id, a.to_id), _min_s(a.owner, b.owner), _max_s(a.owner, b.owner)]


static func _froms(t: Transit) -> PackedStringArray:
	if t.from_ids.size() > 0:
		return t.from_ids
	return PackedStringArray([t.from_id])


static func _is_reciprocal(a: Transit, b: Transit) -> bool:
	return _contains(_froms(b), a.to_id) and _contains(_froms(a), b.to_id)


static func _contains(ids: PackedStringArray, id: String) -> bool:
	for x in ids:
		if x == id:
			return true
	return false


static func _merge_same_owner(transits: Array) -> Array:
	var groups := {}
	var order: Array = []
	for t in transits:
		var k := "%s|%s" % [t.owner, t.to_id]
		if not groups.has(k):
			groups[k] = []
			order.append(k)
		groups[k].append(t)
	var out: Array = []
	for k in order:
		var bunch: Array = groups[k]
		if bunch.size() == 1:
			out.append(bunch[0])
			continue
		var merged: Transit = Transit.new()
		merged.owner = bunch[0].owner
		merged.to_id = bunch[0].to_id
		var froms: Array = []
		var surge := str(bunch[0].surge_to)
		var surge_ok := true
		for t in bunch:
			merged.strength += t.strength
			for f in _froms(t):
				if not froms.has(f):
					froms.append(f)
			if t.surge_to != surge:
				surge_ok = false
		froms.sort()
		merged.from_id = str(froms[0])
		merged.from_ids = PackedStringArray(froms)
		merged.surge_to = surge if surge_ok else ""
		out.append(merged)
	return out


static func _resolve_destinations(w: Types.World, transits: Array, match_seed: int, events: Array, surge_book: Dictionary) -> void:
	var by_dest := {}
	for t in transits:
		if not by_dest.has(t.to_id):
			by_dest[t.to_id] = []
		by_dest[t.to_id].append(t)
	var dests: Array = by_dest.keys()
	dests.sort()
	for dest in dests:
		var pkts: Array = by_dest[dest]
		pkts.sort_custom(func(a, b): return _order_key(match_seed, w.round, dest, a) < _order_key(match_seed, w.round, dest, b))
		var arrived_now := false
		for t in pkts:
			if t.strength < 1:
				continue
			var ts: Types.TerritoryState = w.get_territory(dest)
			if ts.owner == Types.UNOCCUPIED or ts.held() < 1:
				_take(w, events, dest, t.owner, t.strength)
				_remember_surge(surge_book, dest, t)
				arrived_now = true
				continue
			if ts.owner == t.owner:
				ts.armies += t.strength
				_remember_surge(surge_book, dest, t)
				continue
			var key := "invasion|%s|%s|%s" % [dest, t.owner, t.from_id]
			var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
			var defense: int = ts.held()
			var fight
			if arrived_now:
				fight = Combat.spoils(t.strength, defense, rng)
				events.append(Events.spoils_event(dest, t.owner, ts.owner, fight))
			else:
				fight = Combat.invasion(t.strength, defense, rng)
				events.append(Events.invasion_event(t.from_id, dest, t.owner, ts.owner, fight))
			if fight.attacker_won:
				_take(w, events, dest, t.owner, fight.winner_remaining)
				_remember_surge(surge_book, dest, t)
				arrived_now = true
			else:
				_apply_defender_remnant(ts, fight.winner_remaining)


static func _remember_surge(surge_book: Dictionary, dest: String, t: Transit) -> void:
	surge_book[dest] = {"owner": t.owner, "surge_to": t.surge_to, "from": t.from_id}


static func _resolve_surges(w: Types.World, map: Types.MapDef, match_seed: int, events: Array, surge_book: Dictionary) -> void:
	var dests: Array = surge_book.keys()
	dests.sort()
	var surges: Array = []
	for dest in dests:
		var info: Dictionary = surge_book[dest]
		var ts: Types.TerritoryState = w.get_territory(dest)
		var surge_to: String = str(info.get("surge_to", ""))
		if ts == null or ts.owner != str(info.get("owner", "")):
			continue
		if surge_to == "" or ts.armies < 2:
			continue
		if not MapLib.is_adjacent(map, dest, surge_to):
			continue
		var target: Types.TerritoryState = w.get_territory(surge_to)
		if target == null:
			continue
		if target.owner == ts.owner:
			continue
		var strength: int = ts.armies - 1
		ts.armies = 1
		events.append(Events.surge_event(ts.owner, dest, surge_to, strength, 1))
		var t := Transit.new()
		t.owner = ts.owner
		t.from_id = dest
		t.from_ids = PackedStringArray([dest])
		t.to_id = surge_to
		t.strength = strength
		surges.append(t)
	if surges.is_empty():
		return
	var by_dest := {}
	for t in surges:
		if not by_dest.has(t.to_id):
			by_dest[t.to_id] = []
		by_dest[t.to_id].append(t)
	var surge_dests: Array = by_dest.keys()
	surge_dests.sort()
	for dest in surge_dests:
		var pkts: Array = _merge_same_owner(by_dest[dest])
		pkts.sort_custom(func(a, b): return _order_key(match_seed, w.round, "surge|" + dest, a) < _order_key(match_seed, w.round, "surge|" + dest, b))
		var champ: Transit = pkts[0]
		for i in range(1, pkts.size()):
			var a: Transit = champ
			var b: Transit = pkts[i]
			if a.owner == b.owner:
				champ.strength += b.strength
				continue
			if a.owner > b.owner:
				var tmp: Transit = a
				a = b
				b = tmp
			var key := "spoils|surge|%s|%s|%s" % [dest, a.owner, b.owner]
			var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
			var fight = Combat.spoils(a.strength, b.strength, rng)
			events.append(Events.spoils_event(dest, a.owner, b.owner, fight))
			champ = a if fight.attacker_won else b
			champ.strength = fight.winner_remaining
		var ts: Types.TerritoryState = w.get_territory(dest)
		if ts.owner == champ.owner:
			continue
		if ts.owner == Types.UNOCCUPIED or ts.held() < 1:
			_take(w, events, dest, champ.owner, champ.strength)
			continue
		var ikey := "invasion|surge|%s|%s|%s" % [dest, champ.owner, champ.from_id]
		var irng: RefCounted = Rng.derive_stream(match_seed, w.round, ikey)
		var inv = Combat.invasion(champ.strength, ts.held(), irng)
		events.append(Events.invasion_event(champ.from_id, dest, champ.owner, ts.owner, inv))
		if inv.attacker_won:
			_take(w, events, dest, champ.owner, inv.winner_remaining)
		else:
			_apply_defender_remnant(ts, inv.winner_remaining)


static func _apply_defender_remnant(ts: Types.TerritoryState, remnant: int) -> void:
	## Garrison eats hits first. Remnant sits garrison, then mobile.
	var g: int = ts.garrison
	if remnant >= g:
		ts.armies = remnant - g
	else:
		ts.garrison = maxi(0, remnant)
		ts.armies = 0


static func _entrench(w: Types.World, map: Types.MapDef, held: Dictionary, events: Array) -> void:
	## +1 dug-in on land you still own from the start of the round, up to cap.
	var ids: Array = w.territories.keys()
	ids.sort()
	for terr_id in ids:
		var ts: Types.TerritoryState = w.get_territory(str(terr_id))
		if ts == null or ts.owner == Types.UNOCCUPIED:
			continue
		if str(held.get(str(terr_id), "")) != ts.owner:
			continue
		var cap: int = Income.garrison_cap(w, map, str(terr_id))
		if cap < 1 or ts.garrison >= cap:
			continue
		ts.garrison += 1
		events.append(Events.entrenched(str(terr_id), ts.garrison, cap))


static func _upkeep(w: Types.World, map: Types.MapDef, events: Array) -> void:
	var living: Array = []
	var pids: Array = w.players.keys()
	pids.sort()
	for pid in pids:
		if str(pid).begins_with("__"):
			continue
		var ps: Types.PlayerState = w.players[pid]
		if not ps.alive:
			continue
		if pid == Income.NEUTRAL_ID:
			continue
		var n: int = MapLib.player_territory_ids(w, pid).size()
		if n == 0:
			ps.alive = false
			events.append(Events.player_eliminated(pid))
		else:
			living.append(pid)

	var scores := {}
	var leader := ""
	var best := [-1, -1, -1] ## score, regions, armies
	for pid in living:
		var sc: int = Income.score_of(w, map, pid)
		var regions := 0
		for region in map.region_bonus.keys():
			if MapLib.holds_region(w, map, pid, str(region)):
				regions += 1
		var armies := 0
		for terr_id in MapLib.player_territory_ids(w, pid):
			var ts: Types.TerritoryState = w.get_territory(terr_id)
			armies += ts.armies + ts.garrison
		scores[pid] = sc
		var tup := [sc, regions, armies]
		if _better(tup, best) or leader == "":
			best = tup
			leader = pid
	events.append(Events.score(scores, leader))

	var winner := ""
	var early := false
	var max_rounds: int = Setup.rounds_for(map)
	var threshold: int = Setup.early_end_threshold(map)
	if living.size() <= 1:
		winner = living[0] if living.size() == 1 else leader
		early = true
	else:
		for pid in living:
			if MapLib.player_territory_ids(w, pid).size() >= threshold:
				winner = pid
				early = true
				break
		if winner == "" and w.round >= max_rounds:
			winner = leader
	events.append(Events.round_ended(w.round, winner, early))
	w.round += 1


static func _better(a: Array, b: Array) -> bool:
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return int(a[i]) > int(b[i])
	return false


static func _take(w: Types.World, events: Array, terr_id: String, owner: String, armies: int) -> void:
	var ts: Types.TerritoryState = w.get_territory(terr_id)
	var prev: String = ts.owner
	if armies < 1 or owner == Types.UNOCCUPIED:
		if prev != Types.UNOCCUPIED:
			events.append(Events.became_unoccupied(terr_id, prev))
		w.set_hex(terr_id, Types.UNOCCUPIED, 0)
		return
	w.set_hex(terr_id, owner, armies)
	if prev != owner:
		events.append(Events.occupied(owner, terr_id, armies))


static func _order_key(match_seed: int, round: int, dest: String, t: Transit) -> String:
	var n: int = Hash.mix_battle(match_seed, round, "order|%s|%s|%s" % [dest, t.owner, t.from_id])
	return "%010d|%s|%s" % [n, t.owner, t.from_id]


static func _min_s(a: String, b: String) -> String:
	return a if a < b else b


static func _max_s(a: String, b: String) -> String:
	return a if a > b else b
