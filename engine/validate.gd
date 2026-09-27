## validate_sheet against the planning-window world (pre-lock).
## Packet legality is checked on the post-regroup, post-place projection
## because just-placed armies may attack this round.
## Cap overflow is not an error — it vanishes. Illegal leftover is an error.
## No Node. No UI. No RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Cards := preload("res://engine/cards.gd")


static func validate_sheet(world: Types.World, map: Types.MapDef, sheet: Types.Sheet) -> PackedStringArray:
	var errors := PackedStringArray()
	if sheet == null or sheet.player_id == "":
		errors.append("sheet missing playerId")
		return errors
	if sheet.player_id == Income.NEUTRAL_ID:
		errors.append("neutral does not plan")
		return errors
	var ps: Types.PlayerState = world.players.get(sheet.player_id, null)
	if ps == null or not ps.alive:
		errors.append("%s is not a living player" % sheet.player_id)
		return errors

	if sheet.cash_set.size() > 0:
		if not map.cards:
			errors.append("cards are off on this map")
		elif not Cards.is_set(Array(sheet.cash_set)):
			errors.append("those cards are not a set")
		elif not Cards.holds(ps.cards, sheet.cash_set):
			errors.append("you do not hold those cards")

	var projected: Types.World = world.clone()
	_validate_regroup(projected, map, sheet, errors)
	if errors.size() > 0:
		return errors
	_apply_regroup_to(projected, sheet)
	_apply_placements_to(projected, map, sheet) ## overflow lost, not an error
	_validate_packets(projected, map, sheet, errors)
	return errors


static func _validate_regroup(world: Types.World, map: Types.MapDef, sheet: Types.Sheet, errors: PackedStringArray) -> void:
	if sheet.regroup == null:
		return
	if world.round <= 1:
		errors.append("round 1 has no regroup")
		return
	var r: Types.Regroup = sheet.regroup
	if r.strength < 1:
		errors.append("regroup strength must be >= 1")
		return
	var from_ts: Types.TerritoryState = world.get_territory(r.from_id)
	var to_ts: Types.TerritoryState = world.get_territory(r.to_id)
	if from_ts == null or to_ts == null:
		errors.append("regroup hex does not exist")
		return
	if from_ts.owner != sheet.player_id or to_ts.owner != sheet.player_id:
		errors.append("regroup must be friendly to friendly")
		return
	if not Array(MapLib.supply_links(world, map, r.from_id)).has(r.to_id):
		errors.append("regroup requires adjacent hexes")
		return
	if r.from_id == r.to_id:
		errors.append("regroup to self")
		return
	var max_move: int = Income.max_send(from_ts)
	if r.strength > max_move:
		errors.append("illegal leftover: regroup %s sends %s" % [r.from_id, r.strength])


static func _apply_regroup_to(world: Types.World, sheet: Types.Sheet) -> void:
	if sheet.regroup == null:
		return
	var r: Types.Regroup = sheet.regroup
	var from_ts: Types.TerritoryState = world.get_territory(r.from_id)
	var to_ts: Types.TerritoryState = world.get_territory(r.to_id)
	from_ts.armies -= r.strength
	to_ts.armies += r.strength
	if from_ts.armies < 1 and from_ts.garrison < 1:
		world.set_hex(r.from_id, Types.UNOCCUPIED, 0)


static func cash_value_of(world: Types.World, map: Types.MapDef, sheet: Types.Sheet) -> int:
	## Armies a legal cashed set adds to this sheet's income. 0 if none or illegal.
	if sheet == null or sheet.cash_set.size() == 0 or not map.cards:
		return 0
	var ps: Types.PlayerState = world.players.get(sheet.player_id, null)
	if ps == null or not Cards.is_set(Array(sheet.cash_set)) or not Cards.holds(ps.cards, sheet.cash_set):
		return 0
	return Cards.set_value(world.sets_cashed)


