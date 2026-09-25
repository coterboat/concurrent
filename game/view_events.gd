## Apply engine events onto a view-world for cinema. No Node. No RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")


static func apply(world: Types.World, event: Dictionary) -> void:
	var kind: String = str(event.get("kind", ""))
	match kind:
		Types.EVENT_VACATED:
			var from_id: String = str(event.get("from", ""))
			var left: int = int(event.get("originRemaining", 0))
			var ts: Types.TerritoryState = world.get_territory(from_id)
			if ts == null:
				return
			if left < 1:
				if ts.garrison < 1:
					world.set_hex(from_id, Types.UNOCCUPIED, 0)
				else:
					ts.armies = 0
			else:
				ts.armies = left
		Types.EVENT_PLACED:
			var terr_id: String = str(event.get("terrId", ""))
			var ts: Types.TerritoryState = world.get_territory(terr_id)
			if ts != null:
				ts.armies = int(event.get("armies", ts.armies))
		Types.EVENT_REGROUP_APPLIED:
			var from_ts: Types.TerritoryState = world.get_territory(str(event.get("from", "")))
			var to_ts: Types.TerritoryState = world.get_territory(str(event.get("to", "")))
			if from_ts != null:
				from_ts.armies = int(event.get("fromRemaining", from_ts.armies))
				## A dug-in garrison still holds the land after every mobile soldier walks.
				if from_ts.armies < 1 and from_ts.garrison < 1:
					world.set_hex(str(event.get("from", "")), Types.UNOCCUPIED, 0)
			if to_ts != null:
				to_ts.armies = int(event.get("toArmies", to_ts.armies))
		Types.EVENT_OCCUPIED:
			world.set_hex(str(event.get("terrId", "")), str(event.get("playerId", "")), int(event.get("armies", 1)))
		Types.EVENT_BECAME_UNOCCUPIED:
			world.set_hex(str(event.get("terrId", "")), Types.UNOCCUPIED, 0)
		Types.EVENT_INVASION:
			## reserves marched out of their home lands
			for r in event.get("reserves", []):
				var os: Types.TerritoryState = world.get_territory(str(r.get("from", "")))
				if os != null:
					os.armies = int(r.get("left", os.armies))
			if bool(event.get("pending", false)):
				return
			if bool(event.get("fellBack", false)):
				var rt: Types.TerritoryState = world.get_territory(str(event.get("refuge", "")))
				if rt != null:
					rt.armies = int(event.get("refugeArmies", rt.armies))
			if not bool(event.get("attackerWon", false)):
				var ts: Types.TerritoryState = world.get_territory(str(event.get("to", "")))
				if ts != null:
					## Same split as resolve: the garrison absorbs losses first.
					var remnant: int = int(event.get("winnerRemaining", ts.held()))
					if remnant >= ts.garrison:
						ts.armies = remnant - ts.garrison
					else:
						ts.garrison = maxi(0, remnant)
						ts.armies = 0
		Types.EVENT_SPOILS:
			var dest: String = str(event.get("to", ""))
			var winner_id: String = str(event.get("winnerId", ""))
			var rem: int = int(event.get("winnerRemaining", 1))
			var ts: Types.TerritoryState = world.get_territory(dest)
			if ts == null:
				return
			if ts.owner == winner_id:
				ts.armies = rem
			else:
				world.set_hex(dest, winner_id, rem)
		Types.EVENT_SURGE:
			var ts: Types.TerritoryState = world.get_territory(str(event.get("from", "")))
			if ts != null:
				ts.armies = int(event.get("originRemaining", 1))
		Types.EVENT_PLAYER_ELIMINATED:
			var ps: Types.PlayerState = world.players.get(str(event.get("playerId", "")), null)
			if ps != null:
				ps.alive = false
		Types.EVENT_ENTRENCHED:
			var ts: Types.TerritoryState = world.get_territory(str(event.get("terrId", "")))
			if ts != null:
				ts.garrison = int(event.get("garrison", ts.garrison))
		_:
			pass


static func apply_through(pre: Types.World, events: Array, last_index: int) -> Types.World:
	var w: Types.World = pre.clone()
	if last_index < 0:
		return w
	for i in range(0, mini(last_index + 1, events.size())):
		apply(w, events[i])
	return w


