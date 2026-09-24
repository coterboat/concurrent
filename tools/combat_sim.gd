## Print invasion capture bands against bible 3.5. Exit 1 if a band moves.
extends SceneTree

const CombatScript := preload("res://engine/combat.gd")
const Bands := preload("res://tests/combat_bands.gd")


func _initialize() -> void:
	print("CONCURRENT combat_sim")
	print("invasion  size+1d6  ties -> attacker  n=%s  seed=%s" % [Bands.N, Bands.SEED])
	print("")
	print("%-8s %6s %6s %11s %-6s  %s" % ["matchup", "exact", "sim", "band", "gate", "note"])
	var failed := 0
	var wipes := 0
	for row in Bands.band_rows():
		var label: String = row[0]
		var att: int = row[1]
		var def: int = row[2]
		var lo: float = row[3]
		var hi: float = row[4]
		var note: String = row[5]
		var sim: Dictionary = Bands.simulate_invasion(att, def)
		var exact: float = sim["exact_pct"]
		var pct: float = sim["capture_pct"]
		var ok: bool = Bands.in_band(exact, lo, hi) and Bands.in_band(pct, lo, hi) and int(sim["double_wipes"]) == 0
		if not ok:
			failed += 1
		wipes += int(sim["double_wipes"])
		var word: String = CombatScript.odds_word(att, def)
		print(
			"%-8s %5.1f%% %5.1f%% %4.0f-%-4.0f  %-6s  %s  [%s]"
			% [label, exact, pct, lo, hi, "ok" if ok else "FAIL", note, word]
		)
	print("")
	print("1v1 double-wipes: %s" % wipes)
	print("odds are words, not a spreadsheet: long shot / toss-up / likely / lock")
	if failed == 0 and wipes == 0:
		print("G1 ok  bands hold")
		quit(0)
	else:
		print("G1 FAIL  %s band(s) moved" % failed)
		quit(1)
