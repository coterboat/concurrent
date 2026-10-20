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

## v1.6 the firing line (Amendment 17): at most LINE men of a side fire in any volley, so a
## bigger army wins by staying power, not by winning every volley; and an even volley is
## fired again instead of going to the attacker. Set per game from the map (use_rules): the
## resolve queue, the AI and the table all read the same rule. Before v1.6: every man
## counted and ties went to the attacker.
const LINE := 5
static var line := 0 ## 0 = every man fires (games from before v1.6)
static var fair_ties := false
static var line_size := LINE ## tuning only (the arena's line=): the size of the line use_rules sets


static func use_rules(map) -> void:
	var on: bool = map != null and bool(map.fire_line)
	line = line_size if on else 0
	fair_ties = on


static func fire(n: int, bonus: int = 0) -> int:
	## The men of an army of n who fire in a volley. `bonus` is v1.7's fortress bonus:
	## a fort's defenders fire a longer line. With no firing line (games before v1.6)
	## every man fires already, so a fort adds nothing.
	return mini(n, line + maxi(0, bonus)) if line > 0 else n
const CALL_PRESS := "p"
const CALL_RESERVES := "r"
const CALL_FALL_BACK := "f"
const CALL_FORTUNE := "F" ## v1.8: throw that exchange again (engine/fortune.gd)
const CALL_STAND := "n" ## v1.8: let it stand (Fortune declined)
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
	var luck: float = 0.0 ## v1.9: the dice's swing in the attacker's chances, exchange by exchange
	var luck_kept: bool = false ## v1.9 (rules 18): the event carries it, for Fortune's ledger
	var rebate: Dictionary = {} ## v2.2 (rules 22): pid -> hundredths of a battle owed for an exchange Fortune threw away from them

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
		if luck_kept:
			d["luck"] = int(round(luck * 100.0))
		if not rebate.is_empty():
			d["rebate"] = rebate
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


static func invasion(att_armies: int, def_armies: int, rng: RefCounted, mode: String = MODE_DECISIVE, d_bonus: int = 0) -> FightResult:
	if mode == MODE_VOLLEYS:
		return _volleys(att_armies, def_armies, rng, fair_ties, d_bonus)
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
				if line > 0: ## v1.6: at most a firing line against each foe
					wi = minf(wi, float(line))
					wj = minf(wj, float(line))
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


static var _scr_memo := {}


static func scramble_odds(sizes: Array, trials: int = 240) -> Array:
	## v1.9: each army's chance to be the last standing in a scramble, simulated from a fixed
	## seed (so the same fight always quotes, and books, the same odds). Memoised.
	var key: String = "%s|%d|%d" % [",".join(PackedStringArray(sizes.map(func(x): return str(int(x))))), trials, line]
	if _scr_memo.has(key):
		return (_scr_memo[key] as Array).duplicate()
	var wins: Array = []
	for i in sizes.size():
		wins.append(0.0)
	var standing := 0
	for v in sizes:
		if int(v) > 0:
			standing += 1
	if standing <= 1:
		for i in sizes.size():
			wins[i] = 1.0 if int(sizes[i]) > 0 else 0.0
		return wins
	var rng: RefCounted = preload("res://engine/rng.gd").new(1_000_003 + sizes.size() * 7919)
	for k in trials:
		var r: Dictionary = scramble(sizes, rng)
		wins[int(r["winner"])] = float(wins[int(r["winner"])]) + 1.0
	for i in wins.size():
		wins[i] = float(wins[i]) / float(trials)
	if _scr_memo.size() > 4000:
		_scr_memo.clear()
	_scr_memo[key] = wins.duplicate()
	return wins


static func _standing(left: Array) -> int:
	var n := 0
	for v in left:
		if int(v) > 0:
			n += 1
	return n


