## Event factories. Cinema renders this list. Nothing else.
## No Node. No UI. No RNG.
extends RefCounted

const Types := preload("res://engine/types.gd")


static func regroup_applied(player_id: String, from_id: String, to_id: String, strength: int, from_left: int, to_armies: int) -> Dictionary:
	return {
		"kind": Types.EVENT_REGROUP_APPLIED,
		"playerId": player_id,
		"from": from_id,
		"to": to_id,
		"strength": strength,
		"fromRemaining": from_left,
		"toArmies": to_armies,
	}


static func placed(player_id: String, terr_id: String, added: int, armies: int, overflow: int) -> Dictionary:
	return {
		"kind": Types.EVENT_PLACED,
		"playerId": player_id,
		"terrId": terr_id,
		"added": added,
		"armies": armies,
		"overflow": overflow,
	}


static func vacated(player_id: String, from_id: String, to_id: String, strength: int, origin_remaining: int) -> Dictionary:
	return {
		"kind": Types.EVENT_VACATED,
		"playerId": player_id,
		"from": from_id,
		"to": to_id,
		"strength": strength,
		"originRemaining": origin_remaining,
	}


static func clash_event(hex_a: String, hex_b: String, player_a: String, player_b: String, fight: RefCounted) -> Dictionary:
	return {
		"kind": Types.EVENT_CLASH,
		"hexA": hex_a,
		"hexB": hex_b,
		"playerA": player_a,
		"playerB": player_b,
		"sizeA": fight.attacker_size,
		"sizeB": fight.defender_size,
		"dieA": fight.attacker_die,
		"dieB": fight.defender_die,
		"totalA": fight.attacker_total,
		"totalB": fight.defender_total,
		"rerolls": fight.rerolls,
		"winnerId": player_a if fight.attacker_won else player_b,
		"winnerRemaining": fight.winner_remaining,
		"rolls": fight.rolls,
	}


static func invasion_event(from_id: String, to_id: String, attacker_id: String, defender_id: String, fight: RefCounted) -> Dictionary:
	return {
		"kind": Types.EVENT_INVASION,
		"from": from_id,
		"to": to_id,
		"attackerId": attacker_id,
		"defenderId": defender_id,
		"attackerSize": fight.attacker_size,
		"defenderSize": fight.defender_size,
		"attackerDie": fight.attacker_die,
		"defenderDie": fight.defender_die,
		"attackerTotal": fight.attacker_total,
		"defenderTotal": fight.defender_total,
		"attackerWon": fight.attacker_won,
		"winnerRemaining": fight.winner_remaining,
		"rolls": fight.rolls,
	}


static func spoils_event(to_id: String, player_a: String, player_b: String, fight: RefCounted) -> Dictionary:
	return {
		"kind": Types.EVENT_SPOILS,
		"to": to_id,
		"playerA": player_a,
		"playerB": player_b,
		"sizeA": fight.attacker_size,
		"sizeB": fight.defender_size,
		"dieA": fight.attacker_die,
		"dieB": fight.defender_die,
		"totalA": fight.attacker_total,
		"totalB": fight.defender_total,
		"rerolls": fight.rerolls,
		"winnerId": player_a if fight.attacker_won else player_b,
		"winnerRemaining": fight.winner_remaining,
		"rolls": fight.rolls,
	}


static func surge_event(player_id: String, from_id: String, to_id: String, strength: int, origin_remaining: int) -> Dictionary:
	return {
		"kind": Types.EVENT_SURGE,
		"playerId": player_id,
		"from": from_id,
		"to": to_id,
		"strength": strength,
		"originRemaining": origin_remaining,
	}


static func occupied(player_id: String, terr_id: String, armies: int) -> Dictionary:
	return {
		"kind": Types.EVENT_OCCUPIED,
		"playerId": player_id,
		"terrId": terr_id,
		"armies": armies,
	}


static func became_unoccupied(terr_id: String, previous_owner: String) -> Dictionary:
	return {
		"kind": Types.EVENT_BECAME_UNOCCUPIED,
		"terrId": terr_id,
		"previousOwner": previous_owner,
	}


static func player_eliminated(player_id: String) -> Dictionary:
	return {"kind": Types.EVENT_PLAYER_ELIMINATED, "playerId": player_id}


static func score(scores: Dictionary, leader: String) -> Dictionary:
	return {"kind": Types.EVENT_SCORE, "scores": scores, "leader": leader}


static func entrenched(terr_id: String, garrison: int, cap: int) -> Dictionary:
	return {
		"kind": Types.EVENT_ENTRENCHED,
		"terrId": terr_id,
		"garrison": garrison,
		"cap": cap,
	}


static func round_ended(round: int, winner: String, early: bool) -> Dictionary:
	return {
		"kind": Types.EVENT_ROUND_ENDED,
		"round": round,
		"winner": winner,
		"early": early,
	}


static func canonical_list(events: Array) -> String:
	var Hash := load("res://engine/hash.gd")
	return Hash.canonical(events)
