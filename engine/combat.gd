## Two battle styles, one set of bands.
##   decisive (bible v0.2): size + 1d6, one roll. Winner loses floor(loser / 2), keeps >= 1.
##   volleys (v1.1): roll by roll. Each volley both sides score die x 5 + armies; the
##     lower score loses one army; fight until one side is gone. The same capture bands
##     and the same survivors within a fraction of an army (tools/battle_sim) — but every
##     roll kills someone, so the battle can be watched and rolled by hand.
##   battle calls (v1.2, volleys only): an invasion runs in exchanges of three volleys.
##     After each, the attacker calls: press on, throw in the reserves still at home
##     (once), or fall back to a friendly land. Unwatched battles follow the sealed
##     stance on the order (doctrine below); watched ones are called live and recorded.
## Ties -> attacker on invasion. Clash/spoils reroll ties. No Node. No UI. Seeded RNG only.
extends RefCounted

const MODE_DECISIVE := "decisive"
const MODE_VOLLEYS := "volleys"
const VOLLEY_DIE := 5 ## one pip is worth five armies in a volley

const EXCHANGE := 3 ## volleys between battle calls
const CALL_PRESS := "p"
const CALL_RESERVES := "r"
const CALL_FALL_BACK := "f"
const STANCE_HOLD := "hold" ## to the last man (v1.1 behaviour)
const STANCE_CAREFUL := "careful" ## fall back when it turns
const STANCE_BOLD := "bold" ## throw in the reserves, never fall back
const STANCE_JUDGMENT := "judgment" ## reserves when they swing it, fall back when hopeless
const STANCES := [STANCE_JUDGMENT, STANCE_HOLD, STANCE_BOLD, STANCE_CAREFUL]

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
	var calls: Array = [] ## [{at, call, n?, to?}] battle calls, at = rolls made before the call
	var reserves: Array = [] ## [{from, n, left}] reserves pulled from home
	var reserves_added: int = 0
	var fell_back: bool = false
	var refuge: String = ""
	var refuge_armies: int = 0 ## armies at the refuge after the survivors arrive
	var attacker_left: int = 0 ## attacker survivors (captors, or those who fell back)
	var pending: bool = false ## stopped at a live call

	func extras(d: Dictionary) -> Dictionary:
		if not calls.is_empty():
			d["calls"] = calls
		if not reserves.is_empty():
			d["reserves"] = reserves
			d["reservesAdded"] = reserves_added
		if fell_back:
			d["fellBack"] = true
			d["refuge"] = refuge
			d["refugeArmies"] = refuge_armies
			d["attackerLeft"] = attacker_left
		if pending:
			d["pending"] = true
			d["attackerLeft"] = attacker_left
		return d

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


static func invasion(att_armies: int, def_armies: int, rng: RefCounted, mode: String = MODE_DECISIVE) -> FightResult:
	if mode == MODE_VOLLEYS:
		return _volleys(att_armies, def_armies, rng, false)
	return _resolve(att_armies, def_armies, rng, false)


static func clash(left_armies: int, right_armies: int, rng: RefCounted, mode: String = MODE_DECISIVE) -> FightResult:
	if mode == MODE_VOLLEYS:
		return _volleys(left_armies, right_armies, rng, true)
	return _resolve(left_armies, right_armies, rng, true)


static func spoils(left_armies: int, right_armies: int, rng: RefCounted, mode: String = MODE_DECISIVE) -> FightResult:
	return clash(left_armies, right_armies, rng, mode)


