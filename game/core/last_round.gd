## v1.13: last round's marches as they went, for the planning map's ghost arrows. Every column a
## commander sent, and what became of it: it took the land, it was thrown back, it fell back, it
## was beaten in a scramble, or it met the other side's column on the border and died there.
## Display only: nothing here is saved or hashed, and the session rebuilds it from each round it
## absorbs (save replay included), so a loaded game shows the same arrows.
extends RefCounted

const Types := preload("res://engine/types.gd")

const TOOK := "took" ## it holds the land it marched on
const THROWN_BACK := "thrown_back" ## beaten at the walls, and none came home
const FELL_BACK := "fell_back" ## beaten, and the survivors fell back
const OUTFOUGHT := "outfought" ## beaten in a scramble, or in the fight for the spoils
const CLASH := "clash" ## met the other side's column on the border and lost there
const MISSED := "missed" ## didn't end the round holding it, for any other reason
const FAILED := [THROWN_BACK, FELL_BACK, OUTFOUGHT, CLASH, MISSED]


static func ghosts(before: Types.World, after: Types.World, sheets: Array, events: Array) -> Array:
	## [{from, to, strength, owner, surgeTo, result, by, left, fellTo, surgeFate, surgeBy}] for every
	## packet sent. `result` is "" for a march between your own lands; `by` is who beat it; `left`
	## how many fell back (FELL_BACK) to `fellTo`. `surgeFate` is CLASH when the surge it sent on
	## met another on the border and died there.
	## The engine marches all of a commander's columns bound for one land as one (their first
	## origin names it), so a fate belongs to every column with that owner and destination.
	var packets := {} ## owner -> [Packet]
	for s in sheets:
		var sh: Types.Sheet = s
		packets[sh.player_id] = sh.packets
	var beaten := {} ## "pid|to" -> the clash's winner: those columns died on the border
	var surge_beaten := {} ## "pid|captured land|surge_to" -> the winner
	var surged := {}
	var surge_phase := false
	for e in events:
		match str(e.get("kind", "")):
			Types.EVENT_SURGE:
				surge_phase = true
				surged[str(e.get("playerId", "")) + "|" + str(e.get("from", ""))] = true
			Types.EVENT_CLASH:
				## A marched hexA -> hexB (hexA: the first origin of its column); B marched from
				## hexB (among others) to one of A's origins
				var pa: String = str(e.get("playerA", ""))
				var pb: String = str(e.get("playerB", ""))
				var ha: String = str(e.get("hexA", ""))
				var hb: String = str(e.get("hexB", ""))
				var won: String = str(e.get("winnerId", ""))
				if surge_phase:
					## two surges met: each ran from the land it had just taken to the other's
					if won == pa:
						surge_beaten[pb + "|" + hb + "|" + ha] = won
					else:
						surge_beaten[pa + "|" + ha + "|" + hb] = won
				elif won == pb:
					beaten[pa + "|" + hb] = won
				else:
					beaten[pb + "|" + _clash_target(packets.get(pa, []), packets.get(pb, []), ha, hb)] = won
	var out: Array = []
	for s in sheets:
		var sh: Types.Sheet = s
		for p in sh.packets:
			var pk: Types.Packet = p
			var pid: String = sh.player_id
			var key: String = pid + "|" + pk.to_id
			var g := {"from": pk.from_id, "to": pk.to_id, "strength": pk.strength, "owner": pid,
				"surgeTo": pk.surge_to if surged.has(key) else "", "result": "", "by": "", "left": 0, "fellTo": "", "surgeFate": "", "surgeBy": ""}
			var was: Types.TerritoryState = before.get_territory(pk.to_id) if before != null else null
			var now: Types.TerritoryState = after.get_territory(pk.to_id) if after != null else null
			if beaten.has(key):
				g["result"] = CLASH
				g["by"] = beaten[key]
			elif was != null and was.owner == pid:
				pass ## a march between your own lands: nothing to say
			elif now != null and now.owner == pid:
				g["result"] = TOOK
			else:
				_why(g, pid, events, now)
			var sk: String = key + "|" + pk.surge_to
			if str(g["surgeTo"]) != "" and surge_beaten.has(sk):
				g["surgeFate"] = CLASH
				g["surgeBy"] = surge_beaten[sk]
			out.append(g)
	return out


