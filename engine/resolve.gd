## regroup → place → vacate → A clash → B invasion → C spoils → D surge → upkeep.
## One lock. Seed is not stored on World. No Node. No UI. No unseeded RNG.
## Battle calls (v1.2): an invasion stops after every exchange of three volleys for the
## attacker's call. Recorded calls (Sheet.calls) are replayed; a player in `live` with no
## recorded call pauses the whole round: the result carries "pending" and the events so
## far, and the caller resolves again once the call is on the sheet. Same inputs, same
## prefix, so a paused round and a replayed one agree exactly.
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
const Cards := preload("res://engine/cards.gd")
const Capitals := preload("res://engine/capitals.gd")
const Fortune := preload("res://engine/fortune.gd")


class Transit extends RefCounted:
	var owner: String = ""
	var from_id: String = ""
	var from_ids: PackedStringArray = PackedStringArray()
	var to_id: String = ""
	var strength: int = 0
	var surge_to: String = ""
	var surge_n: int = 0 ## v1.5: most men to push on (0 = all but one)


static func resolve_round(world: Types.World, map: Types.MapDef, sheets: Array, match_seed: int, live: Array = []) -> Dictionary:
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

	Combat.use_rules(map)
	var w: Types.World = world.clone()
	var held := {}
	for terr_id in world.territories.keys():
		held[str(terr_id)] = world.get_territory(str(terr_id)).owner
	var events: Array = []
	var ctx := _context(by_player, live)
	Capitals.apply_moves(w, map, by_player, events) ## v1.8: a capital moved the round after it fell
	_apply_regroups(w, map, by_player, events)
	_apply_placements(w, map, by_player, events)
	var transits: Array = _vacate(w, map, by_player, events)
	transits = _merge_same_owner(transits)
	transits = _resolve_clashes(w, map, transits, match_seed, events)
	var surge_book := {}
	_resolve_destinations(w, map, transits, match_seed, events, surge_book, ctx)
	if not (ctx["pending"] as Dictionary).is_empty():
		return {"world": w, "events": events, "errors": PackedStringArray(), "pending": ctx["pending"]}
	_resolve_surges(w, map, match_seed, events, surge_book, ctx)
	if not (ctx["pending"] as Dictionary).is_empty():
		return {"world": w, "events": events, "errors": PackedStringArray(), "pending": ctx["pending"]}
	_entrench(w, map, held, events)
	Capitals.upkeep(w, map, events, match_seed) ## v1.8: fallen capitals are plundered and named anew
	Fortune.upkeep(world, w, map, events) ## v1.8: Fortune pays the favours she owes
	_upkeep(w, map, events, held, match_seed)
	return {"world": w, "events": events, "errors": PackedStringArray()}


static func _context(by_player: Dictionary, live: Array) -> Dictionary:
	var calls := {}
	var stances := {}
	var auto := {}
	for pid in by_player.keys():
		var sheet: Types.Sheet = by_player[pid]
		calls[pid] = sheet.calls
		if sheet.fortune_auto:
			auto[pid] = true
		var st := {}
		for raw in sheet.packets:
			var p: Types.Packet = raw
			st[p.from_id + "|" + p.to_id] = p.stance
		stances[pid] = st
	var lv := {}
	for pid in live:
		lv[str(pid)] = true
	return {"calls": calls, "stances": stances, "live": lv, "pending": {}, "auto": auto}


static func _stance_of(ctx: Dictionary, t: Transit, dest: String) -> String:
	## A merged attack follows the order from its first origin (sorted).
	var st: Dictionary = ctx["stances"].get(t.owner, {})
	for f in _froms(t):
		var s: String = str(st.get(str(f) + "|" + dest, ""))
		if s != "":
			return s
	## a surge carries its origin order's stance (or none: to the last man)
	return str(ctx.get("surge_stance", {}).get(t.owner + "|" + t.from_id, ""))


static func reserves_available(w: Types.World, owner: String, froms: PackedStringArray) -> int:
	var n := 0
	for f in froms:
		var ts: Types.TerritoryState = w.get_territory(f)
		if ts != null and ts.owner == owner:
			n += Income.max_send(ts)
	return n


static func _column_room(map: Types.MapDef, dest: String, froms: PackedStringArray, a: int) -> int:
	## v1.7: how many more men may join a column storming a pass: at most the pass's cap
	## from each road in, reserves included. -1: no limit (open ground, or an older game).
	var col: int = MapLib.column_cap(map, dest)
	if col <= 0 or map.rules < 17:
		return -1
	return maxi(0, col * maxi(1, froms.size()) - a)


static func refuge_for(w: Types.World, map: Types.MapDef, owner: String, froms: PackedStringArray, dest: String) -> String:
	## Survivors fall back to where they marched from; if that is lost, to the
	## strongest friendly land bordering the battle. Nowhere: they are cut off.
	var ids: Array = Array(froms)
	ids.sort()
	for f in ids:
		var ts: Types.TerritoryState = w.get_territory(str(f))
		if ts != null and ts.owner == owner:
			return str(f)
	var best := ""
	var best_n := -1
	var ns: Array = Array(MapLib.neighbors(map, dest))
	ns.sort()
	for n in ns:
		var ts: Types.TerritoryState = w.get_territory(str(n))
		if ts != null and ts.owner == owner and ts.held() > best_n:
			best = str(n)
			best_n = ts.held()
	return best