static func scramble(sizes: Array, rng: RefCounted) -> Dictionary:
	## v1.4 spoils: every army fights every other at once. Each salvo, every pair still
	## standing duels once: score = 5 x die + this army's weight against that foe, where an
	## army splits its men across its foes in proportion to their size
	## (weight = mine x theirs / all my foes). The loser of a duel loses one man; a tie
	## costs nobody. Duels run in a fixed order and a man who is down fights no more that
	## salvo, so someone is always left standing. With two armies it is a volley fight.
	## Returns {salvos: [[{i, j, a, b, si, sj, w}]], left: [n], winner: index}.
	var left: Array = []
	for n in sizes:
		left.append(maxi(0, int(n)))
	var salvos: Array = []
	var guard := 0
	while _standing(left) > 1 and guard < 4000:
		guard += 1
		var snap: Array = left.duplicate()
		var tot := 0
		for v in snap:
			tot += int(v)
		var salvo: Array = []
		for i in left.size():
			for j in range(i + 1, left.size()):
				if int(left[i]) <= 0 or int(left[j]) <= 0:
					continue
				var wi: float = float(snap[i]) * float(snap[j]) / float(maxi(1, tot - int(snap[i])))
				var wj: float = float(snap[j]) * float(snap[i]) / float(maxi(1, tot - int(snap[j])))
				var di: int = rng.roll_d6()
				var dj: int = rng.roll_d6()
				var si: float = float(VOLLEY_DIE * di) + wi
				var sj: float = float(VOLLEY_DIE * dj) + wj
				var w := ""
				if si > sj:
					w = "a"
					left[j] = int(left[j]) - 1
				elif sj > si:
					w = "b"
					left[i] = int(left[i]) - 1
				salvo.append({"i": i, "j": j, "a": di, "b": dj, "si": snappedf(wi, 0.1), "sj": snappedf(wj, 0.1), "w": w})
		salvos.append(salvo)
	var winner := 0
	for k in left.size():
		if int(left[k]) > int(left[winner]):
			winner = k
	if _standing(left) > 1:
		## the guard (never seen): the biggest army carries the field, the rest are routed
		for k in left.size():
			if k != winner:
				left[k] = 0
	return {"salvos": salvos, "left": left, "winner": winner}


static func _standing(left: Array) -> int:
	var n := 0
	for v in left:
		if int(v) > 0:
			n += 1
	return n


static func volley_once(a: int, d: int, rng: RefCounted, reroll_ties: bool) -> Dictionary:
	## One volley, rolled exactly as _volleys rolls it (attacker die first).
	var da: int = rng.roll_d6()
	var db: int = rng.roll_d6()
	var sa: int = VOLLEY_DIE * da + a
	var sb: int = VOLLEY_DIE * db + d
	if sa == sb and reroll_ties:
		return {"a": da, "b": db, "sa": a, "sd": d, "w": ""}
	return {"a": da, "b": db, "sa": a, "sd": d, "w": "a" if sa >= sb else "b"}


static func doctrine(stance: String, a: int, d: int, reserves: int, can_fall_back: bool) -> String:
	## What an officer does at a battle call with no commander watching.
	## Pure: the same stance and numbers always give the same call.
	if stance == STANCE_HOLD or stance == "" or (reserves <= 0 and not can_fall_back):
		return CALL_PRESS
	var p: float = volley_capture_rate(a, d, true)
	match stance:
		STANCE_CAREFUL:
			if can_fall_back and p < 0.3:
				return CALL_FALL_BACK
		STANCE_BOLD:
			if reserves > 0 and p < 0.8:
				return CALL_RESERVES
		STANCE_JUDGMENT:
			if reserves > 0 and p < 0.65 and volley_capture_rate(a + reserves, d, true) >= p + 0.15:
				return CALL_RESERVES
			if can_fall_back and p < 0.2:
				return CALL_FALL_BACK
	return CALL_PRESS


static func stance_name(stance: String) -> String:
	match stance:
		STANCE_HOLD:
			return "To the last man"
		STANCE_BOLD:
			return "All in"
		STANCE_CAREFUL:
			return "Fall back if it turns"
	return "Officer's judgment"


static func stance_help(stance: String) -> String:
	match stance:
		STANCE_HOLD:
			return "Never falls back, never calls the reserves."
		STANCE_BOLD:
			return "Throws in the reserves from home as soon as it's not a sure thing. Never falls back."
		STANCE_CAREFUL:
			return "Falls back to save the men once the odds drop under 30%."
	return "Calls the reserves when they'd swing it; falls back when it's hopeless."


