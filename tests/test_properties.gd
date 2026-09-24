## P1–P4 + 1000 monkey games. G3 gate.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Bot := preload("res://engine/bot.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Income := preload("res://engine/income.gd")

const MONKEY_GAMES := 1000


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	_p4_illegal(report, map)
	_p4_legal_resolves(report, map)
	_determinism(report, map)
	_monkey(report, map)


func _p4_illegal(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 3],
		"beacon": ["red", 1],
		"mill": ["green", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var leftover: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 2), H.pkt("ridge", "gate", 2)])
	report.call(Validate.validate_sheet(world, map, leftover).size() > 0, "P4 leftover is rejected")

	var friendly: Types.Sheet = H.sheet("red", [H.pkt("ridge", "beacon", 1)])
	report.call(Validate.validate_sheet(world, map, friendly).size() > 0, "P4 attack-friendly is rejected")

	var far: Types.Sheet = H.sheet("red", [H.pkt("ridge", "quarry", 1)])
	report.call(Validate.validate_sheet(world, map, far).size() > 0, "P4 non-adjacent is rejected")

	var r := Types.Regroup.new()
	r.from_id = "ridge"
	r.to_id = "beacon"
	r.strength = 1
	var rg: Types.Sheet = H.sheet("red", [], {}, r)
	world.round = 1
	report.call(Validate.validate_sheet(world, map, rg).size() > 0, "P4 round-1 regroup is rejected")

	var cash: Types.Sheet = H.sheet("red", [])
	cash.cash_set = PackedStringArray([Types.CARD_SUN])
	report.call(Validate.validate_sheet(world, map, cash).size() > 0, "P4 cards on knife7 rejected")

	var zero: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 0)])
	report.call(Validate.validate_sheet(world, map, zero).size() > 0, "P4 strength 0 rejected")


func _p4_legal_resolves(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = Setup.deal_knife7_two_player(map, 7, true)
	var ok := 0
	var n := 40
	for i in n:
		var rng: RefCounted = Rng.derive_stream(7, 1, "p4|%s" % i)
		var sheet: Types.Sheet = Bot.legal_sheet(world, map, "red", rng)
		var verr: PackedStringArray = Validate.validate_sheet(world, map, sheet)
		if verr.size() > 0:
			report.call(false, "P4 bot sheet %s failed validate: %s" % [i, " ".join(verr)])
			return
		var result: Dictionary = Resolve.resolve_round(world, map, [sheet], 7 + i)
		if result["errors"].is_empty():
			ok += 1
		else:
			report.call(false, "P4 validate passed but resolve choked: %s" % " ".join(result["errors"]))
			return
	report.call(ok == n, "P4 validate accepts what resolve will run (%s/%s)" % [ok, n])


func _determinism(report: Callable, map: Types.MapDef) -> void:
	var matched := 0
	for seed in [1, 2, 9, 42, 99]:
		var a: Dictionary = Bot.play_match(map, seed, false)
		var b: Dictionary = Bot.play_match(map, seed, false)
		if a["final_hash"] == b["final_hash"] and a["hashes"] == b["hashes"] and a["ok"] and b["ok"]:
			matched += 1
		else:
			report.call(false, "T6/monkey determinism seed %s a=%s b=%s va=%s" % [seed, a["final_hash"], b["final_hash"], " ".join(a["violations"])])
			return
	report.call(matched == 5, "same matchSeed replays to the same world hashes")


func _monkey(report: Callable, map: Types.MapDef) -> void:
	var t0: int = Time.get_ticks_msec()
	var ok := 0
	var rounds := 0
	var leaks := 0
	for i in MONKEY_GAMES:
		var three: bool = i % 5 == 0
		var result: Dictionary = Bot.play_match(map, 1000 + i, three)
		rounds += int(result["rounds"])
		if result["ok"]:
			ok += 1
		else:
			leaks += 1
			report.call(false, "monkey game %s failed: %s" % [i, " ".join(result["violations"])])
			return
	var ms: int = Time.get_ticks_msec() - t0
	report.call(ok == MONKEY_GAMES, "monkey %s/%s games clean" % [ok, MONKEY_GAMES])
	report.call(ms < 30000, "monkey %s games in %sms (<30s)" % [MONKEY_GAMES, ms])
	print("  monkey  games=%s  rounds=%s  ms=%s  avg_rounds=%.2f" % [MONKEY_GAMES, rounds, ms, float(rounds) / float(MONKEY_GAMES)])