static func _invade(w: Types.World, map: Types.MapDef, t: Transit, dest: String, key: String, match_seed: int, ctx: Dictionary) -> RefCounted:
	var ts: Types.TerritoryState = w.get_territory(dest)
	var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
	var fortify: int = MapLib.defender_bonus(w, map, dest) ## v1.7: a fortress fires a longer line (v1.8: a capital too)
	if map.battle != Combat.MODE_VOLLEYS:
		return Combat.invasion(t.strength, ts.held(), rng, map.battle, fortify)
	var fight = Combat.FightResult.new()
	fight.attacker_size = t.strength
	fight.defender_size = ts.held()
	var a: int = t.strength
	var d: int = ts.held()
	var recorded: Array = (ctx["calls"].get(t.owner, {}) as Dictionary).get(key, [])
	var stance: String = _stance_of(ctx, t, dest)
	var ci := 0
	var used_reserves := false
	var froms: PackedStringArray = _froms(t)
	var def_owner: String = ts.owner
	var def_recorded: Array = (ctx["calls"].get(def_owner, {}) as Dictionary).get(key, [])
	var dci := 0
	var fortuned := {} ## v1.8: "a"/"d" once that side has called on Fortune in this battle
	var luck_on: bool = map.rules >= 18
	fight.luck_kept = luck_on
	var guard := 0
	while a > 0 and d > 0 and guard < 4000:
		var a0: int = a
		var d0: int = d
		var r0: int = fight.rolls.size()
		var n := 0
		while n < Combat.EXCHANGE and a > 0 and d > 0 and guard < 4000:
			guard += 1
			var r: Dictionary = Combat.volley_once(a, d, rng, false, fortify)
			fight.rolls.append(r)
			fight.attacker_die = int(r["a"])
			fight.defender_die = int(r["b"])
			fight.attacker_total = Combat.VOLLEY_DIE * int(r["a"]) + Combat.fire(a)
			fight.defender_total = Combat.VOLLEY_DIE * int(r["b"]) + Combat.fire(d, fortify)
			## Amendment 18: an even volley is fired again. It costs nobody and it is not one
			## of the exchange's three. Before v1.7 the queue gave every even volley to the
			## defender, so a fought battle ran at 41.7% a volley where the sheet, the
			## advisor and the AI all quoted 50% — and a fortress changed nothing at all,
			## because its extra man only ever turned a tie into the same lost volley.
			if str(r["w"]) == "":
				if map.rules >= 17:
					fight.rerolls += 1
					continue
				## games begun before v1.7 replay as they were fought (the defender took it),
				## and the record now says so, so their battle report shows what happened
				r["w"] = "b"
			if str(r["w"]) == "a":
				d -= 1
			else:
				a -= 1
			n += 1
		## v1.8 Fortune: a disastrous exchange may be thrown again, once a battle for each side
		if map.fortune:
			var side: String = Fortune.bad_for(a0, d0, a, d)
			var chooser: String = t.owner if side == "a" else def_owner
			if side != "" and not fortuned.has(side) and Fortune.held(w, chooser) > 0:
				var dec := ""
				if side == "a" and ci < recorded.size():
					dec = str(recorded[ci])
					ci += 1
				elif side == "d" and dci < def_recorded.size():
					dec = str(def_recorded[dci])
					dci += 1
				elif (ctx["live"] as Dictionary).has(chooser):
					fight.pending = true
					fight.attacker_left = a
					fight.winner_remaining = d
					var pend := {"key": key, "attacker": t.owner, "defender": def_owner, "to": dest, "from": t.from_id,
						"a": a, "d": d, "a0": a0, "d0": d0, "stance": stance, "call": fight.calls.size(), "rolls": fight.rolls.size(),
						"fortune": true, "chooser": chooser, "side": side, "ended": a <= 0 or d <= 0,
						"fortunes": Fortune.held(w, chooser), "reserves": 0, "reserveFrom": [], "refuge": ""}
					if side == "a" and a > 0 and d > 0:
						## the attacker's call comes straight after: ask both on one plate
						var res0: int = 0 if used_reserves else reserves_available(w, t.owner, froms)
						var room0: int = _column_room(map, dest, froms, a)
						pend["reserves"] = mini(res0, room0) if room0 >= 0 else res0
						pend["reserveFrom"] = _reserve_sources(w, t.owner, froms)
						pend["refuge"] = refuge_for(w, map, t.owner, froms, dest)
					ctx["pending"] = pend
					return fight
				elif (ctx["auto"] as Dictionary).has(chooser):
					dec = Combat.CALL_FORTUNE if Fortune.doctrine(side, a0, d0, a, d, fortify, map.battle) else Combat.CALL_STAND
				else:
					dec = Combat.CALL_STAND ## a commander's favours are theirs to spend: never behind their back
				if dec == Combat.CALL_FORTUNE:
					fortuned[side] = true
					(w.players[chooser] as Types.PlayerState).fortune -= 1
					fight.calls.append({"at": fight.rolls.size(), "call": Combat.CALL_FORTUNE, "by": chooser, "side": side, "from": r0, "a": a0, "d": d0})
					a = a0
					d = d0
					continue
		if luck_on:
			## v1.9: the dice's share of the battle, measured one exchange at a time. What the
			## commander chose (reserves, falling back) and an exchange Fortune threw away are
			## not luck; every exchange that stands is, even in a battle abandoned halfway.
			fight.luck += Combat.capture_rate(a, d, map.battle, fortify) - Combat.capture_rate(a0, d0, map.battle, fortify)
		if a <= 0 or d <= 0:
			break
		## the call
		var reserves: int = 0 if used_reserves else reserves_available(w, t.owner, froms)
		var room: int = _column_room(map, dest, froms, a)
		if room >= 0:
			reserves = mini(reserves, room)
		var refuge: String = refuge_for(w, map, t.owner, froms, dest)
		var call := ""
		if ci < recorded.size():
			call = str(recorded[ci])
			ci += 1
		elif (ctx["live"] as Dictionary).has(t.owner):
			fight.pending = true
			fight.attacker_left = a
			fight.winner_remaining = d
			ctx["pending"] = {"key": key, "attacker": t.owner, "defender": ts.owner, "to": dest, "from": t.from_id,
				"a": a, "d": d, "reserves": reserves, "reserveFrom": _reserve_sources(w, t.owner, froms),
				"refuge": refuge, "stance": stance, "call": fight.calls.size(), "rolls": fight.rolls.size()}
			return fight
		else:
			call = Combat.doctrine(stance, a, d, reserves, refuge != "", fortify)
		if call == Combat.CALL_RESERVES and reserves <= 0:
			call = Combat.CALL_PRESS
		if call == Combat.CALL_FALL_BACK and refuge == "":
			call = Combat.CALL_PRESS
		var entry := {"at": fight.rolls.size(), "call": call}
		if call == Combat.CALL_RESERVES:
			used_reserves = true
			var added := 0
			for f in froms:
				var os: Types.TerritoryState = w.get_territory(f)
				if os == null or os.owner != t.owner:
					continue
				var k: int = Income.max_send(os)
				if room >= 0:
					k = mini(k, room - added) ## a pass: the road is only so wide
				if k <= 0:
					continue
				os.armies -= k
				added += k
				fight.reserves.append({"from": f, "n": k, "left": os.armies})
			a += added
			fight.reserves_added += added
			entry["n"] = added
			fight.calls.append(entry)
		elif call == Combat.CALL_FALL_BACK:
			entry["n"] = a
			entry["to"] = refuge
			fight.calls.append(entry)
			fight.fell_back = true
			fight.refuge = refuge
			fight.attacker_left = a
			break
		## a press is the default: not logged, so an order that never calls matches v1.1
	fight.attacker_won = d <= 0 and a > 0 and not fight.fell_back
	fight.winner_remaining = a if fight.attacker_won else d
	if fight.attacker_won:
		fight.attacker_left = a
	return fight