static func volley_once(a: int, d: int, rng: RefCounted, reroll_ties: bool, d_bonus: int = 0) -> Dictionary:
	## One volley, rolled exactly as _volleys rolls it (attacker die first).
	var da: int = rng.roll_d6()
	var db: int = rng.roll_d6()
	var sa: int = VOLLEY_DIE * da + fire(a)
	var sb: int = VOLLEY_DIE * db + fire(d, d_bonus)
	var r := {"a": da, "b": db, "sa": a, "sd": d, "w": ""}
	if line > 0:
		r["fa"] = fire(a)
		r["fd"] = fire(d, d_bonus)
	if sa == sb and (reroll_ties or fair_ties):
		return r
	r["w"] = "a" if sa >= sb else "b"
	return r


static func doctrine(stance: String, a: int, d: int, reserves: int, can_fall_back: bool, d_bonus: int = 0) -> String:
	## What an officer does at a battle call with no commander watching.
	## Pure: the same stance and numbers always give the same call.
	if stance == STANCE_HOLD or stance == "" or (reserves <= 0 and not can_fall_back):
		return CALL_PRESS
	var p: float = volley_capture_rate(a, d, true, d_bonus)
	match stance:
		STANCE_CAREFUL:
			if can_fall_back and p < 0.3:
				return CALL_FALL_BACK
		STANCE_BOLD:
			if reserves > 0 and p < 0.8:
				return CALL_RESERVES
		STANCE_JUDGMENT:
			if reserves > 0 and p < 0.65 and volley_capture_rate(a + reserves, d, true, d_bonus) >= p + 0.15:
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


static func _volleys(att: int, def: int, rng: RefCounted, reroll_ties: bool, d_bonus: int = 0) -> FightResult:
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
		var sa: int = VOLLEY_DIE * da + fire(a)
		var sb: int = VOLLEY_DIE * db + fire(d, d_bonus)
		var roll := {"a": da, "b": db, "sa": a, "sd": d, "w": ""}
		if line > 0:
			roll["fa"] = fire(a)
			roll["fd"] = fire(d, d_bonus)
		if sa == sb and reroll_ties:
			result.rerolls += 1
			result.rolls.append(roll)
			continue
		var a_wins: bool = sa >= sb
		roll["w"] = "a" if a_wins else "b"
		result.rolls.append(roll)
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


static func volley_step(a: int, d: int, attacker_ties: bool, d_bonus: int = 0) -> float:
	## P(attacker wins one volley): P(5X + a >= 5Y + d) with ties per the rule.
	var wins := 0
	var ties := 0
	for x in range(1, 7):
		for y in range(1, 7):
			var sa: int = VOLLEY_DIE * x + fire(a)
			var sb: int = VOLLEY_DIE * y + fire(d, d_bonus)
			if sa > sb:
				wins += 1
			elif sa == sb:
				ties += 1
	if attacker_ties:
		return float(wins + ties) / 36.0
	return float(wins) / float(36 - ties)


static func volley_capture_rate(att: int, def: int, attacker_ties: bool = true, d_bonus: int = 0) -> float:
	if def <= 0:
		return 1.0
	if att <= 0:
		return 0.0
	var t: int = 1 if attacker_ties and not fair_ties else 0
	var key: int = _vkey(att, def, t, d_bonus)
	if _volley_memo.has(key):
		return _volley_memo[key]
	## iterative DP over the grid so deep stacks cannot blow the call stack;
	## every cell is kept, so battle calls asking about (a, d) mid-fight are free
	for s in range(1, att + def + 1):
		for aa in range(maxi(0, s - def), mini(att, s) + 1):
			var dd: int = s - aa
			if dd < 0 or dd > def:
				continue
			var ck: int = _vkey(aa, dd, t, d_bonus)
			if _volley_memo.has(ck):
				continue
			var v: float
			if dd == 0:
				v = 1.0 if aa > 0 else 0.0
			elif aa == 0:
				v = 0.0
			else:
				var p: float = volley_step(aa, dd, t == 1, d_bonus)
				v = p * float(_volley_memo.get(_vkey(aa, dd - 1, t, d_bonus), 1.0)) + (1.0 - p) * float(_volley_memo.get(_vkey(aa - 1, dd, t, d_bonus), 0.0))
			_volley_memo[ck] = v
	return float(_volley_memo.get(key, 0.0))


