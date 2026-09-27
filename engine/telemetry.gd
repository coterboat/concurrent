## Match JSONL for G6 tuning. No Node. No UI. No RNG.
## One object per finished match, appended to user://telemetry.jsonl.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const Match := preload("res://engine/match.gd")


static func summarize_events(events: Array) -> Dictionary:
	var vacated := {} ## hex -> player
	var walked := 0
	var emptied := 0
	var invasions := 0
	var even := 0
	var even_cap := 0
	## v1.7: an even fight is only a reading on the combat rule if it was fought as it
	## started. Reserves thrown in mid-battle make the attacker bigger than attackerSize
	## says, and a fall-back is scored as a loss the dice never dealt — together they were
	## masking the very bug Amendment 18 fixed.
	var even_clean := 0
	var even_clean_cap := 0
	var r32 := 0
	var r32_cap := 0
	var leader := ""
	var scores := {}
	var winner := ""
	var early := false
	var round_n := 0
	var reserves := 0
	var fallbacks := 0
	var melees := 0
	var scrambles := 0
	var capitals := 0 ## v1.8: capitals that fell
	var fortune_spent := 0 ## v1.8: exchanges thrown again
	var fortune_saved := 0 ## ...and battles that came out the other way for it
	var fortune_gained := 0
	var upsets := 0 ## v1.8: assaults that went the way the odds said they would not (under 30%)
	for event in events:
		var kind: String = str(event.get("kind", ""))
		match kind:
			Types.EVENT_VACATED:
				vacated[str(event.get("from", ""))] = str(event.get("playerId", ""))
			Types.EVENT_CAPITAL_TAKEN:
				capitals += 1
			Types.EVENT_FORTUNE:
				fortune_gained += int(event.get("gained", 1))
			Types.EVENT_BECAME_UNOCCUPIED:
				var hex: String = str(event.get("terrId", ""))
				if vacated.has(hex):
					emptied += 1
			Types.EVENT_OCCUPIED:
				var hex2: String = str(event.get("terrId", ""))
				var who: String = str(event.get("playerId", ""))
				if vacated.has(hex2) and str(vacated[hex2]) != who:
					walked += 1
			Types.EVENT_INVASION:
				invasions += 1
				if not bool(event.get("fellBack", false)):
					var pu: float = Combat.capture_rate(int(event.get("attackerSize", 1)), int(event.get("defenderSize", 1)), Combat.MODE_VOLLEYS)
					var wu: bool = bool(event.get("attackerWon", false))
					if (wu and pu < 0.3) or (not wu and pu > 0.7):
						upsets += 1
				for c in event.get("calls", []):
					if str(c.get("call", "")) == "F":
						fortune_spent += 1
						## the side that called it won the battle in the end
						if (str(c.get("side", "")) == "a") == bool(event.get("attackerWon", false)):
							fortune_saved += 1
				if int(event.get("reservesAdded", 0)) > 0:
					reserves += 1
				if bool(event.get("fellBack", false)):
					fallbacks += 1
				var a: int = int(event.get("attackerSize", 0))
				var d: int = int(event.get("defenderSize", 0))
				var won := bool(event.get("attackerWon", false))
				if a == d and a > 0:
					even += 1
					if won:
						even_cap += 1
					if int(event.get("reservesAdded", 0)) == 0 and not bool(event.get("fellBack", false)):
						even_clean += 1
						if won:
							even_clean_cap += 1
				if d > 0 and a * 2 == d * 3:
					r32 += 1
					if won:
						r32_cap += 1
			Types.EVENT_SCRAMBLE:
				scrambles += 1
			Types.EVENT_MELEE:
				melees += 1
				for f in event.get("fronts", []):
					invasions += 1
					if int(f.get("reservesAdded", 0)) > 0:
						reserves += 1
					if bool(f.get("fellBack", false)):
						fallbacks += 1
			Types.EVENT_SCORE:
				leader = str(event.get("leader", ""))
				var sc: Variant = event.get("scores", {})
				if typeof(sc) == TYPE_DICTIONARY:
					scores = sc
			Types.EVENT_ROUND_ENDED:
				winner = str(event.get("winner", ""))
				early = bool(event.get("early", false))
				round_n = int(event.get("round", 0))
	return {
		"round": round_n,
		"vacatePunish": walked,
		"emptiedOrigins": emptied,
		"invasions": invasions,
		"even": even,
		"evenCaptures": even_cap,
		"capitalsTaken": capitals,
		"fortuneSpent": fortune_spent,
		"upsets": upsets,
		"fortuneSaved": fortune_saved,
		"fortuneGained": fortune_gained,
		"evenClean": even_clean,
		"evenCleanCaptures": even_clean_cap,
		"ratio32": r32,
		"ratio32Captures": r32_cap,
		"reserves": reserves,
		"fallbacks": fallbacks,
		"melees": melees,
		"scrambles": scrambles,
		"leader": leader,
		"scores": scores,
		"winner": winner,
		"early": early,
	}


static func from_play(play: Dictionary) -> Dictionary:
	var rounds: Array = play.get("rounds", [])
	var walked := 0
	var invasions := 0
	var even := 0
	var even_cap := 0
	var r32 := 0
	var r32_cap := 0
	var leaders: Array = []
	for raw in rounds:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		walked += int(raw.get("vacatePunish", 0))
		invasions += int(raw.get("invasions", 0))
		even += int(raw.get("even", 0))
		even_cap += int(raw.get("evenCaptures", 0))
		r32 += int(raw.get("ratio32", 0))
		r32_cap += int(raw.get("ratio32Captures", 0))
		var lead: String = str(raw.get("leader", ""))
		if lead != "":
			leaders.append(lead)
	var lead_changes := 0
	for i in range(1, leaders.size()):
		if i >= 2 and str(leaders[i]) != str(leaders[i - 1]):
			lead_changes += 1
	return {
		"kind": "match",
		"mapId": str(play.get("mapId", "knife7")),
		"matchSeed": int(play.get("matchSeed", 0)),
		"vsMonkey": bool(play.get("vsMonkey", false)),
		"teach": bool(play.get("teach", false)),
		"roundsPlayed": rounds.size(),
		"winner": str(play.get("winner", "")),
		"early": bool(play.get("early", false)),
		"vacatePunish": walked,
		"invasions": {
			"n": invasions,
			"even": even,
			"evenCaptures": even_cap,
			"ratio32": r32,
			"ratio32Captures": r32_cap,
		},
		"leadChangesAfter3": lead_changes,
		"hashes": play.get("hashes", []),
	}


static func append(path: String, rec: Dictionary) -> String:
	var abs_path := Match._abs(path)
	var f := FileAccess.open(abs_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s (err %s)" % [abs_path, FileAccess.get_open_error()]
	f.seek_end()
	f.store_line(JSON.stringify(rec))
	return ""