static func _apply_placements_to(world: Types.World, map: Types.MapDef, sheet: Types.Sheet) -> void:
	var cashed: int = cash_value_of(world, map, sheet)
	var income: int = Income.income_of(world, map, sheet.player_id) + cashed
	if cashed > 0:
		## v1.6: a turned-in card's free soldier on its land (as the resolve queue does)
		for c in sheet.cash_set:
			var lt: Types.TerritoryState = world.get_territory(Cards.land(c)) if Cards.land(c) != "" else null
			if lt != null and lt.owner == sheet.player_id:
				lt.armies += 1
	var remaining := income
	var keys: Array = sheet.placements.keys()
	keys.sort()
	for terr_id in keys:
		if remaining <= 0:
			break
		var want: int = int(sheet.placements[terr_id])
		if want < 0:
			continue
		var ts: Types.TerritoryState = world.get_territory(str(terr_id))
		if ts == null or ts.owner != sheet.player_id:
			continue
		var cap: int = Income.cap_of(world, map, str(terr_id))
		var spent: int = mini(want, remaining)
		var add: int = mini(spent, cap)
		remaining -= spent
		if add > 0:
			ts.armies += add


static func _validate_packets(world: Types.World, map: Types.MapDef, sheet: Types.Sheet, errors: PackedStringArray) -> void:
	var outgoing := {} ## from_id -> total strength
	var i := 0
	for raw in sheet.packets:
		var p: Types.Packet = raw
		var tag := "packet[%s]" % i
		i += 1
		if p.strength < 1:
			errors.append("%s strength must be >= 1" % tag)
			continue
		var from_ts: Types.TerritoryState = world.get_territory(p.from_id)
		var to_ts: Types.TerritoryState = world.get_territory(p.to_id)
		if from_ts == null or to_ts == null:
			errors.append("%s hex does not exist" % tag)
			continue
		if from_ts.owner != sheet.player_id:
			errors.append("%s from is not yours" % tag)
			continue
		if not MapLib.is_adjacent(map, p.from_id, p.to_id):
			errors.append("%s to is not adjacent" % tag)
			continue
		if p.to_id == p.from_id:
			errors.append("%s to equals from" % tag)
			continue
		if to_ts.owner == sheet.player_id:
			errors.append("%s cannot attack a friendly hex" % tag)
			continue
		## v1.7: only so many can come through a pass at once, however many you have.
		var col: int = MapLib.column_cap(map, p.to_id)
		if col > 0 and p.strength > col:
			errors.append("%s only %s can storm %s at once" % [tag, col, p.to_id])
			continue
		if p.surge_to != "":
			if p.surge_to == p.from_id:
				errors.append("%s surgeTo cannot be from" % tag)
			elif not MapLib.is_adjacent(map, p.to_id, p.surge_to):
				errors.append("%s surgeTo must be adjacent to to" % tag)
		outgoing[p.from_id] = int(outgoing.get(p.from_id, 0)) + p.strength

	## v1.3 surges belong to the land being attacked
	for dest in sheet.surges.keys():
		var to: String = str(sheet.surges[dest])
		var attacked := false
		for raw in sheet.packets:
			if (raw as Types.Packet).to_id == str(dest):
				attacked = true
		if not attacked:
			errors.append("surge from %s: nothing attacks it" % dest)
		elif to == str(dest) or not MapLib.is_adjacent(map, str(dest), to):
			errors.append("surge from %s must go to a neighbouring land" % dest)

	## v1.5 a surge may carry a count: at least one man, and only for a surge that was ordered
	for dest in sheet.surge_n.keys():
		if not sheet.surges.has(dest):
			errors.append("surge count for %s: no surge from there" % dest)
		elif int(sheet.surge_n[dest]) < 1:
			errors.append("surge from %s must push on with at least one man" % dest)

	for from_id in outgoing.keys():
		var ts: Types.TerritoryState = world.get_territory(from_id)
		if ts == null:
			continue
		var max_out: int = Income.max_send(ts)
		if int(outgoing[from_id]) > max_out:
			errors.append("illegal leftover: %s sends %s leaving %s" % [from_id, outgoing[from_id], ts.armies - int(outgoing[from_id])])