static func _vkey(a: int, d: int, t: int, d_bonus: int = 0) -> int:
	## line and the fortress bonus get their own digits: before v1.7 this packed line into
	## 16 slots, so an arena run with line >= 16 would have collided with another (a, d).
	return (((a * 100000 + d) * 2 + t) * 64 + mini(line, 63)) * 16 + mini(maxi(0, d_bonus), 15)


static func capture_rate(att: int, def: int, mode: String = MODE_DECISIVE, d_bonus: int = 0) -> float:
	if def <= 0:
		return 1.0
	if att <= 0:
		return 0.0
	if mode == MODE_VOLLEYS:
		return volley_capture_rate(att, def, true, d_bonus)
	return invasion_capture_rate(att, def)


## ---- v2.3: what a storm from several lands is worth (rules 21: one commander's columns from
## different lands are separate fronts, and the defenders' whole firing line answers each). For the
## planners and the odds shown (the AI, the order card, the advisor); no battle is fought by it.
## Each salvo every front fires one volley at the defenders' line: a win costs the defenders a man,
## a loss costs that front one, an even volley costs nobody (resolve.gd's melee under the firing
## line). Exact for up to three fronts (RV-006 F1: folding small fronts into one priced [1,1,1]
## against 2 at 66%, the battles' 59%). A fourth or more fold the two smallest together (a little
## kind to the attacker: the folded front fires a longer line than its parts); a fight too big to
## count (FRONTS_STATES) is priced scaled down. Without the firing line, or in one decisive roll,
## the old sum.

const FRONTS_EXACT := 3 ## fronts priced exactly; more are folded
const FRONTS_STATES := 20000 ## states counted exactly at most (a first pricing ~200 ms); bigger fights are scaled

static var _fronts_memo := {}
static var _odds_memo := {}


static func fronts_capture_rate(sizes: Array, def: int, mode: String = MODE_VOLLEYS, d_bonus: int = 0) -> float:
	var live: Array = []
	var tot := 0
	for x in sizes:
		if int(x) > 0:
			live.append(int(x))
			tot += int(x)
	if def <= 0:
		return 1.0 if tot > 0 else 0.0
	if tot <= 0:
		return 0.0
	if live.size() == 1 or line <= 0 or mode != MODE_VOLLEYS:
		return capture_rate(tot, def, mode, d_bonus)
	live.sort()
	live.reverse()
	while live.size() > 2 and (live.size() > FRONTS_EXACT or _states(live, def) > FRONTS_STATES):
		var a: int = int(live.pop_back())
		live[-1] = int(live[-1]) + a
		live.sort()
		live.reverse()
	var d: int = def
	var n: int = _states(live, d)
	if n > FRONTS_STATES:
		## a huge fight: priced at a scale it can be counted at (the line fires five a side either way,
		## so a volley's odds are the same; only the staying power is rounded)
		var k: float = ceilf(pow(float(n) / float(FRONTS_STATES), 1.0 / float(live.size() + 1)))
		for i in live.size():
			live[i] = maxi(1, int(round(float(live[i]) / k)))
		d = maxi(1, int(round(float(d) / k)))
		live.sort()
		live.reverse()
	return _fronts(live, d, d_bonus)


static func _states(fronts: Array, d: int) -> int:
	var n: int = d + 1
	for f in fronts:
		n *= int(f) + 1
	return n


static func _volley_odds(a: int, d: int, d_bonus: int) -> Array:
	## [win, lose, even] for one front's volley at the defenders' line (by the men who fire)
	var fa: int = fire(a)
	var fd: int = fire(d, d_bonus)
	var key: int = fa * 1024 + fd
	if _odds_memo.has(key):
		return _odds_memo[key]
	var wins := 0
	var ties := 0
	for x in range(1, 7):
		for y in range(1, 7):
			var sa: int = VOLLEY_DIE * x + fa
			var sb: int = VOLLEY_DIE * y + fd
			if sa > sb:
				wins += 1
			elif sa == sb:
				ties += 1
	var o: Array = [float(wins) / 36.0, float(36 - wins - ties) / 36.0, float(ties) / 36.0]
	_odds_memo[key] = o
	return o