static func _reserve_sources(w: Types.World, owner: String, froms: PackedStringArray) -> Array:
	var out: Array = []
	for f in froms:
		var ts: Types.TerritoryState = w.get_territory(f)
		if ts != null and ts.owner == owner and Income.max_send(ts) > 0:
			out.append({"from": f, "n": Income.max_send(ts)})
	return out


static func _fall_back(w: Types.World, events: Array, owner: String, fight) -> void:
	## Survivors march to the refuge (always friendly: refuge_for checks it).
	var rt: Types.TerritoryState = w.get_territory(fight.refuge)
	if rt == null or rt.owner != owner:
		return
	rt.armies += fight.attacker_left
	fight.refuge_armies = rt.armies


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
	## Sets cashed this round all pay the table value at lock, then the counter moves.
	var pids: Array = by_player.keys()
	pids.sort()
	var cashed := 0
	for pid in pids:
		var sheet: Types.Sheet = by_player[pid]
		var bonus: int = Validate.cash_value_of(w, map, sheet)
		var income: int = Income.income_of(w, map, pid) + bonus
		if bonus > 0:
			var ps: Types.PlayerState = w.players[pid]
			ps.cards = Cards.without(ps.cards, sheet.cash_set)
			cashed += 1
			var cev: Dictionary = Events.set_cashed(pid, sheet.cash_set, bonus)
			## v1.6: a card naming a land you hold puts a free soldier there
			var free: Array = []
			for c in sheet.cash_set:
				var ln: String = Cards.land(c)
				var lt: Types.TerritoryState = w.get_territory(ln) if ln != "" else null
				if lt != null and lt.owner == pid:
					lt.armies += 1
					free.append(ln)
			if not free.is_empty():
				cev["lands"] = free
			events.append(cev)
			for ln in free:
				var lt2: Types.TerritoryState = w.get_territory(str(ln))
				var pev: Dictionary = Events.placed(pid, str(ln), 1, lt2.armies, 0)
				pev["cardBonus"] = true
				events.append(pev)
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
	w.sets_cashed += cashed


static func _vacate(w: Types.World, map: Types.MapDef, by_player: Dictionary, events: Array) -> Array:
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
			var dug := false
			if map.first_digs_in and ts.garrison < 1 and ts.armies >= 1:
				## (first_digs_in) the man who stays behind digs in
				ts.armies -= 1
				ts.garrison = 1
				dug = true
			var left: int = ts.armies
			if left < 1 and ts.garrison < 1:
				_take(w, events, p.from_id, Types.UNOCCUPIED, 0)
				left = 0
			elif left < 1:
				ts.armies = 0
				left = 0
			var vev: Dictionary = Events.vacated(pid, p.from_id, p.to_id, p.strength, left)
			if dug:
				vev["dugIn"] = 1
			events.append(vev)
			var t := Transit.new()
			t.owner = pid
			t.from_id = p.from_id
			t.from_ids = PackedStringArray([p.from_id])
			t.to_id = p.to_id
			t.strength = p.strength
			## v1.3: a surge is ordered from the land being taken, so every army that
			## converges on it pushes on together
			t.surge_to = str(sheet.surges.get(p.to_id, p.surge_to))
			t.surge_n = int(sheet.surge_n.get(p.to_id, 0))
			transits.append(t)
	return transits