static func _clash_target(a_packets: Array, b_packets: Array, ha: String, hb: String) -> String:
	## B lost a border clash: B's column ran from hb to one of A's origins (A's columns bound for hb)
	var a_from := {ha: true}
	for p in a_packets:
		if (p as Types.Packet).to_id == hb:
			a_from[(p as Types.Packet).from_id] = true
	for p in b_packets:
		var pk: Types.Packet = p
		if pk.from_id == hb and a_from.has(pk.to_id):
			return pk.to_id
	return ha


static func _why(g: Dictionary, pid: String, events: Array, now: Types.TerritoryState) -> void:
	## the fight at the column's destination that it lost (all of pid's columns there marched as one)
	var to: String = str(g["to"])
	g["result"] = MISSED
	g["by"] = now.owner if now != null and now.owner != Types.UNOCCUPIED else ""
	for e in events:
		var kind: String = str(e.get("kind", ""))
		if str(e.get("to", "")) != to:
			continue
		match kind:
			Types.EVENT_INVASION:
				if str(e.get("attackerId", "")) == pid and not bool(e.get("attackerWon", false)):
					g["by"] = str(e.get("defenderId", ""))
					if bool(e.get("fellBack", false)):
						g["result"] = FELL_BACK
						g["left"] = int(e.get("attackerLeft", 0))
						g["fellTo"] = str(e.get("refuge", ""))
					else:
						g["result"] = THROWN_BACK
					return
			Types.EVENT_MELEE:
				for f in e.get("fronts", []):
					if str(f.get("attackerId", "")) != pid:
						continue
					if int(e.get("defenderLeft", 0)) <= 0 and not bool(f.get("fellBack", false)) and int(f.get("left", 0)) > 0:
						continue ## the walls fell and this front stood: it lost what came after (a scramble)
					g["by"] = str(e.get("defenderId", ""))
					if bool(f.get("fellBack", false)):
						g["result"] = FELL_BACK
						g["left"] = int(f.get("left", 0))
						g["fellTo"] = str(f.get("refuge", ""))
					else:
						g["result"] = THROWN_BACK
					return
			Types.EVENT_SCRAMBLE:
				for f in e.get("fronts", []):
					if str(f.get("playerId", "")) == pid and str(e.get("winnerId", "")) != pid:
						g["result"] = OUTFOUGHT
						g["by"] = str(e.get("winnerId", ""))
						return
			Types.EVENT_SPOILS:
				if (str(e.get("playerA", "")) == pid or str(e.get("playerB", "")) == pid) and str(e.get("winnerId", "")) != pid:
					g["result"] = OUTFOUGHT
					g["by"] = str(e.get("winnerId", ""))
					return


static func said(g: Dictionary, name_of: Callable, hex_name: Callable) -> String:
	## one line for a ghost's fate: "Varek's 7 were thrown back by Dad." ("" when there's nothing to say)
	var n: int = int(g["strength"])
	var who: String = ("%s's %d" % [name_of.call(str(g["owner"])), n]) if n != 1 else "%s's lone man" % name_of.call(str(g["owner"]))
	var were: String = "were" if n != 1 else "was"
	var by: String = str(g.get("by", ""))
	var by_s: String = (" by %s" % name_of.call(by)) if by != "" and by != Types.UNOCCUPIED else ""
	match str(g.get("result", "")):
		TOOK:
			return "%s took it." % who
		THROWN_BACK:
			return "%s %s thrown back%s." % [who, were, by_s]
		FELL_BACK:
			var to: String = str(g.get("fellTo", ""))
			return "%s %s beaten%s; %d fell back%s." % [who, were, by_s, int(g.get("left", 0)), (" to %s" % hex_name.call(to)) if to != "" else ""]
		OUTFOUGHT:
			return "%s %s beaten%s in the fight for it." % [who, were, by_s]
		CLASH:
			return "%s never got there: %s's column met them on the border." % [who, name_of.call(by)]
		MISSED:
			return "%s didn't hold it." % who
	return ""