static func _fronts(fronts: Array, d: int, d_bonus: int) -> float:
	## fronts: sizes > 0, biggest first, at most FRONTS_EXACT of them
	if d <= 0:
		return 1.0
	if fronts.is_empty():
		return 0.0
	if fronts.size() == 1:
		return volley_capture_rate(int(fronts[0]), d, true, d_bonus)
	if fronts.size() == 2:
		return _two_fronts(int(fronts[0]), int(fronts[1]), d, d_bonus)
	var key: int = 0
	for f in fronts:
		key = key * 1024 + mini(int(f), 1023)
	key = (((key * 1024 + mini(d, 1023)) * 16 + mini(maxi(0, d_bonus), 15)) * 8 + fronts.size()) * 64 + mini(line, 63)
	if _fronts_memo.has(key):
		return _fronts_memo[key]
	var odds: Array = []
	var stay := 1.0
	for f in fronts:
		var o: Array = _volley_odds(int(f), d, d_bonus)
		odds.append(o)
		stay *= float(o[2])
	var k: int = fronts.size()
	var v := 0.0
	for c in int(pow(3, k)):
		## each front's volley: 0 won (the defenders lose a man), 1 lost (the front does), 2 even
		var code: int = c
		var pr := 1.0
		var wins := 0
		var moved := false
		var nxt: Array = []
		for i in k:
			var r: int = code % 3
			code /= 3
			pr *= float(odds[i][r])
			if r == 0:
				wins += 1
			if r != 2:
				moved = true
			var s: int = int(fronts[i]) - (1 if r == 1 else 0)
			if s > 0:
				nxt.append(s)
		if not moved or pr <= 0.0:
			continue ## every volley even: the salvo changed nothing (normalised out below)
		nxt.sort()
		nxt.reverse()
		v += pr * _fronts(nxt, maxi(0, d - wins), d_bonus)
	v /= 1.0 - stay
	_fronts_memo[key] = v
	return v


static func _two_fronts(a: int, b: int, d: int, d_bonus: int) -> float:
	## _fronts for two (the common case), without building arrays: a >= b > 0
	if d <= 0:
		return 1.0
	if b <= 0:
		return volley_capture_rate(a, d, true, d_bonus) if a > 0 else 0.0
	var key: int = ((((a * 1024 + b) * 1024 + mini(d, 1023)) * 16 + mini(maxi(0, d_bonus), 15)) * 8 + 2) * 64 + mini(line, 63)
	if _fronts_memo.has(key):
		return _fronts_memo[key]
	var oa: Array = _volley_odds(a, d, d_bonus)
	var ob: Array = _volley_odds(b, d, d_bonus)
	var v := 0.0
	for ra in 3:
		for rb in 3:
			if ra == 2 and rb == 2:
				continue ## both even: the salvo changed nothing (normalised out below)
			var pr: float = float(oa[ra]) * float(ob[rb])
			if pr <= 0.0:
				continue
			var na: int = a - (1 if ra == 1 else 0)
			var nb: int = b - (1 if rb == 1 else 0)
			var nd: int = maxi(0, d - (1 if ra == 0 else 0) - (1 if rb == 0 else 0))
			v += pr * (_two_fronts(na, nb, nd, d_bonus) if na >= nb else _two_fronts(nb, na, nd, d_bonus))
	v /= 1.0 - float(oa[2]) * float(ob[2])
	_fronts_memo[key] = v
	return v


static func invasion_wins_out_of_36(att_armies: int, def_armies: int) -> int:
	var wins := 0
	for da in range(1, 7):
		for db in range(1, 7):
			if att_armies + da >= def_armies + db:
				wins += 1
	return wins


static func invasion_capture_rate(att_armies: int, def_armies: int) -> float:
	return float(invasion_wins_out_of_36(att_armies, def_armies)) / 36.0


static func odds_word(att_armies: int, def_armies: int, mode: String = MODE_DECISIVE, d_bonus: int = 0) -> String:
	return word_for(capture_rate(att_armies, def_armies, mode, d_bonus))


static func word_for(p: float) -> String:
	## v2.3: the word for a chance (odds_word's, for odds priced some other way: fronts_capture_rate)
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