static func _pkt_key(p: Types.Packet) -> String:
	return "%s|%s|%s" % [p.from_id, p.to_id, p.surge_to]


static func _resolve_clashes(w: Types.World, map: Types.MapDef, transits: Array, match_seed: int, events: Array, tag: String = "") -> Array:
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
		var key := "clash|%s%s|%s|%s|%s" % [tag, _min_s(a.from_id, a.to_id), _max_s(a.from_id, a.to_id), a.owner, b.owner]
		var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
		var fight = Combat.clash(a.strength, b.strength, rng, map.battle)
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
		merged.surge_n = int(bunch[0].surge_n) if surge_ok else 0
		out.append(merged)
	return out


static func _resolve_destinations(w: Types.World, map: Types.MapDef, transits: Array, match_seed: int, events: Array, surge_book: Dictionary, ctx: Dictionary = {}) -> void:
	if ctx.is_empty():
		ctx = {"calls": {}, "stances": {}, "live": {}, "pending": {}, "auto": {}}
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
		## v1.4 games: the owner's columns join the defence first; a lone comer fights (or
		## walks in); several commanders storm a held land in a melee, or scramble for an empty one
		if map.scramble and map.battle == Combat.MODE_VOLLEYS:
			if _land_v14(w, map, dest, pkts, match_seed, ctx, events, surge_book, ""):
				return
			continue
		## v1.3: two or more commanders storming a held land fight it at once
		if map.battle == Combat.MODE_VOLLEYS:
			var held_now: Types.TerritoryState = w.get_territory(dest)
			var invaders: Array = []
			for t in pkts:
				if t.strength >= 1 and t.owner != held_now.owner:
					invaders.append(t)
			if held_now.owner != Types.UNOCCUPIED and held_now.held() >= 1 and invaders.size() >= 2:
				for t in pkts:
					if t.strength >= 1 and t.owner == held_now.owner:
						held_now.armies += t.strength
				if _melee(w, map, dest, invaders, match_seed, ctx, events, surge_book):
					return
				continue
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
			var defense: int = ts.held()
			var fight
			if arrived_now:
				var rng: RefCounted = Rng.derive_stream(match_seed, w.round, key)
				fight = Combat.spoils(t.strength, defense, rng, map.battle)
				events.append(Events.spoils_event(dest, t.owner, ts.owner, fight))
			else:
				fight = _invade(w, map, t, dest, key, match_seed, ctx)
				if fight.pending:
					events.append(Events.invasion_event(t.from_id, dest, t.owner, ts.owner, fight))
					return
				if fight.fell_back:
					_fall_back(w, events, t.owner, fight)
				events.append(Events.invasion_event(t.from_id, dest, t.owner, ts.owner, fight))
			if fight.attacker_won:
				_take(w, events, dest, t.owner, fight.winner_remaining)
				_remember_surge(surge_book, dest, t)
				arrived_now = true
			else:
				_apply_defender_remnant(ts, fight.winner_remaining)


