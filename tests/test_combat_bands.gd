## G1 assertions. Runner calls run(report).
extends RefCounted

const CombatScript := preload("res://engine/combat.gd")
const RngScript := preload("res://engine/rng.gd")
const Bands := preload("res://tests/combat_bands.gd")


func run(report: Callable) -> void:
	_exact(report)
	_formula(report)
	_scripted(report)
	_odds(report)
	_bands(report)
	_no_double_wipe(report)
	_determinism(report)


func _exact(report: Callable) -> void:
	report.call(CombatScript.invasion_wins_out_of_36(1, 1) == 21, "1v1 exact 21/36")
	report.call(CombatScript.invasion_wins_out_of_36(3, 1) == 30, "3v1 exact 30/36")
	report.call(CombatScript.invasion_wins_out_of_36(6, 4) == 30, "6v4 exact 30/36 (same as 3v1)")
	report.call(CombatScript.invasion_wins_out_of_36(8, 5) == 33, "8v5 exact 33/36")
	report.call(CombatScript.invasion_wins_out_of_36(5, 8) == 6, "5v8 exact 6/36")
	report.call(CombatScript.invasion_wins_out_of_36(10, 5) == 36, "10v5 exact 36/36")
	report.call(CombatScript.invasion_wins_out_of_36(4, 4) == 21, "4v4 exact 21/36")
	report.call(CombatScript.invasion_wins_out_of_36(20, 20) == 21, "20v20 exact 21/36")


func _formula(report: Callable) -> void:
	report.call(CombatScript.winner_loss(1) == 0, "winner_loss(1) = 0")
	report.call(CombatScript.winner_loss(4) == 2, "winner_loss(4) = 2")
	report.call(CombatScript.winner_loss(5) == 2, "winner_loss(5) = 2")
	report.call(CombatScript.remaining_after_win(1, 1) == 1, "1v1 winner occupies with 1")
	report.call(CombatScript.remaining_after_win(6, 4) == 4, "6 beats 4, keeps 4")
	report.call(CombatScript.remaining_after_win(2, 10) == 1, "lucky 2 vs 10 still keeps 1")
	report.call(CombatScript.remaining_after_win(8, 5) == 6, "8 beats 5, loses 2")


func _scripted(report: Callable) -> void:
	var inv := Bands.ScriptedRng.new()
	inv.seq = PackedInt32Array([4, 4]) ## 1+4 vs 1+4, tie -> attacker
	var r1: CombatScript.FightResult = CombatScript.invasion(1, 1, inv)
	report.call(r1.attacker_won and r1.winner_remaining == 1, "invasion tie goes to attacker, remnant 1")
	report.call(r1.rerolls == 0, "invasion does not reroll ties")

	var clash_tie := Bands.ScriptedRng.new()
	clash_tie.seq = PackedInt32Array([3, 3, 6, 1])
	var r2: CombatScript.FightResult = CombatScript.clash(5, 5, clash_tie)
	report.call(r2.rerolls == 1, "clash rerolls a tie")
	report.call(r2.attacker_won and r2.winner_remaining == 3, "clash 5v5 after 6-1: left keeps 3")
	report.call(r2.rolls.size() == 2, "clash stores both rolls")

	var def_win := Bands.ScriptedRng.new()
	def_win.seq = PackedInt32Array([1, 6])
	var r3: CombatScript.FightResult = CombatScript.invasion(1, 1, def_win)
	report.call(not r3.attacker_won and r3.winner_remaining == 1, "1v1 defender can hold with 1")


func _odds(report: Callable) -> void:
	report.call(CombatScript.odds_word(1, 1) == CombatScript.ODDS_TOSS_UP, "1v1 toss-up")
	report.call(CombatScript.odds_word(6, 4) == CombatScript.ODDS_LIKELY, "3:2 likely")
	report.call(CombatScript.odds_word(10, 5) == CombatScript.ODDS_LOCK, "2:1 lock")
	report.call(CombatScript.odds_word(5, 8) == CombatScript.ODDS_LONG_SHOT, "5v8 long shot")
	report.call(CombatScript.odds_word(8, 5) == CombatScript.ODDS_LIKELY, "8v5 likely not a percent")


func _bands(report: Callable) -> void:
	for row in Bands.band_rows():
		var label: String = row[0]
		var att: int = row[1]
		var def: int = row[2]
		var lo: float = row[3]
		var hi: float = row[4]
		var sim: Dictionary = Bands.simulate_invasion(att, def)
		var exact: float = sim["exact_pct"]
		var pct: float = sim["capture_pct"]
		report.call(Bands.in_band(exact, lo, hi), "%s exact %.1f in %.0f-%.0f" % [label, exact, lo, hi])
		report.call(Bands.in_band(pct, lo, hi), "%s sim %.1f in %.0f-%.0f (n=%s)" % [label, pct, lo, hi, sim["n"]])
		report.call(int(sim["double_wipes"]) == 0, "%s never double-wipes" % label)


func _no_double_wipe(report: Callable) -> void:
	var wiped := false
	for da in range(1, 7):
		for db in range(1, 7):
			var rng := Bands.ScriptedRng.new()
			rng.seq = PackedInt32Array([da, db])
			var fight: CombatScript.FightResult = CombatScript.invasion(1, 1, rng)
			if fight.winner_remaining != 1:
				wiped = true
	report.call(not wiped, "all 36 1v1 outcomes occupy with 1")


func _determinism(report: Callable) -> void:
	var a: CombatScript.FightResult = CombatScript.invasion(8, 5, RngScript.derive_stream(7, 3, "gate|red|blue"))
	var b: CombatScript.FightResult = CombatScript.invasion(8, 5, RngScript.derive_stream(7, 3, "gate|red|blue"))
	var c: CombatScript.FightResult = CombatScript.invasion(8, 5, RngScript.derive_stream(7, 3, "harbor|red|blue"))
	report.call(
		a.attacker_die == b.attacker_die and a.defender_die == b.defender_die and a.attacker_won == b.attacker_won,
		"same battle_key same dice"
	)
	report.call(
		a.attacker_die != c.attacker_die or a.defender_die != c.defender_die,
		"other-side packet does not reuse this fight's dice"
	)