static func _volleys(att: int, def: int, rng: RefCounted, reroll_ties: bool) -> FightResult:
	## rolls: [{a, b, sa, sd, w}] — dice, sizes before the volley, and who won it ("a"/"b").
	var result := FightResult.new()
	result.attacker_size = att
	result.defender_size = def
	if att < 1 or def < 1:
		push_error("combat requires both sides >= 1 (got %s vs %s)" % [att, def])
		return result
	var a := att
	var d := def
	var guard := 0
	while a > 0 and d > 0 and guard < 4000:
		guard += 1
		var da: int = rng.roll_d6()
		var db: int = rng.roll_d6()
		var sa: int = VOLLEY_DIE * da + a
		var sb: int = VOLLEY_DIE * db + d
		if sa == sb and reroll_ties:
			result.rerolls += 1
			result.rolls.append({"a": da, "b": db, "sa": a, "sd": d, "w": ""})
			continue
		var a_wins: bool = sa >= sb
		result.rolls.append({"a": da, "b": db, "sa": a, "sd": d, "w": "a" if a_wins else "b"})
		result.attacker_die = da
		result.defender_die = db
		result.attacker_total = sa
		result.defender_total = sb
		if a_wins:
			d -= 1
		else:
			a -= 1
	result.attacker_won = a > 0
	result.winner_remaining = a if a > 0 else d
	return result


## ---- exact odds for either style

static var _volley_memo := {}


static func volley_step(a: int, d: int, attacker_ties: bool) -> float:
	## P(attacker wins one volley): P(5X + a >= 5Y + d) with ties per the rule.
	var wins := 0
	var ties := 0
	for x in range(1, 7):
		for y in range(1, 7):
			var sa: int = VOLLEY_DIE * x + a
			var sb: int = VOLLEY_DIE * y + d
			if sa > sb:
				wins += 1
			elif sa == sb:
				ties += 1
	if attacker_ties:
		return float(wins + ties) / 36.0
	return float(wins) / float(36 - ties)


static func volley_capture_rate(att: int, def: int, attacker_ties: bool = true) -> float:
	if def <= 0:
		return 1.0
	if att <= 0:
		return 0.0
	var t: int = 1 if attacker_ties else 0
	var key: int = _vkey(att, def, t)
	if _volley_memo.has(key):
		return _volley_memo[key]
	## iterative DP over the grid so deep stacks cannot blow the call stack;
	## every cell is kept, so battle calls asking about (a, d) mid-fight are free
	for s in range(1, att + def + 1):
		for aa in range(maxi(0, s - def), mini(att, s) + 1):
			var dd: int = s - aa
			if dd < 0 or dd > def:
				continue
			var ck: int = _vkey(aa, dd, t)
			if _volley_memo.has(ck):
				continue
			var v: float
			if dd == 0:
				v = 1.0 if aa > 0 else 0.0
			elif aa == 0:
				v = 0.0
			else:
				var p: float = volley_step(aa, dd, attacker_ties)
				v = p * float(_volley_memo.get(_vkey(aa, dd - 1, t), 1.0)) + (1.0 - p) * float(_volley_memo.get(_vkey(aa - 1, dd, t), 0.0))
			_volley_memo[ck] = v
	return float(_volley_memo.get(key, 0.0))


static func _vkey(a: int, d: int, t: int) -> int:
	return (a * 100000 + d) * 2 + t


static func capture_rate(att: int, def: int, mode: String = MODE_DECISIVE) -> float:
	if def <= 0:
		return 1.0
	if att <= 0:
		return 0.0
	if mode == MODE_VOLLEYS:
		return volley_capture_rate(att, def, true)
	return invasion_capture_rate(att, def)


static func invasion_wins_out_of_36(att_armies: int, def_armies: int) -> int:
	var wins := 0
	for da in range(1, 7):
		for db in range(1, 7):
			if att_armies + da >= def_armies + db:
				wins += 1
	return wins


static func invasion_capture_rate(att_armies: int, def_armies: int) -> float:
	return float(invasion_wins_out_of_36(att_armies, def_armies)) / 36.0


static func odds_word(att_armies: int, def_armies: int, mode: String = MODE_DECISIVE) -> String:
	var p := capture_rate(att_armies, def_armies, mode)
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