static func _melee(w: Types.World, map: Types.MapDef, dest: String, invaders: Array, match_seed: int, ctx: Dictionary, events: Array, surge_book: Dictionary, tag: String = "") -> bool:
	## Every salvo, each invader fights its own volley against the defender, who splits
	## his weight across the fronts in proportion to the invaders: score = 5 x die + share,
	## share = defenders x invader / all invaders. Each volley's loser loses one, so the
	## defender can lose a man on every front at once, or win on all of them.
	## Battle calls come front by front after every exchange. When the defender is gone,
	## the survivors fight for the spoils. Returns true if the round pauses for a call.
	var ts: Types.TerritoryState = w.get_territory(dest)
	var defender: String = ts.owner
	var d0: int = ts.held()
	var d: int = d0
	var rng: RefCounted = Rng.derive_stream(match_seed, w.round, "melee|" + tag + dest)
	var fortify: int = MapLib.defender_bonus(w, map, dest) ## v1.7: a fortress fires a longer line on every front (v1.8: a capital too)
	var fronts: Array = []
	for t in invaders:
		fronts.append({"t": t, "a": t.strength, "size": t.strength, "key": "invasion|%s%s|%s|%s" % [tag, dest, t.owner, t.from_id],
			"stance": _stance_of(ctx, t, dest), "ci": 0, "used": false, "fell": false, "reserves": [], "added": 0,
			"calls": [], "refuge": "", "refuge_armies": 0})
	var salvos: Array = []
	var pending := false
	while d > 0 and _fronts_alive(fronts) > 0:
		var n := 0
		while n < Combat.EXCHANGE and d > 0 and _fronts_alive(fronts) > 0:
			var tot := 0
			for f in fronts:
				if _front_up(f):
					tot += int(f["a"])
			var salvo: Array = []
			var loss := 0
			for i in fronts.size():
				var f: Dictionary = fronts[i]
				if not _front_up(f):
					continue
				var share: float = float(d) * float(f["a"]) / float(tot)
				var da: int = rng.roll_d6()
				var db: int = rng.roll_d6()
				if Combat.line > 0:
					## v1.6: the defenders' whole firing line faces every front, and an even
					## volley costs nobody (the same loss ratio as one combined attack)
					var fa: int = Combat.fire(int(f["a"]))
					var fd: int = Combat.fire(d, fortify)
					var sa2: int = Combat.VOLLEY_DIE * da + fa
					var sd2: int = Combat.VOLLEY_DIE * db + fd
					var w2: String = "a" if sa2 > sd2 else ("b" if sd2 > sa2 else "")
					salvo.append({"i": i, "a": da, "b": db, "sa": int(f["a"]), "sd": d, "fa": fa, "fd": fd, "w": w2})
					if w2 == "a":
						loss += 1
					elif w2 == "b":
						f["a"] = int(f["a"]) - 1
					continue
				var won: bool = float(Combat.VOLLEY_DIE * da + int(f["a"])) >= float(Combat.VOLLEY_DIE * db) + share
				salvo.append({"i": i, "a": da, "b": db, "sa": int(f["a"]), "sd": snappedf(share, 0.1), "w": "a" if won else "b"})
				if won:
					loss += 1
				else:
					f["a"] = int(f["a"]) - 1
			d = maxi(0, d - loss)
			salvos.append(salvo)
			n += 1
		if d <= 0 or _fronts_alive(fronts) == 0:
			break
		## the calls, front by front
		var tot2 := 0
		for f in fronts:
			if _front_up(f):
				tot2 += int(f["a"])
		for i in fronts.size():
			var f: Dictionary = fronts[i]
			if not _front_up(f):
				continue
			var t: Transit = f["t"]
			var froms: PackedStringArray = _froms(t)
			var reserves: int = 0 if bool(f["used"]) else reserves_available(w, t.owner, froms)
			var room: int = _column_room(map, dest, froms, int(f["a"]))
			if room >= 0:
				reserves = mini(reserves, room)
			var refuge: String = refuge_for(w, map, t.owner, froms, dest)
			var share_now: int = d if Combat.line > 0 else maxi(1, int(round(float(d) * float(f["a"]) / float(maxi(1, tot2)))))
			var recorded: Array = (ctx["calls"].get(t.owner, {}) as Dictionary).get(f["key"], [])
			var call := ""
			if int(f["ci"]) < recorded.size():
				call = str(recorded[int(f["ci"])])
				f["ci"] = int(f["ci"]) + 1
			elif (ctx["live"] as Dictionary).has(t.owner):
				ctx["pending"] = {"key": f["key"], "attacker": t.owner, "defender": defender, "to": dest, "from": t.from_id,
					"a": int(f["a"]), "d": share_now, "dTotal": d, "reserves": reserves, "reserveFrom": _reserve_sources(w, t.owner, froms),
					"refuge": refuge, "stance": f["stance"], "call": (f["calls"] as Array).size(), "rolls": salvos.size(),
					"melee": true, "front": i}
				pending = true
				break
			else:
				call = Combat.doctrine(str(f["stance"]), int(f["a"]), share_now, reserves, refuge != "", fortify)
			if call == Combat.CALL_RESERVES and reserves <= 0:
				call = Combat.CALL_PRESS
			if call == Combat.CALL_FALL_BACK and refuge == "":
				call = Combat.CALL_PRESS
			if call == Combat.CALL_RESERVES:
				f["used"] = true
				var added := 0
				for fr in froms:
					var os: Types.TerritoryState = w.get_territory(fr)
					if os == null or os.owner != t.owner:
						continue
					var k: int = Income.max_send(os)
					if room >= 0:
						k = mini(k, room - added)
					if k <= 0:
						continue
					os.armies -= k
					added += k
					(f["reserves"] as Array).append({"from": fr, "n": k, "left": os.armies})
				f["a"] = int(f["a"]) + added
				f["added"] = int(f["added"]) + added
				(f["calls"] as Array).append({"at": salvos.size(), "call": call, "n": added})
			elif call == Combat.CALL_FALL_BACK:
				f["fell"] = true
				f["refuge"] = refuge
				var rt: Types.TerritoryState = w.get_territory(refuge)
				rt.armies += int(f["a"])
				f["refuge_armies"] = rt.armies
				(f["calls"] as Array).append({"at": salvos.size(), "call": call, "n": int(f["a"]), "to": refuge})
		if pending:
			break
	var ev := {"kind": Types.EVENT_MELEE, "to": dest, "defenderId": defender, "defenderSize": d0, "defenderLeft": d, "salvos": salvos, "fronts": []}
	for f in fronts:
		var t2: Transit = f["t"]
		var fd := {"attackerId": t2.owner, "from": t2.from_id, "fromIds": Array(_froms(t2)), "size": int(f["size"]), "left": int(f["a"])}
		if int(f["added"]) > 0:
			fd["reservesAdded"] = int(f["added"])
			fd["reserves"] = f["reserves"]
		if not (f["calls"] as Array).is_empty():
			fd["calls"] = f["calls"]
		if bool(f["fell"]):
			fd["fellBack"] = true
			fd["refuge"] = f["refuge"]
			fd["refugeArmies"] = int(f["refuge_armies"])
		(ev["fronts"] as Array).append(fd)
	if pending:
		ev["pending"] = true
		events.append(ev)
		return true
	events.append(ev)
	if d > 0:
		_apply_defender_remnant(ts, d)
		return false
	## the defender is gone: whoever is left fights for the prize
	var alive: Array = []
	for f in fronts:
		if _front_up(f):
			alive.append(f)
	if map.scramble and alive.size() >= 2:
		## v1.4: the victors turn on each other all at once
		var sides: Array = []
		for f in alive:
			sides.append({"t": f["t"], "a": int(f["a"])})
		var won: Dictionary = _scramble(w, dest, sides, match_seed, events, tag + "melee")
		_take(w, events, dest, (won["t"] as Transit).owner, int(won["a"]))
		_remember_surge(surge_book, dest, won["t"])
		return false
	var champ: Dictionary = alive[0]
	for i in range(1, alive.size()):
		var other: Dictionary = alive[i]
		var ta: Transit = champ["t"]
		var tb: Transit = other["t"]
		var srng: RefCounted = Rng.derive_stream(match_seed, w.round, "spoils|melee|%s|%s|%s" % [dest, ta.owner, tb.owner])
		var fight = Combat.spoils(int(champ["a"]), int(other["a"]), srng, map.battle)
		events.append(Events.spoils_event(dest, ta.owner, tb.owner, fight))
		if fight.attacker_won:
			champ["a"] = fight.winner_remaining
		else:
			other["a"] = fight.winner_remaining
			champ = other
	var winner: Transit = champ["t"]
	_take(w, events, dest, winner.owner, int(champ["a"]))
	_remember_surge(surge_book, dest, winner)
	return false