static func involved_hexes(event: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key in ["from", "to", "terrId", "hexA", "hexB"]:
		var v: Variant = event.get(key, "")
		if str(v) != "":
			out.append(str(v))
	return out


static func caption(event: Dictionary) -> String:
	var kind: String = str(event.get("kind", ""))
	match kind:
		Types.EVENT_VACATED:
			return "%s leaves %s with %s — %s walk toward %s." % [event.get("playerId"), event.get("from"), event.get("originRemaining"), event.get("strength"), event.get("to")]
		Types.EVENT_PLACED:
			return "%s places %s on %s." % [event.get("playerId"), event.get("added"), event.get("terrId")]
		Types.EVENT_REGROUP_APPLIED:
			return "%s regroups %s from %s to %s." % [event.get("playerId"), event.get("strength"), event.get("from"), event.get("to")]
		Types.EVENT_CLASH:
			return "Clash on the %s–%s border. %s %s vs %s %s. Dice %s–%s. %s keeps %s." % [event.get("hexA"), event.get("hexB"), event.get("playerA"), event.get("sizeA"), event.get("playerB"), event.get("sizeB"), event.get("dieA"), event.get("dieB"), event.get("winnerId"), event.get("winnerRemaining")]
		Types.EVENT_INVASION:
			var word: String = Combat.odds_word(int(event.get("attackerSize", 1)), int(event.get("defenderSize", 1)))
			var result: String = "takes it" if event.get("attackerWon") else "the garrison holds"
			return "Military advisor: %s %s vs %s %s at %s — %s. Dice %s–%s. %s." % [event.get("attackerId"), event.get("attackerSize"), event.get("defenderId"), event.get("defenderSize"), event.get("to"), word, event.get("attackerDie"), event.get("defenderDie"), result]
		Types.EVENT_SPOILS:
			return "Spoils at %s. %s keeps %s." % [event.get("to"), event.get("winnerId"), event.get("winnerRemaining")]
		Types.EVENT_SURGE:
			return "%s surges from %s into %s with %s." % [event.get("playerId"), event.get("from"), event.get("to"), event.get("strength")]
		Types.EVENT_OCCUPIED:
			return "%s occupies %s with %s." % [event.get("playerId"), event.get("terrId"), event.get("armies")]
		Types.EVENT_BECAME_UNOCCUPIED:
			return "%s is empty." % event.get("terrId")
		Types.EVENT_PLAYER_ELIMINATED:
			return "%s is eliminated." % event.get("playerId")
		Types.EVENT_SCORE:
			return "Score %s. Leader %s." % [event.get("scores"), event.get("leader")]
		Types.EVENT_ENTRENCHED:
			return "%s digs in (%s / %s)." % [event.get("terrId"), event.get("garrison"), event.get("cap")]
		Types.EVENT_ROUND_ENDED:
			var w: String = str(event.get("winner", ""))
			if w != "":
				return "Round %s ends. Winner: %s%s." % [event.get("round"), w, " (early)" if event.get("early") else ""]
			return "Round %s ends." % event.get("round")
		_:
			return kind


static func recap(events: Array, map = null) -> PackedStringArray:
	## F3 board: who got walked, who took what, score. Not a second cinema.
	var lines := PackedStringArray()
	var vacated := {} ## hex -> player who left
	var taken := {}
	for event in events:
		var kind: String = str(event.get("kind", ""))
		match kind:
			Types.EVENT_VACATED:
				vacated[str(event.get("from", ""))] = str(event.get("playerId", ""))
			Types.EVENT_BECAME_UNOCCUPIED:
				var hex: String = str(event.get("terrId", ""))
				var prev: String = str(event.get("previousOwner", ""))
				if vacated.has(hex):
					lines.append("%s is empty — %s marched off." % [_hex(map, hex), prev if prev != "" else vacated[hex]])
			Types.EVENT_OCCUPIED:
				var hex2: String = str(event.get("terrId", ""))
				var who: String = str(event.get("playerId", ""))
				taken[hex2] = true
				if vacated.has(hex2) and str(vacated[hex2]) != who:
					lines.append("Walk-in: %s takes %s (vacated by %s)." % [who, _hex(map, hex2), vacated[hex2]])
				else:
					lines.append("%s takes %s with %s." % [who, _hex(map, hex2), event.get("armies", 1)])
			Types.EVENT_CLASH:
				lines.append("Clash %s–%s: %s keeps %s." % [_hex(map, str(event.get("hexA", ""))), _hex(map, str(event.get("hexB", ""))), event.get("winnerId"), event.get("winnerRemaining")])
			Types.EVENT_INVASION:
				if bool(event.get("attackerWon", false)):
					var dest: String = str(event.get("to", ""))
					if not taken.has(dest):
						lines.append("%s captures %s." % [event.get("attackerId"), _hex(map, dest)])
				elif bool(event.get("fellBack", false)):
					lines.append("%s falls back from %s with %s." % [event.get("attackerId"), _hex(map, str(event.get("to", ""))), event.get("attackerLeft")])
				else:
					lines.append("%s holds %s." % [event.get("defenderId"), _hex(map, str(event.get("to", "")))])
			Types.EVENT_PLAYER_ELIMINATED:
				lines.append("%s is out." % event.get("playerId"))
			Types.EVENT_SCORE:
				lines.append("Score %s. Leader %s." % [_scores(event.get("scores", {})), event.get("leader")])
			Types.EVENT_ROUND_ENDED:
				var w: String = str(event.get("winner", ""))
				if w != "":
					lines.append("That's the game. %s wins%s." % [w, " early" if event.get("early") else ""])
				else:
					lines.append("Round %s is on the board." % event.get("round"))
	var dug := 0
	for event in events:
		if str(event.get("kind", "")) == Types.EVENT_ENTRENCHED:
			dug += 1
	if dug > 0:
		lines.append("%s held hexes dig in." % dug)
	if lines.is_empty():
		lines.append("Nothing moved.")
	return lines


static func _hex(map, terr_id: String) -> String:
	if map == null or terr_id == "":
		return terr_id
	var t = map.get_territory(terr_id)
	return t.display_name if t else terr_id


static func _scores(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return str(raw)
	var keys: Array = raw.keys()
	keys.sort()
	var bits: Array = []
	for k in keys:
		bits.append("%s %s" % [k, raw[k]])
	return ", ".join(bits)
