## Seeded RNG only. Callers must go through derive_stream.
## No Node. No UI. Never randomize(). Never randi()/randf() from global Random.
class_name GameRng
extends RefCounted

const _Hash := preload("res://engine/hash.gd")

var _rng: RandomNumberGenerator


func _init(p_seed: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = p_seed


func roll_d6() -> int:
	return _rng.randi_range(1, 6)


func rand_index(n: int) -> int:
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)


func roll_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return _rng.randi_range(lo, hi)


func chance(numer: int, denom: int) -> bool:
	if denom <= 0:
		return false
	return rand_index(denom) < numer


static func derive_stream(match_seed: int, round: int, battle_key: String) -> RefCounted:
	var script: GDScript = preload("res://engine/rng.gd")
	return script.new(_Hash.mix_battle(match_seed, round, battle_key))