static func _front_up(f: Dictionary) -> bool:
	return int(f["a"]) > 0 and not bool(f["fell"])


static func _fronts_alive(fronts: Array) -> int:
	var n := 0
	for f in fronts:
		if _front_up(f):
			n += 1
	return n


static func _land_v14(w: Types.World, map: Types.MapDef, dest: String, pkts: Array, match_seed: int, ctx: Dictionary, events: Array, surge_book: Dictionary, tag: String) -> bool:
	## Everything arriving at one land this step, settled at once. True if paused for a call.
	var ts: Types.TerritoryState = w.get_territory(dest)
	var invaders: Array = []
	for t in pkts:
		if t.strength < 1:
			continue
		if ts.owner != Types.UNOCCUPIED and t.owner == ts.owner:
			ts.armies += t.strength ## the owner's own column arrives in time to man the walls
			_remember_surge(surge_book, dest, t)
		else:
			invaders.append(t)
	if invaders.is_empty():
		return false
	if ts.owner != Types.UNOCCUPIED and ts.held() >= 1:
		if invaders.size() >= 2:
			return _melee(w, map, dest, invaders, match_seed, ctx, events, surge_book, tag)
		var t0: Transit = invaders[0]
		var defender: String = ts.owner
		var fight = _invade(w, map, t0, dest, "invasion|%s%s|%s|%s" % [tag, dest, t0.owner, t0.from_id], match_seed, ctx)
		if fight.pending:
			events.append(Events.invasion_event(t0.from_id, dest, t0.owner, defender, fight))
			return true
		if fight.fell_back:
			_fall_back(w, events, t0.owner, fight)
		events.append(Events.invasion_event(t0.from_id, dest, t0.owner, defender, fight))
		if fight.attacker_won:
			_take(w, events, dest, t0.owner, fight.winner_remaining)
			_remember_surge(surge_book, dest, t0)
		else:
			_apply_defender_remnant(ts, fight.winner_remaining)
		return false
	## nobody home: one comer walks in, several fight it out among themselves
	if invaders.size() == 1:
		var t1: Transit = invaders[0]
		_take(w, events, dest, t1.owner, t1.strength)
		_remember_surge(surge_book, dest, t1)
		return false
	var sides: Array = []
	for t in invaders:
		sides.append({"t": t, "a": t.strength})
	var won: Dictionary = _scramble(w, dest, sides, match_seed, events, tag + "empty")
	_take(w, events, dest, (won["t"] as Transit).owner, int(won["a"]))
	_remember_surge(surge_book, dest, won["t"])
	return false


static func _scramble(w: Types.World, dest: String, sides: Array, match_seed: int, events: Array, key: String) -> Dictionary:
	## sides: [{t: Transit, a}] of different commanders. One free-for-all (Combat.scramble);
	## returns the last army standing {t, a}.
	var sizes: Array = []
	for sd in sides:
		sizes.append(int(sd["a"]))
	var rng: RefCounted = Rng.derive_stream(match_seed, w.round, "scramble|%s|%s" % [key, dest])
	var r: Dictionary = Combat.scramble(sizes, rng)
	var fronts: Array = []
	for k in sides.size():
		var t: Transit = sides[k]["t"]
		fronts.append({"playerId": t.owner, "from": t.from_id, "fromIds": Array(_froms(t)), "size": int(sizes[k]), "left": int(r["left"][k])})
	var win: int = int(r["winner"])
	events.append({"kind": Types.EVENT_SCRAMBLE, "to": dest, "fronts": fronts, "salvos": r["salvos"],
		"winnerId": (sides[win]["t"] as Transit).owner, "winnerLeft": int(r["left"][win]), "after": key.get_slice("|", key.get_slice_count("|") - 1)})
	return {"t": sides[win]["t"], "a": int(r["left"][win])}


static func _remember_surge(surge_book: Dictionary, dest: String, t: Transit) -> void:
	surge_book[dest] = {"owner": t.owner, "surge_to": t.surge_to, "from": t.from_id, "froms": _froms(t), "n": t.surge_n}


