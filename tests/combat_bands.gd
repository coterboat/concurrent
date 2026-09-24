## Shared G1 band table. Invasion, ties -> attacker. 8k+ fights.
## No Node. No UI.
extends RefCounted

const CombatScript := preload("res://engine/combat.gd")
const RngScript := preload("res://engine/rng.gd")

const N := 8000
const SEED := 1


class ScriptedRng extends RefCounted:
	var seq: PackedInt32Array = PackedInt32Array()
	var i: int = 0

	func roll_d6() -> int:
		if i >= seq.size():
			push_error("ScriptedRng underrun")
			return 1
		var v: int = seq[i]
		i += 1
		return v


static func band_rows() -> Array:
	## [label, att, def, lo_pct, hi_pct, note]
	return [
		["1v1", 1, 1, 55.0, 60.0, "winner keeps 1"],
		["3v1", 3, 1, 80.0, 86.0, "remnant taxes"],
		["4v4", 4, 4, 55.0, 60.0, "even any size"],
		["8v8", 8, 8, 55.0, 60.0, "even any size"],
		["20v20", 20, 20, 55.0, 60.0, "even any size"],
		["6v4", 6, 4, 78.0, 86.0, "3:2 ~80"],
		["8v5", 8, 5, 85.0, 95.0, "high 80s / low 90s"],
		["5v8", 5, 8, 12.0, 22.0, "<=25, stack holds"],
		["10v5", 10, 5, 95.0, 100.0, "2:1 ~95+"],
	]


static func simulate_invasion(att: int, def: int, n: int = N, match_seed: int = SEED) -> Dictionary:
	var captures := 0
	var double_wipes := 0
	var remnant_sum := 0
	for i in n:
		var key := "invasion|%s|%s|%s" % [att, def, i]
		var rng: RefCounted = RngScript.derive_stream(match_seed, 0, key)
		var fight: CombatScript.FightResult = CombatScript.invasion(att, def, rng)
		if fight.attacker_won:
			captures += 1
		if fight.winner_remaining < 1:
			double_wipes += 1
		remnant_sum += fight.winner_remaining
	return {
		"n": n,
		"captures": captures,
		"capture_pct": 100.0 * float(captures) / float(n),
		"exact_pct": 100.0 * CombatScript.invasion_capture_rate(att, def),
		"double_wipes": double_wipes,
		"mean_remaining": float(remnant_sum) / float(n),
	}


static func in_band(pct: float, lo: float, hi: float) -> bool:
	return pct >= lo and pct <= hi
