## Size + 1d6. One roll. Ties -> attacker on invasion. Clash/spoils reroll ties.
## Winner loses floor(loser / 2), always keeps >= 1. No volleys. No mid-fight 2x.
## No Node. No UI. No unseeded RNG — caller passes a derived stream.
extends RefCounted

const TIE_ATTACKER := "attacker"
const TIE_REROLL := "reroll"

const ODDS_LONG_SHOT := "long shot"
const ODDS_TOSS_UP := "toss-up"
const ODDS_LIKELY := "likely"
const ODDS_LOCK := "lock"


class FightResult extends RefCounted:
	var attacker_won: bool = false
	var winner_remaining: int = 0
	var attacker_size: int = 0
	var defender_size: int = 0
	var attacker_die: int = 0
	var defender_die: int = 0
	var attacker_total: int = 0
	var defender_total: int = 0
	var rerolls: int = 0
	var rolls: Array = [] ## [{a, b}, ...] last pair is the deciding roll

	func to_dict() -> Dictionary:
		return {
			"attackerWon": attacker_won,
			"winnerRemaining": winner_remaining,
			"attackerSize": attacker_size,
			"defenderSize": defender_size,
			"attackerDie": attacker_die,
			"defenderDie": defender_die,
			"attackerTotal": attacker_total,
			"defenderTotal": defender_total,
			"rerolls": rerolls,
			"rolls": rolls,
		}


static func winner_loss(loser_size: int) -> int:
	if loser_size < 0:
		return 0
	return loser_size / 2


static func remaining_after_win(winner_size: int, loser_size: int) -> int:
	return maxi(1, winner_size - winner_loss(loser_size))


static func invasion(att_armies: int, def_armies: int, rng: RefCounted) -> FightResult:
	return _resolve(att_armies, def_armies, rng, false)


static func clash(left_armies: int, right_armies: int, rng: RefCounted) -> FightResult:
	return _resolve(left_armies, right_armies, rng, true)


static func spoils(left_armies: int, right_armies: int, rng: RefCounted) -> FightResult:
	return clash(left_armies, right_armies, rng)


static func invasion_wins_out_of_36(att_armies: int, def_armies: int) -> int:
	var wins := 0
	for da in range(1, 7):
		for db in range(1, 7):
			if att_armies + da >= def_armies + db:
				wins += 1
	return wins


static func invasion_capture_rate(att_armies: int, def_armies: int) -> float:
	return float(invasion_wins_out_of_36(att_armies, def_armies)) / 36.0


static func odds_word(att_armies: int, def_armies: int) -> String:
	var p := invasion_capture_rate(att_armies, def_armies)
	if p >= 0.95:
		return ODDS_LOCK
	if p >= 0.75:
		return ODDS_LIKELY
	if p >= 0.40:
		return ODDS_TOSS_UP
	return ODDS_LONG_SHOT


static func _resolve(att_armies: int, def_armies: int, rng: RefCounted, reroll_ties: bool) -> FightResult:
	var result := FightResult.new()
	result.attacker_size = att_armies
	result.defender_size = def_armies
	if att_armies < 1 or def_armies < 1:
		push_error("combat requires both sides >= 1 (got %s vs %s)" % [att_armies, def_armies])
		return result

	while true:
		var da: int = rng.roll_d6()
		var db: int = rng.roll_d6()
		result.rolls.append({"a": da, "b": db})
		result.attacker_die = da
		result.defender_die = db
		result.attacker_total = att_armies + da
		result.defender_total = def_armies + db
		if result.attacker_total == result.defender_total and reroll_ties:
			result.rerolls += 1
			if result.rerolls > 64:
				push_error("clash/spoils tie reroll cap hit")
				break
			continue
		break

	if reroll_ties:
		result.attacker_won = result.attacker_total > result.defender_total
	else:
		result.attacker_won = result.attacker_total >= result.defender_total

	var winner_size := att_armies if result.attacker_won else def_armies
	var loser_size := def_armies if result.attacker_won else att_armies
	result.winner_remaining = remaining_after_win(winner_size, loser_size)
	return result