static func _resolve_surges(w: Types.World, map: Types.MapDef, match_seed: int, events: Array, surge_book: Dictionary, ctx: Dictionary = {}) -> void:
	if ctx.is_empty():
		ctx = {"calls": {}, "stances": {}, "live": {}, "pending": {}}
	## a surge fights under the stance of the order that broke through
	var surge_stance := {}
	for dest in surge_book.keys():
		var info: Dictionary = surge_book[dest]
		var st: Dictionary = ctx["stances"].get(str(info.get("owner", "")), {})
		for f in info.get("froms", PackedStringArray([str(info.get("from", ""))])):
			var s: String = str(st.get(str(f) + "|" + str(dest), ""))
			if s != "":
				surge_stance[str(info.get("owner", "")) + "|" + str(dest)] = s
				break
	ctx["surge_stance"] = surge_stance
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
		if map.rules >= 15 and int(info.get("n", 0)) > 0:
			strength = mini(strength, int(info["n"])) ## v1.5: the count the surge was ordered with, at most
		if map.rules >= 17 and MapLib.column_cap(map, surge_to) > 0:
			strength = mini(strength, MapLib.column_cap(map, surge_to)) ## v1.7: a pass takes a column of six, surge or not
		ts.armies -= strength
		events.append(Events.surge_event(ts.owner, dest, surge_to, strength, ts.armies))
		var t := Transit.new()
		t.owner = ts.owner
		t.from_id = dest
		t.from_ids = PackedStringArray([dest])
		t.to_id = surge_to
		t.strength = strength
		surges.append(t)
	if surges.is_empty():
		return
	if map.rules >= 15:
		## v1.5: two surges running at each other's lands meet in the field, like any border clash
		surges = _resolve_clashes(w, map, surges, match_seed, events, "surge|")
	var by_dest := {}
	for t in surges:
		if not by_dest.has(t.to_id):
			by_dest[t.to_id] = []
		by_dest[t.to_id].append(t)
	var surge_dests: Array = by_dest.keys()
	surge_dests.sort()
	if map.scramble and map.battle == Combat.MODE_VOLLEYS:
		var spent := {} ## a surge never surges again
		for dest in surge_dests:
			var pk: Array = _merge_same_owner(by_dest[dest])
			pk.sort_custom(func(a, b): return _order_key(match_seed, w.round, "surge|" + dest, a) < _order_key(match_seed, w.round, "surge|" + dest, b))
			if _land_v14(w, map, dest, pk, match_seed, ctx, events, spent, "surge|"):
				return
		return
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
			var fight = Combat.spoils(a.strength, b.strength, rng, map.battle)
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
		var inv = _invade(w, map, champ, dest, ikey, match_seed, ctx)
		if inv.pending:
			events.append(Events.invasion_event(champ.from_id, dest, champ.owner, ts.owner, inv))
			return
		if inv.fell_back:
			_fall_back(w, events, champ.owner, inv)
		events.append(Events.invasion_event(champ.from_id, dest, champ.owner, ts.owner, inv))
		if inv.attacker_won:
			_take(w, events, dest, champ.owner, inv.winner_remaining)
		else:
			_apply_defender_remnant(ts, inv.winner_remaining)


static func _apply_defender_remnant(ts: Types.TerritoryState, remnant: int) -> void:
	## The field army takes the losses first; the dug-in men behind the walls are the last
	## to fall. Survivors fill the garrison first, then the army.
	var g: int = ts.garrison
	if remnant >= g:
		ts.armies = remnant - g
	else:
		ts.garrison = maxi(0, remnant)
		ts.armies = 0


static func _entrench(w: Types.World, map: Types.MapDef, held: Dictionary, events: Array) -> void:
	## +1 dug-in on land you still own from the start of the round, up to cap.
	## (first_digs_in: a land with nobody dug in, a fresh conquest, digs in its first soldier instead)
	var ids: Array = w.territories.keys()
	ids.sort()
	for terr_id in ids:
		var ts: Types.TerritoryState = w.get_territory(str(terr_id))
		if ts == null or ts.owner == Types.UNOCCUPIED:
			continue
		if map.first_digs_in and ts.garrison < 1 and ts.armies >= 1 and ts.owner != Income.NEUTRAL_ID:
			ts.armies -= 1
			ts.garrison = 1
			var ev: Dictionary = Events.entrenched(str(terr_id), 1, Income.garrison_cap(w, map, str(terr_id)))
			ev["converted"] = 1
			events.append(ev)
			continue
		if str(held.get(str(terr_id), "")) != ts.owner:
			continue
		var cap: int = Income.garrison_cap(w, map, str(terr_id))
		if cap < 1 or ts.garrison >= cap:
			continue
		ts.garrison += 1
		events.append(Events.entrenched(str(terr_id), ts.garrison, cap))


static func _upkeep(w: Types.World, map: Types.MapDef, events: Array, held: Dictionary, match_seed: int) -> void:
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
			if map.rules >= 18:
				_divide_spoils(w, events, held, str(pid), match_seed)
			else:
				_hand_over_cards(w, events, held, str(pid))
		else:
			living.append(pid)
	if map.cards:
		var taken := {} ## v1.6: land cards in anyone's hand
		if map.rules >= 16:
			for q in w.players.keys():
				for c in (w.players[q] as Types.PlayerState).cards:
					if Cards.land(c) != "":
						taken[Cards.land(c)] = true
		for pid in living:
			var ps: Types.PlayerState = w.players[pid]
			if ps.cards.size() >= Cards.HAND_LIMIT or not _captured_any(w, held, str(pid)):
				continue
			var card: String
			if map.rules >= 16:
				card = Cards.draw_land(match_seed, w.round, str(pid), Array(map.territory_ids()), taken)
				taken[Cards.land(card)] = true
			else:
				card = Cards.draw(match_seed, w.round, str(pid), map.territories.size(), map.wild_cards)
			ps.cards.append(card)
			events.append(Events.card_drawn(str(pid), card))

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


static func _captured_any(w: Types.World, held: Dictionary, pid: String) -> bool:
	for terr_id in w.territories.keys():
		var ts: Types.TerritoryState = w.territories[terr_id]
		if ts.owner == pid and str(held.get(str(terr_id), "")) != pid:
			return true
	return false


static func _hand_over_cards(w: Types.World, events: Array, held: Dictionary, victim: String) -> void:
	## Cards go to whoever took the victim's last land (latest capture in queue order).
	## If the land was only emptied, the hand is discarded.
	var ps: Types.PlayerState = w.players[victim]
	if ps.cards.is_empty():
		return
	var taker := ""
	for e in events:
		if str(e.get("kind", "")) != Types.EVENT_OCCUPIED:
			continue
		var terr_id: String = str(e.get("terrId", ""))
		var from_victim: bool = str(e.get("previousOwner", "")) == victim or (not e.has("previousOwner") and str(held.get(terr_id, "")) == victim)
		if from_victim and str(e.get("playerId", "")) != victim:
			taker = str(e.get("playerId", ""))
		elif str(e.get("playerId", "")) == victim:
			taker = "" ## they took something back later: only the very last loss counts
	if taker != "" and w.players.has(taker) and taker != Income.NEUTRAL_ID:
		var to: Types.PlayerState = w.players[taker]
		for c in ps.cards:
			to.cards.append(c)
		events.append(Events.cards_captured(victim, taker, ps.cards))
	ps.cards = PackedStringArray()


static func _divide_spoils(w: Types.World, events: Array, held: Dictionary, victim: String, match_seed: int) -> void:
	## v1.9 (rules 18): a war chest is divided among everyone who took the fallen commander's
	## lands this round, since they all fell at once. Each taker throws a die, and the cards
	## are shared out in proportion to the throws (the highest thrower first for what is
	## left over). A lone taker gets it all, as before; a land only emptied takes nothing.
	var ps: Types.PlayerState = w.players[victim]
	if ps.cards.is_empty():
		return
	var takers: Array = []
	for e in events:
		if str(e.get("kind", "")) != Types.EVENT_OCCUPIED:
			continue
		var terr_id: String = str(e.get("terrId", ""))
		var from_victim: bool = str(e.get("previousOwner", "")) == victim or (not e.has("previousOwner") and str(held.get(terr_id, "")) == victim)
		var by: String = str(e.get("playerId", ""))
		if from_victim and by != victim and by != Income.NEUTRAL_ID and w.players.has(by) and not takers.has(by):
			takers.append(by)
	if takers.is_empty():
		ps.cards = PackedStringArray()
		return
	var hand: Array = Array(ps.cards)
	ps.cards = PackedStringArray()
	if takers.size() == 1:
		var to: Types.PlayerState = w.players[takers[0]]
		for c in hand:
			to.cards.append(c)
		events.append(Events.cards_captured(victim, str(takers[0]), PackedStringArray(hand)))
		return
	takers.sort()
	var rng: RefCounted = Rng.derive_stream(match_seed, w.round, "spoils|cards|" + victim)
	var rolls := {}
	var tiebreak := {}
	var total := 0
	for pid in takers:
		rolls[pid] = rng.roll_d6()
		tiebreak[pid] = rng.roll_d6()
		total += int(rolls[pid])
	## the order of the throws: the highest first (a tie is thrown off again)
	var order: Array = takers.duplicate()
	order.sort_custom(func(x, y):
		if int(rolls[x]) != int(rolls[y]):
			return int(rolls[x]) > int(rolls[y])
		if int(tiebreak[x]) != int(tiebreak[y]):
			return int(tiebreak[x]) > int(tiebreak[y])
		return str(x) < str(y))
	## shares in proportion to the throws; the cards left over go down the order
	var shares := {}
	var given := 0
	for pid in order:
		shares[pid] = int(hand.size() * int(rolls[pid]) / total)
		given += int(shares[pid])
	var k := 0
	while given < hand.size():
		shares[order[k % order.size()]] = int(shares[order[k % order.size()]]) + 1
		given += 1
		k += 1
	## which cards: drawn by lot from the hand, the highest thrower drawing first
	for i in range(hand.size() - 1, 0, -1):
		var j: int = rng.rand_index(i + 1)
		var tmp = hand[i]
		hand[i] = hand[j]
		hand[j] = tmp
	var split := {"rolls": rolls, "shares": shares, "order": order, "of": hand.size()}
	var at := 0
	for pid in order:
		var n: int = int(shares[pid])
		var got := PackedStringArray()
		for q in n:
			got.append(str(hand[at]))
			at += 1
		var to: Types.PlayerState = w.players[pid]
		for c in got:
			to.cards.append(c)
		var ev: Dictionary = Events.cards_captured(victim, str(pid), got)
		ev["split"] = split
		events.append(ev)


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
		var e: Dictionary = Events.occupied(owner, terr_id, armies)
		e["previousOwner"] = prev
		events.append(e)


static func _order_key(match_seed: int, round: int, dest: String, t: Transit) -> String:
	var n: int = Hash.mix_battle(match_seed, round, "order|%s|%s|%s" % [dest, t.owner, t.from_id])
	return "%010d|%s|%s" % [n, t.owner, t.from_id]


static func _min_s(a: String, b: String) -> String:
	return a if a < b else b


static func _max_s(a: String, b: String) -> String:
	return a if a > b else b
